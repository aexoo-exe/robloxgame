"""mount_spurshot: the pilot creature model (docs/design/creature-models.md).

A chunky stylized low-poly horse built from primitives, one mesh with one palette material
(a 256x256 texture: flat color swatches + a star tile for the bedroll), a simple skeleton with rigid
per-part skinning, three animations (idle, gallop loop, rear-up), an optional inverted-hull outline
mesh, FBX export and review renders.

Run headless from the repository root:
  tools/blender-4.2.3-windows-x64/blender.exe -b --factory-startup --python scripts/blender/models/mount_spurshot.py

Writes:
  assets/models/mount_spurshot.fbx            mesh + outline mesh + armature + 3 animations (tracked)
  assets/models/mount_spurshot_palette.png    the palette texture (tracked)
  docs/references/models/review/mount_spurshot_*.png   review renders (gitignored)
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
FPS = 30
OUTLINE = 0.035  # inverted-hull thickness (studs)
random.seed(7)

# -------------------------------------------------------------------------------------------------
# Palette: 8x4 swatches of 32 px in the top half, a star tile in the bottom half.
# -------------------------------------------------------------------------------------------------

def srgb(r, g, b):
    return (r / 255, g / 255, b / 255, 1.0)

SWATCHES = {
    "coat": srgb(236, 237, 240),
    "spot": srgb(78, 82, 92),
    "legshade": srgb(150, 153, 160),
    "mane": srgb(240, 224, 172),
    "hoof": srgb(58, 58, 64),
    "muzzle": srgb(128, 130, 138),
    "eye": srgb(20, 20, 26),
    "earinner": srgb(205, 160, 160),
    "tack": srgb(176, 124, 72),
    "tackdark": srgb(112, 74, 42),
    "medallion": srgb(36, 64, 150),
    "blanket": srgb(138, 196, 232),
    "saddle": srgb(150, 102, 60),
    "outline": srgb(22, 22, 30),
    "metal": srgb(200, 204, 214),
}
SWATCH_INDEX = {name: index for index, name in enumerate(SWATCHES)}
STAR_BG = srgb(150, 204, 236)
STAR_PINK = srgb(236, 120, 170)
STAR_WHITE = srgb(250, 250, 255)
SIZE = 256


def swatch_uv(name):
    index = SWATCH_INDEX[name]
    col, row = index % 8, index // 8
    return ((col + 0.5) / 8, 1 - (row + 0.5) / 8)


def star_inside(px, py, cx, cy, radius):
    """Point inside a 5-point star centered at (cx, cy)."""
    dx, dy = px - cx, py - cy
    r = math.hypot(dx, dy)
    if r > radius:
        return False
    angle = math.atan2(dy, dx) + math.pi / 2
    sector = (angle % (2 * math.pi / 5)) / (2 * math.pi / 5)
    edge = radius * (0.45 + 0.55 * abs(sector - 0.5) * 2)
    return r <= edge


def make_palette():
    pixels = np.zeros((SIZE, SIZE, 4), dtype=np.float32)
    for name, color in SWATCHES.items():
        index = SWATCH_INDEX[name]
        col, row = index % 8, index // 8
        y0 = SIZE - (row + 1) * 32
        pixels[y0 : y0 + 32, col * 32 : (col + 1) * 32] = color
    # Unused swatch cells stay coat white.
    for index in range(len(SWATCHES), 32):
        col, row = index % 8, index // 8
        y0 = SIZE - (row + 1) * 32
        pixels[y0 : y0 + 32, col * 32 : (col + 1) * 32] = SWATCHES["coat"]
    # The star tile (bottom half): light blue with pink and white stars.
    pixels[0:128, :] = STAR_BG
    stars = [(28, 30, 13, STAR_PINK), (92, 92, 12, STAR_WHITE), (150, 34, 13, STAR_PINK), (214, 88, 12, STAR_WHITE),
             (60, 100, 9, STAR_WHITE), (186, 20, 9, STAR_PINK), (122, 60, 9, STAR_WHITE), (240, 30, 9, STAR_PINK)]
    for y in range(128):
        for x in range(SIZE):
            for cx, cy, radius, color in stars:
                if star_inside(x, y, cx, cy, radius):
                    pixels[y, x] = color
    image = bpy.data.images.new(NAME + "_palette", SIZE, SIZE, alpha=False)
    image.pixels = pixels.flatten()
    image.filepath_raw = os.path.join(ASSETS, NAME + "_palette.png")
    image.file_format = "PNG"
    image.save()
    return image


# -------------------------------------------------------------------------------------------------
# Geometry
# -------------------------------------------------------------------------------------------------

PARTS = []  # (object, bone name)


def finish(obj, bone, color):
    """Flat-colors every face of a part (its UVs on one swatch) and records its bone."""
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


def limb(a, b, r1, r2, bone, color, sides=8):
    location, length, rotation = between(b, a)  # radius1 at `a`'s end
    bpy.ops.mesh.primitive_cone_add(vertices=sides, radius1=r2, radius2=r1, depth=length, location=location,
                                    rotation=rotation)
    return finish(bpy.context.active_object, bone, color)


def blob(location, scale, bone, color, segments=14, rings=9):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=segments, ring_count=rings, radius=1, location=location)
    obj = bpy.context.active_object
    obj.scale = scale
    bpy.ops.object.transform_apply(scale=True)
    return finish(obj, bone, color)


def box(location, scale, bone, color, rotation=(0, 0, 0)):
    bpy.ops.mesh.primitive_cube_add(size=2, location=location, rotation=rotation)
    obj = bpy.context.active_object
    obj.scale = scale
    bpy.ops.object.transform_apply(scale=True, rotation=True)
    return finish(obj, bone, color)


def build_horse():
    # Body: chest, barrel and hindquarters, overlapping. Faces -Y.
    chest = blob((0, -0.95, 3.15), (0.66, 0.85, 0.78), "spine", "coat")
    barrel = blob((0, 0.05, 3.05), (0.64, 1.15, 0.72), "spine", "coat")
    hind = blob((0, 1.0, 3.18), (0.7, 0.85, 0.8), "spine", "coat")
    # Neck and head.
    limb((0, -1.2, 3.55), (0, -2.05, 4.75), 0.52, 0.34, "neck", "coat")
    head = box((0, -2.55, 4.55), (0.31, 0.62, 0.34), "head", "coat", rotation=(math.radians(-38), 0, 0))
    box((0, -2.98, 4.18), (0.24, 0.24, 0.24), "head", "muzzle", rotation=(math.radians(-38), 0, 0))
    for side in (-1, 1):
        limb((side * 0.15, -2.2, 4.95), (side * 0.2, -2.18, 5.42), 0.09, 0.02, "ear." + ("L" if side > 0 else "R"),
             "coat", sides=5)
        box((side * 0.275, -2.55, 4.72), (0.03, 0.07, 0.06), "head", "eye")
    # Mane: blocky tufts along the neck, and a forelock.
    for i in range(6):
        t = i / 5
        y = -1.35 + (-2.05 + 1.35) * t
        z = 3.95 + (4.95 - 3.95) * t
        box((0, y + 0.18, z + 0.12), (0.1, 0.16, 0.24), "neck", "mane", rotation=(math.radians(-35), 0, 0))
    box((0, -2.28, 4.98), (0.12, 0.12, 0.18), "head", "mane", rotation=(math.radians(-50), 0, 0))
    # Legs: upper, lower, hoof. Slender racing legs.
    legs = {"FL": (0.38, -1.15), "FR": (-0.38, -1.15), "BL": (0.4, 1.2), "BR": (-0.4, 1.2)}
    for key, (x, y) in legs.items():
        back = key[0] == "B"
        knee = (x, y + (0.12 if back else 0), 1.35)
        limb((x, y, 2.75), knee, 0.3 if back else 0.26, 0.17, "upper." + key, "coat")
        limb(knee, (x, y, 0.22), 0.16, 0.14, "lower." + key, "legshade")
        limb((x, y, 0.22), (x, y, 0.0), 0.16, 0.18, "hoof." + key, "hoof", sides=8)
    # Tail: three flowing segments.
    limb((0, 1.75, 3.45), (0, 2.15, 2.85), 0.17, 0.2, "tail.1", "mane")
    limb((0, 2.15, 2.85), (0, 2.4, 2.05), 0.2, 0.18, "tail.2", "mane")
    limb((0, 2.4, 2.05), (0, 2.5, 1.25), 0.18, 0.07, "tail.3", "mane")
    # Tack: noseband, cheek straps, reins, chest strap with the medallion.
    bpy.ops.mesh.primitive_torus_add(major_radius=0.3, minor_radius=0.035, major_segments=10, minor_segments=4,
                                     location=(0, -2.85, 4.3), rotation=(math.radians(52), 0, 0))
    finish(bpy.context.active_object, "head", "tack")
    for side in (-1, 1):
        limb((side * 0.29, -2.75, 4.35), (side * 0.29, -2.3, 4.85), 0.03, 0.03, "head", "tack", sides=4)
        limb((side * 0.3, -2.9, 4.25), (side * 0.32, -1.3, 3.95), 0.025, 0.025, "neck", "tackdark", sides=4)
    bpy.ops.mesh.primitive_torus_add(major_radius=0.7, minor_radius=0.06, major_segments=16, minor_segments=4,
                                     location=(0, -1.12, 3.15))
    strap = bpy.context.active_object
    # Keep only the front half of the strap ring (it wraps the chest).
    bm = bmesh.new()
    bm.from_mesh(strap.data)
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if v.co.y > 0.05], context="VERTS")
    bm.to_mesh(strap.data)
    bm.free()
    finish(strap, "spine", "tack")
    bpy.ops.mesh.primitive_cylinder_add(vertices=12, radius=0.17, depth=0.08, location=(0, -1.84, 3.15),
                                        rotation=(math.radians(90), 0, 0))
    finish(bpy.context.active_object, "spine", "medallion")
    # Saddle blanket, saddle, and the star bedroll behind it.
    box((0, -0.05, 3.72), (0.72, 0.62, 0.06), "spine", "blanket")
    for side in (-1, 1):
        box((side * 0.66, -0.05, 3.35), (0.05, 0.6, 0.38), "spine", "blanket")
    box((0, -0.1, 3.84), (0.38, 0.42, 0.08), "spine", "saddle")
    bpy.ops.mesh.primitive_cylinder_add(vertices=12, radius=0.26, depth=1.3, location=(0, 0.75, 4.0),
                                        rotation=(0, math.radians(90), 0))
    roll = bpy.context.active_object
    finish(roll, "spine", "blanket")
    star_map(roll)
    for x in (-0.35, 0.35):
        bpy.ops.mesh.primitive_torus_add(major_radius=0.275, minor_radius=0.03, major_segments=10, minor_segments=4,
                                         location=(x, 0.75, 4.0), rotation=(0, math.radians(90), 0))
        finish(bpy.context.active_object, "spine", "tackdark")
    return chest, barrel, hind


def star_map(obj):
    """UVs of the bedroll on the star tile: around the roll -> u, along it -> v (0-0.5)."""
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    uv = bm.loops.layers.uv.verify()
    center = Vector((0, 0.75, 4.0))
    for face in bm.faces:
        for loop in face.loops:
            p = obj.matrix_world @ loop.vert.co - center
            u = (math.atan2(p.z, p.y) / (2 * math.pi)) % 1.0
            v = (p.x / 1.3 + 0.5) * 0.48 + 0.01
            loop[uv].uv = (u, v)
    bm.to_mesh(obj.data)
    bm.free()


def spots(body_parts):
    """8-15 large dark spots (whole faces), most on the hindquarters; darker toward the feet."""
    faces = []
    for obj in body_parts:
        for poly in obj.data.polygons:
            faces.append((obj, poly.index, obj.matrix_world @ poly.center))
    candidates = [f for f in faces if f[2].z > 2.6]
    hind = [f for f in candidates if f[2].y > 0.35]
    mid = [f for f in candidates if -0.6 < f[2].y <= 0.35]
    front = [f for f in candidates if f[2].y <= -0.6]
    centers = random.sample(hind, 7) + random.sample(mid, 3) + random.sample(front, 2)
    chosen = set()
    for _, _, point in centers:
        radius = random.uniform(0.28, 0.42)
        for obj, index, center in faces:
            if (center - point).length < radius:
                chosen.add((obj.name, index))
    u, v = swatch_uv("spot")
    for obj in body_parts:
        bm = bmesh.new()
        bm.from_mesh(obj.data)
        uv = bm.loops.layers.uv.verify()
        bm.faces.ensure_lookup_table()
        for face in bm.faces:
            if (obj.name, face.index) in chosen:
                for loop in face.loops:
                    loop[uv].uv = (u, v)
        bm.to_mesh(obj.data)
        bm.free()
    return len(centers)


# -------------------------------------------------------------------------------------------------
# Rig
# -------------------------------------------------------------------------------------------------

BONES = {
    # name: (head, tail, parent)
    "root": ((0, 0, 0), (0, 0, 0.6), None),
    "spine": ((0, 1.2, 3.15), (0, -1.15, 3.25), "root"),
    "neck": ((0, -1.2, 3.55), (0, -2.05, 4.75), "spine"),
    "head": ((0, -2.05, 4.75), (0, -3.05, 4.15), "neck"),
    "ear.L": ((0.15, -2.2, 4.95), (0.2, -2.18, 5.42), "head"),
    "ear.R": ((-0.15, -2.2, 4.95), (-0.2, -2.18, 5.42), "head"),
    "tail.1": ((0, 1.75, 3.45), (0, 2.15, 2.85), "spine"),
    "tail.2": ((0, 2.15, 2.85), (0, 2.4, 2.05), "tail.1"),
    "tail.3": ((0, 2.4, 2.05), (0, 2.5, 1.25), "tail.2"),
}
for _key, (_x, _y) in {"FL": (0.38, -1.15), "FR": (-0.38, -1.15), "BL": (0.4, 1.2), "BR": (-0.4, 1.2)}.items():
    _back = _key[0] == "B"
    _knee = (_x, _y + (0.12 if _back else 0), 1.35)
    BONES["upper." + _key] = ((_x, _y, 2.75), _knee, "spine")
    BONES["lower." + _key] = (_knee, (_x, _y, 0.22), "upper." + _key)
    BONES["hoof." + _key] = ((_x, _y, 0.22), (_x, _y, 0.0), "lower." + _key)


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
        group = obj.vertex_groups.new(name=bone)
        group.add(range(len(obj.data.vertices)), 1.0, "REPLACE")
    bpy.ops.object.select_all(action="DESELECT")
    for obj, _ in PARTS:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = PARTS[0][0]
    bpy.ops.object.join()
    mesh = bpy.context.active_object
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
    """An inverted hull: the mesh pushed out along its normals, faces flipped, outline color."""
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
# bone down and swings a downward-pointing bone back)
# -------------------------------------------------------------------------------------------------

def key(arm, frame, values):
    """values: { bone: (x, y, z) degrees } or { "root.loc": (x, y, z) }."""
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


def anim_idle(arm):
    action = new_action(arm, "idle")
    length = 90
    for frame in range(0, length + 1, 6):
        t = frame / length
        sway = math.sin(t * 2 * math.pi)
        values = {
            "spine": (0, sway * 2.0, 0),
            "root.loc": (sway * 0.04, 0, -abs(sway) * 0.02),
            "neck": (math.sin(t * 2 * math.pi + 0.8) * 3, 0, 0),
            "head": (math.sin(t * 2 * math.pi + 1.6) * 2, 0, 0),
            "tail.1": (0, 0, math.sin(t * 4 * math.pi) * 8),
            "tail.2": (0, 0, math.sin(t * 4 * math.pi - 0.6) * 10),
            "upper.BL": (sway * -2, 0, 0),
            "upper.BR": (sway * 2, 0, 0),
        }
        # An ear flick around frame 40 (L) and 66 (R).
        values["ear.L"] = (0, 0, -28 if 38 <= frame <= 44 else 0)
        values["ear.R"] = (0, 0, 28 if 64 <= frame <= 70 else 0)
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
            values["upper." + leg] = (-swing * (38 if front else 32), 0, 0)
            # The lower leg folds while the leg comes forward (swing rising).
            fold = max(0.0, math.cos(p * 2 * math.pi)) * (55 if front else -50)
            values["lower." + leg] = (fold, 0, 0)
        bob = math.sin(t * 4 * math.pi)
        values["spine"] = (math.sin(t * 2 * math.pi) * 5, 0, 0)
        values["root.loc"] = (0, 0, 0.18 + bob * 0.12)
        values["neck"] = (-math.sin(t * 2 * math.pi) * 7, 0, 0)
        values["head"] = (math.sin(t * 2 * math.pi) * 4, 0, 0)
        values["tail.1"] = (28 + math.sin(t * 2 * math.pi) * 6, 0, 0)
        values["tail.2"] = (12 + math.sin(t * 2 * math.pi - 0.7) * 8, 0, 0)
        values["tail.3"] = (8 + math.sin(t * 2 * math.pi - 1.4) * 10, 0, 0)
        values["ear.L"] = (-15, 0, 0)
        values["ear.R"] = (-15, 0, 0)
        key(arm, frame, values)
    make_cyclic(action)
    return action, (0, length)


def anim_rear(arm):
    action = new_action(arm, "rear_up")
    # The spine pitches up about the hips (its head); the hind legs counter-rotate to stay planted.
    poses = [
        (0, 0.0, 0.0),
        (10, 0.15, 0.25),  # gather
        (22, 1.0, 1.0),  # reared
        (34, 1.0, 1.05),  # hold at the top, front hooves pawing
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
            "lower.BL": (-12 * up, 0, 0),
            "lower.BR": (-12 * up, 0, 0),
            "upper.FL": (-70 * paw, 0, 0),
            "upper.FR": (-58 * paw, 0, 0),
            "lower.FL": (118 * paw, 0, 0),
            "lower.FR": (104 * paw, 0, 0),
            "neck": (-14 * up, 0, 0),
            "head": (18 * up, 0, 0),
            "tail.1": (62 * up, 0, 0),
            "tail.2": (18 * up, 0, 0),
            "tail.3": (14 * up, 0, 0),
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
    cam_data.ortho_scale = 8.2
    cam = bpy.data.objects.new("cam", cam_data)
    scene.collection.objects.link(cam)
    scene.camera = cam
    return cam


def aim(cam, angle_deg, elevation_deg=12, target=(0, 0.2, 2.6), distance=20):
    a, e = math.radians(angle_deg), math.radians(elevation_deg)
    t = Vector(target)
    cam.location = t + Vector((math.sin(a) * math.cos(e), -math.cos(a) * math.cos(e), math.sin(e))) * distance
    cam.rotation_euler = (t - cam.location).to_track_quat("-Z", "Y").to_euler()


def render_to(scene, path, size):
    scene.render.resolution_x = size
    scene.render.resolution_y = size
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)


def load_pixels(path):
    image = bpy.data.images.load(path)
    w, h = image.size
    pixels = np.array(image.pixels[:], dtype=np.float32).reshape(h, w, 4)
    bpy.data.images.remove(image)
    return pixels


def save_sheet(rows, path):
    """rows: list of lists of pixel arrays (same size). Row 0 is the top row."""
    tile_h, tile_w = rows[0][0].shape[:2]
    sheet = np.ones((tile_h * len(rows), tile_w * max(len(r) for r in rows), 4), dtype=np.float32)
    for r, row in enumerate(rows):
        y0 = (len(rows) - 1 - r) * tile_h  # image rows start at the bottom
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
    save_sheet(rows, os.path.join(REVIEW, NAME + "_turntable.png"))


def frame_strip(scene, cam, arm, action, frames, name, count):
    arm.animation_data.action = action
    scene.world.color = (0.42, 0.42, 0.44)
    aim(cam, 90, 8, target=(0, 0.4, 3.0))  # side view, room above for the rear-up
    cam.data.ortho_scale = 10.5
    start, end = frames
    row = []
    for i in range(count):
        frame = round(start + (end - start) * i / max(1, count - 1))
        scene.frame_set(frame)
        path = tmp("%s%d" % (name, i))
        render_to(scene, path, 320)
        row.append(load_pixels(path))
    save_sheet([row], os.path.join(REVIEW, NAME + "_anim_" + name + ".png"))
    cam.data.ortho_scale = 8.2


def rig_render(scene, cam, arm, mesh, outline):
    """The rest pose with the skeleton drawn as orange sticks through a see-through body."""
    arm.data.pose_position = "REST"
    sticks = []
    stick_material = bpy.data.materials.new("bone")
    stick_material.diffuse_color = (1.0, 0.45, 0.05, 1)
    for name, (head, tail, _parent) in BONES.items():
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
    rows = []
    row = []
    for angle in (90, 30):
        aim(cam, angle, 10)
        path = tmp("rig%d" % angle)
        render_to(scene, path, 512)
        row.append(load_pixels(path))
    rows.append(row)
    save_sheet(rows, os.path.join(REVIEW, NAME + "_rig.png"))
    for stick in sticks:
        bpy.data.objects.remove(stick)
    shading.color_type = "TEXTURE"
    shading.show_xray = False
    outline.hide_render = False
    arm.data.pose_position = "POSE"


# -------------------------------------------------------------------------------------------------

def main():
    os.makedirs(ASSETS, exist_ok=True)
    os.makedirs(REVIEW, exist_ok=True)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.render.fps = FPS

    image = make_palette()
    material = make_material(image)
    body = build_horse()
    spot_count = spots(list(body))
    arm = build_rig()
    mesh = join_and_skin(arm, material)
    outline = make_outline(mesh, material)

    idle, idle_range = anim_idle(arm)
    gallop, gallop_range = anim_gallop(arm)
    rear, rear_range = anim_rear(arm)
    arm.animation_data.action = idle

    tris = sum(len(p.vertices) - 2 for p in mesh.data.polygons)
    outline_tris = sum(len(p.vertices) - 2 for p in outline.data.polygons)

    # FBX: mesh, outline mesh and armature with every action.
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

    # Review renders.
    setup_render(scene)
    cam = camera(scene)
    scene.frame_set(0)
    arm.data.pose_position = "REST"
    turntable(scene, cam)
    arm.data.pose_position = "POSE"
    rig_render(scene, cam, arm, mesh, outline)
    frame_strip(scene, cam, arm, idle, idle_range, "idle", 10)
    frame_strip(scene, cam, arm, gallop, gallop_range, "gallop", 10)
    frame_strip(scene, cam, arm, rear, rear_range, "rear_up", 12)
    for name in os.listdir(REVIEW):
        if name.startswith("_tmp_"):
            os.remove(os.path.join(REVIEW, name))

    print("MODEL %s: %d tris (+%d outline hull), %d bones, %d spots, palette %dx%d" % (
        NAME, tris, outline_tris, len(BONES), spot_count, SIZE, SIZE))


main()
