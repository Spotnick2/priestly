------------------------------------------------------------
-- test_buffs.lua - aura reads, the GUID-keyed cache, combat secrecy,
-- learned durations and target picking.
--
-- The interesting case is combat: on this client auras become unreadable while
-- tainted (C_Secrets.ShouldAurasBeSecret), and a naive read reports everyone
-- as unbuffed - the whole frame flips red the instant a pull starts.
--
--   & 'C:\Program Files (x86)\Lua\5.1\lua.exe' tests\test_buffs.lua
------------------------------------------------------------

dofile("tests/wow_stubs.lua")
local H = dofile("tests/harness.lua")
local T, TC = H.loadAddon()

local HAS, MISSING, UNKNOWN = T.states.HAS, T.states.MISSING, T.states.UNKNOWN

local function defById(id)
    for _, d in ipairs(T.DEFS) do
        if d.id == id then return d end
    end
end

local function setup()
    WoW.reset()
    PriestlyDB = nil
    Priestly_EnsureDefaults()
    H.TeachSpells({ "FORT_SINGLE", "FORT_GROUP" })
    T.RefreshSpellData()
    for k in pairs(T.auraCache()) do T.auraCache()[k] = nil end
    return defById("fort")
end

local function member(unit) return { unit = unit, name = WoW.units[unit].name } end

------------------------------------------------------------
-- BuffRem: three states, not two
------------------------------------------------------------

local fort = setup()
WoW.SetUnit("party1", { name = "Karuzo Elegia", guid = "P1" })

local rem, dur, state = T.BuffRem("party1", fort)
H.eq(state, MISSING, "no aura -> MISSING")
H.eq(rem, 0, "and no time")

WoW.SetAura("party1", "Power Word: Fortitude", 3600, 1800)
rem, dur, state = T.BuffRem("party1", fort)
H.eq(state, HAS, "aura present -> HAS")
H.eq(rem, 1800, "remaining is passed through")
H.eq(dur, 3600, "duration is passed through")

------------------------------------------------------------
-- Combat secrecy: count down from the cache instead of guessing
------------------------------------------------------------

H.secrecy(true)
WoW.time = WoW.time + 60

rem, dur, state = T.BuffRem("party1", fort)
H.eq(state, HAS, "a cached buff stays HAS while auras are unreadable")
H.eq(rem, 1740, "and the timer keeps counting down from the cached expiry")

-- Somebody we never saw before the pull is unknown, not missing.
WoW.SetUnit("party2", { name = "Sten Thornbeard", guid = "P2" })
rem, dur, state = T.BuffRem("party2", fort)
H.eq(state, UNKNOWN, "no cached state under secrecy -> UNKNOWN, never a confident MISS")

-- A cached buff that genuinely ran out mid-fight does report missing.
WoW.time = WoW.time + 2000
rem, dur, state = T.BuffRem("party1", fort)
H.eq(state, MISSING, "a cached buff that expired during the fight is MISSING")

H.secrecy(false)

-- We attempt the read regardless of the flag rather than refusing whenever
-- ShouldAurasBeSecret() is true. On build 69913 the read does throw, but if a
-- future build stops covering party and raid auras, live data must win over a
-- cache that is only as fresh as the last pull.
fort = setup()
WoW.SetUnit("party1", { name = "Karuzo Elegia", guid = "P1" })
WoW.SetAura("party1", "Power Word: Fortitude", 3600, 1800)
T.BuffRem("party1", fort)                      -- seed the cache
WoW.secret = true                              -- flag on...
WoW.auraReadsThrow = false                     -- ...but reads still work
WoW.ClearAuras("party1")
WoW.SetAura("party1", "Renew", 15, 10)         -- still has *something*
rem, dur, state = T.BuffRem("party1", fort)
H.eq(state, MISSING,
    "a readable aura list beats the cache: losing the buff is seen, not masked by stale state")

