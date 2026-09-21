# Priestly Agent Instructions

Trust these instructions. Search the codebase only when information here is incomplete, stale, or
appears incorrect.

## Review preferences

- When asked to review a pull request, review its committed changes and post actionable findings on
  that PR. If there are no actionable findings, post a review summary with validation performed and
  any material limitations. Link the posted review in the final response.
- End every pull-request review and follow-up review with an explicit merge-readiness verdict:
  `Ready for merge` or `Not ready for merge`, followed by the reason and any remaining required
  work. State the same verdict clearly in the final response to the user.
- Before starting a substantive code review, assess its scope and recommend an appropriate model
  and reasoning effort. Use a GPT-5.6 model as the floor for substantive reviews; normally recommend
  `gpt-5.6-sol`, reserving stronger models for exceptional cases. Keep making recommendations on
  future reviews; the user handles session model switches. Ask when an escalation or de-escalation
  is warranted, and honor explicit approval to use the current model for that review without asking
  again. Do not silently switch models or effort. Follow the user's cost policy.
- Preserve unrelated local edits during reviews.

## What This Repository Is

Priestly Forever is a World of Warcraft addon for **WoW: Forever 1.60.1** (Interface `16001`). It
provides PallyPower-style Priest buff management for Power Word: Fortitude, Divine Spirit / Prayer
of Spirit, and Shadow Protection across party and raid members.

**TBC Classic Anniversary is no longer supported.** v1.0.6 was the final TBC release; it stays
downloadable on CurseForge for Anniversary players, and the code is archived on the
`tbc-anniversary` branch / `v1.0.6` tag. Do not add flavor branching for it.

Forever is *Vanilla content running on Blizzard's Retail (Mainline) codebase*: content assumptions
are Vanilla, API assumptions are Retail. The field notes for this client are
`C:\Projects\References\PORTING-TBC-TO-FOREVER.md` — read them before touching an unfamiliar API.

There is no build system, compiler or package manager. The BigWigs packager handles releases.

## Repository Layout

- `Priestly.toc` — addon manifest. Interface version, saved variables, load order.
- `PriestlyCompat.lua` — **loads first.** All removed/moved APIs live here as `Priestly.API`.
- `PriestlyConfig.lua` — options panel, defaults, instance database, exported config helpers.
- `Priestly.lua` — main UI, buff logic, secure buttons, event handling, slash commands.
- `tests/` — Lua 5.1 unit tests, no game client. See `tests/README.md`.
- `Tools/deploy.ps1` — deploy to the local Forever AddOns folder.
- `Tools/PriestlyProbe/` — throwaway in-game API probe. Delete once `docs/FOREVER-PROBE.md` is
  settled.
- `.github/workflows/` — release (on `v*` tag) and package-check (dry run on PR).
- `.pkgmeta`, `README.md`, `CHANGELOG.md`, `LICENSE` — packaging and user-facing material.

No embedded libraries, no external dependencies.

## Architecture

Load order from `Priestly.toc`:

1. `PriestlyCompat.lua` — defines `Priestly.API`. Nothing else may touch a moved API directly.
2. `PriestlyConfig.lua` — `PriestlyDB` defaults, instance database, `Priestly_*` helper globals.
3. `Priestly.lua` — UI and event logic; calls the config helpers.

`Priestly.API` (the only sanctioned route to a changed API):

| Contract | Replaces |
|---|---|
| `ReadBuff(unit, names)` → `"HAS"\|"NONE"\|"BLOCKED"`, remaining, duration, expirationTime, matchedName | `UnitBuff` walk |
| `AurasAreSecret()` | — (`C_Secrets.ShouldAurasBeSecret`) |
| `SpellInfo` / `SpellName(id)` / `SpellIcon(spell, fallback)` | `GetSpellInfo` tuple |
| `SpellRange(unit, spell)` → `"IN_RANGE"\|"OUT_RANGE"\|"OFFLINE"\|"UNKNOWN"` | `IsSpellInRange` 1/0/nil |
| `KnowsSpell(idOrName)` / `GetSpellRank(name)` | the spell-tab walk |
| `ItemIcon(itemID)` | `GetItemIcon` |
| `UnitKey(unit)` / `UnitDisplayName(unit, fallback)` | `UnitGUID` / `UnitName` |
| `RegisterEvents(frame, ...)` | bare `RegisterEvent` (throws on unknown names here) |
| `ClientBuild()` | `select(2, GetBuildInfo())` |
| `CountItem(itemID)` — whole carried inventory, reagent bag included | `GetItemCount` / the `GetContainerNumSlots` walk |
| `AddonVersion(addonName)` | `GetAddOnMetadata` |
| `IsMouseOver(frame)` | `MouseIsOver` (absent on this client) |

