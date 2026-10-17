------------------------------------------------------------
-- test_probe.lua - Tools/PriestlyProbe, a ForeverProbe module (/fp pp).
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
-- ForeverProbe is private and local (..\ForeverProbe, or $FOREVERPROBE): the
-- host is loaded into this stub environment, and CI, which cannot see it,
-- sets FOREVERPROBE_OPTIONAL=1 and skips this file.
--
--   & 'C:\Program Files (x86)\Lua\5.1\lua.exe' tests\test_probe.lua
------------------------------------------------------------

dofile("tests/wow_stubs.lua")
local H = dofile("tests/harness.lua")

WoW.reset()
local FP = H.loadForeverProbe()

local PROBE = "Tools/PriestlyProbe/PriestlyProbe.lua"

-- The client's order: the addon's files, then its ADDON_LOADED (which is when
-- its saved tables are readable), then PLAYER_LOGIN.
-- Only ONE copy of the probe answers an event: a copy left over from an
-- earlier load would satisfy a check on its own, without the copy under test
-- having seen anything (which is how the original of the persistence checks
-- passed a file-scope mutation). So loading drops the previous copy's boot
-- frame, and keeps the host's registrations.
local function loadProbe(login)
    for frame in pairs(WoW.events) do
        if frame._probeBoot then WoW.events[frame] = nil end
    end
    local known = {}
    for frame in pairs(WoW.events) do known[frame] = true end
    local ns = {}
    assert(loadfile(PROBE))("PriestlyProbe", ns)
    for frame in pairs(WoW.events) do
        if not known[frame] then frame._probeBoot = true end
    end
    WoW.dispatch("ADDON_LOADED", "PriestlyProbe")
    if login then WoW.dispatch("PLAYER_LOGIN") end
    return ns
end

loadProbe()

local function fp(cmd) SlashCmdList.FOREVERPROBE(cmd) end

local function sections() return PriestlyProbeDB.sections end

