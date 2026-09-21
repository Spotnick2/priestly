------------------------------------------------------------
-- test_config.lua - saved variables: defaults, the one-time migration off
-- the TBC line, and the Shadow Protection visibility modes.
--
--   & 'C:\Program Files (x86)\Lua\5.1\lua.exe' tests\test_config.lua
------------------------------------------------------------

dofile("tests/wow_stubs.lua")
local H = dofile("tests/harness.lua")
local T, TC = H.loadAddon()

------------------------------------------------------------
-- Defaults on a fresh install
------------------------------------------------------------

WoW.reset()
PriestlyDB = nil
Priestly_EnsureDefaults()

H.check(PriestlyDB ~= nil, "a missing PriestlyDB is created")
H.eq(PriestlyDB.trackFort, true, "Fortitude tracked by default")
H.eq(PriestlyDB.trackSpirit, true, "Spirit tracked by default")
H.eq(PriestlyDB.shadowMode, "detect", "Shadow Protection defaults to detect")
H.eq(PriestlyDB.showSolo, false, "solo display off by default")
H.eq(PriestlyDB.trackPets, true, "pets tracked by default")
H.eq(PriestlyDB.flavor, TC.FLAVOR, "the flavor marker is stamped")

local seeded = 0
for _, entry in ipairs(TC.INSTANCE_DB) do
    if PriestlyDB.shadowInstances[entry[1]] ~= nil then seeded = seeded + 1 end
