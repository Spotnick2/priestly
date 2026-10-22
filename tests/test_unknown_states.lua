-- #107/#111: distinguish the two '?' indicators without claiming a live BG repro.
dofile("tests/wow_stubs.lua")
local H = dofile("tests/harness.lua")
local T = H.loadAddon()

for _, locale in ipairs({ "enUS", "deDE" }) do
    for _, instanceType in ipairs({ "none", "pvp" }) do
        WoW.reset()
        PriestlyAccountDB = nil
        Priestly_EnsureDefaults()
        Priestly_SetConfig("shadowMode", "never")
        WoW.locale = locale
        WoW.instanceType = instanceType
        WoW.instanceName = instanceType == "pvp" and "Warsong Gulch" or "Elwynn Forest"
        local single = locale == "deDE" and "Machtwort: Seelenstaerke" or "Power Word: Fortitude"
        local prayer = locale == "deDE" and "Gebet der Seelenstaerke" or "Prayer of Fortitude"
        WoW.Know(1243, single)
        WoW.DefineSpell(21562, prayer) -- known by the client, not learned by this priest
        T.RefreshSpellData()
        WoW.groupMembers = 2
        WoW.SetUnit("player", { name = "Priest", guid = "P", class = "PRIEST" })
        WoW.SetUnit("party1", { name = "Friend", guid = "F", class = "WARRIOR" })
        WoW.SetAura("party1", prayer, 3600, 3000)
        WoW.range.party1 = true
        T.UpdateUI()
        local row
        for _, r in ipairs(T.rows()) do
            if r._active and r._def.id == "fort" then row = r; break end
        end
        H.check(row ~= nil, "Fortitude row exists in " .. locale .. "/" .. instanceType)
        T.UpdatePopover(row, row._members, row._def)
        local pop
        for _, pr in ipairs(T.popRows()) do
            if pr._active and pr._unit == "party1" then pop = pr; break end
        end
        H.check(pop ~= nil, "friend appears in popover")
        H.eq(pop:GetAttribute("spell1"), single, "secure click uses resolved localized name")
        H.eq(select(3, T.BuffRem("party1", row._def)), T.states.HAS,
            "localized unlearned Prayer aura is recognized")
        H.eq(pop.rangeTxt:GetText(), "R", "localized spell range resolves")
        H.check(pop.timeTxt:GetText() ~= "?" and pop.timeTxt:GetText() ~= "MISS",
            "readable localized aura produces a timer")

        WoW.range.party1 = nil
        T.ui:ApplyPopRowVisuals(pop)
        H.eq(pop.rangeTxt:GetText(), "?", "unknown range has its own indicator")
        H.check(pop.timeTxt:GetText() ~= "?", "unknown range does not hide a readable buff")

        -- Model blocked reads separately from locale and instance type. These
        -- flags simulate a possible client response, not measured BG policy.
        WoW.range.party1 = true
        WoW.secret = true
        WoW.auraReadsThrow = true
        T.ui:ApplyPopRowVisuals(pop)
        H.check(pop.timeTxt:GetText() ~= "?", "cached localized buff survives blocked reads")
        WoW.units.party1.guid = "NEW-FRIEND-" .. locale .. "-" .. instanceType
        T.ui:ApplyPopRowVisuals(pop)
        H.eq(pop.timeTxt:GetText(), "?", "new member with blocked reads has no cached state")
        H.eq(pop.rangeTxt:GetText(), "R", "blocked aura does not imply unknown range")
        WoW.secret = false
        WoW.auraReadsThrow = false
        T.ui:ApplyPopRowVisuals(pop)
        H.check(pop.timeTxt:GetText() ~= "?" and pop.timeTxt:GetText() ~= "MISS",
            "live localized aura recovers when reads resume")
    end
end

H.done("test_unknown_states")
