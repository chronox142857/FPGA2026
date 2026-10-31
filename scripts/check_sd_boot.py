"""Read-only verification after the user cold-boots from the prepared SD card."""
from pathlib import Path
from datetime import datetime
import os
import re
import subprocess

ROOT = Path(__file__).resolve().parents[1]
SDK = Path(r"E:\fpga\SDK\2018.2")


def main():
    out = ROOT / "build/sd_boot/cold_check" / datetime.now().strftime("%Y%m%d_%H%M%S_%f")
    out.mkdir(parents=True, exist_ok=True)
    elf = ROOT / "build/sd_boot/analyzer.elf"
    binary_tools = SDK / "gnu/aarch32/nt/gcc-arm-none-eabi/bin"
    subprocess.run([str(binary_tools / "arm-none-eabi-objcopy.exe"), "--dump-section",
                    f".text={out / 'expected_text.bin'}", str(elf), str(out / "copy.elf")], check=True)
    nm = subprocess.run([str(binary_tools / "arm-none-eabi-nm.exe"), "-n", str(elf)],
                        capture_output=True, text=True, check=True).stdout
    symbols = dict((name, int(address, 16)) for address, name in
                   re.findall(r"^([0-9a-fA-F]+) [bBdD] (screen_ok|last_paint)$", nm, re.M))
    if len(symbols) != 2:
        raise RuntimeError("Missing status symbols")
    settings = [f"set out {{{out.as_posix()}}}",
                f"set text_words {(out / 'expected_text.bin').stat().st_size//4}"]
    settings.extend(f"set {name} 0x{value:08x}" for name, value in symbols.items())
    (out / "settings.tcl").write_bytes(("\n".join(settings)+"\n").encode("ascii"))
    with (out / "status.log").open("w", encoding="utf-8") as log:
        result = subprocess.run([str(SDK / "bin/xsct.bat"), str(ROOT / "scripts/check_sd_boot.tcl"),
                                 str(out / "settings.tcl")], stdout=log, stderr=subprocess.STDOUT,
                                env=dict(os.environ, PROCESSOR_ARCHITECTURE="AMD64"), timeout=45)
    text = (out / "status.log").read_text(encoding="utf-8", errors="replace")
    print(text)
    if result.returncode or "SD_AUTONOMOUS_BOOT_VERIFIED_WITHOUT_TARGET_WRITES" not in text:
        raise RuntimeError("Read-only SD cold-boot check did not pass; no download attempted")


if __name__ == "__main__":
    main()
