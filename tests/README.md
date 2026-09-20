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

## How it works

- **`wow_stubs.lua`** — a minimal WoW: Forever API mock: chainable
  `CreateFrame` whose frames *record their secure attributes*, a `C_Timer` that
  collects callbacks instead of waiting, `C_UnitAuras` backed by an injectable
  per-unit aura table with a secrecy switch, `C_Spell` / `C_SpellBook` backed
  by an injectable known-spell set, and units that carry a GUID and a Forever
  surname. Drive it through the exported `WoW` table:
  `WoW.reset()`, `WoW.SetUnit`, `WoW.SetAura`, `WoW.Know`, `WoW.DefineSpell`,
  `WoW.fire`. `dofile("tests/wow_stubs.lua")` **first** in every test.
- **`harness.lua`** — `check`/`eq`/`near`, `loadAddon()` (loads the three files
  in TOC order and hands back the test seams) and `TeachSpells{...}` for the
  common "this priest knows X" setup.
- Internals that are file-local are reached through a **test seam**:
  `Priestly._test` at the end of `Priestly.lua` and `Priestly._testConfig` at
  the end of `PriestlyConfig.lua`. Both are harmless in game.
- A file prints `name: N tests passed` and exits non-zero on failure.

## Test files

| File | What it pins down |
|---|---|
| `test_compat.lua` | The API adapters: aura structs → `(remaining, duration)`, the `IsSpellInRange` boolean/nil tri-state (the old `== 1` / `== 0` ladder, where `0` is truthy), icon fallbacks, surname-bearing names, GUID identity, and `RegisterEvents` reporting an event name this client throws on. |
| `test_availability.lua` | Which buffs get a row and what each click casts, per spell the priest actually knows — including the level-20 case where no group Prayer exists, and the Divine-Spirit-without-Prayer-of-Spirit case that used to show nothing. |
| `test_buffs.lua` | `GroupStat` counts, offline handling, the GUID-keyed aura cache surviving a roster reshuffle, combat secrecy (count down from cache, `UNKNOWN` rather than a confident `MISS`), duration learning in both directions with a build reset, `PickTarget`, and `UNIT_AURA` filtering. |
| `test_clicks.lua` | The secure attributes after a rebuild: what `spell1`/`unit1` are actually set to, that they clear rather than cast on a corpse, that `PreClick` re-aims out of combat and leaves things alone in it, and the popover rows. |
| `test_roster.lua` | `GatherGroups` for solo / party / raid / pets, subgroup ordering, pets last, and two raiders sharing a first name. |
| `test_config.lua` | SavedVariables: fresh defaults, the one-time migration off the TBC line (drops TBC instances, keeps the user's own settings), the per-build duration store, and the three Shadow Protection modes. |

## What these cannot cover

Anything that needs the real client: whether a `SecureActionButtonTemplate`
click genuinely casts, combat lockdown behaviour, whether `GetInstanceInfo()`
returns the exact instance names in `INSTANCE_DB`, and how the options panel
renders. Those live in the in-game checklist in `AGENTS.md`.
