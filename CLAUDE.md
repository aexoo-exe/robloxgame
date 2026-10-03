# robloxgame — Claude Development Instructions

## Project

robloxgame is a Roblox auto-battler currently in early development.

The game is inspired by auto-battlers such as Teamfight Tactics, with an emphasis on anime-inspired characters, transformations, team building, and increasingly fast gameplay as a match progresses.

## Development Environment

- Language: Luau
- IDE: Visual Studio Code
- Engine: Roblox Studio
- Sync: Rojo
- Tool manager: Rokit
- Version control: Git / GitHub

## Source Structure

- `src/client` — client-side code
- `src/server` — server-authoritative game logic
- `src/shared` — modules shared between client and server

## Core Design Direction

Planned systems include:

- Auto-battler combat
- 7x4 player boards
- Eventually up to 8 players
- Character shop
- Shop expands as the player progresses through the match
- Shop rerolling
- Gold economy
- Player levels and XP
- Unit cost tiers
- Bench
- Unit placement
- 1-star, 2-star, and 3-star unit upgrades
- Traits and team synergies
- Character abilities
- Character-specific transformations
- Player health and elimination
- Increasing match speed and spectacle from early game to late game

These are design goals, not permission to implement all systems without being asked.

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

- `main` represents the known-working version.
- Do not force-push.
- Do not rewrite Git history.
- Do not commit secrets, credentials, API keys, generated files, or machine-specific configuration.
- Use focused commits with descriptive messages.
- Major features should eventually be developed on feature branches.
- Do not merge into `main` unless explicitly instructed.

## Current Development Stage

The project is currently in foundation/setup stage.

Do not attempt to build the entire game unless explicitly instructed.

The current priority is establishing a clean, reproducible development environment before implementing V0.1 gameplay.

## When Completing a Task

Always report:

- Files created
- Files modified
- What was implemented
- Tests/checks performed
- Any known limitations
- Recommended next step

End substantial development responses with:

## COPY FOR GPT

Provide a concise summary of the work completed, important implementation details, test results, and anything GPT should know before planning the next task.