------------------------------------------------------------
-- test_clicks.lua - what the secure buttons are actually wired to after a
-- rebuild.
--
-- This is the part that has to be right: a row whose spell1 attribute names a
-- Prayer the priest does not have is a click that does nothing, and the frame
-- gives no hint of it. Asserting the attributes is the closest we can get to
-- clicking without a game client.
--
--   & 'C:\Program Files (x86)\Lua\5.1\lua.exe' tests\test_clicks.lua
------------------------------------------------------------

dofile("tests/wow_stubs.lua")
local H = dofile("tests/harness.lua")
local T, TC = H.loadAddon()

local function setup(known)
    WoW.reset()
    PriestlyDB = nil
    Priestly_EnsureDefaults()
    PriestlyDB.shadowMode = "never"
    H.TeachSpells(known)
    T.RefreshSpellData()

    WoW.SetUnit("player", { name = "Karuzo Elegia", guid = "P0", class = "PRIEST" })
    WoW.SetUnit("party1", { name = "Sten Thornbeard", guid = "P1", class = "WARRIOR" })
    WoW.SetUnit("party2", { name = "Mirel Dawnsong", guid = "P2", class = "MAGE" })
    WoW.groupMembers = 3
    T.UpdateUI()
    return T.rows()
end

local function activeRows(rows)
    local out = {}
    for _, r in ipairs(rows) do
        if r._active then out[#out + 1] = r end
    end
    return out
end

------------------------------------------------------------
-- Level 20: only Power Word: Fortitude exists
------------------------------------------------------------

local rows = setup({ "FORT_SINGLE" })
local active = activeRows(rows)
H.eq(#active, 1, "one row: the one buff this priest has")

local row = active[1]
H.eq(row:GetAttribute("type1"), "spell", "left-click casts a spell")
H.eq(row:GetAttribute("spell1"), "Power Word: Fortitude",
    "left-click falls back to the single-target spell, never a Prayer that does not exist")
H.eq(row:GetAttribute("spell2"), "Power Word: Fortitude", "right-click likewise")
H.check(row:GetAttribute("unit1") ~= nil, "and it has somebody to cast on")

-- Everyone is unbuffed, so both clicks should aim at a real group member.
local u1 = row:GetAttribute("unit1")
H.check(u1 == "player" or u1 == "party1" or u1 == "party2",
    "the target is a group member, got " .. tostring(u1))

------------------------------------------------------------
-- The target follows who is actually missing the buff
------------------------------------------------------------

rows = setup({ "FORT_SINGLE" })
WoW.SetAura("player", "Power Word: Fortitude", 3600, 3000)
WoW.SetAura("party1", "Power Word: Fortitude", 3600, 3000)
T.UpdateUI()
row = activeRows(T.rows())[1]
H.eq(row:GetAttribute("unit2"), "party2", "right-click aims at the one missing it")
H.eq(row:GetAttribute("unit1"), "party2",
    "and so does left-click while there is no group Prayer")

------------------------------------------------------------
-- With the Prayer learned, left-click becomes the group cast
------------------------------------------------------------

rows = setup({ "FORT_SINGLE", "FORT_GROUP" })
row = activeRows(rows)[1]
H.eq(row:GetAttribute("spell1"), "Prayer of Fortitude", "left-click is the group Prayer")
H.eq(row:GetAttribute("spell2"), "Power Word: Fortitude", "right-click stays single-target")

------------------------------------------------------------
-- Nobody valid to cast on: clear the spell rather than cast on yourself
------------------------------------------------------------

rows = setup({ "FORT_SINGLE" })
WoW.units.player.dead = true
WoW.units.party1.dead = true
WoW.units.party2.connected = false
T.UpdateUI()
row = activeRows(T.rows())[1]
H.check(row:GetAttribute("spell1") == nil,
    "no valid target -> no spell on left-click, instead of buffing a corpse")
H.check(row:GetAttribute("spell2") == nil, "same for right-click")

------------------------------------------------------------
-- PreClick re-picks the target at click time
------------------------------------------------------------

rows = setup({ "FORT_SINGLE" })
WoW.SetAura("player", "Power Word: Fortitude", 3600, 3000)
WoW.SetAura("party1", "Power Word: Fortitude", 3600, 3000)
WoW.SetAura("party2", "Power Word: Fortitude", 3600, 3000)
T.UpdateUI()
row = activeRows(T.rows())[1]

-- Everyone is buffed at rebuild time; party1's falls off a moment later.
WoW.ClearAuras("party1")
row._scripts.PreClick(row, "RightButton")
H.eq(row:GetAttribute("unit2"), "party1",
    "PreClick re-aims at whoever lost the buff since the last rebuild")

-- In combat PreClick must not touch attributes (SetAttribute is refused under
-- lockdown anyway) - it should bail without error.
WoW.inCombat = true
WoW.ClearAuras("party2")
row._scripts.PreClick(row, "RightButton")
H.eq(row:GetAttribute("unit2"), "party1", "in combat the wiring is left alone")
WoW.inCombat = false

------------------------------------------------------------
-- A button PreClick disarmed must re-arm itself
--
-- PreClick cleared the spell when nobody was valid, then on the next click
-- wrote only the unit - leaving the spell nil. So the first click after
-- somebody became valid again did nothing at all: no cast, no error, exactly
-- the complaint that started #17. PostClick would fix it afterwards, so the
-- SECOND click worked, which is the kind of thing a user reports as "it
-- works sometimes".
------------------------------------------------------------

rows = setup({ "FORT_SINGLE" })
row = activeRows(rows)[1]

WoW.units.player.dead = true
WoW.units.party1.dead = true
WoW.units.party2.dead = true
row._scripts.PreClick(row, "RightButton")
H.check(row:GetAttribute("spell2") == nil, "nobody valid disarms the button")

-- Somebody comes back, without a rebuild.
WoW.units.party1.dead = false
row._scripts.PreClick(row, "RightButton")
H.eq(row:GetAttribute("unit2"), "party1", "the next click retargets to them")
H.eq(row:GetAttribute("spell2"), "Power Word: Fortitude",
    "and re-arms the spell, so that click actually casts")

-- Left-click takes the same path.
WoW.units.party1.dead = true
row._scripts.PreClick(row, "LeftButton")
H.check(row:GetAttribute("spell1") == nil, "left-click disarms too")
WoW.units.party1.dead = false
row._scripts.PreClick(row, "LeftButton")
H.eq(row:GetAttribute("spell1"), "Power Word: Fortitude", "and re-arms")

-- Range is NOT what disarms a row, which is easy to assume and wrong:
-- PickTarget makes a second pass ignoring range, so an out-of-range member is
-- still a target. Only an invalid one - dead, offline, gone - gives nil.
rows = setup({ "FORT_SINGLE" })
row = activeRows(rows)[1]
WoW.range.player  = false
WoW.range.party1  = false
WoW.range.party2  = false
row._scripts.PreClick(row, "RightButton")
H.eq(row:GetAttribute("spell2"), "Power Word: Fortitude",
    "everyone out of range keeps the button armed")
H.check(row:GetAttribute("unit2") ~= nil, "and still aimed at somebody")
WoW.range.player, WoW.range.party1, WoW.range.party2 = nil, nil, nil

------------------------------------------------------------
-- PostClick restores anything PreClick cleared
------------------------------------------------------------

rows = setup({ "FORT_SINGLE", "FORT_GROUP" })
row = activeRows(rows)[1]
row:SetAttribute("spell1", nil)
row:SetAttribute("spell2", nil)
row._scripts.PostClick(row, "LeftButton")
H.eq(row:GetAttribute("spell1"), "Prayer of Fortitude", "spell1 is restored")
H.eq(row:GetAttribute("spell2"), "Power Word: Fortitude", "spell2 is restored")

------------------------------------------------------------
-- Popover rows
------------------------------------------------------------

rows = setup({ "FORT_SINGLE" })
row = activeRows(rows)[1]
local members = {
    { unit = "player",  name = "Karuzo Elegia",   class = "PRIEST" },
    { unit = "party1",  name = "Sten Thornbeard", class = "WARRIOR" },
}
T.UpdatePopover(row, members, row._def)
local prs = T.popRows()
H.check(prs[1]._active, "the popover has a row per member")
H.eq(prs[1]:GetAttribute("unit1"), "player", "each row targets its own member")
H.eq(prs[2]:GetAttribute("unit1"), "party1", "...the second one too")
H.eq(prs[1]:GetAttribute("spell1"), "Power Word: Fortitude",
    "with no Prayer known, the popover's left-click is single-target")
H.check(prs[3]._active == false, "unused rows are released")

------------------------------------------------------------
-- Two buffs, two rows
------------------------------------------------------------

rows = setup({ "FORT_SINGLE", "SPIRIT_SINGLE" })
active = activeRows(rows)
H.eq(#active, 2, "one row per buff")
H.eq(active[1]:GetAttribute("spell1"), "Power Word: Fortitude", "first row is Fortitude")
H.eq(active[2]:GetAttribute("spell1"), "Divine Spirit", "second row is Spirit")

------------------------------------------------------------
-- Both mouse edges, on every button in both pools
--
-- "Single click does nothing" was this: the rows were registered for the
-- mouse button going DOWN only. The client's secure handler performs the
-- action when `down == useOnKeyDown`, and useOnKeyDown follows the
-- ActionButtonUseKeyDown CVar - so on a client set to act on release the
-- handler rejected the only edge we had asked for. No cast, no error.
--
-- Registering both edges hands the choice back to the handler, which takes
-- exactly one of them. It cannot fall out of step with the CVar, including
-- mid-fight when RegisterForClicks is protected and we could not re-register
-- even if we noticed.
------------------------------------------------------------

local function clicksOf(button)
    local set = {}
    for _, e in ipairs(button._clicks or {}) do set[e] = true end
    return set
end

setup({ "FORT_SINGLE" })

local EXPECTED = { "LeftButtonDown", "RightButtonDown", "LeftButtonUp", "RightButtonUp" }

local function assertBothEdges(button, what)
    local set = clicksOf(button)
    H.eq(#(button._clicks or {}), 4, what .. " registers four click events")
    for _, e in ipairs(EXPECTED) do
        H.check(set[e], what .. " registers " .. e)
    end
end

assertBothEdges(T.rows()[1], "the first row")
assertBothEdges(T.rows()[#T.rows()], "the last row in the pool")
assertBothEdges(T.popRows()[1], "the first popover row")
assertBothEdges(T.popRows()[#T.popRows()], "the last popover row")

-- Nothing re-registers later, so there is no combat-deferral hole to test and
-- no CVAR_UPDATE handler to keep in step. Guard that it stays that way: a
-- future edit that reintroduces conditional registration has to come back here
-- and read why it was removed.
H.check(WoW.events[T.eventFrame()].CVAR_UPDATE == nil,
    "no CVAR_UPDATE handler - the registration is unconditional")

WoW.inCombat = true
WoW.dispatch("PLAYER_REGEN_ENABLED")
WoW.inCombat = false
assertBothEdges(T.rows()[1], "after a combat cycle the first row still")

------------------------------------------------------------
-- Which side the popover opens on
--
-- It was hard-anchored to the left of its row, so a frame parked on the left
-- of the screen - where Pally Power sits, and therefore where a Pally Power
-- user puts this - opened its popover off-screen, taking per-member click
-- casting with it. SetClampedToScreen hid how bad it was by dragging the
-- remains back on.
------------------------------------------------------------

setup({ "FORT_SINGLE" })
local anchor = T.rows()[1]
WoW.screenWidth = 1920

PriestlyDB.popoverSide = "auto"
WoW.centers[anchor] = 200
H.eq(T.PopoverSide(anchor), "right", "a frame on the left opens the popover to the right")
WoW.centers[anchor] = 1700
H.eq(T.PopoverSide(anchor), "left", "and a frame on the right opens it to the left")

-- The frame is draggable, so the side has to be decided per open, not once.
WoW.centers[anchor] = 300
H.eq(T.PopoverSide(anchor), "right", "dragging it across the screen flips the side")

-- Explicit settings win over the geometry.
PriestlyDB.popoverSide = "left"
H.eq(T.PopoverSide(anchor), "left", "'always left' overrides a frame on the left")
PriestlyDB.popoverSide = "right"
WoW.centers[anchor] = 1700
H.eq(T.PopoverSide(anchor), "right", "'always right' overrides a frame on the right")

-- Unknown geometry falls back to the old behaviour rather than guessing.
-- GetCenter is nil before layout, and screen width is 0 mid UI-scale change -
-- which is TRUTHY in Lua and would otherwise sail through an `or` guard.
PriestlyDB.popoverSide = "auto"
WoW.centers[anchor] = nil
H.eq(T.PopoverSide(anchor), "left", "an unplaced row falls back to the left")
WoW.centers[anchor] = 200
WoW.screenWidth = 0
H.eq(T.PopoverSide(anchor), "left", "and so does a zero-width screen, which is truthy")
WoW.screenWidth = 1920

------------------------------------------------------------
-- ...and the popover is actually anchored that way
------------------------------------------------------------

local members = { { unit = "player", name = "Karuzo Elegia", class = "PRIEST" } }
local pop = T.popFrame()

WoW.centers[anchor] = 200
T.UpdatePopover(anchor, members, anchor._def)
local point, _, relPoint = pop:GetPoint()
H.eq(point .. "/" .. relPoint, "LEFT/RIGHT",
    "on the left of the screen the popover hangs off the row's right edge")

WoW.centers[anchor] = 1700
T.UpdatePopover(anchor, members, anchor._def)
point, _, relPoint = pop:GetPoint()
H.eq(point .. "/" .. relPoint, "RIGHT/LEFT", "and off its left edge on the right")

------------------------------------------------------------
-- Click hints
--
-- The point of these is that the mapping is NOT fixed: with no group Prayer
-- known, left-click casts the single spell. A static "left is group, right is
-- single" would be a lie for the whole current level range, and acting on it
-- burns a reagent. So the hint is read from the attributes the buttons were
-- wired with, and the tests check it says what a click would actually do.
------------------------------------------------------------

-- Clear first, and mean it. The previous version set a field nothing reads,
-- so an early return in ShowClickHint would have been scored against the
-- PREVIOUS hover's text and every assertion here would still have passed.
local function hintFor(row)
    WoW.clearTooltip()
    row._scripts.OnEnter(row)
    return WoW.tooltipText()
end

-- Prove the clear works, or none of the assertions below mean anything.
WoW.clearTooltip()
H.eq(WoW.tooltipText(), "", "the tooltip starts empty between hovers")

-- Level 20: no Prayer exists, so BOTH buttons are single-target.
rows = setup({ "FORT_SINGLE" })
row = activeRows(rows)[1]
local hint = hintFor(row)
H.check(hint:find("Power Word: Fortitude"), "the hint names the spell, got: " .. hint)
H.check(not hint:find("Prayer"), "and never names a Prayer this priest cannot cast: " .. hint)
H.check(hint:find("Left") and hint:find("Right"), "with a line per mouse button: " .. hint)

-- With the Prayer known, left-click changes meaning - and the hint follows.
rows = setup({ "FORT_SINGLE", "FORT_GROUP" })
row = activeRows(rows)[1]
hint = hintFor(row)
H.check(hint:find("Prayer of Fortitude"), "left-click now reads as the group Prayer: " .. hint)
H.check(hint:find("Power Word: Fortitude"), "with right-click still single-target: " .. hint)
H.check(hint:find("your party"), "and the group cast names the group, not one member: " .. hint)

-- The single-target line names who it would land on, which is the part that
-- tells you whether the click is about to do what you meant.
H.check(hint:find("Karuzo Elegia") or hint:find("Sten Thornbeard") or hint:find("Mirel Dawnsong"),
    "the single buff names its target: " .. hint)

-- Nobody valid: say so rather than naming a spell that will not fire.
rows = setup({ "FORT_SINGLE" })
WoW.units.player.dead = true
WoW.units.party1.dead = true
WoW.units.party2.connected = false
T.UpdateUI()
row = activeRows(T.rows())[1]
hint = hintFor(row)
H.check(hint:find("nothing to buff"), "a row with no valid target says so: " .. hint)

-- Off by preference.
rows = setup({ "FORT_SINGLE" })
row = activeRows(rows)[1]
PriestlyDB.showClickHints = false
H.eq(hintFor(row), "", "turning hints off shows nothing")
PriestlyDB.showClickHints = true

-- Leaving the row drops the tooltip. The popover has its own polling hide, so
-- this must not be the thing that closes it.
row._scripts.OnEnter(row)
H.check(WoW.tooltipText() ~= "", "hovering shows it again")
row._scripts.OnLeave(row)
H.eq(WoW.tooltipText(), "", "and leaving hides it")
H.check(T.popFrame():IsShown(), "without closing the popover")

------------------------------------------------------------
-- The hint must name whoever the click will ACTUALLY buff
--
-- The wired attributes are only the answer in combat. Out of combat PreClick
-- calls PickTarget again at click time, so a hover between a rebuild and a
-- buff falling off named one person while the click buffed another - the hint
-- lying about the one thing it exists to state.
------------------------------------------------------------

rows = setup({ "FORT_SINGLE" })
WoW.SetAura("player", "Power Word: Fortitude", 3600, 3000)
WoW.SetAura("party1", "Power Word: Fortitude", 3600, 3000)
WoW.SetAura("party2", "Power Word: Fortitude", 3600, 3000)
T.UpdateUI()
row = activeRows(T.rows())[1]

-- Everybody was buffed at rebuild time. Now party1's falls off.
WoW.ClearAuras("party1")
hint = hintFor(row)
H.check(hint:find("Sten Thornbeard"),
    "the hint re-picks, naming whoever lost the buff since the rebuild: " .. hint)

-- ...and that is the same person the click lands on.
row._scripts.PreClick(row, "RightButton")
H.eq(row:GetAttribute("unit2"), "party1", "which is exactly who PreClick retargets to")

-- Range moves without a rebuild too.
rows = setup({ "FORT_SINGLE" })
T.UpdateUI()
row = activeRows(T.rows())[1]
-- Unset range is UNKNOWN, not in-range, and PickTarget only prefers a
-- confirmed IN_RANGE - so party2 has to be stated, not left to default.
WoW.range.player = false
WoW.range.party1 = false
WoW.range.party2 = true
hint = hintFor(row)
H.check(hint:find("Mirel Dawnsong"),
    "and it follows range, which never triggers a rebuild: " .. hint)
WoW.range.player, WoW.range.party1, WoW.range.party2 = nil, nil, nil

-- In combat PreClick cannot rewrite anything, so there the wired attributes
-- ARE what the click will use and re-picking would be the thing that lies.
rows = setup({ "FORT_SINGLE" })
WoW.SetAura("player", "Power Word: Fortitude", 3600, 3000)
WoW.SetAura("party1", "Power Word: Fortitude", 3600, 3000)
T.UpdateUI()
row = activeRows(T.rows())[1]
local wiredUnit = row:GetAttribute("unit2")
H.eq(wiredUnit, "party2", "wired at rebuild to the one missing it")
WoW.inCombat = true
WoW.SetAura("party2", "Power Word: Fortitude", 3600, 3000)
WoW.ClearAuras("player")
hint = hintFor(row)
H.check(hint:find("Mirel Dawnsong"),
    "in combat the hint reports the wired target, not a fresh pick: " .. hint)
WoW.inCombat = false

------------------------------------------------------------
-- A Prayer on BOTH buttons must not be described as single-target
--
-- ClickSpells hands the group spell to both clicks when the priest knows a
-- Prayer but not the single form. Calling right-click "Prayer of Spirit on
-- Sten Thornbeard" is the exact mistake this tooltip exists to prevent - the
-- player casts it expecting one person and spends a reagent on the group.
------------------------------------------------------------

rows = setup({ "SPIRIT_GROUP" })
row = activeRows(rows)[1]
H.eq(row:GetAttribute("spell2"), "Prayer of Spirit", "right-click really does carry the Prayer")
hint = hintFor(row)
H.check(not hint:find("Prayer of Spirit on Karuzo Elegia"),
    "so it is not described as landing on one person: " .. hint)
H.eq(select(2, hint:gsub("your party", "")), 2,
    "both lines name the group, because both clicks cast the group spell: " .. hint)

------------------------------------------------------------
-- Group naming
------------------------------------------------------------

H.eq(T.GroupLabel(nil), "this group", "an unknown group still reads as something")
WoW.inRaid = true
H.eq(T.GroupLabel(3), "group 3", "raid groups are numbered")
WoW.inRaid = false
H.eq(T.GroupLabel(1), "your party", "and a party is a party")

-- Pet buckets are a display grouping, not a subgroup: a Prayer cast on a pet
-- buffs whatever party that pet is in, so there is no "the pets" to name.
H.eq(T.GroupLabel(99), nil, "the pet bucket names no group")
H.eq(T.GroupLabel(103), nil, "nor do the later pet buckets")

------------------------------------------------------------
-- In combat the hint lists who still needs the buff
--
-- The popover cannot open then - it parents secure buttons - so this is the
-- only way to see who is missing it mid-fight. Wired through Priestly's own
-- rows and definitions.
------------------------------------------------------------

rows = setup({ "FORT_SINGLE" })
WoW.SetAura("player", "Power Word: Fortitude", 3600, 1500)
T.UpdateUI()
row = activeRows(T.rows())[1]

WoW.inCombat = true
WoW.clearTooltip()
T.ShowClickHint(row)
local combatHint = WoW.tooltipText()
H.check(combatHint:find("Needs it"), "the hint lists them in combat: " .. combatHint)
H.check(combatHint:find("Sten Thornbeard") and combatHint:find("MISS"),
    "naming who is missing Fortitude: " .. combatHint)
H.check(not combatHint:find("Karuzo Elegia  24", 1, true),
    "and leaving out the one who has it")
WoW.inCombat = false

WoW.clearTooltip()
T.ShowClickHint(row)
H.check(not WoW.tooltipText():find("Needs it"),
    "out of combat the popover shows it instead: " .. WoW.tooltipText())

H.done("test_clicks")
