# robloxgame — Claude Development Instructions

## Project

robloxgame is an anime-inspired Roblox auto-battler (in the style of Teamfight Tactics): a shop, gold and levels, a bench and 7x4 boards, star upgrades, traits, forms/transformations, items, PvE rounds and bot opponents. Matches get faster and more spectacular as they go.

### Current state

- **Roster:** 42 units, referred to by unit id only (`src/shared/UnitConfig.luau`). Each unit's signature ultimate is a client module in `src/client/Ultimates/<unit_id>.luau`, configured in `src/shared/UltimateConfig.luau`.
- **VFX kit:** `VfxRecipe` (layer recipes), `ImpactEffects` (particles, rings, lights, budgets), `VfxPicks` + `assets/vfx/ids.json` (texture/mesh ids), Blender generators in `scripts/blender/` (portable Blender lives in `tools/`, gitignored).
- **Dev tools:** `DevLineup` (close-ups, test arenas, reel), `ReelCheck` (peak vs tier budget, leaks, unloaded textures).
- **Ultimate template:** `cinder_arc` is finished and is the template for every ultimate. Rebuild others with the `/slice-unit` skill.

### Key docs

- [docs/design/ultimate-playbook.md](docs/design/ultimate-playbook.md): how every ultimate is built (modules, beats, caps, budgets, dev keys).
- [docs/design/vfx-style.md](docs/design/vfx-style.md): the texture look and the asset pipeline.

## Development Environment

- Language: Luau
- IDE: Visual Studio Code
- Engine: Roblox Studio
- Sync: Rojo
- Tool manager: Rokit
- Version control: Git / GitHub

## Source Structure

- `src/client`: client-side code (presentation, UI, ultimates, VFX)
- `src/server`: server-authoritative game logic
- `src/shared`: modules and config shared between client and server
- `scripts/`: Lune/PowerShell tooling, Blender scripts, Studio helpers
- `sim/`, `tests/`: headless simulation and Lune tests (not synced to Roblox)

## Standing Rules (every task)

1. **Do not run tests, the audit, the sim, Studio MCP or Blender MCP** unless the user explicitly asks in that task. They cost usage.
2. **Unit ids only.** Never put real character or anime names in code, comments, file names, assets or commit messages. Real names belong only in gitignored `docs/references/`.
3. **Presentation never changes gameplay.** Client effects, poses and ultimates must never change server results, event timing or real unit positions.
4. **Stay within the tier VFX budgets** (`ReelConfig.budget`, the same as the audit's PEAK_LIMIT). Aim for half the tier budget at peak.

## Engineering Rules

1. Keep systems modular.
2. Prefer configuration/data-driven character definitions over hardcoded character logic.
3. Keep important combat and economy decisions server-authoritative.
4. Do not trust the Roblox client with authoritative game state.
5. Keep client code focused on input, presentation, UI, animation, and effects.
6. Do not introduce external dependencies unless requested or clearly justified.
7. Do not modify unrelated systems while implementing a feature.
8. Do not delete working functionality unless explicitly requested.
9. Preserve compatibility with the existing Rojo project structure.
10. Prefer readable Luau over unnecessary abstractions.

## Git Rules

- `main` represents the known-working version. Never push to or merge into `main` unless told to.
- Work on a feature branch (`feature/<name>`) for every task.
- Commit in focused chunks with descriptive messages.
- At the **end of every task**, push the feature branch so the work is backed up: `git push -u origin <branch>`.
- Do not force-push. Do not rewrite Git history.
- Do not commit secrets, credentials, API keys, generated files, or machine-specific configuration.

## When Completing a Task

End every task with a **HANDOFF** in ONE copyable code block:

```
HANDOFF
Branch: feature/<name>  (pushed: yes/no)
Commits: <hash> <message>, ...
Files changed: <path> (new/modified), ...
What changed: <short bullets>
Per-unit beats: <unit_id>: <timeline>   (if relevant)
New sounds/assets needing ids: <SfxConfig name>: <description>, ...
Budget peaks: <unit_id> <peak>/<tier budget>   (estimated unless measured)
Unsure: <anything guessed or unverified>
Next step: <one recommendation>
```
