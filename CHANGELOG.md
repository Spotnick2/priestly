# Priestly Changelog

## v0.2

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