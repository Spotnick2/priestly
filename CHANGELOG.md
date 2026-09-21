# Priestly Changelog

## Unreleased

### Fixed
- **The per-member popover opened off-screen if you kept Priestly on the left.** It always opened to
  the left of the frame, so anyone who put Priestly where Pally Power normally sits lost the popover
  past the edge of the screen - and with it the per-member click casting. It now opens on whichever
  side has room, and follows the frame when you drag it.

### Added
- **Popover Side** in Options - Appearance. Automatic by default, which is what the above describes;
  set it to always-left or always-right if you would rather pin it.

  Thanks to **zoikes** on CurseForge for the report.

## v2.0.1 - 2026-09-20

### Fixed
- **Clicking a buff row did nothing at all, for some people.** If you use AdvancedInterfaceOptions,
  MiniPressRelease, or anything else that makes your buttons fire when you *release* the mouse
  rather than when you press it, every row in Priestly was dead - no cast, no error message,
  nothing to suggest the addon had even noticed. The rows now work whichever way you have that set,
  and keep working if you change it without reloading.

  Still one cast per click, so this costs you no extra reagents.

  Thanks to **Jaybeoh** on CurseForge for the report, and for working out what the two addons had in
  common - that was the whole answer.

## v2.0.0 - 2026-09-20

**Priestly Forever** - a port to World of Warcraft: Forever 1.60.1 (Interface 16001).
TBC Classic Anniversary is no longer supported; v1.0.6 remains available for that client.

Forever itself is in beta and capped at level 20, so parts of this are waiting on content: the
group "Prayer of X" spells do not exist yet, reagents do not apply, and most instances cannot be
reached. Everything that can work at the current cap does, and is verified in game.

### Ported
- Rebuilt every removed or moved API call behind a compatibility layer: auras now read through
  `C_UnitAuras`, spell data through `C_Spell`, the spellbook through `C_SpellBook`, item icons
  through `C_Item`.
- Event registration is guarded: this client throws on an unknown event name instead of ignoring it,
  and anything unsupported is now reported rather than silently dead.
- The options panel no longer depends on Classic-only frame templates.

### New behaviour for Forever
- **Works before the Prayers exist.** Every buff row is built from the spells you actually know, and
  left-click falls back to the single-target spell when there is no group Prayer - so no click is
  ever wired to a spell that does not exist. This applies to Fortitude and Shadow Protection now,
  not just Divine Spirit.
- **Buff durations are learned, not assumed.** Forever's durations match neither TBC nor Vanilla and
  are still being tuned, so the timer bars scale against what your own buffs actually report, and
  reset whenever the client build changes.
- **Combat aura secrecy is handled.** This client makes every aura unreadable once combat starts -
  for the whole group, not just you - and the by-name lookup returns "no buff" rather than an error,
  so a naive port would report the entire raid as unbuffed the moment you pull. Priestly detects the
  block, counts down from the last reading instead, and shows `?` for anyone it never saw buffed.
- **Surnames.** Forever characters have one, and first names are not unique, so full names are shown
  and the popover is wider to fit them. Buff state now follows the character, not the raid slot.
- `UNIT_AURA` is filtered to the units and spells that matter - it fires far more often here.

### Known client issue
- **Settings are stored per character.** This client writes account-wide saved variables but never
  reads them back, so any addon using them resets to defaults every session. Per-character storage
  does work, so that is where Priestly keeps its settings. Configuring one character does not
  configure the others.

### Changed
- **The instance list is Forever's content**, not Vanilla's: the three raids — The Barrow Deeps
  (10), Hyjal Summit (20) and Onyxia's Lair (40) — and all twenty-eight dungeons, ordered by level.
  That includes Forever's nine new ones, from The Hall of Thanes at 13 up to Shaper's Terrace at 60.
  They are listed but unchecked, because nothing is known about their encounters yet and the
  tooltip says so rather than inventing detail. The Vanilla raids beyond Onyxia are gone; they are
  not in the game.
- Multi-wing instances are one entry each. Scarlet Monastery, Maraudon, Dire Maul, Stratholme and
  Blackrock Spire report a single name to addons however you enter them, so one row is what the
  game actually exposes.
- If Priestly does not recognise an instance you walk into, it now says so instead of quietly doing
  nothing — most of these names cannot be checked against the game until the level cap rises, and a
  wrong one would otherwise just fail in silence.
- The TBC instance list is gone; the options panel is now **Settings | Instances**. Priestly will
  migrate a v1.x profile if it ever sees one - keeping your settings and dropping the TBC-only
  entries - but on this client it will not: v1.x stored settings account-wide, and account-wide
  saved variables are not read back (see above). Expect to configure Forever from defaults.
- The main frame now survives being closed during combat the same way the popover already did.
- Reagent tracking follows the spells you know instead of a hardcoded level, and counts the whole
  carried inventory including a reagent bag.
- Clicks prefer somebody in range. Casting at a member who is out of reach simply fails, and a
  group Prayer reaches further than the single-target spell, so each click is measured against the
  spell it will actually cast.
