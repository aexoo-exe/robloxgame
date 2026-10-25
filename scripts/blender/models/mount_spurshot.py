"""mount_spurshot: the pilot creature model (docs/design/creature-models.md), v2.

A stylized low-poly horse made of lofted cross-sections (one continuous barrel, an arched neck, a
shaped head, legs with knee / hock bulges, a flowing tail, mane tufts), one mesh with one palette
material (a 512x512 texture: flat color swatches, a star tile for the bedroll, and painted coat
tiles with round leopard spots for the barrel, neck and legs), a simple skeleton with per-ring
skinning (blended at the joints), three animations (idle, gallop loop, rear-up), an optional
inverted-hull outline mesh, FBX export and review renders.

Run headless from the repository root:
  tools/blender-4.2.3-windows-x64/blender.exe -b --factory-startup --python scripts/blender/models/mount_spurshot.py

Writes:
  assets/models/mount_spurshot.fbx            mesh + outline mesh + armature + 3 animations (tracked)
  assets/models/mount_spurshot_palette.png    the palette texture (tracked)
  docs/references/models/review/mount_spurshot_*_v2.png   review renders (gitignored)
"""

import math
import os
import random

import bpy
import bmesh
import numpy as np
from mathutils import Euler, Vector

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
ASSETS = os.path.join(ROOT, "assets", "models")
REVIEW = os.path.join(ROOT, "docs", "references", "models", "review")
NAME = "mount_spurshot"
SUFFIX = "_v2_1"
FULL_RENDERS = False  # also the rig and animation strips (v2.1 re-renders the turntable and match distance)
FPS = 30
OUTLINE = 0.03  # inverted-hull thickness (studs)
SIZE = 512
random.seed(21)

# Scale (v2.1): sized to its rider, an R6 unit 4.6 studs tall: the withers at 0.9x the rider's height
# and nose to rump 1.5x. The model is authored small (withers 3.88), then placed after skinning
# (`place`): the body and neck scale by KX / KY / KZ (longer than tall), while the head, legs and
# tail scale evenly by KZ about where they join, so they keep their authored shape.
RIDER_HEIGHT = 4.6
AUTHORED_WITHERS = 3.88
AUTHORED_POLL_Y, AUTHORED_NOSE_Y, AUTHORED_RUMP_Y = -2.08, -3.0, 1.95
KZ = 0.9 * RIDER_HEIGHT / AUTHORED_WITHERS
KX = KZ
KY = (1.5 * RIDER_HEIGHT - (AUTHORED_POLL_Y - AUTHORED_NOSE_Y) * KZ) / (AUTHORED_RUMP_Y - AUTHORED_POLL_Y)
RATIO = KY / KZ

# The saddle seat's top (authored), where a rider's hips go: the "seat" bone's head.
SEAT_AUTHORED = Vector((0, -0.13, 3.89))


def scaled(p):
    return Vector((p[0] * KX, p[1] * KY, p[2] * KZ))

# -------------------------------------------------------------------------------------------------
# Palette (512x512): swatches top-left (8x8 of 32 px), star tile top-right, coat tiles at the
# bottom: barrel (x 0-384), legs (x 384-448), neck (x 448-512). Blender image rows start at the bottom.
# -------------------------------------------------------------------------------------------------

def srgb(r, g, b):
    return (r / 255, g / 255, b / 255, 1.0)

SWATCHES = {
    "coat": srgb(236, 237, 240),
    "spot": srgb(74, 78, 88),
    "legshade": srgb(150, 153, 160),
    "mane": srgb(240, 224, 172),
    "maneshade": srgb(214, 194, 140),
    "hoof": srgb(58, 58, 64),
    "muzzle": srgb(122, 124, 132),
    "nostril": srgb(40, 40, 46),
    "eye": srgb(20, 20, 26),
    "earinner": srgb(205, 160, 160),
    "tack": srgb(176, 124, 72),
    "tackdark": srgb(112, 74, 42),
    "medallion": srgb(36, 64, 150),
    "blanket": srgb(138, 196, 232),
    "blankettrim": srgb(96, 150, 196),
    "saddle": srgb(118, 76, 44),
    "outline": srgb(22, 22, 30),
    "metal": srgb(200, 204, 214),
}
SWATCH_INDEX = {name: index for index, name in enumerate(SWATCHES)}
STAR_BG = srgb(150, 204, 236)
STAR_PINK = srgb(236, 120, 170)
STAR_WHITE = srgb(250, 250, 255)

TILE_BODY = (0, 0, 384, 256)  # x, y, w, h in pixels
TILE_LEG = (384, 0, 64, 256)
TILE_NECK = (448, 0, 64, 256)
TILE_STAR = (256, 256, 256, 256)


def swatch_uv(name):
    index = SWATCH_INDEX[name]
    col, row = index % 8, index // 8
    return ((col + 0.5) * 32 / SIZE, (SIZE - (row + 0.5) * 32) / SIZE)


def tile_uv(tile, u, v):
    """(u, v) in 0-1 inside a tile -> texture UV (inset a little)."""
    x, y, w, h = tile
    u = min(max(u, 0.002), 0.998)
    v = min(max(v, 0.002), 0.998)
    return ((x + u * w) / SIZE, (y + v * h) / SIZE)


def star_inside(px, py, cx, cy, radius):
    dx, dy = px - cx, py - cy
    r = math.hypot(dx, dy)
    if r > radius:
        return False
    angle = math.atan2(dy, dx) + math.pi / 2
    sector = (angle % (2 * math.pi / 5)) / (2 * math.pi / 5)
    return r <= radius * (0.45 + 0.55 * abs(sector - 0.5) * 2)


def paint_spots(pixels, tile, spots, px_per_u, px_per_v, wrap_u=False):
    """Irregular round blobs: (u, v, radius in studs, seed) in tile space; px_per_* converts studs to
    pixels along each axis so spots stay round on the body."""
    x0, y0, w, h = tile
    ys, xs = np.mgrid[0:h, 0:w]
    region = pixels[y0 : y0 + h, x0 : x0 + w]
    for u, v, radius, seed in spots:
        cx, cy = u * w, v * h
        dx = (xs - cx) / px_per_u
        if wrap_u:
            dx = np.minimum(np.abs(xs - cx), w - np.abs(xs - cx)) / px_per_u
        dy = (ys - cy) / px_per_v
        r = np.hypot(dx, dy)
        phi = np.arctan2(dy, dx)
        edge = radius * (1 + 0.22 * np.sin(3 * phi + seed) + 0.12 * np.sin(5 * phi + 2 * seed))
        region[r <= edge] = SWATCHES["spot"]


