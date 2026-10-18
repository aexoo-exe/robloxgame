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
    """A thick curved ribbon (crescent) filling the cell: a hot white core along the leading
    (outer) edge, a soft fading tail, and petals breaking off the trailing (inner) edge."""
    R = 0.7
    u, across, inarc = arc_band(X, Y, 0.0, -0.1, R, math.radians(-25), math.radians(230))
    uc = np.clip(u, 0.0, 1.0)
    # A thick band toward the head (u ~ 0.7), needle tapered at both ends.
    half = 0.01 + 0.17 * np.sin(math.pi * uc ** 1.1) ** 1.1
    v = across / np.maximum(half, 1e-3)  # -1 trailing (inner) edge -> +1 leading (outer) edge
    # The trailing edge fades out smoothly (a soft gradient, no teeth); a gentle low-frequency
    # wobble keeps the fade from looking ruled.
    wobble = (fbm(uc * 5.0, np.zeros_like(uc) + 0.3, 211, period=8, octaves=2) - 0.5) * 0.25
    fade = ss(-1.0 + wobble, -0.05 + wobble, v)
    sd_band = np.abs(across) - half
    body = fill(sd_band, px) * inarc * fade
    # Four small petals breaking off the trailing edge at irregular places, each a leaf a little
    # inside the band, turned and sized differently (not a pattern).
    petals = np.zeros_like(X)
    centre_y = -0.1
    for pu, drift, size, turn in ((0.27, 0.05, 0.034, 0.5), (0.46, 0.09, 0.026, -0.4), (0.63, 0.06, 0.04, 0.9), (0.81, 0.11, 0.022, -0.2)):
        ang = math.radians(-25) + math.radians(230) * pu
        width_here = 0.01 + 0.17 * math.sin(math.pi * pu ** 1.1) ** 1.1
        r = R - width_here - drift
        cx, cy = math.cos(ang) * r, centre_y + math.sin(ang) * r
        # A leaf: an ellipse along its own turned axis.
        cs, sn = math.cos(ang + turn), math.sin(ang + turn)
        lx, ly = (X - cx) * cs + (Y - cy) * sn, -(X - cx) * sn + (Y - cy) * cs
        leaf = np.hypot(lx / (size * 1.8), ly / size) - 1.0
        petals = np.maximum(petals, fill(leaf * size, px) * 0.85)
    # The hot white core along the leading edge.
    core = fill((np.abs(v - 0.55) - 0.32) * half, px) * inarc * ss(0.08, 0.3, uc) * (1.0 - ss(0.93, 1.0, uc))
    tail = 0.3 + 0.7 * ss(0.0, 0.5, uc)  # the tail fades out
    halo = glow(sd_band, 0.05, 0.35) * inarc * ss(0.05, 0.4, uc) * (1.0 - ss(0.9, 1.0, uc))
    c = 0.88 + 0.12 * core
    a = np.clip(np.maximum(body * tail, petals) + core, 0.0, 1.0)
    return c, a + halo * (1.0 - a)


# ---------------------------------------------------------------- 12 slash crescent

def slash_crescent(X, Y, px):
    """A big sharp crescent blade wave: white core, thin darker rim, needle-tapered ends. Scaled to
    the cell's height and centered (its thickest point on the cell's middle)."""
    R, d = 0.86, 0.36
    cx, cy = -R + d * 0.5, 0.0
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
    """A long razor slash: a white core (twice the first pass's), thin dark edge, very tapered
    ends, inside a faint soft glow."""
    u = (X + 0.94) / 1.88
    uc = np.clip(u, 0.0, 1.0)
    along = np.sin(math.pi * uc)
    half = 0.044 * along ** 0.8
    d = np.where((u >= 0.0) & (u <= 1.0), np.abs(Y) - half, 1.0)
    inside = fill(d, px)
    edge = fill(np.abs(d + 0.005) - 0.004, px) * inside
    c = np.where(edge > 0.5, 0.3, 1.0)
    # A faint soft halo: tight bright glow plus a wide faint one, both fading toward the tips.
    out = np.maximum(d, 0.0)
    halo = (0.32 * np.exp(-out / 0.012) + 0.16 * np.exp(-out / 0.035)) * along ** 1.3
    a = np.maximum(inside, edge)
    return c, np.clip(a + halo * (1.0 - a), 0.0, 1.0)


# ---------------------------------------------------------------- 14 brush swirl

