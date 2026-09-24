# Forever client probe — findings

What `Tools/PriestlyProbe` actually measured on the live client, as opposed to what the
documentation says. Existence is not a contract: a namespace being present tells you nothing about
arity, return order, or whether the underlying system is wired up on a Vanilla-content client.

**Client:** WoW: Forever 1.60.1, build **69913**, `Sep 17 2026`, `tocVersion` **16001**,
`WOW_PROJECT_ID == WOW_PROJECT_MAINLINE (1)`, locale enUS.
Probed 2026-09-20 on a level 3 Priest, in a 2-person party, standing in Undercity.

**Still current on build 69977** (`Sep 22 2026`), which is what is installed as of 2026-09-24 and
what `MEASURED_ON_BUILD` now says. Nothing below was re-run with `/pprobe`; what carries it over
is that the two builds' API dumps are **identical sets** - documented functions, events, enums and
structures, widget methods, namespace functions. A finding here that stops matching the game is a
bug report, not a surprise: re-run the probe rather than assuming the note was always wrong.

The SavedVariables finding (section 11) is the exception, because a dump cannot show it: the
client lists the same symbols whether or not it reads the file back. It was re-measured on 69977
**from the files themselves**, without launching the game - see below.

---

## 1. Secure click-casting — the blocking question

The porting guide reports that secure *snippets* are broken here and concludes that "click-casting
addons do not work". Priestly uses none of that machinery — plain `SecureActionButtonTemplate`,
`SetAttribute("type1", "spell")`, and insecure `PreClick`/`PostClick`.

| Check | Result |
|---|---|
| `SecureActionButtonTemplate` frame creates | **yes** |
| `SetAttribute` from an insecure `PreClick`, out of combat | **yes**, no taint error |
| `PreClick` / `PostClick` both fire on left and right click | **yes** |
| `loadstring_untainted` | **missing** — confirms secure *snippets* are broken |
| `SecureHandlerWrapScript`, `RegisterStateDriver` | present as functions, but unusable without the above |

The guide's warning is about `SecureHandler*` and state drivers specifically. Priestly's attribute
based click casting is a different mechanism and is intact. **Do not introduce a `SecureHandler*`.**

**Confirmed by hand:** the button casts, on the player and on a party member, both buttons. The
design holds.

> Still to confirm: clicking in combat, where `PreClick` cannot re-target and the click has to use
> the pre-combat wiring.

### Which mouse edge to register for — **both**, and the client picks

Read from Forever 1.60.1 (69913) FrameXML, `SecureTemplates.lua` — `SecureActionButton_OnClick`:

```lua
useOnKeyDown = <button's "useOnKeyDown" attribute> or GetCVarBool("ActionButtonUseKeyDown")
clickAction  = (down and useOnKeyDown) or (not down and not useOnKeyDown)
```

`clickAction` is `down == useOnKeyDown`, so **of the two mouse edges exactly one ever performs the
action**, and which one follows the CVar. That explains both halves of the CurseForge report:

- Registering only `*ButtonDown`, as the addon did through v2.0.0, is dead on any client set to act
  on release — AdvancedInterfaceOptions and MiniPressRelease both flip that CVar. The handler
  rejects the only edge we asked for. No cast, no error.
- Registering **both** edges is one cast, not two, because the handler admits one. This is the fix
  suggested on CurseForge, and it is correct here.

**Measured in game with `/pprobe click`,** three secure buttons all registering both edges, casts
counted from `UNIT_SPELLCAST_SENT`:

| Button | `useOnKeyDown` attribute | Casts per click |
|---|---|---|
| A | none — follows the CVar | **1** |
| B | `true` — forces the keydown branch | **1** |
| C | `false` — forces the keyup branch | **1** |

So the keyup branch **does** dispatch here — the fix works for the people who reported dead clicks —
and registering both edges is **one cast**, not two. Confirmed, not reasoned.

