"""
VFX kit, batch 2: review contact sheet.

Headless: tools/blender-*/blender.exe -b -P scripts/blender/vfx_batch2_sheet.py
Reads assets/vfx/src_b2/fx_*.png and writes assets/vfx/preview/batch2_sheet.png: one row per
texture, labeled, drawn over a mid-gray tile and a dark tile; flipbooks show frame 1, the middle
frame and the last frame on each.
"""

import sys
from pathlib import Path

import bpy
import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))

from vfx_b2_common import OUT, PREVIEW, draw_text, preview, save_png  # noqa: E402
from vfx_flipbooks import FLIPBOOKS  # noqa: E402

TILE, GAP, LABEL_W, ROW_PAD = 128, 6, 230, 14
BACKGROUNDS = (0.5, 0.08)  # mid-gray, dark


def load(path):
    img = bpy.data.images.load(str(path))
    w, h = img.size
    px = np.empty(w * h * 4, np.float32)
    img.pixels.foreach_get(px)
    bpy.data.images.remove(img)
    return px.reshape(h, w, 4)[::-1].copy()


def frames(rgba, grid, picks):
    cell = rgba.shape[0] // grid
    out = []
    for i in picks:
        row, col = divmod(i, grid)
        out.append(rgba[row * cell:(row + 1) * cell, col * cell:(col + 1) * cell])
    return out


def paste(sheet, rgba, x, y, bg):
    sheet[y:y + TILE, x:x + TILE, :3] = bg
    pre = preview(rgba, TILE)
    ph, pw = pre.shape[:2]
    oy, ox = y + (TILE - ph) // 2, x + (TILE - pw) // 2
    under = sheet[oy:oy + ph, ox:ox + pw, :3]
    sheet[oy:oy + ph, ox:ox + pw, :3] = under * (1.0 - pre[..., 3:4]) + pre[..., :3]


def main():
    modes = {name: (mode, fps) for name, _, mode, fps in FLIPBOOKS}
    names = sorted(p.stem for p in OUT.glob("fx_*.png"))
    row_h = TILE + ROW_PAD
    width = LABEL_W + 6 * (TILE + GAP) + GAP
    height = 44 + len(names) * row_h
    sheet = np.zeros((height, width, 4), np.float32)
    sheet[..., 3] = 1.0
    sheet[..., :3] = 0.16
    draw_text(sheet, "VFX BATCH 2 - MID GREY / DARK", 10, 14, scale=3)
    for i, name in enumerate(names):
        rgba = load(OUT / f"{name}.png")
        y = 44 + i * row_h
        h, w = rgba.shape[:2]
        draw_text(sheet, name[3:], 10, y + 10)
        if name in modes:
            mode, fps = modes[name]
            tiles = frames(rgba, 4, (0, 7, 15))
            draw_text(sheet, f"4X4 {mode} {fps}FPS", 10, y + 26, value=0.7)
            draw_text(sheet, "FRAMES 1 8 16", 10, y + 42, value=0.7)
        else:
            tiles = [rgba]
            draw_text(sheet, f"{w}X{h}", 10, y + 26, value=0.7)
        x = LABEL_W
        for bg in BACKGROUNDS:
            for tile in tiles:
                paste(sheet, tile, x, y, bg)
                x += TILE + GAP
            if len(tiles) == 1:
                x += 2 * (TILE + GAP)
    PREVIEW.mkdir(parents=True, exist_ok=True)
    save_png(PREVIEW / "batch2_sheet.png", sheet)
    print(f"[vfx-b2] contact sheet: {PREVIEW / 'batch2_sheet.png'} ({width}x{height}, {len(names)} textures)")


if __name__ == "__main__":
    main()
