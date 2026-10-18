"""
VFX kit, batch 2: static anime-style textures.

Headless: tools/blender-*/blender.exe -b -P scripts/blender/vfx_textures_b2.py
Writes assets/vfx/src_b2/fx_*.png (max 1024 px, real alpha). Procedural (numpy, fixed seeds).

Tint rule: swooshes, slashes, brush strokes, runes, speed lines, smears, halftone, aura spikes and
the spike burst are white/grayscale with a hot white core (ParticleEmitter.Color, Beam.Color and
ImageColor3 tint them). The shadow pool and the ink splatter bake their own colors. The rune circle
and the three-mark eye are original, generic designs (invented glyphs, plain comma marks).

Skipped as already covered by batch 1: none of these (batch 1's slashes are soft crescents without
a rim, and nothing there is painterly, comic or ink).
"""

import math
import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))

from vfx_b2_common import (  # noqa: E402
    TAU, bands, fbm, fill, glow, jagged, rect, rgb, seg_distance, square, ss, union, vnoise, write,
)


def polar(X, Y, cx=0.0, cy=0.0):
    return np.hypot(X - cx, Y - cy), np.arctan2(Y - cy, X - cx)


def arc_band(X, Y, cx, cy, R, start, span):
    """Coordinates along an arc: u 0 (tail) -> 1 (head) over `span` radians from `start`, and the
    signed offset across the band (outward positive)."""
    r, th = polar(X, Y, cx, cy)
    rel = (th - start) % TAU
    u = rel / span
    across = r - R
    return u, across, rel <= span


# ---------------------------------------------------------------- 11 swoosh ribbon

def swoosh_ribbon(X, Y, px):
    """A thick curved ribbon (crescent): hot core along the leading edge, soft tail, and the
    trailing (inner) edge breaking into petals."""
    u, across, inarc = arc_band(X, Y, 0.0, -0.15, 0.62, math.radians(20), math.radians(160))
    uc = np.clip(u, 0.0, 1.0)
    half = 0.03 + 0.17 * np.sin(math.pi * uc ** 0.75) ** 1.2  # thick toward the head, tapered ends
    d = np.abs(across) - half
    body = fill(d, px) * inarc
    # Petals: the inner (trailing) half breaks up, more toward the tail.
    petals = vnoise(uc * 26.0, across * 0 + 0.5, 211, 64) * 0.6 + fbm(uc * 14.0, across * 9.0, 212, period=16) * 0.4
    inner = ss(0.15, -0.9, across / np.maximum(half, 1e-3))  # 0 at the outer edge -> 1 at the inner
    broken = ss(0.25 + 0.5 * uc, 0.45 + 0.5 * uc, petals + 0.6 * (1.0 - inner))
    body = body * np.where(across < 0.0, broken, 1.0)
    lead = np.clip(1.0 - np.abs(across - half * 0.45) / np.maximum(half * 0.5, 1e-3), 0.0, 1.0) * inarc
    core = fill(np.abs(across - half * 0.45) - half * 0.22, px) * inarc * ss(0.05, 0.3, uc)
    halo = glow(d, 0.05, 0.4) * inarc * ss(0.0, 0.25, uc) * (1.0 - ss(0.92, 1.0, uc))
    c = 0.8 + 0.2 * np.maximum(core, lead * 0.5)
    a = np.clip(body * (0.55 + 0.45 * ss(0.0, 0.35, uc)) + core, 0.0, 1.0)
    return c, a + halo * (1.0 - a)


# ---------------------------------------------------------------- 12 slash crescent

def slash_crescent(X, Y, px):
    """A big sharp crescent blade wave: white core, thin darker rim, needle-tapered ends."""
    cx, cy, R, d = 0.12, 0.0, 0.8, 0.3
    sd_outer = np.hypot(X - cx, Y - cy) - R
    sd_inner = np.hypot(X - cx + d, Y - cy) - R
    sd = np.maximum(sd_outer, -sd_inner)
    inside = fill(sd, px)
    rim = fill(np.abs(sd + 0.012) - 0.009, px) * inside  # thin dark line inside the edge
    depth = np.clip(-sd_outer / np.maximum(sd_inner - sd_outer, 1e-4), 0.0, 1.0)
    core = inside * (1.0 - depth) ** 1.3
    c = np.where(rim > 0.5, 0.32, 0.86 + 0.14 * core)
    halo = glow(sd, 0.04, 0.3) * ss(cx - d * 0.6, cx - d * 0.6 + 0.25, X)
    a = np.maximum(inside * (0.75 + 0.25 * core), rim)
    return c, a + halo * (1.0 - a)


