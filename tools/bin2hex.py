#!/usr/bin/env python3
"""Convert a raw binary program into a $readmemh file of 32-bit words.

Usage:  python bin2hex.py <in.bin> <out.hex> <words>

The CPU's RAM is 32 bits wide and RISC-V is little-endian: the byte at the
lowest address is the least significant byte of the word. So bytes
  13 05 a0 00   become the word   00a00513
The output is padded with zeros to <words> lines (the RAM depth).
"""

import sys


def main():
    if len(sys.argv) != 4:
        sys.exit(__doc__)
    data = open(sys.argv[1], "rb").read()
    depth = int(sys.argv[3])
    data += b"\0" * (-len(data) % 4)            # pad to a whole word
    words = len(data) // 4
    if words > depth:
        sys.exit(f"program is {words} words, RAM has only {depth}")
    with open(sys.argv[2], "w", newline="\n") as f:
        for i in range(depth):
            w = int.from_bytes(data[4 * i:4 * i + 4], "little") if i < words else 0
            f.write(f"{w:08x}\n")
    print(f"{sys.argv[2]}: {words} of {depth} words used ({100 * words // depth}%)")


if __name__ == "__main__":
    main()
