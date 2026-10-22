-- #111: localized Shadow detection and remembered-name recovery through the host.
dofile("tests/wow_stubs.lua")
local H = dofile("tests/harness.lua")
local T = H.loadAddon()
WoW.reset()
PriestlyAccountDB, PriestlyDB = nil, nil
Priestly_EnsureDefaults()
Priestly_SetConfig("shadowMode", "detect")
WoW.locale = "deDE"
local single, prayer = "Schattenschutz", "Gebet des Schattenschutzes"
H.TeachSpells({ "SHADOW_SINGLE" })
WoW.Know(H.SPELL.SHADOW_SINGLE, single)
WoW.DefineSpell(H.SPELL.SHADOW_GROUP, prayer)
T.RefreshSpellData()
WoW.groupMembers = 2
WoW.SetUnit("player", { name = "Priest", guid = "P", class = "PRIEST" })
WoW.SetUnit("party1", { name = "Friend", guid = "F", class = "WARRIOR" })
local groups, ord = T.GatherGroups()
H.check(not Priestly_ShouldShowShadow(groups, ord), "detect hides absent localized Shadow")
for _, name in ipairs({ single, prayer }) do
    WoW.ClearAuras("party1")
    WoW.SetAura("party1", name, 600, 300)
    H.check(Priestly_ShouldShowShadow(groups, ord), "detect recognizes " .. name)
    T.UpdateUI()
    local row
    for _, r in ipairs(T.rows()) do
        if r._active and r._def.id == "shadow" then row = r; break end
    end
    H.check(row ~= nil, "detected localized Shadow has a row")
    H.eq(row:GetAttribute("spell1"), single, "unknown Prayer falls back to localized single cast")
    H.eq(row:GetAttribute("spell2"), single, "secondary click uses localized single cast")
    H.eq(select(3, T.BuffRem("party1", row._def)), T.states.HAS,
        "detected aura and member state agree")
end

-- A transient lookup failure must retain a previously resolved name, and say
-- remembered rather than falsely calling that name an English fallback.
local spellName = Priestly.API.SpellName
Priestly.API.SpellName = function(id)
    if id == H.SPELL.SHADOW_SINGLE or id == H.SPELL.SHADOW_GROUP then return nil end
    return spellName(id)
end
T.RefreshSpellData()
Priestly.API.SpellName = spellName
local shadow
for _, d in ipairs(T.DEFS) do if d.id == "shadow" then shadow = d; break end end
H.eq(shadow.sngl, single, "temporary failure retains localized single name")
H.eq(shadow.grp, prayer, "temporary failure retains localized Prayer name")
H.eq(shadow.snglFrom, "remembered", "diagnostic distinguishes remembered from fallback")
H.check(Priestly_ShouldShowShadow(groups, ord), "detection still works with remembered names")
T.RefreshSpellData()
H.eq(shadow.snglFrom, "resolved", "successful lookup restores resolved status")
H.eq(shadow.grpFrom, "resolved", "unlearned Prayer resolves by ID again")
WoW.ClearAuras("party1")
H.check(not Priestly_ShouldShowShadow(groups, ord), "removed localized aura stops detection")
H.done("test_localized_shadow")