# ---------------------------------------------------------------- 13 slash line (1024 x 128)

def slash_line(X, Y, px):
    """A long razor-thin slash: white core, thin dark edge, very tapered ends."""
    u = (X + 0.96) / 1.92
    uc = np.clip(u, 0.0, 1.0)
    half = 0.022 * np.sin(math.pi * uc) ** 0.7
    d = np.where((u >= 0.0) & (u <= 1.0), np.abs(Y) - half, 1.0)
    inside = fill(d, px)
    edge = fill(np.abs(d + 0.004) - 0.0035, px) * inside
    c = np.where(edge > 0.5, 0.3, 1.0)
    halo = 0.3 * np.exp(-np.maximum(d, 0.0) / 0.012) * np.sin(math.pi * uc) ** 1.5
    a = np.maximum(inside, edge)
    return c, a + halo * (1.0 - a)


# ---------------------------------------------------------------- 14 brush swirl

def brush_swirl(X, Y, px):
    """A painterly dry-brush arc: thick wet start, bristle streaks along the stroke, rough edges,
    a dry broken tail."""
    u, across, inarc = arc_band(X, Y, 0.0, -0.05, 0.58, math.radians(200), math.radians(250))
    uc = np.clip(u, 0.0, 1.0)
    half = 0.16 * (1.0 - 0.55 * uc) * np.sqrt(ss(0.0, 0.06, uc))
    rough = (fbm(uc * 20.0, np.zeros_like(uc) + 0.3, 221, period=32, octaves=3) - 0.5) * 0.06
    d = np.abs(across + rough) - half
    body = fill(d, px * 2.0) * inarc
    # Bristles: fine streaks along the stroke (high frequency across, low along).
    v = across / np.maximum(half, 1e-3)
    bristle = fbm(uc * 3.0, (v + 2.0) * 9.0, 222, period=16, octaves=3)
    dry = ss(0.35, 1.0, uc)  # the tail runs dry
    keep = ss(0.2 + 0.45 * dry, 0.3 + 0.45 * dry, bristle + 0.15 * (1.0 - np.abs(v)))
    a = body * keep
    c = 0.82 + 0.18 * (1.0 - np.abs(v)) * (1.0 - 0.5 * dry)
    return c, np.clip(a, 0.0, 1.0)


# ---------------------------------------------------------------- 15 rune circle (original)

def glyph_strokes(rng):
    """An invented glyph: 2-4 strokes on a 3x3 lattice."""
    lattice = [(x, y) for x in (-1, 0, 1) for y in (-1, 0, 1)]
    strokes = []
    for _ in range(rng.integers(2, 5)):
        a, b = rng.choice(len(lattice), 2, replace=False)
        strokes.append((lattice[a], lattice[b]))
    return strokes


def rune_circle(X, Y, px):
    """An original magic circle: three concentric rings, a band of invented glyphs, an inscribed
    eight-point star of two squares, an inked line look."""
    r, th = polar(X, Y)
    line = 0.006
    rings = np.zeros_like(X)
    for R in (0.88, 0.8, 0.56, 0.5, 0.18):
        rings = np.maximum(rings, fill(np.abs(r - R) - line, px))
    # Two squares turned 45 degrees from each other, inscribed in r = 0.5.
    star = np.zeros_like(X)
    for turn in (0.0, math.pi / 4):
        cs, sn = math.cos(turn), math.sin(turn)
        xr, yr = X * cs + Y * sn, -X * sn + Y * cs
        sq = np.maximum(np.abs(xr), np.abs(yr)) - 0.5 / math.sqrt(2.0)
        star = np.maximum(star, fill(np.abs(sq) - line, px))
    # Glyph band between 0.8 and 0.56: 16 cells around.
    rng = np.random.default_rng(231)
    glyphs = np.zeros_like(X)
    cells = 16
    for k in range(cells):
        ang = (k + 0.5) * TAU / cells
        cx, cy = math.cos(ang) * 0.68, math.sin(ang) * 0.68
        # Local frame: up points outward.
        ux, uy = math.cos(ang), math.sin(ang)
        lx = (X - cx) * (-uy) + (Y - cy) * ux
        ly = (X - cx) * ux + (Y - cy) * uy
        scale = 0.042
        for (ax, ay), (bx, by) in glyph_strokes(rng):
            sd, _ = seg_distance(lx, ly, [(ax * scale, ay * scale), (bx * scale, by * scale)], [line * 0.9] * 2)
            glyphs = np.maximum(glyphs, fill(sd, px))
    # Small marks on the outer band.
    ticks = fill(np.maximum(np.abs(r - 0.84) - 0.03, (np.abs(((th / TAU * 48) % 1.0) - 0.5) - 0.42) * 0.11), px)
    ink = np.maximum.reduce([rings, star, glyphs, ticks])
    halo = 0.25 * np.exp(-((r - 0.68) / 0.3) ** 2) * (r < 0.92)
    return 0.92 + 0.08 * ink, ink + halo * 0.35 * (1.0 - ink)


