# robloxgame

tft clone

## Current stage

i ain done shi yet

## Repository structure

```
robloxgame/
├── default.project.json   Rojo project: maps src/ into the Roblox DataModel
├── rokit.toml             Pinned tool versions (Rojo, StyLua, Selene, Lune)
├── stylua.toml            Formatter settings
├── selene.toml            Linter settings
├── .luaurc                Luau type-checking mode for editor tooling
├── .vscode/               Recommended VS Code extensions and workspace settings
├── docs/                  Design and implementation plans
├── scripts/
│   ├── setup.ps1          One-time bootstrap of repository tools
│   ├── start.ps1          Starts a dev session (Rojo server)
│   ├── test.ps1           Runs the Lune tests
│   └── simulate.ps1       Runs the headless match simulation
├── sim/                   Headless bot match simulation (not synced to Roblox)
├── tests/                 Lune tests for the pure shared modules (not synced to Roblox)
└── src/
    ├── client/            Client code   -> StarterPlayer.StarterPlayerScripts.Client (LocalScript)
    ├── server/            Server code   -> ServerScriptService.Server (Script)
    └── shared/            Shared code   -> ReplicatedStorage.Shared (Folder)
```

`init.server.luau` and `init.client.luau` turn the `server` and `client` folders
into a Script and a LocalScript. Other `.luau` files placed in those folders
become ModuleScripts parented under them.

## Required external software

Install these yourself before running the setup script:

| Software | Why | Where |
| --- | --- | --- |
| Git | Clone and version control | https://git-scm.com/download/win |
| Rokit | Installs the pinned project tools | https://github.com/rojo-rbx/rokit#installation |
| Roblox Studio | Runs the game | https://create.roblox.com/ |
| Visual Studio Code | Editor | https://code.visualstudio.com/ |

You do **not** install Rojo, StyLua, or Selene by hand. Rokit installs the
exact versions listed in `rokit.toml`.

## Fresh Windows PC setup

### 1. Install the external software

Install Git, Rokit, Roblox Studio, and VS Code from the table above.

