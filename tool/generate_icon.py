#!/usr/bin/env python3
"""
Generates assets/icon/app_icon.png — 1024×1024 clipboard+pencil icon.
Light background, yellow #FFD60A clipboard and pencil — matches the login screen.
Pure Python stdlib. Row-span rendering for speed.
"""

import struct, zlib, os, math

S   = 1024
BG  = bytes([255, 252, 220])  # very light yellow background
IC  = bytes([255, 214,  10])  # #FFD60A — icon colour (clipboard + pencil)
DIC = bytes([220, 180,   0])  # slightly darker yellow for pencil tip shading


def fill(row, x1, x2, color):
    x1, x2 = max(0, int(x1)), min(S, int(x2))
    if x2 > x1:
        row[x1*3 : x2*3] = color * (x2 - x1)


def rrect_xspan(y, y1, y2, x1, x2, r):
    """Horizontal span of a rounded-rect at row y. Returns (lx, rx) or None."""
    if y < y1 or y > y2:
        return None
    if y < y1 + r:
        dy = (y1 + r) - y
        dx = math.sqrt(max(0.0, r*r - dy*dy))
        return (x1 + r - dx, x2 - r + dx + 1)
    if y > y2 - r:
        dy = y - (y2 - r)
        dx = math.sqrt(max(0.0, r*r - dy*dy))
        return (x1 + r - dx, x2 - r + dx + 1)
    return (x1, x2 + 1)


def make_rows():
    # ── Clipboard body ─────────────────────────────────────────────────────────
    cb = (int(S*.200), int(S*.215), int(S*.800), int(S*.870), int(S*.060))

    # ── Clip tab (rounded rect at top centre, overlapping body) ───────────────
    ctw = int(S*.175)
    ct  = (S//2 - ctw//2, int(S*.128), S//2 + ctw//2, int(S*.238), int(S*.038))

    # ── Clip hole (punches through tab back to BG) ─────────────────────────────
    chw = int(S*.080)
    ch  = (S//2 - chw//2, int(S*.155), S//2 + chw//2, int(S*.212), int(S*.020))

    # ── Pencil (upright, centred) ─────────────────────────────────────────────
    cx     = S // 2
    pw     = int(S * .100)           # pencil width
    pb_x1  = cx - pw // 2
    pb_x2  = cx + pw // 2
    er_t   = int(S * .385)           # eraser band top
    er_b   = int(S * .412)           # eraser band bottom
    body_t = er_b                    # body starts after eraser
    body_b = int(S * .715)           # body ends
    tip_b  = int(S * .800)           # tip point

    rows = []
    for y in range(S):
        row = bytearray(BG * S)      # start: light background

        # Clipboard body
        sp = rrect_xspan(y, cb[1], cb[3], cb[0], cb[2], cb[4])
        if sp:
            fill(row, sp[0], sp[1], IC)

        # Clip tab
        sp = rrect_xspan(y, ct[1], ct[3], ct[0], ct[2], ct[4])
        if sp:
            fill(row, sp[0], sp[1], IC)

        # Clip hole
        sp = rrect_xspan(y, ch[1], ch[3], ch[0], ch[2], ch[4])
        if sp:
            fill(row, sp[0], sp[1], BG)

        # Pencil eraser band (light background colour — contrast stripe)
        if er_t <= y < er_b:
            fill(row, pb_x1 - int(S*.010), pb_x2 + int(S*.010), BG)

        # Pencil body (slightly darker yellow so it reads against the clipboard)
        elif body_t <= y <= body_b:
            fill(row, pb_x1, pb_x2, DIC)
            # Light ferrule stripe at top of body
            if y < body_t + int(S * .025):
                fill(row, pb_x1, pb_x2, BG)

        # Pencil tip (triangle, narrowing to a point)
        elif body_b < y <= tip_b:
            progress = (y - body_b) / (tip_b - body_b)
            hw = pw / 2 * (1.0 - progress)
            fill(row, cx - hw, cx + hw, DIC)

        rows.append(bytes(row))
    return rows


def write_png(path, rows):
    def chunk(tag, data):
        c = tag + data
        return struct.pack('>I', len(data)) + c + struct.pack('>I', zlib.crc32(c) & 0xFFFFFFFF)
    raw = bytearray()
    for row in rows:
        raw.append(0)
        raw.extend(row)
    os.makedirs(os.path.dirname(path) or '.', exist_ok=True)
    with open(path, 'wb') as f:
        f.write(b'\x89PNG\r\n\x1a\n')
        f.write(chunk(b'IHDR', struct.pack('>IIBBBBB', S, S, 8, 2, 0, 0, 0)))
        f.write(chunk(b'IDAT', zlib.compress(bytes(raw), 9)))
        f.write(chunk(b'IEND', b''))
    print(f'Written {path}  ({os.path.getsize(path):,} bytes)')


if __name__ == '__main__':
    write_png('assets/icon/app_icon.png', make_rows())
