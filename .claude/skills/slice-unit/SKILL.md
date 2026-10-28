---
name: slice-unit
description: Rebuild one unit's signature ultimate to the cinder_arc standard (docs/design/ultimate-playbook.md) from a short concept, review it with the playbook-reviewer agent, commit, push and summarize. Invoked as /slice-unit <unit_id> "<concept>".
argument-hint: <unit_id> "<concept>"
---

# /slice-unit

Arguments: `$ARGUMENTS`. The first word is the `unit_id`; the rest (quoted) is the concept: what the ultimate should look and feel like.

Rebuild `src/client/Ultimates/<unit_id>.luau` to the playbook's standard, using `cinder_arc` as the template. This is client presentation only. The unit's concept, wave and shared assets are in `docs/design/overhaul-plan.md`; tick its row in `docs/design/overhaul-queue.md` as you go.

**Time-box.** One build pass (steps 2-5), one review round (step 6), the Studio check with at most one fix round (step 6b), then commit, push and summarize (step 7) **even if minor issues remain**: record them as **leftovers** (summary and queue row) instead of iterating.

## Standing rules (from CLAUDE.md)

- Do **not** run tests, the audit, the sim or Blender MCP. Budget numbers are estimates you work out by hand. Studio MCP is used only for the short check in step 6b, and only if it is already connected.
- Unit ids only. No real character or anime names anywhere: code, comments, file names, asset names, commit messages.
- Never change gameplay: no edits to `src/server`, `CombatSim`, `Abilities`, `AbilityConfig`, `UnitConfig` or any event timing. Real unit positions are never moved (visual travel is `lunge` / `rise` only).
- Touch only this unit's files and entries (its `UltimateConfig` entry, its `SfxConfig.units` entry if any), plus its rows in `docs/design/overhaul-queue.md` and `sound-picks.md`.

## 0. Check and branch

1. If `unit_id` or the concept is missing, stop and ask for them.
2. Confirm the unit exists: `src/client/Ultimates/<unit_id>.luau` and its entry in `UltimateConfig.units`. If either is missing, stop and say so.
3. If on `main`, create `feature/slice-<unit_id>`. If already on a feature branch, stay on it.

## 1. Read

- `docs/design/ultimate-playbook.md` (all of it).
- `src/client/Ultimates/cinder_arc.luau`, the template.
- The unit's current module, and its `UltimateConfig.units.<unit_id>` entry (tier, preroll, linger, look, wanted).
- What the real cast emits: the current module's `def.event`, and the unit's ability in `src/shared/AbilityConfig.luau` / `Abilities.luau` (read only). The finisher must land on the real hit event, and every other real event must still be handled or drawn.
- `src/shared/SfxConfig.luau`, and the `VfxRecipe` / `ImpactEffects` / `HitFeel` / `BladeTrail` functions you plan to call. Check their signatures in the source; don't guess them.

## 2. Beat timeline first

Before writing any code, write the timeline as the module's header comment, in cinder_arc's format:

- The tier and what the real cast does at t = 0.
- Each beat with its real time at full length: coil 0.25–0.3, set/hold 0.2–0.5 with a shiver and a beat of stillness, 0.06 s snaps, follow-through holds 0.15–0.35, a 0.12 load dip, the finisher on the real hit, recover 0.25–0.3, slide home.
- How it compresses (`planOf`: holds, then set, then coil; floor 0.6; never the snaps or anything after the hit).
- Its layers, and the peak live-part estimate against the tier budget (`ReelConfig.budget`).

Fit the concept to the unit's tier and weapon. A ranged or caster unit swaps blade trails for its own readable arc, such as a trail on a hand attachment or a projectile. Every playbook cap still applies.

## 3. Rebuild the module

Follow the playbook and cinder_arc's structure:

- `SEGMENTS` / `LEAST` / `SHRINK_ORDER` / `ORDER` / `AFTER`, `planOf(k)` cached per k, `planFor(run)` in `run.memo.plan`.
- Poses about 2x realistic, built with `pose()` so each pose names every body channel. `def.poseFor` returns a `PoseAnimator.track`, cached per plan.
- `UltimateCallout.mark` through the windup and strikes. Weapon arcs come from `BladeTrail` with `viewScale = true`.
- Hits use `HitFeel.react` / `hitStop` (≤0.07 s, bodies + impact sparks) / `cameraShake`. `punchIn` goes on the finisher only.
- The finisher runs on the real event, with the fallback timer at `finisher + 0.05`.
- Every readable layer is multiplied by `VfxRecipe.viewScale(at)`. Lights and extra particles are skipped when `run.reduced`.
- Keep the `def` interface the current module uses (`poseFor`, `beats`, `release`, `event`).

