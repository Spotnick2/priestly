-- Fortitude's row must stop aiming at a member the client refuses it on.
-- A world buff (Might of Stormwind, Warchief's Blessing) or Camp Benefits can
-- make a Fortitude cast fail with "A more powerful spell is already active".
-- The row's automatic target used to stay on that member, so every click
-- failed and nobody else got buffed (LibGroupBuffs #95). Whether one blocks
-- depends on the caster's rank, so it can't be listed; the library learns it
-- from the client's refusal instead (r39, #97), from the events Priestly
-- forwards. The sequence is the measured one: SENT, FAILED with its castGUID,
-- then UI error 57 with SPELL_FAILED_AURA_BOUNCED. The library tracks no
-- click: SENT names the target and the rank, so a cast from the window, an
-- action bar or a macro teaches it alike.
--
--   & 'C:\Program Files (x86)\Lua\5.1\lua.exe' tests\test_refusal.lua
dofile("tests/wow_stubs.lua")
local H = dofile("tests/harness.lua")
local T = H.loadAddon()

local BOUNCED = "A more powerful spell is already active"

local function setup(known)
    WoW.reset()
    PriestlyAccountDB = nil
    Priestly_EnsureDefaults()
    H.TeachSpells(known)
    T.RefreshSpellData()
    rawset(_G, "SPELL_FAILED_AURA_BOUNCED", BOUNCED)
    WoW.groupMembers = 3
    WoW.SetUnit("player", { name = "Priest", guid = "P", class = "PRIEST" })
    WoW.SetUnit("party1", { name = "Warrior", guid = "W", class = "WARRIOR" })
    WoW.SetUnit("party2", { name = "Mage", guid = "M", class = "MAGE" })
    WoW.SetAura("player", H.NAME.FORT_SINGLE, 3600, 3000, H.SPELL.FORT_SINGLE)
end

local function fortRow()
    T.UpdateUI()
    for _, row in ipairs(T.rows()) do
        if row._active and row._def.id == "fort" then return row end
    end
end

local cast = 0
local function refuse(target)
    cast = cast + 1
    local guid = "Cast-" .. cast
    WoW.dispatch("UNIT_SPELLCAST_SENT", "player", target, guid, H.SPELL.FORT_SINGLE)
    WoW.dispatch("UNIT_SPELLCAST_FAILED", "player", guid, H.SPELL.FORT_SINGLE)
    WoW.dispatch("UI_ERROR_MESSAGE", 57, BOUNCED)
end

H.check(T.ui.RefusalEvents ~= nil, "the library has refusal memory (r39)")

-- The single-target click is the one that skips: the left click without
-- Prayer, the right click with it.
for _, case in ipairs({
    { known = { "FORT_SINGLE" }, button = "LeftButton", attr = "unit1", label = "single only, left click" },
    { known = { "FORT_SINGLE", "FORT_GROUP" }, button = "RightButton", attr = "unit2", label = "with Prayer, right click" },
}) do
    setup(case.known)
    local row = fortRow()
    H.check(row ~= nil, case.label .. ": the Fortitude row is shown")
    if row and T.ui.RefusalEvents then
        T.ui:RowPreClick(row, case.button)
        H.eq(row:GetAttribute(case.attr), "party1", case.label .. ": the click aims at the first member missing it")
        refuse("Warrior")
        H.check(T.engine:RefusalOf("party1", row._def) ~= nil,
            case.label .. ": Priestly's forwarded events teach the library the refusal")
        -- The next click, more than a second later: only its PreClick pick
        -- skips the refused member, so the attribute is read straight after it.
        WoW.now = WoW.now + 2
        T.ui:RowPreClick(row, case.button)
        H.eq(row:GetAttribute(case.attr), "party2", case.label .. ": the next click aims past the refused member")
        local stats = T.GroupStat(row._members, row._def)
        H.eq(stats.nMiss, 2, case.label .. ": the refused member still counts as missing")
        -- Combat clears every refusal (a click in combat uses the aim wired
        -- before it). Priestly forwards the combat events too.
        WoW.dispatch("PLAYER_REGEN_DISABLED")
        H.eq(T.engine:RefusalOf("party1", row._def), nil, case.label .. ": entering combat forgets the refusal")
        WoW.dispatch("PLAYER_REGEN_ENABLED")
    end
end

-- A pet leaving prunes the engine, which drops its refusals (#97), so one
-- back within 30 s isn't skipped for a refusal it no longer has.
do
    local pruned, real = 0, T.engine.PruneCache
    T.engine.PruneCache = function(...) pruned = pruned + 1; return real(...) end
    WoW.dispatch("UNIT_PET", "party1")
    T.engine.PruneCache = real
    H.eq(pruned, 1, "UNIT_PET prunes the engine")
end

H.done("test_refusal")
