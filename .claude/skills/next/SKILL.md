---
name: next
description: Continue the project as its director. Reads docs/director.md and the queues, picks the top "Now" item, does it end to end (plan, build, self-review, Studio MCP check, one fix round, commit, push), updates Now / Next / Later and the queues, and summarizes. Asks the user only for what docs/director.md says needs them. Invoked as /next.
---

# /next

You are the project director ([docs/director.md](../../../docs/director.md)). Do the next piece of
work end to end.

## 1. Pick

1. Read `docs/director.md` (all of it), `docs/design/overhaul-queue.md`, and the design doc of the
   item you pick (`overhaul-plan.md`, `creature-models.md`, `retention.md`, `playtest.md`, ...).
2. Take the **top "Now" item**. If it is marked `(user)`, or needs one of the "When to ask the user"
   things (a sound pick, a review gate, a merge to `main`, money, a Studio action the MCP can't do):
   - ask for **exactly** that, with click-by-click steps and any commands in code blocks,
   - and move on to the next "Now" item that you can do alone (then "Next", in order).
   Don't wait on the answer in the same task.
3. Say in one or two lines what you're going to do. Then do it without further check-ins.

## 2. Do it (the workflow in director.md)

1. **Branch:** `feature/<name>` from `main`, unless the item lives on another branch (e.g. the
   models pilot on `feature/models-pilot`). Never commit to `main`.
2. **Build.** Ultimates: run `/slice-unit <unit_id> "<concept>"` with the concept from
   `overhaul-plan.md`; it has its own review, Studio check and time-box. When a wave has independent
   units and it's worth it, run them in parallel with the Agent tool (`isolation: "worktree"`,
   **at most 3 agents**), one `/slice-unit` per agent on its own branch.
3. **Self-review:** the `playbook-reviewer` agent for ultimates (one round). Other work: re-read the
   diff against CLAUDE.md's rules.
4. **Studio MCP check:** at most 8 screenshots from fixed cameras, the console output once, judged
   against the quality bar in director.md. Skip it if the MCP isn't connected and say so.
5. **One fix round at most.** Never a third round on the same thing. What's left becomes a leftover:
   a note in the queue row or a new "Next" item.
6. **Don't run tests, the audit or the sim locally.** CI runs them on push; check it with
   `gh run list --branch <branch> --limit 1` and report the result.

## 3. Record and push

1. Tick the item's queue columns (`overhaul-queue.md`), and update `docs/director.md`: move the item
   out of "Now" (or note what's left), promote from "Next" so "Now" has 3-4 items, and update
   "Current state" if something changed.
2. Commit in focused chunks (ids only, the session's attribution line), then
   `git push -u origin <branch>`. Never merge to `main` without asking.

## 4. Report

A short summary for the user: what changed, what you saw in Studio, what's next, and anything you
need from them (with exact steps). No HANDOFF block while CLAUDE.md has them paused.
