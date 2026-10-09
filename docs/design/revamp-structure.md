BLOCK 1 — STRUCTURE / TRAITS / ENGINE CONTRACT v1.1

NOTE (Overhaul 1): the ORIGINS, CLASSES and DUOS sections below are superseded. The current
traits, bonds, memberships, engine building blocks and the radius-2 stun rule (now The Strongest
and Za Warudo) are in docs/design/overhaul-1.md. The rest is kept as the v1.1 record.

LEGEND
[H] hard rule | [T] tunable | [?] validate

GLOBAL HEALTH MULTIPLIER: 1.16 [T]
Expected average fight: 22.5–24.5s [T].
Target timeout rate: 1–3%.

COST SPLIT [H]
1c 9 | 2c 9 | 3c 10 | 4c 9 | 5c 5 = 42

CLASS ADDITIONS [H]
Kachan: Caster/Marksman
Itchigo: Blade/Marksman
Archmage: Caster/Marksman

BACKLINE ACCESS [H]
Lightitsu: FARTHEST dash
Freaks: FARTHEST PULL
Jonny: FARTHEST shot
Saucekay: FARTHEST dash
Beast Giant: FARTHEST blast
Itchigo: FARTHEST slash
All others avoid FARTHEST.

==================================================
ORIGINS
==================================================

SHINOBI (5)
2: +15% AS [T]
3: +28% AS, +10% AD [T]
4: +42% AS, +18% AD [T]

CURSED (6)
2: +15 AP, +8% AD [T]
4: +32 AP, +16% AD [T]
5: +50 AP, +25% AD [T]

CREW (4)
2: Crew +7% AD/+7% AS; other allies +3%/+3% [T]
3: Crew +14%/+14%; other allies +6%/+6% [T]

TITANS (4)
2: +15% max HP, +12 Armor [T]
3: +28% max HP, +25 Armor/MR [T]

CORPS (3)
2: +15% AS, +10 Armor/MR [T]
3: +30% AS, +20 Armor/MR, +15% AD [T]

SPIRIT (5)
2: +12% AS, +8% AD [T]
3: +24% AS, +15% AD [T]
4: +38% AS, +24% AD [T]

HEROES (5)
2: +10% AD, +15 AP [T]
3: +18% AD, +30 AP [T]
4: +28% AD, +48 AP [T]

HUNTERS (6)
2: +10% AD, +10% AS [T]
4: +20% AD, +22% AS [T]
5: +30% AD, +36% AS [T]

[H] Hunters remains structurally valid after Freaks becomes 4c:
Lightitsu/Tontaro remain two 1c openers; total membership remains 6.

ARCANE (4)
2: +22 AP, +10 MR [T]
3: +45 AP, +22 MR [T]

==================================================
CLASSES
==================================================

BLADE (10)
2: +10% AD
4: +20% AD/+10% AS
6: +32% AD/+20% AS
8: +48% AD/+32% AS [T]

BRAWLER (10)
2: +10% max HP
4: +18% HP/+10% AD
6: +28% HP/+18% AD
8: +40% HP/+28% AD [T]

CASTER (11)
2/4/6/8: +18/+35/+55/+80 AP [T]

MARKSMAN (6)
2: +12% AD
4: +25% AD/+12% AS
5: +38% AD/+25% AS [T]

ASSASSIN (8)
2: +12% AD/+10% AS
4: +24%/+22%
6: +38%/+38% [T]

GUARDIAN (5)
2: +18 Armor/MR
4: +38 Armor/MR, +12% max HP [T]

SUPPORT (5)
2: members +20 AP; ALL_ALLIES +8 MR
4: members +42 AP; ALL_ALLIES +18 Armor/MR [T]

==================================================
DUOS
==================================================

SPARKBOUND — Freaks + Zolduck
2: +18% AS/+12% AD [T]
[H] Still valid despite Freaks moving to 4c.

STEELOATH — Jonny + Jyro
2: +20% AD/+15 Armor/MR [T]

RIVAL SEAL — Fish Cake + Saucekay
2: +18% AD/+25 AP [T]

