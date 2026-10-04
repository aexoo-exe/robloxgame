# Shop and economy

Builds gold, income, interest, streaks, XP, levels, the shop (buy, sell, reroll, buy XP), the unit
cap, a placeholder roster, persistent boards and unit swapping on top of the baseline.
Every number comes from [design/unit-stats-economy.md](design/unit-stats-economy.md).

Out of scope (not built, no hooks): star merging, shared unit pool, armor, magic resistance, crits,
mana, abilities, player HP, traits, transformations, pairing for more than two players.

## Module layout

Config (frozen tables in `src/shared`):

| Module | Contents |
| --- | --- |
| `EconomyConfig` | Starting grant, base income, interest, streak bonuses, win bonus (spec sections 9-11) |
| `LevelConfig` | Starting and max level, XP per round, XP purchase, XP table (section 12) |
| `ShopConfig` | Slots, reroll cost, odds per level (sections 7-8) |
| `UnitConfig` | 10 placeholder units: cost, role, health, attack damage, attack speed, range, move speed |
| `CombatConfig` | `enemyBoardsByRound` for solo play |

Pure logic (no Roblox APIs, tested with Lune):

| Module | Contents |
| --- | --- |
| `Economy` | Interest, streak bonus and transitions, round income, XP and level-ups |
| `Shop` | Rolls a 5-slot shop: cost tier by the level's odds, then a unit of that cost |
| `Board` | Adds swapping, `maxPlaced` cap, `removeUnit`, `starLevel` |
| `PlayerState` | One player's gold, XP, level, streak, shop and board; validates buy, sell, reroll, buy XP and move |

Server: `PlayerService` replaces `BoardService`. It owns a `PlayerState` per participant, handles the
five request remotes, and sends `BoardUpdated` and `PlayerStateUpdated` to the owner only.
`CombatService` returns each player's outcome, and `RoundService` records it.

Client: `ShopPanel` is a placeholder panel on the right edge. `BoardController` gains click-to-swap,
exposes the selected unit for selling, and reports unit changes.

## Assumptions

1. **Income after every fight.** Round income, interest, streak bonus, the win bonus and the
   automatic 2 XP are paid after every fight, including solo fights against the scripted enemy.
   There is no PvE/PvP distinction yet.
2. **No income at a player's first Preparation.** Players start with the 10-gold grant instead.
   Income is owed only if the player fought since the last Preparation, so a player who joins
   mid-round is not paid for a fight they missed.
3. **Interest timing.** Interest uses the gold held before that round's income is added.
4. **Streaks.** A streak includes the latest fight, so the first win pays no streak bonus. A draw
   ends any streak and pays no win bonus.
5. **Level 10.** At level 10, XP stays at 0 and buying XP is refused.
6. **Shop rolls.** A roll draws 1-100 against the cumulative odds, then picks a unit of that cost
   uniformly. Each player has their own seeded generator. The pool is unlimited.
7. **Level-up mid-Preparation.** Levelling up does not reroll the current shop; the new odds apply
   from the next roll.
8. **Selling.** Units can be sold from the board or the bench, during Preparation only, for their
   full cost. All units are 1-star.
9. **Swaps and the cap.** Moving onto an occupied cell or slot swaps the two units. The unit cap
   (= level) only blocks moving a bench unit onto an empty cell; swaps never change the count.
10. **Click-to-swap.** With a unit selected, clicking another unit swaps them. Clicking the selected
    unit (or empty space) deselects it.
11. **Roster names.** Plain placeholders: `Tank1`-`Tank5` (frontline), plus damage dealers that
    alternate the two baseline archetypes: `Archer1`, `Archer3`, `Archer5` (range 4) and
    `Striker2`, `Striker4` (fast melee).
12. **Tank4 attack speed.** Tank4 uses 0.65 rather than the spec's 0.60 example, which is outside
    the 4-cost band.
13. **Solo enemies.** Boards are listed for rounds 1-8; later rounds reuse round 8. With two players
    they fight each other, as before.
14. **Buttons.** Buttons are always clickable; the server ignores requests outside Preparation.

## Balance (simulated)

A scratch bot played 400 seeded matches against `enemyBoardsByRound`. It never rerolls, buys
units up to its cap with a mix of roles, upgrades to higher-cost units when it can, and buys XP
while it has 24+ gold.

| Round | Win % | Draw % | Avg fight (s) | Longest (s) | Avg level |
| --- | --- | --- | --- | --- | --- |
| 1 | 50 | 0 | 22.1 | 23.0 | 2.0 |
| 2 | 59 | 0 | 21.9 | 35.1 | 3.0 |
| 3 | 74 | 0 | 24.4 | 36.8 | 3.0 |
| 4 | 74 | 0 | 23.2 | 36.8 | 3.6 |
| 5 | 84 | 0 | 24.0 | 40.0 | 4.3 |

Round 1 is an exact mirror (Tank1 + Archer1). A human who rerolls or positions better will do
better than the bot.
