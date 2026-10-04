<#
    deploy.ps1 - Deploy Priestly (and optionally the throwaway API probe) into
    the WoW: Forever AddOns folder.

    The repo keeps `## Version: @project-version@` because the CurseForge/BigWigs
    packager substitutes it at release time. The client would display that literal
    string, so the deployed copy gets `## Version: dev` instead. The repo copy is
    never modified.

    Priestly embeds two libraries side by side, which a release gets from
    .pkgmeta externals:
      - LibGlass-1.0, the glass material. Deployed by the LibGlass checkout's
        own Tools\deploy.ps1 ($env:LIBGLASS or -LibGlass, else ..\LibGlass),
        which checks the checkout is complete and prints its commit. It runs
        FIRST: a refusal there leaves the deployed Priestly untouched.
      - LibGroupBuffs-1.0, copied from the checkout next to this repository
        (../LibGroupBuffs, or -Library) into Priestly\Libs\LibGroupBuffs-1.0,
        exactly the files its XML lists. Nothing is written until every one
        of them has been found, and every texture it draws is in LibGlass.
    A checkout that is not at its .pkgmeta pin is a warning, not a refusal:
    trying a library change in game before the pin moves is legitimate.

    Usage:
        pwsh Tools/deploy.ps1                # addon only
        pwsh Tools/deploy.ps1 -Probe         # addon + PriestlyProbe
        pwsh Tools/deploy.ps1 -ProbeOnly     # just PriestlyProbe
        pwsh Tools/deploy.ps1 -AddOnsPath "D:\...\_classic_beta_\Interface\AddOns"
        pwsh Tools/deploy.ps1 -Library "D:\src\LibGroupBuffs" -LibGlass "D:\src\LibGlass"
#>

param(
    [string]$AddOnsPath = "C:\Program Files (x86)\World of Warcraft\_classic_beta_\Interface\AddOns",
    [switch]$Probe,
    [switch]$ProbeOnly,
    [string]$Library = "",
    [string]$LibGlass = "",
    [string]$Lua = "C:\Program Files (x86)\Lua\5.1\lua.exe"
)

$ErrorActionPreference = "Stop"

# Repo root = parent of this script's folder.
$RepoRoot = Split-Path -Parent $PSScriptRoot

if (-not (Test-Path $AddOnsPath)) {
    Write-Error "AddOns path not found: $AddOnsPath"
    exit 1
}

# Every file the library needs in the addon folder - its XMLs and its Lua -
# from tests/libfiles.lua, the one reader of its XML that the test harness,
# run.ps1 and CI also use. It fails, naming the file, if anything listed is
# missing, so nothing is copied until the whole library has been found.
function Get-LibraryFiles {
    param([string]$Root, [string]$GlassRoot)
    if (-not (Test-Path $Lua)) {
        throw "Lua 5.1 not found at $Lua (pass -Lua <path>); deploy reads the library's file list with it."
    }
    $files = & $Lua (Join-Path $RepoRoot "tests\libfiles.lua") $Root ship $GlassRoot 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw ("$files. Clone https://github.com/Spotnick2/LibGroupBuffs next to this repository, " +
            "or pass -Library.")
    }
    return @($files)
}

