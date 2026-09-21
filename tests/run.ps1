<#
    run.ps1 - Run all Priestly unit tests.

    The tests are plain Lua 5.1 scripts (no dependencies) that load the addon
    files against tests/wow_stubs.lua. WoW uses Lua 5.1, so the tests do too -
    not the newer Lua that may be first on PATH.

    Priestly loads LibGroupBuffs-1.0 first (the shared compat layer), so the
    tests need it too. They read it from a checkout next to this repository -
    ../LibGroupBuffs - or from -Library. There is no vendored copy to fall back
    to: a stale one would let the suite pass against code that no longer ships.

    Usage:
        pwsh tests/run.ps1
        pwsh tests/run.ps1 -Lua "C:\path\to\lua5.1.exe"
        pwsh tests/run.ps1 -Library "D:\src\LibGroupBuffs"
#>

param(
    [string]$Lua = "C:\Program Files (x86)\Lua\5.1\lua.exe",
    [string]$Library = ""
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path $Lua)) {
    Write-Error "Lua 5.1 interpreter not found at: $Lua  (pass -Lua <path>)"
    exit 1
}

$RepoRoot = Split-Path -Parent $PSScriptRoot

if (-not $Library) { $Library = Join-Path (Split-Path -Parent $RepoRoot) "LibGroupBuffs" }
$LibraryXml = Join-Path $Library "LibGroupBuffs-1.0.xml"
if (-not (Test-Path $LibraryXml)) {
    Write-Error ("LibGroupBuffs-1.0 not found at $Library. Clone " +
        "https://github.com/Spotnick2/LibGroupBuffs next to this repository, or pass -Library.")
    exit 1
}
$Library = (Resolve-Path $Library).Path
$env:LIBGROUPBUFFS = $Library

# Say which library the tests actually ran against, and which one a release
# would ship. A mismatch is normal while working on both; it is printed so it
# is never a surprise.
# Informational only: a missing pin must not stop the run, because
# tests/test_manifest.lua is what reports it, by name.
$pinMatch = Select-String -Path (Join-Path $RepoRoot ".pkgmeta") -Pattern '^\s*tag:\s*(\S+)' |
    Select-Object -First 1
$pinned = if ($pinMatch) { $pinMatch.Matches[0].Groups[1].Value } else { "NOTHING" }
# No git, or a library that is not a git checkout (a downloaded zip), must
# not stop a test run for a line that only prints.
$revision = try {
    $r = git -C $Library describe --tags --always --dirty 2>$null
    if ($LASTEXITCODE -eq 0 -and $r) { $r } else { "not a git checkout" }
} catch { "git not available" }
$global:LASTEXITCODE = 0
Write-Host "LibGroupBuffs: $Library @ $revision (release pins $pinned)" -ForegroundColor DarkGray

# Run from the repo root so the tests can dofile('tests/...') and
# loadfile('Priestly.lua') with paths relative to the project.
Push-Location $RepoRoot
try {
    $failed = 0

    # Syntax-check everything that ships, the library included: a parse error
    # there would show up as a confusing load failure inside every test.
    $luac = Join-Path (Split-Path -Parent $Lua) "luac.exe"
    if (Test-Path $luac) {
        # The library's files come from tests/libfiles.lua, the one reader of
        # its XML that the harness, deploy.ps1 and CI also use.
        $libFiles = & $Lua (Join-Path $PSScriptRoot "libfiles.lua") $Library load
        if ($LASTEXITCODE -ne 0) { Write-Host "LibGroupBuffs file list FAILED" -ForegroundColor Red; exit 1 }
        $libFiles = $libFiles | ForEach-Object { Join-Path $Library $_ }
        & $luac -p PriestlyCompat.lua PriestlyConfig.lua Priestly.lua @libFiles
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