def make_palette():
    pixels = np.zeros((SIZE, SIZE, 4), dtype=np.float32)
    pixels[:, :] = SWATCHES["coat"]
    for name, color in SWATCHES.items():
        index = SWATCH_INDEX[name]
        col, row = index % 8, index // 8
        y0 = SIZE - (row + 1) * 32
        pixels[y0 : y0 + 32, col * 32 : (col + 1) * 32] = color
    # Star tile.
    x0, y0, w, h = TILE_STAR
    pixels[y0 : y0 + h, x0 : x0 + w] = STAR_BG
    stars = [(30, 40, 20, STAR_PINK), (110, 150, 18, STAR_WHITE), (190, 60, 20, STAR_PINK), (60, 210, 16, STAR_WHITE),
             (220, 200, 17, STAR_PINK), (150, 100, 13, STAR_WHITE), (20, 130, 13, STAR_WHITE), (240, 120, 13, STAR_PINK)]
    for y in range(h):
        for x in range(w):
            for cx, cy, radius, color in stars:
                if star_inside(x, y, cx, cy, radius):
                    pixels[y0 + y, x0 + x] = color
    # Barrel: u along the body (front 0 -> rump 1), v around (0 belly, 0.5 top, 1 belly). After the
    # stretch it is about 3.9 x KY studs long over 384 px and 4.4 x KZ studs around over 256 px.
    # Appaloosa spotting: many small, varied spots, densest over the hindquarters, two medium ones on
    # the rump; none on the belly (v near 0 / 1).
    spots = []

    def side_v():
        return random.choice([random.uniform(0.17, 0.42), random.uniform(0.58, 0.83)])

    for _ in range(13):  # hindquarters
        spots.append((random.uniform(0.6, 0.97), side_v(), random.uniform(0.07, 0.15), random.uniform(0, 6)))
    for _ in range(4):  # over the rump top
        spots.append((random.uniform(0.7, 0.95), random.uniform(0.42, 0.58), random.uniform(0.06, 0.12),
                      random.uniform(0, 6)))
    for _ in range(5):  # mid barrel, thinning toward the front
        spots.append((random.uniform(0.35, 0.6), side_v(), random.uniform(0.06, 0.11), random.uniform(0, 6)))
    for _ in range(2):  # shoulder
        spots.append((random.uniform(0.08, 0.3), side_v(), random.uniform(0.05, 0.09), random.uniform(0, 6)))
    for v in (0.3, 0.7):  # two medium ones on the rump
        spots.append((random.uniform(0.78, 0.88), v, random.uniform(0.2, 0.24), random.uniform(0, 6)))
    paint_spots(pixels, TILE_BODY, spots, 384 / (3.9 * KY), 256 / (4.4 * KZ))
    # Legs: u around, v up the leg (0 hoof -> 1 top). Darker toward the feet.
    x0, y0, w, h = TILE_LEG
    for y in range(h):
        v = y / h
        color = SWATCHES["spot"] if v < 0.2 else SWATCHES["legshade"] if v < 0.46 else SWATCHES["coat"]
        pixels[y0 + y, x0 : x0 + w] = color
    leg_spots = [(0.3, 0.74, 0.07, 1.0), (0.78, 0.62, 0.06, 3.0), (0.55, 0.4, 0.06, 4.0), (0.1, 0.55, 0.05, 5.0)]
    paint_spots(pixels, TILE_LEG, leg_spots, 64 / (1.3 * KZ), 256 / (2.9 * KZ), wrap_u=True)
    # Neck: u around, v along (0 base -> 1 head). A few small spots.
    neck_spots = [(0.25, 0.25, 0.07, 2.0), (0.7, 0.45, 0.06, 5.0), (0.4, 0.62, 0.05, 1.0)]
    paint_spots(pixels, TILE_NECK, neck_spots, 64 / 2.6, 256 / (1.6 * KZ), wrap_u=True)

    image = bpy.data.images.new(NAME + "_palette", SIZE, SIZE, alpha=False)
    image.pixels = pixels.flatten()
    image.filepath_raw = os.path.join(ASSETS, NAME + "_palette.png")
    image.file_format = "PNG"
    image.save()
    return image, (len(spots), len(leg_spots), len(neck_spots))


# -------------------------------------------------------------------------------------------------
# Building blocks
# -------------------------------------------------------------------------------------------------

PARTS = []  # (object, bone name or weights(world point) -> {bone: weight})


def new_object(name, bm):
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    return obj


