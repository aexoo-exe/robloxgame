"""
VFX kit, batch 2: low-poly effect meshes, exported as FBX.

Headless: tools/blender-*/blender.exe -b -P scripts/blender/vfx_meshes.py
Writes assets/vfx/meshes/mesh_*.fbx (Y up, 1 unit = 1 stud, centered on the origin).

UVs: U runs along each mesh's length (0 at the tail, 1 at the head; around for rings) and V across,
so a gradient or a batch 2 texture (fx_slash_crescent, fx_swoosh_ribbon, fx_speed_lines...) runs
along it and can be scrolled with a texture offset.
  mesh_slash_arc     a 160 degree crescent ribbon, tapered ends, slight thickness (slashes, swooshes)
  mesh_shock_ring    a shallow cone ring (inner edge raised) for expanding shockwaves
  mesh_spiral_rings  three spiral bands around a sphere volume (orbiting rings, swirls)
  mesh_twister       a tapered open cone (tornado shell) with spiral UVs
"""

import math
from pathlib import Path

import bmesh
import bpy

OUT = Path(__file__).resolve().parents[2] / "assets" / "vfx" / "meshes"
TAU = 2.0 * math.pi


def clear():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def build(name, verts, faces, uvs):
    """verts: [(x, y, z)] in Roblox axes (Y up); faces: [(i, ...)]; uvs: per face, per corner."""
    mesh = bpy.data.meshes.new(name)
    bm = bmesh.new()
    # Blender is Z up: store (x, -z, y) so the FBX export (Y up) comes back as Roblox's (x, y, z).
    bverts = [bm.verts.new((x, -z, y)) for x, y, z in verts]
    uv_layer = bm.loops.layers.uv.new("UVMap")
    for face, face_uv in zip(faces, uvs):
        f = bm.faces.new([bverts[i] for i in face])
        for loop, uv in zip(f.loops, face_uv):
            loop[uv_layer].uv = uv
    bm.normal_update()
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(obj)
    for poly in mesh.polygons:
        poly.use_smooth = True
    return obj


def strip(rows, closed=False):
    """Quads between consecutive rows of vertex indices (each row the same length)."""
    faces = []
    for a, b in zip(rows, rows[1:] + ([rows[0]] if closed else [])):
        for k in range(len(a) - 1):
            faces.append((a[k], a[k + 1], b[k + 1], b[k]))
    return faces


# ---------------------------------------------------------------- slash arc

def slash_arc():
    steps, across = 24, 3
    span = math.radians(160)
    radius, width, thick = 2.0, 0.55, 0.06
    verts, rows, uvrows = [], [], []
    for i in range(steps + 1):
        u = i / steps
        ang = -span / 2 + span * u
        w = width * math.sin(math.pi * u) ** 0.8 + 0.01  # tapered ends
        row, uvrow = [], []
        for j in range(across + 1):
            v = j / across
            r = radius - w / 2 + w * v
            y = thick * math.sin(math.pi * v) * (1.0 if w > 0.02 else 0.0)  # slight thickness, a ridge
            verts.append((math.sin(ang) * r, y, -math.cos(ang) * r))
            row.append(len(verts) - 1)
            uvrow.append((u, v))
        rows.append(row)
        uvrows.append(uvrow)
    faces = strip(rows)
    uvs = []
    for i in range(steps):
        for k in range(across):
            uvs.append([uvrows[i][k], uvrows[i][k + 1], uvrows[i + 1][k + 1], uvrows[i + 1][k]])
    return build("mesh_slash_arc", verts, faces, uvs)


# ---------------------------------------------------------------- shock ring

