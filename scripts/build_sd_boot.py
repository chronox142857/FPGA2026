"""Package the verified OCM application for ZYNQ7010 SD boot; never writes media.

The supplied 7010 vendor FSBL configures the board DDR/SD. A tiny DDR trampoline
then copies the unchanged released application to OCM after FSBL has finished.
Do not substitute a 7020 FSBL or a generic board preset.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import struct
import subprocess

ROOT = Path(__file__).resolve().parents[1]
VENDOR_SHA = "e69bc124d76f6eeecaebd1ff6a5fb354576f41937571d61b0c6458762a8eb569"


def run(command, **kwargs):
    return subprocess.run([str(x) for x in command], check=True, **kwargs)


def restore_vendor_handoff(path):
    """Restore the missing application handoff in this exact PL-only FSBL.

    Board-specific initialization stays unchanged. Never patch another vendor
    revision: the input SHA and both instruction sites must match first.
    """
    original = path.read_bytes()
    if hashlib.sha256(original).hexdigest() != VENDOR_SHA:
        raise RuntimeError("Refusing to patch an unknown vendor FSBL")
    if original[:7] != b"\x7fELF\x01\x01\x01":
        raise RuntimeError("Expected ELF32 little-endian FSBL")
    phoff = struct.unpack_from("<I", original, 28)[0]
    phsize, phcount = struct.unpack_from("<HH", original, 42)

    def file_offset(address):
        matches = []
        for index in range(phcount):
            kind, offset, vaddr, _, size, _, _, _ = struct.unpack_from(
                "<8I", original, phoff + index * phsize)
            if kind == 1 and vaddr <= address and address + 4 <= vaddr + size:
                matches.append(offset + address - vaddr)
        if len(matches) != 1:
            raise RuntimeError("FSBL instruction is not in exactly one file-backed LOAD segment")
        return matches[0]

    site, target = 0xE6E4, 0x1380
    offset = file_offset(site)
    if struct.unpack_from("<II", original, offset - 4) != (0xEBFFC8FF, 0xEAFFFFFE):
        raise RuntimeError("Expected LoadBootImage call followed by the vendor wait loop")
    if struct.unpack_from("<I", original, file_offset(target))[0] != 0xE3093EB4:
        raise RuntimeError("FsblHandoff entry does not match the audited vendor ELF")
    displacement = target - (site + 8)
    if displacement % 4 or not -(1 << 25) <= displacement < (1 << 25):
        raise RuntimeError("ARM branch target is out of range or unaligned")
    instruction = 0xEA000000 | ((displacement // 4) & 0xFFFFFF)
    patched = bytearray(original)
    struct.pack_into("<I", patched, offset, instruction)
    if patched[:offset] != original[:offset] or patched[offset + 4:] != original[offset + 4:]:
        raise RuntimeError("Unexpected changes outside the handoff instruction")
    path.write_bytes(patched)
    return dict(address=hex(site), before="0xeafffffe", after=f"0x{instruction:08x}",
                target="FsblHandoff at 0x00001380", file_offset=offset,
                reason="Vendor PL-only main waited after LoadBootImage instead of handing off")


def verify_image(out):
    """Check actual Bootgen output; SDK 2018.2 can return zero on errors."""
    image = (out / "BOOT.bin").read_bytes()
    word = lambda offset: struct.unpack_from("<I", image, offset)[0]
    if word(0x20) != 0xAA995566 or word(0x24) != 0x584C4E58:
        raise RuntimeError("Invalid Zynq boot header")
    partitions = []
    for index in range(3):
        header = struct.unpack_from("<16I", image, word(0x9C) + index * 64)
        if sum(header) & 0xFFFFFFFF != 0xFFFFFFFF:
            raise RuntimeError("Invalid partition header checksum")
        offset, length = header[5] * 4, header[0] * 4
        data = image[offset:offset + length]
        if len(data) != length:
            raise RuntimeError("Truncated boot partition")
        partitions.append((header, data))
    if partitions[0][1] != (out / "fsbl_flat.bin").read_bytes():
        raise RuntimeError("BOOT.bin FSBL payload differs from the corrected FSBL")
    # Parse .bit metadata instead of relying on a fixed header length.
    bit = (out / "system.bit").read_bytes()
    pos = 2 + struct.unpack_from(">H", bit, 0)[0]
    if bit[pos:pos + 3] != b"\x00\x01a":
        raise RuntimeError("Unexpected bitstream metadata")
    pos += 2
    for tag in b"abcd":
        if bit[pos] != tag:
            raise RuntimeError("Unexpected bitstream metadata tag")
        pos += 3 + struct.unpack_from(">H", bit, pos + 1)[0]
    if bit[pos] != ord("e"):
        raise RuntimeError("Missing bitstream data tag")
    length = struct.unpack_from(">I", bit, pos + 1)[0]
    raw = bit[pos + 5:]
    if len(raw) != length or length % 4:
        raise RuntimeError("Invalid bitstream length")
    swapped = b"".join(raw[i:i + 4][::-1] for i in range(0, length, 4))
    if partitions[1][1][:length] != swapped or partitions[1][0][6] != 0x20:
        raise RuntimeError("BOOT.bin FPGA payload differs from released bitstream")
    loader = (out / "loader_flat.bin").read_bytes()
    if partitions[2][1] != loader or partitions[2][0][3:5] != (0x200000, 0x200000):
        raise RuntimeError("BOOT.bin loader payload/address mismatch")
    if not loader.endswith((out / "analyzer.bin").read_bytes()):
        raise RuntimeError("Loader does not contain the unchanged analyzer image")
    return "header checksums, corrected FSBL, FPGA payload and OCM loader payload verified"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--sdk", default=r"E:\fpga\SDK\2018.2")
    parser.add_argument("--fsbl", default=r"E:\FPGAproject\ZYNQ_7010_FPGA\ZYNQ_7010_FPGA\11_key_led\zynq纯PL端固化脚本\zynq_fsbl.elf")
    args = parser.parse_args()
    out = ROOT / "build/sd_boot"
    out.mkdir(parents=True, exist_ok=True)
    release = ROOT / "releases/analyzer-selftest-20261031"
    for line in (release / "SHA256SUMS.txt").read_text().splitlines():
        expected, name = line.split("  ", 1)
        if hashlib.sha256((release / name).read_bytes()).hexdigest() != expected:
            raise RuntimeError(f"Release checksum mismatch: {name}")
    fsbl = Path(args.fsbl)
    if hashlib.sha256(fsbl.read_bytes()).hexdigest() != VENDOR_SHA:
        raise RuntimeError("FSBL differs from the documented local 7010 reference")
    for source, name in [(release / "system.bit", "system.bit"),
                         (release / "analyzer.elf", "analyzer.elf"), (fsbl, "fsbl_7010.elf")]:
        shutil.copy2(source, out / name)
    handoff_patch = restore_vendor_handoff(out / "fsbl_7010.elf")
    binary_tools = Path(args.sdk) / "gnu/aarch32/nt/gcc-arm-none-eabi/bin"
    run([binary_tools / "arm-none-eabi-objcopy.exe", "-O", "binary",
         "fsbl_7010.elf", "fsbl_flat.bin"], cwd=out)
    run([binary_tools / "arm-none-eabi-objcopy.exe", "-O", "binary", "analyzer.elf", "analyzer.bin"], cwd=out)
    payload = (out / "analyzer.bin").read_bytes()
    if not 0 < len(payload) <= 0x30000 or len(payload) % 4:
        raise RuntimeError("Unexpected OCM image span/alignment")
    # Ensure the payload begins at the vector table's OCM address zero.
    elf = (out / "analyzer.elf").read_bytes()
    if struct.unpack_from("<I", elf, 24)[0] != 0:
        raise RuntimeError("Analyzer reset entry is not zero")
    run([binary_tools / "arm-none-eabi-objcopy.exe", "-I", "binary", "-O", "elf32-littlearm",
         "-B", "arm", "analyzer.bin", "payload.o"], cwd=out)
    run([binary_tools / "arm-none-eabi-gcc.exe", "-mcpu=cortex-a9", "-marm", "-c",
         ROOT / "boot/sd/ocm_loader.S", "-o", "loader.o"], cwd=out)
    run([binary_tools / "arm-none-eabi-ld.exe", "-T", ROOT / "boot/sd/loader.ld",
         "-Map=loader.map", "loader.o", "payload.o", "-o", "ocm_loader.elf"], cwd=out)
    run([binary_tools / "arm-none-eabi-objcopy.exe", "-O", "binary",
         "ocm_loader.elf", "loader_flat.bin"], cwd=out)
    # Absolute ASCII paths avoid SDK 2018.2's handling of Chinese input paths.
    bif = "the_ROM_image:\n{\n [bootloader] fsbl_7010.elf\n system.bit\n ocm_loader.elf\n}\n"
    (out / "boot.bif").write_bytes(bif.encode("ascii"))
    env = dict(os.environ, PROCESSOR_ARCHITECTURE="AMD64")
    run([Path(args.sdk) / "bin/bootgen.bat", "-arch", "zynq", "-image", "boot.bif",
         "-o", "BOOT.bin", "-w", "on"], cwd=out, env=env)
    verification = verify_image(out)
    info = dict(status="built; cold boot not yet verified", device="xc7z010clg400-1",
                static_verification=verification,
                fsbl_handoff_patch=handoff_patch,
                vendor_fsbl_source=str(fsbl), vendor_fsbl_sha256=VENDOR_SHA,
                analyzer_release="analyzer-selftest-20261031", payload_bytes=len(payload),
                trampoline_ddr_address="0x00200000", analyzer_ocm_entry="0x00000000",
                files={name: hashlib.sha256((out / name).read_bytes()).hexdigest()
                       for name in ("fsbl_7010.elf", "system.bit", "analyzer.elf", "ocm_loader.elf", "BOOT.bin")})
    (out / "manifest.json").write_text(json.dumps(info, indent=2, ensure_ascii=False), encoding="utf-8")
    print("SD_BOOT_IMAGE_BUILT", out / "BOOT.bin")
    print("No removable media or Flash was written. Actual cold boot is still required.")


if __name__ == "__main__":
    main()