def loft(name, rings, uv_of, cap_uv, cap_start=True, cap_end=True):
    """A closed tube through `rings` (lists of points, same count). uv_of(i, j) gives the UV of ring i,
    point j (j == len(ring) on the seam). Caps take `cap_uv`."""
    bm = bmesh.new()
    uv = bm.loops.layers.uv.new("UVMap")
    count = len(rings[0])
    verts = [[bm.verts.new(p) for p in ring] for ring in rings]
    index_of = {}
    for i, ring in enumerate(verts):
        for j, vert in enumerate(ring):
            index_of[vert] = (i, j)
    for i in range(len(rings) - 1):
        for j in range(count):
            bm.faces.new((verts[i][j], verts[i][(j + 1) % count], verts[i + 1][(j + 1) % count], verts[i + 1][j]))
    caps = []
    if cap_start:
        caps.append(bm.faces.new(list(reversed(verts[0]))))
    if cap_end:
        caps.append(bm.faces.new(verts[-1]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    cap_set = set(caps)
    for face in bm.faces:
        if face in cap_set:
            for loop in face.loops:
                loop[uv].uv = cap_uv
            continue
        js = [index_of[loop.vert][1] for loop in face.loops]
        wraps = (0 in js) and (count - 1 in js)
        for loop in face.loops:
            i, j = index_of[loop.vert]
            if wraps and j == 0:
                j = count
            loop[uv].uv = uv_of(i, j)
    return new_object(name, bm)


def ring_points(center, side, up, rx, r_top, r_bot, count):
    """A ring around `center` in the plane of `side` / `up`, starting at the bottom; top and bottom radii
    may differ."""
    points = []
    for j in range(count):
        theta = 2 * math.pi * j / count
        vertical = -math.cos(theta)
        r_v = r_top if vertical > 0 else r_bot
        points.append(center + side * (rx * math.sin(theta)) + up * (r_v * vertical))
    return points


def frame_at(tangent):
    tangent = tangent.normalized()
    side = Vector((1, 0, 0))
    up = tangent.cross(side).normalized()
    return side, up


def flat_part(obj, bone, color):
    """Flat-colors every face of a primitive part and records its bone."""
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    uv = bm.loops.layers.uv.verify()
    u, v = swatch_uv(color)
    for face in bm.faces:
        for loop in face.loops:
            loop[uv].uv = (u, v)
    bm.to_mesh(obj.data)
    bm.free()
    PARTS.append((obj, bone))
    return obj


def between(a, b):
    a, b = Vector(a), Vector(b)
    direction = b - a
    rotation = Vector((0, 0, 1)).rotation_difference(direction.normalized()).to_euler()
    return (a + b) / 2, direction.length, rotation


def rod(a, b, r1, r2, bone, color, sides=6):
    location, length, rotation = between(b, a)
    bpy.ops.mesh.primitive_cone_add(vertices=sides, radius1=r2, radius2=r1, depth=length, location=location,
                                    rotation=rotation)
    return flat_part(bpy.context.active_object, bone, color)


def chain_weights(points, bones, blend=0.12):
    """Weights for a vertex near a polyline whose segments belong to `bones` (one per segment): the
    nearest segment's bone, blended toward 50/50 within `blend` of a joint."""
    def weights(p):
        best, best_d, best_t = 0, math.inf, 0
        for k in range(len(points) - 1):
            a, b = points[k], points[k + 1]
            ab = b - a
            t = max(0.0, min(1.0, (p - a).dot(ab) / ab.length_squared))
            d = (a + ab * t - p).length
            if d < best_d:
                best, best_d, best_t = k, d, t
        length = (points[best + 1] - points[best]).length
        near_end = (1 - best_t) * length
        near_start = best_t * length
        if near_end < blend and best + 1 < len(bones):
            share = 0.5 + 0.5 * (near_end / blend)
            return {bones[best]: share, bones[best + 1]: 1 - share}
        if near_start < blend and best > 0:
            share = 0.5 + 0.5 * (near_start / blend)
            return {bones[best]: share, bones[best - 1]: 1 - share}
        return {bones[best]: 1.0}
    return weights


def rein_weights(start, end):
    """head at `start` fading to neck at `end`."""
    def weights(p):
        ab = end - start
        t = max(0.0, min(1.0, (p - start).dot(ab) / ab.length_squared))
        return {"head": 1 - t, "neck": t} if 0 < t < 1 else {("head" if t <= 0 else "neck"): 1.0}
    return weights


def unstretch(obj, center):
    """Pre-squeezes a round part along y about `center`, so the body's stretch (RATIO longer in y than
    in z) leaves it round."""
    world = obj.matrix_world.copy()
    local = world.inverted()
    for vert in obj.data.vertices:
        p = world @ vert.co
        p.y = center.y + (p.y - center.y) / RATIO
        vert.co = local @ p


def bone_anchor(bone):
    """Where the part on `bone` joins the body (it scales evenly about it), or None for the body."""
    if bone in ("head", "ear.L", "ear.R"):
        return HEAD_POLL
    if bone.startswith("tail."):
        return TAIL[0]
    side = bone.split(".")[-1]
    if side in LEG_X:
        return leg_points(side)[0]
    return None


def place(p, bone):
    """The authored point `p` on `bone` at final scale."""
    anchor = bone_anchor(bone)
    if anchor is None:
        return scaled(p)
    return scaled(anchor) + (Vector(p) - anchor) * KZ


# -------------------------------------------------------------------------------------------------
# The horse (faces -Y, Z up; 1 unit = 1 stud)
# -------------------------------------------------------------------------------------------------

# Barrel sections: (y, half width, top radius, bottom radius, center height). A deep chest, a withers
# bump, a slight belly curve, a rounded rump.
BARREL = [
    (-1.95, 0.22, 0.26, 0.3, 3.12),
    (-1.78, 0.46, 0.56, 0.68, 3.1),
    (-1.45, 0.58, 0.7, 0.86, 3.04),
    (-1.0, 0.6, 0.84, 0.82, 3.04),
    (-0.5, 0.61, 0.74, 0.8, 3.02),
    (0.0, 0.63, 0.71, 0.86, 3.0),
    (0.5, 0.66, 0.72, 0.82, 3.04),
    (0.95, 0.7, 0.8, 0.76, 3.12),
    (1.35, 0.67, 0.8, 0.72, 3.2),
    (1.7, 0.52, 0.66, 0.58, 3.22),
    (1.92, 0.26, 0.34, 0.3, 3.2),
]
BODY_N = 12


def barrel_ring(y):
    """(half width, top radius, bottom radius, center height) of the barrel at `y`."""
    for k in range(len(BARREL) - 1):
        a, b = BARREL[k], BARREL[k + 1]
        if a[0] <= y <= b[0]:
            t = (y - a[0]) / (b[0] - a[0])
            return [a[i] + (b[i] - a[i]) * t for i in range(1, 5)]
    return list(BARREL[0][1:])


def build_barrel():
    rings = [ring_points(Vector((0, y, cz)), Vector((1, 0, 0)), Vector((0, 0, 1)), rx, rt, rb, BODY_N)
             for y, rx, rt, rb, cz in BARREL]
    ys = [s[0] for s in BARREL]
    length = ys[-1] - ys[0]
    obj = loft("barrel", rings, lambda i, j: tile_uv(TILE_BODY, (ys[i] - ys[0]) / length, j / BODY_N),
               tile_uv(TILE_BODY, 0.5, 0.0))
    PARTS.append((obj, "spine"))


NECK_BASE, NECK_CTRL, NECK_TOP = Vector((0, -1.3, 3.5)), Vector((0, -1.5, 4.55)), Vector((0, -2.08, 4.82))


def bezier(a, c, b, t):
    return a * (1 - t) ** 2 + c * 2 * (1 - t) * t + b * t * t


def neck_frame(t):
    center = bezier(NECK_BASE, NECK_CTRL, NECK_TOP, t)
    tangent = (NECK_CTRL - NECK_BASE) * 2 * (1 - t) + (NECK_TOP - NECK_CTRL) * 2 * t
    side, up = frame_at(tangent)
    return center, side, up


def neck_radii(t):
    return 0.42 + (0.25 - 0.42) * t, 0.6 + (0.3 - 0.6) * t


def build_neck():
    count = 10
    ts = [0.0, 0.2, 0.4, 0.6, 0.8, 1.0]
    rings = []
    for t in ts:
        center, side, up = neck_frame(t)
        rx, rz = neck_radii(t)
        rings.append(ring_points(center, side, up, rx, rz, rz * 0.95, count))
    obj = loft("neck", rings, lambda i, j: tile_uv(TILE_NECK, j / count, ts[i]), swatch_uv("coat"))
    PARTS.append((obj, "neck"))


HEAD_POLL, HEAD_TIP = Vector((0, -2.08, 4.86)), Vector((0, -2.98, 4.12))


def build_head():
    count = 10
    axis = HEAD_TIP - HEAD_POLL
    side, up = frame_at(axis)
    # (t along the head, half width, top radius, bottom radius (the jaw), color)
    sections = [
        (0.0, 0.2, 0.22, 0.26, "coat"),
        (0.22, 0.29, 0.26, 0.4, "coat"),  # cheeks and jaw
        (0.45, 0.24, 0.24, 0.3, "coat"),
        (0.7, 0.19, 0.21, 0.23, "muzzle"),
        (0.92, 0.18, 0.2, 0.2, "muzzle"),
        (1.0, 0.16, 0.17, 0.17, "muzzle"),  # the nostril plane (the end cap)
    ]
    rings = [ring_points(HEAD_POLL + axis * t, side, up, rx, rt, rb, count) for t, rx, rt, rb, _ in sections]
    colors = [section[4] for section in sections]
    obj = loft("head", rings, lambda i, j: swatch_uv(colors[i]), swatch_uv("muzzle"))
    PARTS.append((obj, "head"))
    facing = axis.to_track_quat("Y", "Z").to_euler()
    for sx in (-1, 1):
        # Nostrils on the flat muzzle end.
        bpy.ops.mesh.primitive_cube_add(size=1, location=HEAD_TIP + axis.normalized() * 0.01 + side * (0.08 * sx)
                                        + up * 0.02, rotation=facing)
        nostril = bpy.context.active_object
        nostril.scale = (0.06, 0.03, 0.08)
        bpy.ops.object.transform_apply(scale=True, rotation=True)
        flat_part(nostril, "head", "nostril")
        # Eyes on the sides, above the cheeks.
        bpy.ops.mesh.primitive_cube_add(size=1, location=HEAD_POLL + axis * 0.2 + side * (0.27 * sx) + up * 0.1,
                                        rotation=facing)
        eye = bpy.context.active_object
        eye.scale = (0.06, 0.1, 0.08)
        bpy.ops.object.transform_apply(scale=True, rotation=True)
        flat_part(eye, "head", "eye")
        # Ears: larger, alert, a little flattened.
        base = HEAD_POLL + side * (0.15 * sx) + up * 0.1
        bpy.ops.mesh.primitive_cone_add(vertices=6, radius1=0.12, radius2=0.015, depth=0.58,
                                        location=base + Vector((0.03 * sx, 0.02, 0.29)))
        ear = bpy.context.active_object
        ear.scale = (0.65, 1.0, 1.0)
        ear.rotation_euler = (math.radians(-8), math.radians(8 * sx), 0)
        bpy.ops.object.transform_apply(scale=True, rotation=True)
        flat_part(ear, "ear." + ("L" if sx > 0 else "R"), "coat")


def tuft(name, points, widths, thickness, bone, along):
    """A flowing mane / forelock tuft: a flattened tapered tube through `points`, its flat side along
    `along` (the neck), `widths` per point."""
    rings = []
    for k, p in enumerate(points):
        tangent = (points[min(k + 1, len(points) - 1)] - points[max(k - 1, 0)]).normalized()
        flat = along - tangent * along.dot(tangent)
        flat = flat.normalized() if flat.length > 1e-4 else Vector((0, 1, 0))
        normal = tangent.cross(flat).normalized()
        w = widths[k]
        rings.append([p + flat * w, p + normal * thickness, p - flat * w, p - normal * thickness])
    obj = loft(name, rings, lambda i, j: swatch_uv("mane" if j % 2 == 0 else "maneshade"), swatch_uv("mane"))
    PARTS.append((obj, bone))


def build_mane():
    # Five flowing tufts along the crest, falling to the horse's right (+x), close to the neck.
    for k in range(5):
        t = 0.1 + 0.19 * k
        center, side, up = neck_frame(t)
        rx, rz = neck_radii(t)
        along = (neck_frame(min(t + 0.05, 1))[0] - neck_frame(max(t - 0.05, 0))[0]).normalized()
        root = center + up * (rz * 0.92) + side * 0.03
        mid = center + up * (rz * 0.55) + side * (rx + 0.06) + Vector((0, 0.06, 0))
        end = center + up * (rz * 0.05) + side * (rx + 0.07) + Vector((0, 0.12, -0.12))
        tuft("mane%d" % k, [root, mid, end], [0.28 - 0.015 * k, 0.24, 0.1], 0.07, "neck", along)
    # The forelock between the ears, falling forward over the face.
    axis = (HEAD_TIP - HEAD_POLL).normalized()
    root = HEAD_POLL + Vector((0, 0.02, 0.2))
    tuft("forelock", [root, root + axis * 0.22 + Vector((0.03, 0, 0.04)), root + axis * 0.45 + Vector((0.05, 0, -0.02))],
         [0.11, 0.09, 0.02], 0.05, "head", Vector((1, 0, 0)))


LEGS = {
    # (y, z) path points and radii; the x is set per side.
    "F": ([(-1.2, 2.85), (-1.22, 2.35), (-1.22, 1.65), (-1.22, 1.32), (-1.22, 0.9), (-1.22, 0.42), (-1.2, 0.24),
           (-1.2, 0.22), (-1.2, 0.0)],
          [0.26, 0.22, 0.165, 0.19, 0.13, 0.155, 0.13, 0.19, 0.22]),
    # The hind leg: the gaskin slopes back to the point of the hock, the cannon comes down near vertical.
    "B": ([(1.15, 2.95), (1.3, 2.15), (1.48, 1.42), (1.42, 1.28), (1.37, 0.85), (1.33, 0.42), (1.32, 0.24),
           (1.32, 0.22), (1.32, 0.0)],
          [0.32, 0.24, 0.19, 0.2, 0.13, 0.155, 0.13, 0.19, 0.22]),
}
LEG_X = {"FL": 0.36, "FR": -0.36, "BL": 0.4, "BR": -0.4}


def leg_points(key):
    path, _ = LEGS[key[0]]
    return [Vector((LEG_X[key], y, z)) for y, z in path]


def build_leg(key):
    _, radii = LEGS[key[0]]
    points = leg_points(key)
    count = 8
    rings = []
    for k, p in enumerate(points):
        tangent = points[min(k + 1, len(points) - 1)] - points[max(k - 1, 0)]
        side, up = frame_at(tangent)
        rings.append(ring_points(p, side, up, radii[k], radii[k], radii[k], count))
    top = points[0].z

    def uv_of(i, j):
        if i >= 7:  # rings 7-8 are the hoof
            return swatch_uv("hoof")
        return tile_uv(TILE_LEG, j / count, points[i].z / top)

    obj = loft("leg" + key, rings, uv_of, swatch_uv("hoof"))
    # Bones: upper (points 0-3: to the knee / hock), lower (3-7: to the hoof top), hoof (7-8).
    joints = [points[0], points[3], points[7], points[8]]
    PARTS.append((obj, chain_weights(joints, ["upper." + key, "lower." + key, "hoof." + key], blend=0.14)))


TAIL = [Vector((0, 1.86, 3.5)), Vector((0, 2.12, 3.05)), Vector((0, 2.32, 2.45)), Vector((0, 2.44, 1.85)),
        Vector((0, 2.5, 1.2))]
TAIL_RADII = [0.12, 0.2, 0.25, 0.22, 0.06]


def build_tail():
    count = 6
    rings = []
    for k, p in enumerate(TAIL):
        tangent = TAIL[min(k + 1, 4)] - TAIL[max(k - 1, 0)]
        side, up = frame_at(tangent)
        r = TAIL_RADII[k]
        rings.append(ring_points(p, side, up, r * 0.75, r, r, count))
    obj = loft("tail", rings, lambda i, j: swatch_uv("mane" if j % 2 == 0 else "maneshade"), swatch_uv("mane"))
    PARTS.append((obj, chain_weights(TAIL, ["tail.1", "tail.2", "tail.3", "tail.4"])))


def arc_slab(name, y0, y1, half_angle, inner, outer, hang, color, steps=5):
    """A thin slab draped over the barrel's top between y0 and y1: `half_angle` each side of the top,
    from `inner` to `outer` off the surface; its edges flare out and hang `hang` lower."""
    arc = 8
    rings = []
    for s in range(steps):
        y = y0 + (y1 - y0) * s / (steps - 1)
        rx, rt, _rb, cz = barrel_ring(y)
        outer_pts, inner_pts = [], []
        for a in range(arc + 1):
            ang = -half_angle + 2 * half_angle * a / arc  # 0 = the top
            edge = abs(ang) / half_angle
            sx, cz_off = math.sin(ang), math.cos(ang)
            surface = Vector((rx * sx * (1 + edge * edge * hang), y, cz + rt * cz_off - edge ** 3 * hang))
            normal = Vector((sx / max(rx, 1e-3), 0, cz_off / max(rt, 1e-3))).normalized()
            outer_pts.append(surface + normal * outer)
            inner_pts.append(surface + normal * inner)
        rings.append(outer_pts + list(reversed(inner_pts)))
    obj = loft(name, rings, lambda i, j: swatch_uv(color), swatch_uv(color))
    PARTS.append((obj, "spine"))


def star_map(obj, center, length):
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    uv = bm.loops.layers.uv.verify()
    for face in bm.faces:
        for loop in face.loops:
            p = obj.matrix_world @ loop.vert.co - center
            if abs(face.normal.x) > 0.9:
                loop[uv].uv = swatch_uv("blanket")  # the end caps
                continue
            u = (math.atan2(p.z, p.y) / (2 * math.pi)) % 1.0
            loop[uv].uv = tile_uv(TILE_STAR, u, p.x / length + 0.5)
    bm.to_mesh(obj.data)
    bm.free()


def build_tack():
    # Saddle blanket draped over the back, a brown seat, a smaller star bedroll behind the saddle.
    arc_slab("blanket", -0.55, 0.38, math.radians(78), 0.01, 0.05, 0.12, "blanket")
    arc_slab("blankettrim", -0.6, -0.5, math.radians(80), 0.012, 0.06, 0.13, "blankettrim", steps=2)
    arc_slab("seat", -0.38, 0.12, math.radians(42), 0.05, 0.17, 0.02, "saddle", steps=4)
    arc_slab("cantle", 0.06, 0.18, math.radians(30), 0.15, 0.3, 0.0, "saddle", steps=2)
    _rx, rt, _rb, cz = barrel_ring(0.5)
    roll_at = Vector((0, 0.5, cz + rt + 0.14))
    bpy.ops.mesh.primitive_cylinder_add(vertices=10, radius=0.17, depth=0.9, location=roll_at,
                                        rotation=(0, math.radians(90), 0))
    roll = bpy.context.active_object
    bpy.ops.object.transform_apply(rotation=True)
    flat_part(roll, "spine", "blanket")
    star_map(roll, roll_at, 0.9)
    unstretch(roll, roll_at)
    for x in (-0.28, 0.28):
        bpy.ops.mesh.primitive_torus_add(major_radius=0.18, minor_radius=0.025, major_segments=8, minor_segments=4,
                                         location=roll_at + Vector((x, 0, 0)), rotation=(0, math.radians(90), 0))
        flat_part(bpy.context.active_object, "spine", "tackdark")
        unstretch(bpy.context.active_object, roll_at)
    # Bridle: noseband, cheek straps, reins to the withers.
    axis = HEAD_TIP - HEAD_POLL
    side, up = frame_at(axis)
    nose = HEAD_POLL + axis * 0.72
    bpy.ops.mesh.primitive_torus_add(major_radius=0.24, minor_radius=0.03, major_segments=10, minor_segments=4,
                                     location=nose, rotation=axis.to_track_quat("Z", "Y").to_euler())
    band = bpy.context.active_object
    band.scale = (0.92, 1.05, 1.0)
    bpy.ops.object.transform_apply(scale=True, rotation=True)
    flat_part(band, "head", "tack")
    for sx in (-1, 1):
        rod(nose + side * (0.22 * sx), HEAD_POLL + side * (0.2 * sx) + up * 0.05, 0.025, 0.025, "head", "tack", sides=4)
        start, end = nose + side * (0.24 * sx) - up * 0.08, Vector((0.3 * sx, -1.35, 3.92))
        rod(start, end, 0.022, 0.022, "neck", "tackdark", sides=4)
        # The rein runs from the head to the withers: blend it head -> neck along its length.
        PARTS[-1] = (PARTS[-1][0], rein_weights(start, end))
    # Chest strap around the front of the chest, with the round medallion at its center.
    rx, _rt, _rb, cz = barrel_ring(-1.55)
    bpy.ops.mesh.primitive_torus_add(major_radius=1.0, minor_radius=0.05, major_segments=20, minor_segments=4,
                                     location=(0, -1.55, cz - 0.05))
    strap = bpy.context.active_object
    strap.scale = (rx + 0.05, 0.36, 1.0)
    bpy.ops.object.transform_apply(scale=True)
    bm = bmesh.new()
    bm.from_mesh(strap.data)
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if v.co.y > -0.02], context="VERTS")
    bm.to_mesh(strap.data)
    bm.free()
    flat_part(strap, "spine", "tack")
    bpy.ops.mesh.primitive_cylinder_add(vertices=12, radius=0.16, depth=0.07, location=(0, -1.55 - 0.38, cz - 0.05),
                                        rotation=(math.radians(90), 0, 0))
    flat_part(bpy.context.active_object, "spine", "medallion")