# ---------------------------------------------------------------- 16 three-mark eye (original)

def tri_spiral_eye(X, Y, px):
    """An original, generic decal: a ring, a center dot and three comma marks orbiting it."""
    r, th = polar(X, Y)
    ring = fill(np.abs(r - 0.78) - 0.035, px)
    disc = 0.25 * fill(r - 0.76, px)  # a faint fill so it reads as a disc
    dot = fill(r - 0.11, px)
    marks = np.zeros_like(X)
    for k in range(3):
        ang = math.pi / 2 + k * TAU / 3
        hx, hy = math.cos(ang) * 0.45, math.sin(ang) * 0.45
        head = np.hypot(X - hx, Y - hy) - 0.11
        # The tail: a thinning arc trailing behind the head, around the center.
        rel = (th - ang) % TAU
        tail_u = np.clip(rel / 1.3, 0.0, 1.0)
        tail = np.where(rel < 1.3, np.abs(r - (0.45 + 0.08 * tail_u)) - 0.1 * (1.0 - tail_u) ** 1.2, 1.0)
        marks = np.maximum(marks, fill(np.minimum(head, tail), px))
    ink = np.maximum.reduce([ring, dot, marks])
    a = np.maximum(ink, disc)
    return np.where(ink > 0.5, 1.0, 0.7), a


# ---------------------------------------------------------------- 17 speed lines

def speed_lines(X, Y, px):
    """Anime radial speed lines: thin tapered wedges from the edge toward a clear center."""
    r, th = polar(X, Y)
    rng = np.random.default_rng(241)
    a = np.zeros_like(X)
    for _ in range(64):
        ang = rng.uniform(0.0, TAU)
        inner = rng.uniform(0.38, 0.62)
        width = rng.uniform(0.004, 0.014)
        dth = np.abs((th - ang + math.pi) % TAU - math.pi) * r
        k = ss(inner, inner + 0.25, r)  # tapered toward the center
        line = fill(dth - width * k, px) * (r > inner)
        a = np.maximum(a, line * (0.6 + 0.4 * k))
    a = a * (1.0 - ss(0.93, 0.99, np.maximum(np.abs(X), np.abs(Y))))
    return 1.0, a


# ---------------------------------------------------------------- 18 fist blur

def fist_sd(X, Y, px):
    """A fist from the side, pointing right: a rounded box with three knuckle bumps."""
    bx, by, hw, hh, rad = 0.3, 0.0, 0.2, 0.15, 0.06
    q = np.maximum(np.abs(X - bx) - (hw - rad), 0.0), np.maximum(np.abs(Y - by) - (hh - rad), 0.0)
    box = np.hypot(q[0], q[1]) - rad
    knuckles = np.full_like(X, 10.0)
    for ky in (-0.09, 0.0, 0.09):
        knuckles = np.minimum(knuckles, np.hypot(X - (bx + hw - 0.02), Y - ky) - 0.055)
    thumb = np.hypot((X - (bx - 0.02)) / 1.6, Y + hh) - 0.05
    return np.minimum(np.minimum(box, knuckles), thumb)


def fist_blur(X, Y, px):
    """A punch smear: the fist silhouette at the front, smeared back into a fading streak, with a
    few speed lines."""
    a = np.zeros_like(X)
    c = np.ones_like(X)
    steps = 14
    for k in range(steps):
        shift = k * 0.07
        sd = fist_sd(X + shift, Y, px)
        weight = (1.0 - k / steps) ** 1.6
        a = np.maximum(a, fill(sd, px) * weight)
    front = fill(fist_sd(X, Y, px), px)
    outline = fill(np.abs(fist_sd(X, Y, px) + 0.01) - 0.008, px)
    for ly, L in ((-0.22, 0.9), (0.2, 0.7), (-0.05, 1.1), (0.1, 0.8)):
        u = (X - 0.25 + L) / L
        line = np.where((u > 0.0) & (u < 1.0), np.abs(Y - ly) - 0.008 * u, 1.0)
        a = np.maximum(a, fill(line, px) * u * 0.7)
    c = np.where(outline > 0.5, 0.45, 0.85 + 0.15 * front)
    a = np.maximum(a, np.maximum(front, outline))
    return c, a * (1.0 - ss(0.85, 0.97, np.abs(X)))


