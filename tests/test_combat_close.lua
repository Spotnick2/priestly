-- #110: drive the host's real close paths and assert no protected writes.
dofile("tests/wow_stubs.lua")
local H = dofile("tests/harness.lua")
local T = H.loadAddon()

local function settle()
    WoW.flushTimers()
    WoW.flushTimers()
end

for _, action in ipairs({ "button", "slash", "roster", "solo", "popover" }) do
    WoW.reset()
    PriestlyAccountDB, PriestlyDB = nil, nil
    Priestly_EnsureDefaults()
    H.TeachSpells({ "FORT_SINGLE" })
    T.RefreshSpellData()
    WoW.SetUnit("player", { name = "Priest", guid = "P", class = "PRIEST" })
    WoW.SetUnit("party1", { name = "Friend", guid = "F", class = "WARRIOR" })
    WoW.groupMembers = action == "solo" and 0 or 2
    Priestly_SetConfig("showSolo", action == "solo")
    WoW.dispatch("PLAYER_LOGIN")
    SlashCmdList.PRIESTLY("show")
    settle()
    local main = T.mainFrame()
    H.check(main:IsShown(), action .. ": window initially shown")
    if action == "popover" then
        for _, row in ipairs(T.rows()) do
            if row._active then row:GetScript("OnEnter")(row); break end
        end
        H.check(T.popFrame():IsShown(), "popover initially shown")
    end
    WoW.inCombat = true
    if action == "button" then
        main.closeBtn:GetScript("OnClick")(main.closeBtn)
    elseif action == "slash" then
        SlashCmdList.PRIESTLY("hide")
    elseif action == "roster" then
        WoW.groupMembers = 0
        WoW.dispatch("GROUP_ROSTER_UPDATE")
    elseif action == "solo" then
        Priestly_SetConfig("showSolo", false)
        Priestly_OnSoloToggle(false)
    else
        local pop = T.popFrame()
        pop:GetScript("OnUpdate")(pop, 5)
    end
    settle()
    H.check(main:IsShown(), action .. ": main remains physically shown in combat")
    if action == "popover" then
        H.check(T.popFrame():IsShown(), "popover cannot hide during combat")
    else
        H.check(not T.ui:IsVisible(), action .. ": close is logically recorded")
    end
    H.eq(#WoW.blockedCalls, 0, action .. ": no attempted protected-frame operations")
    H.eq(#WoW.combatWrites, 0, action .. ": no secure attribute writes")
    WoW.inCombat = false
    WoW.dispatch("PLAYER_REGEN_ENABLED")
    settle()
    if action == "popover" then
        H.check(not T.popFrame():IsShown(), "deferred popup dismissal completes")
        H.check(main:IsShown(), "popup dismissal leaves main window open")
    else
        H.check(not main:IsShown(), action .. ": deferred close completes")
    end
end
H.done("test_combat_close")