RISING RIVALS — Quirkless + Kachan
2: +15% AD/+25 AP [T]

SUNDER BROTHERS — Tontaro + Lightitsu
2: +20% AS/+15% AD [T]
[H] Unchanged; both remain 1c Hunters.

LAST WALL — Aaron + Mika
2: +15% max HP/+18% AD [T]

DEFER: Moss Head/Love-cook, Goataro/Za Warudo,
The Strongest/Bangs.

==================================================
BUILDING BLOCKS
==================================================

AREA_STUN [H]
Center selector + radius + duration.
At resolution, stun every living enemy within radius.
Entrants afterward unaffected.
Maximum duration from any STUN/AREA_STUN: 2.0s [H].
Only The Strongest may use offensive radius 2 [H].
Urarocka may use SELF-centered radius 2 defensively [H].
All other AREA_STUN radius <=1.

SUMMON [H]
Fields: count, duration, HP/AD/Armor/MR/AS percentages,
range, move speed.
Place nearest legal free hex expanding from caster.
Summons basic attack, cannot gain mana/cast, inherit/count for no traits/duos.
Disappear on death/expiration.
Damage credited to summoner.
Excluded from timeout resolution, surviving-unit counts and player damage.
Board units + summons cap: 12.

PULL [H]
Move selected enemy to free adjacent caster hex.
Nearest-displacement deterministic placement.
Fails movement if none available; later effects still resolve.
Pulled unit becomes CURRENT_TARGET.

DAMAGE_OVER_TIME [H]
Fields: center/target, optional radius, damage type,
damage/tick, interval, duration.
First tick after one interval.
Normal mitigation.
Victim receives damage-taken mana, capped at 10 mana per DOT application.
Different casters stack.
Same caster+ability refreshes duration and retains stronger tick.

COPY [H]
Immediately casts selected living unit's ability at Kashi's star level.
Uses Kashi's stats where effects reference caster stats.

Magnitude multiplier based on COPIED UNIT COST:
1–3c: 0.80
4c: 0.60
5c: 0.45

Multiplier applies DAMAGE, AREA_DAMAGE, HEAL, SHIELD and DOT magnitudes.
Does NOT scale stun duration, radius, dash distance, summon count or structural values.
Copied SUMMON uses copied definition but Kashi's stats.
Copied COPY: nested COPY ignored; other effects resolve.

BUFF STACKING [H]
A BUFF may explicitly declare stack_per_cast=true and max_stacks=N.
Each cast adds one independent numeric stack up to cap.
Recasting at cap refreshes duration without adding another stack.
Only Sonion uses this in v1.1.

SELECTORS [H]
ALL_ALLIES: all living deployed non-summoned allies including caster.
LOWEST_HP_OTHER_ALLY: lowest HP% living deployed non-summoned ally excluding caster; no target if none.

==================================================
POOL / SHOP
==================================================

COPIES PER CHARACTER [T]
1c 30 | 2c 26 | 3c 22 | 4c 15 | 5c 10
3 copies -> 2★; 9 -> 3★ [H].
Reroll cost: 1g experimental [T].

SHOP ODDS [T]
LV | 1c | 2c | 3c | 4c | 5c
2  |100 |  0 |  0 |  0 |  0
3  | 75 | 25 |  0 |  0 |  0
4  | 55 | 30 | 15 |  0 |  0
5  | 45 | 33 | 20 |  2 |  0
6  | 30 | 40 | 25 |  5 |  0
7  | 19 | 30 | 40 | 10 |  1
8  | 18 | 25 | 32 | 22 |  3
9  | 15 | 20 | 25 | 30 | 10
10 |  5 | 10 | 20 | 40 | 25

==================================================
DEFERRED
==================================================

Transformation mechanics/stat bonuses/triggers.
Items.
Revives/executes/untargetability.
Mana manipulation.
Penetration/healing reduction.
Displacement immunity.
Summons with active abilities.
Trait emblems.
Remaining duos.
Further effects/selectors.
Final pool/shop/trait numbers.

[H] Establish no-trait 42-unit combat baseline before transformations.