`PriestlyConfig.lua` exposes: `Priestly_EnsureDefaults`, `Priestly_ShowSolo`, `Priestly_TrackPets`,
`Priestly_IsBuffEnabled`, `Priestly_ShouldShowShadow`, `Priestly_GetFrameAlpha`,
`Priestly_OpenConfig`, `Priestly_LearnDuration`, `Priestly_GetLearnedDuration`.

`Priestly.lua` exposes: `Priestly_ScheduleRefresh`, `Priestly_ForceRebuild`,
`Priestly_OnSoloToggle`, `Priestly_ApplyAlpha`, and `Priestly.shadowAuraNames` (localized Shadow
Protection aura names, which the config's "detect" mode reads).

**`PriestlyDB` is `SavedVariablesPerCharacter`, not account-wide.** Measured on build
1.60.1.69913 by two independent probes: this client writes account-wide SavedVariables but never
reads them back, so every session starts from defaults. Per-character storage does load. Do not
"fix" the TOC back — `tests/test_manifest.lua` asserts it, because the failure is invisible (the file
on disk looks perfectly correct) and the cost is every setting silently resetting. The trade is that
settings are no longer shared between characters.

This is a workaround for a client bug, tracked in **issue #9** for revisiting once the client loads
account-wide variables. Moving back is not just reverting the TOC line: by then people will have
configured characters, and seeding the account-wide table from them is what stops every setting
resetting a second time. Keep `Tools/PriestlyProbe` until #9 closes — `/pprobe sv` is how the client
gets re-tested.

Always call `Priestly_EnsureDefaults()` before assuming saved variable keys exist. Current keys:
`trackFort`, `trackSpirit`, `shadowMode`, `showSolo`, `trackPets`, `frameAlpha`, `shadowInstances`,
`learnedDurations`, `flavor`, `visible`, `pos`. `learnedDurations` is keyed by **spell name**,
not by buff id: the single and group forms of one buff share an id and do not share a duration.

## WoW API And Lua Rules

- Target the **Retail/Mainline** API. `WOW_PROJECT_ID == WOW_PROJECT_MAINLINE` here.
- Keep `## Interface: 16001` in `Priestly.toc` as the source of compatibility. The format is
  `%d%02d%02d`, so 1.60.1 → 16001. `11601` is a transposed-digit bug you will see in the wild.
- Never add a moved API call outside `PriestlyCompat.lua` — take a file-local alias instead.
- Watch the false friends: `C_Item.GetItemIconByID`, **not** `C_Item.GetItemIcon` (that takes an
  ItemLocation); reputation is `C_Reputation`, not `C_CreatureInfo.GetFactionInfo`.
- **`C_Spell.GetSpellInfo(name)` only resolves spells the player KNOWS.** By ID it always works.
  Resolve names *from* IDs, never the reverse, or every unlearned buff silently gets a nil name.
- **`UnitName(unit)` is a trap.** On the player it returns the full two-part name with the realm
  second; on any other unit it returns only the **first name**, with the surname where the realm
  normally sits. Use `API.UnitDisplayName` (`GetUnitName(unit, false)`).
- **`GetInstanceInfo()` returns the continent outdoors**, not an empty string — gate on
  `instanceType ~= "none"`.
- Measured behaviour for all of this is in `docs/FOREVER-PROBE.md`; re-probe with
  `Tools/PriestlyProbe` rather than assuming.
- `RegisterEvent` **throws** on an unknown event name. Go through `API.RegisterEvents`.
- `ReloadUI()` is protected — use the `/reload` slash command.
- Errors are off by default (`/console scriptErrors 1`) and stop being delivered after 100 in a
  session.
- Lua 5.1. `0` is truthy — `x or default` does not guard a numeric that can be 0.

## Content Rules (Vanilla, mid-beta)

- **Level cap is 60**, and the live beta is capped far lower (20, then 30). Never hardcode a cap.
- **The group "Prayer of X" spells may not exist.** Every buff row must work single-target-only;
  `ClickSpells(def)` falls back so the primary click is never dead.
- **Buff durations differ from both TBC and Vanilla and are still moving.** `DEFS[].duration` is a
  seed; the real value is learned from live auras and stored per client build. Do not hardcode.
- **Characters have a surname** ("Karuzo Elegia"), and first names are not unique. Display the full
  name; key every cache on `UnitGUID` via `API.UnitKey`. Never split a name to strip a realm.
- **Auras are unreadable in combat, for every unit** — not just the player. Measured: index reads
  *throw* ("Auras cannot be accessed when secret while tainted by '<addon>'"), while
  `GetAuraDataBySpellName` quietly returns nil, which looks exactly like "not buffed". Never read an
  aura outside `API.ReadBuff`, which guards everything and returns `BLOCKED` as distinct from
  `NONE`. `BuffRem` then falls back to the GUID-keyed cache, or reports `UNKNOWN` rather than a
  confident `MISS`.
- **A secret value throws when it is COMPARED or TRUTH-TESTED, not only when it is read.**
  `if updateInfo.isFullUpdate then` raises *"attempt to perform boolean test on field 'isFullUpdate'
  (a secret boolean value)"*; so does `nm == name` on a secret string and `if aura then` on a secret
  table. Guarding the field read and testing the result one line later is **not** enough — that shape
  shipped once and errored on the first pull. Every touch of data that came from the client in
  combat belongs *inside* the same `pcall`.
- **The `UNIT_AURA` payload is secret data too**, not just the auras it describes: `isFullUpdate`
  arrives as a secret boolean and `updatedAuraInstanceIDs` as a secret table.
- `GetInstanceInfo()` names in `INSTANCE_DB` are unverified until those zones are reachable.

## Secure UI Rules

Combat lockdown matters. Any code that changes secure frame attributes, shows or hides a frame that
parents secure buttons, or rebuilds secure UI must guard with `InCombatLockdown()` and defer.

Both `g_Main` and `g_Pop` parent secure buttons, so both use `CombatPark()` (move offscreen at
alpha 0) instead of `Hide()` during combat, and are properly hidden again on
`PLAYER_REGEN_ENABLED`. Unparking clears `g_Moved` so the saved position is re-applied.

**Known limitation, do not try to "fix" it.** Row click targets are unit tokens, wired during
`UpdateUI`. If the roster changes during combat, `party2`/`raid3` can be handed to a different
player while the attribute still names that token, so a click can land on the wrong person. There is
no way out: attributes cannot be rewritten under lockdown, and an insecure `PreClick` cannot cancel
a secure action. Parking the affected rows would need the same forbidden writes. It corrects itself
on `PLAYER_REGEN_ENABLED`.

Secure *snippets* are broken on this client (`loadstring_untainted` is missing, so
`SecureHandlerWrapScript`, `_onstate-*` and state drivers throw). Priestly uses none of them — plain
`SecureActionButtonTemplate` + `SetAttribute` + insecure `PreClick`/`PostClick`. Do not introduce a
`SecureHandler*`.

## Common Change Patterns

Adding a buff:

1. Add a `DEFS` entry in `Priestly.lua` with `id`, `grpID`, `snglID`, enUS `grp`/`sngl` fallback
   names, `fallbackIcon`, a `duration` seed, and `visibility` if it is conditionally shown.
2. Add a config toggle default in `PriestlyConfig.lua` and extend `Priestly_IsBuffEnabled(id)`.
3. Add a case to `tests/test_availability.lua`.

Adding a config option:

1. Add the default to `DEFAULTS`.
2. Add the widget in the relevant tab (use `MakeCheckButton` / `SafeFrame`, never a raw
   `CreateFrame` with a template that might not exist).
3. Expose a `Priestly_*` helper if `Priestly.lua` needs it.
4. Trigger the right refresh: `Priestly_ScheduleRefresh` for data, `Priestly_ForceRebuild` for
   layout.

Changing patch compatibility:

- Update only `## Interface:` in `Priestly.toc` unless Lua API changes are required.
- Keep `@project-version@`; the packager replaces it. `Tools/deploy.ps1` rewrites it to `dev` in the
  deployed copy only — never in the repo copy.

## Workflow

Work is tracked on GitHub and lands through pull requests, so that reviews — including automated
ones — have something to attach to.

1. **Open an issue first** describing the change, with enough context to review against.
2. **Branch** off `main` (`gh issue develop`, or a plain `git switch -c`). Never commit to `main`
   directly.
3. **Open a PR** referencing the issue (`Closes #N`). The `package-check` workflow runs the syntax
   check, the unit tests and a dry-run package build on every PR.
4. **Review before merge.** For an architecture or risk review, run
   `codex exec --profile high-review --sandbox read-only` with a prompt describing the change.
   Treat its findings as input, verify each claim against the code, and say which ones you acted on
   and which you rejected.
5. Squash-merge, then delete the branch.

## Validation

Offline, on every change:

```powershell
pwsh tests\run.ps1        # luac -p + all unit tests
```

`tests/wow_stubs.lua` fails the run on the read of **any global it does not stub**. That is
deliberate: the stub is the list of APIs verified present on this client, so it has to model the
client's *absences* too. Defining something there that Forever does not actually have is how a call
to `MouseIsOver` — removed on this client — survived into a build and surfaced only as a Lua error
on mouseover in game. Confirm a new global with `Tools/PriestlyProbe` before stubbing it.

`tests/test_frames.lua` exists to *execute* every script handler and event the addon installs,
rather than to assert behaviour: strict globals only catch what actually runs. A new handler belongs
in that file the day it is written.

In game:

```powershell
pwsh Tools\deploy.ps1
```
```
/console scriptErrors 1
/reload
```

- AddOn list: enabled **and not flagged out of date** (this client does not hard-block a wrong
  interface number, so "it loaded" proves nothing).
- `/priestly help | config | show | hide | reset`; drag the frame, `/reload`, confirm the position.
- Rows appear for whatever the priest actually knows; no Prayer wiring when no Prayer is known.
- Left-click and right-click both cast, out of combat and in combat, on a live party member.
- Enter combat: timers keep counting from the cache instead of flipping red; a member with no
  cached state shows `?`, not `MISS`.
- Roster churn: invite/leave, reshuffle subgroups, summon/dismiss a pet — buff state must follow the
  *player*, not the unit slot.
- A grouped player with a surname renders in full.
- Options panel: every checkbox, the three shadow radios, the opacity slider, and Select All /
  Deselect All / Reset Defaults.
- Log in with a pre-existing TBC `PriestlyDB`: settings survive, TBC instance keys are gone.

## Packaging

`.pkgmeta` packages the addon as `Priestly`, uses `CHANGELOG.md` as the manual changelog, and
excludes `.github`, `docs`, `screenshots`, `tests`, `Tools`, `README.md`, `CHANGELOG.md`, `LICENSE`.

Releases run `BigWigsMods/packager` from `.github/workflows/release.yml` on a `v*` tag, pinned to
commit `e50a250f8705` (Forever support landed in `7391c8de`). CurseForge project `1489106`, flavor
`forever` (alias `camelot`), `gameVersionTypeID` 88568. The release type comes from the **tag
name**: `alpha` → Alpha, `beta` → Beta, anything else → Release. Pull requests run the same packager
with `-d` (no uploads) and publish the zip as a CI artifact.

Requires a `CF_API_KEY` repo secret.