- Closing the window is remembered. It no longer reopens on the next login, ready check or roster
  change - only on joining a group, which is what the addon promises. A `/priestly show` asked for
  during combat now happens when combat ends instead of being dropped.
- Pets get as many rows as they need. A raid with more pets than the popover can list is split into
  several pet groups rather than counting members it gave you no way to click.
- The per-member popover follows a roster change while it is open, instead of showing the previous
  group under the new names.

### Added
- A unit test suite (`tests/`, plain Lua 5.1, no game client) and a deploy script.
- A package check on every pull request: syntax, the full test suite, and a dry-run build of the
  release zip.

## v1.0.6 - 2026-05-13

### Fixed
- Fixed the main frame displaying an extra `v` before addon versions that already include the prefix.

## v1.0.3

### Fixed
- Fixed Divine Spirit tracking not appearing for priests who know Divine Spirit but do not yet know Prayer of Spirit.
- Fixed the popover closing behavior during combat.
- Prevented the popover from trying to fully hide while in combat, which could cause secure frame issues.
- Popover now becomes visually hidden during combat and is properly restored or fully hidden once combat ends.
- Fixed cases where manually closing Priestly during combat could leave the popover in a bad state.

### Improved
- Improved combat-safe handling for UI elements attached to secure buttons.
- Added cleanup logic so the popover is properly reset after leaving combat.

### Changed
- Updated addon version metadata.

## v1.0.2 - 2026-04-06

- Fix a bug with GetAddOnMetadata

## v1.0.1 - 2026-04-06

- Fixed changelog packaging

## v1.0.0 - 2026-04-06

Priestly’s first stable release brings a full in-game configuration experience, more flexible buff tracking, and better support for solo play, pets, and Shadow Protection management.

### Added
- Full in-game options panel with dedicated tabs for:
  - General settings
  - TBC instance Shadow Protection settings
  - Vanilla instance Shadow Protection settings
- New `/priestly config` command, with additional aliases for opening the options panel.
- Solo mode option to keep Priestly visible even when you are not in a party or raid.
- Optional pet tracking, with pets shown in their own group at the bottom of the frame.
- Per-buff tracking toggles for:
  - Power Word: Fortitude / Prayer of Fortitude
  - Divine Spirit / Prayer of Spirit
- Configurable Shadow Protection display modes:
  - Always show
  - Show when detected on a group member
  - Show by instance
- Curated TBC and Vanilla instance lists for Shadow Protection, including encounter notes and default recommendations.
- Appearance control for frame opacity, applied to both the main window and the popover.

### Changed
- Priestly now supports being shown automatically in solo mode as well as in groups.
- Group/solo visibility handling now refreshes more cleanly when your party state changes.
- Main frame version text now reads from addon metadata instead of a hardcoded version string.
- Addon metadata updated for current TBC Classic Anniversary interface support and CurseForge packaging.

### Improved
- Better control over when Shadow Protection appears in the buff tracker.
- Better control over whether pets are included in buff assignments.
- Better control over which core priest buffs Priestly actively tracks.
- Improved onboarding by advertising both `/priestly help` and `/priestly config` when the addon loads.

### Compatibility
- Updated for TBC Classic Anniversary interface version `20505`.

## v0.2.0 alpha2

### Configuration Panel
- Added full options panel integrated into WoW's Interface → AddOns → Priestly (no standalone window needed)
- Three-tab layout: **Settings**, **TBC Instances**, **Vanilla Instances**
- Accessible via `/priestly config` (also accepts `options`, `settings`, `opt`)

### Settings Tab
- **Show when solo** — keeps the frame visible even without a group; toggling it on/off takes effect immediately
- **Buff tracking checkboxes** — independently toggle Fortitude and Spirit tracking
- **Shadow Protection mode** — three radio options:
  - *Always* — permanently visible
  - *Detected* — shows when any group member already has the buff (default)
  - *By instance* — activates when entering a whitelisted instance from the Instances tabs
- **Pet tracking toggle** — show/hide the Pets group at the bottom of the frame
- **Frame opacity slider** — 20%–100%, applies live to both main frame and popover; custom dark track background for visibility

### TBC Instances Tab
- All 25 TBC instances listed (9 raids, 16 dungeons) in a two-column layout
- Instances with significant shadow damage are pre-checked by default
- Hover any instance for a tooltip describing which boss encounters deal shadow damage
- Select All / Deselect All / Reset Defaults buttons

### Vanilla Instances Tab
- 17 classic instances (7 raids, 10 dungeons) in the same two-column layout
- Shadow-relevant instances pre-checked (Naxx, BWL, AQ40, ZG, Scholomance, Stratholme, Dire Maul, Sunken Temple)
- Same tooltip and button controls as the TBC tab

### Detection System
- Instance-based detection uses `GetInstanceInfo()` on zone change — no NPC/GUID parsing needed
- New instances are automatically backfilled into existing saved data on addon upgrade

### Other
- SavedVariables migration cleans up old `shadowBosses` data from any earlier builds
- Login message now mentions `/priestly config`
- `/priestly help` updated with the new config command

## v0.1
- Initial release
