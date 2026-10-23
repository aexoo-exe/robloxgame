# 2026-10-23: playtest hardening (autonomous session)

Branch `feature/playtest-1`. The user was away; decisions made without them are marked **Decision**.
CI (GitHub Actions) runs the tests after every phase; the Lune suite was not run locally.

## Phase 1: playtest blockers

- **How-to-play placement.** It no longer opens in the match. A player who hasn't seen it gets it in
  the hub before their first match (centered, dim backdrop; the backdrop is a plain Frame and takes
  no input). If a match starts while it is open, or the "?" button opens it in a match, it docks at
  the left edge without a backdrop, so the board, bench and shop stay usable. "?" toggles it.
  **Decision:** hub-first instead of a side panel during the first Preparation (simpler, and the
  first match starts with a creep round that needs no shopping anyway).
- **Rejoin mid-match.** CombatService keeps this round's fight payload per player. Every client fires
  `RequestMatchSync` once its screens have started; for a participant the server resends board and
  shop, and during Combat the fight, which CombatPlayback already plays from the current moment
  (earlier events applied without their one-shot effects). A "You're back! ... ends in Xs" banner
  shows for 5 s. Sync requests are rate-limited (one per 2 s per player).
- **Leaving never stalls.** Checked by reading: the hub queue is rebuilt from the current players
  every poll (a leaver drops out; the countdown cancels if the queue empties), phase timers are
  plain clocks that don't wait on anyone, and every send/state update skips players who aren't
  there. A leaver stays in the match (leaver grace rounds) and can rejoin. No change needed.

Open questions:
- Rejoining can only be tested on a live server (Studio local tests can't reconnect a client).
