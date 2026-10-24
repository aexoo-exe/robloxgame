# Retention v1

Reasons to come back that never touch a match. **Fairness rules:** no stat boosts, no units behind
progression or payment, no gameplay advantage from anything here. Rewards are cosmetics, titles,
soft currency or progress. Bots never earn or affect progression. Monetization later is
cosmetics-only (boxes per category: arena skins, emotes, finishers, flair); nothing is purchasable
yet.

Code: `src/shared/RetentionConfig.luau` (every number below), `Progression`, `Quests`, `Mastery`,
`ProfileSchema` (pure, tested in `tests/RetentionTest.luau`), `src/server/PlayerData.luau`,
`src/server/RetentionService.luau`, `src/client/PostMatchSummary.luau`, `src/client/ProfilePanel.luau`.

## Reasons to come back

| System | What it gives | Status |
|---|---|---|
| Account level | XP from every match; level-up rewards 2–30 | v1 |
| Daily / weekly quests | 3 + 3 small goals, coins and XP | v1 |
| Unit mastery | per-unit levels, badges and titles; later recolors and finishers | v1 (data and list) |
| Collection | titles, nameplates, profile icons, board skins (BoardSkinConfig), emotes, finishers | ids stored in v1; equip UI for titles only |
| Gentle streak | days played and a streak counter; the day's first match pays a small coin bonus | v1; missing days costs nothing |
| Season pass | free track first, a cosmetic premium track later | design only |

## Account XP

Per match (`Progression.matchXp`): **60** for finishing a Play match + **4 per round survived** +
a placement bonus **90 / 70 / 55 / 45 / 30 / 20 / 12 / 8** (1st to 8th). Practice: **40%** of that.
Leaving early: **25%** of base + rounds, no placement bonus, **at least 10** (never zero).
Examples: 1st after 12 rounds 198, 4th after 10 rounds 145, 6th after 6 rounds 104, a Practice win
76, leaving at round 3 18.

Level curve: XP to the next level = **120 + 30 × (level − 1)^1.35**. Fast early, slower later:

| Level | XP to next | Total to reach the next | Roughly |
|---|---|---|---|
| 1 | 120 | 120 | one match |
| 5 | 315 | 1,033 | ~6 matches |
| 10 | 703 | 3,728 | ~20 matches with quests |
| 20 | 1,717 | 16,123 | a few weeks of regular play |
| 29 | 2,816 | 36,966 (level 30) | a season |

### Level-up rewards (levels 2–30)

Every level: **40 + 10 × level coins**. Plus:

| Level | Reward | Level | Reward |
|---|---|---|---|
| 2 | title Rookie | 15 | title Strategist |
| 3 | profile icon (spark) | 16 | profile icon (wave) |
| 4 | nameplate (steel) | 18 | board skin (sakura) |
| 5 | title Contender | 20 | title Veteran |
| 6 | profile icon (blade) | 22 | nameplate (gold) |
| 7 | board skin (dusk) | 24 | finisher (thunder) hook |
| 8 | profile icon (flame) | 25 | title Warlord |
| 10 | title Tactician | 26 | profile icon (crown) |
| 12 | nameplate (jade) | 28 | board skin (eclipse) |
| 14 | emote (bow) hook | 30 | title Legend + nameplate (legend) |

Cosmetic ids are stored on the profile now; the art and equip UI come later.

## Quests

3 dailies (reset 00:00 UTC) and 3 weeklies (reset Monday 00:00 UTC), rolled per player from the
pools, the same on every server. **One free reroll per day** (swap one unfinished daily). Progress
counts in Play and Practice matches (placement quests only in Play). Claim in the hub profile for
coins and account XP.

| Daily | Target | | Weekly | Target |
|---|---|---|---|---|
| Play matches | 2 | | Play matches | 10 |
| Place top 4 | 1 | | Place top 4 | 5 |
| Win rounds | 5 | | Win rounds | 30 |
| Reroll the shop | 6 | | Upgrade a unit to 3 stars | 1 |
| Upgrade units to 2 stars | 3 | | Win rounds with <trait> active | 12 |
| Fight rounds with 3 traits active | 3 | | | |
| Win rounds with <trait> active | 3 | | | |

Rewards: dailies 50–80 coins and 60–100 XP; weeklies 250–300 coins and 300–350 XP. Every daily is
doable by a new player in one or two matches against easy bots (PvE rounds count as round wins).

## Unit mastery

Per unit a player fields: **5 XP per round** it fought on their board, plus **20** per unit on the
final board when the player placed top 4 (**5** otherwise). Levels 1–10 at 0 / 50 / 150 / 300 /
500 / 800 / 1,200 / 1,700 / 2,300 / 3,000 total XP. Rewards: level 3 bronze badge, 5 silver badge +
title Adept, 7 gold badge, 8 VFX recolor (hook), 10 finisher (hook) + title Master. The profile
shows the top 12 units.

## Soft currency

"Coins" (placeholder name): from levels, quests and the day's first match. Spent later on
cosmetics. A premium currency only via Robux later, kept separate; nothing is built for it.

## What players see

- **Post-match summary** (hub, after each match): placement, XP with the bar filling and a
  "LEVEL N!" moment per level with its reward, coins, quest ticks, mastery gains.
- **Hub profile panel**: level, XP, coins, title, quests with CLAIM and SWAP, mastery list; the
  PROFILE button shows "!" when a quest is ready to claim.
- Later: a toast when a quest completes mid-match, profile icons and nameplates on the player list.

## Anti-burnout and fairness

- Nothing expires that was earned; missing days never costs progress (only the streak counter).
- Dailies are small (one or two matches); weeklies cover a few sessions; no "log in or lose" timers.
- No grind multipliers for play time; the day's first-match bonus is small.
- Practice earns less so Play stays the main way, but Practice still counts for quests.
- Server-authoritative: every grant on the server; requests are validated and rate-limited.

## What we measure

Through PlaytestAnalytics (custom events, plus the existing funnel and match log):
`quest_completed` (quest id), `level_up_account` (level), `mastery_level` (unit, level),
`return_day` (days since the first visit, once per UTC day: day-1 and day-7 return).
Targets for the playtest: median account level after the first session, share of players who
complete at least one daily, day-1 / day-7 return.

## Season pass (design only)

A ~8-week season with a free track first (cosmetics, coins, titles) earned with season XP from
matches and quests. A premium cosmetic track later, Robux only. No gameplay rewards on either.
