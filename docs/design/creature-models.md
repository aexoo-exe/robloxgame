# Creature Models

New stylized low-poly models for the non-human cast: two mounts (mount_spurshot,
mount_orbit_breaker), four titans (titan_iron_rush, titan_titanheart, titan_skyboulder,
titan_boiling_crown) and one summon (summon_marsh_fortress). A pilot comes first; the rest wait for
its review. Generators live in `scripts/blender/models/`; exports in `assets/models/` (ids only).
Reference images and notes are local only (`docs/references/models/`). See also
[style-guide.md](style-guide.md).

## Style rules

- **Chunky stylized low-poly** that sits next to blocky R6 avatars and block-built figures: big
  readable masses, slightly oversized heads and signature parts, flat-shaded facets, no fine detail.
- **Silhouette first:** each model must read from the match camera (~60 studs) with color off.
- **Color:** one small palette texture per model (flat swatches, nearest-neighbor, at most
  256x256; never above 1024). Each face's UVs sit on one swatch; a pattern (stars, plates) gets its
  own tile in the same texture. One material, one texture per mesh.
- **Markings:** chunky, 8-15 large patches (spots, plates, scars) made of whole faces, not noise.
- **Outline (optional):** a baked inverted hull (the mesh pushed out ~0.035 studs along its normals,
  faces flipped, the outline swatch), matching the units' thin dark outline (FigureConfig.outline).
  It doubles the triangles, so it is a separate mesh the game can leave out.
- **Limits:** about 10k triangles per model at most (target 2-5k for mounts), each mesh part under
  Roblox's per-mesh limits (well under 20k triangles), texture at most 1024.
- **Recognizable, never traced:** carry the signature features from the local notes in our own
  shapes; no official art, models or textures.
- **Rig:** a simple skeleton, rigid per-part skinning (each part fully on one bone), bones named
  `root`, `spine`, `neck`, `head`, `<part>.<side>`; animations as named actions (`idle`, a locomotion
  loop, one or two ultimate beats).

## Pilot: mount_spurshot

Generator: `scripts/blender/models/mount_spurshot.py` (headless:
`tools/blender-4.2.3-windows-x64/blender.exe -b --factory-startup --python scripts/blender/models/mount_spurshot.py`).

Version 2 (after the first review: v1 read as a crude blockout).

- **Mesh:** lofted cross-sections instead of stacked primitives: one continuous tapered barrel
  (deep chest, withers bump, belly curve, rounded rump), an arched neck thicker at the base, a head
  with cheeks and jaw, a tapered muzzle ending in a flat nostril plane, larger alert ears and a
  forelock; legs with knee / fetlock bulges, the hind leg's gaskin sloping back to the point of the
  hock and the cannon near vertical, wider hooves. **2,264 triangles** (+2,264 for the optional
  outline hull: 4,528 with it). Flat-shaded.
- **Texture:** `assets/models/mount_spurshot_palette.png`, 512x512: 18 flat swatches (top-left), a
  star tile for the bedroll (top-right), and painted coat tiles (bottom): the barrel with 13 round,
  irregular leopard spots of varied size (10 on the hindquarters and rump, 2 mid, 1 at the shoulder),
  the legs (white, gray, then dark toward the hooves, 3 small spots) and the neck (2 spots). Spots
  are painted in UV space, scaled per axis so they stay round on the body.
- **Look:** a light-blue blanket draped over the back (follows it, hangs a little at the sides, a
  darker front trim), a brown seat with a cantle, a smaller star bedroll behind the saddle with two
  ties; tan bridle and reins; a chest strap with the round dark-blue medallion; five wide cream mane
  tufts falling to one side, close to the neck (no fan in the front view); a tapered flowing tail.
- **Rig:** 22 bones: root, spine (pivot at the hips), neck, head, two ears, four tail bones, and
  upper / lower / hoof for each leg. Each ring of the lofted parts is weighted to its bone, blended
  50/50 at the joints, so the legs and tail bend without cracks.
