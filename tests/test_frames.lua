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

-- ...and in combat it stays: it parents secure buttons, so the client refuses
-- to hide it. It goes when the fight ends (docs/FOREVER-PROBE.md section 13).
runScript(row, "OnEnter")
WoW.inCombat = true
runScript(pop, "OnUpdate", 5.0)
H.check(pop:IsShown(), "in combat the popover stays up rather than being hidden")
WoW.inCombat = false
WoW.dispatch("PLAYER_REGEN_ENABLED")
H.check(not pop:IsShown(), "and closes when combat ends")
WoW.flushTimers()

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
-- them (checked further down); drive whichever are built.
for _, btn in ipairs(T.ui.footerBtns) do
    runScript(btn, "OnEnter")
    runScript(btn, "OnLeave")
end

------------------------------------------------------------
-- Header: drag handle and close button
--
-- OnDragStop is the only writer of PriestlyDB.pos and calls
-- StartMoving/StopMovingOrSizing/GetPoint - exactly the shape of call the
-- MouseIsOver regression proved can be silently absent on this client.
------------------------------------------------------------

setup()
local drag = T.mainFrame().dragHandle
H.check(drag ~= nil, "the drag handle is reachable")
runScript(drag, "OnDragStart")
PriestlyDB.pos = nil
runScript(drag, "OnDragStop")
H.check(PriestlyDB.pos ~= nil, "dragging the frame saves its position")
H.check(PriestlyDB.pos.point ~= nil, "with an anchor point")

-- The close button is the other way a user shuts the window.
local closeBtn = T.mainFrame().closeBtn
H.check(closeBtn ~= nil, "the close button is reachable")
runScript(closeBtn, "OnClick")
H.check(not T.mainFrame():IsShown(), "clicking it closes the window")
H.eq(PriestlyDB.visible, false, "and records that as deliberate")

------------------------------------------------------------
-- Close, in and out of combat
------------------------------------------------------------

H.check(pcall(T.CloseUI, true), "CloseUI out of combat")
T.UpdateUI()
WoW.inCombat = true
T.UpdateUI()
H.check(pcall(T.CloseUI, false), "CloseUI in combat")
H.check(main:IsShown(), "the main frame stays up: the client refuses to hide it")
WoW.inCombat = false
WoW.dispatch("PLAYER_REGEN_ENABLED")
H.check(not main:IsShown(), "and it goes when combat ends")
WoW.flushTimers()

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
                       "options", "settings", "opt", "pos", "garbage" }) do
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

