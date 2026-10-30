"""Compare the executable archived C initializer against the RTL test oracle."""
from pathlib import Path
import subprocess
import sys

root = Path(__file__).resolve().parents[1]
ref = root / "reference/slow_gpio_0044"
build = root / "build/sim"
build.mkdir(parents=True, exist_ok=True)
exe = build / "emit_slow_init.exe"
gcc = sys.argv[1] if len(sys.argv) > 1 else r"E:\DevC++\Dev-Cpp\MinGW64\bin\gcc.exe"
subprocess.run([gcc, "-std=c99", "-Wall", "-Wextra", "-Werror", "-I", str(ref),
                str(ref / "tft.c"), str(ref / "emit_init.c"), "-o", str(exe)], check=True)
trace = subprocess.check_output([str(exe)], text=True)
(build / "slow_c_trace.txt").write_text(trace, encoding="ascii")
words = [int(line.split()[1], 16) for line in trace.splitlines() if line.startswith("B ")]
golden = [int(line, 16) for line in (root / "reference/slow_gpio_init.hex").read_text().splitlines()
          if line and not line.startswith("//")]
assert words == golden, "Archived C and RTL reference initialization differ"
packets = [int(line.split()[1]) for line in trace.splitlines() if line.startswith("P ")]
expected_packets = []
for word in words:
    if word < 256:
        expected_packets.append(1)
    elif len(expected_packets) == 0 or words[sum(expected_packets)-1] < 256:
        expected_packets.append(1)
    else:
        expected_packets[-1] += 1
assert packets == expected_packets and len(packets) == 34
delays = [int(line.split()[1]) for line in trace.splitlines() if line.startswith("D ")]
assert delays == [100000, 100000, 100000, 100000, 120000, 20000]
print("PASS: archived C matches all 78 initialization bytes, 34 CS packets and six delays")
