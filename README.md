# Priestly Forever

**Priestly** is a lightweight buff manager for priests, inspired by **PallyPower**. It tracks
*Power Word: Fortitude*, *Divine Spirit* and *Shadow Protection* across your party or raid and lets
you rebuff with a single click.

This is the **World of Warcraft: Forever** edition (client 1.60.1, Interface `16001`).

![Priestly buff window in a group](https://raw.githubusercontent.com/Spotnick2/priestly/main/docs/screenshots/priestly-05.gif)

*Example from an earlier build; the current window has additional controls.*

> **Playing TBC Classic Anniversary?** Install **v1.0.6** — the last release for that client. It
> stays available on CurseForge and the CurseForge app will keep offering it for the Anniversary
> game version. The Anniversary line is no longer being developed.

---

## Features

* **One row per group, per buff** — colour-coded by how many people are missing it, with the lowest
  remaining timer on the bar.
* **One-click buffing** — left-click casts the group Prayer, right-click buffs the first person
  missing it. No targeting.
* **Works before you have the Prayers** — while you only know the single-target spells, left-click
  simply buffs whoever needs it. Nothing is wired to a spell you do not have.
* **Per-member popover** — mouse over a row for the full list with range indicators and per-person
  click casting.
* **Group-aware** — follows party and raid changes, subgroups, and pets.
* **Reagent tracking** — shows the candles and Light Feathers needed by spells you know.
* **Shadow Protection when it counts** — always, only when someone in the group already has it, or
  only inside instances you pick.
* **Window controls** — minimize without closing, lock its position, adjust opacity and choose
  which side the member popover opens on.

---

## Usage

```
/priestly          toggle the window
/priestly show     force open
/priestly hide     close
/priestly config   open the options panel
/priestly reset    reset the window position
/priestly pos      explain the window's saved position
/priestly adopt    use this character's old settings for all your priests
/priestly help     full command and click reference
```

If a member shows `?`, note where it appears: beside the class icon it means the
spell's range is unknown; in place of a timer it means the buff cannot be read and
there is no cached observation. These are independent, and neither proves a language
problem. For a battleground report, include a screenshot showing the column, whether
you are in combat, whether it recovers afterwards, and the spell-name report at the
end of `/priestly help` (locale, game build, addon/library versions and resolved names).

The window opens on its own when you join a group.

Settings persist between sessions. Buff choices and window options are shared across your priests;
whether the window is open is saved per character. If you previously configured different priests
and want one character's older setup to become the shared setup, log into that character and use
`/priestly adopt`.

Use **-** in the header to minimize to a small header, and **+** to restore the
buff rows. This keeps the window accessible; **X** still closes it. Minimize and
restore wait until combat ends. The choice lasts for the current session and
resets to expanded on `/reload` or login. Dragging, locking and resetting the
window work in either mode outside combat.

**Row colours:** green = everyone has it · yellow = some missing · red = nobody has it ·
grey `?` = buff state cannot be read right now (the client hides aura data during combat; Priestly
keeps counting down from the last reading instead of guessing).

---

## Installation

### CurseForge (recommended)

Install through the CurseForge app and enable it in game.

### GitHub and Wago

Download from [GitHub Releases](https://github.com/Spotnick2/priestly/releases/latest)
or [Wago Addons](https://addons.wago.io/addons/priestly-priest-buff-manager-pally-power-style).
Both include the required libraries.

### Manual

Download the release zip and extract it so the folder lands at:

```
World of Warcraft/_classic_beta_/Interface/AddOns/Priestly/
```

---

## Good to know

Priestly uses single-target buffs until you learn the corresponding Prayer. It learns buff
durations from live auras and relearns them when the client build changes. If an instance is
missing from the Shadow Protection list, please report its in-game name.

Forever can hide aura data during combat. When it does, Priestly uses its last observation and
shows `?` if no reliable reading is available. Window movement, closing and minimize/restore
requests made during combat take effect after combat ends.

---

## Feedback

Open an [issue on GitHub](https://github.com/Spotnick2/priestly/issues) or leave a comment on
CurseForge. Include the addon version, client build, locale, whether the problem happened in
combat, and a screenshot if the display looks wrong. Use `/console scriptErrors 1` to show Lua
errors that the client otherwise hides.

## Author

**Spotnick**

## License

MIT — see [LICENSE](LICENSE).
