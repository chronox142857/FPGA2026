"""Capture physical loopback using the running ARM application's normal path.

Requires the matching exported ELF and SDK sources, JTAG, and documented wires.
Does not rebuild/program the FPGA, inject sampled data, or write persistent boot.
"""
from pathlib import Path
import argparse
import hashlib
import json
import os
import struct
import subprocess
from datetime import datetime, timedelta, timezone

ROOT = Path(__file__).resolve().parents[1]
LAYOUT_NAMES = """cfg_size cfg_divider cfg_trigger cfg_channel cfg_pre cfg_mask
cfg_level_mask cfg_level_value cfg_test cfg_spi cfg_repeat cfg_error cfg_decode
opt_size opt_mask opt_protocol opt_channels opt_spi opt_baud rec_size rec_samples
rec_count rec_hz rec_trigger rec_first rec_tick rec_mask result_size res_candidates
cand_size cand_rate cand_valid cand_errors dec_size dec_events dec_count dec_dropped
event_size event_data event_aux event_type event_flags ui_size ui_page cand_channels cand_mode""".split()


def check(condition, message):
    if not condition:
        raise RuntimeError(message)


def run(command, **kwargs):
    return subprocess.run([str(s) for s in command], check=True, **kwargs)


def words(path):
    return [int(s, 16) for s in path.read_text().split()]


def data_bytes(path):
    return b"".join(struct.pack("<I", w) for w in words(path))


def u32(data, offset):
    return struct.unpack_from("<I", data, offset)[0]


def u64(data, offset):
    return struct.unpack_from("<Q", data, offset)[0]


