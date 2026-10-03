<#
.SYNOPSIS
    Bootstraps the repository-managed development tools for robloxgame.

.DESCRIPTION
    Run this once after cloning (and again whenever rokit.toml changes).

    What it does:
      1. Checks that the external prerequisites (Git, Rokit) are installed.
      2. Reads the tool list from rokit.toml and asks you to confirm trusting them.
      3. Runs `rokit install` to download the exact pinned tool versions.
      4. Verifies each tool runs and reports the version pinned in rokit.toml.

    What it does NOT do:
      - Install Git, Rokit, VS Code, or Roblox Studio for you.
      - Change anything outside this repository except Rokit's own tool cache
        and trust list in your user profile.

.PARAMETER Yes
    Skip the confirmation prompt before trusting the tools listed in rokit.toml.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File scripts\setup.ps1
#>
[CmdletBinding()]
param(
    [switch]$Yes
)

$ErrorActionPreference = "Stop"

function Write-Step([string]$Message) {
    Write-Host ""
    Write-Host "==> $Message" -ForegroundColor Cyan
}

function Fail([string]$Message) {
    Write-Host ""
    Write-Host "SETUP FAILED: $Message" -ForegroundColor Red
    exit 1
}

function Test-Command([string]$Name) {
    return [bool](Get-Command $Name -ErrorAction SilentlyContinue)
}

# Rokit resolves tools from the rokit.toml in the current directory,
# so everything runs from the repository root.
$RepoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $RepoRoot

$ManifestPath = Join-Path $RepoRoot "rokit.toml"
if (-not (Test-Path $ManifestPath)) {
    Fail "rokit.toml not found at $ManifestPath. Run this script from a clone of the repository."
}

# --- 1. External prerequisites -------------------------------------------------

Write-Step "Checking external prerequisites"

if (-not (Test-Command "git")) {
    Fail "Git is not installed or not on PATH. Install it from https://git-scm.com/download/win and open a new terminal."
}
Write-Host "  git:   $(git --version)"

if (-not (Test-Command "rokit")) {
    Fail ("Rokit is not installed or not on PATH.`n" +
        "  Install it from https://github.com/rojo-rbx/rokit#installation, then open a new terminal and re-run this script.")
}
Write-Host "  rokit: $(rokit --version)"

# --- 2. Read tools from rokit.toml ---------------------------------------------

Write-Step "Reading tools from rokit.toml"

# Matches lines like:  rojo = "rojo-rbx/rojo@7.7.1"
$Tools = @()
foreach ($Line in Get-Content $ManifestPath) {
    if ($Line -match '^\s*([A-Za-z0-9_-]+)\s*=\s*"([^"@]+)@([^"]+)"') {
        $Tools += [pscustomobject]@{
            Alias   = $Matches[1]
            Source  = $Matches[2]
            Version = $Matches[3]
        }
    }
}

if ($Tools.Count -eq 0) {
    Fail "No tools found in rokit.toml."
}

foreach ($Tool in $Tools) {
    Write-Host ("  {0,-8} {1}@{2}" -f $Tool.Alias, $Tool.Source, $Tool.Version)
}

# --- 3. Trust and install ------------------------------------------------------

Write-Step "Trusting tools"

Write-Host "Rokit only runs tools you have marked as trusted."
Write-Host "The tools above will be downloaded from their GitHub releases."
if (-not $Yes) {
    $Answer = Read-Host "Trust these tools and continue? [y/N]"
    if ($Answer -notmatch '^(y|yes)$') {
        Fail "Cancelled by user. Nothing was installed."
    }
}

foreach ($Tool in $Tools) {
    rokit trust $Tool.Source
    if ($LASTEXITCODE -ne 0) {
        Fail "rokit trust $($Tool.Source) failed."
    }
}

Write-Step "Installing tools with rokit install"

rokit install
if ($LASTEXITCODE -ne 0) {
    Fail ("rokit install failed. If you see GitHub rate-limit errors, run`n" +
        "  rokit authenticate github`nand try again.")
}

# --- 4. Verify -----------------------------------------------------------------

Write-Step "Verifying tools"

$Problems = 0
foreach ($Tool in $Tools) {
    try {
        $Output = (& $Tool.Alias --version 2>&1 | Out-String).Trim()
        $Ran = ($LASTEXITCODE -eq 0)
    } catch {
        $Output = $_.Exception.Message
        $Ran = $false
    }
    if (-not $Ran) {
        Write-Host "  [FAIL] $($Tool.Alias): $Output" -ForegroundColor Red
        $Problems++
    } elseif ($Output -notmatch [regex]::Escape($Tool.Version)) {
        Write-Host "  [FAIL] $($Tool.Alias): expected $($Tool.Version), got '$Output'" -ForegroundColor Red
        $Problems++
    } else {
        Write-Host "  [ OK ] $Output" -ForegroundColor Green
    }
}

if ($Problems -gt 0) {
    Fail "$Problems tool(s) did not verify. Try opening a new terminal, or run: rokit install --force"
}

Write-Host ""
Write-Host "Setup complete." -ForegroundColor Green
Write-Host "Next steps:"
Write-Host "  1. Install the Rojo plugin in Roblox Studio (see README.md)."
Write-Host "  2. Start a dev session:  powershell -ExecutionPolicy Bypass -File scripts\start.ps1"