# ---------------------------------------------------------------- 19 halftone burst

def halftone_burst(X, Y, px):
    """A comic halftone burst: dots on a grid, biggest at the center, inside a spiky star."""
    r, th = polar(X, Y)
    rng = np.random.default_rng(251)
    n = 16
    angs = (np.arange(n) + rng.uniform(-0.2, 0.2, n)) * TAU / n
    lens = np.where(np.arange(n) % 2 == 0, rng.uniform(0.8, 0.92, n), rng.uniform(0.55, 0.68, n))
    R = np.full_like(r, 0.3)
    for ang, L in zip(angs, lens):
        dth = np.abs((th - ang + math.pi) % TAU - math.pi)
        R = np.maximum(R, L * (1.0 - dth / 0.32))
    cell = 0.055
    # A grid turned 30 degrees (classic halftone), dot radius from the burst's falloff.
    cs, sn = math.cos(0.52), math.sin(0.52)
    gx, gy = X * cs + Y * sn, -X * sn + Y * cs
    fx = (gx / cell) % 1.0 - 0.5
    fy = (gy / cell) % 1.0 - 0.5
    level = np.clip(1.0 - r / np.maximum(R, 1e-3), 0.0, 1.0)
    dot = np.hypot(fx, fy) * cell - 0.5 * cell * level ** 0.6
    a = fill(dot, px) * (r < R)
    return 1.0, a


# ---------------------------------------------------------------- 20 shadow pool (baked)

POOL_INK = rgb(16, 10, 22)
POOL_RIM = rgb(130, 80, 190)


def shadow_pool(X, Y, px):
    """A dark ink pool with a soft wobbly edge and a faint violet rim. Seen near the floor as a
    particle or billboard (never a flat neon part)."""
    r, th = polar(X, Y * 1.0)
    wobble = (fbm((th + math.pi) / TAU * 8.0, np.zeros_like(th) + 0.4, 261, period=8, octaves=3) - 0.5) * 0.16
    R = 0.66 + wobble
    sd = r - R
    body = ss(0.06, -0.04, sd)
    rim = np.exp(-((sd + 0.02) / 0.04) ** 2) * 0.8
    inner = ss(-0.5, -0.05, sd)  # the rim's glow fades into the middle
    col = POOL_INK + (POOL_RIM - POOL_INK) * np.clip(rim * inner, 0.0, 1.0)[..., None]
    a = np.clip(body * 0.92 + rim * 0.4 * (1.0 - body), 0.0, 1.0)
    return col, a


# ---------------------------------------------------------------- 21 aura spike

def aura_spike(X, Y, px):
    """A tall spiky flame aura sheet: sharp tongues rising from a hot band at the bottom, tallest
    in the middle, licking at the top."""
    h = (Y + 0.85) / 1.7
    hc = np.clip(h, 0.0, 1.0)
    rng = np.random.default_rng(271)
    # The hot base: a soft lens tapering at both ends (not a flat bar).
    d = 1.0 - ((Y + 0.78) / (0.07 * np.sqrt(np.clip(1.0 - (X / 0.78) ** 2, 0.0, 1.0)) + 1e-3)) ** 2
    for k in range(13):
        x0 = -0.7 + 1.4 * k / 12 + rng.uniform(-0.03, 0.03)
        top = (0.45 + 0.5 * (1.0 - abs(x0) / 0.75) ** 1.4) * rng.uniform(0.8, 1.0)
        w0 = 0.07 + 0.03 * rng.uniform()
        lean = rng.uniform(-0.06, 0.06)
        u = np.clip(hc / top, 0.0, 1.0)
        width = w0 * (1.0 - u) ** 1.1 + 1e-3
        tongue = 1.0 - np.abs(X - x0 - lean * u * u) / width
        d = np.maximum(d, np.where((h > 0.02) & (hc < top), tongue, -1.0))  # never below the base
    n = fbm((X + 1.0) * 4.0, (Y + 1.0) * 2.0, 272, period=8, octaves=3)
    F = d - (n - 0.5) * 0.35 * hc
    a = ss(0.0, 0.08, F)
    core = ss(0.35, 0.7, F) * (1.0 - ss(0.1, 0.55, hc))
    c = 0.8 + 0.2 * np.maximum(core, bands(1.0 - hc, 3) * 0.5)
    halo = 0.2 * ss(-0.35, 0.0, F) * (1.0 - ss(0.4, 0.9, hc))
    return union((c, a), (1.0, halo))


