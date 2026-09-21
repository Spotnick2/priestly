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

-- Everything said since message n. Note the guard: table.concat(t, sep, i)
-- defaults j to #t, so with nothing new i > j and it quietly returns the LAST
-- OLD message - which reads as a fresh report that never happened.
local function reportSince(n)
    if #WoW.messages <= n then return "" end
    return table.concat(WoW.messages, " | ", n + 1, #WoW.messages)
end

-- One physical click on a keydown-acting button: press, cast, release.
-- The release must not reset the count, or every reading is a half-click.
local before = #WoW.messages
bench._scripts.PreClick(bench, "LeftButton", true)
WoW.dispatch("UNIT_SPELLCAST_SENT", "player")
bench._scripts.PreClick(bench, "LeftButton", false)
WoW.flushTimers()
local said = reportSince(before)
H.check(said:find("1 cast"), "reports exactly one cast, got: " .. said)
H.check(not said:find("DOUBLE"), "and does not cry double-cast for a single one")

------------------------------------------------------------
-- A HELD click on the forced-keyup button
--
-- C casts on release. Anything that reports on a timer started at the press
-- closes the window first on a click held longer than it, and reports 0 -
-- which reads as "the keyup branch is dead on this client" about a button
-- working perfectly. That is the one wrong answer this bench must never give,
-- because it argues for reverting a correct fix.
------------------------------------------------------------

before = #WoW.messages
bench._scripts.PreClick(bench, "LeftButton", true)      -- pressed, and held
WoW.flushTimers(1.0)                                    -- a second goes by
H.eq(reportSince(before), "", "nothing is reported while the button is still held")

WoW.dispatch("UNIT_SPELLCAST_SENT", "player")           -- the release-edge cast
bench._scripts.PreClick(bench, "LeftButton", false)     -- released at last
WoW.flushTimers()
said = reportSince(before)
H.check(said:find("1 cast"), "the held click still counts its cast, got: " .. said)

------------------------------------------------------------
-- A client that does not pass `down` to PreClick
------------------------------------------------------------

before = #WoW.messages
bench._scripts.PreClick(bench)                          -- press
WoW.dispatch("UNIT_SPELLCAST_SENT", "player")
bench._scripts.PreClick(bench)                          -- release
WoW.flushTimers()
said = reportSince(before)
H.check(said:find("1 cast"), "the edge is inferred when the client stays quiet, got: " .. said)

H.check(pcall(slash, ""), "/pprobe with no argument runs everything")

H.done("test_probe")