def brush_swirl(X, Y, px):
    """A dry-brush stroke arc of ~270 degrees filling the cell: many parallel bristle streaks with
    gaps between them, ragged broken ends, uneven pressure (thick start, thinning, a tail that
    splits), and a few stray flecks."""
    R = 0.64
    u, across, inarc = arc_band(X, Y, 0.0, 0.0, R, math.radians(225), math.radians(270))
    uc = np.clip(u, 0.0, 1.0)
    # Pressure: a quick heavy press, then thinning; a little wobble along the way.
    wob = (fbm(uc * 6.0, np.zeros_like(uc) + 0.2, 220, period=8, octaves=2) - 0.5) * 0.25
    half = 0.2 * (1.0 - 0.7 * uc ** 0.9 + wob) * np.sqrt(ss(0.0, 0.05, uc))
    rng = np.random.default_rng(221)
    streaks = 15
    a = np.zeros_like(X)
    c = np.zeros_like(X)
    for k in range(streaks):
        offset = -0.92 + 1.84 * k / (streaks - 1) + rng.uniform(-0.04, 0.04)
        # Half width as a share of the band's half width: streaks sit ~0.13 apart, so gaps show.
        width = rng.uniform(0.03, 0.058)
        start = rng.uniform(0.0, 0.06)
        # Outer bristles run out first: the tail splits and frays.
        end = 1.0 - abs(offset) * rng.uniform(0.25, 0.55) - rng.uniform(0.0, 0.1)
        # The tail splits: streaks drift apart as the brush lifts.
        spread = 1.0 + 0.5 * ss(0.6, 1.0, uc)
        centre = offset * half * spread
        dist = np.abs(across - centre) - width * np.maximum(half, 0.02)
        line = fill(dist, px) * inarc * (uc >= start) * (uc <= end)
        # Ragged ends and dry breaks along the streak.
        ragged = 1.0 - ss(end - 0.08, end, uc) * (fbm(uc * 40.0 + k * 3.1, np.zeros_like(uc) + k, 222, period=64, octaves=2) < 0.55)
        dry = fbm(uc * 22.0 + k * 1.7, np.zeros_like(uc) + 0.5 * k, 223, period=32, octaves=3)
        keep = ss(0.32 + 0.25 * uc, 0.38 + 0.25 * uc, dry)
        stroke = line * ragged * keep
        shade = rng.uniform(0.82, 1.0)
        c = np.where(stroke > a, shade, c)
        a = np.maximum(a, stroke)
    # Stray flecks flicked off near the tail and the outer edge.
    for _ in range(18):
        fu = rng.uniform(0.45, 1.0)
        ang = math.radians(225) + math.radians(270) * fu
        r = R + rng.uniform(-0.3, 0.3)
        fx, fy = math.cos(ang) * r, math.sin(ang) * r
        dot = fill(np.hypot(X - fx, Y - fy) - rng.uniform(0.006, 0.016), px)
        c = np.where(dot > a, 0.9, c)
        a = np.maximum(a, dot)
    return np.where(a > 0.0, c, 1.0), a


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

FIST = {"x": 0.5, "hw": 0.29, "hh": 0.27}


def capsule(X, Y, a, b, r):
    sd, _ = seg_distance(X, Y, [a, b], [r, r])
    return sd


def fist_sd(X, Y, px):
    """A fist from the side, punching right: a rounded block of curled fingers with four knuckle
    bumps on the front, a thumb wrapped along the bottom, a short wrist behind."""
    bx, hw, hh = FIST["x"], FIST["hw"], FIST["hh"]
    rad = 0.1
    q = np.maximum(np.abs(X - bx) - (hw - rad), 0.0), np.maximum(np.abs(Y) - (hh - rad), 0.0)
    block = np.hypot(q[0], q[1]) - rad
    knuckles = np.full_like(X, 10.0)
    for ky in (-0.15, -0.05, 0.05, 0.15):
        knuckles = np.minimum(knuckles, np.hypot(X - (bx + hw - 0.05), Y - ky) - 0.072)
    thumb = capsule(X, Y, (bx - 0.14, -hh + 0.02), (bx + 0.16, -hh + 0.06), 0.075)
    wrist = capsule(X, Y, (bx - hw - 0.12, 0.0), (bx - hw + 0.05, 0.0), 0.15)
    return np.minimum(np.minimum(block, knuckles), np.minimum(thumb, wrist))


