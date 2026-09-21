------------------------------------------------------------
-- test_availability.lua - which buffs get a row, and what a click casts.
--
-- The current Forever beta caps at level 20, so a priest knows Power Word:
-- Fortitude and none of the group "Prayer of X" spells. Wiring a row to a
-- Prayer that does not exist is a dead click, and that is exactly what the TBC
-- code did for Fortitude (it was flagged `always = true` and skipped the
-- known-spell check entirely).
--
--   & 'C:\Program Files (x86)\Lua\5.1\lua.exe' tests\test_availability.lua
------------------------------------------------------------

dofile("tests/wow_stubs.lua")
local H = dofile("tests/harness.lua")
local T, TC = H.loadAddon()

local function defById(id)
    for _, d in ipairs(T.DEFS) do
        if d.id == id then return d end
    end
end

local function ids(defs)
    local out = {}
    for _, d in ipairs(defs) do out[#out + 1] = d.id end
    return table.concat(out, ",")
end

local function setup(known)
    WoW.reset()
    PriestlyDB = nil
    Priestly_EnsureDefaults()
    H.TeachSpells(known)
    T.RefreshSpellData()
end

------------------------------------------------------------
-- A level-20 priest: single-target Fortitude only
------------------------------------------------------------

setup({ "FORT_SINGLE" })

local fort = defById("fort")
H.check(fort.hasSingle == true, "Power Word: Fortitude is known")
H.check(fort.hasGroup == false, "Prayer of Fortitude is not")
H.eq(ids(T.ActiveDefs({}, {})), "fort", "only the buff we can actually cast gets a row")

local primary, secondary = T.ClickSpells(fort)
H.eq(primary, "Power Word: Fortitude",
    "left-click falls back to the single-target spell - never a dead primary click")
H.eq(secondary, "Power Word: Fortitude", "right-click is the same spell here")

------------------------------------------------------------
-- Prayer learned: left-click becomes the group spell
------------------------------------------------------------

setup({ "FORT_SINGLE", "FORT_GROUP" })
fort = defById("fort")
H.check(fort.hasGroup == true, "Prayer of Fortitude is known now")
primary, secondary = T.ClickSpells(fort)
H.eq(primary, "Prayer of Fortitude", "left-click prefers the group Prayer")
H.eq(secondary, "Power Word: Fortitude", "right-click stays single-target")

------------------------------------------------------------
-- The Divine Spirit gate: knowing EITHER form is enough
--
-- The original bug: the Spirit row only appeared if the player knew the group
-- spell, so a priest with Divine Spirit and no Prayer of Spirit saw nothing.
------------------------------------------------------------

setup({ "FORT_SINGLE", "SPIRIT_SINGLE" })
H.eq(ids(T.ActiveDefs({}, {})), "fort,spirit",
    "Divine Spirit alone is enough for a Spirit row")
primary, secondary = T.ClickSpells(defById("spirit"))
H.eq(primary, "Divine Spirit", "and it casts the single-target form")

setup({ "FORT_SINGLE", "SPIRIT_GROUP" })
H.eq(ids(T.ActiveDefs({}, {})), "fort,spirit",
    "Prayer of Spirit alone is also enough")
primary, secondary = T.ClickSpells(defById("spirit"))
H.eq(primary, "Prayer of Spirit", "left-click casts the group form")
H.eq(secondary, "Prayer of Spirit",
    "right-click falls back to the group form when there is no single-target one")

------------------------------------------------------------
-- Knowing nothing means no row at all
------------------------------------------------------------

setup({})
H.eq(ids(T.ActiveDefs({}, {})), "", "a priest who knows none of them gets no rows")

------------------------------------------------------------
-- The config toggle layers on top of availability, not instead of it
------------------------------------------------------------

setup({ "FORT_SINGLE", "SPIRIT_SINGLE" })
PriestlyDB.trackSpirit = false
H.eq(ids(T.ActiveDefs({}, {})), "fort", "untracking Spirit removes its row")
PriestlyDB.trackSpirit = true
PriestlyDB.trackFort = false
H.eq(ids(T.ActiveDefs({}, {})), "spirit", "untracking Fortitude removes its row too")
PriestlyDB.trackFort = true

------------------------------------------------------------
-- Shadow Protection visibility modes
------------------------------------------------------------

setup({ "FORT_SINGLE", "SHADOW_SINGLE" })

PriestlyDB.shadowMode = "always"
H.eq(ids(T.ActiveDefs({}, {})), "fort,shadow", "'always' shows it")

PriestlyDB.shadowMode = "detect"
WoW.SetUnit("party1", { name = "Karuzo Elegia" })
local groups = { [1] = { { unit = "party1", name = "Karuzo Elegia" } } }
H.eq(ids(T.ActiveDefs(groups, { 1 })), "fort", "'detect' hides it when nobody has it")
WoW.SetAura("party1", "Shadow Protection", 600, 300)
H.eq(ids(T.ActiveDefs(groups, { 1 })), "fort,shadow",
    "'detect' shows it once a group member has the aura")
WoW.ClearAuras("party1")
WoW.SetAura("party1", "Prayer of Shadow Protection", 600, 300)
H.eq(ids(T.ActiveDefs(groups, { 1 })), "fort,shadow", "the Prayer form counts too")

PriestlyDB.shadowMode = "instance"
WoW.instanceName = "Stratholme"
PriestlyDB.shadowInstances["Stratholme"] = true
TC.CheckCurrentInstance()
H.eq(ids(T.ActiveDefs({}, {})), "fort,shadow", "'instance' shows it in a checked instance")
PriestlyDB.shadowInstances["Stratholme"] = false
TC.CheckCurrentInstance()
H.eq(ids(T.ActiveDefs({}, {})), "fort", "and hides it in an unchecked one")

-- Availability still wins: not knowing Shadow Protection beats every mode.
setup({ "FORT_SINGLE" })
PriestlyDB.shadowMode = "always"
H.eq(ids(T.ActiveDefs({}, {})), "fort",
    "'always' cannot conjure a row for a spell the priest does not have")

------------------------------------------------------------
-- Localized names come from the client, not from our literals
------------------------------------------------------------

WoW.reset()
PriestlyDB = nil
Priestly_EnsureDefaults()
WoW.DefineSpell(1243, "Machtwort: Seelenstaerke")
WoW.Know(1243, "Machtwort: Seelenstaerke")
T.RefreshSpellData()
H.eq(defById("fort").sngl, "Machtwort: Seelenstaerke",
    "the name is whatever the client says, not the enUS literal")
H.eq(defById("fort").names[1], "Machtwort: Seelenstaerke",
    "and the aura lookup uses that name")

H.done("test_availability")
