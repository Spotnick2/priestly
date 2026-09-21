# Priestly Forever

**Priestly** is a lightweight buff manager for priests, inspired by **PallyPower**. It tracks
*Power Word: Fortitude*, *Divine Spirit* and *Shadow Protection* across your party or raid and lets
you rebuff with a single click.

This is the **World of Warcraft: Forever** edition (client 1.60.1, Interface `16001`).

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
* **Reagent tracking** — Sacred/Holy Candle and Light Feather counts, once those spells matter.
* **Shadow Protection when it counts** — always, only when someone in the group already has it, or
  only inside instances you pick.

---

## Usage

```
/priestly          toggle the window
/priestly show     force open
/priestly hide     close
/priestly config   open the options panel
/priestly reset    reset the window position
/priestly help     full command and click reference
```

The window opens on its own when you join a group.

**Row colours:** green = everyone has it · yellow = some missing · red = nobody has it ·
grey `?` = buff state cannot be read right now (the client hides aura data during combat; Priestly
keeps counting down from the last reading instead of guessing).

---

## Installation

### CurseForge (recommended)

Install through the CurseForge app and enable it in game.

### Manual

Download the release zip and extract it so the folder lands at:

```
World of Warcraft/_classic_beta_/Interface/AddOns/Priestly/
```

---

## Beta notes

Forever is in beta and the level cap is still low, so some of Priestly is waiting for content to
catch up:

* The group **Prayer of X** spells are not learnable yet. Every row works single-target until they
  are, and switches over automatically once you learn one.
* **Buff durations differ from both TBC and Vanilla** and are still being tuned. Priestly learns the
  real duration from your own buffs rather than assuming one, and forgets what it learned whenever
  the client build changes.
* **Reagents** (candles, Light Feather) only appear once you know the spells that need them.
* The **by-instance** Shadow Protection mode lists Forever's own raids and dungeons. Most are above
  the current level cap, so the names it matches on are still unverified — if it ever fails to
  notice an instance you are standing in, that is why.
* **Your settings reset every time you reload.** This is a client bug and it affects every addon,
  not just this one: Forever writes addon settings to disk correctly and then never reads them back
  at login. Per-character storage fails the same way as account-wide. So the window position, the
  lock, the buff toggles and the Shadow Protection list all start fresh each session.

  Nothing an addon does can work around it directly. There is a usable alternative on this client
  and Priestly will move its settings there, so this should be temporary — but for now, please do
  not report lost settings as a Priestly bug.

---

## Feedback

Open an issue on GitHub or leave a comment on CurseForge.

## Author

**Spotnick**

## License

MIT — see [LICENSE](LICENSE).
