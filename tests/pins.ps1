<#
    pins.ps1 - Is a library checkout at the ref .pkgmeta pins for it?

    Dot-sourced by tests/run.ps1 and Tools/deploy.ps1, which used to carry a
    copy each. The pin is read BY PATH through tests/pkgmeta.lua, the one
    reader of .pkgmeta's externals: with two externals, the first `tag:` in
    the file is LibGlass's.

        . (Join-Path $RepoRoot "tests\pins.ps1")
        $s = Get-PinState -Lua $Lua -RepoRoot $RepoRoot -Path "Libs/LibGlass-1.0" -Root $LibGlass
        # $s.Pin       "<kind> <ref>", or $null when .pkgmeta pins nothing there
        # $s.Ref       the ref alone
        # $s.Revision  `git describe` of the checkout, or why there is none
        # $s.AtPin     HEAD is the pinned commit and nothing is uncommitted
        # $s.Dirty     there are uncommitted changes

    Informational only. It never throws and leaves $LASTEXITCODE at 0: no git,
    or a checkout that is not one (a downloaded zip), must not stop a test run
    or a deploy for a line that only prints.
#>

function Get-PinState {
    param(
        [Parameter(Mandatory)][string]$Lua,
        [Parameter(Mandatory)][string]$RepoRoot,
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Root
    )
    $state = [pscustomobject]@{ Pin = $null; Ref = $null; Revision = "not a git checkout"; AtPin = $false; Dirty = $false }

    Push-Location $RepoRoot
    try {
        $pin = & $Lua (Join-Path $RepoRoot "tests\pkgmeta.lua") $Path 2>$null
        if ($LASTEXITCODE -eq 0 -and $pin) {
            $state.Pin = "$pin"
            $state.Ref = ("$pin" -split ' ', 2)[1]
        }
    } catch { } finally { Pop-Location }

    try {
        $r = git -C $Root describe --tags --always --dirty 2>$null
        if ($LASTEXITCODE -eq 0 -and $r) {
            $state.Revision = "$r"
            $state.Dirty = [bool](git -C $Root status --porcelain 2>$null)
            if ($state.Ref) {
                $want = git -C $Root rev-parse --verify --quiet "$($state.Ref)^{commit}" 2>$null
                $head = git -C $Root rev-parse HEAD 2>$null
                $state.AtPin = [bool]($want -and $want -eq $head -and -not $state.Dirty)
            }
        }
    } catch { $state.Revision = "git not available" }

    $global:LASTEXITCODE = 0
    return $state
}