**That it does not double-cast rests on two things, not one.** The edge the handler rejects can
still reach the press-and-hold release path when `ActionButtonUseKeyHeldSpell` is on. That path
resolves its action from the **`typerelease`** attribute, not `type`, and Priestly sets no
`typerelease` — so it finds no action and casts nothing. The measurement above confirms the outcome;
it does not make `typerelease` safe to set. **Setting one would double-cast and burn two reagents.**

Following the CVar with a single edge was tried and rejected: `RegisterForClicks` is protected under
combat lockdown, so a CVar change mid-fight leaves the rows on an edge the handler now refuses, with
no way to re-register until combat ends. Both edges has no such state, so `C_CVar`, `GetCVarBool`,
`GetCVar` and `CVAR_UPDATE` are all recorded by the probe for reference and consumed by nothing.

The readers do exist, which closes what this section previously listed as unknown. `/api s GetCVar`
returns `C_CVar.GetCVar`, `GetCVarBool`, `GetCVarBitfield`, `GetCVarDefault` and `GetCVarInfo`, and
the full API dump's `_G` section lists the bare globals as well. Nothing to change: the addon
stopped consuming them when it stopped guessing the edge.

One thing is still unread, and it no longer matters. `SecureActionButton_OnClick` also takes
`isKeyPress` / `isSecureAction` and forces `useOnKeyDown = false` for what it calls a secure mouse
press, which would pin mouse clicks to the Up edge regardless of attribute or CVar. The bench above
does not discriminate — with both edges registered every branch yields exactly one dispatch, which
is precisely why it is safe either way. Registering both edges is correct under every reading of
that code, so the question is archived rather than open.

## 2. Events — all 16 register, none throw

Including `ACTIVE_TALENT_GROUP_CHANGED`, which was the one to distrust (no working Forever addon in
the local sample registers it). `PLAYER_SPECIALIZATION_CHANGED` and `CHARACTER_POINTS_CHANGED` also
register.

**`CVAR_UPDATE` is the 17th and is not yet measured.** It is in the probe's list for reference. The
addon does not register it: see section 1 — registering both mouse edges removes the reason to
watch the CVar at all.