- **Animations:** `idle` (90 frames, 3 s loop: head bob and turn, ear flicks at 20 / 42 / 62, tail
  swish, weight shift with a resting hind leg), `gallop` (20-frame loop: four-beat legs with knee and
  hock folding the lower leg back and up, body bob, head and neck counter to the body, the tail
  streaming and whipping), `rear_up` (56 frames: gather, rear up ~56 degrees about the hips with the
  front knees folded high, the tail hanging and flowing, a held top, back down).
- **Export:** `assets/models/mount_spurshot.fbx` (mesh, outline mesh, armature, the three actions;
  texture embedded; -Z forward, Y up). Scale: 1 Blender unit = 1 stud, exported at final size (v2.1).
- **Review renders** (local, `docs/references/models/review/`, `_v2`): `mount_spurshot_turntable_v2.png`
  (8 angles on gray and dark), `_rig_v2.png` (rest pose, skeleton through a see-through body),
  `_anim_idle_v2.png` (from 3/4, so the sway shows), `_anim_gallop_v2.png`, `_anim_rear_up_v2.png`
  (10-12 frames each), `_match_distance_v2.png` (game size at the match camera's angle next to a
  4.6-stud blocky figure, on the arena gray).

Version 2.1 (v2 approved; scale and spots).

- **Scale:** sized to its rider, an R6 unit 4.6 studs tall. Withers **4.14** studs (0.90x the
  rider), nose to rump **6.95** (1.51x), **5.88** to the ear tips, **1.63** wide; bounding box
  (Blender) x -0.82..0.82, y -4.13..3.58 (nose to tail tip), z 0..5.88. The generator authors the
  v2 shapes and places them after skinning: the body and neck scale by (1.067, 1.469, 1.067), so the
  horse is longer than tall; the head, legs and tail scale evenly by 1.067 about where they join, so
  they keep their v2 shapes (the bedroll is pre-squeezed so it stays round).
- **Spots:** appaloosa-style, **33** in all: 26 on the barrel (13 small on the hindquarters, 4 over
  the rump, 5 thinning along the mid barrel, 2 at the shoulder, 2 medium on the rump), 4 on the legs,
  3 on the neck. Small spots are ~0.1-0.3 studs across, the two medium ones ~0.5.
- **Rig:** 23 bones: the v2 skeleton plus `seat` (child of `spine`), its head on the saddle seat's
  top, pointing up: the rider anchor.
- **Review renders** (`_v2_1`): `mount_spurshot_turntable_v2_1.png`, `_match_distance_v2_1.png`
  (top: the match camera's angle, a figure seated on the saddle and one standing behind; bottom: a
  side view of the same, for the rider fit). Rig and animation strips are unchanged from v2 apart
  from the scale (set `FULL_RENDERS = True` to re-render them).

### Rider seat offset

The rider's hips sit on the seat anchor: the `seat` bone's head. Relative to the horse root (the
armature origin: on the ground, under the middle of the body):

| Space | Seat anchor | Horse forward |
|---|---|---|
| Blender (Z up) | (0, -0.191, 4.151) | -Y |
| Roblox (Y up, after the FBX's -Z forward / Y up axes) | (0, 4.151, 0.191) | +Z |

```lua
-- Horse root (ground point under the body) to the rider's hips, rider facing the horse's forward (+Z).
local SEAT_OFFSET = CFrame.new(0, 4.151, 0.191) * CFrame.Angles(0, math.pi, 0)
-- An R6 rider's root (torso center) sits half a torso above the hips: 0.92 studs at the 4.6-stud unit
-- size (1 at the default 5-stud R6).
local RIDER_ROOT = SEAT_OFFSET * CFrame.new(0, 0.92, 0)
```

If Studio's importer pivots the model on its bounding-box center instead of the root, the bounding
box center is (0, 2.94, 0.275) in Roblox axes from the root, so the seat is (0, 1.211, -0.084) from
the pivot. Check the forward axis on import (the head should point along +Z for these numbers);
the legs hang from the hips down the barrel's sides (straddling), so the rider's leg pose needs the
thighs turned out about 26 degrees. Integration also replaces the mount's horse scaling
(FigureConfig.horse.backHeight 0.42 of the unit): this model is already at final size.

**Review gate:** the other six models wait until this pilot is approved (style, proportions,
palette, spots, animations).

## Integration plan (not built)

What these replace: the mounts' horse today is HorseLookConfig (`model = "horse"`: a Creator Store
part model, recolored) or the block-built HorseKit horse; the titans are Creator Store part models
(UnitModelConfig + `src/shared/UnitModels/*`). All of them are posed by Figure (part pieces on
anchors, PoseAnimator channels).