-- With nothing readable at all, though, secrecy means we genuinely cannot tell
-- the difference between "unbuffed" and "hidden" - so fall back rather than
-- assert a MISS.
WoW.ClearAuras("party1")
rem, dur, state = T.BuffRem("party1", fort)
H.eq(state, UNKNOWN,
    "an empty aura list under secrecy is not evidence of being unbuffed - and the "
    .. "cache was already cleared by the definite read above, so: unknown")
H.secrecy(false)

------------------------------------------------------------
-- The cache is keyed by GUID, not by unit token
--
-- raid3 / party2 get handed to whoever is in that slot now. A token-keyed
-- cache would show the previous occupant's buffs after a reshuffle.
------------------------------------------------------------

fort = setup()
WoW.SetUnit("raid3", { name = "Karuzo Elegia", guid = "P1" })
WoW.SetAura("raid3", "Power Word: Fortitude", 3600, 1800)
T.BuffRem("raid3", fort)                              -- caches under P1

-- Roster reshuffle: raid3 is now a different character, unbuffed.
WoW.ClearAuras("raid3")
WoW.SetUnit("raid3", { name = "Sten Thornbeard", guid = "P2" })
H.secrecy(true)
rem, dur, state = T.BuffRem("raid3", fort)
H.eq(state, UNKNOWN,
    "the new occupant of raid3 does not inherit the previous player's buff")

-- ...and the original character keeps their cached state under their own GUID.
WoW.SetUnit("raid7", { name = "Karuzo Elegia", guid = "P1" })
rem, dur, state = T.BuffRem("raid7", fort)
H.eq(state, HAS, "the same character keeps their state after moving slots")
H.secrecy(false)

------------------------------------------------------------
-- Learned durations: seeds are only seeds
------------------------------------------------------------

fort = setup()
H.eq(T.DurationFor(fort, nil), 3600, "with nothing learned, the DEFS seed is used")
H.eq(T.DurationFor(fort, 1800), 1800, "an observed duration always wins")

WoW.SetUnit("party1", { name = "Karuzo Elegia", guid = "P1" })
WoW.SetAura("party1", "Power Word: Fortitude", 1800, 900)
T.BuffRem("party1", fort)
H.eq(Priestly_GetLearnedDuration("fort"), 1800, "a live aura teaches the real duration")
H.eq(T.DurationFor(fort, nil), 1800, "and that is what later bars are scaled against")

-- A beta patch shortens the buff: the stored value must follow it DOWN.
WoW.ClearAuras("party1")
WoW.SetAura("party1", "Power Word: Fortitude", 600, 300)
T.BuffRem("party1", fort)
H.eq(Priestly_GetLearnedDuration("fort"), 600,
    "durations are replaced in both directions, not maxed")

-- A new client build throws the whole table away.
WoW.build = "70000"
H.check(Priestly_GetLearnedDuration("fort") == nil,
    "what was learned on an older build is discarded")

------------------------------------------------------------
-- GroupStat
------------------------------------------------------------

fort = setup()
WoW.SetUnit("party1", { name = "A One", guid = "P1" })
WoW.SetUnit("party2", { name = "B Two", guid = "P2" })
WoW.SetUnit("party3", { name = "C Three", guid = "P3" })
local members = { member("party1"), member("party2"), member("party3") }

local st = T.GroupStat(members, fort)
H.eq(st.nTotal, 3, "counts everyone")
H.eq(st.nMiss, 3, "nobody buffed -> all missing")
H.check(st.allHave == false, "and allHave is false")

WoW.SetAura("party1", "Power Word: Fortitude", 3600, 3000)
WoW.SetAura("party2", "Power Word: Fortitude", 3600, 1200)
st = T.GroupStat(members, fort)
H.eq(st.nMiss, 1, "one still missing")
H.eq(st.minR, 1200, "the bar shows the lowest remaining time")

WoW.SetAura("party3", "Power Word: Fortitude", 3600, 2000)
st = T.GroupStat(members, fort)
H.eq(st.nMiss, 0, "everyone buffed")
H.check(st.allHave == true, "allHave")

-- Offline counts as missing regardless of what they had.
WoW.units.party3.connected = false
st = T.GroupStat(members, fort)
H.eq(st.nMiss, 1, "a disconnected member counts as missing")
WoW.units.party3.connected = true

