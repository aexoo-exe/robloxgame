# Director

Claude is the project director: it picks the work, builds it, judges it and reports to the user
directly. Continue work with **`/next`** (`.claude/skills/next/SKILL.md`), which reads this file
and does the top "Now" item. Unit ids only in this file; real names live in `docs/references/`
(gitignored).

## Now / Next / Later

Updated at the end of every task. `(user)` marks an item that needs the user; `/next` asks for
exactly that and moves on to the next item it can do alone.

**Paused 2026-10-27 (resume here):** to merge (user OK needed): `feature/hold-views` (hold side /
front34 / back34 views, verified) and `feature/slice-severing_temple` (built, reviewed: no FAIL;
Studio-checked with 5 held beats and one fix round, fixes not re-captured; contains hold-views). Then
starless_burst, the cinder_arc / flashline arm sweep, and animation-notes Plan step 2.

**Now**

1. **Playtest readiness:** done. CI green on `main`, [playtest.md](playtest.md) syncs from `main`,
   and the smoke run passed (2026-10-27, `main` 2e29f83): a Practice match ran rounds 0-4 (creeps
   won, gold and XP paid, board, bench, shop, traits, HUD all showing), no gameplay errors; the only
   `[ErrorLog]` line is "profile not loaded" (Studio without API access). Found:
   - the **item pick panel opens over the middle of the board during the fight** (it hides the
     fight): fix before friends play (Now 2);
   - the intro "seen" flag can't save in Studio without API access, so the intro returns every
     Studio session (fine on a live server; enable API access per playtest.md for Studio tests);
   - (user) the shop's display nicknames ("Jonny", "Dengi", "Kenny", ...) are close to real
     character names: the user decides whether they stay for a public playtest.
2. **Item pick panel off the fight:** done on `feature/item-pick-off-fight` (verified in Studio: open
   in Preparation, gone when the fight starts). The panel over the fight was a stale choice the server
   had already resolved (`PlayerState.startCombat`).
3. **Friend playtest** (user): 1-2 friends, the checklist in [playtest.md](playtest.md) section 7.
   Afterwards Claude reads the feedback and errors (`scripts/playtest-report`, needs the user's
   Open Cloud key in their own terminal) and turns them into queue items.
4. **mount_spurshot v2.2 import** (user, then Claude): the user imports the v2.2 FBX
   (`feature/models-pilot`, commit `dfb5a43`; a copy at `tools/mount_spurshot_v2_2.fbx`, gitignored,
   so it works from any branch) with File > Import 3D (the MCP can't run the importer; the old 100x
   copy is already removed from Workspace); Claude re-runs the MCP model check (scale
   vs a 4.6-stud R6, seat, coat, outline, match-camera view). Then the review gate (user).
5. **Merge** (user OK): `feature/playtest-ready` (director, notes, playtest guide),
   `feature/item-pick-off-fight`, `feature/devlineup-hold` (the beat-hold capture tool) and
   `feature/slice-infinite_collapse` (built, reviewed, Studio-checked with one fix round; it contains
   the hold tool). All four green on CI.
6. **Overhaul wave 1: severing_temple** (Claude): `/slice-unit` with its concept from
   [overhaul-plan.md](design/overhaul-plan.md); check it with `hold` (playbook, Dev keys).
7. **Hold camera + arm sweep** (Claude): a side / front camera option for `hold`, then sweep
   cinder_arc and flashline for the forward + out arm bug ([animation-notes.md](design/animation-notes.md)).

Before any Studio capture: make sure Studio isn't minimized (a minimized window captures black);
restore it without focus (the user approved this).

**Next**

