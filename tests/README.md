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

**The tests need LibGroupBuffs-1.0 checked out next to this repository**
(`../LibGroupBuffs`), because Priestly loads it before its own files. `run.ps1`
takes `-Library <path>` instead, and prints which checkout and revision it used
next to the tag a release pins. A single test run by hand reads the
`LIBGROUPBUFFS` environment variable, or the sibling checkout. There is no
vendored copy to fall back to, on purpose.

## How it works

- **`wow_stubs.lua`** — a minimal WoW: Forever API mock: chainable
  `CreateFrame` whose frames *record their secure attributes*, a `C_Timer` that
  collects callbacks instead of waiting, `C_UnitAuras` backed by an injectable
  per-unit aura table with a secrecy switch, `C_Spell` / `C_SpellBook` backed
  by an injectable known-spell set, and units that carry a GUID and a Forever
  surname. Drive it through the exported `WoW` table:
  `WoW.reset()`, `WoW.SetUnit`, `WoW.SetAura`, `WoW.Know`, `WoW.DefineSpell`,
  `WoW.fire`. `dofile("tests/wow_stubs.lua")` **first** in every test.
- **`harness.lua`** — `check`/`eq`/`near`, `loadAddon()` (loads the library
  through its own XML, then Priestly's files in TOC order, failing on anything
  missing, and hands back the test seams) and `TeachSpells{...}` for the common
  "this priest knows X" setup.
- Internals that are file-local are reached through a **test seam**:
  `Priestly._test` at the end of `Priestly.lua` and `Priestly._testConfig` at
  the end of `PriestlyConfig.lua`. Both are harmless in game.
- A file prints `name: N tests passed` and exits non-zero on failure.

## Test files

| File | What it pins down |
|---|---|
| `test_bridge.lua` | Priestly on top of LibGroupBuffs-1.0: `Priestly.API` is the library's own table, every `API.*` function Priestly calls exists there, rejected events are printed in chat, and a missing library stops loading with a message naming it. The compat adapters' own tests moved to `LibGroupBuffs/tests/test_compat.lua`. |
| `test_availability.lua` | Which buffs get a row and what each click casts, per spell the priest actually knows — including the level-20 case where no group Prayer exists, and the Divine-Spirit-without-Prayer-of-Spirit case that used to show nothing. |
| `test_buffs.lua` | `GroupStat` counts, offline handling, the GUID-keyed aura cache surviving a roster reshuffle, combat secrecy (count down from cache, `UNKNOWN` rather than a confident `MISS`), duration learning in both directions with a build reset, `PickTarget`, and `UNIT_AURA` filtering. |
| `test_clicks.lua` | The secure attributes after a rebuild: what `spell1`/`unit1` are actually set to, that they clear rather than cast on a corpse, that `PreClick` re-aims out of combat and leaves things alone in it, and the popover rows. |
| `test_roster.lua` | `GatherGroups` for solo / party / raid / pets, subgroup ordering, pets last, and two raiders sharing a first name. |
| `test_frames.lua` | Executes every script handler and event rather than asserting behaviour — the popover hover poll, row and popover clicks, the ticker, reagent tooltips, close in and out of combat, every registered event, every slash command. Strict globals only catch what runs. |
| `test_visibility.lua` | When the window opens itself and when it must not: a deliberate close surviving a reload and roster churn, joining a group reopening it, and a show asked for during combat happening once combat ends. |
| `test_options.lua` | Builds the options panel and clicks everything in it — checkboxes, radios, the opacity slider, tabs, instance boxes and the three bulk buttons — plus the zero-height layout case. The panel builds lazily on OnShow, so until this existed the whole options UI sat outside the strict-global net. |
| `test_config.lua` | SavedVariables: fresh defaults, the one-time migration off the TBC line (drops TBC instances, keeps the user's own settings), the per-build duration store, and the three Shadow Protection modes. |

## The stub is an allowlist, and it must model absences

`wow_stubs.lua` fails the run on the read of any global it does not define, so it is the list of
APIs verified present on this client. That only works if it is also honest about what is *missing*
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