def prepare(args, out):
    sdk = Path(args.sdk)
    tools = sdk / "gnu/aarch32/nt/gcc-arm-none-eabi/bin"
    elf = ROOT / "build/export/analyzer.elf"
    include = ROOT / "firmware/include"
    if args.release_commit:
        # A saved release must not derive ABI offsets from experimental working
        # sources or a newer SDK build. Bind both executable and headers to Git.
        def blob(path):
            return run(["git", "show", f"{args.release_commit}:{path}"],
                       cwd=ROOT, capture_output=True).stdout
        release = args.release_directory.rstrip("/")+"/"
        check(elf.read_bytes() == blob(release+"analyzer.elf"), "ELF differs from requested Git release")
        check((ROOT / "build/export/system.bit").read_bytes() == blob(release+"system.bit"),
              "Bitstream differs from requested Git release")
        include = out / "release_include"
        include.mkdir()
        for name in ("la.h", "ui.h", "board_config.h"):
            (include / name).write_bytes(blob("firmware/include/"+name))
    else:
        for name in ("la.h", "ui.h", "board_config.h"):
            check((include / name).read_bytes() ==
                  (ROOT / "build/sdk/analyzer/src" / name).read_bytes(),
                  f"SDK header differs from current source: {name}; rebuild first")
        for name in ("main.c", "la.c", "ui.c", "tft.c"):
            check((ROOT / "firmware/src" / name).read_bytes() ==
                  (ROOT / "build/sdk/analyzer/src" / name).read_bytes(),
                  f"SDK source differs from current source: {name}; rebuild first")
    run([tools / "arm-none-eabi-gcc.exe", "-mcpu=cortex-a9", "-std=c99", "-c",
         "-I", include, ROOT / "tests/selftest_layout.c",
         "-o", out / "layout.o"], capture_output=True)
    run([tools / "arm-none-eabi-objcopy.exe", "-O", "binary", "-j", ".rodata",
         out / "layout.o", out / "layout.bin"], capture_output=True)
    raw = (out / "layout.bin").read_bytes()
    check(len(raw) == len(LAYOUT_NAMES)*4, "Unexpected ARM layout object")
    layout = dict(zip(LAYOUT_NAMES, struct.unpack("<"+"I"*len(LAYOUT_NAMES), raw)))
    check(layout["cfg_size"] % 4 == 0 and layout["rec_samples"] == 0, "Unexpected ABI")
    nm = run([tools / "arm-none-eabi-nm.exe", "-n", elf], capture_output=True, text=True).stdout
    run([tools / "arm-none-eabi-objcopy.exe", "--dump-section",
         f".text={out / 'expected_text.bin'}", elf, out / "firmware_copy.elf"], capture_output=True)
    text_size = (out / "expected_text.bin").stat().st_size
    check(text_size % 4 == 0, "Unaligned executable text size")
    required = "config awaiting record result decoded samples repeat_at last_paint ui screen_ok first_frame".split()
    symbols = {parts[2]: int(parts[0], 16) for line in nm.splitlines()
               if len(parts := line.split()) == 3 and parts[2] in required}
    check(len(symbols) == len(required), "Firmware symbols missing")
    config = bytearray(layout["cfg_size"])
    config[layout["cfg_divider"]] = 10
    config[layout["cfg_pre"]] = args.pre
    config[layout["cfg_mask"]] = 1 if args.protocol.startswith("uart") else 3 if args.protocol == "i2c" else 15
    config[layout["cfg_level_mask"]] = 1
    config[layout["cfg_test"]] = 1 if args.protocol.startswith("uart") else 2 if args.protocol == "i2c" else 3
    config[layout["cfg_spi"]] = args.mode
    config[layout["cfg_repeat"]] = 1
    config[layout["cfg_trigger"]] = 2 if args.protocol.startswith("uart") or args.protocol == "spi" else 0
    config[layout["cfg_channel"]] = 3 if args.protocol == "spi" else 0
    option = layout["cfg_decode"]
    config[option+layout["opt_mask"]] = config[layout["cfg_mask"]]
    config[option+layout["opt_channels"]:option+layout["opt_channels"]+4] = bytes(range(4))
    config[option+layout["opt_spi"]] = 255
    if args.protocol == "uart-error":
        config[layout["cfg_error"]] = 1
        config[option+layout["opt_protocol"]] = 1
        struct.pack_into("<I", config, option+layout["opt_baud"], 115200)
    if args.manual_spi:
        check(args.protocol == "spi", "--manual-spi requires --protocol spi")
        config[option+layout["opt_protocol"]] = 3
        config[option+layout["opt_spi"]] = args.mode
    repeat_offset = layout["cfg_repeat"]
    settings = [f"set out {{{out.as_posix()}}}", f"set text_words {text_size//4}"]
    settings += [f"set {name} 0x{value:08x}" for name, value in symbols.items()]
    settings += ["set config_words {"+" ".join(f"0x{w:08x}" for w in struct.unpack("<"+"I"*(len(config)//4), config))+"}",
                 f"set record_count 0x{symbols['record']+layout['rec_count']:08x}",
                 f"set repeat_word_address 0x{symbols['config']+(repeat_offset&~3):08x}",
                 f"set repeat_word_mask 0x{255<<((repeat_offset&3)*8):08x}",
                 f"set record_words {layout['rec_size']//4}",
                 f"set result_words {layout['result_size']//4}",
                 f"set decoded_words {layout['dec_size']//4}"]
    (out / "settings.tcl").write_text("\n".join(settings)+"\n", encoding="ascii")
    (out / "layout.json").write_text(json.dumps(layout, indent=2), encoding="ascii")
    return layout, symbols, hashlib.sha256(elf.read_bytes()).hexdigest()


def verify(args, out, layout, symbols, elf_hash):
    regs = words(out / "capture_registers.hex")
    record = data_bytes(out / "record.hex")
    result = data_bytes(out / "result.hex")
    decoded = data_bytes(out / "decoded.hex")
    samples = data_bytes(out / "arm_samples.hex")
    ram = data_bytes(out / "bram_samples.hex")
    check(regs[0] == 0x4c410101 and regs[2] == 3 and regs[10] == 32768, "Invalid capture state/count")
    check(u32(record, layout["rec_samples"]) == symbols["samples"], "Wrong ARM sample pointer")
    check(len(samples) == len(ram) == u32(record, layout["rec_count"]) == 32768, "Invalid sample length")
    start, trigger = regs[9], regs[11]
    check(samples == ram[start:]+ram[:start], "ARM readout differs from frozen physical BRAM")
    fs = u32(record, layout["rec_hz"])
    check(fs == 5000000 and regs[17] == 10, "Sample rate mismatch")
    check(trigger == args.pre*8192 == u32(record, layout["rec_trigger"]), "Pretrigger position mismatch")
    first, tick = u64(record, layout["rec_first"]), u64(record, layout["rec_tick"])
    check(first == regs[12]+(regs[13]<<32) and tick == regs[14]+(regs[15]<<32), "Timestamp readout mismatch")
    check(first+trigger*10 == tick, "Timestamp/sample-index relationship failed")
    if args.protocol.startswith("uart"):
        check(samples[trigger] == 0 and (trigger == 0 or samples[trigger-1] == 1), "Falling-edge trigger mismatch")
    check(not any(v & ~regs[16] for v in samples), "Disabled channel contains data")
    proto = 1 if args.protocol.startswith("uart") else 2 if args.protocol == "i2c" else 3
    check(result[1] > 0 and result[layout["res_candidates"]] == proto and decoded[0] == proto,
          "ARM did not select the expected protocol")
    statuses = {3} if args.protocol == "uart-error" or args.manual_spi else {2} if proto == 3 else {1, 2} if proto == 2 else {1}
    check(result[0] in statuses, "Unexpected identification status")
    if proto == 3:
        candidates = [result[layout["res_candidates"]+i*layout["cand_size"]:
                             layout["res_candidates"]+(i+1)*layout["cand_size"]] for i in range(result[1])]
        check(any(c[0] == 3 and c[layout["cand_mode"]] == args.mode and
                  c[layout["cand_channels"]:layout["cand_channels"]+4] == bytes(range(4)) for c in candidates),
              "SPI candidates omit the known physical roles/mode")
    valid, errors = u32(decoded, layout["cand_valid"]), u32(decoded, layout["cand_errors"])
    rate = u32(decoded, layout["cand_rate"])
    check(valid > 5, "Too few complete decoded bytes")
    check(abs(rate-(115200 if proto == 1 else 100000)) < (2304 if proto == 1 else 2000), "Estimated rate mismatch")
    events, data = [], []
    for i in range(u32(decoded, layout["dec_count"])):
        base = layout["dec_events"]+i*layout["event_size"]
        event = decoded[base:base+layout["event_size"]]
        position, end = struct.unpack_from("<II", event)
        value = struct.unpack_from("<H", event, layout["event_data"])[0]
        aux = struct.unpack_from("<H", event, layout["event_aux"])[0]
        kind, flags = event[layout["event_type"]], event[layout["event_flags"]]
        check(position <= end < len(samples), "Event outside capture")
        events.append(dict(sample=position, end=end, data=value, aux=aux, type=kind, flags=flags))
        if kind != 0 or flags & 2:
            continue
        if proto == 1:
            # Independently inspect bit centres using the known source timing,
            # not the firmware's decoder or its estimated baud rate.
            period = 434/10
            check(samples[round(position+period/2)] == 0, "UART start bit mismatch")
            measured = sum((samples[round(position+(b+1.5)*period)] & 1) << b for b in range(8))
            stop = samples[round(position+9.5*period)] & 1
            check(measured == value and bool(flags & 1) == (not stop), "UART bit/data/error mismatch")
            data.append(value)
        elif proto == 2:
            if flags & 8:
                check(value == 0xa0, "I2C address mismatch")
            check(not(flags & 4), "Unexpected NACK from selftest source")
        else:
            check((value ^ aux) == 255, "SPI MOSI/MISO complement mismatch")
    if proto == 1:
        check(len(data) > 5 and all(((b-a)&255) == 0x13 for a, b in zip(data, data[1:])), "UART known sequence mismatch")
        check(errors > 0 if args.protocol == "uart-error" else errors == 0, "UART frame-error count mismatch")
    spi_oracle = []
    if proto == 3:
        # The source transmits two equal bytes per CS interval; each subsequent
        # transaction increments by 0x13. Inspect the physical lines using the
        # known source mode, independently of the ARM's preferred candidate.
        packet, bits, tx, rx, active = [], 0, 0, 0, False
        previous_packet = None
        sample_level = 1 if (args.mode >> 1) == (args.mode & 1) else 0
        first_bit = 0
        for i in range(1, len(samples)):
            cs, pcs = (samples[i] >> 3) & 1, (samples[i-1] >> 3) & 1
            clock, previous_clock = samples[i] & 1, samples[i-1] & 1
            if pcs and not cs:
                packet, bits, tx, rx, active = [], 0, 0, 0, True
            if active and not cs and clock != previous_clock and clock == sample_level:
                if not bits:
                    first_bit = i
                tx = (tx << 1) | ((samples[i] >> 1) & 1)
                rx = (rx << 1) | ((samples[i] >> 2) & 1)
                bits += 1
                if bits == 8:
                    packet.append((first_bit, i, tx, rx))
                    tx, rx, bits = 0, 0, 0
            if active and not pcs and cs:
                check(bits == 0 and len(packet) == 2, "SPI transaction length mismatch")
                check(packet[0][2] == packet[1][2] and all((v[2] ^ v[3]) == 255 for v in packet),
                      "SPI source data mismatch")
                check(previous_packet is None or ((packet[0][2]-previous_packet)&255) == 0x13,
                      "SPI known transaction sequence mismatch")
                previous_packet = packet[0][2]
                spi_oracle.extend(packet)
                active = False
        check(len(spi_oracle) > 10, "Too few complete SPI transactions")
        if args.manual_spi:
            actual = [(e["sample"], e["end"], e["data"], e["aux"]) for e in events if e["type"] == 0 and not e["flags"]]
            # An incomplete final CS interval may contain a complete byte that
            # the oracle intentionally excludes; compare only closed packets.
            check(actual[:len(spi_oracle)] == spi_oracle, "ARM SPI bytes/timestamps differ from physical-line oracle")
    (out / "samples.hex").write_text("".join(f"{b:02x}\n" for b in samples), encoding="ascii")
    report = dict(protocol=args.protocol, mode=args.mode, manual_spi=args.manual_spi,
                  spi_oracle=spi_oracle, pretrigger=args.pre*25, firmware_sha256=elf_hash,
                  samples=len(samples), sample_hz=fs, start_index=start, trigger_index=trigger,
                  first_tick=first, trigger_tick=tick, identification_status=result[0], candidates=result[1],
                  rate=rate, valid_bytes=valid, errors=errors, decoded_events=events,
                  arm_equals_bram=True, uart_sequence=data,
                  bitstream_sha256=hashlib.sha256((ROOT / "build/export/system.bit").read_bytes()).hexdigest(),
                  scope="physical FPGA pin loopback; same source/sample clock; not independent-device or maximum-speed validation")
    (out / "report.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
    print(f"PASS PHYSICAL {args.protocol}: {len(samples)} samples; ARM==BRAM; trigger={trigger}; rate={rate}; valid={valid}; errors={errors}; status={result[0]}", flush=True)
    if data:
        print("UART bytes:", " ".join(f"{b:02X}" for b in data[:24]))
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--protocol", choices=("uart", "uart-error", "i2c", "spi"), default="uart")
    parser.add_argument("--mode", type=int, choices=range(4), default=0)
    parser.add_argument("--pre", type=int, choices=range(4), default=1)
    parser.add_argument("--sdk", default=r"E:\fpga\SDK\2018.2")
    parser.add_argument("--release-commit", help="Use executable and ABI headers from this published Git revision")
    parser.add_argument("--release-directory", default="releases/analyzer-st7735s-integrated-20261031",
                        help="Git-relative artifact directory used with --release-commit")
    parser.add_argument("--count", type=int, default=1, help="Number of separately verified physical acquisitions")
    parser.add_argument("--cycle-pre", action="store_true", help="Cycle through 0/25/50/75 percent pretrigger")
    parser.add_argument("--manual-spi", action="store_true", help="Verify the known SPI mode/roles separately from AUTO ambiguity")
    args = parser.parse_args()
    check(1 <= args.count <= 1000, "Count must be 1..1000")
    stamp = datetime.now(timezone(timedelta(hours=8))).strftime("%Y%m%d_%H%M%S_%f")
    batch = ROOT / "build/hardware_selftest" / (stamp+"_"+args.protocol+str(args.mode))
    batch.mkdir(parents=True, exist_ok=False)
    reports = []
    for index in range(args.count):
        out = batch if args.count == 1 else batch / f"capture_{index+1:03d}"
        out.mkdir(parents=True, exist_ok=True)
        if args.cycle_pre:
            args.pre = index % 4
        try:
            layout, symbols, elf_hash = prepare(args, out)
            env = dict(os.environ, PROCESSOR_ARCHITECTURE="AMD64")
            with (out / "jtag.log").open("w", encoding="utf-8") as handle:
                outcome = subprocess.run([str(Path(args.sdk)/"bin/xsct.bat"), str(ROOT/"scripts/selftest_jtag.tcl"),
                                          str(out/"settings.tcl")], stdout=handle, stderr=subprocess.STDOUT,
                                         env=env, timeout=120)
            log = (out / "jtag.log").read_text(encoding="utf-8", errors="replace")
            check(outcome.returncode == 0 and "PHYSICAL_CAPTURE_EXPORTED_CPU_RESUMED" in log, "JTAG capture failed:\n"+log[-5000:])
            report = verify(args, out, layout, symbols, elf_hash)
            if reports:
                check(report["trigger_tick"] > reports[-1]["trigger_tick"], "Trigger timestamp did not advance; stale record")
            reports.append(report)
            print(f"Verified acquisition {index+1}/{args.count}; evidence: {out}", flush=True)
        except Exception as error:
            (out / "failure.json").write_text(json.dumps(dict(error=str(error), acquisition=index+1), indent=2), encoding="utf-8")
            raise
        finally:
            (batch / "batch_summary.json").write_text(json.dumps(dict(requested=args.count, passed=len(reports),
                timestamp_timezone="Asia/Shanghai", protocol=args.protocol,
                records=[{key:value for key,value in r.items() if key not in ("decoded_events", "uart_sequence")} for r in reports]), indent=2), encoding="utf-8")
    print("Evidence:", batch, flush=True)


if __name__ == "__main__":
    main()
