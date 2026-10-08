# PvE rounds (creeps and bosses)

A match has two kinds of PvE round:

- An **opening creep phase**: every player fights the same creep lineup in rounds 1–3.
- An **end-of-stage boss**: every player fights the same boss on the last round of stages 2–5.

Creeps and bosses come from a **theme**. Each match picks one theme at the start and uses it for
every PvE round in that match. There is one theme, `placeholder`.

## Round layout

Stages come from `StageConfig`: stage 1 is rounds 1–4, stage 2 is rounds 5–8, and so on. Stage 6
is round 21 onwards.

| Round | Kind | Preparation |
| --- | --- | --- |
| 1 | Creep (easiest) | none: each player's starting unit is already on the board |
| 2 | Creep | 15 s, shop open |
| 3 | Creep (a little harder) | 15 s |
| 4–7 | PvP | 30 s (`MatchConfig.preparationDuration`) |
| 8 | **Boss** (stage 2) | 30 s |
| 9–11 | PvP | 30 s |
| 12 | **Boss** (stage 3) | 30 s |
| 13–15 | PvP | 30 s |
| 16 | **Boss** (stage 4) | 30 s |
| 17–19 | PvP | 30 s |
| 20 | **Boss** (stage 5) | 30 s |
| 21+ | PvP | 30 s |

- Stage 1 has no boss; its PvE is the creep phase.
- Stage 6 has no end, so it has no boss.
- PvP stage damage (`StageConfig`) is unchanged.

## Rules

- **Starting unit.** When the match starts, every player gets one random 1-cost unit, placed on
  the board. It's drawn from the shared pool and weighted by copies left, the same way a shop roll
  picks a character.
- **Creep rounds.** Each creep round has a gold amount (round 1: 1, round 2: 2, round 3: 2), the
  same for every player. It's paid in proportion to the share of creeps killed, rounded down, so
  only a full clear is guaranteed the whole amount. You don't need to win to get paid.
- **Boss rounds.** Gold depends on the share of the boss's health removed when the fight ends. The
  highest step reached pays, and killing the boss adds a bonus:

  | Health removed | Gold |
  | --- | --- |
  | under 25% | 0 |
  | 25-44% | 1 |
  | 45-64% | 2 |
  | 65-84% | 3 |
  | 85% or more | 4 |
  | Kill | +1 |
- **Boss signature ability ("Boss Slam").** Physical damage to every enemy within 1 hex of the
  boss, then a short stun on the same enemies. It's built from the existing `AREA_DAMAGE` and
  `AREA_STUN` effects.
- **No HP loss.** Losing or timing out in a PvE round costs `healthLoss` HP, which is 0 for both
  kinds.
- **Income and streaks.**
  - PvE gold is paid at that round's Results.
  - The next Preparation still pays normal round income (base + interest + streak) and the
    automatic XP.
  - PvE rounds don't change the win/loss streak and never pay the win bonus.
- **Separate from PvP.** PvE fights don't go into the pairing history. Ghosts and practice
  enemies are used only in PvP rounds; a solo practice match plays the PvE rounds too.
- **Server-authoritative.** The server decides everything: `Match` builds the fights and rewards,
  `CombatService` simulates them, and `RoundService` pays out and publishes the result.
- **What clients see.**
  - The MatchState attribute `RoundKind` ("Creep", "Boss" or "PvP") drives a CREEP ROUND or BOSS
    ROUND tag and tint on the top label.
  - Each player's `LastResult` and `LastGold` show what they earned, for example
    "Creeps: 3/3 killed, +2 gold" or "Boss: 62% damage dealt, +2 gold".
  - Creeps and bosses use their theme's look (name, color, size).

## Where the config lives

| What | Where |
| --- | --- |
| Number of opening creep rounds | `PveConfig.openingCreepRounds` (3) |
| Which rounds are boss rounds | `PveConfig.bossRounds` ({ 8, 12, 16, 20 }) |
| Preparation time per round | `PveConfig.preparationDurations` ([1]=0, [2]=15, [3]=15; other rounds use `MatchConfig.preparationDuration`, 30) |
| Starting-unit rule | `PveConfig.startingUnits` (count 1, cost 1, cells (4,4), (3,4), (5,4)) |
| Gold per creep round | `PveConfig.creepRoundGold` ([1]=1, [2]=2, [3]=2) |
| Boss reward steps and kill bonus | `PveConfig.bossRewardSteps` (25/45/65/85% -> 1/2/3/4), `PveConfig.bossKillBonus` (1) |
| HP loss for PvE rounds | `PveConfig.healthLoss` (Creep 0, Boss 0) |
| Opponent names shown in combat | `PveConfig.opponentNames` |
| Creep and boss stats, looks, lineups, boss per stage | `PveThemeConfig.<theme>` |
| Round tint colors | `RenderConfig.creepRoundColor`, `RenderConfig.bossRoundColor` |

The logic is in `src/shared/Pve.luau`. It's used by `Match`, the server and the headless sim.

## Themes

A theme is one entry in `PveThemeConfig`:

```lua
my_theme = {
	units = {      -- creep and boss unit types (UnitConfig stat fields + kind + look)
		my_creep = { kind = "creep", health = ..., attackDamage = ..., ..., look = { name = "Creep", color = { r, g, b }, scale = 0.8 } },
		my_boss = { kind = "boss", ..., maxMana = ..., ability = { name = ..., effects = { ... } }, look = { ... } },
	},
	creepRounds = { [1] = { { unitType = "my_creep", column = 3, row = 4 }, ... }, [2] = ..., [3] = ... },
	bosses = { [2] = { unitType = "my_boss", column = 4, row = 3 }, [3] = ..., [4] = ..., [5] = ... },
}
```

- **Unit types.** They use the `UnitConfig` stat fields. Their health is the final combat health:
  the roster health dial (`CombatConfig.globalHealthMultiplier`) does not apply to creeps or bosses.
  They run through the same combat engine, with the theme's types added to `UnitConfig` for that
  fight only (`Pve.unitTypes`).
- **Never in the shop.** Theme units are never in `UnitConfig`, so they never reach the shop or
  the unit pool.
- **Unique ids.** Every unit id must be unique across `UnitConfig` and all themes.
- **Abilities.** Creeps have no ability. A boss needs `maxMana` and an ability made of existing
  effects.
- **Positions.** Lineup and boss positions use the enemy's own board coordinates (row 4 is the
  front).
- **What a theme must cover.** Lineups for every opening round and a boss for every stage with a
  boss round. `tests/PveTest.luau` checks this, and that every boss ability is valid.

To add a theme, add an entry. `Pve.pickTheme` chooses among all themes with the match seed.

## Sim

`sim/run.luau` plays the PvE rounds the way the server does: starting units, no Preparation in
round 1, PvE gold at Results. It prints a "PvE rounds" section with each round's win rate and
gold. For boss rounds it also prints the average share of boss health removed and the kill rate,
and it reports PvE gold per player per match. PvE fights are kept out of the per-character,
mechanics and timeout numbers, which measure the roster against itself.
