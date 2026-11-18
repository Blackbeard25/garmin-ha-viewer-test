#!/usr/bin/env python3
"""Create resources/drawables/launcher_icon.png (40x40 white house, transparent).

Pure standard library - no Pillow needed. Run once before the first build:
    python3 tools/make_icon.py
"""
import os, struct, zlib

S = 40

def inside(x, y):
    # roof: triangle (20,5) (35,18) (5,18)
    if 5 <= y <= 18:
        half = (y - 5) * 15 / 13
        if abs(x - 20) <= half:
            return True
    # walls with a door cut out
    if 9 <= x <= 31 and 18 <= y <= 35:
        return not (17 <= x <= 23 and 25 <= y <= 35)
    return False

rows = b"".join(
    b"\x00" + b"".join(b"\xff\xff\xff\xff" if inside(x, y) else b"\x00\x00\x00\x00" for x in range(S))
    for y in range(S))

def chunk(t, d):
    return struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d) & 0xffffffff)

png = (b"\x89PNG\r\n\x1a\n"
       + chunk(b"IHDR", struct.pack(">IIBBBBB", S, S, 8, 6, 0, 0, 0))
       + chunk(b"IDAT", zlib.compress(rows, 9))
       + chunk(b"IEND", b""))

out = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "resources", "drawables", "launcher_icon.png")
with open(out, "wb") as f:
    f.write(png)
print("wrote", os.path.normpath(out))