def fist_blur(X, Y, px):
    """A punch smear filling the cell's width: the rounded fist at the front (outlined, finger
    grooves, thumb), smeared back into a long tapered streak, with a few speed lines."""
    a = np.zeros_like(X)
    steps = 22
    for k in range(1, steps):
        shift = k * 0.062
        squash = 1.0 - 0.7 * k / steps  # the smear tapers toward its tail
        sd = fist_sd(X + shift, Y / squash, px) * squash
        a = np.maximum(a, fill(sd, px) * 0.85 * (1.0 - k / steps) ** 1.2)
    sd = fist_sd(X, Y, px)
    front = fill(sd, px)
    outline = fill(np.abs(sd + 0.012) - 0.01, px)
    # Finger grooves between the knuckle rows and the thumb's edge.
    bx, hw, hh = FIST["x"], FIST["hw"], FIST["hh"]
    grooves = np.zeros_like(X)
    for gy in (-0.1, 0.0, 0.1):
        g = capsule(X, Y, (bx + 0.02, gy), (bx + hw - 0.06, gy), 0.008)
        grooves = np.maximum(grooves, fill(g, px))
    thumb_line = fill(np.abs(capsule(X, Y, (bx - 0.14, -hh + 0.02), (bx + 0.16, -hh + 0.06), 0.075)) - 0.008, px)
    lines = np.maximum(grooves, thumb_line) * front
    for ly, L in ((-0.3, 1.2), (0.3, 1.0), (-0.12, 1.5), (0.14, 1.3), (0.0, 0.9)):
        u = (X - (bx - hw) + L) / L
        line = np.where((u > 0.0) & (u < 1.0), np.abs(Y - ly) - 0.009 * u, 1.0)
        a = np.maximum(a, fill(line, px) * u * 0.65)
    c = np.where(np.maximum(outline, lines) > 0.5, 0.42, 0.88 + 0.12 * front)
    a = np.maximum(a, np.maximum(front, outline))
    return c, a * (1.0 - ss(0.86, 0.95, np.abs(X)))


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

AURA_BASE, AURA_TOP = -0.86, 0.84


def aura_spike(X, Y, px):
    """A flame aura sheet filling the cell's height: 9 curved flame tongues of uneven height that
    lean and curl, wide at the base, pointed and wispy at the tips; a hot white core fading to a
    soft outer edge. White/grayscale for tinting."""
    full = AURA_TOP - AURA_BASE
    h = np.clip((Y - AURA_BASE) / full, 0.0, 1.0)
    rng = np.random.default_rng(271)
    # A soft hot base joining the tongues (a lens tapering at both ends).
    d = 1.0 - (X / 0.7) ** 2 - ((Y - AURA_BASE - 0.05) / 0.09) ** 2
    count = 9
    for k in range(count):
        x0 = -0.6 + 1.2 * k / (count - 1) + rng.uniform(-0.04, 0.04)
        # Uneven heights, tallest toward the middle; the tallest reaches the top.
        frac = (0.5 + 0.5 * (1.0 - abs(x0) / 0.7) ** 1.2) * rng.uniform(0.72, 1.0)
        if k == count // 2:
            frac = 1.0
        top = full * frac
        w0 = rng.uniform(0.11, 0.16)
        lean = rng.uniform(-0.16, 0.16)
        curl = rng.uniform(-0.09, 0.09)
        u = np.clip((Y - AURA_BASE) / top, 0.0, 1.0)
        centre = x0 + lean * u ** 1.5 + curl * np.sin(math.pi * u * 1.3) * u * u
        flicker = 1.0 + 0.18 * np.sin(u * 9.0 + k * 1.7)
        width = w0 * (1.0 - u) ** 0.75 * flicker + 1e-3
        tongue = 1.0 - np.abs(X - centre) / width
        d = np.maximum(d, np.where((Y > AURA_BASE) & (u < 1.0), tongue, -1.0))
    # Wispy tips: noise eats into the flame more the higher it goes.
    n = fbm((X + 1.0) * 5.0, (Y + 1.0) * 2.5, 272, period=16, octaves=3)
    F = d - (n - 0.5) * (0.15 + 0.7 * h ** 1.4)
    a = ss(0.0, 0.12, F) * (1.0 - 0.3 * ss(0.65, 1.0, h))
    core = ss(0.45, 0.8, F) * (1.0 - ss(0.25, 0.8, h))  # hot white inside, lower down
    c = 0.74 + 0.26 * core
    halo = 0.22 * ss(-0.4, 0.0, F) * (1.0 - ss(0.5, 1.0, h))  # the soft outer edge
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
