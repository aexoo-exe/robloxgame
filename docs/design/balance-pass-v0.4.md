POST-TRAIT STRUCTURE / BALANCE PASS v0.4

[H] = structural decision / implement.
[T] = tunable starting value.
[?] = lower-confidence; validate by simulation.

CORE RULES
[H] KEEP all three implemented rules:
- Trait count = unique characters on board; duplicate copies count once; bench does not count.
- "All allies" = all deployed units.
- Warden combat-start SHIELD scales with each Warden's AP; existing larger-shield-only rule remains.

These are clean and should not change.


1. TRAIT REACHABILITY + NEW VALUES

Design rule [H]:
Origins with 4 members become 2/3.
Eclipse (5 members) becomes 2/3/4.
Classes should generally require commitment, NOT near-total membership.
6-unit class caps become 5.
Four/five-member classes cap at 3.

ORIGINS

IRONVEIL (4 members)
2: +14 Armor/MR [T]
3: +32 Armor/MR [T]

EMBERWAKE (4)
2: +14% AD [T]
3: +28% AD, +18% AS [T]

TIDEGLASS (4)
2: Tideglass +18 AP; all allies +9 MR [T]
3: Tideglass +40 AP; all allies +20 MR [T]

STORMCREST (4)
2: +18% AS [T]
3: +40% AS, +18% MoveSpeed [T]

STARFALL (4)
2: +24 AP [T]
3: +52 AP [T]

ECLIPSE (5)
2: +12% AD, +12 AP [T]
3: +23% AD, +23 AP [T]
4: +38% AD, +45 AP [T]

CLASSES

VANGUARD (7 members)
2: +12 Armor/MR [T]
4: +25 Armor/MR [T]
5: +42 Armor/MR [T]

WARDEN (5)
2: combat-start SHIELD 140 for 6s [T]
3: combat-start SHIELD 310 for 6s [T]

DUELIST (7)
2: +14% AS [T]
4: +32% AS [T]
5: +55% AS [T]

MARKSMAN (4)
2: +14% AD [T]
3: +33% AD [T]

ARCANIST (7)
2: +18 AP [T]
4: +40 AP [T]
5: +68 AP [T]

MYSTIC (5)
2: all allies +12 MR; Mystics +12 AP [T]
3: all allies +28 MR; Mystics +30 AP [T]

REAVER (6)
2: +12% AD, +12% AS [T]
4: +23% AD, +28% AS [T]
5: +38% AD, +50% AS [T]

[H] This deliberately makes top origins achievable with 3–4 slots and top classes achievable with 3–5 slots. A capstone should represent commitment, not "own literally every character."


2. TRAIT IMPACT

[H] Increase bonuses modestly, approximately 10–20% versus v0.1, as reflected above.

Do NOT make a huge power jump.

22.8s vs 23.6s does NOT mean traits are ineffective: traits redistribute combat power, and placement data already shows meaningful advantages (Arcanist 4 = 2.05, Reaver 4 = 2.33).

The bigger problem was breakpoint accessibility, not raw trait strength.

Goal [T]:
A completed mid breakpoint should be clearly noticeable.
A capstone should materially influence composition choice without automatically beating a stronger upgraded board.


3. TIMEOUTS

[H] ONE LEVER:
Global HP multiplier from v0.3:
1.15x -> 1.12x base HP.

Nothing else globally changes.

Reason:
4.7% timeouts is too high, while average combat is already below the original 24–30 target. This suggests a long-tail durability problem rather than universally slow fights.

Expected [?]:
Average ~22.2–22.6s.
Timeouts ~2.5–3.5%.

If timeouts remain >3%, investigate WHICH units/compositions create them before another global adjustment. Do not keep cutting HP blindly.


4. UNIT OUTLIERS

LIO — CHANGE [T]
Gale Edge DAMAGE:
115/180/290 -> 130/205/330.
AS buff remains 15/25/40%.

Reason: -16% is large enough that trait restructuring alone shouldn't be trusted to fix him.

IONE — HOLD [H]
Skyneedle remains 220/350/560.
AD buff remains 10/15/25%.

Reason: +14% is probably trait-driven and Marksman 3 is being completely redesigned. Measure first.

SOLENNE — HOLD [H]
Nova Lance remains 300/480/780.
AP buff remains 20/35/55.

Reason: +9% is acceptable noise for a synergy-sensitive carry, especially before testing reachable Starfall/Marksman/Arcanist caps.

VELA — HOLD [H]
Black Arc remains 210/340/550.
AP buff remains 15/25/40.

Reason: +9% is too small to justify contaminating the trait-breakpoint experiment.

KES — HOLD.
TORRA — HOLD.

[H] Next run should primarily test STRUCTURE, not simultaneously rebalance every beneficiary.


5. REROLLING

[H] YES: rerolling should be a legitimate alternate strategy.

A shop/economy game with star upgrades loses strategic depth if "level normally and take whatever upgrades appear" is always correct.

But current bot results are too strategy-dependent to justify changing match length.

TEST ONE LEVER ONLY:

[H/T] Reroll cost:
2 gold -> 1 gold.

Keep pool sizes 22/20/17/10/9 unchanged.

Why:
Bots are reaching partial copy counts but spending only ~50g. Cutting reroll cost directly tests whether the limiting factor is reroll economics rather than pool scarcity.

Healthy eventual targets [T]:
1-cost 3★: 45–65% of committed reroll games.
2-cost: 30–50%.
3-cost: 15–30%.

More important [H]: measure these among players ACTIVELY pursuing that reroll strategy, not across every match.

Also record average completion round and placement conditional on successful/failed completion.

[?] 1-gold rerolls may be too generous for humans. Treat this strictly as an experimental lever; human playtests ultimately decide it.


6. NEXT ROSTER EXPANSION

[H] YES — origins eventually need more members.

Current 4-member origins force breakpoint compression to 2/3. That's acceptable for roster v0.4 but limits future composition diversity.

NEXT EXPANSION: +6 characters [H]
25 -> 31 total.

Add:
+1 Ironveil
+1 Emberwake
+1 Tideglass
+1 Stormcrest
+1 Starfall
+1 Eclipse

Do NOT design them yet.

Goal:
Every origin reaches 5 members (Eclipse reaches 6), allowing future origin structures such as 2/4 or 2/4/6 without requiring every faction member.

Do not expand immediately. First establish a stable 25-unit + traits baseline.


NEXT TEST GATE

Run 200+ matches with:
- New breakpoint tables/bonuses.
- HP multiplier 1.12.
- Lio buff only.
- Ione/Solenne/Vela held.
- 1g rerolls for reroll-strategy testing.

Report trait breakpoint usage + placement, fight distribution/timeouts, all-unit damage/casts/survival, composition diversity, and reroll completion by strategy.

[H] Do NOT design transformations/items or add the six characters until this pass establishes whether the trait structure itself is healthy.
