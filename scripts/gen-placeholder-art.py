#!/usr/bin/env python3
"""Generate the RISC-V Combinator's placeholder art (ADR-0010 tracks real Blender art
as debt). Pure stdlib (zlib) -- no Pillow/ImageMagick dependency. Flat solid shapes at
32 px/tile so a data-stage sprite at scale 1 maps 1:1 to tiles. Re-run to regenerate:

    python3 scripts/gen-placeholder-art.py

Outputs (committed as the mod's shipped placeholders):
  graphics/entity/riscv-combinator-h.png  96x64  east/west body   (3 wide x 2 tall)
  graphics/entity/riscv-combinator-v.png  64x96  north/south body (2 wide x 3 tall)
  graphics/status/riscv-status.png        32x32  white status disc, tinted per Hart mode
"""
import os
import struct
import zlib

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

BODY = (43, 58, 82, 255)  # dark slate -- reads as "not a decider"
EDGE = (90, 110, 150, 255)  # lighter bezel
SCREEN = (55, 211, 192, 255)  # teal screen; slice-4 status overlay sits over it


def img(w, h, color=(0, 0, 0, 0)):
    return [[color for _ in range(w)] for _ in range(h)]


def rect(px, x0, y0, x1, y1, color):
    for y in range(y0, y1):
        for x in range(x0, x1):
            px[y][x] = color


def write_png(path, px):
    h, w = len(px), len(px[0])
    raw = bytearray()
    for row in px:
        raw.append(0)  # filter type 0 (none)
        for r, g, b, a in row:
            raw += bytes((r, g, b, a))

    def chunk(tag, data):
        return (
            struct.pack(">I", len(data))
            + tag
            + data
            + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)
        )

    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n")
        f.write(chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0)))
        f.write(chunk(b"IDAT", zlib.compress(bytes(raw), 9)))
        f.write(chunk(b"IEND", b""))


def body(w, h):
    px = img(w, h)
    rect(px, 2, 2, w - 2, h - 2, EDGE)  # bezel
    rect(px, 5, 5, w - 5, h - 5, BODY)  # body
    # screen inset near the top edge (where the status overlay lands)
    rect(px, 10, 8, w - 10, h // 2 - 2, SCREEN)
    return px


def status_glyph(n):
    # a filled white disc on transparent; the colour comes from the per-mode tint the
    # LuaRendering overlay applies at runtime (lib/overlay).
    px = img(n, n)
    c, r = (n - 1) / 2.0, n / 2.0 - 1
    for y in range(n):
        for x in range(n):
            if (x - c) ** 2 + (y - c) ** 2 <= r * r:
                px[y][x] = (255, 255, 255, 255)
    return px


def main():
    write_png(os.path.join(ROOT, "graphics/entity/riscv-combinator-h.png"), body(96, 64))
    write_png(os.path.join(ROOT, "graphics/entity/riscv-combinator-v.png"), body(64, 96))
    write_png(os.path.join(ROOT, "graphics/status/riscv-status.png"), status_glyph(32))
    print("wrote placeholder art under graphics/")


if __name__ == "__main__":
    main()
