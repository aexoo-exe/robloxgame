"""
VFX kit, batch 2: animated flipbooks (square atlases for ParticleEmitter.FlipbookLayout).

Headless: tools/blender-*/blender.exe -b -P scripts/blender/vfx_flipbooks.py
Writes assets/vfx/src_b2/fx_*.png. Procedural (numpy, fixed seeds): fast and deterministic.

Grid4x4 (16 frames of 256 px) for all of them. Tint rule: lightning, crackle and the impact star
are white with a hot core (ParticleEmitter.Color tints them); fire, steam, dust, water and the
cartoon poof bake their own colors. Style: anime 2D FX, bold shapes, a hard core inside a softer
glow, a few chunky bands instead of mush. Modes and frame rates are recorded in FLIPBOOKS below
(and in src/shared/VfxConfig.luau traits).

Skipped as already covered by batch 1 (assets/vfx/textures): a looping flame (vfx_fire_flipbook,
Loop, tinted by the effect's palette) and a smoke billow (vfx_smoke_flipbook, OneShot, gray and
tintable, so also the toxic mist).
"""

import math
import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))

from vfx_b2_common import (  # noqa: E402
    TAU, bands, fbm, fill, flipbook, glow, jagged, ramp, rgb, seg_distance, ss, union, write,
)


def ease_out(t):
    return 1.0 - (1.0 - t) ** 2


# ---------------------------------------------------------------- fire burst (baked colors)

FIRE_STOPS = [
    (0.0, rgb(120, 22, 12)),   # dark red edge
    (0.3, rgb(235, 85, 20)),   # orange body
    (0.62, rgb(255, 190, 55)),  # yellow
    (0.85, rgb(255, 245, 205)),  # white-hot
    (1.0, rgb(255, 255, 240)),
]
SMOKE = rgb(58, 52, 50)


def fire_burst(X, Y, px, t, i):
    """White-yellow flash -> orange fireball with dark red edges -> breaks into dark smoke."""
    r = np.hypot(X, Y)
    R = 0.34 + 0.52 * ease_out(min(1.0, t * 1.4))
    n = fbm((X / R + 2.0) * 1.6, (Y / R + 2.0) * 1.6 - 1.4 * t, 121, period=8, octaves=4)
    # Chunky lobes: a few big bulges around the rim.
    lobes = 0.12 * np.cos(5.0 * np.arctan2(Y, X) + 1.3) * (0.4 + t)
    dens = 1.0 - r / R + (n - 0.5) * (0.55 + 0.8 * t) + lobes * (r / R)
    thr = 0.02 + 0.62 * t ** 1.5
    a = ss(thr - 0.02, thr + 0.06, dens)
    heat = ss(thr, thr + 0.5, dens) * (1.0 - ss(0.15, 0.8, t))
    heat = bands(heat, 4)
    col = ramp(heat, FIRE_STOPS)
    # Cooling: edges go to smoke as the fireball breaks up.
    smoke_k = ss(0.35, 0.8, t) * (1.0 - heat)
    col = col * (1.0 - smoke_k[..., None]) + SMOKE * smoke_k[..., None]
    # The opening flash: a hard white disc in a soft glow.
    flash = 1.0 - ss(0.0, 0.22, t)
    disc = fill(r - (0.22 + 0.3 * t), px) * flash
    soft = 0.75 * flash * np.exp(-2.5 * (r / 0.6) ** 2)
    top = np.clip(disc + soft, 0.0, 1.0)
    col = col * (1.0 - top[..., None]) + rgb(255, 252, 235) * top[..., None]
    a = np.clip(a + top * (1.0 - a), 0.0, 1.0)
    return col, a * (1.0 - ss(0.62, 1.0, t))


# ---------------------------------------------------------------- steam billow (baked white)

def _blobs(seed, count, spread):
    rng = np.random.default_rng(seed)
    out = []
    for k in range(count):
        ang = rng.uniform(0.0, TAU)
        d = rng.uniform(0.0, spread) if k else 0.0
        out.append((math.cos(ang) * d, math.sin(ang) * d * 0.75, rng.uniform(0.26, 0.36)))
    return out


STEAM_BLOBS = _blobs(140, 9, 0.3)