Registration still goes through `Priestly.RegisterEvents`, which reports rejected names in chat: it
costs nothing, and it means a future event rename is reported instead of silently killing a handler.
(`API.RegisterEvents` in LibGroupBuffs only returns the rejected names, since a library must not
print into another addon's chat frame; called directly, the report is lost.)

## 3. Templates — all 14 present, none throw

`UICheckButtonTemplate`, `InterfaceOptionsCheckButtonTemplate`, `UIRadioButtonTemplate`,
`OptionsSliderTemplate`, `UISliderTemplateWithLabels`, `MinimalSliderTemplate`,
`UIPanelScrollFrameTemplate`, `ScrollFrameTemplate`, `BackdropTemplate`, `UIPanelDialogTemplate`,
`UIPanelCloseButton`, `UIPanelButtonTemplate`, `UIMenuButtonStretchTemplate`,
`SecureActionButtonTemplate`.

So `InterfaceOptionsCheckButtonTemplate` survives here even though Retail dropped it. The config
panel's `SafeFrame` degradation stays anyway — it costs a few lines and a missing template is a load
blocker, not a cosmetic problem.

**Probe gotcha worth remembering:** a template must be created with the frame type it was written
for. `CreateFrame("Button", nil, UIParent, "MinimalSliderTemplate")` throws from inside Blizzard's
own `MinimalSlider.lua` because its OnLoad calls a Slider method. That looks exactly like "template
missing" and is not. Conversely a genuinely missing template does *not* throw — `CreateFrame` hands
back a bare frame — so presence has to be checked by looking for the regions the template brings.

## 4. Names and surnames — confirmed, and the APIs disagree

`C_PlayerInfo.ShouldDisplaySurname()` → **true**. The separator is a **space**, not a hyphen (the
hyphen in the porting guide comes from the WTF folder layout).

| API | player | party1 |
|---|---|---|
| `UnitName` | `"Karuzo Elegia"`, `"ClassicBetaPvE"` | `"Zoruka"`, `"Mortalis"` |
| `UnitFullName` | `"Karuzo Elegia"`, `"ClassicBetaPvE"` | `"Zoruka"`, `"Mortalis"` |
| `UnitNameUnmodified` | `"Karuzo Elegia"` | `"Zoruka"`, `"Mortalis"` |
| **`GetUnitName(unit, false)`** | **`"Karuzo Elegia"`** | **`"Zoruka Mortalis"`** |
| `GetUnitName(unit, true)` | `"Karuzo Elegia"` | `"Zoruka Mortalis"` |
| `C_PlayerInfo.GetName` | errors — wants a `playerLocation`, not a unit token | same |

**`UnitName` is a trap.** On the player it returns the whole two-part name with the realm second;
on another unit it returns only the **first name**, with the surname in the position where realm
normally lives. Any code that uses `UnitName(unit)` for a party or raid member silently drops the
surname — and first names are not unique.

`API.UnitDisplayName` uses `GetUnitName(unit, false)`, which is the only one that returns the joined
name consistently for both. Identity still keys on `UnitGUID` (`Player-4618-00C6CDD5`), never on a
name.

## 5. Instances — `GetInstanceInfo` returns the continent outdoors

Standing in Undercity: `GetInstanceInfo()` → `"Eastern Kingdoms", "none", 0, "", 0, 0, false, 0, 0`
while `GetRealZoneText()` → `"Undercity"`.

So the name is **not** empty outside an instance, and testing only the name would have been correct
purely by luck — until an `INSTANCE_DB` key collided with a continent or the addon gained a zone
list. `CheckCurrentInstance` now gates on `instanceType ~= "none"`.

The `INSTANCE_DB` names themselves are still unverified: none of those dungeons are reachable at the
current cap.

## 6. Items — the globals are gone, `C_Item` works

`GetItemIcon` and `GetItemInfo` globals: **absent**. `C_Item.GetItemIconByID(17028/17029/17056)` →
`133752 / 133751 / 132917` (file IDs, not paths). `C_Item.GetItemInfo` returns the full tuple with
the texture in position 10, and reports Holy Candle as required level 48, Sacred Candle 60, Light
Feather 1 — so the reagent items exist in this client's database even though the spells that consume
them are not learnable yet. `C_Container` present.

## 7. Options framework

`Settings.RegisterCanvasLayoutCategory` and `Settings.OpenToCategory`: **present**.
`InterfaceOptions_AddCategory`: **absent** — the fallback branch that used to call it is correctly
gone.

## 8. Spells — the Prayers exist, and name lookup is knowledge-gated

All six IDs resolve through `C_Spell.GetSpellInfo(id)`, including the three Prayers the player
cannot learn yet:

| Spell | ID | resolves by ID | maxRange | known at lvl 3 |
|---|---|---|---|---|
| Power Word: Fortitude | 1243 | yes | 30 | **yes** |
| Divine Spirit | 14752 | yes | 30 | no |
| Shadow Protection | 976 | yes | 30 | no |
| Prayer of Fortitude | 21562 | yes | **40** | no |
| Prayer of Spirit | 27681 | yes | **40** | no |
| Prayer of Shadow Protection | 27683 | yes | **40** | no |

So the group-buff concept is present in this client's spell database — the Prayers are simply not
learnable at the current cap. Building the rows from what the player knows, and switching the click
mapping over the moment a Prayer is learned, is the right shape.

**The Prayers buff the whole raid here, not one subgroup.** Every Prayer, at every rank, reads
*"Power infuses all party and raid members"*. On Vanilla and TBC a Prayer covered only the party of
whoever it was cast on, which is the assumption behind per-subgroup rows, the `groupMode` target
pick and the click hint that names "group 3" or "your party". Read from the tooltips at the current
cap, and datamining agrees so far. **Not castable yet** - the cap is 20 - so none of it is verified
in play.

| Prayer | Rank | Level | Mana | Reagent | Effect | Duration |
|---|---|---|---|---|---|---|
| Fortitude | 1 | 48 | 2600 | Holy Candle (17028) | +56 Stamina | 1 h |
| Fortitude | 2 | 60 | 3400 | Sacred Candle (17029) | +70 Stamina | 1 h |
| Spirit | 1 | 60 | 1940 | Sacred Candle | +40 Spirit | 1 h |
| Shadow Protection | 1 | 56 | 1300 | Sacred Candle | +60 Shadow resistance | **20 min** |

**Unreconciled, and possibly not a conflict: the Shadow Prayer needs level 56 and a Sacred Candle,
while section 6 records the client's item database reporting that candle as required level 60.**
Both numbers come from the client. Whether an item's minimum level gates its use *as a spell
reagent* is not something this probe has measured - it may not, in which case both readings stand.
Test the cast at 56 when it is reachable; do not assume either number is wrong until then.

What this changes, **from level 48** - the first learnable rank, which the tooltips say is already
raid-wide - not from 60:

- **The reagent footer would show the wrong candle, silently** (issue #49). `GetCandleInfo`
  derives the candle
  from `GetPrayerRank()`, which reads the rank of **Prayer of Fortitude only**. A priest at 56-59
  knows the Shadow Prayer (Sacred Candle) while Fortitude is still rank 1 (Holy Candle), so the
  footer counts Holy Candles, labels them "used by the group Prayers", plural, and says nothing
  about the Sacred Candles the Shadow Prayer is burning. Running out mid-raid with a full stack of
  the other candle on screen is the failure. The footer needs to be driven by the reagents of every
  Prayer the priest knows, not by one def's rank.
- **Per-subgroup rows would offer the same cast eight times, at a candle each** (issue #50). Rows
  are built per
  subgroup per buff, and each one's left click casts the Prayer. If a Prayer covers the whole raid,
  a priest working down a frame of eight red rows can spend eight candles where one cast would have
  done - Holy Candles from 48, Sacred ones later. That is the strongest argument against keeping
  the per-subgroup model, and it costs the player real reagents, not just clarity.
- **The click hint would promise a subgroup**, naming "group 3" or "your party" for a spell whose
  text says it covers party and raid.
- **Unmeasured, and needed before any targeting decision: what the buff actually reaches.** The 40
  yards from `C_Spell.GetSpellInfo` is `maxRange`, the range at which the spell can be cast at a
  target. It says nothing about how far the raid-wide effect extends, or whether that radius is
  centred on the caster or on the target. A probe at 48 should establish both, because "aim it at
  anyone" and "aim it to cover the most people" are different behaviours.

**The Shadow Prayer runs 20 minutes where the single-target form runs 10.** The group form is not
just wider, it is longer. `DEFS[].duration` is one seed per buff - 600 for shadow - so until a live
aura is seen the Prayer's bar is scaled against the single form's length. It clamps to full rather
than misreporting, and the learned-duration cache keys on the **spell name** for exactly this
reason, so the Prayer learns 1200 while the single keeps 600. Closing the gap before anything is
seen means a per-form seed, and that is a LIBRARY change: `DurationFor` lives in
LibGroupBuffs' `Engine.lua` and ends in `return def.duration or 3600`, taking only
`(def, observed, spellName)`. A `grpDuration` field added to Priestly's `DEFS` alone would be
ignored - the engine would have to prefer it when `spellName == def.grp`, and Priestly would have
to re-pin.

**`C_Spell.GetSpellInfo(name)` only resolves spells the player KNOWS.** By ID it always works; by
name it returned nothing for Divine Spirit, Shadow Protection and all three Prayers, while working
for Power Word: Fortitude. This is why `RefreshSpellData` resolves names *from IDs* — the reverse
would have silently produced nil names for every buff the priest has not learned.

`C_Spell.IsSpellInRange` returns `true` / `false` / nothing, and nothing for a spell the player does
not know. `IsSpellInRange` and `GetSpellInfo` globals are both gone.

## 9. Auras

`C_UnitAuras` present, `UnitBuff` global gone. `AuraUtil` **is** present here, contrary to the
porting guide — unused either way. The struct carries everything needed:

```
{ name="Power Word: Fortitude", duration=3600, expirationTime=595726.39, icon=135987,
  applications=0, auraInstanceID=1, dispelName="Magic", isHelpful=true, isRaid=true,
  isFromPlayerOrPlayerPet=true, sourceUnit="player", points={1=4}, ... }
```

**Power Word: Fortitude lasts 3600s here** — an hour, against 1800 in Vanilla. Priestly's own saved
variables confirm it learned exactly that (`learnedDurations = { build = "69913", fort = 3600 }`),
which also proves the learning path works end to end in game.

`GetAuraDataBySpellName` found the aura the unit actually had and returned nothing for the rest.
That leaves one thing unresolved out of combat: whether the by-name lookup is subject to the same
knowledge gating as `GetSpellInfo(name)`. If it is, a priest who has not learned Prayer of Fortitude
could not see it on someone another priest buffed. **`API.ReadBuff` therefore never treats a by-name
miss as "not buffed"** — it falls through to the index walk to confirm.

### Combat secrecy — measured, and it is total

In combat every index read **throws**, for every unit:

```
GetAuraDataByIndex(): Auras cannot be accessed when secret while tainted by 'PriestlyProbe'
Lua Taint: PriestlyProbe
```

Three things follow, all confirmed on `player`, `target` and `party1` across three separate runs:

1. **Secrecy is not limited to the player.** Party and raid helpful auras are equally unreadable.
   An addon is blind to every buff for the whole fight, so the GUID-keyed cache is load-bearing,
   not a nicety.
2. **It throws rather than returning an empty list**, so the block is detectable: `API.ReadBuff`
   pcalls every read and reports `BLOCKED`, distinct from `NONE`.
3. **`GetAuraDataBySpellName` does NOT throw — it quietly returns nil.** On its own that is
   indistinguishable from "not buffed", so an addon that used only the by-name lookup would report
   the entire raid as unbuffed the moment combat started, with no error to explain it. The index
   walk is what makes the block visible.

The taint is attributed by addon name, so this applies to any addon-initiated read; there is no
way to opt out.

Because of (1), `BuffRem` attempts the read *regardless* of `ShouldAurasBeSecret()` rather than
refusing whenever the flag is set: on this build it always ends in `BLOCKED`, but if a future build
stops covering party and raid auras, live data wins over a cache that is only as fresh as the last
pull.

`C_Secrets.GetSpellAuraSecrecy(id)` returns `2` for all seven spells probed. The enum that names
that value was not present under `Enum.SpellAuraSecrecy`; it does not matter, since
`ShouldAurasBeSecret()` plus a throwing read is the whole signal.

## 10. Spellbook — rank subtext survives

`C_SpellBook.IsSpellKnown`, `IsSpellInSpellBook` and `IsSpellKnownOrInSpellBook` all agree.
`GetNumSpellBookSkillLines` is 3, with `itemIndexOffset` / `name` per line, and a flat
`GetSpellBookItemName(1..n, Enum.SpellBookSpellBank.Player)` walk covers everything.

The walk returns the rank in the subtext — `Lesser Heal [Rank 1]`, `Power Word: Fortitude [Rank 1]`
— so the reagent-rank logic (`API.GetSpellRank`) has something to parse once Prayer of Fortitude is
learnable.

## 11. SavedVariables — nothing loads back, per-character included

**Re-measured 2026-09-21 01:14 on build 1.60.1.69913. This supersedes the earlier finding in this
section that per-character storage worked.**

`/pprobe sv`:

```
account-wide table arrived at load: NO
per-character table arrived at load: NO
launches recorded before this one: account=0 character=0
launches now: account=1 character=1
```

Both files on disk read `launches = 1`. Every session starts from zero and writes 1; a working load
would show 2, 3, 4. Confirmed independently by Priestly itself: `PriestlyDB.pos` is present in the
character file and nil in the next session, which `/priestly pos` reports directly.

**Still broken on 69977, re-measured 2026-09-24 without launching the game.** The probe's own
before/after is *in the file it writes*, so once a counting addon has ever run, the check costs
nothing — `WTF/Account/<id>/SavedVariables/PriestlyProbe.lua`:

```lua
PriestlyProbePersist = {
["marker"] = "written by PriestlyProbe",
["launches"] = 1,
["stamps"] = {
"2026-09-24 11:00:02",
},
}
```

`stamps` is **append-only per addon load** and `launches` increments from whatever arrived, so the
list's length is the number of loads since the table last came back. One entry, on a client whose
file already held an earlier session's data — the 2026-09-21 measurement read it, and the client
only writes this file at logout. So the addon saw *nothing* at load.

That also rules out the trap this section warns about: `/reload` and a relog to character select
both hand the table back in-process, so either would have left **two** stamps. One stamp is a real
process start with no load-back.

Corroborated in the same session by two other addons, tied to it by the stamps rather than by
sitting in one file — `SavedVariables/AltStableProbe.lua` has `loadCount = 1` at `11:00:10`, and
`SavedVariables/Priestly.lua` has `svLoadCheck = { build = "69977", stamp = "…11:00:10" }`, which
is what dates the measurement to **this build**.

`SV_BROKEN_ON_BUILD` rests on this, not on the API dumps matching — a dump lists the same symbols
whether or not the client reads the file back. `MEASURED_ON_BUILD` is a different question and
stays at 69913 until `/pprobe` is re-run here: identical declarations cannot show that aura
secrecy or secure click casting still behave the same way.

**How the earlier wrong answer happened, because it will happen again.** Persistence was checked by
reading the saved file. That file looks fully populated whether or not the load ran, because
`Priestly_EnsureDefaults` rewrites every `DEFAULTS` key at login and `learnedDurations` / `flavor`
are rebuilt from runtime state. Only a key absent from `DEFAULTS` can show the failure. `pos` is the
only such key in this addon, and it is precisely the one that kept disappearing — reported twice by
the user before it was believed.

Verify persistence by **counting launches inside the addon**, never by reading the file.

**Only the account-scoped folders are affected.** Reported on the Blizzard forums
([UI/Addon settings wiped on client restart](https://us.forums.blizzard.com/en/wow/t/uiaddon-settings-wiped-on-client-restart/2353992/15),
same build, no Blizzard reply as of 2026-09-21) and matched on this install: the machine-level
`WTF\SavedVariables\` holds only Blizzard's own login-screen files (`Blizzard_AddOnList`,
`Blizzard_Console`, `Blizzard_GlueSavedVariables`), and those persist. Everything under
`WTF\Account\<id>\` - account-wide and per-character alike - is lost. Addon SavedVariables
always land under the account folder, so this narrows the bug without offering a workaround.

### CVars do not persist — the earlier "measured" result was a `/reload` artefact

An earlier version of this section reported `/pprobe cvar` counting 1 → 2 → 3 and concluded CVars
were a working store. **Every one of those readings was taken across `/reload`**, which keeps the
client process alive — a CVar set last session is still in memory and reads back as though it had
persisted.

After a **full client exit** on this build, the client rewrote `Config.wtf` and both
`config-cache.wtf` files without the addon's CVar, and `GetCVar` returned `nil` on relaunch.
Measured in AltStable (PR #33 there). Nothing an addon writes survives a real restart.

The SavedVariables result in the section above still stands: SavedVariables are re-read from disk on
`/reload`, so "nothing loads even across `/reload`" is a valid negative. The rule that follows:
**`/reload` can prove something is broken, never that it works.** Confirm any persistence claim with
a full exit and relaunch.

`/pprobe cvar` and `/pprobe sv` are kept, and neither guesses how the session started. When a value
comes back they call it inconclusive if the user only did a `/reload`, and confirmed if they did a
full exit and relaunch. That keeps them able to recognise Blizzard's fix when it lands.

## 12. Instances

Measured with `/pprobe here`, standing inside:

| Instance | `GetInstanceInfo()` name | `instanceMapID` | type | players |
|---|---|---|---|---|
| Ruins of Lordaeron | `Ruins of Lordaeron` | **2999** | `party` | 5 |

`GetRealZoneText()` and `GetZoneText()` both agree with the instance name here, and
`GetSubZoneText()` is empty.

Two things follow. The name matches the list exactly, so that key is confirmed. And the map ID is a
real number for the first time — 2999 is well outside the Vanilla range, which is expected for
Forever's own content and is why hardcoding Classic IDs would not have worked either. Issue #12
covers matching on it.

The encounter journal is not a usable source on this client: `EJ_GetNumTiers()` returns **0** while
`EJ_GetInstanceByIndex` works. Anything enumerating tiers first finds nothing.

## 13. A frame that parents secure buttons cannot be touched in combat

Measured in game on 2026-09-22, build 69913, with BugGrabber watching.

Priestly's window is a plain `Frame` whose children are `SecureActionButtonTemplate` buttons. That
makes the parent **protected**: in combat the client refuses to hide it, move it, re-anchor it,
unclamp it, or stop a drag on it. The refusal is not a Lua error. The call does nothing, and an
`ADDON_ACTION_BLOCKED` is raised naming *whichever addon's taint the call path happens to carry* -
in the capture below, an unrelated addon - so the code that actually made the call only shows up in
the stack:

```
AddOn 'AltStable' tried to call the protected function 'Frame:SetClampedToScreen()'.
[C]: in function 'SetClampedToScreen'
[Priestly/Libs/LibGroupBuffs-1.0/UI.lua]:172: in function <...UI.lua:170>   -- CombatPark
[Priestly/Libs/LibGroupBuffs-1.0/UI.lua]:1059: in function <...UI.lua:1056> -- Close

AddOn 'AltStable' tried to call the protected function 'Frame:StopMovingOrSizing()'.
[C]: in function 'StopMovingOrSizing'
[Priestly/Libs/LibGroupBuffs-1.0/UI.lua]:763                                -- DragStop
```

**So "park it offscreen instead of hiding it" does not work here.** That workaround - drop the
screen clamp, set alpha 0, re-anchor far off screen - was in Priestly from the Forever port
onwards and is in every release up to v2.0.5. It was blocked at its first call, silently, and
nothing on screen said so. It only surfaced when somebody finally closed the window mid-fight with
an error display running.

What works instead: do nothing while locked down, and do it on `PLAYER_REGEN_ENABLED`. The rows
stay on screen for the rest of the fight, which is when they are worth having anyway. The library
does this from r7: `Close`, `ResetPosition` and `DragStop` record what was asked for and return,
`OnCombatEnd` carries it out, and `ui:Close()` returns false so the addon can say "when combat
ends".

A drag that combat interrupts keeps following the cursor until the fight ends, because the release
is blocked too. Nothing can be done about that from an addon.

## 14. Still open

- **Clicking in combat.** Casting works out of combat on both self and another player, and the
  rows still cast during a fight (measured 2026-09-22); what is unverified is a wired unit token
  changing hands mid-fight.
- **`ActionButtonUseKeyHeldSpell`**, and whether a live mouse click is CVar-gated — see the end of
  section 1. `/pprobe secure`.
- **`INSTANCE_DB` names** against real `GetInstanceInfo()` output, once those zones are reachable.
