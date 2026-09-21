------------------------------------------------------------
-- test_roster.lua - GatherGroups: solo, party, raid, pets, and the
-- Forever surname showing up in the names we draw.
--
--   & 'C:\Program Files (x86)\Lua\5.1\lua.exe' tests\test_roster.lua
------------------------------------------------------------

dofile("tests/wow_stubs.lua")
local H = dofile("tests/harness.lua")
local T, TC = H.loadAddon()

local function setup()
    WoW.reset()
    PriestlyDB = nil
    Priestly_EnsureDefaults()
    H.TeachSpells({ "FORT_SINGLE" })
    T.RefreshSpellData()
end

local function names(list)
    local out = {}
    for _, m in ipairs(list or {}) do out[#out + 1] = m.name end
    return table.concat(out, ",")
end

------------------------------------------------------------
-- Solo
------------------------------------------------------------

setup()
WoW.SetUnit("player", { name = "Karuzo Elegia", class = "PRIEST" })

local groups, ord = T.GatherGroups()
H.eq(#ord, 0, "ungrouped and solo mode off -> nothing to draw")

PriestlyDB.showSolo = true
groups, ord = T.GatherGroups()
H.eq(#ord, 1, "solo mode draws one group")
H.eq(names(groups[1]), "Karuzo Elegia", "which is just the player, surname included")

------------------------------------------------------------
-- Party
------------------------------------------------------------

setup()
WoW.SetUnit("player", { name = "Karuzo Elegia", class = "PRIEST" })
WoW.SetUnit("party1", { name = "Sten Thornbeard", class = "WARRIOR" })
WoW.SetUnit("party2", { name = "Mirel Dawnsong", class = "MAGE" })
WoW.groupMembers = 3

groups, ord = T.GatherGroups()
H.eq(#ord, 1, "a party is one group")
H.eq(names(groups[1]), "Karuzo Elegia,Sten Thornbeard,Mirel Dawnsong",
    "player first, then party members, all with surnames")
H.eq(groups[1][2].class, "WARRIOR", "classes come along for the icon and colour")

------------------------------------------------------------
-- Raid: subgroups, and two characters sharing a first name
------------------------------------------------------------

setup()
WoW.inRaid = true
WoW.groupMembers = 4
WoW.raidRoster = {
    { name = "Karuzo Elegia",     subgroup = 1 },
    { name = "Karuzo Mistwalker", subgroup = 1 },
    { name = "Sten Thornbeard",   subgroup = 2 },
    { name = "Mirel Dawnsong",    subgroup = 2 },
}
WoW.SetUnit("raid1", { name = "Karuzo Elegia",     guid = "P1", class = "PRIEST" })
WoW.SetUnit("raid2", { name = "Karuzo Mistwalker", guid = "P2", class = "PRIEST" })
WoW.SetUnit("raid3", { name = "Sten Thornbeard",   guid = "P3", class = "WARRIOR" })
WoW.SetUnit("raid4", { name = "Mirel Dawnsong",    guid = "P4", class = "MAGE" })

groups, ord = T.GatherGroups()
H.eq(#ord, 2, "two subgroups")
H.eq(ord[1], 1, "sorted ascending")
H.eq(names(groups[1]), "Karuzo Elegia,Karuzo Mistwalker",
    "both Karuzos are listed, told apart only by surname")
H.eq(names(groups[2]), "Sten Thornbeard,Mirel Dawnsong", "subgroup 2")

------------------------------------------------------------
-- Pets go last, in their own group, and can be turned off
------------------------------------------------------------

setup()
WoW.SetUnit("player", { name = "Karuzo Elegia", class = "PRIEST" })
WoW.SetUnit("party1", { name = "Sten Thornbeard", class = "HUNTER" })
WoW.SetUnit("partypet1", { name = "Broll" })
WoW.groupMembers = 2

groups, ord = T.GatherGroups()
H.eq(#ord, 2, "a pet adds a group")
H.eq(ord[2], 99, "and it sorts to the bottom")
H.eq(names(groups[99]), "Broll", "the pet is in it")
H.eq(groups[99][1].class, "PET_HUNTER", "with an owner-appropriate icon key")

PriestlyDB.trackPets = false
groups, ord = T.GatherGroups()
H.eq(#ord, 1, "pet tracking off removes the pet group")

------------------------------------------------------------
-- Names are for display; identity is the GUID
------------------------------------------------------------

setup()
WoW.SetUnit("raid1", { name = "Karuzo Elegia",     guid = "P1" })
WoW.SetUnit("raid2", { name = "Karuzo Mistwalker", guid = "P2" })
local API = Priestly.API
H.check(API.UnitKey("raid1") ~= API.UnitKey("raid2"),
    "same first name, different GUID - never key a cache on the name")

------------------------------------------------------------
-- The worst roster the addon can produce must still fit
--
-- Rows and headers are allocated once, so the pool has to cover a full raid
-- with a pet on every member. Splitting pets into popover-sized buckets (the
-- fix for pets past the eighth being uncountable) pushed the group count from
-- 9 to 13, past the old pool - and UpdateUI does not truncate gracefully, it
-- just stops emitting rows. Pets sort last, so pets are what vanished.
------------------------------------------------------------

setup()
WoW.inRaid = true
WoW.groupMembers = 40
for i = 1, 40 do
    local nm = "Raider" .. i .. " Sur"
    WoW.raidRoster[i] = { name = nm, subgroup = math.ceil(i / 5) }
    WoW.SetUnit("raid" .. i, { name = nm, guid = "R" .. i, class = "HUNTER" })
    WoW.SetUnit("raidpet" .. i, { name = "Pet" .. i, guid = "PET" .. i })
end
H.TeachSpells({ "FORT_SINGLE", "SPIRIT_SINGLE", "SHADOW_SINGLE" })
T.RefreshSpellData()
PriestlyDB.shadowMode = "always"          -- all three buffs get a row

groups, ord = T.GatherGroups()
H.eq(#ord, 13, "8 subgroups plus 5 pet buckets")

T.UpdateUI()

-- Every unit in the roster has to appear in some row, or it is invisible and
-- unbuffable no matter what GatherGroups produced.
local seen = {}
local activeRows = 0
for _, r in ipairs(T.rows()) do
    if r._active then
        activeRows = activeRows + 1
        for _, m in ipairs(r._members or {}) do seen[m.unit] = true end
    end
end

H.eq(activeRows, 39, "13 groups x 3 buffs, all of them rendered")

local missingRaiders, missingPets = 0, 0
for i = 1, 40 do
    if not seen["raid" .. i] then missingRaiders = missingRaiders + 1 end
    if not seen["raidpet" .. i] then missingPets = missingPets + 1 end
end
H.eq(missingRaiders, 0, "every raider is on screen")
H.eq(missingPets, 0, "and so is every pet - not just the first bucket")

-- The same roster with pets off must still fit, and must not waste rows.
PriestlyDB.trackPets = false
T.UpdateUI()
activeRows = 0
for _, r in ipairs(T.rows()) do
    if r._active then activeRows = activeRows + 1 end
end
H.eq(activeRows, 24, "8 subgroups x 3 buffs with pet tracking off")
PriestlyDB.trackPets = true

H.done("test_roster")
