# Style Guide: units

One look for the whole roster. Units stay recognizable as the characters they are inspired by, but
everything is drawn in our own style, from our own data. Inspirations and per-unit notes live only
in the gitignored `docs/references/` (roster-map.md, unit-sheets.md). Tracked files use unit ids and
the display names in `SkinConfig`.

Related: [vfx-style.md](vfx-style.md) (effect textures), [ultimate-playbook.md](ultimate-playbook.md)
(poses and timing), [art-roadmap.md](art-roadmap.md) (order and per-unit checklist).

## 1. Where the roster is today

Three pipelines draw units (CharacterLook picks one per unit):

| Pipeline | Source | Units | Built by |
|---|---|---|---|
| Catalog avatar (R6) | `UnitAvatarPicks` + `UnitAvatarConfig.tuning` | 38 | server (AvatarService), from catalog UGC |
| Hand-built figure | `UnitLookConfig` -> `LookKit` -> `Figure` | marsh_fortress (and the fallback of 24 avatar units) | client, from data |
| Store model | `UnitModelConfig` + `src/shared/UnitModels/` | iron_rush, skyboulder, boiling_crown, titanheart's Titan form | client, from generated part data |

Inconsistencies between them:

| Aspect | Catalog avatar | Hand-built figure | Store model |
|---|---|---|---|
| Proportions | R6: head ~0.25 of height, long limbs, wide flat torso | FigureConfig body: head 0.20, legs 0.40, torso 0.34; `proportions` per unit | whatever the model's author made (titan scale, 180 parts on iron_rush) |
| Materials | textured classic clothing (2D) + UGC meshes with their own textures and shading | SmoothPlastic flat colors | mixed (Plastic, SmoothPlastic, textures) |
| Outlines | none; a Highlight only for flash and selection | none | none |
| Colors | the UGC author's palette; can't be tinted (forms show as a Highlight tint) | our palette per unit | the author's palette |
| Hair / signature pieces | UGC hair meshes of very different detail and scale | LookKit hair styles (13 shapes), blocks | baked in |
| Weapons | LookKit weapons added on the blocky fist (longer hilts to show) | LookKit weapons | baked in or none |
| Detail level | high, uneven (one unit's hair can out-detail its whole body) | low and even | very high (heaviest figures) |
| Loading | async from the catalog; falls back to the figure if slow or failing | immediate | immediate |
| Control | none over the art (UGC can be changed or removed by its author) | full | partial (frozen data) |
| IP exposure | UGC items often copy official designs closely | ours | depends on the model |

The fallback figures and the avatars also differ for the same unit, so a slow catalog load changes a
unit's look mid-match.

## 2. Directions considered

### A. Chunky stylized figure (code-built)
- **Proportions:** about 4 heads tall: head 0.26 of height, short legs (0.34), wide shoulders,
  oversized hands and feet. Big hair and signature props, about 1.3x a realistic size.
- **Materials:** SmoothPlastic, flat colors, no reflectance. Cel tricks: a darker "shade" part under
  overhangs (hair, coat hem), a 1-step lighter top face on hair, thin dark trim parts on edges.
  Highlights stay for flashes and selection (Roblox caps live Highlights at 31 per client).
- **Palette:** 3 main colors + 1 accent per unit, mid values so effect glows read on top.
- **Signature features:** each is a data field or a LookKit piece (hair style, coat pattern,
  scarf, weapon); new pieces are added to LookKit once and reused.
- **Cost:** code only. LookKit, Figure and PoseAnimator exist; each unit is a data entry (about 1–3
  hours per unit to design and tune).
- **Rigs:** the part-built Figure is posed by channels (PoseAnimator). Real animation clips later
  would need a Motor6D rig built from the same parts: doable in code, no new art.

### B. Sleek anime proportions on R15 avatars (commissioned)
- **Proportions:** 6–7 heads tall, R15 bodies with commissioned layered clothing and hair meshes.
- **Materials:** SurfaceAppearance textures with painted shading and outlines baked in.
- **Palette:** per the artist; harder to keep one rule across 42 units.
- **Signature features:** the most faithful and detailed.
- **Cost:** commissioned meshes for every unit (hair, outfit, weapon), plus rigging checks;
  the highest budget and slowest; the most IP-sensitive look (closest to official designs).
- **Rigs:** native Roblox animation (Animator, R15) for everything; the best support for real clips.
- **At the match camera:** fine detail is lost at ~45 px tall; silhouettes read less than A's.

### C. Toon-shaded low-poly meshes (Blender pipeline)
- **Proportions:** as A (chunky), but each unit's hair, head and outfit shells are low-poly meshes
  generated or modeled in Blender (the portable Blender in `tools/`, scripts in `scripts/blender/`).
- **Materials:** a shared palette texture (flat color swatches, UV-mapped), an inverted-hull outline
  baked into each mesh (no Highlight needed), 2-tone cel shading painted into the swatches.
- **Palette:** strict, from one swatch sheet.
- **Signature features:** sculpted hair and props read much better than blocks.
- **Cost:** a mesh pipeline (generator scripts, upload through Open Cloud like the VFX kit) plus
  per-unit modeling; medium. Meshes must be uploaded and moderated.
- **Rigs:** meshes ride the same limb anchors as A; a Motor6D rig is the same work as A.

### Recommendation: A now, with C's meshes for hair and signature props later

Direction A for the whole roster, built in code on LookKit, with direction C's meshes added only
where blocks can't carry a signature feature (hair silhouettes first, then a few weapons and
creature heads).

