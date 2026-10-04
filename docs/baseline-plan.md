# Baseline combat plan

First playable baseline: players place units on a hex board during Preparation, and Combat runs a
real deterministic fight that produces a winner. All stats are placeholders for a later design pass.

## Scope

In: board model, bench, four placeholder units, placement through request remotes, combat simulation,
placeholder rendering, result reporting, Lune tests.

Out (not built, no hooks): shop, gold, XP, star upgrades, traits, mana, abilities, player health,
multi-player pairing.

## Module layout

### `src/shared` (ReplicatedStorage.Shared)

Config. These are frozen tables, and every tunable value lives here:

| Module | Contents |
| --- | --- |
| `MatchConfig` | Phase durations, `minPlayersToStart`, `maxPlayers` |
| `BoardConfig` | Columns (7), rows per player (4), bench slots (9), starting units |
| `UnitConfig` | Four placeholder unit types: health, attackDamage, attacksPerSecond, range, moveSpeed |
| `CombatConfig` | Simulation tick rate, end-of-combat padding, preset enemy board |
| `RenderConfig` | Placeholder visuals: arena position, hex size, colors, camera |

Pure logic. These use no Roblox APIs and are tested with Lune:

| Module | Contents |
| --- | --- |
| `HexGrid` | Odd-r offset hex math: neighbors, distance, half-turn rotation |
| `SeededRandom` | Park–Miller PRNG (exact in doubles) used for tie-breaking |
| `Board` | One player's board and bench state, plus placement rules |
| `CombatSim` | Takes two boards and a seed, advances fixed ticks, returns events and a result |

Other shared modules: `Phase` (phase names) and `RemoteNames` (remote event names).

### `src/server` (ServerScriptService.Server)

| Module | Responsibility |
| --- | --- |
| `Remotes` | Creates RemoteEvents under `ReplicatedStorage.Remotes` |
| `BoardService` | Owns each participant's `Board`, handles `RequestMoveUnit`, sends `BoardUpdated` |
| `CombatService` | Builds the sim input, runs `CombatSim`, broadcasts `CombatStarted`, returns duration and result |
| `RoundService` | Phase loop. Calls BoardService at Preparation and Combat, and CombatService for the fight |

### `src/client` (StarterPlayerScripts.Client)

| Module | Responsibility |
| --- | --- |
| `Arena` | Builds the hex cells and bench slots (local parts), maps cells to world positions, sets the camera |
| `UnitView` | One placeholder unit: colored part, name, health bar |
| `BoardController` | Renders own board during Preparation; click to select, click a cell or slot to send a request |
| `CombatPlayback` | Plays back combat events from the server |
| `PhaseDisplay` | Existing round/phase/countdown label |

### `tests/` and `scripts/test.ps1`

Lune test files (`HexGridTest`, `BoardTest`, `CombatSimTest`) and a minimal runner, `tests/run.luau`.

## Key decisions

- **Hex grid:** pointy-top hexes in odd-r offset coordinates (even-numbered rows, counting from 1,
  shift half a cell right). Coordinates are 1-based. In its own coordinates a player's row 1 is the
  back row and row 4 the front row.
- **Combat field:** 7×8. Side 1 keeps its own coordinates. Side 2's board is rotated a half turn,
  `(c, r) -> (columns + 1 - c, 8 + 1 - r)`. With an even total row count this is an exact geometric
  point reflection of the hex layout, so distances are preserved (covered by a test).
- **Determinism:** the sim uses integer tick counters, sorted inputs, and a seeded PRNG for turn order
  and target tie-breaks. It never iterates with `pairs` and uses no wall-clock time.
- **Unit behavior per tick:**
  1. Keep the current target if it is alive and in range; otherwise pick the nearest enemy (random tie-break).
  2. If in range, attack when the cooldown is ready.
  3. Otherwise step one cell along a breadth-first shortest path over free cells to any cell within
     range, waiting for the move cooldown.

  Cells are never shared.
- **Ending:** a side with no units left loses. If both sides still have units when the combat timer
  (`MatchConfig.combatMaxDuration`) runs out, the round is a draw.
- **Pure-module requires:** pure modules use
  `if script then require(script.Parent.X) else require("./X")`. Roblox takes the Instance path;
  in Lune `script` is nil, so the relative string path is used.

### Replication approach

The server runs the whole simulation instantly at the start of Combat. It then sends the full result
(start positions plus a time-stamped event list) to every client in **one `CombatStarted` RemoteEvent**,
along with the server time at which playback starts. Clients replay the events against
`workspace:GetServerTimeNow()`. The Combat phase lasts exactly as long as the fight, plus a short padding.

Why this approach:

- It is simplest. There is one message per round, with no per-tick streaming and no replicated
  Instances to manage.
- It is server-authoritative. Clients only animate what the server already decided, and they never
  run the sim.
- It is small. A full 45 s fight is a few hundred events (tens of KB).
- Re-simulating on the client from the seed was rejected. It would need the client to trust identical
  code and floating-point behavior, for no benefit at this stage.

Board state (Preparation) goes to the owner only, as a full snapshot in a `BoardUpdated` RemoteEvent,
after every accepted change and at each reset. A snapshot holds at most a handful of units.

## Assumptions (picked the simpler option)

1. **Opponents:** with one player present, that player fights `CombatConfig.presetEnemyBoard`. With two
   present, the first two players fight each other. `MatchConfig.maxPlayers = 2`; any extra players
   get no board and only watch. This is not pairing; pairing remains out of scope.
2. **Reset each round:** every Preparation resets each board to the five starting units on the bench,
   so placements do not carry over between rounds.
3. **No board unit limit:** all five units may be placed, because there are no player levels.
4. **No swaps:** a move to an occupied cell or slot is rejected instead of swapping the two units.
5. **Damage:** raw `attackDamage` per hit. There is no armor, crit, or mitigation yet. The first attack
   happens as soon as a unit is in range; after that it waits `1 / attacksPerSecond`.
6. **Tick rounding:** attack and move intervals are rounded to whole ticks (20 ticks per second).
7. **Empty board:** a side with no units placed loses immediately. Both empty means a draw.
8. **Rendering is client-local:** each client builds its own arena parts. Every client sees its own
   side at the bottom (side 2 clients see the field rotated). Spectators see side 1's view. A player
   who joins mid-combat sees nothing until the next Preparation.
9. **Result text:** `MatchState.LastResult` holds a short human-readable string such as
   `"Player1 wins"`, `"Enemy wins"` or `"Draw"`.
10. **Mid-round joins:** a player who joins during Combat gets a board at the next Preparation.

## Build order (one commit per milestone)

1. Plan doc, Lune via Rokit, test runner, `scripts/test.ps1`
2. Configs + `HexGrid` + `SeededRandom` + `Board`, with tests
3. `CombatSim`, with tests (determinism, stronger team wins, timeout draw, no shared cells)
4. Server: `Remotes`, `BoardService`, `CombatService`, RoundService integration
5. Client: `Arena`, `UnitView`, `BoardController`, `CombatPlayback`
6. README update, PR into `main`