# ---------------------------------------------------------------- 22 ink splatter (baked red)

INK_RED = rgb(200, 18, 34)
INK_DARK = rgb(120, 8, 20)


def ink_splatter(X, Y, px):
    """Stylized red ink splatter: a round central blob, satellite drops and teardrop streaks
    thrown outward (cartoon ink, not gore)."""
    rng = np.random.default_rng(281)
    sd = np.hypot(X, Y) - 0.24 - 0.03 * np.cos(7.0 * np.arctan2(Y, X))
    for _ in range(9):  # teardrops
        ang = rng.uniform(0.0, TAU)
        dist = rng.uniform(0.38, 0.7)
        size = rng.uniform(0.04, 0.08)
        cx, cy = math.cos(ang) * dist, math.sin(ang) * dist
        sd = np.minimum(sd, np.hypot(X - cx, Y - cy) - size)
        tail, _ = seg_distance(X, Y, [(cx * 0.55, cy * 0.55), (cx, cy)], [0.004, size * 0.8])
        sd = np.minimum(sd, tail)
    for _ in range(14):  # specks
        ang = rng.uniform(0.0, TAU)
        dist = rng.uniform(0.3, 0.85)
        sd = np.minimum(sd, np.hypot(X - math.cos(ang) * dist, Y - math.sin(ang) * dist) - rng.uniform(0.012, 0.03))
    inside = fill(sd, px)
    shine = fill(np.hypot(X + 0.08, Y - 0.1) - 0.05, px)  # a cartoon highlight
    edge = ss(-0.04, 0.0, sd)
    col = INK_RED + (INK_DARK - INK_RED) * edge[..., None]
    col = col + (rgb(255, 210, 215) - col) * shine[..., None] * 0.85
    return col, inside


# ---------------------------------------------------------------- 23 ink spike burst

def ink_spike_burst(X, Y, px):
    """An ink starburst: jagged black spikes around a bright center (black stays black when tinted;
    the center takes the tint)."""
    r, th = polar(X, Y)
    rng = np.random.default_rng(291)
    n = 22
    angs = np.sort(rng.uniform(0.0, TAU, n))
    lens = rng.uniform(0.45, 0.92, n)
    widths = rng.uniform(0.06, 0.12, n)
    R = np.full_like(r, 0.26)
    for ang, L, w in zip(angs, lens, widths):
        dth = np.abs((th - ang + math.pi) % TAU - math.pi)
        R = np.maximum(R, L * np.clip(1.0 - dth / w, 0.0, 1.0) ** 1.3)  # clipped: no NaN powers
    R = R + (vnoise((th + math.pi) / TAU * 60.0, np.zeros_like(th) + 0.5, 292, 60) - 0.5) * 0.03
    spikes = fill(r - R, px)
    center = np.exp(-(r / 0.2) ** 2)
    hot = fill(r - 0.13, px)
    bright = np.clip(center + hot, 0.0, 1.0)
    c = 0.06 + 0.94 * bright
    a = np.maximum(spikes, bright)
    return c, a


# ---------------------------------------------------------------- list

TEXTURES = [
    ("fx_swoosh_ribbon", lambda: square(swoosh_ribbon, 1024)),
    ("fx_slash_crescent", lambda: square(slash_crescent, 1024)),
    ("fx_slash_line", lambda: rect(slash_line, 1024, 128)),
    ("fx_brush_swirl", lambda: square(brush_swirl, 1024)),
    ("fx_rune_circle", lambda: square(rune_circle, 1024)),
    ("fx_tri_spiral_eye", lambda: square(tri_spiral_eye, 512)),
    ("fx_speed_lines", lambda: square(speed_lines, 1024)),
    ("fx_fist_blur", lambda: square(fist_blur, 512)),
    ("fx_halftone_burst", lambda: square(halftone_burst, 1024)),
    ("fx_shadow_pool", lambda: square(shadow_pool, 512)),
    ("fx_aura_spike", lambda: square(aura_spike, 1024)),
    ("fx_ink_splatter", lambda: square(ink_splatter, 512)),
    ("fx_ink_spike_burst", lambda: square(ink_spike_burst, 1024)),
]


def main():
    only = set(sys.argv[sys.argv.index("--") + 1:]) if "--" in sys.argv else set()
    for name, build in TEXTURES:
        if only and name not in only:
            continue
        write(name, build())


if __name__ == "__main__":
    main()
