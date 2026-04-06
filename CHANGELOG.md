# Priestly Changelog

## v1.0.0

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