function Copy-AddonFile {
    param([string]$Source, [string]$Destination)

    if ($Source -like "*.toc") {
        # Substitute the packager token so the client shows something sane.
        (Get-Content -LiteralPath $Source -Raw) `
            -replace '## Version: @project-version@', '## Version: dev' |
            Set-Content -LiteralPath $Destination -NoNewline
    } else {
        Copy-Item -LiteralPath $Source -Destination $Destination -Force
    }
}

# Warn when a checkout is not at the ref .pkgmeta pins for it, read by path
# (tests/pkgmeta.lua): with two externals, the first `tag:` in the file is
# LibGlass's.
function Test-Pin {
    param([string]$Name, [string]$Path, [string]$Root)
    Push-Location $RepoRoot
    try { $pin = & $Lua (Join-Path $RepoRoot "tests\pkgmeta.lua") $Path ref 2>$null } finally { Pop-Location }
    if ($LASTEXITCODE -ne 0 -or -not $pin) {
        $global:LASTEXITCODE = 0
        Write-Host "  (no $Name pin found in .pkgmeta)" -ForegroundColor Yellow
        return
    }
    try {
        $want = git -C $Root rev-parse --verify --quiet "$pin^{commit}" 2>$null
        $head = git -C $Root rev-parse HEAD 2>$null
        $dirty = git -C $Root status --porcelain 2>$null
        if (-not $want -or $want -ne $head -or $dirty) {
            Write-Host ("  WARNING: the $Name checkout at $Root is not at the .pkgmeta pin ($pin)" +
                "$(if ($dirty) { ', or has uncommitted changes' }); a release ships the pin") -ForegroundColor Yellow
        }
    } catch { }
    $global:LASTEXITCODE = 0
}

function Deploy-Priestly {
    $dest = Join-Path $AddOnsPath "Priestly"

    # Preflight: find the whole library before touching the AddOns folder, so a
    # missing checkout cannot leave half a deploy behind.
    $glassRoot = $LibGlass
    if (-not $glassRoot) { $glassRoot = $env:LIBGLASS }
    if (-not $glassRoot) { $glassRoot = Join-Path (Split-Path -Parent $RepoRoot) "LibGlass" }
    if (-not (Test-Path -LiteralPath (Join-Path $glassRoot "Tools\deploy.ps1"))) {
        throw ("LibGlass checkout not found at $glassRoot. Clone https://github.com/Spotnick2/LibGlass " +
            "next to this repository, or set `$env:LIBGLASS / pass -LibGlass.")
    }
    $glassRoot = (Resolve-Path $glassRoot).Path
    $libRoot = $Library
    if (-not $libRoot) { $libRoot = Join-Path (Split-Path -Parent $RepoRoot) "LibGroupBuffs" }
    $libFiles = Get-LibraryFiles -Root $libRoot -GlassRoot $glassRoot
    $libRoot = (Resolve-Path $libRoot).Path
    Test-Pin -Name "LibGlass" -Path "Libs/LibGlass-1.0" -Root $glassRoot
    Test-Pin -Name "LibGroupBuffs" -Path "Libs/LibGroupBuffs-1.0" -Root $libRoot

    # LibGlass first, by its own deploy: a refusal there must leave the
    # deployed Priestly untouched.
    & pwsh -NoProfile -File (Join-Path $glassRoot "Tools\deploy.ps1") -Addon Priestly -AddOnsPath $AddOnsPath -Lua $Lua
    if ($LASTEXITCODE -ne 0) { throw "LibGlass deploy refused; Priestly was not touched" }
    # Informational: no git, or a library that is not a checkout, must not
    # stop a deploy.
    $revision = try {
        $r = git -C $libRoot describe --tags --always --dirty 2>$null
        if ($LASTEXITCODE -eq 0 -and $r) { $r } else { "not a git checkout" }
    } catch { "git not available" }

    Write-Host "Deploying Priestly -> $dest" -ForegroundColor Cyan
    if (-not (Test-Path $dest)) { New-Item -ItemType Directory -Path $dest | Out-Null }

    $files = @("Priestly.toc") + (Get-ChildItem -LiteralPath $RepoRoot -Filter "*.lua" |
        Select-Object -ExpandProperty Name)
    foreach ($f in $files) {
        $src = Join-Path $RepoRoot $f
        if (-not (Test-Path $src)) { continue }
        Copy-AddonFile -Source $src -Destination (Join-Path $dest $f)
        Write-Host "  $f"
    }

    # Purge files that no longer exist in the repo (e.g. a removed Lua file that
    # the TOC no longer lists but the client would still find).
    Get-ChildItem -LiteralPath $dest -File | Where-Object { $files -notcontains $_.Name } |
        ForEach-Object {
            Write-Host "  removing stale $($_.Name)" -ForegroundColor DarkYellow
            Remove-Item -LiteralPath $_.FullName -Force
        }

    # The embedded library. The subtree is ours, so it is replaced whole: a file
    # the library no longer ships must not linger where the client can load it.
    $libDest = Join-Path $dest "Libs\LibGroupBuffs-1.0"
    if (Test-Path $libDest) { Remove-Item -LiteralPath $libDest -Recurse -Force }
    foreach ($f in $libFiles) {
        $target = Join-Path $libDest $f
        $dir = Split-Path -Parent $target
        if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        Copy-Item -LiteralPath (Join-Path $libRoot $f) -Destination $target -Force
    }
    Write-Host "  Libs\LibGroupBuffs-1.0  ($($libFiles.Count) files from $libRoot @ $revision)"
}

function Deploy-Probe {
    $src = Join-Path $RepoRoot "Tools\PriestlyProbe"
    if (-not (Test-Path $src)) {
        Write-Host "No Tools\PriestlyProbe - skipping" -ForegroundColor DarkYellow
        return
    }
    $dest = Join-Path $AddOnsPath "PriestlyProbe"
    Write-Host "Deploying PriestlyProbe -> $dest" -ForegroundColor Cyan
    if (-not (Test-Path $dest)) { New-Item -ItemType Directory -Path $dest | Out-Null }
    Get-ChildItem -LiteralPath $src -File | ForEach-Object {
        Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $dest $_.Name) -Force
        Write-Host "  $($_.Name)"
    }
}

if (-not $ProbeOnly) { Deploy-Priestly }
if ($Probe -or $ProbeOnly) { Deploy-Probe }

Write-Host ""
Write-Host "Done. In game:  /console scriptErrors 1  then  /reload" -ForegroundColor Green
Write-Host "Check the AddOn list: enabled AND not flagged out of date." -ForegroundColor Green
