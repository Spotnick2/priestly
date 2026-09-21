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
                       "auras", "names", "misc", "sv", "cvar", "secure", "click",
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
-- A leftover timer from an EARLIER click must not close a later one
--
-- Each click leaves a 10s watchdog queued. Report the click on release and
-- that watchdog outlives it, still pending while the next button is being
-- measured. Firing it then reports the NEW click's count - zero, because its
-- cast has not arrived yet - and clears the measurement, so the real cast is
-- counted into nothing.
--
-- The earlier tests drain every timer after each click, which is exactly why
-- they could not see this: they disposed of the watchdog before the overlap
-- could happen. This one deliberately leaves it pending.
------------------------------------------------------------

local benchA = _G.PriestlyProbeBenchA
before = #WoW.messages
benchA._scripts.PreClick(benchA, "LeftButton", true)
WoW.dispatch("UNIT_SPELLCAST_SENT", "player")
benchA._scripts.PreClick(benchA, "LeftButton", false)
WoW.flushTimers(0.5)          -- the release report only; A's watchdog stays queued
said = reportSince(before)
H.check(said:find("A: 1 cast"), "A reports its own click, got: " .. said)

-- Nearly ten seconds pass, so A's watchdog is about to come due...
WoW.flushTimers(9.3)
-- ...and C is clicked right before it does.
before = #WoW.messages
bench._scripts.PreClick(bench, "LeftButton", true)
WoW.flushTimers(0.3)          -- A's stale watchdog fires in here
H.eq(reportSince(before), "", "A's leftover timer does not report against C")

WoW.dispatch("UNIT_SPELLCAST_SENT", "player")
bench._scripts.PreClick(bench, "LeftButton", false)
WoW.flushTimers()
said = reportSince(before)
H.check(said:find("C: 1 cast"), "C still counts its own cast, got: " .. said)
H.check(not said:find("does not dispatch"),
    "and is never declared dead by someone else's timer")

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

------------------------------------------------------------
-- /pprobe cvar when a value comes back
--
-- This branch produced a false conclusion once: a counter that survived
-- /reload was reported as "CVars DO persist", but /reload keeps the client
-- process alive, and a full exit lost the value. The branch never ran here,
-- because the CVar API is absent in the stubs - so restoring the old message
-- would have passed every test. Load the probe again with a CVar API that
-- already holds a value, and check what it says.
------------------------------------------------------------

local store = { priestlyProbeLaunches = "2" }
C_CVar = {
    GetCVar = function(name) return store[name] end,
    SetCVar = function(name, value) store[name] = value return true end,
    RegisterCVar = function(name, value) if store[name] == nil then store[name] = value end end,
    GetCVarInfo = function(name) return store[name] end,
    AreCVarsLoaded = function() return true end,
}
assert(loadfile("Tools/PriestlyProbe/PriestlyProbe.lua"))()

local before = #WoW.messages
H.check(pcall(SlashCmdList["PPROBE"], "cvar"), "/pprobe cvar runs when a value came back")
local said = table.concat(WoW.messages, " | ", before + 1, #WoW.messages)

H.check(said:find("before this one: 2", 1, true), "it reads the value that arrived: " .. said)
H.eq(store.priestlyProbeLaunches, "3", "and counts this launch")
-- The probe cannot know whether this followed a /reload or a real restart,
-- so it must not assume either. Assuming /reload would report Blizzard's fix
-- as inconclusive forever; assuming a restart is the original false positive.
H.check(said:find("came back", 1, true), "it reports what it saw: " .. said)
H.check(said:find("inconclusive", 1, true), "calls it inconclusive after only /reload: " .. said)
H.check(said:find("FULL exit and relaunch", 1, true), "and conclusive after a full exit: " .. said)
H.check(not said:find("process stayed alive", 1, true),
    "without asserting which one happened: " .. said)
H.check(not said:find("DO persist", 1, true), "and with no unconditional claim: " .. said)
H.check(not said:find("usable store", 1, true), "or advice to build on it: " .. said)

-- /pprobe sv had the same flaw: it said "SavedVariables DO load" on any value
-- that came back, which a /reload alone can produce.
PriestlyProbePersist = { launches = 4, stamps = {} }
PriestlyProbeChar = { launches = 4 }
assert(loadfile("Tools/PriestlyProbe/PriestlyProbe.lua"))()
before = #WoW.messages
H.check(pcall(SlashCmdList["PPROBE"], "sv"), "/pprobe sv runs when values came back")
said = table.concat(WoW.messages, " | ", before + 1, #WoW.messages)
H.check(said:find("inconclusive", 1, true), "sv is inconclusive after only /reload: " .. said)
H.check(said:find("FULL exit and relaunch", 1, true), "and conclusive after a full exit: " .. said)
H.check(not said:find("DO load", 1, true), "with no unconditional claim: " .. said)
PriestlyProbePersist, PriestlyProbeChar = nil, nil

C_CVar = nil

H.done("test_probe")
