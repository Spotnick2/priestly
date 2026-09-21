------------------------------------------------------------
-- test_probe.lua - Tools/PriestlyProbe.
--
-- The probe is a throwaway dev tool and would normally not be worth testing.
-- It is tested because of what it is FOR: it is the instrument that answers
-- questions about the live client, and several decisions in this addon rest on
-- its output. A probe that silently reports nothing is worse than no probe,
-- because the empty answer looks like a measurement.
--
-- That is not hypothetical. `EJ_GetNumTiers()` returns 0 on this client while
-- `EJ_GetInstanceByIndex` works perfectly well, and the first version did
-- `numTiers = (ok and n) or 1` - which leaves 0 in place, because ZERO IS
-- TRUTHY in Lua. `for tier = 1, 0` never ran and the journal dump came back
-- empty, looking exactly like "this client has no dungeon list".
--
--   & 'C:\Program Files (x86)\Lua\5.1\lua.exe' tests\test_probe.lua
------------------------------------------------------------

dofile("tests/wow_stubs.lua")
local H = dofile("tests/harness.lua")

WoW.reset()
assert(loadfile("Tools/PriestlyProbe/PriestlyProbe.lua"))()

local slash = SlashCmdList["PPROBE"]
H.check(slash ~= nil, "the probe registers its slash command")

local function journalEntries()
    local section = PriestlyProbeDB and PriestlyProbeDB.journal
    local n = 0
    for key in pairs(section or {}) do
        if key:find("dungeon%[") or key:find("raid%[") then n = n + 1 end
    end
    return n
end

------------------------------------------------------------
-- Zero tiers is this client's answer, not an absence of data
------------------------------------------------------------

WoW.ejNumTiers = 0
WoW.ejDungeons = {
    { id = 1, name = "The Hall of Thanes" },
    { id = 2, name = "Ruins of Lordaeron" },
}
WoW.ejRaids = { { id = 10, name = "The Barrow Deeps" } }

H.check(pcall(slash, "journal"), "the journal probe runs")
H.eq(journalEntries(), 3,
    "it enumerates the instances even though EJ_GetNumTiers() reports 0 - the whole point")

------------------------------------------------------------
-- A client that does report tiers still works
------------------------------------------------------------

WoW.ejNumTiers = 2
H.check(pcall(slash, "journal"), "the journal probe runs with real tiers")
H.eq(journalEntries(), 6,
    "and walks every tier - the stub returns the same list for both, so six entries under two "
    .. "tier keys is the right answer, not a duplicate")

------------------------------------------------------------
-- A failed tier selection must be flagged, not silently repeated
--
-- Without this, every tier records the same list under a different key: a dump
-- that reads as real per-tier data while being one tier repeated, which is the
-- worst possible output from a tool trusted for exact names.
------------------------------------------------------------

WoW.ejNumTiers = 3
WoW.ejSelectThrows = true
H.check(pcall(slash, "journal"), "it survives EJ_SelectTier throwing")
local warned = false
for key in pairs(PriestlyProbeDB.journal or {}) do
    if key:find("WARNING") then warned = true end
end
H.check(warned, "and says the listing may not be the tier it claims")
WoW.ejSelectThrows = false

------------------------------------------------------------
-- `here` accumulates rather than overwriting
------------------------------------------------------------

WoW.reset()
WoW.instanceName = "The Hall of Thanes"
WoW.instanceType = "party"
H.check(pcall(slash, "here"), "the here probe runs")
WoW.instanceName = "Ruins of Lordaeron"
H.check(pcall(slash, "here"), "and again somewhere else")

H.check(PriestlyProbeDB["here.The Hall of Thanes"] ~= nil, "the first instance is kept")
H.check(PriestlyProbeDB["here.Ruins of Lordaeron"] ~= nil, "and so is the second")

------------------------------------------------------------
-- Nothing in the probe throws
------------------------------------------------------------

for _, cmd in ipairs({ "client", "events", "templates", "spells", "spellbook",
                       "auras", "names", "misc", "sv", "secure", "click",
                       "hide", "nonsense" }) do
    local ok, err = pcall(slash, cmd)
    H.check(ok, "/pprobe " .. cmd .. ": " .. tostring(err))
end

------------------------------------------------------------
-- The click bench actually counts
--
-- It exists to answer "does one click cast twice?", so a bench that silently
-- counts nothing would answer "no" to the one question where a wrong "no"
-- costs the user reagents.
------------------------------------------------------------

WoW.reset()
H.check(pcall(slash, "click"), "the click bench builds")

local bench = _G.PriestlyProbeBenchC
H.check(bench ~= nil, "the forced-keyup button exists - the branch that matters")
H.eq(#(bench._clicks or {}), 4, "and registers both edges, like the rows it stands in for")
H.eq(bench:GetAttribute("useOnKeyDown"), false,
    "with the attribute that simulates a release-click client, so no /console is needed")
H.eq(_G.PriestlyProbeBenchB:GetAttribute("useOnKeyDown"), true, "and B forces the other branch")
H.check(_G.PriestlyProbeBenchA:GetAttribute("useOnKeyDown") == nil,
    "while A sets none and follows the client")

-- One physical click: PreClick on press, a cast, PreClick again on release.
-- The second must not reset the count, or every reading is a half-click.
bench._scripts.PreClick(bench)
WoW.dispatch("UNIT_SPELLCAST_SENT", "player")
bench._scripts.PreClick(bench)
local before = #WoW.messages
WoW.flushTimers()
local said = table.concat(WoW.messages, " | ", math.min(before + 1, #WoW.messages))
H.check(said:find("1 cast"), "reports exactly one cast, got: " .. said)
H.check(not said:find("DOUBLE"), "and does not cry double-cast for a single one")

H.check(pcall(slash, ""), "/pprobe with no argument runs everything")

H.done("test_probe")
