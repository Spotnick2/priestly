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

H.done("test_clicks")
