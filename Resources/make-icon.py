#!/usr/bin/env python3
"""Generates Teslaris.icns. Pure stdlib — no PIL, no ImageMagick.

The icon follows the same family language as Polaris (dark squircle,
off-white glyph, accent dot on a faint ring) but with its own mark:
a lightning bolt with slightly concave edges, and a red accent.

    python3 Resources/make-icon.py   # rewrites Resources/Teslaris.icns
"""

import math
import os
import struct
import zlib

SIZE = 1024
CENTER = SIZE / 2

BG_TOP = (30, 30, 33)
BG_BOTTOM = (13, 13, 15)
BOLT = (245, 242, 234)
RING = (255, 255, 255)
RING_ALPHA = 0.09
DOT = (232, 33, 39)          # accent red (not Tesla's trademark T)

RING_R = 302.0
RING_STROKE = 3.5
DOT_R = 34.0
DOT_ANGLE = math.radians(45)  # lower-right, sitting on the ring


# --- geometry ------------------------------------------------------------

def quad(p0, c, p1, steps=48):
    """Flattened quadratic Bézier, excluding the start point."""
    pts = []
    for i in range(1, steps + 1):
        t = i / steps
        u = 1 - t
        pts.append((u * u * p0[0] + 2 * u * t * c[0] + t * t * p1[0],
                    u * u * p0[1] + 2 * u * t * c[1] + t * t * p1[1]))
    return pts


def bowed(p0, p1, bow):
    """Edge from p0 to p1 bowed sideways: positive bows left of travel."""
    mx, my = (p0[0] + p1[0]) / 2, (p0[1] + p1[1]) / 2
    dx, dy = p1[0] - p0[0], p1[1] - p0[1]
    length = math.hypot(dx, dy) or 1.0
    return quad(p0, (mx + bow * dy / length, my - bow * dx / length), p1)


def circle(cx, cy, r, n=256):
    return [(cx + r * math.cos(2 * math.pi * i / n),
             cy + r * math.sin(2 * math.pi * i / n)) for i in range(n)]


def squircle(cx, cy, half, exponent=5.0, n=1024):
    """Superellipse — close enough to the macOS icon squircle."""
    pts = []
    for i in range(n):
        t = 2 * math.pi * i / n
        c, s = math.cos(t), math.sin(t)
        pts.append((cx + half * math.copysign(abs(c) ** (2 / exponent), c),
                    cy + half * math.copysign(abs(s) ** (2 / exponent), s)))
    return pts


def bolt_polygon():
    """Lightning bolt with gently concave long edges (echoes the Polaris
    star's swashes). Points in 1024-space."""
    a = (615, 235)   # top tip
    b = (438, 580)   # left shoulder
    c = (506, 580)   # notch, stepping right
    d = (420, 795)   # bottom tip
    e = (612, 452)   # right shoulder
    f = (528, 470)   # notch, stepping left
    poly = [a]
    poly += bowed(a, b, -8)
    poly += quad(b, ((b[0] + c[0]) / 2, b[1] + 4), c, steps=8)
    poly += bowed(c, d, -7)
    poly += bowed(d, e, -8)
    poly += quad(e, ((e[0] + f[0]) / 2, e[1] + 5), f, steps=8)
    poly += bowed(f, a, -7)
    return poly


# --- rasterizer ----------------------------------------------------------