# -------------------------------------------------------------------------------------------------
# Rig
# -------------------------------------------------------------------------------------------------

def bone_table():
    bones = {
        "root": ((0, 0, 0), (0, 0, 0.6), None),
        "spine": ((0, 1.15, 3.15), (0, -1.2, 3.25), "root"),
        "neck": (tuple(NECK_BASE), tuple(NECK_TOP), "spine"),
        "head": (tuple(HEAD_POLL), tuple(HEAD_TIP), "neck"),
        "ear.L": ((0.18, -2.06, 4.98), (0.21, -2.04, 5.55), "head"),
        "ear.R": ((-0.18, -2.06, 4.98), (-0.21, -2.04, 5.55), "head"),
    }
    names = ["tail.1", "tail.2", "tail.3", "tail.4"]
    for k, name in enumerate(names):
        bones[name] = (tuple(TAIL[k]), tuple(TAIL[k + 1]), "spine" if k == 0 else names[k - 1])
    for key in LEG_X:
        points = leg_points(key)
        bones["upper." + key] = (tuple(points[0]), tuple(points[3]), "spine")
        bones["lower." + key] = (tuple(points[3]), tuple(points[7]), "upper." + key)
        bones["hoof." + key] = (tuple(points[7]), tuple(points[8]), "lower." + key)
    # The rider's anchor: head on the seat's top, pointing up (a rider's hips go at its head).
    bones["seat"] = (tuple(SEAT_AUTHORED), tuple(SEAT_AUTHORED + Vector((0, 0, 0.5))), "spine")
    return {name: (tuple(place(head, name)), tuple(place(tail, name)), parent)
            for name, (head, tail, parent) in bones.items()}


