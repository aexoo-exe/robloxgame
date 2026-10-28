# Ultimate Playbook

How every signature ultimate is built. The template is `src/client/Ultimates/cinder_arc.luau`: read it alongside this. Every number here comes from it.

An ultimate dresses the unit's real cast. It is client presentation only. Combat results, event timing and real unit positions never change (see `src/shared/UltimateConfig.luau`, header).

## Modules

| Module | Role |
|---|---|
| `PoseAnimator` | Pose channels on the part-built Figure (`crouch`, `lean`, `twist`, `tilt`, `spin`, `rise`, `lunge`, arms, legs, head), not Motor6Ds. Keyframes with `ease` (`snap`, `quadOut`, `expoOut`, `back`, `inOut`, `hold`…), `hold` and `shiver`. Return the track from `def.poseFor(run)`. |
| Anticipation / `planOf` | The per-run beat layout from `run.k` (Cinematic's anticipation speed). `SEGMENTS` (full lengths), `LEAST` (floors), `SHRINK_ORDER`; returns design times (real ÷ k). Cache plans by k and keep the run's plan in `run.memo.plan`. |
| `BladeTrail` | Trails on blade attachments for weapon arcs: `BladeTrail.attach(run.view, { hand, from, to, viewScale = true })`, one `add` per cut, `enable` / `disable` around each swing, `destroy` after the last fades. |
| `HitFeel` | `react` (flash, knockback slide, stagger, finisher launch), `hitStop`, `cameraShake`, `punchIn` (finisher only). |
| `ViewScale` | Distance sizing: 1.0 at ≤20 studs → 1.8 at ≥60 (smoothstep). Use `VfxRecipe.viewScale(at)` / `ViewScale.of(at)`. |
| `UltimateCallout` | Caster outline + a small ground ring through the windup and strikes: `UltimateCallout.mark(run.view, color, run:span(...))`. |
| `Sfx` + `SfxConfig` | Named sounds: the shared `library` (`Sfx.play("impactHeavy")`, varied per use) and at most 2 signature sounds per tier 3+ unit (`Sfx.play("<unit_id>.<sound>")`). An empty `id` skips silently. No `fallback` that pings (the built-in "charge" ping read as a monotone ding). |

## Beats

```
coil 0.25–0.3  →  set / hold 0.2–0.5 (shiver, plus a beat of stillness)
→  0.06 s snaps  →  follow-through holds 0.15–0.35
→  0.12 load dip  →  FINISHER on the real hit (t = 0)
→  recover 0.25–0.3  →  slide home
```

- Everything before t = 0 is anticipation. The finisher lands exactly on the real hit (the `Area` / `Damage` event), with a fallback timer in case the event never comes.
- Visual travel only through `lunge` (dash) and `rise` (hop) pose keys. Real positions are never touched. Recover where the unit stands, then slide `lunge` back to 0.
- Write the timeline as a header comment first (see cinder_arc lines 1–30), then build to it.

## Compression

When the real window is short (`run.k < 1`), lay the anticipation out again with `planOf`:

1. Holds give first, then the set, then the coil, each down to its `LEAST`.
2. Only past that does everything shrink evenly.
3. The floor is 0.6 of `preroll` (`UltimateConfig.tiers[*].minShare`).
4. Never shrink the snaps or anything after the hit.

## Rules

- **Poses ~2x realistic.** Every body pose names every body channel, so a held pose holds still.
- **Arms: `Out` turns the raised arm, it doesn't add to it.** `<side>ArmOut` rotates about the body's forward axis after `<side>Arm` raises the arm, so an arm raised 90 forward with 85 out still points forward (it only rolls). Arms spread wide: a big `Out` on a small forward raise (about 15 / 85). Reaching forward: a big forward raise, `Out` near 0. Seen in Studio on infinite_collapse's spread.
- **Weapon arcs are trails, never static camera-facing sprites.** The one exception: a finisher swoosh that wipes in in ≤0.08 s and fades in ≤0.28 s.
- **No long-lived world-space flames near a moving caster.** Particles stay where emitted. Re-emit short flames (0.07–0.14 s) at the tip instead.
- **Hit-stop** freezes bodies and impact sparks only, for ≤0.07 s. Never trails, swooshes, blooms or the caster's own effects.
- **Reactions:** 1 stud / 15° on a strike. The finisher's main target 2.5 studs / 24° and a 0.8 launch; the others ~1.5 studs.
- **Lights:** ~1.8 brightness, range ≤1.5 unit heights, ≤0.3 s. Skipped when `run.reduced`.
- **Bloom:** ~half the area radius, pushed behind the target (away from the camera, `zOffset` negative), ≤0.45 s.
- **Rings:** at most ~1 mesh ring per impact point and 4–6 per cast (Cinematic's ring budget: 4 for tiers 1–2, 6 for 3–5).
- **ViewScale on every readable layer:** trails, swooshes, hit stars, sparks, blooms, flames, dust.
- **Shake** through `HitFeel.cameraShake` (it caps and budgets): strikes 0.12–0.15 for ~0.18 s, the finisher ~0.3 for ~0.35 s. Punch-in on the finisher only. Camera moves/dims only where the tier allows (`UltimateConfig.tiers`: tiers 4–5).
- **Budget:** peak live effect parts per tier are `ReelConfig.budget` = `{ 14, 18, 26, 34, 44 }` (tiers 1–5; same as `scripts/audit-units.luau` PEAK_LIMIT). Aim for half the tier budget at peak.
- **Sounds:** library sounds first ([sound-picks.md](sound-picks.md)); a tier 3+ unit may add at most 2 signature sounds (`SfxConfig.units`), each with an empty id and a one-line description (length, character).
- **Names:** unit ids only. Real character or anime names never go in code, file names, assets or commits.

## Dev keys (DevLineup)

| Key | Does |
|---|---|
| K | Replays the slice unit (`SLICE_UNIT` in `src/client/DevLineup/Config.luau`) on the close orbit camera. RMB drag / arrows orbit, wheel zooms, P prints and keeps the framing. |
| G | The same with the match camera (how players see it). |
| S | After K or G: the same replay at 0.25x. |

**Beat captures (Studio MCP):** `Players.LocalPlayer.DevLineupQA:Invoke("hold", beat, offset?, mode?)` from the client replays the slice and holds it at one beat: a plan name from the module (`"windup"`, `"set"`, `"load"`, `"finisher"`, ...) or a design time (`-0.5`), plus an optional offset; `mode` picks the camera: `"side"`, `"front34"` or `"back34"` (fixed views: judge poses from the front and side, not only from behind), `"gameplay"` (the match camera) or `"slice"` (K's camera as last aimed, the default); an optional 4th argument picks the preview fight's cast (default the first: units whose casts differ). It returns once held (poses, effects and the slice camera all stopped), so the next screenshot is exactly that beat. `Invoke("resume")` goes on.
