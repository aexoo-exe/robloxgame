"""
VFX kit, batch 2: shared helpers for vfx_flipbooks.py, vfx_textures_b2.py and vfx_batch2_sheet.py.

Reuses batch 1's helpers (vfx_textures.py: coordinates, smoothstep, signed-distance fill, noise,
the pixel font, PNG saving) and adds colored output (fire, dust, water, ink and shadow bake their
own colors), Random-mode flipbooks (one independent frame per cell) and polyline distances for
bolts. Everything is deterministic (fixed seeds).
"""

import math
import sys
from pathlib import Path

import numpy as np

HERE = Path(__file__).resolve().parent
if str(HERE) not in sys.path:
    sys.path.insert(0, str(HERE))

import vfx_textures as b1  # noqa: E402  (batch 1 helpers; its main() only runs as __main__)

coords, ss, fill, glow, union, border_fade = b1.coords, b1.ss, b1.fill, b1.glow, b1.union, b1.border_fade
vnoise, fbm, save_png, draw_text, preview = b1.vnoise, b1.fbm, b1.save_png, b1.draw_text, b1.preview
TAU = b1.TAU

ROOT = HERE.parents[1]
OUT = ROOT / "assets" / "vfx" / "src_b2"
PREVIEW = ROOT / "assets" / "vfx" / "preview"


def rgb(r, g, b):
    return np.array([r, g, b], np.float32) / 255.0


def finish_rgb(col, a):
    """(H, W, 3) or broadcastable color plus alpha -> RGBA. Invisible pixels keep the nearest
    visible color family (no white or black fringe when filtered)."""
    a = np.clip(a, 0.0, 1.0).astype(np.float32)
    col = np.clip(np.broadcast_to(col, a.shape + (3,)), 0.0, 1.0).astype(np.float32)
    return np.dstack([col, a]).astype(np.float32)


def finish_any(c, a):
    """Gray (scalar or HxW) or color (HxWx3) value."""
    if np.ndim(c) == 3:
        return finish_rgb(c, a)
    return b1.finish(c, a)


def ramp(t, stops):
    """Color ramp: stops = [(pos, rgb array), ...] sorted by pos; t is HxW in [0, 1]."""
    t = np.clip(t, 0.0, 1.0)[..., None]
    out = np.broadcast_to(stops[0][1], t.shape[:-1] + (3,)).astype(np.float32).copy()
    for (p0, c0), (p1, c1) in zip(stops, stops[1:]):
        k = np.clip((t - p0) / max(p1 - p0, 1e-6), 0.0, 1.0)
        out = np.where(t >= p0, c0 * (1.0 - k) + c1 * k, out)
    return out


def bands(x, steps, soft=0.035):
    """Soft posterize: x in [0, 1] into `steps` flat bands (the chunky anime look)."""
    out = np.zeros_like(x)
    for k in range(1, steps):
        out = out + ss(k / steps - soft, k / steps + soft, x)
    return out / (steps - 1)


def square(fn, w):
    X, Y = coords(w)
    c, a = fn(X, Y, 2.0 / w)
    return finish_any(c, a * border_fade(X, Y, 2.0 / w))


def rect(fn, w, h):
    """Non-square texture (streaks): X in [-1, 1] across the width, Y scaled by h / w."""
    xs = (np.arange(w, dtype=np.float32) + 0.5) / w * 2.0 - 1.0
    ys = (1.0 - (np.arange(h, dtype=np.float32) + 0.5) / h * 2.0) * (h / w)
    X, Y = np.meshgrid(xs, ys)
    px = 2.0 / w
    c, a = fn(X, Y, px)
    edge = 1.0 - ss(1.0 - 8 * px, 1.0 - 4 * px, np.abs(X))
    edge = edge * (1.0 - ss((h / w) - 8 * px, (h / w) - 4 * px, np.abs(Y)))
    return finish_any(c, a * edge)


def flipbook(fn, mode, size=1024, grid=4):
    """Square atlas, frames left to right, top to bottom. `fn(X, Y, px, t, i)`: t runs 0..1
    (OneShot: last frame is t = 1; Loop: wraps), i is the frame index (Random: independent)."""
    cell = size // grid
    X, Y = coords(cell)
    fade = border_fade(X, Y, 2.0 / cell)
    frames = grid * grid
    sheet = np.zeros((size, size, 4), np.float32)
    for i in range(frames):
        t = i / frames if mode == "Loop" else i / (frames - 1)
        c, a = fn(X, Y, 2.0 / cell, t, i)
        row, col = divmod(i, grid)
        sheet[row * cell:(row + 1) * cell, col * cell:(col + 1) * cell] = finish_any(c, a * fade)
    return sheet


def seg_distance(X, Y, points, widths):
    """Distance to a polyline (points: list of (x, y)), minus a width tapering per point.
    Returns (signed distance, distance along normalized 0..1)."""
    sd = np.full_like(X, 10.0)
    along = np.zeros_like(X)
    lengths = [math.hypot(points[i + 1][0] - points[i][0], points[i + 1][1] - points[i][1])
               for i in range(len(points) - 1)]
    total = max(sum(lengths), 1e-6)
    start = 0.0
    for i in range(len(points) - 1):
        (x0, y0), (x1, y1) = points[i], points[i + 1]
        dx, dy = x1 - x0, y1 - y0
        L2 = max(dx * dx + dy * dy, 1e-9)
        t = np.clip(((X - x0) * dx + (Y - y0) * dy) / L2, 0.0, 1.0)
        w = widths[i] + (widths[i + 1] - widths[i]) * t
        d = np.hypot(X - (x0 + t * dx), Y - (y0 + t * dy)) - w
        closer = d < sd
        sd = np.where(closer, d, sd)
        along = np.where(closer, (start + t * lengths[i]) / total, along)
        start += lengths[i]
    return sd, along


def jagged(rng, a, b, depth, jitter):
    """Midpoint-displaced polyline from a to b (2^depth segments)."""
    pts = [a, b]
    amp = jitter * math.hypot(b[0] - a[0], b[1] - a[1])
    for _ in range(depth):
        nxt = [pts[0]]
        for p, q in zip(pts, pts[1:]):
            mx, my = (p[0] + q[0]) / 2.0, (p[1] + q[1]) / 2.0
            dx, dy = q[0] - p[0], q[1] - p[1]
            L = max(math.hypot(dx, dy), 1e-6)
            off = rng.uniform(-1.0, 1.0) * amp
            nxt += [(mx - dy / L * off, my + dx / L * off), q]
        pts = nxt
        amp *= 0.55
    return pts


def check_border(name, rgba, grid=1, margin=4, ends_touch=False):
    h, w = rgba.shape[0] // grid, rgba.shape[1] // grid
    worst = 0.0
    for row in range(grid):
        for col in range(grid):
            a = rgba[row * h:(row + 1) * h, col * w:(col + 1) * w, 3]
            edges = [a[:margin], a[-margin:]]
            if not ends_touch:
                edges += [a[:, :margin], a[:, -margin:]]
            worst = max(worst, max(float(e.max()) for e in edges))
    if worst >= 1.0 / 255.0:
        print(f"[vfx-b2] WARNING {name}: alpha {worst:.3f} within {margin}px of the border")


def write(name, rgba, grid=1, ends_touch=False):
    OUT.mkdir(parents=True, exist_ok=True)
    assert max(rgba.shape[:2]) <= 1024, name + " is larger than 1024"
    check_border(name, rgba, grid, ends_touch=ends_touch)
    save_png(OUT / f"{name}.png", rgba)
    print(f"[vfx-b2] {name}.png {rgba.shape[1]}x{rgba.shape[0]}")
