-- Fortitude must not ask for casts on Forever's ineligible stat-buff pets.
dofile("tests/wow_stubs.lua")
local H = dofile("tests/harness.lua")
local T = H.loadAddon()

for _, raid in ipairs({ false, true }) do
    for _, track in ipairs({ false, true }) do
        WoW.reset()
        PriestlyAccountDB = nil
        Priestly_EnsureDefaults()
        Priestly_SetConfig("trackPets", track)
        Priestly_SetConfig("shadowMode", "always")
        H.TeachSpells({ "FORT_SINGLE", "FORT_GROUP", "SPIRIT_SINGLE", "SHADOW_SINGLE" })
        T.RefreshSpellData()
        WoW.inRaid = raid
        WoW.groupMembers = 4
        WoW.SetUnit("player", { name = "Priest", guid = "P", class = "PRIEST" })
        local excluded = {}
        for i, class in ipairs({ "HUNTER", "WARLOCK", "MAGE" }) do
            local unit = (raid and "raid" or "party") .. i
            local pet = (raid and "raidpet" or "partypet") .. i
            WoW.SetUnit(unit, { name = class, guid = unit, class = class })
            WoW.SetUnit(pet, { name = "Pet " .. i, guid = pet })
            if raid then WoW.raidRoster[i] = { name = class, subgroup = 1 } end
            if class ~= "MAGE" then excluded[pet] = true end
        end
        if raid then
            WoW.SetUnit("raid4", { name = "Priest", guid = "P", class = "PRIEST" })
            WoW.raidRoster[4] = { name = "Priest", subgroup = 1 }
        end
        T.UpdateUI()
        local totals = { fort = 0, spirit = 0, shadow = 0 }
        for _, row in ipairs(T.rows()) do
            if row._active then
                local id = row._def.id
                local stats = T.GroupStat(row._members, row._def)
                totals[id] = totals[id] + stats.nTotal
                H.eq(stats.nMiss, #row._members, "missing count uses eligible members")
                if id == "fort" then
                    for _, m in ipairs(row._members) do
                        H.check(not excluded[m.unit], "Fortitude members exclude hunter/warlock pets")
                    end
                    H.check(not excluded[row:GetAttribute("unit1")], "primary target is eligible")
                    H.check(not excluded[row:GetAttribute("unit2")], "secondary target is eligible")
                    T.UpdatePopover(row, row._members, row._def)
                    for _, pr in ipairs(T.popRows()) do
                        if pr._active then
                            H.check(not excluded[pr:GetAttribute("unit1")], "popover target is eligible")
                        end
                    end
                end
            end
        end
        H.eq(totals.fort, track and 5 or 4, "Fortitude keeps players and unverified pet types")
        H.eq(totals.spirit, track and 7 or 4, "Spirit eligibility unchanged")
        H.eq(totals.shadow, track and 7 or 4, "Shadow eligibility unchanged")
    end
end

-- A pet-only bucket must disappear entirely for Fortitude, even without Prayer.
WoW.reset()
PriestlyAccountDB = nil
Priestly_EnsureDefaults()
H.TeachSpells({ "FORT_SINGLE" })
T.RefreshSpellData()
WoW.groupMembers = 2
WoW.SetUnit("party1", { name = "Hunter", class = "HUNTER" })
WoW.SetUnit("partypet1", { name = "Pet" })
T.UpdateUI()
for _, row in ipairs(T.rows()) do
    if row._active then
        for _, m in ipairs(row._members) do
            H.check(m.unit ~= "partypet1", "no Fortitude pet row without Prayer")
        end
    end
end
H.done("test_pet_eligibility")
