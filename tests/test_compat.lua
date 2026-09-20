------------------------------------------------------------
-- test_compat.lua - PriestlyCompat.lua, the WoW: Forever API adapters.
--
-- These are the seams where a mechanical port goes silently wrong: aura
-- structs instead of tuples, IsSpellInRange returning booleans where the old
-- code compared against 1 and 0, and RegisterEvent throwing on names this
-- client does not have.
--
--   & 'C:\Program Files (x86)\Lua\5.1\lua.exe' tests\test_compat.lua
------------------------------------------------------------

dofile("tests/wow_stubs.lua")
local H = dofile("tests/harness.lua")
local _, _, API = H.loadAddon()

local FORT = { "Power Word: Fortitude", "Prayer of Fortitude" }

------------------------------------------------------------
-- GetBuff: struct in, (remaining, duration, expiration) out
------------------------------------------------------------

WoW.reset()
WoW.SetUnit("party1", { name = "Karuzo Elegia" })

H.check(API.GetBuff("party1", FORT) == nil, "no aura -> nil, not a zero tuple")

WoW.SetAura("party1", "Power Word: Fortitude", 3600, 1200)
local rem, dur, exp = API.GetBuff("party1", FORT)
H.eq(rem, 1200, "remaining comes back in seconds")
H.eq(dur, 3600, "duration comes back from the struct")
H.eq(exp, WoW.time + 1200, "expirationTime is passed through for the cache")

-- The group form applies an aura under a different name; both must match.
WoW.ClearAuras("party1")
WoW.SetAura("party1", "Prayer of Fortitude", 3600, 900)
rem = API.GetBuff("party1", FORT)
H.eq(rem, 900, "the Prayer form of the same buff is recognised")

-- A permanent aura reports expirationTime 0, which is not "expired".
WoW.ClearAuras("party1")
WoW.SetAura("party1", "Power Word: Fortitude", 0, nil)
rem = API.GetBuff("party1", FORT)
H.eq(rem, math.huge, "expirationTime 0 means permanent, not expired")

-- The by-name lookup is a fast path, not the truth. On this client
-- C_Spell.GetSpellInfo(name) only resolves spells the PLAYER knows, so if the
-- aura lookup shares that resolution, a priest who has not learned Prayer of
-- Fortitude would never see it on someone another priest buffed. A by-name
-- miss must fall through to the index walk.
WoW.ClearAuras("party1")
WoW.SetAura("party1", "Prayer of Fortitude", 3600, 1500)
WoW.byNameBlind = true
rem = API.GetBuff("party1", FORT)
H.eq(rem, 1500, "a by-name miss falls through to the aura walk instead of reporting unbuffed")
WoW.ClearAuras("party1")
H.check(API.GetBuff("party1", FORT) == nil, "and a genuine absence is still nil")
WoW.byNameBlind = false

------------------------------------------------------------
-- ReadBuff: "not buffed" and "not allowed to look" are different answers
--
-- Measured on build 69913: once combat taints the addon, every index read
-- throws ("Auras cannot be accessed when secret while tainted by '<addon>'")
-- for the player, the target and party members alike - while the by-name
-- lookup quietly returns nil, which is indistinguishable from "not buffed"
-- unless the walk is also attempted.
------------------------------------------------------------

WoW.reset()
WoW.SetUnit("party1", { name = "Karuzo Elegia" })

H.eq(API.ReadBuff("party1", FORT), "NONE", "no aura, readable -> NONE")
WoW.SetAura("party1", "Power Word: Fortitude", 3600, 1200)
local status, r2 = API.ReadBuff("party1", FORT)
H.eq(status, "HAS", "aura present -> HAS")
H.eq(r2, 1200, "with the remaining time")

WoW.auraReadsThrow = true
H.eq(API.ReadBuff("party1", FORT), "BLOCKED",
    "a throwing read is BLOCKED, never mistaken for NONE")
WoW.ClearAuras("party1")
H.eq(API.ReadBuff("party1", FORT), "BLOCKED", "still BLOCKED with no aura to find")
WoW.auraReadsThrow = false

-- If secrecy ever hides auras by returning an empty list instead of throwing,
-- seeing nothing while it is active is still not evidence of being unbuffed.
WoW.secret = true
H.eq(API.ReadBuff("party1", FORT), "BLOCKED",
    "no auras at all while secrecy is active -> BLOCKED, not NONE")
WoW.secret = false
H.eq(API.ReadBuff("party1", FORT), "NONE", "...and NONE once secrecy lifts")

H.eq(API.ReadBuff("raid17", FORT), "NONE", "a unit that does not exist is NONE")

-- A unit that does not exist is not an error.
WoW.SetAura("party1", "Power Word: Fortitude", 3600, 1200)
H.check(API.GetBuff("raid17", FORT) == nil, "missing unit -> nil")
H.check(API.HasBuff("party1", FORT) == true, "HasBuff mirrors GetBuff")