Update this unit's `UltimateConfig.units.<unit_id>`: `preroll` = the full anticipation, `linger` = through the slide home and the last fade, `look` (one line, ids only), `wanted`.

## 4. Sounds

**Prefer the shared library** (`SfxConfig.library`, listed in `docs/design/sound-picks.md`): `Sfx.play("impactHeavy")`, with per-use variation through the options (`Sfx.play("whooshLight", { pitch = 1.1, volume = 0.8 })`). Use the sound cues the unit's concept names in `overhaul-plan.md`.

Signature sounds only when no library sound fits, **at most 2 per unit, and only for tier 3+ units**:

- Add them under `SfxConfig.units.<unit_id>`: `{ <sound> = { id = "", volume = ..., pitch = { ..., ... }, volumeJitter = ... } }`, with **no `fallback`**.
- Put a one-line comment above each: what it sounds like and how long it is (e.g. "a low rising hum, ~0.5 s, no impact in it").
- Call them with `Sfx.play("<unit_id>.<sound>")`. Empty ids skip silently.
- Add a row for each to `docs/design/sound-picks.md` (search terms, what it should sound like).

Optionally set `SLICE_UNIT` in `src/client/DevLineup/Config.luau` to this unit so K / G / S replay it. Mention it in the summary.

## 5. Commit

Commit in focused chunks, ids only in messages, e.g.:

1. `<unit_id> slice: beat timeline and rebuilt ultimate`
2. `<unit_id> slice: config and sound names`

End each message with the attribution line the session asks for.

## 6. Review

Run the `playbook-reviewer` agent (Agent tool, `subagent_type: "playbook-reviewer"`). Give it the branch's diff range (`main...HEAD`), the unit id and its tier.

- Fix every **FAIL** it reports. Fix a **WARN** when the fix is cheap; otherwise list it as a leftover.
- **One review round.** Don't run the reviewer again; anything still open goes to the leftovers.
- Commit the fixes: `<unit_id> slice: playbook review fixes`.

## 6b. Studio check (only if the Studio MCP is connected)

If the Roblox Studio built-in MCP server's tools are available (`start_stop_play`, `execute_luau`, `screen_capture`, `get_console_output`), do this once. If they are not available, skip this step without mentioning it.

1. Set `SLICE_UNIT` in `src/client/DevLineup/Config.luau` to this unit (Rojo syncs it), then start play with `start_stop_play`.
2. Trigger the K replay (the MCP's key input if it has one; otherwise from `execute_luau` in the client context). Use a fixed side camera: the slice camera's default framing, no orbiting between captures.
3. Capture about 6 screenshots at the key beats from your timeline: coil, set, each strike, finisher, aftermath. **At most 8 screenshots per unit.** Check `get_console_output` once for errors from the module.
4. Check them against the playbook: no screen-filling sprites or flashes, trails on the blade (or the ranged arc), readable poses at the coil, set and finisher.
5. Fix obvious problems in **at most one fix round**, commit (`<unit_id> slice: studio check fixes`), stop play with `start_stop_play`. Don't capture again after the fix. List what you saw, and anything left, as leftovers in the summary.

## 7. Push and summarize

Always reach this step, even with leftovers. `git push -u origin <branch>`. Never push or merge `main`.

End with a short summary for the user (HANDOFF blocks are paused, see CLAUDE.md), covering:

- Branch and commits.
- Files changed.
- What changed.
- **Per-unit beats:** the timeline in one or two lines.
- **Sounds:** the library sounds it uses, and any signature sounds (`<unit_id>.<sound>`) needing ids with their descriptions.
- **Budget peak:** the estimate against the tier budget, marked as an estimate.
- **Reviewer result:** pass/fail counts, and anything left as WARN.
- **Leftovers:** minor issues not fixed within the time-box.
- **Unsure:** anything not verified in Studio.
- **Next step:** usually "judge it in Studio: K, G, S".
