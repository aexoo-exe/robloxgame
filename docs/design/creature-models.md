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

- **Mesh:** 1,772 triangles (+1,772 for the optional outline hull: 3,544 with it). Flat-shaded.
- **Texture:** `assets/models/mount_spurshot_palette.png`, 256x256: 15 swatches (coat white, spot
  dark gray, lower-leg gray, cream mane, hooves, muzzle, eyes, inner ear, tan and dark tack, blue
  medallion, light-blue blanket, saddle, outline, metal) and a star tile (light blue with pink and
  white stars) for the bedroll.
- **Look:** white coat with 12 large dark-gray spots (7 on the hindquarters, 3 mid, 2 at the
  shoulder), gray lower legs and dark hooves; cream mane tufts and a long cream tail; ears up; tan
  bridle and reins; a chest strap with a round dark-blue medallion; a light-blue blanket, a saddle and
  a star bedroll behind it. Slender racing legs (a little thicker than real, to sit with R6 bodies).
- **Rig:** 21 bones: root, spine (pivot at the hips), neck, head, two ears, three tail bones, and
  upper / lower / hoof for each leg.
- **Animations:** `idle` (90 frames, 3 s loop: weight shift, ear flicks, tail swish), `gallop`
  (20-frame loop: four-beat legs, body bob, neck pump, streaming tail), `rear_up` (56 frames: gather,
  rear up ~56 degrees about the hips with the front knees folded high and the tail streaming, a held
  top, back down).
- **Export:** `assets/models/mount_spurshot.fbx` (mesh, outline mesh, armature, the three actions;
  texture embedded; -Z forward, Y up). Scale: 1 Blender unit = 1 stud; the horse is ~5.4 studs tall
  at the ears.
- **Review renders** (local, `docs/references/models/review/`): `mount_spurshot_turntable.png` (8
  angles on gray and dark), `mount_spurshot_rig.png` (rest pose, skeleton through a see-through
  body), `mount_spurshot_anim_idle.png`, `_anim_gallop.png`, `_anim_rear_up.png` (10-12 frames each).

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
