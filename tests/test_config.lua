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
PriestlyAccountDB = nil
Priestly_EnsureDefaults()

H.check(PriestlyAccountDB ~= nil, "a missing PriestlyAccountDB is created")
H.eq(PriestlyAccountDB.trackFort, true, "Fortitude tracked by default")
H.eq(PriestlyAccountDB.trackSpirit, true, "Spirit tracked by default")
H.eq(PriestlyAccountDB.shadowMode, "detect", "Shadow Protection defaults to detect")
H.eq(PriestlyAccountDB.showSolo, false, "solo display off by default")
H.eq(PriestlyAccountDB.trackPets, true, "pets tracked by default")
H.eq(PriestlyAccountDB.flavor, TC.FLAVOR, "the flavor marker is stamped")

local seeded = 0
for _, entry in ipairs(TC.INSTANCE_DB) do
    if PriestlyAccountDB.shadowInstances[entry.name] ~= nil then seeded = seeded + 1 end
end
H.eq(seeded, #TC.INSTANCE_DB, "every instance gets a saved default")
H.eq(PriestlyAccountDB.shadowInstances["Scholomance"], true, "heavy-shadow instances start checked")
H.eq(PriestlyAccountDB.shadowInstances["Onyxia's Lair"], false, "fire raids do not")

------------------------------------------------------------
-- Migration from a TBC-era profile
------------------------------------------------------------

WoW.reset()
PriestlyAccountDB = {
    trackFort   = false,            -- a setting the user changed
    shadowMode  = "always",
    frameAlpha  = 0.5,
    shadowInstances = {
        ["Karazhan"]        = true,     -- TBC content: cannot occur here
        ["Black Temple"]    = true,
        ["Naxxramas"]       = true,     -- Vanilla, but not in Forever either
        ["Scholomance"]     = false,    -- reachable, and the user unchecked it
    },
    learnedDurations = { build = "old", fort = 1800 },
}
Priestly_EnsureDefaults()

H.eq(PriestlyAccountDB.trackFort, false, "the user's own settings survive the migration")
H.eq(PriestlyAccountDB.shadowMode, "always", "...all of them")
H.eq(PriestlyAccountDB.frameAlpha, 0.5, "...including the slider")
-- The window state is NOT here: it belongs to the character, not the
-- account, so it lives in the per-character table (see
-- Priestly_SetWindowVisible). tests/test_visibility.lua covers it.
H.eq(PriestlyAccountDB.visible, nil, "...and the shared table holds no window state")

H.check(PriestlyAccountDB.shadowInstances["Karazhan"] == nil, "TBC instances are dropped")
H.check(PriestlyAccountDB.shadowInstances["Black Temple"] == nil, "all of them")
H.check(PriestlyAccountDB.shadowInstances["Naxxramas"] == nil,
    "and Vanilla raids that Forever does not have")
H.eq(PriestlyAccountDB.shadowInstances["Scholomance"], false,
    "an instance the user unchecked stays unchecked - not reset to the default")
H.eq(PriestlyAccountDB.shadowInstances["Hyjal Summit"], true, "new instances are backfilled")
H.check(PriestlyAccountDB.learnedDurations == nil or PriestlyAccountDB.learnedDurations.fort == nil,
    "durations learned on the TBC client are thrown away")
H.eq(PriestlyAccountDB.flavor, TC.FLAVOR, "the marker means this only happens once")

-- Running it again must not undo the user's choices.
PriestlyAccountDB.shadowInstances["Hyjal Summit"] = false
Priestly_EnsureDefaults()
H.eq(PriestlyAccountDB.shadowInstances["Hyjal Summit"], false,
    "a second run does not re-apply defaults over user choices")

-- Pruning is deliberately one-time, guarded by the flavor marker. An entry the
-- current list does not name is inert - nothing reads shadowInstances except
-- the zone lookup - so pruning on every load would buy tidiness and cost real
-- data: install an older build once, and every choice it does not list is gone.
PriestlyAccountDB.shadowInstances["Some Future Instance"] = true
Priestly_EnsureDefaults()
H.eq(PriestlyAccountDB.shadowInstances["Some Future Instance"], true,
    "an unknown entry survives, because a build that does not list it may be an old one")
H.eq(PriestlyAccountDB.flavor, TC.FLAVOR, "and the marker keeps the migration from running again")

------------------------------------------------------------
-- Duration store is per client build
------------------------------------------------------------

WoW.reset()
PriestlyAccountDB = nil
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
PriestlyAccountDB = nil
Priestly_EnsureDefaults()
H.TeachSpells({ "SHADOW_SINGLE" })
T.RefreshSpellData()

PriestlyAccountDB.shadowMode = "always"
H.check(Priestly_ShouldShowShadow(nil, nil) == true, "'always' needs no group at all")

PriestlyAccountDB.shadowMode = "detect"
WoW.SetUnit("party1", { name = "Sten Thornbeard" })
local groups = { [1] = { { unit = "party1" } } }
H.check(Priestly_ShouldShowShadow(groups, { 1 }) == false, "nobody has it")
WoW.SetAura("party1", "Shadow Protection", 600, 300)
H.check(Priestly_ShouldShowShadow(groups, { 1 }) == true, "somebody has it")
H.check(Priestly_ShouldShowShadow(nil, nil) == false, "'detect' with no roster is false")

-- Detect mode runs from ActiveDefs, immediately before the rows ask about the
-- same members - so on a roster where nobody has it, this used to walk
-- everybody's auras once and the rows walked them again. It reads through the
-- engine now, which means an open aura pass covers both (#6).
WoW.reset()
H.TeachSpells({ "SHADOW_SINGLE" })
T.RefreshSpellData()
PriestlyAccountDB.shadowMode = "detect"
local eng = Priestly.engine
H.check(eng ~= nil, "the engine is published for the config to read through")
local roster, bare = {}, {}
for i = 1, 8 do
    WoW.SetUnit("party" .. i, { name = "Raider" .. i, guid = "P" .. i })
    for a = 1, 12 do WoW.SetAura("party" .. i, "Filler" .. a, 600, 300) end
    bare[#bare + 1] = { unit = "party" .. i }
end
roster[1] = bare
WoW.byNameBlind = true          -- force the walk, which is the path being shared

WoW.auraReads.byIndex = 0
H.check(Priestly_ShouldShowShadow(roster, { 1 }) == false, "nobody in the raid has it")
local alone = WoW.auraReads.byIndex

eng:BeginAuraPass()
WoW.auraReads.byIndex = 0
H.check(Priestly_ShouldShowShadow(roster, { 1 }) == false, "same answer inside a pass")
local first = WoW.auraReads.byIndex
WoW.auraReads.byIndex = 0
local shadowDef
for _, d in ipairs(T.DEFS) do if d.id == "shadow" then shadowDef = d end end
for _, m in ipairs(bare) do eng:BuffRem(m.unit, shadowDef) end
local second = WoW.auraReads.byIndex
eng:EndAuraPass()

H.check(alone > 0, "the scan really does walk auras: " .. alone .. " reads")
H.eq(first, alone, "the scan inside a pass costs the same walk, once")
H.eq(second, 0, "and the rows that follow it read nothing at all")

WoW.byNameBlind = false

PriestlyAccountDB.shadowMode = "instance"
WoW.instanceName = "Scholomance"
PriestlyAccountDB.shadowInstances["Scholomance"] = true
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

-- Eleven returns on 70009, nine on 69913. Nothing here reads past the second,
-- and this says so out loud rather than leaving the stub free to model a
-- client shape that no longer exists.
H.eq(select("#", GetInstanceInfo()), 11, "GetInstanceInfo returns the tuple this client returns")

-- Outdoors the live client hands back the CONTINENT with instanceType "none",
-- not an empty name. Gating on the name alone would be correct only by luck -
-- until somebody adds a zone name that collides.
WoW.instanceName = "Eastern Kingdoms"
WoW.instanceType = "none"
PriestlyAccountDB.shadowInstances["Eastern Kingdoms"] = true   -- worst case
TC.CheckCurrentInstance()
H.check(TC.inShadowInstance() == false,
    "a continent name with instanceType 'none' is not an instance")

WoW.instanceName = "Scholomance"
WoW.instanceType = "party"
PriestlyAccountDB.shadowInstances["Scholomance"] = true
TC.CheckCurrentInstance()
H.check(TC.inShadowInstance() == true, "...but a real instance still counts")
WoW.instanceType = nil

------------------------------------------------------------
-- Matched on the client's instance ID, not on its NAME
--
-- The name is localized: a French client returns French instance names, so
-- name matching has been broken for everyone not playing in English since the
-- feature existed. It is also unverifiable - almost every zone in the list is
-- above the current level cap, and a name one character off fails SILENTLY,
-- with the mode simply never firing.
--
-- The ID is identical in every locale and either matches or does not. Only
-- one is measured so far (Ruins of Lordaeron, 2999, with `/pprobe here`), so
-- the name stays as the fallback for entries whose ID nobody has stood in
-- yet.
------------------------------------------------------------

-- A client that answers in another language, with the ID we know.
WoW.instanceName = "Ruines de Lordaeron"
WoW.instanceType = "party"
WoW.instanceMapID = 2999
PriestlyAccountDB.shadowInstances["Ruins of Lordaeron"] = true
TC.CheckCurrentInstance()
H.check(TC.inShadowInstance() == true,
    "a localized instance name still matches, because the ID does")

-- And the setting is still keyed on OUR name, so a player's choices survive.
PriestlyAccountDB.shadowInstances["Ruins of Lordaeron"] = false
TC.CheckCurrentInstance()
H.check(TC.inShadowInstance() == false,
    "and the saved choice is read under the entry's own name, not the client's")

-- An ID we do not know falls back to the name, which is how every entry
-- behaves until somebody stands in it.
PriestlyAccountDB.shadowInstances["Scholomance"] = true
WoW.instanceName = "Scholomance"
WoW.instanceMapID = 4242            -- nothing in the list claims this
TC.CheckCurrentInstance()
H.check(TC.inShadowInstance() == true, "an unknown ID falls back to matching the name")

-- The ID WINS over the name. A client that reuses a name we know for a
-- different instance must not be taken at its word.
WoW.instanceName = "Scholomance"
WoW.instanceMapID = 2999
PriestlyAccountDB.shadowInstances["Scholomance"] = true
PriestlyAccountDB.shadowInstances["Ruins of Lordaeron"] = false
TC.CheckCurrentInstance()
H.check(TC.inShadowInstance() == false,
    "the ID decides which entry it is, and the name does not overrule it")

WoW.instanceMapID = 0
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
PriestlyAccountDB = nil
Priestly_EnsureDefaults()
for k in pairs(TC.reportedUnknown()) do TC.reportedUnknown()[k] = nil end

PriestlyAccountDB.shadowMode = "instance"
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
-- And carries the ID, which is the half worth reporting: it is the same in
-- every language, so pasting it fixes the entry for everybody. The name alone
-- only ever fixes English clients.
-- A name of its own: the once-per-session latch is keyed on the name, and a
-- later section uses "Another Unlisted Dungeon" to prove the warning still
-- arrives when the mode is switched on.
WoW.instanceName = "An Unlisted Dungeon With An Id"
WoW.instanceMapID = 5150
TC.CheckCurrentInstance()
H.check(WoW.messages[#WoW.messages]:find("5150", 1, true) ~= nil,
    "with the instance ID: " .. WoW.messages[#WoW.messages])
WoW.instanceMapID = 0

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
    PriestlyAccountDB.shadowMode = mode
    WoW.instanceName = "Another Unlisted Dungeon"
    WoW.instanceType = "party"
    before = #WoW.messages
    TC.CheckCurrentInstance()
    H.eq(#WoW.messages, before, "'" .. mode .. "' mode does not warn about the instance list")
end

PriestlyAccountDB.shadowMode = "instance"
TC.CheckCurrentInstance()
H.check(#WoW.messages > before,
    "and the warning still arrives the first time the mode is actually on")

WoW.instanceType = nil

------------------------------------------------------------
-- Buff toggles
------------------------------------------------------------

PriestlyAccountDB.trackFort = true
PriestlyAccountDB.trackSpirit = false
H.check(Priestly_IsBuffEnabled("fort") == true, "Fortitude enabled")
H.check(Priestly_IsBuffEnabled("spirit") == false, "Spirit disabled")
H.check(Priestly_IsBuffEnabled("shadow") == true,
    "Shadow has no toggle of its own - the mode controls it")

------------------------------------------------------------
-- Popover side
------------------------------------------------------------

PriestlyAccountDB = nil
Priestly_EnsureDefaults()
H.eq(PriestlyAccountDB.popoverSide, "auto", "auto is the default - it needs no explanation")
H.eq(Priestly_PopoverSide(), "auto", "and the helper agrees")

PriestlyAccountDB.popoverSide = "right"
H.eq(Priestly_PopoverSide(), "right", "an explicit side is reported back")

-- A saved variable from before this setting existed must not break, and must
-- pick up the default rather than a nil that reads as "no preference".
PriestlyAccountDB.popoverSide = nil
H.eq(Priestly_PopoverSide(), "auto", "an older PriestlyAccountDB falls back to auto")
Priestly_EnsureDefaults()
H.eq(PriestlyAccountDB.popoverSide, "auto", "and EnsureDefaults backfills the key")

------------------------------------------------------------
-- Frame lock
-- Click hints
------------------------------------------------------------

PriestlyAccountDB = nil
Priestly_EnsureDefaults()
H.eq(PriestlyAccountDB.lockFrame, false, "unlocked by default - the window has always been draggable")
H.eq(Priestly_FrameLocked(), false, "and the helper agrees")

PriestlyAccountDB.lockFrame = true
H.eq(Priestly_FrameLocked(), true, "locking is reported")

-- A PriestlyAccountDB from before this setting existed must read as unlocked, not as
-- a locked window somebody cannot move and has no reason to look for a
-- setting about.
PriestlyAccountDB.lockFrame = nil
H.eq(Priestly_FrameLocked(), false, "an older PriestlyAccountDB is unlocked")
Priestly_EnsureDefaults()
H.eq(PriestlyAccountDB.lockFrame, false, "and EnsureDefaults backfills it")
H.eq(PriestlyAccountDB.showClickHints, true, "hints are on by default - they exist to be discovered")
H.eq(Priestly_ShowClickHints(), true, "and the helper agrees")

PriestlyAccountDB.showClickHints = false
H.eq(Priestly_ShowClickHints(), false, "turning them off is respected")

-- Only an explicit false turns them off. A PriestlyAccountDB from before this setting
-- existed has no key, and must not read as "the user turned these off".
PriestlyAccountDB.showClickHints = nil
H.eq(Priestly_ShowClickHints(), true, "an older PriestlyAccountDB still gets hints")

H.done("test_config")
