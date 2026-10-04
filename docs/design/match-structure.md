MATCH STRUCTURE DESIGN SPEC v0.1

GOAL
8-player anime auto-battler using TFT's proven match structure as the baseline, compressed for Roblox session length.

Target: 24–28 minutes for a normal full match.
Expected: ~20–22 PvP rounds.
Hard upper target: ~30 minutes.

Reason for departing from TFT pacing: Roblox benefits from a shorter session while still needing enough time for reroll, economy, Level 8, and Level 9 strategies to exist.

==================================================
0. CONFIRM EXISTING ASSUMPTIONS
==================================================

[HARD RULE]
BOARD UNIT CAP = PLAYER LEVEL.

Level 2 = max 2 deployed units.
Level 8 = max 8.
Level 10 = max 10.

Keep the 7x4 board; unit cap and physical board capacity are separate concepts.

[HARD RULE]
Players start at Level 2.

[HARD RULE]
Selling refunds the full PURCHASE cost represented by the unit:

1-star = 1x base cost
2-star = 3x base cost
3-star = 9x base cost

Example:
3-cost 2-star sells for 9g.
3-cost 3-star sells for 27g.

This keeps experimentation forgiving during early development. Revisit only if economy testing shows abuse.

==================================================
1. MATCH LENGTH + XP
==================================================

[TUNABLE STARTING POINT]
Target match: 24–28 minutes.
Expected final round: approximately Round 20–22.

Replace the previous XP curve with:

2 -> 3:   2 XP
3 -> 4:   6 XP
4 -> 5:  10 XP
5 -> 6:  16 XP
6 -> 7:  28 XP
7 -> 8:  40 XP
8 -> 9:  52 XP
9 -> 10: 64 XP

Natural XP remains 2 per completed PvP round.
XP purchase remains 4g = 4 XP.

Cumulative purchased/natural XP:
Level 8: 102 XP
Level 9: 154 XP
Level 10: 218 XP

Intent:
Level 8 should be routinely achievable.
Level 9 should require meaningful economy investment but be realistic.
Level 10 should be exceptional rather than expected every match.

==================================================
2. PLAYER DAMAGE
==================================================

[HARD RULE]
Starting HP = 100.

Damage on a loss:

PLAYER DAMAGE = STAGE BASE DAMAGE + 1 PER SURVIVING ENEMY UNIT

Enemy cost and star level DO NOT affect player damage.

This follows TFT's proven predictable-damage philosophy and prevents a surviving 3-star/high-cost unit from causing extreme HP spikes.

[TUNABLE STARTING POINT]

Rounds      Stage      Base Damage
1–4         1          2
5–8         2          4
9–12        3          6
13–16       4          8
17–20       5          11
21+         6          15

Example:
Stage 4 loss with 4 enemies alive:
8 + 4 = 12 player damage.

[HARD RULE]
A genuine draw deals 0 damage to both players.

==================================================
3. ROUND / STAGE STRUCTURE
==================================================

[HARD RULE]
NO PvE rounds for v0.1.

Every match round is PvP.

Reason: we currently have no item/loot/PvE system worth interrupting PvP for. Do not build placeholder PvE merely because TFT has PvE.

Stages exist for pacing and player-damage scaling:

Stage 1 = Rounds 1–4
Stage 2 = Rounds 5–8
Stage 3 = Rounds 9–12
Stage 4 = Rounds 13–16
Stage 5 = Rounds 17–20
Stage 6 = Rounds 21+

Stage should be exposed as match state.

==================================================
4. PAIRING
==================================================

[HARD RULE]
With an even number of active players, every player gets exactly one opponent.

Pairing priority:
1. Do not pair players who fought last round.
2. Prefer opponents not fought in the previous 2 rounds.
3. Among valid opponents, randomize.
4. If impossible, relax the 2-round restriction.
5. Only allow an immediate rematch when mathematically unavoidable.

Track opponent history server-side.

ODD PLAYER COUNT:

Use a ghost/copy battle.

One player fights a snapshot/copy of another active player's board.

The real player fighting the ghost CAN lose HP normally.

The player whose board supplied the ghost CANNOT gain or lose HP from the ghost battle.

A player should not receive a ghost opponent twice consecutively unless unavoidable.

The ghost source should not be the player's opponent from the immediately previous round when avoidable.

==================================================
5. ELIMINATION / PLACEMENT
==================================================

[HARD RULE]
HP <= 0 after Results = eliminated.

Placement is assigned after ALL combats for that round resolve.

If multiple players are eliminated simultaneously, rank them by:

1. Higher HP after damage wins the tie (example: -2 beats -8).
2. If tied: higher HP entering that round.
3. If still tied: higher total surviving-board unit count from that player's final combat.
4. If still tied: random server tie-break.

Eliminated players:
- cannot buy/sell/reroll/level/modify boards;
- cannot participate in future pairing;
- may remain as spectators.

Match ends when exactly one active player remains.

That player receives 1st place.

==================================================
6. TIMERS / COMBAT TIMEOUT
==================================================

[TUNABLE STARTING POINT]

Preparation: 30 seconds
Combat cap: 50 seconds
Results: 5 seconds

Increase combat from 45 -> 50 seconds because measured fights already reach ~42 seconds BEFORE armor/MR/abilities.

[HARD RULE]
At 50 seconds, resolve timeout by TOTAL REMAINING HEALTH PERCENTAGE:

For each team:
sum(current HP) / sum(max HP) of all units that entered combat.

Higher percentage wins.

If percentages are within 1 percentage point:
DRAW.

Do NOT use surviving unit count alone; a nearly-dead army should not beat one healthy tank purely because it has more bodies.

==================================================
7. LEAVERS
==================================================

[HARD RULE]
A disconnected player remains in the match for 2 full rounds.

Their:
- board stays frozen;
- bench stays frozen;
- gold/economy continues receiving automatic income;
- shop does not reroll automatically beyond normal round refresh;
- no purchases, sales, XP buys, positioning, or other actions occur.

They remain pairable and can deal/take normal player damage.

If they reconnect within the grace period, control resumes.

After missing 2 complete rounds:
HP becomes 0 at the next Results phase.
They are eliminated normally.
Their pairing slot disappears.
Their units return to the shared pool when that system exists.

Do NOT instantly eliminate disconnects because Roblox/network interruptions are common.

==================================================
DELIBERATELY DEFERRED
==================================================

DO NOT implement as part of this match-structure task:

- PvE encounters
- loot/items
- carousel/shared draft
- armor/MR
- mana
- abilities
- crit
- overtime combat buffs
- surrender voting
- reconnect persistence across server shutdowns
- ranked/MMR
- special comeback mechanics
- player-damage modifiers
- damage based on unit cost/star level
- spectator camera/UI beyond what is minimally necessary
- shared-pool return logic if the shared pool itself is not implemented yet

IMPLEMENT ONLY the match-structure systems necessary for:
HP -> pairing -> combat result -> player damage -> elimination -> placement -> winner.

All tunable starting values should live in configuration rather than being scattered through match logic.
