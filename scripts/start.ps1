<#
.SYNOPSIS
    Starts a local robloxgame development session.

.DESCRIPTION
    Checks that the Rokit-managed tools are available, then starts the Rojo
    development server for default.project.json. Leave this window open, then
    click "Connect" in the Rojo plugin inside Roblox Studio.

    Press Ctrl+C to stop the server.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File scripts\start.ps1
#>
[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

function Fail([string]$Message) {
    Write-Host ""
    Write-Host "START FAILED: $Message" -ForegroundColor Red
    exit 1
}

# Rokit resolves tools from the rokit.toml in the current directory.
$RepoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $RepoRoot

if (-not (Get-Command "rokit" -ErrorAction SilentlyContinue)) {
    Fail "Rokit is not installed or not on PATH. See README.md, then run scripts\setup.ps1."
}

try {
    $RojoVersion = (& rojo --version 2>&1 | Out-String).Trim()
    $RojoOk = ($LASTEXITCODE -eq 0)
} catch {
    $RojoVersion = $_.Exception.Message
    $RojoOk = $false
}
if (-not $RojoOk) {
    Fail "Rojo is not available through Rokit ($RojoVersion). Run scripts\setup.ps1 first."
}

Write-Host "Using $RojoVersion" -ForegroundColor Cyan
Write-Host "Starting Rojo server for default.project.json (Ctrl+C to stop)..."
Write-Host "In Roblox Studio: Plugins > Rojo > Connect"
Write-Host ""

rojo serve default.project.json
exit $LASTEXITCODE
