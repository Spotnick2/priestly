------------------------------------------------------------
-- test_frames.lua - run every script handler and event the addon installs.
--
-- The other test files assert behaviour; this one exists to *execute* code,
-- because `tests/wow_stubs.lua` fails on the read of any global it does not
-- stub, and a global that quietly went away in the move to the Retail codebase
-- only shows up when the handler that uses it actually runs.
--
-- This is how MouseIsOver was missed: the popover's OnUpdate hover poll called
-- it, nothing exercised that handler, and the first sign was a Lua error on
-- mouseover in game.
--
--   & 'C:\Program Files (x86)\Lua\5.1\lua.exe' tests\test_frames.lua
------------------------------------------------------------

dofile("tests/wow_stubs.lua")
local H = dofile("tests/harness.lua")
local T, TC = H.loadAddon()

local function setup()
    WoW.reset()
    PriestlyDB = nil
    Priestly_EnsureDefaults()
    H.TeachSpells({ "FORT_SINGLE", "SPIRIT_SINGLE" })
    T.RefreshSpellData()
    WoW.SetUnit("player", { name = "Karuzo Elegia", guid = "P0", class = "PRIEST" })
    WoW.SetUnit("party1", { name = "Zoruka Mortalis", guid = "P1", class = "WARRIOR" })
    WoW.groupMembers = 2
    T.UpdateUI()
end

-- Call a frame's script handler, failing the test rather than the run if it
-- throws - including on an unstubbed global.
local function runScript(frame, script, ...)
    if not frame then H.check(false, "no frame for " .. script) return end
    local fn = frame._scripts and frame._scripts[script]
    if not fn then H.check(false, "no " .. script .. " handler installed") return end
    local ok, err = pcall(fn, frame, ...)
    H.check(ok, script .. " ran without error: " .. tostring(err))
    return ok
end

setup()

------------------------------------------------------------
-- The popover hover poll - where MouseIsOver hid
------------------------------------------------------------

local row = nil
for _, r in ipairs(T.rows()) do
    if r._active then row = r break end
end
H.check(row ~= nil, "there is a row to hover")

runScript(row, "OnEnter")                       -- opens the popover
local pop = T.popFrame()
H.check(pop and pop:IsShown(), "mousing over a row opens the popover")

-- The poll only does its work once the timer passes its threshold, so a big dt
-- is what actually exercises it.
runScript(pop, "OnUpdate", 0.01)
runScript(pop, "OnUpdate", 5.0)
runScript(pop, "OnUpdate", 5.0)

-- ...and again in combat, which takes the offscreen-park branch instead of Hide.
WoW.inCombat = true
pop:Show()
runScript(pop, "OnUpdate", 5.0)
WoW.inCombat = false

------------------------------------------------------------
-- Row and popover-row handlers
------------------------------------------------------------

runScript(row, "PreClick", "LeftButton")
runScript(row, "PreClick", "RightButton")
runScript(row, "PostClick", "LeftButton")
runScript(row, "PostClick", "RightButton")

local pr = T.popRows()[1]
runScript(pr, "OnEnter")
runScript(pr, "OnLeave")
runScript(pr, "PreClick", "LeftButton")
runScript(pr, "PostClick", "LeftButton")

-- An offline member takes the tooltip branch in the popover's OnEnter.
WoW.units.party1.connected = false
T.UpdateUI()
runScript(T.popRows()[1], "OnEnter")
WoW.units.party1.connected = true

------------------------------------------------------------
-- Main frame: ticker, reagent buttons, drag
------------------------------------------------------------

local main = T.mainFrame()
runScript(main, "OnUpdate", 1.0)      -- crosses the 0.5s timer tick
runScript(main, "OnUpdate", 5.0)      -- and the 3s footer tick

H.check(pcall(T.RefreshTimers), "RefreshTimers runs")
H.check(pcall(T.RefreshFooter), "RefreshFooter runs")

-- The reagent buttons only exist once the priest knows the spells that need
-- them, so drive them directly.
for _, name in ipairs({ "candleBtn", "featherBtn" }) do
    local btn = main[name]
    if btn then
        runScript(btn, "OnEnter")
        runScript(btn, "OnLeave")
    end
end

------------------------------------------------------------
-- Close, in and out of combat
------------------------------------------------------------

H.check(pcall(T.CloseUI, true), "CloseUI out of combat")
T.UpdateUI()
WoW.inCombat = true
H.check(pcall(T.CloseUI, false), "CloseUI in combat takes the park branch")
H.check(main._combatHidden == true, "the main frame is parked, not hidden")
WoW.inCombat = false

------------------------------------------------------------
-- Events
------------------------------------------------------------

local evt = T.eventFrame()
H.check(evt ~= nil, "the event frame exists")

local events = {
    { "PLAYER_LOGIN" },
    { "READY_CHECK" },
    { "UNIT_AURA", "player", { isFullUpdate = true } },
    { "UNIT_AURA", "party1", { addedAuras = { { name = "Power Word: Fortitude" } } } },
    { "UNIT_AURA", "nameplate1", { isFullUpdate = true } },
    { "UNIT_PET" },
    { "GROUP_ROSTER_UPDATE" },
    { "RAID_ROSTER_UPDATE" },
    { "PLAYER_TALENT_UPDATE" },
    { "SPELLS_CHANGED" },
    { "ACTIVE_TALENT_GROUP_CHANGED" },
    { "PLAYER_REGEN_ENABLED" },
    { "BAG_UPDATE" },
}
for _, e in ipairs(events) do
    local ok, err = pcall(WoW.fire, evt, e[1], e[2], e[3])
    H.check(ok, e[1] .. " handler ran: " .. tostring(err))
end

-- Leaving the group while solo display is off closes the window.
WoW.groupMembers = 0
H.check(pcall(WoW.fire, evt, "GROUP_ROSTER_UPDATE"), "roster update with an empty group")
WoW.groupMembers = 2

-- And the config's own event frame.
H.check(pcall(TC.CheckCurrentInstance), "instance detection runs")

------------------------------------------------------------
-- Slash commands
------------------------------------------------------------

local slash = SlashCmdList["PRIESTLY"]
H.check(slash ~= nil, "the slash command is registered")
for _, cmd in ipairs({ "", "help", "show", "hide", "close", "reset", "config",
                       "options", "settings", "opt", "garbage" }) do
    local ok, err = pcall(slash, cmd)
    H.check(ok, "/priestly " .. (cmd == "" and "<no args>" or cmd) .. ": " .. tostring(err))
end

------------------------------------------------------------
-- Config helpers that only the panel calls
------------------------------------------------------------

H.check(pcall(Priestly_ApplyAlpha), "Priestly_ApplyAlpha runs")
H.check(pcall(Priestly_ForceRebuild), "Priestly_ForceRebuild runs")
H.check(pcall(Priestly_OnSoloToggle, true), "Priestly_OnSoloToggle(true) runs")
H.check(pcall(Priestly_OnSoloToggle, false), "Priestly_OnSoloToggle(false) runs")
H.check(pcall(Priestly_ScheduleRefresh), "Priestly_ScheduleRefresh runs")
H.check(pcall(Priestly_OpenConfig), "Priestly_OpenConfig runs without the Settings framework")

-- Everything the deferred helpers queued must also run clean.
H.check(pcall(WoW.flushTimers), "queued timers run")

H.done("test_frames")
