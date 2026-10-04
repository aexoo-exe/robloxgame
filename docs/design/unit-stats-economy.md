# DESIGN SPEC — UNIT STATS, ECONOMY, COSTS & SHOP ODDS

This is the initial numerical design specification for our Roblox anime auto-battler.

TFT is our primary mechanical reference. These numbers intentionally begin near proven auto-battler ranges rather than inventing a completely new economy and stat scale.

These are BASELINE VALUES, not permanent balance commitments.

The goal is to establish a coherent numerical ecosystem that we can tune after actual playtesting.

---

# 1. CORE UNIT STAT MODEL

Every standard unit should eventually support:

- MaxHealth
- AttackDamage
- AbilityPower
- Armor
- MagicResistance
- AttackSpeed
- AttackRange
- StartingMana
- MaxMana
- CritChance
- CritDamage
- MoveSpeed

Recommended global defaults:

AbilityPower = 100

Armor = 20

MagicResistance = 20

CritChance = 25%

CritDamage = 140%

MoveSpeed = shared default unless overridden.

Individual units override these where their role requires it.

AttackSpeed should represent attacks per second.

AttackRange should use board hex/tile distance rather than Roblox studs at the gameplay-data level.

---

# 2. BASE STAT BANDS BY UNIT COST

These are design envelopes, NOT stats that every unit of that cost receives.

## 1-COST

Health:
500–750

Attack Damage:
40–65

Attack Speed:
0.55–0.80

Armor/MR:
15–40

Typical Mana:
0–100

Purpose:
Early-game pieces, trait enablers, reroll carries and inexpensive frontline.

A well-upgraded 1-cost should remain relevant rather than automatically becoming worthless.

---

## 2-COST

Health:
600–900

Attack Damage:
45–70

Attack Speed:
0.55–0.85

Armor/MR:
20–45

Typical Mana:
0–110

Purpose:
Stronger early/mid-game specialization.

These should frequently become legitimate reroll carries or durable utility pieces.

---

## 3-COST

Health:
700–1050

Attack Damage:
50–80

Attack Speed:
0.60–0.90

Armor/MR:
20–50

Typical Mana:
0–120

Purpose:
Mid-game power pieces.

A 3-cost should often be capable of becoming a composition's primary carry or tank when sufficiently upgraded.

---

## 4-COST

Health:
800–1200

Attack Damage:
55–90

Attack Speed:
0.65–0.95

Armor/MR:
25–60

Typical Mana:
0–130

Purpose:
Major late-game carries, tanks and high-impact utility units.

A 4-cost should usually feel meaningfully stronger or more sophisticated than inexpensive units without simply having massively inflated stats.

---

## 5-COST

Health:
900–1400

Attack Damage:
60–100

Attack Speed:
0.65–1.00

Armor/MR:
30–70

Typical Mana:
0–150

Purpose:
Rare late-game characters with unusually powerful abilities or mechanics.

Their power should come substantially from their kits rather than simply multiplying every stat.

---

# 3. ROLE MATTERS MORE THAN COST

Cost determines the approximate power budget.

Role determines where that budget goes.

Example:

A 4-cost tank might have:

1150 HP
55 AD
0.60 AS
60 Armor
60 MR

while a 4-cost backline carry might have:

800 HP
85 AD
0.85 AS
25 Armor
25 MR

Both are 4-cost units.

Therefore DO NOT generate stats solely from unit cost.

Each character should eventually have explicit authored base stats.

---

# 4. STAR LEVEL SCALING

Use duplicate acquisition:

3 × 1-star → 1 × 2-star

3 × 2-star → 1 × 3-star

Therefore a natural 3-star requires:

9 copies.

Recommended initial stat scaling:

HEALTH

1-star = 100%
2-star = 180%
3-star = 324%

ATTACK DAMAGE

1-star = 100%
2-star = 150%
3-star = 225%

Armor and MR:

Do NOT automatically multiply these by star level.

Attack Speed:

Do NOT automatically multiply it by star level.

Mana:

Do NOT automatically multiply it by star level.

Ability scaling should be authored per ability because some characters should gain damage while others gain healing, shielding, targets, duration or other effects.

This avoids turning every upgrade into pure stat inflation.

---

# 5. DAMAGE MITIGATION

Use a TFT/League-style resistance model.

For non-negative resistance:

DamageMultiplier = 100 / (100 + Resistance)

Examples:

0 resistance → 100% damage received

20 resistance → 83.3%

50 resistance → 66.7%

100 resistance → 50%

200 resistance → 33.3%

This gives Armor and Magic Resistance diminishing returns naturally.

Physical damage uses Armor.

Magic damage uses MagicResistance.

True damage ignores both.

Keep this centralized in combat math rather than implementing resistance calculations separately inside individual abilities.

---

# 6. UNIT COST

Initial tiers:

1-cost = 1 gold

2-cost = 2 gold

3-cost = 3 gold

4-cost = 4 gold

5-cost = 5 gold

Do not introduce additional normal rarity tiers yet.

Special/transformation characters can eventually break these rules when justified.

---

# 7. SHOP STRUCTURE

Each shop contains:

5 unit slots.

Normal refresh cost:

2 gold.

A new shop should appear automatically at the beginning of each preparation round.

Purchased units should not automatically refill their shop slot during the same round.

The player rerolls to generate another complete shop.

---

# 8. INITIAL SHOP ODDS

Use the following starting table.

Percentages correspond to:

1-cost / 2-cost / 3-cost / 4-cost / 5-cost

