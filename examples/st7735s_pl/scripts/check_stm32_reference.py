"""Execute unchanged STM32 C with a HAL recorder, then create a wire-stream oracle."""
from pathlib import Path
import subprocess
import sys

root = Path(__file__).resolve().parents[1]
ref = root / "reference/stm32_csdn_original"
build = root / "build/sim"
build.mkdir(parents=True, exist_ok=True)
gcc = sys.argv[1] if len(sys.argv) > 1 else r"E:\DevC++\Dev-Cpp\MinGW64\bin\gcc.exe"
exe = build / "emit_stm32.exe"
subprocess.run([gcc, "-std=c99", "-Wall", "-Wextra", "-Werror", "-I", str(ref),
                str(ref / "bsp_lcd.c"), str(ref / "emit_stm32.c"), "-o", str(exe)], check=True)
trace = subprocess.check_output([str(exe)], text=True)
(build / "stm32_c_trace.txt").write_text(trace, encoding="ascii")
lines = trace.splitlines()
words = [int(line.split()[1], 16) for line in lines if line.startswith("B ")]
assert len(words) == 77 + 11 + 32768
assert [int(s.split()[1]) for s in lines if s.startswith("D ")] == [100, 50, 50]
assert [s for s in lines if s.startswith("R ")] == ["R 0", "R 1"]
assert lines.index("L 1") > max(i for i,s in enumerate(lines) if s == "B 029")
assert words[9:19] == [0x0b3, 0x102, 0x135, 0x136, 0x102, 0x135, 0x136, 0x102, 0x135, 0x136]
assert words[77:88] == [0x02a, 0x100, 0x100, 0x100, 0x17f, 0x02b, 0x100, 0x120, 0x100, 0x19f, 0x02c]
assert words[88:] == [0x1f8, 0x100]*16384
(build / "stm32_wire_stream.hex").write_text("".join(f"{w:03x}\n" for w in words), encoding="ascii")
print("PASS: STM32 original: 77 init bytes, 100/50/50ms, SCK held high, 32779-byte red frame")
