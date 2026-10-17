"""
VFX kit, batch 1: procedural effect textures for Roblox.

Run inside Blender: Scripting workspace > Text > Open (this file) > Run Script.
Headless:           blender --background --python scripts/blender/vfx_textures.py

Writes every texture plus contact_sheet.png into assets/vfx/textures/.
Style rules: docs/design/vfx-style.md.

Every texture is near-white RGB with real alpha so Roblox can tint it by element.
Flipbooks are 4x4, read left to right, top to bottom.
"""

import math
import os
from pathlib import Path

import bpy
import numpy as np

# Set to an absolute folder to write somewhere else (env VFX_TEXTURES_OUT also works).
OUT_DIR_OVERRIDE = ""

TAU = 2.0 * math.pi


# ---------------------------------------------------------------- helpers

def coords(w, h=None):
    """Pixel-centre coordinates in [-1, 1]; row 0 is the top, +Y is up."""
    h = h or w
    xs = (np.arange(w, dtype=np.float32) + 0.5) / w * 2.0 - 1.0
    ys = 1.0 - (np.arange(h, dtype=np.float32) + 0.5) / h * 2.0
    return np.meshgrid(xs, ys)


def ss(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def fill(sd, px):
    """Anti-aliased inside mask for a signed distance (negative = inside)."""
    return np.clip(0.5 - sd / px, 0.0, 1.0)


def glow(sd, width, strength):
    return strength * np.exp(-np.maximum(sd, 0.0) / width)


def union(*layers):
    """Stack (value, alpha) layers: alphas combine like light, value is alpha-weighted."""
    shape = np.shape(layers[0][1])
    a = np.zeros(shape, np.float32)
    ca = np.zeros(shape, np.float32)
    wsum = np.zeros(shape, np.float32)
    for c, la in layers:
        a = a + la * (1.0 - a)
        ca = ca + c * la
        wsum = wsum + la
    c = np.where(wsum > 1e-6, ca / np.maximum(wsum, 1e-6), 1.0)
    return c, a


def border_fade(X, Y, start=0.9):
    return 1.0 - ss(start, 1.0, np.maximum(np.abs(X), np.abs(Y)))


def finish(c, a):
    a = np.clip(a, 0.0, 1.0).astype(np.float32)
    c = np.clip(np.broadcast_to(c, a.shape), 0.0, 1.0)
    # Invisible pixels stay white so texture filtering never pulls in a dark fringe.
    c = np.where(a > 1.0 / 512.0, c, 1.0)
    return np.dstack([c, c, c, a]).astype(np.float32)


def square(fn, w):
    X, Y = coords(w)
    c, a = fn(X, Y, 2.0 / w)
    return finish(c, a * border_fade(X, Y))


def flipbook(fn, loop, size=1024, grid=4):
    cell = size // grid
    X, Y = coords(cell)
    fade = border_fade(X, Y)
    frames = grid * grid
    sheet = np.zeros((size, size, 4), np.float32)
    for i in range(frames):
        t = i / frames if loop else i / (frames - 1)
        c, a = fn(X, Y, 2.0 / cell, t)
        row, col = divmod(i, grid)
        sheet[row * cell:(row + 1) * cell, col * cell:(col + 1) * cell] = finish(c, a * fade)
    return sheet


# ---------------------------------------------------------------- noise

_GRIDS = {}


def _grid(seed, n):
    key = (seed, n)
    if key not in _GRIDS:
        _GRIDS[key] = np.random.default_rng(seed).random((n, n)).astype(np.float32)
    return _GRIDS[key]


def vnoise(U, V, seed, n):
    """Smooth value noise; wraps every n units in U and V."""
    g = _grid(seed, n)
    iu = np.floor(U)
    iv = np.floor(V)
    fu = U - iu
    fv = V - iv
    fu = fu * fu * (3.0 - 2.0 * fu)
    fv = fv * fv * (3.0 - 2.0 * fv)
    iu = iu.astype(np.int64) % n
    iv = iv.astype(np.int64) % n
    iu1 = (iu + 1) % n
    iv1 = (iv + 1) % n
    top = g[iv, iu] * (1.0 - fu) + g[iv, iu1] * fu
    bot = g[iv1, iu] * (1.0 - fu) + g[iv1, iu1] * fu
    return top * (1.0 - fv) + bot * fv


def fbm(U, V, seed, period=8, octaves=4):
    """Fractal value noise in [0, 1]; tiles every `period` units."""
    total = 0.0
    norm = 0.0
    amp = 1.0
    for o in range(octaves):
        f = 2 ** o
        total = total + amp * vnoise(U * f, V * f, seed + 101 * o, period * f)
        norm += amp
        amp *= 0.5
    return total / norm


# ---------------------------------------------------------------- slash

def crescent(X, Y, cx, cy, r, d, px, streaks=False, seed=3):
    """Circle minus an offset circle: tapered tips, bright leading edge, faded tail."""
    rad = np.hypot(X - cx, Y - cy)
    sd_outer = rad - r
    sd = np.maximum(sd_outer, -(np.hypot(X - cx + d, Y - cy) - r))
    inside = fill(sd, px)
    lead = (1.0 - np.clip(-sd_outer / d, 0.0, 1.0)) ** 1.5
    core = inside * (0.45 + 0.55 * lead)
    if streaks:
        n = vnoise(rad * 90.0, np.zeros_like(rad), seed, 512)
        core = core * (0.7 + 0.3 * ss(0.35, 0.65, n))
    halo = glow(sd, 0.045, 0.4)
    head = 0.35 + 0.65 * ss(cy - 0.8 * r, cy + 0.35 * r, Y)
    a = (core + halo * (1.0 - core)) * head
    c = 0.86 + 0.14 * lead * inside
    return c, a


def slash_thin(X, Y, px):
    return crescent(X, Y, 0.05, 0.0, 0.8, 0.07, px)


def slash_wide(X, Y, px):
    return crescent(X, Y, 0.05, 0.0, 0.8, 0.28, px, streaks=True)


def slash_double(X, Y, px):
    c1, a1 = crescent(X, Y, 0.05, 0.0, 0.8, 0.11, px)
    c2, a2 = crescent(X, Y, -0.12, 0.0, 0.6, 0.08, px)
    return union((c1, a1), (c2, a2 * 0.85))


# ---------------------------------------------------------------- glow

def glow_soft(X, Y, px):
    r = np.hypot(X, Y)
    return 1.0, np.exp(-r * r * 5.0)


def glow_hard_core(X, Y, px):
    r = np.hypot(X, Y)
    core = fill(r - 0.15, px)
    halo = 0.7 * np.exp(-r * r * 16.0) + 0.3 * np.exp(-r * 5.0)
    return 0.9 + 0.1 * core, core + halo * (1.0 - core)


# ---------------------------------------------------------------- rings

def ring(X, Y, px, radius, half, segments=0, shock=False):
    r = np.hypot(X, Y)
    sd = np.abs(r - radius) - half
    if segments:
        f = (np.arctan2(Y, X) / TAU * segments) % 1.0
        sd = np.maximum(sd, (np.abs(f - 0.5) - 0.36) * (TAU * radius / segments))
    inside = fill(sd, px)
    core = inside
    c = 0.88 + 0.12 * inside
    if shock:
        # Shockwave: soft inner side, crisp bright outer edge.
        t = np.clip((r - (radius - half)) / (2.0 * half), 0.0, 1.0)
        core = inside * (0.3 + 0.7 * t * t)
        c = 0.84 + 0.16 * t * inside
    halo = glow(sd, 0.035, 0.38)
    return c, core + halo * (1.0 - core)


def ring_thin(X, Y, px):
    return ring(X, Y, px, 0.75, 0.014)


def ring_thick(X, Y, px):
    return ring(X, Y, px, 0.66, 0.12, shock=True)


def ring_segmented(X, Y, px):
    return ring(X, Y, px, 0.72, 0.035, segments=12)


# ---------------------------------------------------------------- sparks

def spark_streak(X, Y, px):
    """Horizontal streak: round bright head on the right, needle tail on the left."""
    u = (X + 0.85) / 1.7
    uc = np.clip(u, 0.0, 1.0)
    hw = 0.055 * uc ** 1.1 * np.sqrt(np.clip((1.0 - uc) * 10.0, 0.0, 1.0))
    sd = np.where((u >= 0.0) & (u <= 1.0), np.abs(Y) - hw, 1.0)
    inside = fill(sd, px)
    core = inside * (0.25 + 0.75 * uc)
    d = np.hypot(np.maximum(np.abs(X) - 0.85, 0.0), Y)
    halo = 0.35 * np.exp(-d / 0.05) * (0.15 + 0.85 * uc)
    return 0.9 + 0.1 * inside, core + halo * (1.0 - core)


def spark_star(X, Y, px):
    """Four long rays, four short diagonals, hot centre."""
    r = np.hypot(X, Y)
    core = fill(r - 0.06, px)
    halo = 0.55 * np.exp(-r * r * 22.0)
    rays = [(0, 0.86, 0.075), (90, 0.86, 0.075), (180, 0.86, 0.075), (270, 0.86, 0.075),
            (45, 0.5, 0.045), (135, 0.5, 0.045), (225, 0.5, 0.045), (315, 0.5, 0.045)]
    for deg, length, width in rays:
        cs, sn = math.cos(math.radians(deg)), math.sin(math.radians(deg))
        along = X * cs + Y * sn
        perp = np.abs(-X * sn + Y * cs)
        k = np.clip(1.0 - along / length, 0.0, 1.0) * (along > 0.0)
        sd = np.where(along > 0.0, perp - width * k, 1.0)
        core = np.maximum(core, fill(sd, px))
        halo = np.maximum(halo, 0.3 * np.exp(-perp / 0.035) * k * k)
    return 0.9 + 0.1 * core, core + halo * (1.0 - core)


# ---------------------------------------------------------------- smoke

def smoke_blobs(seed, count=7):
    rng = np.random.default_rng(seed)
    blobs = []
    for i in range(count):
        ang = rng.uniform(0.0, TAU)
        dist = rng.uniform(0.0, 0.3) if i else 0.0
        blobs.append((math.cos(ang) * dist, math.sin(ang) * dist * 0.8, rng.uniform(0.24, 0.36)))
    return blobs


def smoke_density(X, Y, blobs, seed, drift):
    dens = np.full_like(X, -1.0)
    for bx, by, br in blobs:
        dens = np.maximum(dens, 1.0 - np.hypot(X - bx, Y - by) / br)
    n = fbm((X + 1.0) * 2.0, (Y + 1.0) * 2.0 - drift, seed, period=8, octaves=4)
    return dens + (n - 0.5) * 0.9


def smoke(X, Y, blobs, seed, thr=0.2, drift=0.0, opacity=0.9):
    """Lumpy cel-shaded puff: lit rim toward the top-left, darker body."""
    d = smoke_density(X, Y, blobs, seed, drift)
    d_lit = smoke_density(X - 0.05, Y + 0.07, blobs, seed, drift)
    a = ss(thr - 0.015, thr + 0.015, d) * opacity
    c = 0.97 - 0.27 * ss(thr + 0.06, thr + 0.16, d_lit)
    return c, a


PUFF_BLOBS = smoke_blobs(10)
SMOKE_BLOBS = smoke_blobs(11)


def smoke_puff(X, Y, px):
    return smoke(X, Y, PUFF_BLOBS, 12)


def smoke_frame(X, Y, px, t):
    s = 0.5 + 0.55 * (1.0 - (1.0 - t) ** 2)
    rise = 0.12 * t
    c, a = smoke(X / s, (Y - rise) / s, SMOKE_BLOBS, 13, thr=0.2 + 0.6 * t ** 1.7, drift=1.2 * t)
    return c, a * (1.0 - ss(0.75, 1.0, t))


# ---------------------------------------------------------------- explosion

def explosion_frame(X, Y, px, t):
    """Flash and shock ring, swelling fireball, then breaks up into fading smoke."""
    r = np.hypot(X, Y)
    R = 0.22 + 0.58 * (1.0 - (1.0 - t) ** 2.5)
    n = fbm((X / R + 2.0) * 1.5, (Y / R + 2.0) * 1.5, 21, period=8, octaves=4)
    dens = 1.0 - r / R + (n - 0.5) * (0.7 + 0.6 * t)
    thr = 0.02 + 0.7 * t ** 1.5
    a = ss(thr - 0.02, thr + 0.02, dens) * (1.0 - 0.15 * t)
    hot = ss(thr + 0.12, thr + 0.4, dens) * (1.0 - t) ** 0.7
    base = 0.92 - 0.3 * t
    layers = [(base + (1.0 - base) * hot, a),
              (1.0, 0.5 * (1.0 - t) ** 3 * np.exp(-2.0 * (r / (R * 1.2)) ** 2))]
    if t < 0.35:
        k = 1.0 - t / 0.35
        sd = np.abs(r - (0.3 + 1.6 * t)) - 0.02 * k
        layers.append((1.0, (fill(sd, px) + glow(sd, 0.03, 0.3)) * k))
    c, a = union(*layers)
    return c, a * (1.0 - ss(0.8, 1.0, t))


# ---------------------------------------------------------------- fire

def fire_frame(X, Y, px, t):
    """Looping flame tongue; noise scrolls up exactly one period per loop."""
    h = (Y + 0.8) / 1.62
    hc = np.clip(h, 0.0, 1.0)
    sway = 0.06 * np.sin(TAU * (2.0 * t + 1.3 * hc)) * hc
    U = (X + 1.0) * 2.0
    V = (Y + 1.0) * 2.0 - 4.0 * t
    n = fbm(U, V, 31, period=4, octaves=4)
    n2 = fbm(U + 1.7, V, 37, period=4, octaves=3)
    xw = X - sway - (n2 - 0.5) * 0.35 * hc
    width = 0.44 * (1.0 - hc) ** 0.85 * np.sqrt(np.clip(h * 5.0, 0.0, 1.0))
    env = np.where((h > 0.0) & (h < 1.0), 1.0 - np.abs(xw) / np.maximum(width, 1e-3), -1.0)
    dens = env - (n - 0.35) * 1.4 * hc ** 1.2
    a = ss(0.0, 0.05, dens)
    core = ss(0.35, 0.5, dens + 0.25 * (1.0 - hc))
    halo = 0.3 * np.exp(-np.maximum(-dens, 0.0) / 0.25) * ss(-0.1, 0.1, h) * (1.0 - ss(0.8, 1.05, h))
    return union((0.8 + 0.2 * core, a), (1.0, halo))


# ---------------------------------------------------------------- lightning

def periodic_lerp(vals, u):
    n = len(vals)
    i = np.floor(u).astype(np.int64)
    f = u - i
    return vals[i % n] * (1.0 - f) + vals[(i + 1) % n] * f


def lightning_strip(w=512, h=128):
    """Jagged bolt that tiles horizontally (Beam texture, U along the beam)."""
    x = np.arange(w, dtype=np.float32) + 0.5
    yrow = (np.arange(h, dtype=np.float32) + 0.5 - h / 2.0)[:, None]

    def bolt(seed, amp, ctrl):
        rng = np.random.default_rng(seed)
        coarse = rng.uniform(-1.0, 1.0, ctrl) * amp
        fine = rng.uniform(-1.0, 1.0, ctrl * 4) * amp * 0.3
        y = periodic_lerp(coarse, x / w * ctrl) + periodic_lerp(fine, x / w * ctrl * 4)
        slope = (np.roll(y, -1) - np.roll(y, 1)) / 2.0
        return np.abs(yrow - y[None, :]) / np.sqrt(1.0 + slope * slope)[None, :]

    d1 = bolt(41, 20.0, 12)
    d2 = bolt(42, 24.0, 9)
    c, a = union((1.0, np.clip(2.7 - d1, 0.0, 1.0)),
                 (0.92, np.clip(1.4 - d2, 0.0, 1.0) * 0.7),
                 (1.0, 0.5 * np.exp(-d1 / 7.0)),
                 (1.0, 0.22 * np.exp(-d2 / 6.0)))
    a = a * (1.0 - ss(0.85, 1.0, np.abs(yrow) / (h / 2.0)))
    return finish(c, a)


# ---------------------------------------------------------------- energy

def energy_swirl(X, Y, px):
    r = np.hypot(X, Y)
    s = 0.5 + 0.5 * np.cos(3.0 * np.arctan2(Y, X) + 9.0 * r)
    thr = 0.55 + 0.35 * r
    arm = ss(thr - 0.05, thr + 0.05, s)
    env = ss(0.06, 0.22, r) * (1.0 - ss(0.55, 0.88, r))
    core = np.clip(arm * env * (1.1 - r), 0.0, 1.0)
    halo = 0.3 * s ** 3 * env + 0.6 * np.exp(-r * r * 40.0)
    return 0.86 + 0.14 * arm, core + halo * (1.0 - core)


def energy_orb(X, Y, px):
    r = np.hypot(X, Y)
    R = 0.52
    inside = fill(r - R, px)
    rim = np.clip(r / R, 0.0, 1.0) ** 4
    swirl = fbm((np.arctan2(Y, X) + math.pi) / TAU * 8.0 + r * 6.0, r * 6.0, 81, period=8)
    body = inside * (0.45 + 0.4 * rim + 0.3 * (swirl - 0.5))
    line = fill(np.abs(r - R + 0.015) - 0.012, px)
    hl = 0.5 * np.exp(-((X + 0.18) ** 2 + (Y - 0.18) ** 2) / 0.012) * inside
    core = np.clip(body + line + hl, 0.0, 1.0)
    halo = glow(r - R, 0.09, 0.45)
    return 0.86 + 0.14 * np.clip(rim + line + hl * 2.0, 0.0, 1.0), core + halo * (1.0 - core)


# ---------------------------------------------------------------- ground

def ground_crack(X, Y, px):
    """Top-down decal: glowing radial cracks with forks around a small crater."""
    rng = np.random.default_rng(51)
    segs = []

    def walk(x, y, ang, length, width, depth):
        step = 0.05
        n = max(2, int(length / step))
        for i in range(n):
            ang += rng.normal(0.0, 0.3)
            nx, ny = x + math.cos(ang) * step, y + math.sin(ang) * step
            w0, w1 = width * (1.0 - i / n), width * (1.0 - (i + 1) / n)
            segs.append((x, y, nx, ny, w0, w1))
            if depth < 2 and i > 1 and rng.random() < 0.18:
                turn = rng.choice([-1.0, 1.0]) * rng.uniform(0.5, 0.9)
                walk(nx, ny, ang + turn, length * 0.4 * (1.0 - i / n) + 0.08, w1 * 0.75, depth + 1)
            x, y = nx, ny

    for k in range(8):
        ang = k * TAU / 8.0 + rng.normal(0.0, 0.18)
        walk(math.cos(ang) * 0.07, math.sin(ang) * 0.07, ang, rng.uniform(0.5, 0.78), 0.02, 0)

    sd = np.full_like(X, 10.0)
    for x0, y0, x1, y1, w0, w1 in segs:
        dx, dy = x1 - x0, y1 - y0
        t = np.clip(((X - x0) * dx + (Y - y0) * dy) / (dx * dx + dy * dy), 0.0, 1.0)
        d = np.hypot(X - (x0 + t * dx), Y - (y0 + t * dy)) - (w0 + (w1 - w0) * t)
        sd = np.minimum(sd, d)

    r = np.hypot(X, Y)
    core = np.maximum(fill(sd, px), fill(r - 0.08, px) * 0.9)
    halo = glow(np.minimum(sd, r - 0.08), 0.03, 0.45)
    return 0.88 + 0.12 * core, core + halo * (1.0 - core)


def ground_scorch(X, Y, px):
    """Burn mark with a ragged, splattered edge. Tint dark for soot, or by element."""
    r = np.hypot(X, Y)
    U = (np.arctan2(Y, X) + math.pi) / TAU * 12.0
    zero = np.zeros_like(U)
    edge_n = fbm(U, zero, 61, period=12, octaves=3)
    spikes = vnoise(U * 4.0, zero, 62, 48) ** 6
    edge = 0.45 + (edge_n - 0.5) * 0.3 + spikes * 0.3 - r
    mott = fbm((X + 1.0) * 4.0, (Y + 1.0) * 4.0, 63, period=8)
    body = ss(0.0, 0.03, edge) * (0.5 + 0.4 * ss(0.0, 0.35, edge)) * (0.75 + 0.5 * (mott - 0.5))
    halo = 0.2 * np.exp(-np.maximum(-edge, 0.0) / 0.05)
    return union((0.8 + 0.2 * mott, body), (1.0, halo))


# ---------------------------------------------------------------- impact

def impact_starburst(X, Y, px):
    """Anime hit burst: uneven spikes, white inner star, softer outer star."""
    r = np.hypot(X, Y)
    th = np.arctan2(Y, X)
    rng = np.random.default_rng(71)
    n = 14
    angs = (np.arange(n) + rng.uniform(-0.25, 0.25, n)) * TAU / n
    lens = np.where(np.arange(n) % 2 == 0, rng.uniform(0.72, 0.86, n), rng.uniform(0.42, 0.58, n))
    widths = rng.uniform(0.11, 0.16, n)
    R = np.full_like(r, 0.2)
    for ang, length, wd in zip(angs, lens, widths):
        dth = np.abs((th - ang + math.pi) % TAU - math.pi)
        R = np.maximum(R, length * (1.0 - dth / wd))
    outer = fill(r - R, px * 1.5)
    inner = fill(r - R * 0.55, px * 1.5)
    core = np.maximum(outer * 0.9, inner)
    halo = glow(r - R, 0.05, 0.4)
    return 0.82 + 0.18 * inner, core + halo * (1.0 - core)


# ---------------------------------------------------------------- texture list

TEXTURES = [
    ("vfx_slash_thin", lambda: square(slash_thin, 512)),
    ("vfx_slash_wide", lambda: square(slash_wide, 512)),
    ("vfx_slash_double", lambda: square(slash_double, 512)),
    ("vfx_glow_soft", lambda: square(glow_soft, 256)),
    ("vfx_glow_hard_core", lambda: square(glow_hard_core, 256)),
    ("vfx_ring_thin", lambda: square(ring_thin, 512)),
    ("vfx_ring_thick", lambda: square(ring_thick, 512)),
    ("vfx_ring_segmented", lambda: square(ring_segmented, 512)),
    ("vfx_spark_streak", lambda: square(spark_streak, 256)),
    ("vfx_spark_star", lambda: square(spark_star, 256)),
    ("vfx_smoke_puff", lambda: square(smoke_puff, 512)),
    ("vfx_smoke_flipbook", lambda: flipbook(smoke_frame, loop=False)),
    ("vfx_explosion_flipbook", lambda: flipbook(explosion_frame, loop=False)),
    ("vfx_fire_flipbook", lambda: flipbook(fire_frame, loop=True)),
    ("vfx_lightning_strip", lambda: lightning_strip()),
    ("vfx_energy_swirl", lambda: square(energy_swirl, 512)),
    ("vfx_energy_orb", lambda: square(energy_orb, 512)),
    ("vfx_ground_crack", lambda: square(ground_crack, 512)),
    ("vfx_ground_scorch", lambda: square(ground_scorch, 512)),
    ("vfx_impact_starburst", lambda: square(impact_starburst, 512)),
]

NOTES = {
    "vfx_smoke_flipbook": "4X4 ONESHOT",
    "vfx_explosion_flipbook": "4X4 ONESHOT",
    "vfx_fire_flipbook": "4X4 LOOP",
    "vfx_lightning_strip": "TILES X",
}


# ---------------------------------------------------------------- contact sheet

FONT = {
    "A": ".###.|#...#|#####|#...#|#...#", "B": "####.|#...#|####.|#...#|####.",
    "C": ".####|#....|#....|#....|.####", "D": "####.|#...#|#...#|#...#|####.",
    "E": "#####|#....|####.|#....|#####", "F": "#####|#....|####.|#....|#....",
    "G": ".####|#....|#..##|#...#|.###.", "H": "#...#|#...#|#####|#...#|#...#",
    "I": "#####|..#..|..#..|..#..|#####", "J": "..###|...#.|...#.|#..#.|.##..",
    "K": "#...#|#..#.|###..|#..#.|#...#", "L": "#....|#....|#....|#....|#####",
    "M": "#...#|##.##|#.#.#|#...#|#...#", "N": "#...#|##..#|#.#.#|#..##|#...#",
    "O": ".###.|#...#|#...#|#...#|.###.", "P": "####.|#...#|####.|#....|#....",
    "Q": ".###.|#...#|#.#.#|#..#.|.##.#", "R": "####.|#...#|####.|#..#.|#...#",
    "S": ".####|#....|.###.|....#|####.", "T": "#####|..#..|..#..|..#..|..#..",
    "U": "#...#|#...#|#...#|#...#|.###.", "V": "#...#|#...#|#...#|.#.#.|..#..",
    "W": "#...#|#...#|#.#.#|##.##|#...#", "X": "#...#|.#.#.|..#..|.#.#.|#...#",
    "Y": "#...#|.#.#.|..#..|..#..|..#..", "Z": "#####|...#.|..#..|.#...|#####",
    "0": ".###.|#..##|#.#.#|##..#|.###.", "1": ".##..|..#..|..#..|..#..|.###.",
    "2": "####.|....#|.###.|#....|#####", "3": "####.|....#|.###.|....#|####.",
    "4": "#..#.|#..#.|#####|...#.|...#.", "5": "#####|#....|####.|....#|####.",
    "6": ".###.|#....|####.|#...#|.###.", "7": "#####|....#|...#.|..#..|..#..",
    "8": ".###.|#...#|.###.|#...#|.###.", "9": ".###.|#...#|.####|....#|.###.",
    "_": ".....|.....|.....|.....|#####", "-": ".....|.....|.###.|.....|.....",
}


def draw_text(img, text, x, y, scale=2, value=1.0):
    for ch in text.upper():
        glyph = FONT.get(ch)
        if glyph:
            for gy, row in enumerate(glyph.split("|")):
                for gx, bit in enumerate(row):
                    if bit == "#":
                        y0, x0 = y + gy * scale, x + gx * scale
                        img[y0:y0 + scale, x0:x0 + scale, :3] = value
        x += 6 * scale


def preview(rgba, size):
    """Premultiplied box-downsample so the texture fits in size x size."""
    h, w = rgba.shape[:2]
    f = max(1, max(h, w) // size)
    pre = rgba.copy()
    pre[..., :3] *= pre[..., 3:4]
    return pre.reshape(h // f, f, w // f, f, 4).mean(axis=(1, 3))


def contact_sheet(textures):
    cols, cell, label, pad, header = 5, 256, 34, 12, 40
    rows = math.ceil(len(textures) / cols)
    sec_w = pad + cols * (cell + pad)
    sec_h = header + rows * (cell + label + pad) + pad
    sheet = np.zeros((sec_h * 2, sec_w, 4), np.float32)
    sheet[..., 3] = 1.0
    for s, (bg, title) in enumerate([(0.0, "ON BLACK"), (0.5, "ON MID GREY")]):
        y0 = s * sec_h
        sheet[y0:y0 + sec_h, :, :3] = bg
        sheet[y0:y0 + header - 4, :, :3] = 0.12
        draw_text(sheet, "VFX TEXTURES BATCH 1 - " + title, pad, y0 + 13)
        for i, (name, rgba) in enumerate(textures):
            row, col = divmod(i, cols)
            x = pad + col * (cell + pad)
            y = y0 + header + row * (cell + label + pad)
            pre = preview(rgba, cell)
            ph, pw = pre.shape[:2]
            oy, ox = y + (cell - ph) // 2, x + (cell - pw) // 2
            under = sheet[oy:oy + ph, ox:ox + pw, :3]
            sheet[oy:oy + ph, ox:ox + pw, :3] = under * (1.0 - pre[..., 3:4]) + pre[..., :3]
            sheet[y + cell:y + cell + label, x:x + cell, :3] = 0.12
            h, w = rgba.shape[:2]
            draw_text(sheet, name[4:], x + 4, y + cell + 5)
            draw_text(sheet, f"{w}x{h} {NOTES.get(name, '')}", x + 4, y + cell + 19, value=0.7)
    return sheet


# ---------------------------------------------------------------- output

def output_dir():
    override = OUT_DIR_OVERRIDE or os.environ.get("VFX_TEXTURES_OUT", "")
    if override:
        return Path(override)
    candidates = []
    if "__file__" in globals():
        candidates.append(__file__)
    for text in bpy.data.texts:
        if text.filepath:
            candidates.append(bpy.path.abspath(text.filepath))
    for cand in candidates:
        p = Path(cand)
        if p.name == "vfx_textures.py" and p.is_file():
            return p.resolve().parents[2] / "assets" / "vfx" / "textures"
    raise RuntimeError("Open scripts/blender/vfx_textures.py from disk (Text > Open), then Run Script.")


def save_png(path, rgba):
    h, w = rgba.shape[:2]
    img = bpy.data.images.new(path.stem, w, h, alpha=True)
    img.alpha_mode = "STRAIGHT"
    # Blender stores rows bottom-up.
    img.pixels.foreach_set(np.ascontiguousarray(rgba[::-1], dtype=np.float32).ravel())
    img.filepath_raw = str(path)
    img.file_format = "PNG"
    img.save()
    bpy.data.images.remove(img)


def main():
    out = output_dir()
    out.mkdir(parents=True, exist_ok=True)
    made = []
    for name, build in TEXTURES:
        rgba = build()
        save_png(out / f"{name}.png", rgba)
        made.append((name, rgba))
        print(f"[vfx] {name}.png {rgba.shape[1]}x{rgba.shape[0]}")
    save_png(out / "contact_sheet.png", contact_sheet(made))
    print(f"[vfx] done: {len(made)} textures + contact_sheet.png in {out}")


main()
