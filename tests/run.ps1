<#
    run.ps1 - Run all Priestly unit tests.

    The tests are plain Lua 5.1 scripts (no dependencies) that load the addon
    files against tests/wow_stubs.lua. WoW uses Lua 5.1, so the tests do too -
    not the newer Lua that may be first on PATH.

    Usage:
        pwsh tests/run.ps1
        pwsh tests/run.ps1 -Lua "C:\path\to\lua5.1.exe"
#>

param(
    [string]$Lua = "C:\Program Files (x86)\Lua\5.1\lua.exe"
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path $Lua)) {
    Write-Error "Lua 5.1 interpreter not found at: $Lua  (pass -Lua <path>)"
    exit 1
}

# Run from the repo root so the tests can dofile('tests/...') and
# loadfile('Priestly.lua') with paths relative to the project.
$RepoRoot = Split-Path -Parent $PSScriptRoot
Push-Location $RepoRoot
try {
    $failed = 0

    # Syntax-check the shipping files first: a parse error there would show up
    # as a confusing load failure inside every test.
    $luac = Join-Path (Split-Path -Parent $Lua) "luac.exe"
    if (Test-Path $luac) {
        & $luac -p PriestlyCompat.lua PriestlyConfig.lua Priestly.lua
        if ($LASTEXITCODE -ne 0) {
            Write-Host "luac -p FAILED" -ForegroundColor Red
            exit 1
        }
        Remove-Item -LiteralPath (Join-Path $RepoRoot "luac.out") -ErrorAction SilentlyContinue
        Write-Host "luac -p: ok" -ForegroundColor DarkGray
    }

    Get-ChildItem (Join-Path $PSScriptRoot "test_*.lua") | Sort-Object Name | ForEach-Object {
        Write-Host "-- $($_.Name) " -NoNewline -ForegroundColor Cyan
        & $Lua $_.FullName
        if ($LASTEXITCODE -ne 0) { $failed++ }
    }

    if ($failed -gt 0) {
        Write-Host "$failed test file(s) FAILED" -ForegroundColor Red
        exit 1
    }
    Write-Host "All test files passed." -ForegroundColor Green
}
finally {
    Pop-Location
}