BONES = bone_table()


def build_rig():
    bpy.ops.object.armature_add(location=(0, 0, 0))
    arm = bpy.context.active_object
    arm.name = NAME + "_rig"
    arm.data.name = NAME + "_rig"
    bpy.ops.object.mode_set(mode="EDIT")
    edit = arm.data.edit_bones
    for bone in list(edit):
        edit.remove(bone)
    for name, (head, tail, _parent) in BONES.items():
        bone = edit.new(name)
        bone.head, bone.tail = head, tail
        bone.roll = 0
    for name, (_head, _tail, parent) in BONES.items():
        if parent:
            edit[name].parent = edit[parent]
    bpy.ops.object.mode_set(mode="OBJECT")
    for pb in arm.pose.bones:
        pb.rotation_mode = "XYZ"
    return arm


def join_and_skin(arm, material):
    for obj, bone in PARTS:
        if callable(bone):
            groups = {}
            for vert in obj.data.vertices:
                for name, weight in bone(obj.matrix_world @ vert.co).items():
                    if name not in groups:
                        groups[name] = obj.vertex_groups.new(name=name)
                    groups[name].add([vert.index], weight, "REPLACE")
        else:
            group = obj.vertex_groups.new(name=bone)
            group.add(range(len(obj.data.vertices)), 1.0, "REPLACE")
    bpy.ops.object.select_all(action="DESELECT")
    for obj, _ in PARTS:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = PARTS[0][0]
    bpy.ops.object.join()
    mesh = bpy.context.active_object
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    # Final scale: each vertex placed by its bones' weights (the body stretches, the parts on the head,
    # legs and tail scale evenly about their joins).
    names = {group.index: group.name for group in mesh.vertex_groups}
    for vert in mesh.data.vertices:
        total, moved = 0.0, Vector((0, 0, 0))
        for g in vert.groups:
            if g.weight > 0:
                moved += place(vert.co, names[g.group]) * g.weight
                total += g.weight
        vert.co = moved / total if total > 0 else scaled(vert.co)
    mesh.name = NAME
    mesh.data.name = NAME
    mesh.data.materials.clear()
    mesh.data.materials.append(material)
    for poly in mesh.data.polygons:
        poly.use_smooth = False
    modifier = mesh.modifiers.new("Armature", "ARMATURE")
    modifier.object = arm
    mesh.parent = arm
    return mesh


