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
-- ReadBuff: struct in, (status, remaining, duration, expiration) out
------------------------------------------------------------

WoW.reset()
WoW.SetUnit("party1", { name = "Karuzo Elegia" })

H.eq(API.ReadBuff("party1", FORT), "NONE", "no aura -> NONE, not a zero tuple")

WoW.SetAura("party1", "Power Word: Fortitude", 3600, 1200)
local _, rem, dur, exp = API.ReadBuff("party1", FORT)
H.eq(rem, 1200, "remaining comes back in seconds")
H.eq(dur, 3600, "duration comes back from the struct")
H.eq(exp, WoW.time + 1200, "expirationTime is passed through for the cache")

-- The group form applies an aura under a different name; both must match.
WoW.ClearAuras("party1")
WoW.SetAura("party1", "Prayer of Fortitude", 3600, 900)
_, rem = API.ReadBuff("party1", FORT)
H.eq(rem, 900, "the Prayer form of the same buff is recognised")

-- A permanent aura reports expirationTime 0, which is not "expired".
WoW.ClearAuras("party1")
WoW.SetAura("party1", "Power Word: Fortitude", 0, nil)
_, rem = API.ReadBuff("party1", FORT)
H.eq(rem, math.huge, "expirationTime 0 means permanent, not expired")

-- The by-name lookup is a fast path, not the truth. On this client
-- C_Spell.GetSpellInfo(name) only resolves spells the PLAYER knows, so if the
-- aura lookup shares that resolution, a priest who has not learned Prayer of
-- Fortitude would never see it on someone another priest buffed. A by-name
-- miss must fall through to the index walk.
WoW.ClearAuras("party1")
WoW.SetAura("party1", "Prayer of Fortitude", 3600, 1500)
WoW.byNameBlind = true
_, rem = API.ReadBuff("party1", FORT)
H.eq(rem, 1500, "a by-name miss falls through to the aura walk instead of reporting unbuffed")
WoW.ClearAuras("party1")
H.eq(API.ReadBuff("party1", FORT), "NONE", "and a genuine absence is still NONE")
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
H.eq(API.ReadBuff("raid17", FORT), "NONE", "missing unit -> NONE")

-- Secrecy has a second shape: the getter succeeds but hands back a struct whose
-- fields are secret. On this client touching one throws - and so does merely
-- COMPARING it, so every match has to happen inside the guard too.
WoW.reset()
WoW.SetUnit("party1", { name = "Karuzo Elegia" })
WoW.SetAura("party1", "Power Word: Fortitude", 3600, 1200)
WoW.aurasAreSecret = true
H.eq(API.ReadBuff("party1", FORT), "BLOCKED",
    "an aura struct with secret fields is BLOCKED, not a crash and not a NONE")
WoW.aurasAreSecret = false
H.eq(API.ReadBuff("party1", FORT), "HAS", "...and readable again once secrecy lifts")

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

-- Counting reagents has to cover the whole carried inventory. The reagent bag
-- sits at Enum.BagIndex.ReagentBag, outside the 0..NUM_BAG_SLOTS range, so a
-- hardcoded `for bag = 0, 4` reports zero for anything stored there - and a
-- reagent bag is exactly where a player keeps candles.
WoW.reset()
H.eq(API.CountItem(17056), 0, "nothing carried")

WoW.itemCounts[17056] = 3
H.eq(API.CountItem(17056), 3, "counts the backpack")

WoW.bags[Enum.BagIndex.ReagentBag] = { { itemID = 17056, stackCount = 7 } }
H.eq(API.CountItem(17056), 10, "and the reagent bag, which is past NUM_BAG_SLOTS")

WoW.bags[3] = { { itemID = 17056, stackCount = 5 } }
H.eq(API.CountItem(17056), 15, "and an ordinary bag in between")
H.eq(API.CountItem(17028), 0, "a reagent we are not carrying is still zero")
H.eq(API.CountItem(nil), 0, "no item id -> zero, not an error")

-- All of the above goes through C_Item.GetItemCount, which answers for the
-- whole carried inventory in one call. The bag walk is the fallback, and it is
-- where the hardcoded `0, 4` lived - so it needs its own coverage rather than
-- being shadowed by the fast path.
local realGetItemCount = C_Item.GetItemCount
C_Item.GetItemCount = nil
H.eq(API.CountItem(17056), 15, "the bag-walk fallback reaches every carried bag too")
WoW.bags[Enum.BagIndex.ReagentBag] = nil
H.eq(API.CountItem(17056), 8, "...and drops what is no longer in the reagent bag")
C_Item.GetItemCount = realGetItemCount

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

------------------------------------------------------------
-- Which mouse edges the secure buttons register for
--
-- Both of them, always. The client's own secure handler computes
-- `down == useOnKeyDown` and performs the action on exactly one edge, so
-- registering both is one cast and is correct whatever ActionButtonUseKeyDown
-- says. Registering one and guessing wrong is a button that does nothing.
------------------------------------------------------------

local edges = { API.ClickEdges() }
H.eq(#edges, 4, "four names: both buttons, both edges")

local seen = {}
for _, e in ipairs(edges) do seen[e] = true end
for _, want in ipairs({ "LeftButtonDown", "RightButtonDown",
                        "LeftButtonUp", "RightButtonUp" }) do
    H.check(seen[want], "registers " .. want)
end

-- No CVar is consulted. The whole point of registering both edges is that the
-- answer stops mattering to us - including mid-combat, when RegisterForClicks
-- is protected and we could not act on a change anyway.
H.check(Priestly._testCompat.cvarBool == nil,
    "the CVar plumbing is gone, not merely unused")

H.done("test_compat")
