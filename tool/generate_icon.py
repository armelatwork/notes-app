#!/usr/bin/env python3
"""
Generates assets/icon/app_icon.png — a 1024×1024 icon that matches the
login screen: yellow #FFD60A background with a white note_alt_outlined shape.
Uses only Python stdlib (struct + zlib); no third-party packages needed.
"""

import struct
import zlib
import os

SIZE = 1024
YEL = bytes([255, 214, 10])   # #FFD60A
WHT = bytes([255, 255, 255])

# Note body bounds (as fraction of SIZE)
NL   = int(SIZE * 0.155)   # left
NT   = int(SIZE * 0.095)   # top
NR   = int(SIZE * 0.845)   # right
NB   = int(SIZE * 0.905)   # bottom
FOLD = int(SIZE * 0.195)   # folded-corner size

# Text lines
LINE_L      = int(SIZE * 0.235)
LINE_H      = max(2, int(SIZE * 0.022))
LINE_GAP    = int(SIZE * 0.105)
FIRST_Y     = int(SIZE * 0.355)
LINE_RIGHTS = [int(SIZE * 0.765)] * 3 + [int(SIZE * 0.565)]


def set_span(row: bytearray, x1: int, x2: int, color: bytes) -> None:
    if x2 <= x1:
        return
    row[x1 * 3: x2 * 3] = color * (x2 - x1)


def make_rows():
    rows = []
    for y in range(SIZE):
        row = bytearray(YEL * SIZE)

        if NT <= y <= NB:
            # Right edge of white area for this row (fold cuts top-right corner)
            if y < NT + FOLD:
                wr = NR - FOLD + (y - NT)   # diagonal cut
            else:
                wr = NR

            set_span(row, NL, wr + 1, WHT)

            # Yellow text lines on the white body
            for i, lr in enumerate(LINE_RIGHTS):
                ly = FIRST_Y + i * LINE_GAP
                if ly <= y < ly + LINE_H:
                    set_span(row, LINE_L, min(lr, wr + 1), YEL)

        rows.append(bytes(row))
    return rows


def write_png(path: str, rows, width: int, height: int) -> None:
    def chunk(tag: bytes, data: bytes) -> bytes:
        payload = tag + data
        return (struct.pack('>I', len(data))
                + payload
                + struct.pack('>I', zlib.crc32(payload) & 0xFFFFFFFF))

    raw = bytearray()
    for row in rows:
        raw.append(0)   # filter: None
        raw.extend(row)

    sig  = b'\x89PNG\r\n\x1a\n'
    ihdr = chunk(b'IHDR', struct.pack('>IIBBBBB', width, height, 8, 2, 0, 0, 0))
    idat = chunk(b'IDAT', zlib.compress(bytes(raw), 9))
    iend = chunk(b'IEND', b'')

    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, 'wb') as f:
        f.write(sig + ihdr + idat + iend)
    print(f'Written {path}  ({os.path.getsize(path):,} bytes)')


if __name__ == '__main__':
    rows = make_rows()
    write_png('assets/icon/app_icon.png', rows, SIZE, SIZE)
