# Match structure

Builds HP, pairing, combat results, player damage, elimination, placement and a winner on top of
the shop, economy and star work. Rules and numbers come from
[design/match-structure.md](design/match-structure.md). Its DELIBERATELY DEFERRED list is not
built.

## Modules

| Module | Role |
| --- | --- |
| `MatchConfig` | Timers 30 / 50 / 5, up to 8 players, lobby countdown 10 s, final placements 15 s, 100 HP, leaver grace 2 rounds |
| `StageConfig` (new) | Stage start rounds and base damage |
| `LevelConfig` | XP table from section 1 |
| `CombatConfig` | `timeoutDrawMargin = 0.01` |
| `CombatSim` | Timeout resolved by remaining health percentage; reports `timedOut`, `survivors` and `healthPercent` |
| `MatchRules` (new, pure) | Stage by round, player damage, elimination tie-breaks |
| `Pairing` (new, pure) | Section 4 pairing with ghost battles |
| `Match` (new, pure) | Per-match HP, connection, leavers, results, elimination, placement, winner |
| `RoundService` | Lobby, match and MatchOver loop; publishes the public match state |
| `PlayerService` | State keyed by UserId; leavers keep state; rejoin resumes; eliminated players cannot act |
| `CombatService` | Runs every fight of the round and sends each fight only to its players |
| `MatchHud` (new), `PhaseDisplay` | Player list with HP, stage and round, opponent name, elimination message, final placements |
| `sim/` (new) | Headless 8-bot matches using the real pure modules (`scripts/simulate.ps1`) |

## Public match state

`ReplicatedStorage.MatchState` holds these attributes: `Phase`, `PhaseEndsAt`, `Round`, `Stage`
and `Winner`.

`MatchState.Players` holds one folder per participant, named by UserId, with these attributes:
`UserId`, `DisplayName`, `Health`, `Placement`, `Eliminated`, `Connected`, `Opponent` and
`LastResult`.

## Assumptions

1. **Branch base.** Neither `feature/shop-economy` nor `feature/star-upgrades` was merged into
   `main`, so this branch starts from `feature/star-upgrades`.
2. **Leaver timing.** A round counts as missed when the player was disconnected as it started and
   is still away at its Results. The round they left in does not count. HP drops to 0 at the
   Results of the second missed round. Reconnecting at any point resets the count.
3. **Timeout draw.** A gap of exactly 1 percentage point or less is a draw.
4. **Damage at timeout.** "Surviving enemy units" counts the winning side's living units, also
   when a timeout decided the fight.
5. **Ghost history.** A ghost battle is not recorded as a real fight in the opponent history. The
   ghost uses the source player's placed units at the moment boards lock.
6. **Pairing rule order.** Rules are applied in this order: no immediate rematch, no ghost twice in
   a row, no ghost of last round's opponent, then avoid the last 2 rounds. Among the best
   pairings the choice is random.
7. **Last players falling together.** If the last players are eliminated together, the best of
   them by tie-break wins (1st place).
8. **Practice match.** A single participant plays a practice match. When they are eliminated they
   get 1st place and the match ends. Enemy boards follow `CombatConfig.enemyBoardsByRound`
   (round 12 repeats after that).
9. **Lobby.**
   - If the player count drops below the minimum during the countdown, the lobby goes back to
     Waiting.
   - After the final placements, the server returns to a 10-second lobby countdown with everyone
     present, rather than starting instantly.
10. **Participants.** Participants are the first 8 players in `Players:GetPlayers()` order, which
    is roughly join order.
11. **Names.** Names are Roblox usernames captured when the match starts.
12. **Eliminated players.** They keep their frozen board on screen, cannot act and see no fights.
13. **Damage timing.** Damage and eliminations are applied at the start of Results.
14. **HUD refresh.** The HUD redraws 4 times per second instead of tracking every attribute change.
15. **Simulation bots.** Bots place units directly for the sim instead of moving them on the Board
    one by one. Eight strategies are cycled per match.

## Pacing (200 simulated 8-bot matches)

| Measure | Result | Spec target |
| --- | --- | --- |
| Final round | average 25.4, range 22-31 | ~20-22 |
| Match length (timers only) | average 28.2 min, longest 35.0 min | 24-28 min, hard upper ~30 |
| Winner's level | average 8.5 (L9 in 115 of 200) | L8 routine, L9 realistic |
| Fights hitting the 50 s cap | 2 of 16,863 (0.01%) | |

Matches run about 3-4 rounds longer than the spec expects. A few run past the 30-minute hard
upper target. The bots never die early from bad play the way people do, so real matches may end
sooner. If playtests agree with the sim, the likely knobs are the later stages' base damage and
`preparationDuration`. I have not changed the spec's numbers.
