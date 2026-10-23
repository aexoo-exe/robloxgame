# Playtest guide (v0.1)

A small playtest: you plus 1–2 friends in a real multiplayer match, with bots filling the empty seats.

## 1. Before you start

- Sync the latest `feature/playtest-1` into Studio (`scripts/start.ps1`, then connect the Rojo plugin).
- For DataStores (the how-to-play "seen" flag, feedback, error log) to work in Studio:
  Home → Game Settings → Security → **Enable Studio Access to API Services**. The place must be
  published once. Without it everything still runs; entries are only printed to the Output.
- Bots: `src/shared/MatchConfig.luau` → `botsEnabled` (on/off), `botFillTo` (default 6), `botNames`,
  `botDifficulty` (`"easy"` default, for new players; `"normal"` for the old, stronger bots).
  Easy bots never reroll, ignore traits, level slowly, misplace some units and field one unit under
  their cap. In `sim/difficulty.luau` a random-buying "new player" places top 4 in about half of
  its matches against them (5% against normal bots). Re-check after tuning:
  `lune run sim/difficulty.luau 60 both` (takes a few minutes).
- Bots shop a few seconds into each Preparation and place their units one at a time, like a person.

## 2. Multiplayer test in Studio

1. Test tab → **Clients and Servers** → Local Server, **2 or 3 players** → Start.
   Studio opens a server window and one window per player (Player1, Player2, ...).
2. In one player window, walk onto the **Play** pad. With bots on, one queued player starts the
   15 s countdown; step the other players onto the pad before it ends.
3. The match starts with your players plus bots up to 6 seats ("Bot Ronin", ... with a BOT tag in
   the player list on the right).
4. Watch the **server window's Output** for `[RoundService]`, `[BotService]`, `[ErrorLog]` and
   `[Feedback]` lines.
5. Things to try on purpose:
   - Close one player window mid-match (a leaver): their row dims; after 2 missed rounds they are
     out. Reconnecting isn't possible in local Studio tests, so test rejoining on a live server: a
     rejoining player is put back in the match, gets their board and shop (and the fight in
     progress), and sees a "You're back! ... ends in Xs" banner.
   - Get one player knocked out: "Back to hub" works, the others keep playing.
   - Let every human lose: the match should end right away with the bots placed by HP.
   - The **Practice** pad still starts a solo match without bots.

## 3. Publish

1. With Rojo synced, File → **Publish to Roblox** (Alt+P) to the existing experience.
2. Creator Hub → Creations → your experience: check it shows the new version (Places → version history).

## 4. Give friends access

Roblox changes these menus often; look in Creator Hub → your experience → **Configure**
(Audience / Access / Privacy):

- Simplest: set the experience to **Public** for the playtest, share the link, and set it back to
  Private afterwards. Public needs the maturity questionnaire filled in once.
- Don't add friends as Collaborators just to play: that gives them edit access in Studio.

## 5. Reading feedback and errors

What gets saved:

- **Feedback** (DataStore `PlaytestFeedback`, key `recent`, newest 500): stars 1–5, the filtered
  text, placement, participants and bots, rounds, duration, units fielded, server id.
- **Errors** (DataStore `PlaytestErrors`, key `recent`, newest 200): source (`match loop`,
  `request RequestBuyUnit`, `bot Bot Kaze`, `hub poll`, `uncaught ...`), message, stack, phase,
  round, count in that batch. Errors are saved in batches every 30 s and on shutdown.

Ways to read them:

- **Live server, while it runs:** press F9 (Developer Console) → Server tab; you see the
  `[Feedback]` and `[ErrorLog]` lines (owner only).
- **Studio command bar** (View → Command Bar, API access enabled; works without playing):

  ```lua
  local ds, http = game:GetService("DataStoreService"), game:GetService("HttpService") for _, name in { "PlaytestErrors", "PlaytestFeedback" } do local list = ds:GetDataStore(name):GetAsync("recent") or {} print(name, #list .. " saved") for i = math.max(1, #list - 19), #list do print(http:JSONEncode(list[i])) end end
  ```