-- Unknown members are counted apart from missing ones.
H.secrecy(true)
for k in pairs(T.auraCache()) do T.auraCache()[k] = nil end
st = T.GroupStat(members, fort)
H.eq(st.nUnknown, 3, "with no cache under secrecy everyone is unknown")
H.eq(st.nMiss, 0, "and nobody is reported as missing")
H.check(st.allHave == false, "unknown is not 'everyone has it' either")
H.secrecy(false)

------------------------------------------------------------
-- PickTarget
------------------------------------------------------------

fort = setup()
WoW.SetUnit("party1", { name = "A One", guid = "P1" })
WoW.SetUnit("party2", { name = "B Two", guid = "P2" })
WoW.SetUnit("party3", { name = "C Three", guid = "P3" })
members = { member("party1"), member("party2"), member("party3") }

WoW.SetAura("party1", "Power Word: Fortitude", 3600, 3000)
WoW.SetAura("party3", "Power Word: Fortitude", 3600, 3000)
H.eq(T.PickTarget(members, fort, false), "party2", "single target picks the one missing it")

WoW.SetAura("party2", "Power Word: Fortitude", 3600, 500)
H.eq(T.PickTarget(members, fort, false), "party2",
    "with nobody missing it picks the lowest remaining")

H.eq(T.PickTarget(members, fort, true), "party1",
    "a group Prayer just needs any valid member")

-- Dead and offline members are never targets.
WoW.units.party1.dead = true
WoW.units.party2.connected = false
H.eq(T.PickTarget(members, fort, true), "party3", "dead and offline members are skipped")

WoW.units.party3.dead = true
H.check(T.PickTarget(members, fort, true) == nil, "nobody valid -> no target")
H.check(T.PickTarget(members, fort, false) == nil, "...for either click")

------------------------------------------------------------
-- Cache pruning
------------------------------------------------------------

fort = setup()
WoW.SetUnit("party1", { name = "A One", guid = "P1" })
WoW.SetAura("party1", "Power Word: Fortitude", 3600, 3000)
T.BuffRem("party1", fort)
H.check(T.auraCache()["P1"] ~= nil, "the read was cached")
WoW.time = WoW.time + 7200
T.PruneAuraCache()
H.check(T.auraCache()["P1"] == nil, "stale characters are pruned")

------------------------------------------------------------
-- Formatting helpers
------------------------------------------------------------

H.eq(T.FmtTime(90), "1:30", "mm:ss")
H.eq(T.FmtTime(3599), "59:59", "just under an hour")
H.eq(T.FmtTime(0), "", "nothing to show at zero")
H.eq(T.FmtTime(9999), "", "a permanent buff shows no timer")

local r, g, b = T.TimerColor(1.0)
H.eq(r, 0, "full time is green")
H.eq(g, 1.0, "full time is green")
r, g, b = T.TimerColor(0.0)
H.eq(r, 1.0, "no time left is red")
H.eq(g, 0, "no time left is red")

------------------------------------------------------------
-- UNIT_AURA filtering
------------------------------------------------------------

fort = setup()
H.check(T.AuraEventIsRelevant("party1", { isFullUpdate = true }) == true,
    "a full update on a group member is relevant")
H.check(T.AuraEventIsRelevant("target", { isFullUpdate = true }) == false,
    "units we never draw are ignored")
H.check(T.AuraEventIsRelevant("nameplate3", { isFullUpdate = true }) == false,
    "nameplates are ignored")
H.check(T.AuraEventIsRelevant("player", nil) == true,
    "no payload at all -> refresh, we cannot tell")
H.check(T.AuraEventIsRelevant("raid1", {
    addedAuras = { { name = "Power Word: Fortitude" } } }) == true,
    "one of our buffs being applied is relevant")
H.check(T.AuraEventIsRelevant("raid1", {
    addedAuras = { { name = "Renew" }, { name = "Mark of the Wild" } } }) == false,
    "somebody else's HoT ticking is not")

H.done("test_buffs")