LEVEL 2
100 / 0 / 0 / 0 / 0

LEVEL 3
75 / 25 / 0 / 0 / 0

LEVEL 4
55 / 30 / 15 / 0 / 0

LEVEL 5
45 / 33 / 20 / 2 / 0

LEVEL 6
30 / 40 / 25 / 5 / 0

LEVEL 7
19 / 30 / 40 / 10 / 1

LEVEL 8
15 / 20 / 32 / 30 / 3

LEVEL 9
10 / 17 / 25 / 33 / 15

LEVEL 10
5 / 10 / 20 / 40 / 25

These intentionally create strategic reroll windows.

Broadly:

Level 5 → strong 1-cost access

Level 6 → strongest 2-cost access

Level 7 → strongest 3-cost access

Level 8 → strong 4-cost access

Level 9+ → strongest access to 5-costs

The player should therefore make a real decision between spending gold rerolling at the level favorable to their carry versus investing that gold into XP.

Do not flatten these probabilities.

---

# 9. ECONOMY

Recommended standard round income:

5 gold per completed PvP round.

Interest:

+1 gold per 10 saved gold.

Interest cap:

+5 gold.

Therefore:

0–9 gold → +0

10–19 → +1

20–29 → +2

30–39 → +3

40–49 → +4

50+ → +5

Maximum standard income before streak/other bonuses:

10 gold per round.

This creates the central economic tension:

SPEND NOW
versus
SAVE TO ACCELERATE FUTURE INCOME.

---

# 10. STARTING GOLD

Recommended prototype:

Start with 0 gold.

Early scripted/PvE progression can eventually establish the player's first economy.

If V0.1 skips PvE rounds entirely, use a temporary starting grant of:

10 gold.

Make this configurable.

Do not bury it inside PlayerService.

---

# 11. STREAK ECONOMY

Initial recommendation:

2–3 consecutive wins/losses:
+1 gold

4 consecutive wins/losses:
+2 gold

5+ consecutive wins/losses:
+3 gold

Both winning and losing streaks pay because both represent strategic states.

However:

Winning still needs an additional advantage.

Recommended win bonus:

+1 gold for winning PvP combat.

This means losing intentionally has an economic recovery mechanism without being strictly superior to winning.

---

# 12. XP

Players should gain:

2 XP automatically after each PvP round.

Buying XP:

4 gold → 4 XP.

Keep XP purchase increments simple.

Recommended level progression baseline:

Level 2 → 3:
2 XP

3 → 4:
6 XP

4 → 5:
10 XP

5 → 6:
20 XP

6 → 7:
36 XP

7 → 8:
56 XP

8 → 9:
68 XP

9 → 10:
68 XP

Level 10 should initially be the normal maximum.

These values can be compressed later if Roblox matches need to be shorter than standard TFT matches.

Do NOT independently change shop odds and XP pacing without considering their relationship.

Levels determine access to unit tiers, so XP cost is indirectly part of unit rarity.

---

# 13. PLAYER HP

Initial value:

100 HP.

Do not balance player damage yet.

Player damage needs to be designed alongside:

- expected match duration
- combat survivor counts
- round/stage progression
- desired Roblox session duration

For the first implementation, player HP can exist without final damage formulas.

---

# 14. SHARED UNIT POOL

Eventually shops should draw from a finite shared unit pool.

This matters because contested compositions should become harder to complete.

Do NOT implement the full pool until the shop itself exists.

Initial pool-size baseline to test later:

1-cost: 22 copies per character

2-cost: 20

3-cost: 17

4-cost: 10

5-cost: 9

The pool should be server-authoritative.

Buying removes a copy.

Selling returns appropriate copies.

Eliminated players eventually return their owned copies.

---

# 15. TRANSFORMATIONS ARE NOT STAR LEVELS

This is a hard architectural requirement.

Star level represents generic duplicate progression.

Transformations represent character-specific mechanics.

A character may simultaneously be:

2-star

AND

in a transformed state.

Do not encode transformations as StarLevel 4, alternate star values, or anything similar.

Conceptually:

UnitInstance
    BaseCharacter
    StarLevel
    TransformationState

These systems can interact but remain independent.

---

# 16. CONFIGURATION PHILOSOPHY

Claude should NOT scatter these values throughout gameplay modules.

Eventually centralize relevant values into configuration/data modules.

Likely separation:

EconomyConfig
ShopConfig
LevelConfig
CombatConfig
BoardConfig

and individual character/unit definitions.

The server remains authoritative for:

gold
XP
level
shop generation
purchases
selling
unit ownership
star upgrades
combat calculations
player HP

Clients request actions and display results.

---

# 17. IMPLEMENTATION PRIORITY

THIS SPEC DOES NOT MEAN ALL OF THESE SYSTEMS SHOULD BE BUILT NOW.

It establishes our numerical/design baseline.

Continue following the project's incremental V0.1 roadmap.

When a system becomes the next implementation target, use the values in this document as its starting specification.

Do not prematurely implement economy, shops, XP, pools, combat formulas or units simply because their future values are now defined.

Architecture should merely avoid making these systems unnecessarily difficult to add later.

---

# DESIGN INTENT

The central philosophy is:

Use TFT's years of successful auto-battler design as our starting mathematical framework.

Then tune based on OUR game's:

- anime character mechanics
- transformations
- Roblox audience
- desired session duration
- combat feel
- progression
- playtest data

We should not change numbers simply to be different from TFT.

We should change them when our game gives us a concrete reason to.