### Options

1. **Skinned MeshPart + AnimationController / Animator.** Import the FBX with the 3D Importer as a
   rigged mesh (bones), play the uploaded animations through an Animator. Real deformation-free rigid
   skinning, smooth Roblox-native playback, animations made in Blender. Ultimates (PoseAnimator)
   would drive bone transforms instead of Figure channels for these units, or play named
   animation tracks at their beats.
2. **Part-based Figure posing.** Split the model per bone into MeshParts (one per part group) and
   let Figure place each on its anchor, like today's store models. Every existing pose, lunge, hop,
   hit-stop and ultimate keeps working unchanged; animations are recreated as Figure / HorseKit
   poses (Blender clips are only a reference).
3. **Hybrid.** Part-based for the titans (they mostly use the unit's own pose channels and ultimates
   already written for parts), skinned for the mounts (their gallop and rear-up are the clips that
   gain most from authored animation).

**Recommendation: option 2 now, option 1 later.** Figure posing keeps every ultimate, hit reaction
and form change working with no new animation path, and rigid per-part skinning (how the pilot is
rigged) maps one-to-one onto Figure's anchors. Move the mounts to option 1 only if their authored
gallop and rear-up look clearly better than Figure poses in Studio.

### Upload path

- **Mesh:** Studio 3D Importer (manual): File > Import 3D, the FBX, check scale (studs), import as
  one model; per-part split for option 2 (one MeshPart per bone group). Open Cloud can upload the
  mesh asset (like the VFX kit's `scripts/vfx-upload.luau`), but rigging checks still happen in
  Studio.
- **Texture:** upload the palette PNG as a Decal / Image (Open Cloud, as for the VFX textures) and
  set `MeshPart.TextureID`.
- **Animations (option 1 only):** import the FBX into the Animation Editor per action, publish each,
  keep the ids in a config.

### Performance (8 boards)

At most 8 boards, but a client draws only its own board and fight: a few mounts and at most a couple
of titans on screen. A mount at ~1.8k triangles (3.5k with the hull) is less than today's store
models (the heaviest is ~180 parts). Option 2 adds one MeshPart per bone group (~15-20 parts per
mount), similar to the store models; option 1 is one skinned MeshPart plus bones, the cheapest to draw
but an Animator per unit. Keep the outline hull off on low quality (EffectSettings).

## Remaining six

Each reuses the pilot's generator structure (palette, parts, rigid rig, actions, renders, export):

| Model | Work | Estimate |
|---|---|---|
| mount_orbit_breaker | the pilot's horse with its own coat, mane and tack palette, no spots, its own saddle details | small: a variant of the pilot |
| titan_iron_rush | armored plates as faceted shells (a plate tile in the palette), heavy proportions, a ram pose | medium |
| titan_titanheart | a gaunt long-limbed titan with long hair and steam vents, the form-change pose | medium |
| titan_skyboulder | an ape-like titan: long arms, fur as chunky facets, a boulder prop, the throw | medium |
| titan_boiling_crown | a towering skinless body (muscle bands as faceted strips), steam vents, a slow heave | medium-large (the biggest silhouette) |
| summon_marsh_fortress | a giant toad: squat body, wide mouth, pipe and vest, a hop and a splash landing | medium |

Rough cost: a mount variant about a quarter of the pilot; each titan or the toad about one pilot
(build + rig + three actions + review), since their shapes are new.