- It replaces 38 catalog avatars we don't control (and whose UGC often copies official designs)
  with art that is fully ours, which matters in a public repo.
- One proportion and material rule for all 42, and no async catalog load: the look never swaps
  mid-match.
- The ultimates are built on PoseAnimator channels over the part-built Figure: A keeps every
  existing ultimate working unchanged; B would mean re-doing them for R15.
- Readability at the match camera is a silhouette problem; chunky proportions and oversized
  signature pieces win there, and fine detail (B) is lost.
- It can start today, unit by unit, without a budget; C's meshes slot in later on the same anchors.

## 3. Rules (direction A)

### Proportions and silhouette
- Height in "figure heights" (FigureConfig): head 0.26, torso 0.30, legs 0.34, arms 0.32 (hands
  1.3x). Big units (Titans, creatures) keep their own proportions but the same materials and rules.
- Silhouette first: each unit has one shape that reads from the match camera (~60 studs, unit ~45 px
  tall) with color off. Test it in the lineup with the board camera (DevLineup C: gameplay).
- Signature pieces are oversized: hair about 1.3x, weapons 1.2–1.5x, capes and coats reach past the
  knees only if they are the read.
- Star levels scale the whole figure (RenderConfig.starSizeScale); never add star-only parts.

### Materials and shading
- SmoothPlastic only, Reflectance 0, CastShadow on body parts and off on thin trims.
- No textures on body parts except the shared palette sheet (direction C meshes).
- Cel shading by parts: a shade part (the main color x 0.7) under hair and coat hems; a light part
  (x 1.15) on the top of the hair. At most 2 shade parts per unit.
- Outlines: none on bodies in matches (Highlights are kept for hit flashes, cast glows and
  selection). C meshes carry their own inverted-hull outline.

### Palette
- 3 main colors + 1 accent per unit. Value range 0.25–0.85 (HSV V) for large areas: pure white and
  near-black only for small areas (trim, hair) so ability glows and hit flashes stay readable.
- The accent echoes the unit's faction color (AnimationConfig.factionColors) where the inspiration
  allows: Hunters green, Corps blue, Spirit warm yellow, Cursed violet, Arcane indigo, Titans
  orange, Shinobi red, Crew gold, Heroes teal. The cost ring stays the cost's color.
- Saturation: bodies 30–70%; leave 80–100% to VFX and the UI.

### VFX harmony (see vfx-style.md)
- Effects are white cores tinted in Roblox: a unit's ultimate color is its accent or its faction
  color, never a color that matches its own main body color (it would vanish on him).
- Glows sit on mid-value bodies; avoid all-white outfits next to white-core effects (add a dark
  trim or shade part).

### UI tie-ins
- Shop cards, the unit info panel and the trait panel use the cost color and trait icons: the
  figure's accent should not fight the cost color on the board ring.
- Unit avatars in the UI (UnitAvatars) are rendered from the same figure: what reads on the board
  reads on the card.

### Do / don't
- Do carry 3–4 signature features per unit, chosen for the match camera.
- Do keep forms (FormLookConfig) in the same style: a form changes colors and adds pieces, never
  swaps to a different art style.
- Don't use catalog UGC, store models or uploaded images that copy official designs.
- Don't add fine detail that only reads in close-ups (badges, small logos, text).
- Don't use official names, logos, symbols or audio anywhere, including on outfits.

## 4. Recognizable, not copied

- Carry 3–4 **signature features** per unit (hair shape and color, an outfit block or pattern, the
  weapon, a pose or attitude), redrawn in our proportions and materials. The unit sheets
  (local only) list them.
- **Never trace** official art, screenshots or model sheets; no official assets, logos, emblems or
  audio. Patterns are our own versions (e.g. a generic checker or triangle pattern, not an exact
  reproduction).
- **Parody display names** (SkinConfig): recognizable as a nod, not the real name or a one-letter
  change of it. Unit ids are descriptive of the kit, never names.
- Ability and ultimate names describe what happens in our game, not the source's attack names.
- When in doubt, change the color or the shape of the most iconic piece a little more: the unit
  should read as "inspired by", not as "a copy of".
