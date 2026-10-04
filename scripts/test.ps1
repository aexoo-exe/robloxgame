<#
.SYNOPSIS
    Runs the Lune tests for the pure Luau modules (board logic and combat simulation).

.DESCRIPTION
    Uses the Lune version pinned in rokit.toml. Run scripts\setup.ps1 first if Lune is missing.
    Exits with a non-zero code if any test fails.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File scripts\test.ps1
#>
[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

# Rokit resolves tools from the rokit.toml in the current directory.
$RepoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $RepoRoot

if (-not (Get-Command "lune" -ErrorAction SilentlyContinue)) {
    Write-Host "TEST FAILED: Lune is not available. Run scripts\setup.ps1 first." -ForegroundColor Red
    exit 1
}

lune run tests/run.luau
exit $LASTEXITCODE
