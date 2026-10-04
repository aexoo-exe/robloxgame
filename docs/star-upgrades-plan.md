# Star upgrades

Three copies of a unit at one star level merge into one unit of the next star level, up to 3 stars.
Health and attack damage scale by star level. Numbers come from
[design/unit-stats-economy.md](design/unit-stats-economy.md) section 4. Star level is its own unit
field and is used for nothing else (section 15).

Out of scope (not built): mana, abilities, armor, the shared pool, player HP.

## Modules

| Module | Change |
| --- | --- |
| `StarConfig` (new) | Max star level 3, 3 copies per merge, health and attack damage multipliers |
| `StarLevel` (new, pure) | `scaleStats` (the only place multipliers are applied) and `copiesIn` (1 / 3 / 9) |
| `Board` | `mergeUnits` (chained merges), `completesMerge`, unplaced add for full-bench merges, `CapReached` reason |
| `PlayerState` | Buying merges; full-bench buy allowed only if it completes a merge; sell value = cost x copies; refusal reasons |
| `CombatSim` | Applies `StarLevel.scaleStats` once per unit as it enters combat; summaries include `starLevel` |
| `CombatConfig` | Enemy entries take a star level; rounds 7-12 retuned and added |
| `PlayerService` | Sends `RequestRefused` with the reason |
| `UnitView`, `RenderConfig` | Star symbols on the label; 2-star units 15% larger, 3-star 30% |
| `ShopPanel` | Buttons disabled outside Preparation |
| `RefusalNotice` (new) | Shows the refusal reason for 2 seconds |

## Assumptions

1. **Branch base.** `feature/shop-economy` was not merged into `main`, so this branch starts from it.
2. **Where the merged unit goes.** "First copy on the bench" means the lowest-numbered bench slot.
   With several board copies, the one with the lowest id (bought earliest) is kept.
3. **Only purchases trigger merges.** Moving and selling cannot complete a set. After a purchase,
   every unit type is checked, repeatedly, until no set of three remains.
4. **Rounding.** Scaled stats are rounded to whole numbers (Tank1 2-star: 67.5 attack damage
   becomes 68).
5. **Sell value.** Derived as cost x 3^(star - 1), not stored separately.
6. **Full-bench purchase.** The bought copy exists briefly without a place and is consumed by the
   merge in the same request. This is allowed only when the player already owns two 1-star copies.
7. **Unit cap.** Merging two board copies lowers the board count; a merge never raises it.
8. **Refusal messages.**
   - "Not enough gold" for buy, reroll and buy XP; "Bench is full" for buy; "Board is full" for a
     move blocked by the cap; "Already at max level" for buy XP.
   - Malformed requests are ignored silently.
   - Requests outside Preparation are ignored silently; the buttons are disabled then.
9. **Retuning reference.** I measured with the same simulated player as the previous tuning
   (buys to its cap, mixes roles, buys XP above 20 gold, never rerolls, does not chase copies). A
   second bot that buys copies of units it owns is reported as an upper bound.

## Balance (400 simulated matches per bot)

| Round | Previous (plain bot) | Now (plain bot) | Now (copy-seeking bot) | Avg / longest fight (s), plain |
| --- | --- | --- | --- | --- |
| 1 | 50 | 50 | 68 | 22.1 / 23.0 |
| 2 | 59 | 59 | 95 | 21.8 / 35.1 |
| 3 | 74 | 74 | 98 | 23.5 / 36.5 |
| 4 | 74 | 80 | 94 | 21.5 / 32.5 |
| 5 | 84 | 86 | 99 | 22.6 / 35.1 |
| 6 | 93 | 90 | 87 | 21.4 / 40.1 |
| 7 | 79 | 68 | 74 | 23.8 / 35.7 |
| 8 | 53 | 48 | 68 | 24.8 / 37.8 |
| 9 | (reused round 8) | 58 | 62 | 26.2 / 37.8 |
| 10 | | 48 | 67 | 26.6 / 39.2 |
| 11 | | 52 | 68 | 26.8 / 42.6 |
| 12 | | 36 | 52 | 26.3 / 38.9 |

No fight ended in a draw. Round 7 is the largest drift (68% vs 79%): any 2-star or extra unit there
dropped it below 50%, so I chose the smaller step of upgrading the archers to 3-cost.

A player who chases copies wins 87-99% of rounds 2-6, because 2-stars come early and the scripted
enemies have none until round 9.
