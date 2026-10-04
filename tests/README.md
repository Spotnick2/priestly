# Priestly tests

Automated unit tests that run under **Lua 5.1** (the interpreter WoW uses) with
no game client. Plain scripts, no external dependencies.

## Running

All tests:

```powershell
pwsh tests/run.ps1
```

A single test (from the repo root, so the relative `loadfile`/`dofile` paths
resolve):

```powershell
& 'C:\Program Files (x86)\Lua\5.1\lua.exe' tests\test_clicks.lua
```

> Use the Lua **5.1** interpreter, not a newer Lua that may be first on `PATH`.
> `run.ps1` defaults to `C:\Program Files (x86)\Lua\5.1\lua.exe`; override with
> `-Lua <path>`. It also runs `luac -p` over the shipping files first.

**The tests need LibGroupBuffs-1.0 and LibGlass-1.0 checked out next to this
repository** (`../LibGroupBuffs`, `../LibGlass`), because Priestly loads both
before its own files: LibGlass first, then LibGroupBuffs, which draws with it.
`run.ps1` takes `-Library <path>` and `-LibGlass <path>` instead, and prints
which checkout and revision it used, warning when one is not at its `.pkgmeta`
pin. A single test run by hand reads the `LIBGROUPBUFFS` and `LIBGLASS`
environment variables, or the sibling checkouts. There is no vendored copy to
fall back to, on purpose; a missing checkout fails loudly.

To test exactly what a release ships, clone each library at its pin:
`bash tests/fetch_external.sh Libs/LibGlass-1.0 <dir>` (and
`Libs/LibGroupBuffs-1.0`), then point the variables at those clones. CI does
exactly that.

## How it works

- **`wow_stubs.lua`** — Priestly's thin layer over the **shared** stub in
  `../LibGroupBuffs/tests/wow_stubs.lua`. The client surface itself lives
  there, so every absence and refusal measured on this client is measured
  once, for Priestly, Wildly and Magely. What stays local is Priestly's alone:
  a priest as the default unit, the globals this addon owns, the Encounter
  Journal functions only its probe calls, and the journal's defaults re-applied
  on every `WoW.reset()`. **Add a new global here; look for an API's stub in
  the library.**
- **The shared stub** — a minimal WoW: Forever API mock: chainable
  `CreateFrame` whose frames *record their secure attributes*, a `C_Timer` that
  collects callbacks instead of waiting, `C_UnitAuras` backed by an injectable
  per-unit aura table with a secrecy switch, `C_Spell` / `C_SpellBook` backed
  by an injectable known-spell set, and units that carry a GUID and a Forever
  surname. Drive it through the exported `WoW` table:
  `WoW.reset()`, `WoW.SetUnit`, `WoW.SetAura`, `WoW.Know`, `WoW.DefineSpell`,
  `WoW.fire`. `dofile("tests/wow_stubs.lua")` **first** in every test.
- **`harness.lua`** — `check`/`eq`/`near`, `loadAddon()` (loads LibGlass and
  then LibGroupBuffs, each through its own XML, then Priestly's files in TOC
  order, passing each `("Priestly", ns)` as the client does, failing on anything
  missing, and hands back the test seams) and `TeachSpells{...}` for the common
  "this priest knows X" setup.
- **`libfiles.lua`** — the one reader of the libraries' XML (the harness,
  `run.ps1`, `deploy.ps1` and CI use it), and the check that every texture
  LibGroupBuffs draws is in LibGlass's `Media/`.
- **`pkgmeta.lua`** — the one reader of `.pkgmeta`'s externals, by path.
  **`fetch_external.sh`** clones one at its pin and proves the checkout is it;
  **`pins.ps1`** (dot-sourced by `run.ps1` and `Tools/deploy.ps1`) says whether
  a local checkout is at its pin.
- Internals that are file-local are reached through a **test seam**:
  `Priestly._test` at the end of `Priestly.lua` and `Priestly._testConfig` at
  the end of `PriestlyConfig.lua`. Both are harmless in game.
- A file prints `name: N tests passed` and exits non-zero on failure.

## Test files