-- Everything the probe has said since line n, from its saved log. Note the
-- guard: table.concat(t, sep, i) defaults j to #t, so with nothing new i > j
-- and it quietly returns the LAST OLD line - which reads as a fresh report that
-- never happened.
local function logSince(n)
    local log = PriestlyProbeDB.log
    if #log <= n then return "" end
    return table.concat(log, " | ", n + 1, #log)
end

H.check(PriestlyProbeDB ~= nil and type(PriestlyProbeDB.log) == "table",
    "the saved log is bound at the probe's own ADDON_LOADED")
H.check(SlashCmdList["PPROBE"] == nil, "the probe has no slash command of its own any more")

local function journalEntries()
    local n = 0
    for key in pairs(sections().journal or {}) do
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

H.check(pcall(fp, "pp journal"), "the journal probe runs")
H.eq(journalEntries(), 3,
    "it enumerates the instances even though EJ_GetNumTiers() reports 0 - the whole point")

------------------------------------------------------------
-- A client that does report tiers still works
------------------------------------------------------------

WoW.ejNumTiers = 2
H.check(pcall(fp, "pp journal"), "the journal probe runs with real tiers")
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
H.check(pcall(fp, "pp journal"), "it survives EJ_SelectTier throwing")
local warned = false
for key in pairs(sections().journal or {}) do
    if key:find("WARNING") then warned = true end
end
H.check(warned, "and says the listing may not be the tier it claims")
WoW.ejSelectThrows = false

------------------------------------------------------------
-- reset() puts the journal back the way this client has it
--
-- The sections above set three tiers and a throwing EJ_SelectTier. If a reset
-- does not clear them, every later section runs against a client that reports
-- a journal this one does not have, and the probe's whole reason for existing
-- - surviving a journal that is half there - is never exercised again.
------------------------------------------------------------

WoW.reset()
H.eq(EJ_GetNumTiers(), 0, "a reset client reports no tiers, the way this one does")
H.check(not WoW.ejSelectThrows, "and EJ_SelectTier is back to working")
H.eq(next(WoW.ejDungeons), nil, "with no instances left over from the section before")

------------------------------------------------------------
-- `here` accumulates rather than overwriting
------------------------------------------------------------

WoW.instanceName = "The Hall of Thanes"
WoW.instanceType = "party"
H.check(pcall(fp, "pp here"), "the here probe runs")
WoW.instanceName = "Ruins of Lordaeron"
H.check(pcall(fp, "pp here"), "and again somewhere else")

H.check(sections()["here.The Hall of Thanes"] ~= nil, "the first instance is kept")
H.check(sections()["here.Ruins of Lordaeron"] ~= nil, "and so is the second")

------------------------------------------------------------
-- Nothing in the probe throws, and none of it goes to chat
--
-- The point of ForeverProbe: diagnostics go to the console and the saved log.
-- (The click bench and the secure button are built here too; their own
-- behaviour is checked below.)
------------------------------------------------------------

WoW.reset()
local before = #PriestlyProbeDB.log
for _, cmd in ipairs({ "client", "events", "templates", "spells", "spellbook",
                       "auras", "names", "misc", "sv", "cvar", "secure", "click",
                       "hide", "all", "nonsense" }) do
    local ok, err = pcall(fp, "pp " .. cmd)
    H.check(ok, "/fp pp " .. cmd .. ": " .. tostring(err))
end
H.check(#PriestlyProbeDB.log > before, "the sections reach the saved log")
H.check(logSince(before):find("== client ==", 1, true), "with their headings")
H.eq(#WoW.messages, 0, "and chat stays empty")

H.check(pcall(fp, "pp clear"), "clear runs")
H.eq(next(sections()), nil, "it empties the sections")
H.check(PriestlyProbeDB.log ~= nil and #PriestlyProbeDB.log <= 1,
    "and the log, in place (the line it says afterwards is the only one)")
loadProbe()      -- the next case builds its own state

------------------------------------------------------------
-- The click bench actually counts
--
-- It exists to answer "does one click cast twice?", so a bench that silently
-- counts nothing would answer "no" to the one question where a wrong "no"
-- costs the user reagents.
------------------------------------------------------------

WoW.reset()
H.check(pcall(fp, "pp click"), "the click bench builds")

local bench = _G.PriestlyProbeBenchC
H.check(bench ~= nil, "the forced-keyup button exists - the branch that matters")
H.eq(#(bench._clicks or {}), 4, "and registers both edges, like the rows it stands in for")
H.eq(bench:GetAttribute("useOnKeyDown"), false,
    "with the attribute that simulates a release-click client, so no /console is needed")
H.eq(_G.PriestlyProbeBenchB:GetAttribute("useOnKeyDown"), true, "and B forces the other branch")
H.check(_G.PriestlyProbeBenchA:GetAttribute("useOnKeyDown") == nil,
    "while A sets none and follows the client")

-- One physical click on a keydown-acting button: press, cast, release.
-- The release must not reset the count, or every reading is a half-click.
before = #PriestlyProbeDB.log
bench._scripts.PreClick(bench, "LeftButton", true)
WoW.dispatch("UNIT_SPELLCAST_SENT", "player")
bench._scripts.PreClick(bench, "LeftButton", false)
WoW.flushTimers()
local said = logSince(before)
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

before = #PriestlyProbeDB.log
bench._scripts.PreClick(bench, "LeftButton", true)      -- pressed, and held
WoW.flushTimers(1.0)                                    -- a second goes by
H.eq(logSince(before), "", "nothing is reported while the button is still held")

WoW.dispatch("UNIT_SPELLCAST_SENT", "player")           -- the release-edge cast
bench._scripts.PreClick(bench, "LeftButton", false)     -- released at last
WoW.flushTimers()
said = logSince(before)
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
before = #PriestlyProbeDB.log
benchA._scripts.PreClick(benchA, "LeftButton", true)
WoW.dispatch("UNIT_SPELLCAST_SENT", "player")
benchA._scripts.PreClick(benchA, "LeftButton", false)
WoW.flushTimers(0.5)          -- the release report only; A's watchdog stays queued
said = logSince(before)
H.check(said:find("A: 1 cast"), "A reports its own click, got: " .. said)

-- Nearly ten seconds pass, so A's watchdog is about to come due...
WoW.flushTimers(9.3)
-- ...and C is clicked right before it does.
before = #PriestlyProbeDB.log
bench._scripts.PreClick(bench, "LeftButton", true)
WoW.flushTimers(0.3)          -- A's stale watchdog fires in here
H.eq(logSince(before), "", "A's leftover timer does not report against C")

WoW.dispatch("UNIT_SPELLCAST_SENT", "player")
bench._scripts.PreClick(bench, "LeftButton", false)
WoW.flushTimers()
said = logSince(before)
H.check(said:find("C: 1 cast"), "C still counts its own cast, got: " .. said)
H.check(not said:find("does not dispatch"),
    "and is never declared dead by someone else's timer")

------------------------------------------------------------
-- A client that does not pass `down` to PreClick
------------------------------------------------------------

before = #PriestlyProbeDB.log
bench._scripts.PreClick(bench)                          -- press
WoW.dispatch("UNIT_SPELLCAST_SENT", "player")
bench._scripts.PreClick(bench)                          -- release
WoW.flushTimers()
said = logSince(before)
H.check(said:find("1 cast"), "the edge is inferred when the client stays quiet, got: " .. said)

------------------------------------------------------------
-- The procedures
--
-- The click procedure passes only when A, B and C each reported exactly one
-- cast, so it is run end to end: its check reads what the bench recorded.
------------------------------------------------------------

local S = FP.Steps
local function record(name) return ForeverProbeDB.steps.records["PriestlyProbe/" .. name] end

H.check(pcall(fp, "steps pp click"), "the click procedure starts")
H.eq(record("click").status, "active", "and is running")
H.check(_G.PriestlyProbeBenchA ~= nil, "its first step built the bench")
-- Step 1 ran on arrival (auto); step 2 waits for the owner. Nothing was
-- clicked on THIS bench yet, so its check must fail rather than pass blind.
S.Next()
S.Next()
H.eq(record("click").results[2].check, "FAIL", "the check fails when no button has reported")
H.eq(record("click").status, "done", "the procedure ends")

-- Now each button reports one cast, for real.
WoW.reset()
fp("steps pp click")      -- starting it builds the bench and forgets earlier results
for _, b in ipairs({ _G.PriestlyProbeBenchA, _G.PriestlyProbeBenchB, _G.PriestlyProbeBenchC }) do
    b._scripts.PreClick(b, "LeftButton", true)
    WoW.dispatch("UNIT_SPELLCAST_SENT", "player")
    b._scripts.PreClick(b, "LeftButton", false)
    WoW.flushTimers()
end
S.Next()
S.Next()
H.eq(record("click").results[2].check, "PASS", "and passes once A, B and C each reported one cast")

-- A SECOND run with no new clicks must not inherit the first run's PASS: the
-- owner retesting after changing a setting or combat state would otherwise be
-- certified by the previous measurement.
fp("steps pp click")
S.Next()
S.Next()
H.eq(record("click").results[2].check, "FAIL",
    "a repeat run with no new clicks fails; it does not inherit the last run's results")

-- And a report still pending from before the reset cannot land in the new run.
fp("pp clear")
fp("pp click")
local staleA = _G.PriestlyProbeBenchA
staleA._scripts.PreClick(staleA, "LeftButton", true)     -- pressed; its 10s watchdog is queued
fp("pp clear")                                           -- a new measurement begins
before = #PriestlyProbeDB.log
WoW.flushTimers()                                        -- the old watchdog comes due
H.eq(logSince(before), "", "and nothing from the old click is reported after the reset")

for _, name in ipairs({ "auras", "secure", "persist" }) do
    H.check(pcall(fp, "steps pp " .. name), "the " .. name .. " procedure starts")
    H.eq(record(name).status, "active", name .. " is running")
    S.Stop()
end
H.eq(#WoW.messages, 0, "and none of it went to chat")

------------------------------------------------------------
-- /fp pp cvar when a value comes back
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
PriestlyProbePersist, PriestlyProbeChar = nil, nil
loadProbe()
before = #PriestlyProbeDB.log
H.check(pcall(fp, "pp cvar"), "/fp pp cvar runs when a value came back")
said = logSince(before)

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

------------------------------------------------------------
-- /fp pp sv had the same flaw: it said "SavedVariables DO load" on any value
-- that came back, which a /reload alone can produce.
--
-- The tables arrive AFTER the addon's files run - that is the client's
-- order, and reading them at file scope is what made this probe report
-- "arrived: NO" on a build where loading worked. So: load the probe with
-- nothing set, hand it the saved tables the way the client does, and only
-- then log in.
------------------------------------------------------------

PriestlyProbePersist, PriestlyProbeChar = nil, nil
loadProbe()
PriestlyProbePersist = { launches = 4, stamps = {} }
PriestlyProbeChar = { launches = 4 }

before = #PriestlyProbeDB.log
H.check(pcall(fp, "pp sv"), "/fp pp sv before login runs")
said = logSince(before)
H.check(said:find("Not captured yet", 1, true),
    "and says it has not captured, rather than reporting nothing arrived: " .. said)
H.eq(PriestlyProbePersist.launches, 4, "without counting a launch (a latch here would freeze the answer)")

WoW.dispatch("PLAYER_LOGIN")
-- The login line reports what the capture saw, and the capture happens there.
-- Move it to file scope - where this copy was loaded with the tables still
-- nil - and this says "account=no" however well loading works.
said = logSince(before)
H.check(said:find("SavedVariables seen at load: account=yes", 1, true),
    "a table handed over after the addon's files ran is seen at login: " .. said)

before = #PriestlyProbeDB.log
H.check(pcall(fp, "pp sv"), "/fp pp sv runs when values came back")
said = logSince(before)
H.check(said:find("inconclusive", 1, true), "sv is inconclusive after only /reload: " .. said)
H.check(said:find("FULL exit and relaunch", 1, true), "and conclusive after a full exit: " .. said)
H.check(not said:find("DO load", 1, true), "with no unconditional claim: " .. said)
-- The point of the change: tables handed over after the files ran are SEEN.
H.check(said:find("arrived at load: YES", 1, true),
    "and a table that arrived after the addon's files ran is seen, not missed: " .. said)
H.check(said:find("before this one: account=4", 1, true), "with the count it brought: " .. said)
H.eq(PriestlyProbePersist.launches, 5, "which this launch then advances")
H.eq(#WoW.messages, 0, "and chat is still empty")

------------------------------------------------------------
-- The persist procedure gives each store its own verdict
--
-- SavedVariables restored with the CVar lost must not read as one PASS for
-- "do SavedVariables and CVars survive". Walk the procedure through its
-- resume and completion path: the check on the CVar step is its own.
------------------------------------------------------------

local function runPersist(label)
    fp("steps pp persist")
    S.Next()      -- the first reading is automatic; this completes it
    S.Next()      -- the exit-and-relaunch step, taken as done
    S.Next()      -- SavedVariables reading
    S.Next()      -- CVar reading
    return record("persist"), label
end

-- Both SavedVariables counters came back, the CVar did not.
store = {}
PriestlyProbePersist, PriestlyProbeChar = nil, nil
loadProbe()
PriestlyProbePersist = { launches = 4, stamps = {} }
PriestlyProbeChar = { launches = 4 }
WoW.dispatch("PLAYER_LOGIN")
local rec = runPersist("sv restored, cvar lost")
H.eq(rec.results[3].check, "PASS", "SavedVariables restored: that step passes")
H.eq(rec.results[4].check, "FAIL", "but the lost CVar fails its own step, not hidden behind it")

-- No usable CVar API at all.
C_CVar = nil
PriestlyProbePersist, PriestlyProbeChar = nil, nil
loadProbe()
PriestlyProbePersist = { launches = 4, stamps = {} }
PriestlyProbeChar = { launches = 4 }
WoW.dispatch("PLAYER_LOGIN")
rec = runPersist("no cvar api")
H.eq(rec.results[3].check, "PASS", "SavedVariables restored without a CVar API: still passes")
H.eq(rec.results[4].check, "FAIL", "and the unavailable CVar API is a FAIL, not a silent pass")

PriestlyProbePersist, PriestlyProbeChar = nil, nil
C_CVar = nil

H.done("test_probe")
