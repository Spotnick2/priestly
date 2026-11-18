------------------------------------------------------------
-- test_methods.lua - every widget method Priestly (and the library under it)
-- calls exists on the client, for that widget type: WowTestKit's
-- Kit.checkMethods, against the build tests/kit.pin names.
--
-- The stub is the list of what this client has, methods included: a method
-- the build lacks reads as nil and fails where it is called. That does not
-- catch a method the stub IMPLEMENTS called on the wrong type (a
-- FontString:SetTexCoord), which this does. So the exercise below reaches as
-- much as is cheap: login, the window (rows, popover, footer, timers, drag,
-- minimize, a close in combat and the reopen), every slash command, and every
-- handler the options panel installs.
------------------------------------------------------------

dofile("tests/wow_stubs.lua")
local H = dofile("tests/harness.lua")
local T = H.loadAddon()
local ui = T.ui

-- Call a frame's handler, counting a throw as a failure rather than ending the
-- run: the methods it reached before throwing are still recorded.
local function run(frame, script, ...)
    local fn = frame and frame._scripts and frame._scripts[script]
    if not fn then return false end
    local ok, err = pcall(fn, frame, ...)
    check(ok, (frame.GetName and frame:GetName() or "a frame") .. " " .. script .. " ran: " .. tostring(err))
    return ok
end

-- A priest in a party of three, one of them buffed, with candles in the bags.
WoW.reset()
PriestlyAccountDB, PriestlyDB = nil, nil
H.TeachSpells({ "FORT_SINGLE", "FORT_GROUP", "SPIRIT_SINGLE", "SHADOW_SINGLE" })
WoW.SetUnit("player", { name = "Karuzo Elegia", guid = "P0", class = "PRIEST" })
WoW.SetUnit("party1", { name = "Zoruka Mortalis", guid = "P1", class = "WARRIOR" })
WoW.SetUnit("party2", { name = "Morphisto Ruskador", guid = "P2", class = "MAGE" })
WoW.groupMembers = 3
WoW.SetAura("party1", H.NAME.FORT_SINGLE, 3600, 1200)
WoW.itemCounts[17029] = 5

-- Every event any frame registered, PLAYER_LOGIN first.
WoW.dispatch("ADDON_LOADED", "Priestly")
WoW.dispatch("PLAYER_LOGIN")
WoW.dispatch("PLAYER_ENTERING_WORLD", true, false)
for _, set in pairs(WoW.events) do
    for e in pairs(set) do
        if e ~= "PLAYER_LOGIN" then WoW.dispatch(e, "player") end
    end
end
SlashCmdList.PRIESTLY("show")
WoW.flushTimers(); WoW.flushTimers()

-- The window: rows, the popover and its rows, the footer, the click hint.
local rows = {}
for _, r in ipairs(ui.rows or {}) do if r._active then rows[#rows + 1] = r end end
check(#rows > 0, "the window has rows to exercise")
for _, r in ipairs(rows) do
    run(r, "OnEnter")
    run(r, "PreClick", "LeftButton", false)
    run(r, "PostClick", "LeftButton", false)
    run(r, "PreClick", "RightButton", false)
    run(r, "PostClick", "RightButton", false)
    run(r, "OnLeave")
end
if rows[1] then ui:UpdatePopover(rows[1], rows[1]._members, rows[1]._def) end
for _, pr in ipairs(ui.popRows or {}) do
    if pr._unit then
        run(pr, "OnEnter")
        run(pr, "PreClick", "LeftButton", false)
        run(pr, "PostClick", "LeftButton", false)
        run(pr, "OnLeave")
    end
end
for _, b in ipairs(ui.footerBtns or {}) do
    if b:IsShown() then run(b, "OnEnter"); run(b, "OnLeave") end
end
run(ui.main, "OnUpdate", 0.6)
ui:RefreshTimers()
if ui.main.dragHandle then
    run(ui.main.dragHandle, "OnDragStart")
    run(ui.main.dragHandle, "OnDragStop")
end
local mb = ui.main.minimizeBtn
if mb then run(mb, "OnEnter"); run(mb, "OnClick"); run(mb, "OnLeave"); run(mb, "OnClick") end

-- A close in combat, kept until the fight ends, then the reopen.
WoW.inCombat = true
ui:Update()
SlashCmdList.PRIESTLY("hide")
WoW.inCombat = false
WoW.dispatch("PLAYER_REGEN_ENABLED")
SlashCmdList.PRIESTLY("show")
WoW.flushTimers(); WoW.flushTimers()
if ui.main.closeBtn then
    run(ui.main.closeBtn, "OnEnter"); run(ui.main.closeBtn, "OnLeave")
    run(ui.main.closeBtn, "OnClick", "LeftButton")
end

-- Every slash command ("adopt" with no other character to adopt from).
for _, cmd in ipairs({ "", "help", "pos", "reset", "show", "hide", "adopt", "config" }) do
    local ok, err = pcall(SlashCmdList.PRIESTLY, cmd)
    check(ok, "/priestly " .. cmd .. " ran: " .. tostring(err))
    WoW.flushTimers()
end

-- The options panel: every handler on it and on everything under it.
local panel = _G["PriestlyOptionsPanel"]
check(panel ~= nil, "the options panel exists")
local seen = {}
local function walk(f)
    if type(f) ~= "table" or seen[f] then return end
    seen[f] = true
    run(f, "OnShow")
    run(f, "OnEnter"); run(f, "OnLeave")
    run(f, "OnClick", "LeftButton")
    run(f, "OnClick", "LeftButton")      -- toggled back
    -- By type: reading f.GetValue on a Button would itself be recorded.
    if f:GetObjectType() == "Slider" then run(f, "OnValueChanged", f:GetValue(), true) end
    for _, child in ipairs({ f:GetChildren() }) do walk(child) end
end
walk(panel)
WoW.flushTimers()

-- Every method recorded must be on that widget type in the pinned build. The
-- floor is what the exercise records today, rounded down: it keeps the
-- exercise from quietly shrinking.
local recorded = Kit.checkMethods()
check(recorded >= 120,"the exercise reached the window and the options (" .. recorded .. " recorded)")

H.done("test_methods")
