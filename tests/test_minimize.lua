-- Priestly owns the opt-in and wording; LibGroupBuffs owns the state machine.
dofile("tests/wow_stubs.lua")
local H = dofile("tests/harness.lua")
local T = H.loadAddon()
WoW.reset()
PriestlyAccountDB, PriestlyDB = nil, nil
Priestly_EnsureDefaults()
H.TeachSpells({ "FORT_SINGLE" })
T.RefreshSpellData()
WoW.SetUnit("player", { name = "Priest", guid = "P", class = "PRIEST" })
WoW.SetUnit("party1", { name = "Friend", guid = "F", class = "WARRIOR" })
WoW.groupMembers = 2
WoW.dispatch("PLAYER_LOGIN")
WoW.flushTimers(); WoW.flushTimers()
local ui, main = T.ui, T.mainFrame()
local btn = main.minimizeBtn
H.check(btn ~= nil, "Priestly opts into the header control")
local height = main:GetHeight()
btn:GetScript("OnClick")(btn)
H.check(ui:IsMinimized() and main:IsShown(), "minimize leaves accessible header")
H.check(main:GetHeight() < height, "body is collapsed")
H.eq(Priestly_WindowVisible(), true, "minimize does not close the saved window")
WoW.inCombat = true
local before = #WoW.messages
btn:GetScript("OnClick")(btn)
H.check(table.concat(WoW.messages, " ", before + 1):find("restores when you leave combat", 1, true),
    "Priestly explains a deferred restore")
H.check(main:GetHeight() < height, "restore waits for combat end")
btn:GetScript("OnClick")(btn)
H.check(WoW.messages[#WoW.messages]:find("minimizes when you leave combat", 1, true),
    "Priestly explains the revised request")
H.eq(#WoW.blockedCalls, 0, "control attempts no protected-frame mutation")
H.eq(#WoW.combatWrites, 0, "control writes no secure attributes")
WoW.inCombat = false
WoW.dispatch("PLAYER_REGEN_ENABLED")
WoW.flushTimers(); WoW.flushTimers()
H.check(ui:IsMinimized() and main:GetHeight() < height, "latest request wins through host event")
btn:GetScript("OnClick")(btn)
H.check(not ui:IsMinimized() and main:GetHeight() == height, "restore returns full layout")
SlashCmdList.PRIESTLY("help")
H.check(table.concat(WoW.messages, " "):find("Header -/+", 1, true), "help describes controls")
H.done("test_minimize")
