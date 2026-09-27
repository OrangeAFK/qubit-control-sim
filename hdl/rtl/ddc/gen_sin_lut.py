"""Generate quarter-wave sin LUT (Q1.14) for ddc.v — run from repo or this dir."""

from __future__ import annotations

import math
from pathlib import Path

SCALE = 16384
N = 1024
OUT = Path(__file__).resolve().parent / "sin_q14.vh"


def main() -> None:
    lines = [
        "// Auto-generated quarter-wave sin LUT, Q1.14",
        f"// S[i] = round(sin(i*pi/(2*{N}))*{SCALE}); i=0..{N}",
        "// Do not edit by hand — regenerate with gen_sin_lut.py.",
    ]
    for i in range(N + 1):
        v = int(round(math.sin(i * math.pi / (2 * N)) * SCALE))
        lines.append(f"  sin_lut[{i}] = 16'sd{v};")
    OUT.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"Wrote {N + 1} entries -> {OUT}")


if __name__ == "__main__":
    main()
