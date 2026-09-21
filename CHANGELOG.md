# Priestly Changelog

## v2.0.0-beta1 - 2026-09-20

**Priestly Forever** - a port to World of Warcraft: Forever 1.60.1 (Interface 16001).
TBC Classic Anniversary is no longer supported; v1.0.6 remains available for that client.

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

### Changed
- The TBC instance list is gone; the options panel is now **Settings | Instances**. An existing
  Priestly profile is migrated automatically: your settings are kept, TBC-only entries are dropped.
- The main frame now survives being closed during combat the same way the popover already did.
- Reagent tracking follows the spells you know instead of a hardcoded level.

### Added
- A unit test suite (`tests/`, plain Lua 5.1, no game client) and a deploy script.
- Automated releases through the BigWigs packager, with a dry-run package check on every pull
  request.

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
