# Art Roadmap

Bringing every unit onto the style guide ([style-guide.md](style-guide.md), direction A: chunky
code-built figures, with Blender meshes later where blocks can't carry a feature). Per-unit
signature features are in the local-only `docs/references/unit-sheets.md`.

## Order

1. **Groundwork (code, once):** new FigureConfig body proportions for direction A; shade and light
   parts in LookKit (hair underside, coat hem); a lineup check mode that shows the board camera with
   colors off (silhouette test); CharacterLook switch per unit from avatar to figure (`look = "figure"`
   in UnitAvatarConfig tuning), so units move one at a time.
2. **Hero units:** cinder_arc, flashline (the two vertical-slice ultimates; everything learned there
   becomes the template).
3. **The units every player meets first:** the 1-cost pool (wolfstep, ripcord_frenzy, null_edge,
   bitter_vapor, iron_rush, blooming_aid, spurshot), since every early shop shows them.
4. **The most picked units:** take the order from the playtest pick rates
   (`lune run scripts/playtest-report <universeId>`, "unit pick rates"). Until there is data:
   the 5-costs (ascending_core, final_argument, infinite_collapse, severing_temple, boiling_crown),
   then the 4-costs.
5. **Everything else**, then the forms (FormLookConfig) and summons.
6. **Meshes (direction C)** for hair silhouettes that blocks can't carry, creature bodies
   (field_medic, marsh_fortress) and the Titans (replacing the store models).

## Code now vs needs meshes or commissions

| Work | How |
|---|---|
| Proportions, palette, coats, scarves, belts, bands, emblems, shade parts | code (LookKit data), now |
| Weapons (katanas, greatswords, daggers, staffs, rods, balls, vials) | code (LookKit.WEAPONS), now |
| Common hair shapes (spiky, messy, bob, long, twintails ...) | code (LookKit.HAIR), now; refine with meshes later |
| Distinctive hair (tilted spikes, pompadour, half bun, upswept), hats with brims | meshes (Blender pipeline) or careful block builds |
| Creature bodies (a small reindeer, a giant toad), ape and titan bodies | meshes (Blender) or commissioned models |
| Face marks, tattoo lines | our own decal patterns (uploaded images), later |
| Real animation clips | a Motor6D rig built from the figure's parts in code; clips made in Studio's animation editor |

## Per-unit checklist

For each unit, in a branch `feature/look-<unit_id>`:

- [ ] Read its sheet (local `unit-sheets.md`): the 3–4 signature features and the "far" read.
- [ ] Palette: 3 main + 1 accent (faction color where it fits); values 0.25–0.85 on large areas.
- [ ] Build the look in `UnitLookConfig` (direction A proportions); add any missing piece to LookKit
      once, as a reusable field.
- [ ] Silhouette test: lineup, board camera, colors off: the "far" feature reads.
- [ ] Star levels 1–3 and every form (F in the lineup) look right; forms keep the style.
- [ ] Its ultimate still reads on it (K / G / S if it is the slice unit, else key 3): the ultimate's
      color is not the body's main color.
- [ ] Switch the unit from its catalog avatar to the figure; remove its picks from the picker page.
- [ ] Shop card avatar (UnitAvatars) checked.
- [ ] No names, logos or traced shapes; display name is the parody one.

## Status

| Unit | Today | Needs meshes? | Notes |
|---|---|---|---|
| cinder_arc | avatar (fallback look exists) | no | hero unit 1 |
| flashline | avatar (fallback look exists) | no | hero unit 2 |
| wolfstep, null_edge, ripcord_frenzy, bitter_vapor, spurshot | avatar (fallback look exists) | no | 1-cost wave |
| blooming_aid | avatar, no fallback | no | 1-cost wave |
| iron_rush | store model | later (armor plates) | 1-cost wave; keep the model until the mesh exists |
| thunder_nest, horizon_cut, reelbreaker, redline_cut, cyclone_edge, snapfire, orbit_breaker, clockbreaker, frozen_moment, restoration_strike, crimson_hunger, shade_pack, night_parade, severing_temple, infinite_collapse, night_command, starless_burst | avatar (fallback look exists) | some hair | update the fallback look to direction A, then switch |
| volt_spear, mirror_script, echo_legion, flare_kick, threefold_crash, elastic_wardrum, burst_vector, skybreaker, zero_field, ascending_core, final_argument | avatar, no fallback | some hair | new look entry needed |
| field_medic | avatar, no fallback | yes (creature) | |
| marsh_fortress | hand-built look | yes (creature) | |
| titanheart | avatar + store-model titan form | titan form | |
| skyboulder, boiling_crown | store model | yes | keep the models until meshes exist |