- **Animation quality** (the user's top concern; Claude owns it): the plan in
  [animation-notes.md](design/animation-notes.md): per-channel overlap in PoseAnimator, then elbow
  and knee channels, then re-pose the three reference ultimates.
- Wave 1 rest: starless_burst.
- Studio-check cinder_arc and flashline (their "Studio-checked" boxes are open in the queue).
- Library sound ids (user picks): 16 of 20 library sounds have no id
  ([sound-picks.md](design/sound-picks.md)); Claude lists candidates, the user auditions and picks.
- Playtest follow-up: fix what the playtest found; re-order the later waves by unit pick rates.
- Waves 2-3 (heavy brawlers, energy blasts).

**Later**

- Waves 4-13 ([overhaul-queue.md](design/overhaul-queue.md)).
- Creature models: after the pilot passes its gate, the other six (`creature-models.md` on
  `feature/models-pilot`), then integration (option 2: part-based Figure posing) and merging the
  pilot branch.
- Retention: equip UI beyond titles, the season pass (design only today, [retention.md](design/retention.md)).

## Goal

A high-end, recognizable anime auto-battler: every unit reads as its character from the match
camera, every ultimate is a moment players remember, and matches get faster and more spectacular as
they go. Near term: a **friend playtest** (1-2 friends), then the **VFX + sound overhaul** (all 42
ultimates to the playbook standard, a shared sound library) and the **creature models** (two mounts,
four titans, one summon).

## Current state

- **Game loop:** shop, gold, levels, bench, 7x4 boards, stars, traits, forms, items, PvE rounds and
  bots (easy by default) on `main`. Playtest tooling (onboarding intro, feedback panel, error log,
  analytics, match log, report script) is merged; the playtest itself hasn't happened yet.
- **Retention v1** merged: account XP and level rewards, daily/weekly quests, unit mastery, coins,
  post-match summary and profile panel ([retention.md](design/retention.md)).
- **Overhaul:** plan, concepts and 13-wave queue done ([overhaul-plan.md](design/overhaul-plan.md),
  [overhaul-queue.md](design/overhaul-queue.md)). Built and merged: cinder_arc (template) and
  flashline; neither has been Studio-checked. The other 40 wait, in wave order.
- **Sounds:** the shared library has 20 sounds; 4 have ids (whooshLight, impactLight, impactHeavy,
  fireBurst).
- **Creature models:** pilot mount_spurshot at v2.2 on `feature/models-pilot` (not merged): generator,
  rig, three animations, FBX. v2.1 imported at 100x (fixed in v2.2's export, not yet re-imported);
  the other six wait for the pilot's review gate.

## How to work

One task = one pass through:

1. **Plan:** read this file, the item's queue row and its design doc; say in one or two lines
   what you'll do.
2. **Build** on a feature branch (`feature/<name>`, from `main` unless the item lives on another
   branch). Ultimates go through `/slice-unit`.
3. **Self-review:** the `playbook-reviewer` agent for ultimates (one round; fix FAILs, cheap WARNs).
   For other work, re-read the diff against CLAUDE.md's rules.
4. **Studio MCP visual check:** at most **8 screenshots**, from fixed cameras, judged against the
   quality bar below. Check the console output once.
5. **At most one fix round**, then stop. Never a third round on the same thing: log what's left as
   leftovers in the queue.
6. **Commit and push** the feature branch.
7. **Short summary to the user**: what changed and what's next, then the HANDOFF block (CLAUDE.md)
   for the record. Update Now / Next / Later and the queues before pushing.

Parallel work: worktrees (`isolation: "worktree"`) for independent units of a wave when it's worth
it, **at most 3 agents** at once. Each agent runs `/slice-unit` on its own branch.

## Quality bar

Judge your own screenshots against this before calling anything done.

**Ultimates and VFX**

- No static or camera-facing sprites for weapon arcs: use trails. Nothing pops in at full size and
  freezes.
- No effect covering most of the screen or hiding the caster. Blooms go behind targets and last
  at most 0.45 s.
- No world-space flames or particles left hanging where the caster used to be.
- No floor washes from big lights: lights are small and short.
- Mesh rings are capped; dust and smoke fade fast.
- Poses big and readable (about 2x realistic); each strike is its own beat; readable from the match
  camera (G key).
- Colors saturated, not washed out to cream or white.
- Within the tier budget (`ReelConfig.budget`), aiming for half at peak.

**Animation** (running list: [animation-notes.md](design/animation-notes.md); add to it whenever
you watch a replay)

- Overlap: head and arms trail the torso; nothing arrives all at once.
- Weight: feet plant, landings compress, dashes step rather than glide.
- Silhouette first: each key pose reads with the effects hidden.

**Creature models**

- Check scale against an R6 figure (riders must fit on the seat).
- Silhouettes readable at match distance.
- Spots and markings chunky but not "cow blobs".
- No 100x import scale: check the size in Studio after every import.

## When to ask the user

Only for:

- Picking sound ids (Claude lists candidates; the user auditions and chooses).
- Approving a creature model at its review gate.
- Merging anything to `main`.
- Anything that costs money (Robux, paid assets, ads).
- Big design-direction changes.
- Studio actions the MCP can't do (3D import, publishing, game settings, Creator Hub). Give exact
  click-by-click steps, and any commands in copyable code blocks.

Everything else: decide, do it, and report.

## Usage

The user watches their session limit:

- No local test, audit or sim runs: CI runs them on every push; read the CI result
  (`gh run list --branch <branch>`).
- Studio MCP screenshots capped at 8 per task.
- Prefer one solid pass over many small ones.

## User preferences

- Terminal commands in copyable code blocks.
- End each task with a short summary of what changed and what's next, then the HANDOFF block.
- IP: real names only in `docs/references/` (gitignored); ids everywhere else, commit messages
  included.