def make_outline(mesh, material):
    """An inverted hull: the mesh pushed out along its normals, faces flipped, the outline color."""
    outline = mesh.copy()
    outline.data = mesh.data.copy()
    outline.name = NAME + "_outline"
    outline.data.name = NAME + "_outline"
    bpy.context.collection.objects.link(outline)
    bm = bmesh.new()
    bm.from_mesh(outline.data)
    bm.normal_update()
    for vert in bm.verts:
        vert.co += vert.normal * OUTLINE
    for face in bm.faces:
        face.normal_flip()
    uv = bm.loops.layers.uv.verify()
    u, v = swatch_uv("outline")
    for face in bm.faces:
        for loop in face.loops:
            loop[uv].uv = (u, v)
    bm.to_mesh(outline.data)
    bm.free()
    outline.data.materials.clear()
    outline.data.materials.append(material)
    return outline


def make_material(image):
    material = bpy.data.materials.new(NAME + "_palette")
    material.use_nodes = True
    nodes = material.node_tree.nodes
    bsdf = nodes.get("Principled BSDF")
    texture = nodes.new("ShaderNodeTexImage")
    texture.image = image
    texture.interpolation = "Closest"
    material.node_tree.links.new(texture.outputs["Color"], bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = 0.85
    material.use_backface_culling = True
    material.diffuse_color = (0.85, 0.85, 0.88, 1)
    return material


# -------------------------------------------------------------------------------------------------
# Animations (rotation_euler.x pitches a bone in its side plane, degrees: + tips a forward-pointing
# bone down and swings a downward-pointing bone back; .z turns it sideways)
# -------------------------------------------------------------------------------------------------

def key(arm, frame, values):
    for name, value in values.items():
        if name == "root.loc":
            pb = arm.pose.bones["root"]
            pb.location = value
            pb.keyframe_insert("location", frame=frame)
        else:
            pb = arm.pose.bones[name]
            pb.rotation_euler = Euler([math.radians(a) for a in value], "XYZ")
            pb.keyframe_insert("rotation_euler", frame=frame)


def new_action(arm, name):
    action = bpy.data.actions.new(name)
    action.use_fake_user = True
    arm.animation_data_create()
    arm.animation_data.action = action
    for pb in arm.pose.bones:
        pb.rotation_euler = (0, 0, 0)
        pb.location = (0, 0, 0)
    return action


def make_cyclic(action):
    for curve in action.fcurves:
        curve.modifiers.new("CYCLES")


def pulse(frame, at, width):
    """0 -> 1 -> 0 around frame `at`, `width` frames each way."""
    return max(0.0, 1 - abs(frame - at) / width)


def anim_idle(arm):
    action = new_action(arm, "idle")
    length = 90
    for frame in range(0, length + 1, 3):
        t = frame / length
        wave = math.sin(t * 2 * math.pi)
        values = {
            # Weight shift side to side, one hind leg resting at a time.
            "root.loc": (wave * 0.1, 0, -abs(wave) * 0.03),
            "spine": (0, wave * 4.0, 0),
            "upper.BL": (-wave * 5, 0, 0),
            "upper.BR": (wave * 5, 0, 0),
            "lower.BL": (max(0.0, -wave) * 12, 0, 0),
            "lower.BR": (max(0.0, wave) * 12, 0, 0),
            # Head bob (down and up twice) and a little turn.
            "neck": (math.sin(t * 4 * math.pi) * 14, 0, math.sin(t * 2 * math.pi + 0.5) * 12),
            "head": (math.sin(t * 4 * math.pi + 1.2) * 14, 0, 0),
            # Tail swish side to side.
            "tail.1": (8 + math.sin(t * 4 * math.pi + 1.0) * 12, 0, math.sin(t * 4 * math.pi) * 22),
            "tail.2": (4 + math.sin(t * 4 * math.pi + 0.3) * 10, 0, math.sin(t * 4 * math.pi - 0.7) * 24),
            "tail.3": (2, 0, math.sin(t * 4 * math.pi - 1.4) * 22),
            "tail.4": (0, 0, math.sin(t * 4 * math.pi - 2.1) * 24),
            # Ear flicks: left at 20 and 62, right at 42.
            "ear.L": (-55 * max(pulse(frame, 20, 6), pulse(frame, 62, 6)), 0, -25 * pulse(frame, 20, 6)),
            "ear.R": (-55 * pulse(frame, 42, 6), 0, 25 * pulse(frame, 42, 6)),
        }
        key(arm, frame, values)
    make_cyclic(action)
    return action, (0, length)


def anim_gallop(arm):
    action = new_action(arm, "gallop")
    length = 20  # 0.67 s per stride
    phase = {"BL": 0.0, "BR": 0.1, "FL": 0.5, "FR": 0.6}
    for frame in range(0, length + 1, 2):
        t = frame / length
        values = {}
        for leg, offset in phase.items():
            p = (t + offset) % 1.0
            swing = math.sin(p * 2 * math.pi)  # + forward, - back
            front = leg[0] == "F"
            values["upper." + leg] = (-swing * (40 if front else 30), 0, 0)
            # Coming forward the joint folds: the knee (front) and the hock (hind) both bring the lower
            # leg back and up.
            fold = max(0.0, math.cos(p * 2 * math.pi))
            values["lower." + leg] = (fold * (70 if front else 55), 0, 0)
            values["hoof." + leg] = (fold * 30, 0, 0)
        body = math.sin(t * 2 * math.pi)
        values["spine"] = (body * 6, 0, 0)
        values["root.loc"] = (0, 0, 0.2 + math.sin(t * 4 * math.pi) * 0.14)
        # Head and neck counter to the body.
        values["neck"] = (-body * 10, 0, 0)
        values["head"] = (body * 6, 0, 0)
        # The tail streams back and whips.
        values["tail.1"] = (50 + math.sin(t * 2 * math.pi) * 8, 0, 0)
        values["tail.2"] = (14 + math.sin(t * 2 * math.pi - 0.8) * 12, 0, math.sin(t * 2 * math.pi) * 6)
        values["tail.3"] = (10 + math.sin(t * 2 * math.pi - 1.6) * 14, 0, math.sin(t * 2 * math.pi - 0.8) * 8)
        values["tail.4"] = (8 + math.sin(t * 2 * math.pi - 2.4) * 16, 0, math.sin(t * 2 * math.pi - 1.6) * 10)
        values["ear.L"] = (-18, 0, 0)
        values["ear.R"] = (-18, 0, 0)
        key(arm, frame, values)
    make_cyclic(action)
    return action, (0, length)


def anim_rear(arm):
    action = new_action(arm, "rear_up")
    poses = [
        (0, 0.0, 0.0),
        (10, 0.15, 0.25),  # gather
        (22, 1.0, 1.0),  # reared
        (34, 1.0, 1.05),  # held at the top, front hooves pawing
        (42, 1.0, 0.95),
        (56, 0.0, 0.0),  # down
    ]
    for frame, up, paw in poses:
        pitch = -56 * up  # negative pitches the front up (about the hips)
        values = {
            "spine": (pitch, 0, 0),
            "root.loc": (0, 0, -0.15 * up),
            "upper.BL": (-pitch * 0.9, 0, 0),
            "upper.BR": (-pitch * 0.9, 0, 0),
            "lower.BL": (8 * up, 0, 0),
            "lower.BR": (8 * up, 0, 0),
            "upper.FL": (-70 * paw, 0, 0),
            "upper.FR": (-58 * paw, 0, 0),
            "lower.FL": (118 * paw, 0, 0),
            "lower.FR": (104 * paw, 0, 0),
            "neck": (-14 * up, 0, 0),
            "head": (18 * up, 0, 0),
            # The tail hangs and flows behind as the body rises.
            "tail.1": (60 * up, 0, 0),
            "tail.2": (16 * up, 0, 6 * paw),
            "tail.3": (14 * up, 0, -8 * paw),
            "tail.4": (12 * up, 0, 10 * paw),
            "ear.L": (-10 * up, 0, 0),
            "ear.R": (-10 * up, 0, 0),
        }
        key(arm, frame, values)
    return action, (0, 56)


# -------------------------------------------------------------------------------------------------
# Renders
# -------------------------------------------------------------------------------------------------

def setup_render(scene):
    scene.render.engine = "BLENDER_WORKBENCH"
    shading = scene.display.shading
    shading.light = "STUDIO"
    shading.color_type = "TEXTURE"
    shading.show_specular_highlight = False
    shading.show_backface_culling = True  # the outline hull is an inverted shell (back faces only)
    scene.display.render_aa = "8"
    scene.view_settings.view_transform = "Standard"
    scene.render.film_transparent = False
    if scene.world is None:
        scene.world = bpy.data.worlds.new("World")


def camera(scene):
    cam_data = bpy.data.cameras.new("cam")
    cam_data.type = "ORTHO"
    cam_data.ortho_scale = 10.2
    cam = bpy.data.objects.new("cam", cam_data)
    scene.collection.objects.link(cam)
    scene.camera = cam
    return cam


def aim(cam, angle_deg, elevation_deg=12, target=(0, 0.2, 3.0), distance=30):
    a, e = math.radians(angle_deg), math.radians(elevation_deg)
    t = Vector(target)
    cam.location = t + Vector((math.sin(a) * math.cos(e), -math.cos(a) * math.cos(e), math.sin(e))) * distance
    cam.rotation_euler = (t - cam.location).to_track_quat("-Z", "Y").to_euler()


def render_to(scene, path, width, height=None):
    scene.render.resolution_x = width
    scene.render.resolution_y = height or width
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)


