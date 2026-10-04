<#
    run.ps1 - Run all Priestly unit tests.

    The tests are plain Lua 5.1 scripts (no dependencies) that load the addon
    files against tests/wow_stubs.lua. WoW uses Lua 5.1, so the tests do too -
    not the newer Lua that may be first on PATH.

    Priestly embeds two libraries, loaded before its own files: LibGlass-1.0
    (the glass material) and LibGroupBuffs-1.0 (the compat layer, engine and
    window, which draws with LibGlass). The tests read each from a checkout
    next to this repository - ../LibGlass and ../LibGroupBuffs - or from
    -LibGlass / $env:LIBGLASS and -Library. There is no vendored copy to fall
    back to: a stale one would let the suite pass against code that no longer
    ships.

    Usage:
        pwsh tests/run.ps1
        pwsh tests/run.ps1 -Lua "C:\path\to\lua5.1.exe"
        pwsh tests/run.ps1 -Library "D:\src\LibGroupBuffs" -LibGlass "D:\src\LibGlass"
#>

param(
    [string]$Lua = "C:\Program Files (x86)\Lua\5.1\lua.exe",
    [string]$Library = "",
    [string]$LibGlass = ""
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path $Lua)) {
    Write-Error "Lua 5.1 interpreter not found at: $Lua  (pass -Lua <path>)"
    exit 1
}

$RepoRoot = Split-Path -Parent $PSScriptRoot

if (-not $Library) { $Library = Join-Path (Split-Path -Parent $RepoRoot) "LibGroupBuffs" }
if (-not (Test-Path (Join-Path $Library "LibGroupBuffs-1.0.xml"))) {
    Write-Error ("LibGroupBuffs-1.0 not found at $Library. Clone " +
        "https://github.com/Spotnick2/LibGroupBuffs next to this repository, or pass -Library.")
    exit 1
}
$Library = (Resolve-Path $Library).Path
$env:LIBGROUPBUFFS = $Library

if (-not $LibGlass) {
    $LibGlass = if ($env:LIBGLASS) { $env:LIBGLASS } else { Join-Path (Split-Path -Parent $RepoRoot) "LibGlass" }
}
if (-not (Test-Path (Join-Path $LibGlass "LibGlass-1.0.xml"))) {
    Write-Error ("LibGlass-1.0 not found at $LibGlass. Clone " +
        "https://github.com/Spotnick2/LibGlass next to this repository, or set LIBGLASS / pass -LibGlass.")
    exit 1
}
$LibGlass = (Resolve-Path $LibGlass).Path
$env:LIBGLASS = $LibGlass

# Say which checkout the tests actually ran against, and whether it is the one
# a release would ship. A mismatch is normal while working on a library, so it
# is a warning, never a failure: tests/test_manifest.lua is what checks the
# pins themselves, and CI tests exactly the pinned commits. Each pin is read
# BY PATH (tests/pkgmeta.lua) - with two externals, the first `tag:` in the
# file is LibGlass's. No git, or a checkout that is not one (a downloaded
# zip), must not stop a run for a line that only prints.
function Show-Pin {
    param([string]$Name, [string]$Path, [string]$Root)
    Push-Location $RepoRoot
    try { $pin = & $Lua (Join-Path $PSScriptRoot "pkgmeta.lua") $Path 2>$null } finally { Pop-Location }
    $pinOk = ($LASTEXITCODE -eq 0 -and $pin)
    $global:LASTEXITCODE = 0
    $ref = if ($pinOk) { ($pin -split ' ', 2)[1] } else { $null }
    $revision, $atPin = "not a git checkout", $false
    try {
        $r = git -C $Root describe --tags --always --dirty 2>$null
        if ($LASTEXITCODE -eq 0 -and $r) {
            $revision = $r
            if ($ref) {
                $want = git -C $Root rev-parse --verify --quiet "$ref^{commit}" 2>$null
                $head = git -C $Root rev-parse HEAD 2>$null
                $dirty = git -C $Root status --porcelain 2>$null
                $atPin = ($want -and $want -eq $head -and -not $dirty)
            }
        }
    } catch { $revision = "git not available" }
    $global:LASTEXITCODE = 0
    $pinText = if ($pinOk) { $pin } else { "NOTHING" }
    if ($atPin) {
        Write-Host "${Name}: $Root @ $revision (the .pkgmeta pin, $pinText)" -ForegroundColor DarkGray
    } else {
        Write-Host ("WARNING: ${Name} at $Root @ $revision is not the .pkgmeta pin ($pinText)" +
            ", or has uncommitted changes; CI tests the pin") -ForegroundColor Yellow
    }
}
Show-Pin -Name "LibGlass" -Path "Libs/LibGlass-1.0" -Root $LibGlass
Show-Pin -Name "LibGroupBuffs" -Path "Libs/LibGroupBuffs-1.0" -Root $Library

# Run from the repo root so the tests can dofile('tests/...') and
# loadfile('Priestly.lua') with paths relative to the project.
Push-Location $RepoRoot
try {
    $failed = 0

    # Syntax-check Priestly's files and LibGroupBuffs': a parse error there
    # would show up as a confusing load failure inside every test. LibGlass is
    # checked in its own repository, and loading it is the first thing every
    # test does. Skipping this quietly was how the syntax check could look
    # green while never running: say so, loudly, rather than printing nothing.
    $luac = Join-Path (Split-Path -Parent $Lua) "luac.exe"
    if (-not (Test-Path $luac)) {
        Write-Host "luac -p SKIPPED: no luac.exe beside $Lua - syntax was NOT checked" -ForegroundColor Yellow
    }
    else {
        # Priestly's files come from the TOC and the library's from
        # tests/libfiles.lua, the one reader of its XML that the harness,
        # deploy.ps1 and CI use too. Neither list is written out here, so a new
        # file cannot be left unchecked.
        $tocFiles = Get-Content (Join-Path $RepoRoot "Priestly.toc") |
            ForEach-Object { $_.Trim() } |
            Where-Object { $_ -notmatch "^#" -and $_ -match "[.]lua$" }
        if (-not $tocFiles) { Write-Host "Priestly.toc lists no Lua files" -ForegroundColor Red; exit 1 }
        $libFiles = & $Lua (Join-Path $PSScriptRoot "libfiles.lua") $Library load $LibGlass
        if ($LASTEXITCODE -ne 0) { Write-Host "LibGroupBuffs file list FAILED" -ForegroundColor Red; exit 1 }
        $libFiles = $libFiles | ForEach-Object { Join-Path $Library $_ }
        & $luac -p @tocFiles @libFiles
        if ($LASTEXITCODE -ne 0) {
            Write-Host "luac -p FAILED" -ForegroundColor Red
            exit 1
        }
        Remove-Item -LiteralPath (Join-Path $RepoRoot "luac.out") -ErrorAction SilentlyContinue
        Write-Host "luac -p: ok ($($tocFiles.Count) addon + $($libFiles.Count) library files)" -ForegroundColor DarkGray
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
