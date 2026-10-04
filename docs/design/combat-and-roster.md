PART B — COMBAT SYSTEM v0.1 + FIRST ROSTER

==================================================
1. COMBAT RULES
==================================================

[HARD RULE] DAMAGE TYPES

Physical damage -> Armor.
Magic damage -> Magic Resistance.
True damage -> neither.

For Armor/MR >= 0:

DamageMultiplier = 100 / (100 + Resistance)

FinalDamage = RawDamage × DamageMultiplier

Round final damage to the nearest integer, minimum 1 for a successful damaging hit.

[HARD RULE] MANA

Mana is represented as StartingMana / MaxMana.

Basic attack completed:
+10 Mana.

Taking post-mitigation damage:
Gain Mana = 5 × (DamageTaken / MaxHealth × 100), capped at 10 Mana per damage event.

Examples:
Taking 1% max HP -> +5 Mana.
Taking 2%+ -> +10 Mana.

Mana cannot exceed MaxMana.

When Mana reaches MaxMana, the unit finishes its current action, chooses targets using the ability definition, casts, then Mana becomes 0.

Standard cast time = 0.75 seconds.
The unit cannot attack during cast time.

Damage-over-time does NOT generate defensive Mana. Shields absorbing damage do NOT generate defensive Mana.

[HARD RULE] ABILITY POWER

Baseline AP = 100.

Magic ability damage, healing, and shielding:

FinalBaseEffect = ListedValue × AP / 100

Example: 300 listed damage at 125 AP = 375 raw magic damage.

AP does NOT increase physical ability damage, stun duration, dash distance, or stat-buff values unless explicitly specified later.

[HARD RULE] CRITS

Base CritChance = 25%.
Base CritDamage = 140%.

Basic attacks can crit:
CriticalDamage = normal raw basic-attack damage × 1.40.

Crit is rolled independently per attack.

Abilities CANNOT crit in v0.1.

==================================================
2. GENERIC ABILITY BUILDING BLOCKS
==================================================

[HARD RULE]

Every ability must be composed from these seven effects:

1. DAMAGE — Deal specified physical, magic, or true damage to a target.

2. AREA_DAMAGE — Deal specified damage to every enemy within N hexes of a chosen center hex. Center target is included.

3. HEAL — Restore HP to the specified allied target, capped at MaxHealth. Default targeting: lowest current-HP-percentage ally in range; self is eligible.

4. SHIELD — Give target temporary HP for a specified duration. Damage consumes shield before HP. Multiple shields do not stack; keep the larger remaining shield.

5. STUN — Target cannot move, attack, or cast for the specified duration. Mana generation continues.

6. BUFF — Modify one supported stat (AD, AP, AttackSpeed, Armor, MR, or MoveSpeed) by a flat or percentage amount for a specified duration. Same-source buffs refresh rather than stack.

7. DASH — Instantly relocate up to N hexes to a valid unoccupied hex. Offensive dash chooses the nearest valid hex adjacent to the current target. Defensive dash chooses the valid hex within distance N maximizing distance from the nearest enemy.

Target selectors available to abilities:
SELF
CURRENT_TARGET
LOWEST_HP_ALLY
NEAREST_ENEMY
FARTHEST_ENEMY
HIGHEST_AD_ENEMY

No character-specific scripting should be required for these ten abilities.

==================================================
3. FIRST REAL ROSTER
==================================================

All values below are [TUNABLE STARTING POINT].
Range is measured in hexes. AS = attacks/sec.
Move = hex movement speed scalar.
Crit is 25% / 140% for everyone.

Name           Cost Role             HP   AD  AP  Armor MR  AS    Range Move Mana
Kaien Vale       1  Frontline        720  48 100   40  40  .60    1   1.0  40/90
Mira Quill       1  Ranged Carry     540  62 100   18  18  .78    4   1.0  20/80

Rook Ember       2  Bruiser          850  66 100   38  32  .68    1   1.0  30/90
Sena Lume        2  Support          650  48 100   25  35  .70    3   1.0  40/100

Veyra Storm      3  Caster           720  55 100   25  30  .72    4   1.0  20/80
Dax Ironwind     3  Duelist          850  76 100   35  30  .85    1   1.1  30/90