| File | What it pins down |
|---|---|
| `test_bridge.lua` | Priestly on top of LibGroupBuffs-1.0: `Priestly.GB` is the instance `lib:New` made, `Priestly.API` the library's own table, every `API.*` function Priestly calls exists there, rejected events and the settings checks reach the player through the one reporter, and Priestly refuses to start - saying why in chat - when the library is missing, did not finish loading, is below the floor, or LibGlass is missing or half-loaded. Run against the real library put into each state, not a fake. The compat adapters' own tests are in LibGroupBuffs' suite. |
| `test_manifest.lua` | The TOC and `.pkgmeta`: load order (LibGlass, LibGroupBuffs, then Priestly's three files), both externals read by path and pinned, `NEEDS_MINOR` equal to the pinned MINOR, saved variables, and each library's dev files ignored from here. |
| `test_availability.lua` | Which buffs get a row and what each click casts, per spell the priest actually knows — including the level-20 case where no group Prayer exists, and the Divine-Spirit-without-Prayer-of-Spirit case that used to show nothing. |
| `test_buffs.lua` | `GroupStat` counts, offline handling, the GUID-keyed aura cache surviving a roster reshuffle, combat secrecy (count down from cache, `UNKNOWN` rather than a confident `MISS`), duration learning in both directions with a build reset, `PickTarget`, and `UNIT_AURA` filtering. |
| `test_clicks.lua` | The secure attributes after a rebuild: what `spell1`/`unit1` are actually set to, that they clear rather than cast on a corpse, that `PreClick` re-aims out of combat and leaves things alone in it, and the popover rows. |
| `test_roster.lua` | `GatherGroups` for solo / party / raid / pets, subgroup ordering, pets last, and two raiders sharing a first name. |
| `test_frames.lua` | Executes every script handler and event rather than asserting behaviour — the popover hover poll, row and popover clicks, the ticker, reagent tooltips, close in and out of combat, every registered event, every slash command. Strict globals only catch what runs. |
| `test_visibility.lua` | When the window opens itself and when it must not: a deliberate close surviving a reload and roster churn, joining a group reopening it, and a show asked for during combat happening once combat ends. |
| `test_options.lua` | Builds the options panel and clicks everything in it — checkboxes, radios, the opacity slider, tabs, instance boxes and the three bulk buttons — plus the zero-height layout case. The panel builds lazily on OnShow, so until this existed the whole options UI sat outside the strict-global net. |
| `test_config.lua` | SavedVariables: fresh defaults, the one-time migration off the TBC line (drops TBC instances, keeps the user's own settings), the per-build duration store, and the three Shadow Protection modes. |

## The stub is an allowlist, and it must model absences

The shared stub fails the run on the read of any global it does not define, so it is the list of
APIs verified present on this client. Priestly's own globals are added on top of it, in the local
`wow_stubs.lua`, with `WoW.allowGlobal`.

Anything the addon reads **guarded** — `if Priestly_OpenConfig then`, which exists because
`PriestlyConfig.lua` can fail to load while `Priestly.lua` carries on — has to be allowed as nil
there, or the guard throws inside the stub and the branch it protects can never be tested.
`tests/test_bridge.lua` scans the source for those guards and checks them against the list, so the
two cannot drift. That only works if it is also honest about what is *missing*
and about behaviour that differs:

- `MouseIsOver` is deliberately **not** defined — Forever removed it. Defining it is how a call to
  it survived into a build and surfaced only as a Lua error on mouseover in game.
- `UnitName` returns only the first name for units other than the player, as measured.
- `C_Spell.GetSpellInfo(name)` resolves only spells the player knows; by ID it always resolves.
- Aura reads throw under combat secrecy, while `GetAuraDataBySpellName` returns nil.
- Frame predicates (`IsMouseOver`, `IsShown`) are explicit, and underscore-prefixed keys return nil,
  because the catch-all `__index` returns a function for anything else — and a function is truthy,
  so an unset `_active` would otherwise read as "this row is in use".
- `WoW.dispatch(event, ...)` fires every frame registered for an event, the way the game does. The
  addon has three event frames; firing one leaves the others in a state that never occurs in play.

## What these cannot cover

Anything that needs the real client: whether a `SecureActionButtonTemplate`
click genuinely casts, combat lockdown behaviour, whether `GetInstanceInfo()`
returns the exact instance names in `INSTANCE_DB`, and how the options panel
renders. Those live in the in-game checklist in `AGENTS.md`.
