<#
.SYNOPSIS
    Runs the headless match simulation (sim/run.luau) and prints pacing statistics.

.DESCRIPTION
    Plays full matches between scripted bots using the real pure game modules. No Roblox Studio
    needed. Uses the Lune version pinned in rokit.toml.

.PARAMETER Matches
    Number of matches to simulate (default 200).

.PARAMETER Players
    Players per match (default 8).

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File scripts\simulate.ps1 -Matches 200
#>
[CmdletBinding()]
param(
    [int]$Matches = 200,
    [int]$Players = 8
)

$ErrorActionPreference = "Stop"

# Rokit resolves tools from the rokit.toml in the current directory.
$RepoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $RepoRoot

if (-not (Get-Command "lune" -ErrorAction SilentlyContinue)) {
    Write-Host "SIMULATION FAILED: Lune is not available. Run scripts\setup.ps1 first." -ForegroundColor Red
    exit 1
}

lune run sim/run.luau $Matches $Players
exit $LASTEXITCODE