def steam_billow(X, Y, px, t, i):
    """A dense white steam wall puff: solid body, soft rolled edge, thins and fades."""
    zoom = 0.78 - 0.24 * ease_out(t)
    x, y = X * zoom, (Y - 0.08 * t) * zoom
    dens = np.full_like(X, -1.0)
    for bx, by, br in STEAM_BLOBS:
        dens = np.maximum(dens, 1.0 - np.hypot(x - bx, y - by) / br)
    n = fbm((x + 1.0) * 2.4, (y + 1.0) * 2.4 - 0.8 * t, 141, period=8, octaves=4)
    dens = dens + (n - 0.5) * 0.7
    thr = -0.05 + 0.45 * t ** 1.4
    a = ss(thr - 0.12, thr + 0.35, dens) * (0.95 - 0.25 * t)
    # Lit from the top: brighter crowns, cool gray underside.
    lit = ss(-0.6, 0.6, Y + 0.3 * (n - 0.5))
    shade = 0.8 + 0.2 * bands(lit, 3)
    col = np.dstack([shade * 0.98, shade * 0.99, shade])
    return col, a * (1.0 - ss(0.55, 1.0, t))


# ---------------------------------------------------------------- lightning (white, Random)

def bolt_frame(seed, short=False):
    rng = np.random.default_rng(seed)
    if short:
        # Crackle: 2-3 short arcs anywhere in the cell.
        arcs = []
        for _ in range(rng.integers(2, 4)):
            cx, cy = rng.uniform(-0.45, 0.45, 2)
            ang = rng.uniform(0.0, TAU)
            L = rng.uniform(0.35, 0.7)
            a = (cx - math.cos(ang) * L / 2, cy - math.sin(ang) * L / 2)
            b = (cx + math.cos(ang) * L / 2, cy + math.sin(ang) * L / 2)
            arcs.append((jagged(rng, a, b, 3, 0.35), 0.022))
        return arcs
    top = (rng.uniform(-0.25, 0.25), 0.86)
    bottom = (rng.uniform(-0.3, 0.3), -0.86)
    main = jagged(rng, top, bottom, 5, 0.22)
    arcs = [(main, 0.04)]
    for _ in range(rng.integers(1, 4)):
        k = rng.integers(4, len(main) - 6)
        p = main[k]
        side = rng.choice([-1.0, 1.0])
        end = (np.clip(p[0] + side * rng.uniform(0.25, 0.5), -0.8, 0.8), p[1] - rng.uniform(0.2, 0.45))
        arcs.append((jagged(rng, p, end, 3, 0.3), 0.022))
    return arcs


def lightning_draw(X, Y, px, arcs):
    layers = []
    for pts, w in arcs:
        widths = [w * (1.0 - 0.6 * k / (len(pts) - 1)) for k in range(len(pts))]
        sd, _ = seg_distance(X, Y, pts, widths)
        core = fill(sd + w * 0.45, px)  # thick white core
        body = fill(sd, px)
        layers += [(1.0, core), (0.86, body * 0.85), (1.0, glow(sd, 0.05, 0.45)), (1.0, glow(sd, 0.12, 0.18))]
    return union(*layers)


def lightning(X, Y, px, t, i):
    return lightning_draw(X, Y, px, bolt_frame(500 + i))


def crackle(X, Y, px, t, i):
    return lightning_draw(X, Y, px, bolt_frame(600 + i, short=True))


# ---------------------------------------------------------------- impact star (white)

STAR_RNG = np.random.default_rng(170)
STAR_POINTS = 6
STAR_ANGS = (np.arange(STAR_POINTS) + STAR_RNG.uniform(-0.15, 0.15, STAR_POINTS)) * TAU / STAR_POINTS
STAR_LENS = np.where(np.arange(STAR_POINTS) % 2 == 0, 1.0, 0.68)
LINE_ANGS = STAR_RNG.uniform(0.0, TAU, 12)
LINE_SPEED = STAR_RNG.uniform(0.8, 1.2, 12)


def impact_star(X, Y, px, t, i):
    """A fast hit flash: a 6-point star pops, thins and shrinks; spark lines race outward."""
    r = np.hypot(X, Y)
    th = np.arctan2(Y, X)
    grow = ease_out(min(1.0, t * 3.0))
    shrink = 1.0 - ss(0.35, 1.0, t)
    size = 0.78 * grow * (0.55 + 0.45 * shrink)
    R = np.full_like(r, 0.14 * shrink + 0.02)
    for ang, L in zip(STAR_ANGS, STAR_LENS):
        dth = np.abs((th - ang + math.pi) % TAU - math.pi)
        R = np.maximum(R, size * L * (1.0 - dth / (0.42 * (0.4 + 0.6 * shrink))))
    star = fill(r - R, px * 1.5)
    inner = fill(r - R * 0.5, px * 1.5)
    layers = [(1.0, inner), (0.9, star * 0.9), (1.0, glow(r - R, 0.06, 0.35 * shrink))]
    for ang, sp in zip(LINE_ANGS, LINE_SPEED):
        head = 0.25 + 0.65 * ease_out(min(1.0, t * 1.6)) * sp
        tail = head - 0.22 * (1.0 - t)
        along = X * math.cos(ang) + Y * math.sin(ang)
        perp = np.abs(-X * math.sin(ang) + Y * math.cos(ang))
        k = np.clip((along - tail) / max(head - tail, 1e-3), 0.0, 1.0) * (along <= head) * (along >= tail)
        sd = np.where(k > 0, perp - 0.014 * k, 1.0)
        layers.append((1.0, fill(sd, px) * (1.0 - ss(0.5, 1.0, t))))
    c, a = union(*layers)
    return c, a * (1.0 - ss(0.75, 1.0, t))


