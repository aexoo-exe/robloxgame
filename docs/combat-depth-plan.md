# Combat depth and first roster

Adds armor, magic resistance, ability power, mana, crits, damage types and a generic ability
interpreter to the pure combat sim, and replaces the placeholder units with the ten characters from
[design/combat-and-roster.md](design/combat-and-roster.md). Its section 5 deferred list is not
built.

## Modules

| Module | Role |
| --- | --- |
| `CombatConfig` | Global rules: crit 25% / 140%, base AP 100, mana per attack 10, mana per 1% HP lost 5 (cap 10), cast time 0.75 s, base move speed 1 hex/s |
| `CombatMath` (new) | Every formula: resistance multiplier, damage types, rounding with a minimum of 1, crit damage, AP scaling, mana from damage |
| `Battle` (new) | Fight state and primitives: `damage` (the only place damage is applied), `heal`, `shield`, `stun`, `buff`, `relocate`, buffed stat lookup |
| `Abilities` (new) | Generic interpreter: 7 effects, 6 selectors, per-star values, validator. No character-specific code |
| `CombatSim` | Tick loop: casting, seeded crits, buffed attack and move intervals, new event types |
| `UnitConfig` | The ten characters, stats and abilities as data |
| `UnitView`, `CombatPlayback`, `RenderConfig` | Mana bar, shield segment, cast names, stun marker, crit flash and text |
| `sim/run.luau` | Adds per-fight length and per-character damage and cast stats |

Each ability is a list of effects for the interpreter. Most map directly from the spec. Nyra's stun
uses the FARTHEST_ENEMY selector again, which resolves to the same target (see assumption 3).
Orin's armor and MR bonus is two BUFF effects.

## Assumptions (open details, simplest consistent rule)

1. **When effects land.** Effects apply at the moment the cast starts. The 0.75 s cast time is a
   lockout afterwards: the unit cannot move, attack or cast. This means:
   - A target cannot die mid-cast, and a stun cannot interrupt a cast.
   - A stun during the lockout simply overlaps it.
   - Mana resets to 0 at the cast, and the unit can gain mana during the lockout.
2. **Cast trigger.** A unit casts on its next action once its mana is full. Basic attacks are
   instant in the sim, so "finish the current action" needs no extra rule.
3. **Targeting.** Every selector the ability uses is resolved once, at the start of the cast,
   before any effect. Effects that name the same selector share one target.
   - If an effect's target is dead, that effect is skipped.
   - AREA_DAMAGE still uses its center's hex if the center died earlier in the same cast.
   - CURRENT_TARGET with no living target picks the nearest enemy.
4. **Reach.** Abilities have unlimited range. LOWEST_HP_ALLY (heals and shields) picks the lowest
   health percentage among all living allies on the field, the caster included.
5. **Dashes.**
   - Dashes are straight-line and pass over units. A valid landing cell is any free cell within
     N hexes.
   - Offensive: the valid cell adjacent to the target that is nearest the caster. If no adjacent
     cell is reachable, the valid cell nearest the target, but only if it is closer than the
     caster's current cell. An already-adjacent caster stays put.
   - Defensive: the valid cell farthest from the nearest enemy, if that improves on staying.
   - Ties go to the cell nearer the caster, then to the first cell in field order.
6. **Rook's center.** Rook's AREA_DAMAGE has no center in the spec; it uses CURRENT_TARGET (the
   punched unit).
7. **True damage and AP.** True damage does not scale with AP; the spec lists only magic damage,
   heals and shields.
8. **Rounding.** Heals and shields are rounded to whole numbers. Mana can be fractional.
9. **Stacking.**
   - Stuns do not stack; the later end time wins.
   - A buff's source is the caster plus the stat. Buffs from the same source refresh; buffs from
     different sources stack.
   - Buffed stat = (base + flat) x (1 + percent / 100).
   - A new shield of equal size replaces the current one and refreshes its duration.
10. **Mana details.** A basic attack gives +10 mana even if it deals 0 damage. Mana from damage
    counts health actually lost, from basic attacks and ability damage alike, and not damage
    absorbed by shields.
11. **Move speed.** Move speed is a scalar on `CombatConfig.baseMoveSpeed` (1 hex per second),
    which keeps the earlier pace.
12. **Practice enemies and bots.** Practice enemy boards and bot placement were mapped to the new
    characters by cost and role. They were not retuned.
13. **Orin's attack speed.** Orin's attack speed (0.60) is below the 4-cost band in
    unit-stats-economy.md (0.65-0.95). The new spec wins, so the old band test was replaced with
    an exact check against the new spec's table.

## Results (200 simulated 8-bot matches)

- Fight length: average 23.2 s (spec target 24-30 s), shortest 6.3 s, longest 50.0 s.
  1.8% of 14,664 fights hit the 50 s cap.
- Final round: average 22.0, longest 25. Match: average 24.8 min, longest 30.6 min. Winner level:
  average 7.9.
- 1-star characters, per fight they appeared in:

| Character | Cost | Damage dealt | Casts |
| --- | --- | --- | --- |
| Kaien | 1 | 340 | 2.10 |
| Mira | 1 | 1027 | 2.37 |
| Rook | 2 | 712 | 1.67 |
| Sena | 2 | 480 | 1.81 |
| Dax | 3 | 697 | 1.62 |
| Veyra | 3 | 1387 | 2.13 |
| Nyra | 4 | 2035 | 2.65 |
| Orin | 4 | 411 | 2.10 |
| Astra | 5 | 3030 | 2.06 |
| Kairo | 5 | 2303 | 2.07 |
