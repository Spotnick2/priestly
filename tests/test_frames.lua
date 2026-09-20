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

-- The poll only does its work once the timer passes its threshold, so a small
-- dt must leave the popover alone.
WoW.mouseOver[pop] = true
runScript(pop, "OnUpdate", 0.01)
H.check(pop:IsShown(), "below the poll threshold nothing happens")

-- Mouse still on the popover: it stays open.
runScript(pop, "OnUpdate", 5.0)
H.check(pop:IsShown(), "the popover stays open while the mouse is over it")

-- Mouse on the anchor row instead: also stays open.
WoW.mouseOver[pop] = nil
WoW.mouseOver[row] = true
runScript(pop, "OnUpdate", 5.0)
H.check(pop:IsShown(), "and while the mouse is over the row that opened it")

-- Mouse somewhere else entirely: it closes.
WoW.mouseOver[row] = nil
runScript(pop, "OnUpdate", 5.0)
H.check(not pop:IsShown(), "and closes once the mouse leaves both")

-- ...and in combat it parks offscreen instead of hiding, because it parents
-- secure buttons.
runScript(row, "OnEnter")
WoW.inCombat = true
runScript(pop, "OnUpdate", 5.0)
H.check(pop._combatHidden == true, "in combat it parks offscreen rather than hiding")
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
    -- Dispatch to every frame registered for the event, as the game does: the
    -- addon has three event frames and only exercising one leaves the others
    -- in a state that never occurs in play.
    local ok, err = pcall(WoW.dispatch, e[1], e[2], e[3])
    H.check(ok, e[1] .. " handler ran: " .. tostring(err))
end

-- Leaving the group while solo display is off closes the window.
WoW.groupMembers = 0
H.check(pcall(WoW.dispatch, "GROUP_ROSTER_UPDATE"), "roster update with an empty group")
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
H.check(pcall(Priestly_OpenConfig), "Priestly_OpenConfig runs")
H.eq(WoW.settingsOpenedTo, 42, "and it opens the registered Settings category")

-- Everything the deferred helpers queued must also run clean.
H.check(pcall(WoW.flushTimers), "queued timers run")



------------------------------------------------------------
-- Regressions from the PR #2 review
------------------------------------------------------------

setup()

-- The UNIT_AURA payload carries aura structs, and their fields throw while
-- secret - which is exactly when UNIT_AURA fires most. Reading one unguarded
-- errored straight out of the event handler, once per aura event, all fight.
local okSecret = pcall(T.AuraEventIsRelevant, "party1",
    { addedAuras = { WoW.SecretAura() } })
H.check(okSecret, "a secret aura in the UNIT_AURA payload does not throw out of the handler")
H.check(T.AuraEventIsRelevant("party1", { addedAuras = { WoW.SecretAura() } }) == true,
    "and an unreadable payload refreshes rather than being skipped")

-- The payload's OWN fields are secret values in combat, and on this client a
-- secret value throws when truth-tested, not only when read. Guarding the
-- aura loop while leaving `if updateInfo.isFullUpdate then` bare one line above
-- it errored out of the handler on the first pull.
local secretInfo = WoW.SecretUpdateInfo()
H.check(pcall(T.AuraEventIsRelevant, "player", secretInfo),
    "a UNIT_AURA payload whose own fields are secret does not throw out of the handler")
H.check(T.AuraEventIsRelevant("player", secretInfo) == true,
    "and counts as relevant, rather than silently dropping the update")

-- ...and the whole way through the event handler, which is where it surfaced.
H.check(pcall(WoW.dispatch, "UNIT_AURA", "player", WoW.SecretUpdateInfo()),
    "UNIT_AURA with a secret payload is handled end to end")

-- Both frames are clamped to the screen, so parking has to drop the clamp or
-- the frame is dragged back to the edge - an invisible, still-clickable row.
T.UpdateUI()
local mainFrame = T.mainFrame()
mainFrame._clamped = true
WoW.inCombat = true
T.CloseUI(false)
H.check(mainFrame._combatHidden == true, "parked during combat")
H.eq(mainFrame._clamped, false, "and the screen clamp is dropped so it really goes offscreen")
WoW.inCombat = false
WoW.dispatch("PLAYER_REGEN_ENABLED")
H.eq(mainFrame._clamped, true, "the clamp comes back when combat ends")
WoW.flushTimers()

-- A ready check is not a reason to reopen a window the user closed.
T.CloseUI(true)
H.eq(PriestlyDB.visible, false, "closed by hand")
WoW.dispatch("READY_CHECK")
WoW.flushTimers()
H.check(not (T.mainFrame():IsShown()), "a ready check does not resurrect it")
H.eq(PriestlyDB.visible, false, "nor overwrite the preference")

-- A group Prayer reaches further than the single-target spell, so the range
-- check must test whichever spell the click will actually cast.
H.TeachSpells({ "FORT_SINGLE", "FORT_GROUP" })
T.RefreshSpellData()
local fortDef
for _, d in ipairs(T.DEFS) do if d.id == "fort" then fortDef = d end end
WoW.SetUnit("party2", { name = "Sten Thornbeard", guid = "P2", class = "MAGE" })
local spread = {
    { unit = "party1", name = "Zoruka Mortalis" },   -- out of reach of either
    { unit = "party2", name = "Sten Thornbeard" },   -- inside 40y, outside 30y
}
WoW.range["party1"] = { ["Power Word: Fortitude"] = false, ["Prayer of Fortitude"] = false }
WoW.range["party2"] = { ["Power Word: Fortitude"] = false, ["Prayer of Fortitude"] = true }

H.eq(T.PickTarget(spread, fortDef, true), "party2",
    "a group Prayer is range-checked against the Prayer's own 40y reach, so it "
    .. "picks the member it can actually land on")

-- The single-target click uses the shorter range, finds nobody inside it, and
-- falls back rather than refusing to cast at all.
H.eq(T.PickTarget(spread, fortDef, false), "party1",
    "the single-target click falls back rather than picking nobody")

WoW.range["party1"] = nil
WoW.range["party2"] = nil

-- An open popover must follow a rebuild. Its rows carry unit tokens, and a
-- roster reshuffle hands those tokens to different players while the mouse is
-- still resting on the row that opened it.
setup()
local anchorRow
for _, r in ipairs(T.rows()) do
    if r._active then anchorRow = r break end
end
runScript(anchorRow, "OnEnter")
H.check(T.popFrame():IsShown(), "popover open")
H.eq(T.popRows()[1]:GetAttribute("unit1"), "player", "aimed at the current roster")

-- party1 leaves; the group is now just the player.
WoW.RemoveUnit("party1")
WoW.groupMembers = 1
T.UpdateUI()
local live = 0
for _, prow in ipairs(T.popRows()) do
    if prow._active then live = live + 1 end
end
H.eq(live, 1, "the popover follows the rebuild instead of listing a departed member")

H.done("test_frames")
