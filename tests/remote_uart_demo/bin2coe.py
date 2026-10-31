#!/usr/bin/env python3
import sys
from pathlib import Path

src, mif_path, coe_path = map(Path, sys.argv[1:4])
data = src.read_bytes()
data += b"\x00" * ((4 - len(data) % 4) % 4)
words = [int.from_bytes(data[i:i + 4], "little") for i in range(0, len(data), 4)]

with mif_path.open("w") as f:
    for word in words:
        f.write(f"{word:032b}\n")

with coe_path.open("w") as f:
    f.write("memory_initialization_radix=16;\n")
    f.write("memory_initialization_vector=\n")
    f.write(",\n".join(f"{word:08x}" for word in words))
    f.write(";\n")