------------------------------------------------------------
-- Range: the 1/0/nil -> true/false/nil trap
--
-- The old code did `if r == 1 ... elseif r == 0`. Ported mechanically that
-- reads everything as unknown, because C_Spell.IsSpellInRange returns
-- booleans - and in Lua `0` is truthy, so the old shape hid the bug.
------------------------------------------------------------

WoW.reset()
H.TeachSpells({ "FORT_SINGLE" })
WoW.SetUnit("party1", { name = "Karuzo Elegia" })

WoW.range.party1 = true
H.eq(API.SpellRange("party1", "Power Word: Fortitude"), "IN_RANGE", "true -> IN_RANGE")

WoW.range.party1 = false
H.eq(API.SpellRange("party1", "Power Word: Fortitude"), "OUT_RANGE",
    "false -> OUT_RANGE, not UNKNOWN")

WoW.range.party1 = nil
H.eq(API.SpellRange("party1", "Power Word: Fortitude"), "UNKNOWN", "nil -> UNKNOWN")

WoW.range.party1 = true
WoW.units.party1.connected = false
H.eq(API.SpellRange("party1", "Power Word: Fortitude"), "OFFLINE",
    "offline beats any range answer")

WoW.units.party1.connected = true
H.eq(API.SpellRange("party1", "Prayer of Fortitude"), "UNKNOWN",
    "a spell this client does not have -> UNKNOWN")
H.eq(API.SpellRange("party1", nil), "UNKNOWN", "no spell -> UNKNOWN")
H.eq(API.SpellRange("raid17", "Power Word: Fortitude"), "UNKNOWN", "no unit -> UNKNOWN")

------------------------------------------------------------
-- Spell data
------------------------------------------------------------

WoW.reset()
H.TeachSpells({ "FORT_SINGLE", "SPIRIT_SINGLE" })

H.eq(API.SpellName(1243), "Power Word: Fortitude", "name resolves from the ID")
H.check(API.SpellName(999999) == nil, "an ID this client has no spell for -> nil")
H.eq(API.SpellIcon(1243), 101243, "icon comes from iconID, not a tuple position")
H.eq(API.SpellIcon(999999, "fallback.blp"), "fallback.blp", "unknown spell falls back")

H.check(API.KnowsSpell(1243) == true, "known by ID")
H.check(API.KnowsSpell(21562) == false, "a defined-but-unknown spell is not known")
H.check(API.KnowsSpell(nil) == false, "nil is not known")

------------------------------------------------------------
-- Items
------------------------------------------------------------

H.eq(API.ItemIcon(17028), "icon:17028", "item icon by ID")
H.check(API.ItemIcon(nil):find("QuestionMark") ~= nil, "no ID -> question mark")

------------------------------------------------------------
-- Identity and names: surnames, and why GUIDs are the key
------------------------------------------------------------

WoW.reset()
WoW.SetUnit("raid3", { name = "Karuzo Elegia", guid = "Player-1" })
WoW.SetUnit("raid4", { name = "Karuzo Mistwalker", guid = "Player-2" })

H.eq(API.UnitDisplayName("raid3"), "Karuzo Elegia", "the surname is part of the name")
H.eq(API.UnitDisplayName("raid4"), "Karuzo Mistwalker", "same first name, different character")
H.check(API.UnitDisplayName("raid3") ~= API.UnitDisplayName("raid4"),
    "two Karuzos are distinguishable only by surname")
H.eq(API.UnitDisplayName("raid9", "fallback"), "fallback", "missing unit uses the fallback")

H.eq(API.UnitKey("raid3"), "Player-1", "identity is the GUID")
H.check(API.UnitKey("raid3") ~= API.UnitKey("raid4"), "GUIDs separate the two Karuzos")

------------------------------------------------------------
-- Event registration: unknown names throw on this client
------------------------------------------------------------

WoW.reset()
local f = CreateFrame("Frame")
H.check(API.RegisterEvents(f, "PLAYER_LOGIN", "UNIT_AURA") == true,
    "known events register cleanly")
H.check(WoW.events[f].PLAYER_LOGIN == true, "PLAYER_LOGIN is registered")

WoW.badEvents.NOT_A_REAL_EVENT = true
local before = #WoW.messages
H.check(API.RegisterEvents(f, "UNIT_PET", "NOT_A_REAL_EVENT") == false,
    "a throwing event name is reported, not swallowed")
H.check(WoW.events[f].UNIT_PET == true, "the good event still registered")
H.check(#WoW.messages > before, "the failure is printed, not silent")
H.check(API.eventFailures.NOT_A_REAL_EVENT ~= nil, "the failure is recorded")

------------------------------------------------------------
-- Combat aura secrecy
------------------------------------------------------------

WoW.reset()
H.check(API.AurasAreSecret() == false, "auras readable out of combat")
WoW.secret = true
H.check(API.AurasAreSecret() == true, "secrecy is reported when the client says so")

H.done("test_compat")