end
H.eq(seeded, #TC.INSTANCE_DB, "every instance gets a saved default")
H.eq(PriestlyDB.shadowInstances["Scholomance"], true, "heavy-shadow instances start checked")
H.eq(PriestlyDB.shadowInstances["Onyxia's Lair"], false, "fire raids do not")

------------------------------------------------------------
-- Migration from a TBC-era profile
------------------------------------------------------------

WoW.reset()
PriestlyDB = {
    trackFort   = false,            -- a setting the user changed
    shadowMode  = "always",
    frameAlpha  = 0.5,
    visible     = false,
    shadowInstances = {
        ["Karazhan"]        = true,     -- TBC content: cannot occur here
        ["Black Temple"]    = true,
        ["Naxxramas"]       = true,     -- Vanilla, but not in Forever either
        ["Scholomance"]     = false,    -- reachable, and the user unchecked it
    },
    learnedDurations = { build = "old", fort = 1800 },
}
Priestly_EnsureDefaults()

H.eq(PriestlyDB.trackFort, false, "the user's own settings survive the migration")
H.eq(PriestlyDB.shadowMode, "always", "...all of them")
H.eq(PriestlyDB.frameAlpha, 0.5, "...including the slider")
H.eq(PriestlyDB.visible, false, "...and the window state")

H.check(PriestlyDB.shadowInstances["Karazhan"] == nil, "TBC instances are dropped")
H.check(PriestlyDB.shadowInstances["Black Temple"] == nil, "all of them")
H.check(PriestlyDB.shadowInstances["Naxxramas"] == nil,
    "and Vanilla raids that Forever does not have")
H.eq(PriestlyDB.shadowInstances["Scholomance"], false,
    "an instance the user unchecked stays unchecked - not reset to the default")
H.eq(PriestlyDB.shadowInstances["Hyjal Summit"], true, "new instances are backfilled")
H.check(PriestlyDB.learnedDurations == nil or PriestlyDB.learnedDurations.fort == nil,
    "durations learned on the TBC client are thrown away")
H.eq(PriestlyDB.flavor, TC.FLAVOR, "the marker means this only happens once")

-- Running it again must not undo the user's choices.
PriestlyDB.shadowInstances["Hyjal Summit"] = false
Priestly_EnsureDefaults()
H.eq(PriestlyDB.shadowInstances["Hyjal Summit"], false,
    "a second run does not re-apply defaults over user choices")

-- Pruning is deliberately one-time, guarded by the flavor marker. An entry the
-- current list does not name is inert - nothing reads shadowInstances except
-- the zone lookup - so pruning on every load would buy tidiness and cost real
-- data: install an older build once, and every choice it does not list is gone.
PriestlyDB.shadowInstances["Some Future Instance"] = true
Priestly_EnsureDefaults()
H.eq(PriestlyDB.shadowInstances["Some Future Instance"], true,
    "an unknown entry survives, because a build that does not list it may be an old one")
H.eq(PriestlyDB.flavor, TC.FLAVOR, "and the marker keeps the migration from running again")

------------------------------------------------------------
-- Duration store is per client build
------------------------------------------------------------

WoW.reset()
PriestlyDB = nil
Priestly_EnsureDefaults()

-- Keyed by SPELL name, not by buff: the single and group forms of one buff run
-- for different lengths.
H.check(Priestly_GetLearnedDuration("Power Word: Fortitude") == nil, "nothing learned yet")
Priestly_LearnDuration("Power Word: Fortitude", 3600)
H.eq(Priestly_GetLearnedDuration("Power Word: Fortitude"), 3600, "a learned duration is stored")
Priestly_LearnDuration("Power Word: Fortitude", 1800)
H.eq(Priestly_GetLearnedDuration("Power Word: Fortitude"), 1800,
    "and replaced downward on a nerf")
Priestly_LearnDuration("Power Word: Fortitude", 0)
H.eq(Priestly_GetLearnedDuration("Power Word: Fortitude"), 1800, "a nonsense value is ignored")
Priestly_LearnDuration("Prayer of Fortitude", 3600)
H.eq(Priestly_GetLearnedDuration("Prayer of Fortitude"), 3600,
    "the group form of the same buff is stored separately")
H.eq(Priestly_GetLearnedDuration("Power Word: Fortitude"), 1800,
    "...without overwriting the single form")
Priestly_LearnDuration("Shadow Protection", 600)
H.eq(Priestly_GetLearnedDuration("Shadow Protection"), 600, "as is every other spell")
Priestly_LearnDuration(nil, 600)
H.check(true, "a nil spell name is ignored rather than erroring")

WoW.build = "70000"
Priestly_EnsureDefaults()       -- a build change means a restart means a login
H.check(Priestly_GetLearnedDuration("Power Word: Fortitude") == nil,
    "a new build resets the table")
Priestly_LearnDuration("Power Word: Fortitude", 900)
H.eq(Priestly_GetLearnedDuration("Power Word: Fortitude"), 900, "and starts learning again")

------------------------------------------------------------
-- Shadow Protection visibility modes
------------------------------------------------------------

WoW.reset()
PriestlyDB = nil
Priestly_EnsureDefaults()
H.TeachSpells({ "SHADOW_SINGLE" })
T.RefreshSpellData()

PriestlyDB.shadowMode = "always"
H.check(Priestly_ShouldShowShadow(nil, nil) == true, "'always' needs no group at all")

PriestlyDB.shadowMode = "detect"
WoW.SetUnit("party1", { name = "Sten Thornbeard" })
local groups = { [1] = { { unit = "party1" } } }
H.check(Priestly_ShouldShowShadow(groups, { 1 }) == false, "nobody has it")
WoW.SetAura("party1", "Shadow Protection", 600, 300)
H.check(Priestly_ShouldShowShadow(groups, { 1 }) == true, "somebody has it")
H.check(Priestly_ShouldShowShadow(nil, nil) == false, "'detect' with no roster is false")

PriestlyDB.shadowMode = "instance"
WoW.instanceName = "Scholomance"
PriestlyDB.shadowInstances["Scholomance"] = true
TC.CheckCurrentInstance()
H.check(Priestly_ShouldShowShadow(nil, nil) == true, "in a checked instance")
H.check(TC.inShadowInstance() == true, "and the detector agrees")

WoW.instanceName = "Onyxia's Lair"
TC.CheckCurrentInstance()
H.check(Priestly_ShouldShowShadow(nil, nil) == false, "in an unchecked instance")

WoW.instanceName = ""
WoW.instanceType = nil
TC.CheckCurrentInstance()
H.check(Priestly_ShouldShowShadow(nil, nil) == false, "out in the world")

-- Outdoors the live client hands back the CONTINENT with instanceType "none",
-- not an empty name. Gating on the name alone would be correct only by luck -
-- until somebody adds a zone name that collides.
WoW.instanceName = "Eastern Kingdoms"
WoW.instanceType = "none"
PriestlyDB.shadowInstances["Eastern Kingdoms"] = true   -- worst case
TC.CheckCurrentInstance()
H.check(TC.inShadowInstance() == false,
    "a continent name with instanceType 'none' is not an instance")

WoW.instanceName = "Scholomance"
WoW.instanceType = "party"
PriestlyDB.shadowInstances["Scholomance"] = true
TC.CheckCurrentInstance()
H.check(TC.inShadowInstance() == true, "...but a real instance still counts")
WoW.instanceType = nil

------------------------------------------------------------
-- An instance the list does not know must say so
--
-- The keys are exact instance names, most of which cannot be verified until
-- the level cap rises, and a wrong key fails silently - the mode never fires
-- and nothing explains why. Announcing it turns an invisible bug into a bug
-- report from the only people who can measure it.
------------------------------------------------------------

WoW.reset()
PriestlyDB = nil
Priestly_EnsureDefaults()
for k in pairs(TC.reportedUnknown()) do TC.reportedUnknown()[k] = nil end

PriestlyDB.shadowMode = "instance"
WoW.instanceName = "Scholomance"
WoW.instanceType = "party"
local before = #WoW.messages
TC.CheckCurrentInstance()
H.eq(#WoW.messages, before, "a known instance says nothing")

WoW.instanceName = "Some Unlisted Dungeon"
TC.CheckCurrentInstance()
H.check(#WoW.messages > before, "an instance the list does not know is reported")
H.check(WoW.messages[#WoW.messages]:find("Some Unlisted Dungeon", 1, true) ~= nil,
    "and the message names it, so it can be reported and added")

-- Once per session, not once per zone-in.
before = #WoW.messages
TC.CheckCurrentInstance()
H.eq(#WoW.messages, before, "and it does not repeat itself every time you zone in")

-- Out in the world there is no instance to complain about.
WoW.instanceName = "Eastern Kingdoms"
WoW.instanceType = "none"
before = #WoW.messages
TC.CheckCurrentInstance()
H.eq(#WoW.messages, before, "standing outdoors is not an unknown instance")

-- Battlegrounds and arenas report an instanceType, but their names have no
-- business in a shadow-damage list, so asking for them would be asking for the
-- wrong thing.
for _, kind in ipairs({ "pvp", "arena" }) do
    WoW.instanceName = "Some " .. kind .. " Place"
    WoW.instanceType = kind
    before = #WoW.messages
    TC.CheckCurrentInstance()
    H.eq(#WoW.messages, before, "a " .. kind .. " instance is not reported as missing")
end

-- And somebody who has not chosen "by instance" is not warned about a feature
-- they are not using - nor quietly marked as already told, which would stop the
-- warning ever appearing once they did turn it on.
for _, mode in ipairs({ "detect", "always" }) do
    PriestlyDB.shadowMode = mode
    WoW.instanceName = "Another Unlisted Dungeon"
    WoW.instanceType = "party"
    before = #WoW.messages
    TC.CheckCurrentInstance()
    H.eq(#WoW.messages, before, "'" .. mode .. "' mode does not warn about the instance list")
end

PriestlyDB.shadowMode = "instance"
TC.CheckCurrentInstance()
H.check(#WoW.messages > before,
    "and the warning still arrives the first time the mode is actually on")

WoW.instanceType = nil

------------------------------------------------------------
-- Buff toggles
------------------------------------------------------------

PriestlyDB.trackFort = true
PriestlyDB.trackSpirit = false
H.check(Priestly_IsBuffEnabled("fort") == true, "Fortitude enabled")
H.check(Priestly_IsBuffEnabled("spirit") == false, "Spirit disabled")
H.check(Priestly_IsBuffEnabled("shadow") == true,
    "Shadow has no toggle of its own - the mode controls it")

H.done("test_config")