Orin Bastion     4  Main Tank       1180  58 100   60  60  .60    1   0.9  50/110
Nyra Voss        4  Ranged Carry     820  88 100   28  28  .90    4   1.0  20/80

Astra Ren        5  Mystic Carry     980  75 100   38  45  .85    4   1.0  30/100
Kairo Zenith     5  Vanguard Carry  1250  96 100   60  50  .80    1   1.1  40/110

ABILITIES — values shown as 1★ / 2★ / 3★

KAIEN — Iron Pulse
SHIELD SELF: 180/300/500 for 5s.
STUN CURRENT_TARGET: 1.0/1.5/2.25s.
Identity note: disciplined guardian; transformation concept = awakened armored sentinel.

MIRA — Starbolt
DAMAGE CURRENT_TARGET (physical): 140/220/360.
BUFF SELF AttackSpeed +25%/+35%/+50% for 4s.
Identity: precision marksman; transformation = luminous astral archer.

ROOK — Meteor Knuckle
DAMAGE CURRENT_TARGET (physical): 180/290/470.
AREA_DAMAGE radius 1 (magic): 80/130/220.
Identity: reckless fire brawler; transformation = volcanic overdrive.

SENA — Moonveil
SHIELD LOWEST_HP_ALLY: 180/300/480 for 5s.
HEAL LOWEST_HP_ALLY: 100/160/260.
Identity: celestial protector; transformation = moonlit spirit form.

VEYRA — Tempest Core
AREA_DAMAGE centered on CURRENT_TARGET, radius 1 (magic): 260/420/680.
STUN CURRENT_TARGET: 1.0/1.5/2.0s.
Identity: storm-channeling prodigy; transformation = living thunder state.

DAX — Flashbreak
DASH toward CURRENT_TARGET: up to 2 hexes.
DAMAGE CURRENT_TARGET (physical): 240/380/600.
BUFF SELF AttackSpeed +30%/+45%/+65% for 4s.
Identity: speed-focused swordsman; transformation = wind-sheathed ascension.

ORIN — Unbroken Citadel
SHIELD SELF: 450/700/1100 for 6s.
BUFF SELF Armor +30/+45/+70 and MR +30/+45/+70 for 6s.
Identity: immovable fortress; transformation = colossal guardian armor.

NYRA — Voidline Shot
DAMAGE FARTHEST_ENEMY (physical): 350/550/900.
STUN that target: 1.0/1.5/2.25s.
Identity: dimensional sniper; transformation = void-eye awakening.

ASTRA — Falling Constellation
AREA_DAMAGE centered on HIGHEST_AD_ENEMY, radius 2 (magic): 400/650/1050.
Identity: cosmic sorcerer; transformation = constellation embodiment.

KAIRO — Heavenbreaker
DASH toward HIGHEST_AD_ENEMY: up to 3 hexes.
AREA_DAMAGE centered on SELF after dash, radius 1 (magic): 400/650/1050.
SHIELD SELF: 300/500/800 for 5s.
Identity: legendary martial vanguard; transformation = radiant battle ascension.

==================================================
4. FIGHT-LENGTH TARGET
==================================================

[TUNABLE STARTING POINT]

Target average combat duration: 24–30 seconds.
Healthy common range: 15–38 seconds.

Armor/MR will increase effective HP, while abilities introduce burst, AoE, CC and scaling that accelerate board collapse after first casts. These are intentionally balanced against each other so combat should stay near today's duration rather than simply becoming longer.

50-second cap remains unchanged.

==================================================
5. DEFERRED
==================================================

[HARD SCOPE BOUNDARY]

Trait and transformation identities above are DESIGN NOTES ONLY.

Claude should NOT implement yet:

- traits/synergies
- transformations
- items
- ability crits
- negative Armor/MR
- resistance penetration/shred
- dodge
- lifesteal/omnivamp
- healing reduction
- damage amplification/reduction systems
- execute mechanics
- resurrection
- summons
- damage-over-time
- mana-lock/mana-reave
- displacement/knockback
- stealth
- invulnerability
- aggro/taunt
- character-specific ability code

The objective of this milestone is a SMALL GENERIC COMBAT ENGINE capable of expressing all ten characters through data.

After these ten work correctly, traits should be designed against actual combat behavior rather than guessed in advance.