def load_pixels(path):
    image = bpy.data.images.load(path)
    w, h = image.size
    pixels = np.array(image.pixels[:], dtype=np.float32).reshape(h, w, 4)
    bpy.data.images.remove(image)
    return pixels


def save_sheet(rows, path):
    tile_h, tile_w = rows[0][0].shape[:2]
    sheet = np.ones((tile_h * len(rows), tile_w * max(len(r) for r in rows), 4), dtype=np.float32)
    for r, row in enumerate(rows):
        y0 = (len(rows) - 1 - r) * tile_h
        for c, tile in enumerate(row):
            sheet[y0 : y0 + tile_h, c * tile_w : (c + 1) * tile_w] = tile
    h, w = sheet.shape[:2]
    image = bpy.data.images.new("sheet", w, h, alpha=False)
    image.pixels = sheet.flatten()
    image.filepath_raw = path
    image.file_format = "PNG"
    image.save()
    bpy.data.images.remove(image)


def tmp(name):
    return os.path.join(REVIEW, "_tmp_" + name + ".png")


def out(name):
    return os.path.join(REVIEW, NAME + "_" + name + SUFFIX + ".png")


def turntable(scene, cam):
    rows = []
    for background in ((0.42, 0.42, 0.44), (0.06, 0.06, 0.08)):
        scene.world.color = background
        row = []
        for i in range(8):
            aim(cam, i * 45)
            path = tmp("turn%d" % i)
            render_to(scene, path, 384)
            row.append(load_pixels(path))
        rows.append(row)
    save_sheet(rows, out("turntable"))


def frame_strip(scene, cam, arm, action, frames, name, count, closed):
    """`count` frames across the action; a loop (`closed`) leaves out its last frame (= the first)."""
    arm.animation_data.action = action
    scene.world.color = (0.42, 0.42, 0.44)
    # Side view, room above for the rear-up; the idle from 3/4 so its sideways sway shows.
    aim(cam, 60 if name == "idle" else 90, 8, target=(0, 0.4, 3.4))
    cam.data.ortho_scale = 13.0
    start, end = frames
    row = []
    for i in range(count):
        frame = round(start + (end - start) * i / (count if closed else max(1, count - 1)))
        scene.frame_set(frame)
        path = tmp("%s%d" % (name, i))
        render_to(scene, path, 320)
        row.append(load_pixels(path))
    save_sheet([row], out("anim_" + name))
    cam.data.ortho_scale = 10.2


def rig_render(scene, cam, arm, outline):
    """The rest pose with the skeleton drawn as orange sticks through a see-through body (no root)."""
    arm.data.pose_position = "REST"
    sticks = []
    stick_material = bpy.data.materials.new("bone")
    stick_material.diffuse_color = (1.0, 0.45, 0.05, 1)
    for name, (head, tail, _parent) in BONES.items():
        if name == "root":
            continue
        location, length, rotation = between(head, tail)
        bpy.ops.mesh.primitive_cone_add(vertices=4, radius1=0.09, radius2=0.02, depth=max(length, 0.05),
                                        location=location, rotation=rotation)
        stick = bpy.context.active_object
        stick.data.materials.append(stick_material)
        sticks.append(stick)
    shading = scene.display.shading
    shading.color_type = "MATERIAL"
    shading.show_xray = True
    shading.xray_alpha = 0.35
    outline.hide_render = True
    scene.world.color = (0.42, 0.42, 0.44)
    row = []
    for angle in (90, 30):
        aim(cam, angle, 10)
        path = tmp("rig%d" % angle)
        render_to(scene, path, 512)
        row.append(load_pixels(path))
    save_sheet([row], out("rig"))
    for stick in sticks:
        bpy.data.objects.remove(stick)
    shading.color_type = "TEXTURE"
    shading.show_xray = False
    outline.hide_render = False
    arm.data.pose_position = "POSE"


def colored(color):
    """A material whose color shows in Workbench texture mode: a 1-pixel image of that color."""
    img = bpy.data.images.new("c", 1, 1, alpha=False)
    img.pixels = list(color)
    material = bpy.data.materials.new("m")
    material.use_nodes = True
    tex = material.node_tree.nodes.new("ShaderNodeTexImage")
    tex.image = img
    material.node_tree.links.new(tex.outputs["Color"], material.node_tree.nodes["Principled BSDF"].inputs["Base Color"])
    return material


def r6_block(made, size, location, material, parent=None, tilt=0.0):
    """One block of an R6 proxy (studs), optionally tilted about y and parented."""
    bpy.ops.mesh.primitive_cube_add(size=1, location=location, rotation=(0, tilt, 0))
    cube = bpy.context.active_object
    cube.scale = size
    cube.data.materials.append(material)
    if parent:
        cube.parent = parent
    made.append(cube)


def r6_standing(made, x, y, skin, shirt, pants):
    """A blocky R6 figure 4.6 studs tall (legs 2, torso 2, head 1 of 5 parts), standing at (x, y)."""
    k = RIDER_HEIGHT / 5
    for size, loc, material in [
        ((1, 1, 2), (-0.5, 0, 1), pants), ((1, 1, 2), (0.5, 0, 1), pants), ((2, 1, 2), (0, 0, 3), shirt),
        ((1, 1, 2), (-1.5, 0, 3), skin), ((1, 1, 2), (1.5, 0, 3), skin), ((1.2, 1.2, 1), (0, 0, 4.5), skin),
    ]:
        r6_block(made, tuple(v * k for v in size), (x + loc[0] * k, y + loc[1] * k, loc[2] * k), material)


