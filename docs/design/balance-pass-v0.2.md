COMBAT BALANCE PASS v0.2

Overall: combat is already close to target. Make a small targeted pass, then rerun the identical 200-match simulation. Do NOT globally rebalance stats yet.

==================================================
1. ROSTER CONFIG CHANGES
==================================================

MIRA QUILL
[TUNABLE]
Starbolt physical damage:
OLD: 140 / 220 / 360
NEW: 120 / 190 / 310

Attack-speed buff:
OLD: +25% / +35% / +50%
NEW: +20% / +30% / +45%

Reason: 1-cost carry is overperforming relative to 2/3-cost damage dealers. ~10–15% reduction preserves her reroll-carry identity without gutting her.

DAX IRONWIND
[TUNABLE]
Flashbreak physical damage:
OLD: 240 / 380 / 600
NEW: 300 / 475 / 750

Flashbreak target:
OLD: CURRENT_TARGET
NEW: FARTHEST_ENEMY

Dash distance:
OLD: up to 2 hexes
NEW: up to 3 hexes

Reason: Dax is substantially underperforming and his intended mobility currently provides essentially zero value. Damage increase plus functioning backline access should establish his 3-cost carry identity.

NYRA VOSS
[TUNABLE]
Voidline Shot physical damage:
OLD: 350 / 550 / 900
NEW: 320 / 500 / 800

Reason: modest ~9–11% ability reduction. She should remain an excellent 4-cost carry; avoid overcorrecting because raw damage is inflated by later-round board HP.

NO CHANGES:
Kaien, Rook, Sena, Veyra, Orin, Astra, Kairo.

Their results do not justify changing them before seeing how Mira/Dax/Nyra adjustments alter combat.

==================================================
2. DAX TARGETING
==================================================

[HARD RULE]

Flashbreak selects FARTHEST_ENEMY at cast time.

Dax DASHES up to 3 hexes toward that enemy, to the nearest valid unoccupied hex adjacent to it if reachable.

DAMAGE then hits that selected FARTHEST_ENEMY.

After casting, that enemy becomes Dax's CURRENT_TARGET.

His AttackSpeed buff remains:
+30% / +45% / +65% for 4s.

This makes Dax an actual backline diver rather than a melee unit performing a decorative dash.

[WATCH CLOSELY]
Backline access may improve his effective damage substantially beyond what the +25% ability-damage increase alone predicts. Do not buff him again until simulated.

==================================================
3. DAMAGE/FIGHT TARGETS
==================================================

These are [TUNABLE DIAGNOSTIC RANGES], NOT hard balance requirements.

Compare units primarily against same-cost/role peers because later boards contain more HP.

1-cost:
Frontline/support: 250–600
Damage carry: 700–1000

2-cost:
Tank/support: 350–750
Bruiser/carry: 750–1150

3-cost:
Tank/support: 450–900
Carry: 1100–1600

4-cost:
Tank/support: 500–1100
Carry: 1600–2200

5-cost:
Tank/utility: 700–1400
Carry: 2200–3200

More important than raw damage: cost-relative win impact, survival time, casts, and role fulfillment.

==================================================
4. TIMEOUTS
==================================================

[HARD DECISION]
Keep Combat cap = 50 seconds.

1.8% timeout rate is ACCEPTABLE.

Target timeout rate: approximately 1–3%.

A tiny timeout population is healthy for pathological tank/stalemate fights. Do not lengthen every round to accommodate the slowest ~2%.

Average fight duration of 23.2s is also acceptable despite being 0.8s below target. Do not artificially lengthen combat.

==================================================
5. ENGINE DETAIL DECISIONS
==================================================

CAST TIMING
[HARD RULE]
CONFIRM existing behavior:
Effects resolve immediately when casting begins, then 0.75s cast lockout.

Simple, responsive, deterministic.

ABILITY RANGE
[HARD RULE]
CONFIRM unlimited ability range for v0.1.

Selectors operate board-wide. Do not add ability-range validation yet.

HEAL/SHIELD TARGETING
[HARD RULE]
CONFIRM LOWEST_HP_ALLY means lowest current HP percentage anywhere on that unit's team, including self.

DASH
[HARD RULE]
CONFIRM dash is skipped when already adjacent to its selected target.

Dax's targeting change fixes his specific problem without changing global dash behavior.

BUFF STACKING
[HARD RULE]
CONFIRM:
Different sources stack.
Same caster + same stat refreshes instead of stacking.

MOVE SPEED
[HARD RULE]
CONFIRM:
Actual movement rate = 1 hex/second × Move scalar.

Do not globally buff melee movement yet. Dax's new dive provides a controlled test of whether access rather than raw movement speed is the real melee problem.

NEXT TEST:
Run the same 200-match simulation unchanged. Primary watch items are Dax damage/casts, Mira vs other low-cost carries, Nyra vs 5-cost carries, average fight duration, and timeout percentage.
