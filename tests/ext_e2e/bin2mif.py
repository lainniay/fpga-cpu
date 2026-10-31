#!/usr/bin/env python3
import sys
from pathlib import Path

src, dst = Path(sys.argv[1]), Path(sys.argv[2])
data = src.read_bytes()
data += b"\x00" * ((4 - len(data) % 4) % 4)
with dst.open("w") as f:
    for i in range(0, len(data), 4):
        f.write(f"{int.from_bytes(data[i:i + 4], 'little'):032b}\n")