def r6_seated(made, arm, skin, shirt, pants):
    """The same figure astride the saddle: hips on the seat bone's head, torso up, legs from the hips
    tilted out around the barrel. Parented to the rig object, so it turns with the horse."""
    k = RIDER_HEIGHT / 5
    seat = Vector(BONES["seat"][0])
    for size, loc, material in [
        ((2, 1, 2), (0, 0, 1), shirt), ((1.2, 1.2, 1), (0, 0, 2.5), skin),
        ((1, 1, 2), (-1.5, -0.2, 1), skin), ((1, 1, 2), (1.5, -0.2, 1), skin),
    ]:
        r6_block(made, tuple(v * k for v in size), seat + Vector(loc) * k, material, parent=arm)
    half = barrel_ring(SEAT_AUTHORED.y)[0] * KX  # the barrel's half width under the seat
    length = 2 * k
    tilt = math.asin(min(0.75, half / length))
    for sx in (-1, 1):
        center = seat + Vector((sx * (0.5 * k + math.sin(tilt) * length / 2), -0.1, -math.cos(tilt) * length / 2))
        r6_block(made, (k, k, length), center, pants, parent=arm, tilt=sx * tilt)


def match_distance(scene, arm, cam):
    """Two rows: the horse at game size from the match camera's angle (RenderConfig.cameraOffset
    0, 46, 34) with an R6 figure standing beside it and one seated on the saddle; then a side view of
    the same, for the rider fit. On the arena gray, in the rest pose."""
    arm.animation_data.action = None
    arm.data.pose_position = "REST"
    made = []
    bpy.ops.mesh.primitive_plane_add(size=80, location=(0, 0, 0))
    floor = bpy.context.active_object
    floor.data.materials.append(colored((0.55, 0.56, 0.58, 1)))
    made.append(floor)
    skin, pants = colored((0.92, 0.74, 0.58, 1)), colored((0.2, 0.22, 0.3, 1))
    r6_seated(made, arm, skin, colored((0.25, 0.4, 0.75, 1)), pants)
    r6_standing(made, 0.0, 5.6, skin, colored((0.75, 0.3, 0.3, 1)), pants)
    scene.world.color = (0.36, 0.37, 0.39)
    cam_data = bpy.data.cameras.new("match")
    cam_data.lens_unit = "FOV"
    cam_data.angle = math.radians(70)
    match = bpy.data.objects.new("match", cam_data)
    scene.collection.objects.link(match)
    # Row 1: the match angle, the horse turned 3/4.
    arm.rotation_euler = (0, 0, math.radians(-35))
    scene.camera = match
    target = Vector((0, 1.2, 2.2))
    direction = Vector((0, 34, 46)).normalized()  # Roblox (0, 46, 34): up 46, back 34
    match.location = target + direction * 20.0  # closer than the match camera (~57), so it is not tiny
    match.rotation_euler = (target - match.location).to_track_quat("-Z", "Y").to_euler()
    render_to(scene, tmp("match_far"), 960, 540)
    far = load_pixels(tmp("match_far"))
    # Row 2: a side view, orthographic.
    arm.rotation_euler = (0, 0, 0)
    scene.camera = cam
    cam.data.ortho_scale = 17.0
    aim(cam, 90, 4, target=(0, 0.8, 3.2))
    render_to(scene, tmp("match_side"), 960, 540)
    side = load_pixels(tmp("match_side"))
    cam.data.ortho_scale = 10.2
    save_sheet([[far], [side]], out("match_distance"))
    for obj in made:
        bpy.data.objects.remove(obj)
    arm.data.pose_position = "POSE"


def report_dimensions(mesh):
    """Prints the model's sizes (studs, rest pose) and the seat anchor, for the doc."""
    world = [mesh.matrix_world @ v.co for v in mesh.data.vertices]
    xs, ys, zs = [p.x for p in world], [p.y for p in world], [p.z for p in world]
    withers = max(p.z for p in world if abs(p.y + 1.0 * KY) < 0.3 and abs(p.x) < 0.4)
    rump = BARREL[-1][0] * KY
    seat = Vector(BONES["seat"][0])
    print("DIMS ears %.2f withers %.2f nose_y %.2f rump_y %.2f nose-to-rump %.2f width %.2f "
          "bbox x %.2f..%.2f y %.2f..%.2f z %.2f..%.2f" % (
              max(zs), withers, min(ys), rump, rump - min(ys), max(xs) - min(xs),
              min(xs), max(xs), min(ys), max(ys), min(zs), max(zs)))
    print("SEAT blender (%.3f, %.3f, %.3f) roblox (%.3f, %.3f, %.3f) KX %.4f KY %.4f KZ %.4f" % (
        seat.x, seat.y, seat.z, seat.x, seat.z, -seat.y, KX, KY, KZ))


# -------------------------------------------------------------------------------------------------

def main():
    os.makedirs(ASSETS, exist_ok=True)
    os.makedirs(REVIEW, exist_ok=True)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.render.fps = FPS

    image, spot_count = make_palette()
    material = make_material(image)
    build_barrel()
    build_neck()
    build_head()
    build_mane()
    for leg in LEG_X:
        build_leg(leg)
    build_tail()
    build_tack()
    arm = build_rig()
    mesh = join_and_skin(arm, material)
    outline = make_outline(mesh, material)

    idle, idle_range = anim_idle(arm)
    gallop, gallop_range = anim_gallop(arm)
    rear, rear_range = anim_rear(arm)
    arm.animation_data.action = idle

    tris = sum(len(p.vertices) - 2 for p in mesh.data.polygons)
    outline_tris = sum(len(p.vertices) - 2 for p in outline.data.polygons)

    bpy.ops.object.select_all(action="DESELECT")
    for obj in (arm, mesh, outline):
        obj.select_set(True)
    bpy.context.view_layer.objects.active = arm
    bpy.ops.export_scene.fbx(
        filepath=os.path.join(ASSETS, NAME + ".fbx"),
        use_selection=True,
        object_types={"ARMATURE", "MESH"},
        add_leaf_bones=False,
        bake_anim=True,
        bake_anim_use_all_actions=True,
        bake_anim_use_nla_strips=False,
        bake_anim_force_startend_keying=True,
        path_mode="COPY",
        embed_textures=True,
        axis_forward="-Z",
        axis_up="Y",
    )

    setup_render(scene)
    cam = camera(scene)
    scene.frame_set(0)
    arm.data.pose_position = "REST"
    turntable(scene, cam)
    arm.data.pose_position = "POSE"
    if FULL_RENDERS:
        rig_render(scene, cam, arm, outline)
        frame_strip(scene, cam, arm, idle, idle_range, "idle", 10, True)
        frame_strip(scene, cam, arm, gallop, gallop_range, "gallop", 10, True)
        frame_strip(scene, cam, arm, rear, rear_range, "rear_up", 12, False)
    match_distance(scene, arm, cam)
    report_dimensions(mesh)
    for name in os.listdir(REVIEW):
        if name.startswith("_tmp_"):
            os.remove(os.path.join(REVIEW, name))

    print("MODEL %s: %d tris (+%d outline hull = %d), %d bones, spots body/legs/neck %s, palette %dx%d" % (
        NAME, tris, outline_tris, tris + outline_tris, len(BONES), spot_count, SIZE, SIZE))


main()