# ---------------------------------------------------------------- dust burst (baked tan-gray)

DUST_LIGHT = rgb(214, 196, 166)
DUST_DARK = rgb(132, 120, 104)


# Round billows on a low dome: (x -1..1 across, height 0..1, radius), bottom row widest.
DUST_BILLOWS = [
    (-0.86, 0.1, 0.19), (-0.44, 0.08, 0.22), (0.0, 0.1, 0.23), (0.44, 0.08, 0.22), (0.86, 0.1, 0.19),
    (-0.5, 0.42, 0.24), (0.02, 0.45, 0.27), (0.5, 0.4, 0.24),
    (-0.18, 0.75, 0.24), (0.22, 0.78, 0.23),
]
DUST_BASE = -0.84


def dust_burst(X, Y, px, t, i):
    """A ground dust kick: round puffy billows rolling up and out from the ground, filling the cell
    by frame 8, then thinning away; soft edges, tan on top, darker toward the base."""
    grow = ease_out(min(1.0, t * 1.9))  # full size by ~frame 8
    spread = 0.3 + 0.7 * grow
    lift = 0.2 + 0.8 * grow
    dens = np.full_like(X, -1.0)
    for bx, by, br in DUST_BILLOWS:
        cx = bx * 0.66 * spread
        cy = DUST_BASE + 0.12 + by * 1.25 * lift
        r = br * (0.45 + 0.75 * grow)
        dens = np.maximum(dens, 1.0 - np.hypot(X - cx, Y - cy) / r)
    # Gentle, low-frequency noise: rounder billows, no hard bumps.
    n = fbm((X + 2.0) * 1.8, (Y + 2.0) * 1.8 - 0.6 * t, 181, period=8, octaves=3)
    dens = dens + (n - 0.5) * 0.3
    thr = 0.02 + 0.55 * ss(0.45, 1.0, t)
    a = ss(thr - 0.04, thr + 0.32, dens) * (0.92 - 0.15 * t)
    # Lit from above (rounded billow tops), darker toward the ground.
    top_light = ss(-0.3, 0.6, dens + 0.6 * (Y - DUST_BASE) - 0.3)
    base_dark = ss(DUST_BASE, DUST_BASE + 0.45, Y)
    lit = np.clip(0.25 + 0.75 * top_light * base_dark, 0.0, 1.0)
    col = DUST_DARK + (DUST_LIGHT - DUST_DARK) * lit[..., None]
    return col, a * (1.0 - ss(0.7, 1.0, t))


# ---------------------------------------------------------------- water splash (baked white-blue)

WATER_CORE = rgb(245, 252, 255)
WATER_EDGE = rgb(95, 165, 230)
DROPS = np.random.default_rng(190).uniform(0.0, 1.0, (14, 3))


WATER_BASE = -0.84