- **From the terminal** (Open Cloud key with DataStore read/list access for the experience):

  ```powershell
  $env:ROBLOX_API_KEY = "<key>"
  lune run scripts/playtest-logs <universeId> both 20
  ```

  `errors` or `feedback` in place of `both` shows one list. Never commit the key.

Note: Studio tests of a published place write to the same DataStores as the live game, so test
entries show up in the lists too (their `server` field is empty in Studio).

## 6. What gets tracked (analytics)

Server-side only (src/server/PlaytestAnalytics.luau); humans only, bots are never logged.

**Roblox analytics** (Creator Hub → your experience → Analytics; live servers only, skipped in
Studio):

- Onboarding funnel, in order: 1 `joined`, 2 `intro_finished`, 3 `queued`, 4 `first_match_started`,
  5 `round_5_reached`, 6 `match_finished`, 7 `feedback_sent`.
- Progression path `Match`: started at round 1, completed per round survived, failed at the round
  the player is knocked out.
- Custom events: `unit_bought`, `unit_sold`, `star_up` (unit id, star), `trait_active` (trait, level;
  once per player, trait and level per match), `reroll`, `level_up` (level).

**Our match log** (DataStore `PlaytestMatches`, also from Studio when API access is on, marked
`studio`):

- `recent`: the newest 500 match records: duration, rounds, humans and bots, bot difficulty, and per
  human: placement, final level, gold spent, rerolls, XP bought, units bought and sold, units
  picked and fielded, a board snapshot every 5 rounds (`unit_id:star`), the final board, active
  traits at the end, and a quit point (round and phase) if they left while still in the match.
- `units`: all-time per-unit totals (picked, fielded, fielded and placed top 4).
- `funnel`: how many players reached each funnel step for the first time (Studio test players are
  not counted).

**The report:**

```powershell
$env:ROBLOX_API_KEY = "<key>"
lune run scripts/playtest-report <universeId>            # the report, with feedback and errors
lune run scripts/playtest-report <universeId> --csv      # also reports/units.csv, funnel.csv, players.csv
lune run scripts/playtest-report <universeId> --studio   # include matches logged from Studio
```

It shows matches and average length, the funnel with drop-off, quit points, unit pick and top-4
rates, traits at the end, the most common final boards, and the newest feedback and errors.
`reports/` is gitignored. CI runs the report on a simulated match log
(tests/PlaytestReportTest.luau), so its shape stays in step with the server's.

**Privacy:** nothing personal is stored beyond the Roblox UserId (and the player's name next to
feedback). Feedback text is filtered with TextService before it is stored (dropped if filtering
fails). No chat, no device data. To remove a player's data on request, delete their entries from
`PlayerFlags` (key `u<UserId>`) and their records from the lists (Open Cloud or the command bar).

## 7. What to watch during the playtest

- [ ] The how-to-play intro shows in the hub before each player's first match, can be skipped, and
      the "?" button (top left in a match) opens it again, docked at the left edge without blocking
      the board. It doesn't show again next session.
- [ ] New-player help: the shop card "i" button (and hover tooltip with a mouse) shows role and
      ultimate; "UNITS 3/4" under the shop; a hint when a fight starts with room on the board;
      trait rows show "2/3"; the top bar says "Next: Creeps" / "vs <opponent>".
- [ ] Phones: buttons are tappable, the shop and tooltips fit, the info button opens the unit panel.
- [ ] Easy bots feel beatable but not empty (new players should place top 4 about half the time).
- [ ] Every player sees only their own shop, gold and bench; boards fight the right opponents.
- [ ] Bots buy, level and field units (their boards aren't empty after round 4 or so).
- [ ] HP, eliminations and placements look right in the player list and the final screen.
- [ ] Nobody gets stuck: after the match (or "Back to hub") everyone is back in the hub.
- [ ] The feedback panel appears in the hub after each match and sending it says "Thanks!".
- [ ] No `[ErrorLog]` lines in the server output (or note when they appeared).
- [ ] Frame rate during big fights and ultimates on the slowest friend's machine.
- [ ] Ask friends what confused them in the first 3 rounds.