def rasterize(polygons, w=SIZE, h=SIZE, subsamples=4):
    """Even-odd scanline coverage, 0..1 per pixel."""
    edges = []
    for poly in polygons:
        for i in range(len(poly)):
            x1, y1 = poly[i]
            x2, y2 = poly[(i + 1) % len(poly)]
            if y1 != y2:
                edges.append((min(y1, y2), max(y1, y2), x1, y1, x2, y2))
    edges.sort(key=lambda e: e[0])
    cov = [0.0] * (w * h)
    weight = 1.0 / subsamples
    for iy in range(h * subsamples):
        y = (iy + 0.5) / subsamples
        xs = []
        for ymin, ymax, x1, y1, x2, y2 in edges:
            if ymin > y:
                break
            if ymin <= y < ymax:
                xs.append(x1 + (y - y1) / (y2 - y1) * (x2 - x1))
        if not xs:
            continue
        xs.sort()
        row = (iy // subsamples) * w
        for j in range(0, len(xs) - 1, 2):
            x0 = max(0.0, min(float(w), xs[j]))
            x1 = max(0.0, min(float(w), xs[j + 1]))
            if x1 <= x0:
                continue
            ix0, ix1 = int(x0), int(x1)
            if ix0 == ix1:
                cov[row + ix0] += (x1 - x0) * weight
            else:
                cov[row + ix0] += (ix0 + 1 - x0) * weight
                for ix in range(ix0 + 1, ix1):
                    cov[row + ix] += weight
                if ix1 < w:
                    cov[row + ix1] += (x1 - ix1) * weight
    return cov


# --- compositing ---------------------------------------------------------

def render():
    print("rasterizing…")
    mask = rasterize([squircle(CENTER, CENTER, 412)])
    ring = rasterize([circle(CENTER, CENTER, RING_R + RING_STROKE / 2),
                      circle(CENTER, CENTER, RING_R - RING_STROKE / 2)])
    bolt = rasterize([bolt_polygon()])
    dot_c = (CENTER + RING_R * math.cos(DOT_ANGLE),
             CENTER + RING_R * math.sin(DOT_ANGLE))
    dot = rasterize([circle(dot_c[0], dot_c[1], DOT_R)])

    top_y, bottom_y = CENTER - 412, CENTER + 412
    pixels = bytearray(SIZE * SIZE * 4)
    for y in range(SIZE):
        t = min(1.0, max(0.0, (y - top_y) / (bottom_y - top_y)))
        bg = [BG_TOP[i] + (BG_BOTTOM[i] - BG_TOP[i]) * t for i in range(3)]
        for x in range(SIZE):
            i = y * SIZE + x
            r, g, b = bg
            for layer, color, alpha in ((ring, RING, RING_ALPHA),
                                        (bolt, BOLT, 1.0),
                                        (dot, DOT, 1.0)):
                a = min(1.0, layer[i]) * alpha
                if a > 0:
                    r += (color[0] - r) * a
                    g += (color[1] - g) * a
                    b += (color[2] - b) * a
            a = min(1.0, mask[i])
            o = i * 4
            pixels[o] = int(r + 0.5)
            pixels[o + 1] = int(g + 0.5)
            pixels[o + 2] = int(b + 0.5)
            pixels[o + 3] = int(a * 255 + 0.5)
    return pixels


def downscale(pixels, src, factor):
    """Box filter; factor divides src exactly. Premultiplies to avoid
    dark fringes on the squircle edge."""
    dst = src // factor
    out = bytearray(dst * dst * 4)
    area = factor * factor
    for y in range(dst):
        for x in range(dst):
            r = g = b = a = 0.0
            for sy in range(y * factor, (y + 1) * factor):
                row = sy * src * 4
                for sx in range(x * factor, (x + 1) * factor):
                    o = row + sx * 4
                    pa = pixels[o + 3] / 255.0
                    r += pixels[o] * pa
                    g += pixels[o + 1] * pa
                    b += pixels[o + 2] * pa
                    a += pa
            o = (y * dst + x) * 4
            if a > 0:
                out[o] = int(r / a + 0.5)
                out[o + 1] = int(g / a + 0.5)
                out[o + 2] = int(b / a + 0.5)
            out[o + 3] = int(a / area * 255 + 0.5)
    return out


# --- encoding ------------------------------------------------------------

def png(pixels, size):
    raw = b"".join(b"\x00" + bytes(pixels[y * size * 4:(y + 1) * size * 4])
                   for y in range(size))

    def chunk(tag, payload):
        data = tag + payload
        return struct.pack(">I", len(payload)) + data + struct.pack(">I", zlib.crc32(data))

    return (b"\x89PNG\r\n\x1a\n"
            + chunk(b"IHDR", struct.pack(">IIBBBBB", size, size, 8, 6, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(raw, 9))
            + chunk(b"IEND", b""))


ICNS_TYPES = [  # (type code, pixel size)
    (b"icp4", 16), (b"icp5", 32), (b"ic11", 32), (b"ic12", 64),
    (b"ic07", 128), (b"ic08", 256), (b"ic13", 256),
    (b"ic09", 512), (b"ic14", 512), (b"ic10", 1024),
]


def main():
    here = os.path.dirname(os.path.abspath(__file__))
    full = render()
    pngs = {1024: png(full, 1024)}
    for size in (512, 256, 128, 64, 32, 16):
        print(f"downscaling {size}…")
        pngs[size] = png(downscale(full, 1024, 1024 // size), size)

    body = b"".join(code + struct.pack(">I", 8 + len(pngs[size])) + pngs[size]
                    for code, size in ICNS_TYPES)
    icns = b"icns" + struct.pack(">I", 8 + len(body)) + body
    out = os.path.join(here, "Teslaris.icns")
    with open(out, "wb") as f:
        f.write(icns)
    with open("/tmp/teslaris-icon-1024.png", "wb") as f:
        f.write(pngs[1024])
    with open("/tmp/teslaris-icon-64.png", "wb") as f:
        f.write(pngs[64])
    print(f"wrote {out} ({len(icns)} bytes)")


if __name__ == "__main__":
    main()
