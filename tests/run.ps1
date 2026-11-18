<#
    run.ps1 - Run all Priestly unit tests, through WowTestKit's runner at the
    commit tests\kit.pin names (the kit's README).

    The tests are plain Lua 5.1 scripts that load the addon files against
    tests/wow_stubs.lua: Priestly's layer over LibGroupBuffs' shared stub,
    which runs on the kit. WoW uses Lua 5.1, so the tests do too - not the
    newer Lua that may be first on PATH.

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
        pwsh tests/run.ps1 -KitDev        # the ..\WowTestKit working copy instead of the pin
#>

param(
    [string]$Lua = "C:\Program Files (x86)\Lua\5.1\lua.exe",
    [string]$Library = "",
    [string]$LibGlass = "",
    [switch]$KitDev
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
# pins themselves, and CI tests exactly the pinned commits. The comparison is
# tests/pins.ps1, shared with Tools/deploy.ps1.
. (Join-Path $PSScriptRoot "pins.ps1")
function Show-Pin {
    param([string]$Name, [string]$Path, [string]$Root)
    $s = Get-PinState -Lua $Lua -RepoRoot $RepoRoot -Path $Path -Root $Root
    $pinText = if ($s.Pin) { $s.Pin } else { "NOTHING" }
    if ($s.AtPin) {
        Write-Host "${Name}: $Root @ $($s.Revision) (the .pkgmeta pin, $pinText)" -ForegroundColor DarkGray
    } else {
        Write-Host ("WARNING: ${Name} at $Root @ $($s.Revision) is not the .pkgmeta pin ($pinText)" +
            ", or has uncommitted changes; CI tests the pin") -ForegroundColor Yellow
    }
}
Show-Pin -Name "LibGlass" -Path "Libs/LibGlass-1.0" -Root $LibGlass
Show-Pin -Name "LibGroupBuffs" -Path "Libs/LibGroupBuffs-1.0" -Root $Library

# The kit at its pin (or -KitDev's working copy); sets $env:WOWTESTKIT, which
# tests/kit.lua reads.
. (Join-Path $PSScriptRoot "kit.ps1")
$kit = Get-WowTestKit -RepoRoot $RepoRoot -KitDev:$KitDev

# The kit's runner syntax-checks the TOC's Lua files and these extras, then
# runs every tests/test_*.lua from the repo root, one process each. A parse
# error in the library would otherwise show up as a confusing load failure
# inside every test. The library's files come from tests/libfiles.lua, the one
# reader of its XML that the harness, deploy.ps1 and CI use too, so a new file
# cannot be left unchecked. LibGlass is checked in its own repository, and
# loading it is the first thing every test does.
$libFiles = & $Lua (Join-Path $PSScriptRoot "libfiles.lua") $Library load $LibGlass
if ($LASTEXITCODE -ne 0) { Write-Host "LibGroupBuffs file list FAILED" -ForegroundColor Red; exit 1 }
$extra = @($libFiles | ForEach-Object { Join-Path $Library $_ })
& (Join-Path $kit "scripts\run.ps1") -RepoRoot $RepoRoot -Toc "Priestly.toc" -Extra $extra -Lua $Lua
exit $LASTEXITCODE