def shock_ring():
    segments = 48
    inner, outer, rise = 0.65, 1.0, 0.12
    verts, rows, uvrows = [], [], []
    for i in range(segments + 1):
        u = i / segments
        ang = TAU * u
        row, uvrow = [], []
        for v, r, y in ((0.0, inner, rise), (0.5, (inner + outer) / 2, rise * 0.35), (1.0, outer, 0.0)):
            verts.append((math.cos(ang) * r, y, math.sin(ang) * r))
            row.append(len(verts) - 1)
            uvrow.append((u, v))
        rows.append(row)
        uvrows.append(uvrow)
    faces = strip(rows)
    uvs = []
    for i in range(segments):
        for k in range(2):
            uvs.append([uvrows[i][k], uvrows[i][k + 1], uvrows[i + 1][k + 1], uvrows[i + 1][k]])
    return build("mesh_shock_ring", verts, faces, uvs)


# ---------------------------------------------------------------- spiral rings

def spiral_rings():
    bands, steps = 3, 64
    radius, half = 1.0, 0.09
    verts, faces, uvs = [], [], []
    for b in range(bands):
        tilt = math.radians(25 + 30 * b)
        phase = b * TAU / bands
        base = len(verts)
        rowsuv = []
        for i in range(steps + 1):
            u = i / steps
            ang = TAU * u * 1.25 + phase  # a little more than one turn: a spiral, not a circle
            lat = math.sin(TAU * u * 0.5) * 0.35  # drifts up and down: wraps the volume
            for side in (-1.0, 1.0):
                a = ang
                la = lat + side * half
                x = math.cos(a) * math.cos(la) * radius
                y = math.sin(la) * radius
                z = math.sin(a) * math.cos(la) * radius
                # Tilt each band around X so the three cross.
                y, z = y * math.cos(tilt) - z * math.sin(tilt), y * math.sin(tilt) + z * math.cos(tilt)
                verts.append((x, y, z))
            rowsuv.append(u)
        for i in range(steps):
            a0, b0 = base + 2 * i, base + 2 * i + 1
            a1, b1 = a0 + 2, b0 + 2
            faces.append((a0, a1, b1, b0))
            u0, u1 = rowsuv[i], rowsuv[i + 1]
            uvs.append([(u0, 0.0), (u1, 0.0), (u1, 1.0), (u0, 1.0)])
    return build("mesh_spiral_rings", verts, faces, uvs)


# ---------------------------------------------------------------- twister

def twister():
    segments, levels = 32, 12
    height, bottom, top, twist = 3.0, 0.2, 1.2, 1.5
    verts, rows, uvrows = [], [], []
    for j in range(levels + 1):
        v = j / levels
        r = bottom + (top - bottom) * v ** 1.3
        row, uvrow = [], []
        for i in range(segments + 1):
            u = i / segments
            ang = TAU * u
            verts.append((math.cos(ang) * r, height * v, math.sin(ang) * r))
            row.append(len(verts) - 1)
            uvrow.append((u + twist * v, v))  # spiral UVs: U shears with height
        rows.append(row)
        uvrows.append(uvrow)
    faces, uvs = [], []
    for j in range(levels):
        for i in range(segments):
            a, b = rows[j][i], rows[j][i + 1]
            c, d = rows[j + 1][i + 1], rows[j + 1][i]
            faces.append((a, b, c, d))
            uvs.append([uvrows[j][i], uvrows[j][i + 1], uvrows[j + 1][i + 1], uvrows[j + 1][i]])
    return build("mesh_twister", verts, faces, uvs)


MESHES = [slash_arc, shock_ring, spiral_rings, twister]


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    for make in MESHES:
        clear()
        obj = make()
        path = OUT / f"{obj.name}.fbx"
        bpy.ops.object.select_all(action="DESELECT")
        obj.select_set(True)
        bpy.ops.export_scene.fbx(
            filepath=str(path),
            use_selection=True,
            axis_forward="-Z",
            axis_up="Y",
            apply_unit_scale=True,
            mesh_smooth_type="FACE",
            add_leaf_bones=False,
            bake_anim=False,
        )
        print(f"[vfx-b2] {path.name}: {len(obj.data.vertices)} verts, {len(obj.data.polygons)} faces")


if __name__ == "__main__":
    main()