-- /priestly hide during a fight cannot hide the window, so it says when it
-- will go. A command that looks ignored is worse than a slow one.
T.UpdateUI()
local mainFrame = T.mainFrame()
WoW.inCombat = true
before = #WoW.messages
SlashCmdList["PRIESTLY"]("hide")
said = table.concat(WoW.messages, " ", before + 1, #WoW.messages)
H.check(mainFrame:IsShown(), "the window is still up during the fight")
H.check(said:find("leave combat"), "and the player is told when it goes: " .. said)
H.eq(PriestlyDB.visible, false, "the preference is saved straight away")
WoW.inCombat = false
WoW.dispatch("PLAYER_REGEN_ENABLED")
H.check(not mainFrame:IsShown(), "combat's end hides it")
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

------------------------------------------------------------
-- Locking the frame
--
-- The drag handler is gated rather than unregistered, so that toggling the
-- lock never touches frame registration - g_Main parents the secure row
-- buttons, and anything structural would have to wait out combat.
------------------------------------------------------------

-- Through runScript, like every other handler here: a raw _scripts call turns
-- a throw into a dead run instead of one reported failure.
PriestlyDB.lockFrame = false
runScript(drag, "OnDragStart")
H.check(T.mainFrame()._moving, "unlocked, the header drags the window")
runScript(drag, "OnDragStop")

PriestlyDB.lockFrame = true
T.mainFrame()._moving = false
runScript(drag, "OnDragStart")
H.check(not T.mainFrame()._moving, "locked, dragging the header does nothing")

-- Locking mid-drag must not strand the frame on the cursor, and must not
-- overwrite the saved position with wherever the mouse happened to be.
PriestlyDB.lockFrame = false
PriestlyDB.pos = nil
runScript(drag, "OnDragStart")
PriestlyDB.lockFrame = true
runScript(drag, "OnDragStop")
H.check(not T.mainFrame()._moving, "a drag interrupted by the lock still stops")
H.check(PriestlyDB.pos == nil, "and does not save a position it was not allowed to move to")

-- A locked window can still be recovered: the lock must not trap it offscreen.
PriestlyDB.pos = { point = "CENTER", relPoint = "CENTER", x = 9999, y = 9999 }
local msgBefore = #WoW.messages
SlashCmdList["PRIESTLY"]("reset")
H.check(PriestlyDB.pos == nil, "/priestly reset works while locked")

-- ...but say so, because the window is now centred AND still locked. Dragging
-- it does nothing and every reload puts it back, which reads exactly like the
-- position not being saved - and was reported as that.
local said = table.concat(WoW.messages, " ", msgBefore + 1, #WoW.messages)
H.check(said:find("locked"), "and says the window is still locked: " .. said)
H.check(said:find("config") or said:find("Lock frame"),
    "pointing at the setting that undoes it: " .. said)

PriestlyDB.lockFrame = false
msgBefore = #WoW.messages
SlashCmdList["PRIESTLY"]("reset")
said = table.concat(WoW.messages, " ", msgBefore + 1, #WoW.messages)
-- Plain-text match on the exact phrase: a bare "locked" substring would fail
-- the day the unlocked path says anything containing "unlocked".
H.check(not said:find("is locked", 1, true), "unlocked, it does not nag: " .. said)

------------------------------------------------------------
-- Row hover handlers
--
-- Every handler the addon installs belongs here, not only in the file that
-- tests what it produces: strict globals only catch code that actually runs.
------------------------------------------------------------

local hoverRow
for _, r in ipairs(T.rows()) do
    if r._active then hoverRow = r break end
end
H.check(hoverRow ~= nil, "there is a drawn row to hover")
runScript(hoverRow, "OnEnter")
runScript(hoverRow, "OnLeave")

-- ...and with hints off, which takes a different path out of ShowClickHint.
PriestlyDB.showClickHints = false
runScript(hoverRow, "OnEnter")
runScript(hoverRow, "OnLeave")
PriestlyDB.showClickHints = true

------------------------------------------------------------
-- The position diagnostic must work when it is most needed
--
-- Somebody runs this because the window is misbehaving, so it has to survive
-- a nil PriestlyDB, an absent pos and an unbuilt frame rather than throwing a
-- second error on top of the first.
------------------------------------------------------------

local before = #WoW.messages
PriestlyDB.pos = nil
H.check(pcall(SlashCmdList["PRIESTLY"], "pos"), "/priestly pos runs with no saved position")
local said = table.concat(WoW.messages, " ", before + 1, #WoW.messages)
H.check(said:find("nothing saved"), "and says so plainly: " .. said)
H.check(said:find("last restore"), "while still reporting what the restore decided")

before = #WoW.messages
PriestlyDB.pos = { point = "RIGHT", relPoint = "RIGHT", x = -350.5, y = -122.8 }
H.check(pcall(SlashCmdList["PRIESTLY"], "pos"), "and with one")
said = table.concat(WoW.messages, " ", before + 1, #WoW.messages)
H.check(said:find("RIGHT"), "reporting the saved anchor: " .. said)

-- The restore decision must survive ordinary refreshes.
--
-- Every UpdateUI after the window is up skips the restore, correctly, because
-- it is already anchored. If a skip overwrote the decision, one aura or roster
-- event would erase the only thing this command exists to report - and it
-- would be gone long before anybody thought to ask. That is a diagnostic that
-- works in testing and is empty exactly when it is needed.
before = #WoW.messages
runScript(T.eventFrame(), "OnEvent", "PLAYER_LOGIN")
WoW.flushTimers()
T.UpdateUI()
T.UpdateUI()
T.UpdateUI()
H.check(pcall(SlashCmdList["PRIESTLY"], "pos"), "/priestly pos after several refreshes")
said = table.concat(WoW.messages, " ", before + 1, #WoW.messages)
H.check(said:find("applied saved") or said:find("DEFAULT"),
    "still reports what the restore actually decided: " .. said)
H.check(not said:find("SKIPPED"), "rather than the skip that came after it: " .. said)
H.check(said:find("refresh"), "while saying refreshes have happened since: " .. said)

------------------------------------------------------------
-- The reagent footer tooltips
--
-- These handlers are why #29 shipped: nothing executed them, the buttons are
-- hidden until a Prayer is learnable, and the stub's catch-all makes an
-- unknown METHOD a silent no-op - so a call to a GameTooltip method this
-- client does not have was invisible to the whole suite. Run them.
------------------------------------------------------------

-- The buttons are built from Priestly's footer items when there is something
-- to show, so teach the spells that need them: a rank 2 Prayer (Sacred
-- Candle) and Levitate (Light Feather).
WoW.Know(21562, "Prayer of Fortitude", "Rank 2")
WoW.Know(1706, "Levitate")
T.RefreshSpellData()
T.UpdateUI()
local candle = T.footerButton(17029)
local feather = T.footerButton(17056)
H.check(candle ~= nil and feather ~= nil, "the reagent buttons exist once the spells are known")

WoW.clearTooltip()
runScript(candle, "OnEnter")
local tip = WoW.tooltipText()
H.check(tip:find("Item 17029"), "the candle tooltip names the item: " .. tip)
H.check(tip:find("in your bags"), "and how many you have: " .. tip)
H.check(tip:find("group Prayers"), "and what consumes it: " .. tip)
runScript(candle, "OnLeave")

WoW.clearTooltip()
runScript(feather, "OnEnter")
tip = WoW.tooltipText()
H.check(tip:find("Levitate"), "the feather tooltip says what it is for: " .. tip)
runScript(feather, "OnLeave")

-- A cache miss must produce a placeholder, not an empty tooltip, and must not
-- throw. GetItemInfo returns NOTHING on a miss rather than nil.
WoW.clearTooltip()
WoW.itemsUncached[17029] = true
runScript(candle, "OnEnter")
tip = WoW.tooltipText()
H.check(tip:find("Loading"), "an uncached item shows a placeholder: " .. tip)
H.check(WoW.itemsRequested[17029], "and the data is requested for next time")
WoW.itemsUncached[17029] = nil

-- A button with no item must bail rather than opening an empty frame.
WoW.clearTooltip()
candle._itemID = nil
runScript(candle, "OnEnter")
H.eq(WoW.tooltipText(), "", "no item means no tooltip at all")
candle._itemID = 17029

H.done("test_frames")