def water_splash(X, Y, px, t, i):
    """A tall crown splash filling the cell at its peak: it starts as a small splash, the crown's
    spikes shoot up and fall back, big droplets fly up and out. No flat ring on the floor."""
    rise = (0.18 + 0.82 * math.sin(math.pi * min(1.0, t / 0.85))) * (1.0 - 0.6 * ss(0.7, 1.0, t))
    width = 0.3 + 0.52 * ease_out(min(1.0, t * 2.0))
    # The crown on the front of the water ring (three quarters): a thin wall of spikes, tallest in
    # the middle; between the spikes only a narrow lip.
    across = np.clip(X / width, -1.0, 1.0)
    front = WATER_BASE + 0.1 - 0.08 * np.sqrt(1.0 - across * across)
    h = Y - front
    spikes = 9
    f = (X / width * spikes / 2.0) % 1.0
    tip = np.clip(1.0 - np.abs(f - 0.5) * 2.0, 0.0, 1.0) ** 1.6
    height = 0.05 + 1.35 * rise * tip * (1.0 - 0.55 * across ** 2)
    sd = np.maximum(np.maximum(h - height, -h - 0.04), np.abs(X) - width)
    body = fill(sd, px)
    layers = [body]
    # Big droplets thrown up and out on parabolas from the crown's tips.
    for k in range(len(DROPS)):
        side = (DROPS[k, 0] - 0.5) * 2.0
        vx = side * (0.6 + 0.5 * DROPS[k, 1])
        vy = 1.9 + 0.8 * DROPS[k, 2]
        size = 0.04 + 0.04 * DROPS[k, 1]
        dt = max(0.0, t - 0.06)
        dx = vx * dt
        dy = vy * dt - 2.6 * dt * dt
        cy = WATER_BASE + 0.2 + dy
        # Stretched along the motion a little: a teardrop streak.
        stretch = 1.0 + 1.5 * abs(vy - 5.2 * dt)
        d = np.hypot((X - dx) / 1.0, (Y - cy) / stretch * 1.0) - size * (1.0 - 0.4 * t)
        layers.append(fill(d, px) * (t > 0.04))
    a = np.maximum.reduce(layers)
    # Color: white crests and drops, blue body low in the crown.
    crest = ss(0.0, 0.5, h)
    col = WATER_EDGE + (WATER_CORE - WATER_EDGE) * bands(crest, 3)[..., None]
    drops = np.maximum.reduce(layers[1:]) if len(layers) > 1 else np.zeros_like(X)
    col = col + (WATER_CORE - col) * drops[..., None] * 0.8
    return col, a * (1.0 - ss(0.8, 1.0, t))


# ---------------------------------------------------------------- toon poof (white, ink outline)

POOF = [(0.0, 0.0, 0.34), (-0.3, -0.08, 0.24), (0.31, -0.06, 0.25), (-0.14, 0.26, 0.22),
        (0.18, 0.24, 0.23), (-0.38, 0.18, 0.15), (0.4, 0.2, 0.15)]


def toon_poof(X, Y, px, t, i):
    """A cartoon cloud puff: pops big with an ink outline, then splits into little puffs and
    dissipates."""
    pop = ease_out(min(1.0, t * 3.0)) * (1.0 + 0.12 * math.sin(math.pi * min(1.0, t * 3.0)))
    shrink = 1.0 - ss(0.45, 1.0, t)
    spread = 1.0 + 0.6 * ss(0.3, 1.0, t)
    sd = np.full_like(X, 10.0)
    for bx, by, br in POOF:
        sd = np.minimum(sd, np.hypot(X - bx * spread, Y - by * spread) - br * pop * (0.35 + 0.65 * shrink))
    # Breaking up: noise erodes the puffs at the end.
    n = fbm((X + 2.0) * 3.0, (Y + 2.0) * 3.0, 201, period=8, octaves=3)
    sd = sd + ss(0.5, 1.0, t) * (n - 0.3) * 0.25
    inside = fill(sd, px * 1.2)
    outline = fill(np.abs(sd + 0.012) - 0.012, px * 1.2)
    shade = 0.86 + 0.14 * ss(-0.3, 0.3, Y + sd * 2.0)  # a soft lit top
    c = np.where(outline > 0.5, 0.28, shade)
    a = np.maximum(inside * 0.97, outline)
    return c, a * (1.0 - ss(0.8, 1.0, t))


# ---------------------------------------------------------------- list

# name -> (frame function, mode, fps); all Grid4x4 (16 frames, 256 px).
FLIPBOOKS = [
    ("fx_fire_burst", fire_burst, "OneShot", 24),
    ("fx_steam_billow", steam_billow, "OneShot", 20),
    ("fx_lightning", lightning, "Random", 30),
    ("fx_crackle", crackle, "Random", 30),
    ("fx_impact_star", impact_star, "OneShot", 30),
    ("fx_dust_burst", dust_burst, "OneShot", 20),
    ("fx_water_splash", water_splash, "OneShot", 24),
    ("fx_toon_poof", toon_poof, "OneShot", 24),
]


def main():
    only = set(sys.argv[sys.argv.index("--") + 1:]) if "--" in sys.argv else set()
    for name, fn, mode, fps in FLIPBOOKS:
        if only and name not in only:
            continue
        rgba = flipbook(fn, mode)
        write(name, rgba, grid=4)
        print(f"[vfx-b2]   Grid4x4 {mode} {fps} fps")


if __name__ == "__main__":
    main()