To install Rokit, follow its installation instructions. On Windows that means
downloading the latest `rokit-*-windows-x86_64.zip` from the
[Rokit releases](https://github.com/rojo-rbx/rokit/releases), extracting it, and
running `.\rokit.exe self-install` from that folder.

**Open a new terminal afterwards** so Git and Rokit are on your `PATH`. Check:

```powershell
git --version
rokit --version
```

### 2. Clone the repository

```powershell
git clone https://github.com/aexoo-exe/robloxgame.git
cd robloxgame
```

### 3. Bootstrap the project tools

```powershell
powershell -ExecutionPolicy Bypass -File scripts\setup.ps1
```

The script:

1. Checks that Git and Rokit are installed (and stops with a clear message if not).
2. Lists the tools in `rokit.toml` and asks you to confirm trusting them.
3. Runs `rokit install` to download the pinned versions.
4. Verifies that `rojo`, `stylua`, `selene`, and `lune` run and report the pinned versions.

It does not install any system software. Re-run it whenever `rokit.toml` changes.
Pass `-Yes` to skip the confirmation prompt.

> `-ExecutionPolicy Bypass` applies only to that one command. It does not change
> your system's PowerShell policy.

### 4. Set up VS Code

Open the `robloxgame` folder in VS Code. When prompted, install the
**recommended extensions** (or open the Extensions view and filter by
`@recommended`):

- **Luau Language Server** (`JohnnyMorganz.luau-lsp`) for autocomplete, type checking, and Roblox API types
- **StyLua** (`JohnnyMorganz.stylua`) for format on save, using `stylua.toml`
- **Selene** (`Kampfkarren.selene-vscode`) for inline lint warnings, using `selene.toml`

The workspace settings in `.vscode/settings.json` make StyLua the Luau formatter,
enable format on save, and let Luau LSP generate `sourcemap.json` from
`default.project.json` so it understands the Roblox instance tree.

### 5. Install the Rojo plugin in Roblox Studio

The Studio plugin version should match the Rojo version in `rokit.toml` (7.7.1).

Recommended: run this from the repository folder with Studio **closed**:

```powershell
rojo plugin install
```

Alternatively, install **Rojo** from the Roblox Creator Store inside Studio.

Restart Studio. A **Rojo** button should appear in the **Plugins** tab.

## Starting a development session

1. Start the Rojo server from the repository folder and leave the window open:

   ```powershell
   powershell -ExecutionPolicy Bypass -File scripts\start.ps1
   ```

   (Equivalent to `rojo serve default.project.json`.)

2. Open Roblox Studio and open a place. Any of these works:
   - a new **Baseplate** place, or
   - a place built from source: `rojo build default.project.json -o robloxgame.rbxlx`,
     then open `robloxgame.rbxlx` (built place files are ignored by Git).

3. In Studio, go to **Plugins > Rojo > Connect** (default `localhost:34872`).

4. Edit files in `src/` in VS Code. Changes sync into Studio when you save.

Stop the server with `Ctrl+C`.

## Verifying VS Code -> Rojo -> Studio sync

1. With Rojo connected, check Studio's Explorer for:
   - `ReplicatedStorage > Shared > SyncCheck`
   - `ServerScriptService > Server`
   - `StarterPlayer > StarterPlayerScripts > Client`
2. Press **Play**. The Output window should show:
   ```
   robloxgame server is alive! ^w^
   [server] ReplicatedStorage.Shared is synced
   robloxgame client is alive!
   [client] ReplicatedStorage.Shared is synced
   ```
3. Stop play mode, change the `message` in `src/shared/SyncCheck.luau`, save, and
   press Play again. The new message should appear.

## Formatting, linting and tests

Run these from the repository folder:

```powershell
stylua src tests sim          # format all Luau files
stylua --check src tests sim  # check formatting without changing files
selene src tests sim          # lint
powershell -ExecutionPolicy Bypass -File scripts\test.ps1      # run the tests
powershell -ExecutionPolicy Bypass -File scripts\simulate.ps1  # headless 8-bot match pacing
```

The tests run with [Lune](https://github.com/lune-org/lune) outside Roblox Studio. They cover
the modules in `src/shared` that use no Roblox APIs: hex grid, board rules, economy, shop,
star upgrades, pairing, match rules and the combat simulation, including forms
(transformations; see `docs/forms.md`) and PvE rounds (creeps and bosses; see `docs/pve-rounds.md`). `scripts\simulate.ps1` plays
full matches between scripted bots with those same modules and prints pacing numbers (rounds,
match length, winner level, fight timeouts). These modules require each other with
`if script then require(script.Parent.X) else require("./X")` so the same code loads in both
Roblox and Lune.

## Git workflow

- **`main` is the known-working branch.** Do not commit directly to it.
- Do new work on a **feature branch**:

  ```powershell
  git checkout main
  git pull
  git checkout -b feature/short-description
  ```

- Make focused commits with descriptive messages.
- Before committing, run `stylua --check src tests sim`, `selene src tests sim` and `scripts\test.ps1`.
- Push your branch and open a pull request into `main`.
- Do not force-push shared branches or rewrite history.
- Do not commit built place files (`*.rbxl`, `*.rbxlx`), secrets, or
  machine-specific settings.

## Troubleshooting

**`rokit` / `rojo` / `stylua` is not recognized**
Open a new terminal after installing Rokit. If it still fails, run
`rokit self-install` again, then reopen the terminal.

**`Failed to find tool '...' in any project manifest file`**
Rokit tools only work inside a folder containing `rokit.toml`. `cd` into the
repository root.

**`The following tool has not been marked as trusted`**
Run `scripts\setup.ps1`, or `rokit trust <owner/repo>` for that tool.

**`rokit install` fails with a GitHub rate-limit error**
Run `rokit authenticate github`, then re-run the setup script.

**Running a script fails with "running scripts is disabled on this system"**
Use the `powershell -ExecutionPolicy Bypass -File ...` form shown above.

**Studio's Rojo plugin will not connect**
- Make sure `scripts\start.ps1` is running and shows no errors.
- Check that the plugin's address is `localhost` and port `34872`.
- Make sure the plugin version matches Rojo 7.7.1. Reinstall with
  `rojo plugin install` while Studio is closed.
- Allow Rojo through Windows Firewall if prompted.

**Port 34872 is already in use**
Another `rojo serve` is probably running. Close it, or run
`rojo serve --port 34873` and use that port in the plugin.

**Changes are not appearing in Studio**
Confirm the plugin shows *Connected*. Files outside `src/client`, `src/server`,
and `src/shared` are not synced.
