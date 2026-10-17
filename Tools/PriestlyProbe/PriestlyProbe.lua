-- ============================================================================
-- PriestlyProbe  -  throwaway API probe for the WoW: Forever 1.60.1 port.
-- A ForeverProbe module: /fp pp
--
-- Deploy with `pwsh Tools\deploy.ps1 -Probe`, /reload, then:
--   /fp pp            lists the commands
--   /fp pp all        every section, into the console and the saved log
--   /fp steps pp      the guided procedures (auras, secure, click, persist)
-- After the owner's /reload, read PriestlyProbeDB (log + sections) from
--   _classic_beta_\WTF\Account\<id>\SavedVariables\PriestlyProbe.lua
-- and the procedures' results from ForeverProbe.lua (steps.records).
--
-- Nothing here ships. Delete Tools/PriestlyProbe once docs/FOREVER-PROBE.md
-- is filled in.
-- ============================================================================

local ADDON, NS = ...
local MAX_LOG = 3000

local Probe = ForeverProbe:Module("PriestlyProbe", { api = 1, cmd = "pp" })

local function say(msg) Probe:Say(msg) end

-- PriestlyProbeDB is bound at this addon's own ADDON_LOADED (the bottom of the
-- file). Until then sections is a scratch table; after it, the saved one.
local sections = {}

------------------------------------------------------------
-- Does this client load SavedVariables back at all?
--
-- Writing them is easy to confirm - the file on disk looks right. Reading them
-- is the part in doubt, and the two are indistinguishable unless something
-- counts sessions: if the load is broken, every launch starts from defaults,
-- rewrites the same file, and looks fine on disk.
--
-- So: capture what arrived BEFORE touching anything, then increment. If the
-- count is always 1, nothing is being read back. Account-wide and
-- per-character are tested separately because they are different mechanisms
-- and only one of them may be broken - which would be a workaround.
------------------------------------------------------------

-- READ THEM IN AN EVENT, NOT AT FILE SCOPE. This file runs BEFORE the client
-- executes the SavedVariables file, so a file-scope read sees nil no matter
-- how well loading works - and a file-scope WRITE is then overwritten by the
-- file being loaded, so the counter never advances and this addon's own data
-- is discarded at every logout.
--
-- Measured, not assumed. This probe read at file scope until 2026-09-25 and
-- reported "arrived: NO" on build 70009, while AltStable's probe - which
-- reads at PLAYER_LOGIN - reported its account table LOADED in the same
-- session and counted up to 9. This probe's file on disk meanwhile stayed
-- frozen at the values written 2026-09-24 10:56 while its timestamp updated
-- at every logout: the loaded table was replacing the one this code had just
-- built, which is the same ordering seen from the other side.
local SV_ACCOUNT_ARRIVED, SV_CHAR_ARRIVED = false, false
local SV_ACCOUNT_BEFORE, SV_CHAR_BEFORE = 0, 0
local svCaptured = false

local function CaptureSavedVariables()
    if svCaptured then return end
    svCaptured = true

    SV_ACCOUNT_ARRIVED = (PriestlyProbePersist ~= nil)
    SV_CHAR_ARRIVED    = (PriestlyProbeChar ~= nil)
    SV_ACCOUNT_BEFORE  = SV_ACCOUNT_ARRIVED and (PriestlyProbePersist.launches or 0) or 0
    SV_CHAR_BEFORE     = SV_CHAR_ARRIVED and (PriestlyProbeChar.launches or 0) or 0

    PriestlyProbePersist = PriestlyProbePersist or { launches = 0, stamps = {} }
    PriestlyProbePersist.launches = (PriestlyProbePersist.launches or 0) + 1
    PriestlyProbePersist.stamps = PriestlyProbePersist.stamps or {}
    PriestlyProbePersist.stamps[#PriestlyProbePersist.stamps + 1] = date("%Y-%m-%d %H:%M:%S")
    PriestlyProbePersist.marker = "written by PriestlyProbe"

    PriestlyProbeChar = PriestlyProbeChar or { launches = 0 }
    PriestlyProbeChar.launches = (PriestlyProbeChar.launches or 0) + 1
end

------------------------------------------------------------
-- Do CVars survive where SavedVariables do not?
--
-- Measured 2026-09-21: neither account-wide nor per-character SavedVariables
-- are read back on this build. CVars are a different mechanism entirely -
-- they live in Config.wtf and the CLIENT loads them at startup, not the addon
-- loader - so they may persist where SavedVariables do not.
--
-- Same shape as the SavedVariables test above, and for the same reason: count
-- launches. Do not read Config.wtf and conclude from its contents, which is
-- exactly how the SavedVariables answer was wrong for a day.
--
-- READ BEFORE REGISTERING. RegisterCVar takes a default value, so registering
-- first could overwrite the very thing we are trying to read back. A CVar that
-- persisted is already readable before we touch it.
------------------------------------------------------------

local CVAR_NAME = "priestlyProbeLaunches"

local CVAR_API, CVAR_ARRIVED, CVAR_BEFORE, CVAR_NOTE
do
    local get = (C_CVar and C_CVar.GetCVar) or _G.GetCVar
    local set = (C_CVar and C_CVar.SetCVar) or _G.SetCVar
    local reg = (C_CVar and C_CVar.RegisterCVar) or _G.RegisterCVar
    CVAR_API = (get and set and reg) and "present" or string.format(
        "INCOMPLETE (get=%s set=%s register=%s)",
        tostring(get ~= nil), tostring(set ~= nil), tostring(reg ~= nil))

    if get and set and reg then
        local ok, raw = pcall(get, CVAR_NAME)
        CVAR_ARRIVED = ok and raw or nil
        if CVAR_ARRIVED == nil then
            local registered = pcall(reg, CVAR_NAME, "0")
            CVAR_NOTE = registered and "not present at load; registered now"
                or "not present at load; RegisterCVar THREW"
            local ok2, raw2 = pcall(get, CVAR_NAME)
            CVAR_ARRIVED = ok2 and raw2 or nil
        else
            CVAR_NOTE = "arrived at load"
        end
        CVAR_BEFORE = tonumber(CVAR_ARRIVED) or 0
        pcall(set, CVAR_NAME, tostring(CVAR_BEFORE + 1))
    else
        CVAR_NOTE = "no usable CVar API"
        CVAR_BEFORE = 0
    end
end

-- Spells the port cares about.
local SPELLS = {
    { id = 1243,  name = "Power Word: Fortitude" },
    { id = 14752, name = "Divine Spirit" },
    { id = 976,   name = "Shadow Protection" },
    { id = 21562, name = "Prayer of Fortitude" },
    { id = 27681, name = "Prayer of Spirit" },
    { id = 27683, name = "Prayer of Shadow Protection" },
    { id = 1706,  name = "Levitate" },
}

local ITEMS = { 17028, 17029, 17056 }  -- Holy Candle, Sacred Candle, Light Feather

local EVENTS = {
    "PLAYER_LOGIN", "READY_CHECK", "UNIT_AURA", "UNIT_PET",
    "RAID_ROSTER_UPDATE", "GROUP_ROSTER_UPDATE",
    "PLAYER_TALENT_UPDATE", "ACTIVE_TALENT_GROUP_CHANGED",
    "PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED",
    "BAG_UPDATE", "SPELLS_CHANGED",
    "ZONE_CHANGED_NEW_AREA", "PLAYER_ENTERING_WORLD",
    "CVAR_UPDATE",
    "CHARACTER_POINTS_CHANGED", "PLAYER_SPECIALIZATION_CHANGED",
}

-- { template, frameType }. The frame type matters: a template's OnLoad calls
-- methods of the type it was written for, so creating MinimalSliderTemplate as
-- a "Button" throws from inside Blizzard's own code and looks like the template
-- is missing when it is not.
local TEMPLATES = {
    { "UICheckButtonTemplate",               "CheckButton" },
    { "InterfaceOptionsCheckButtonTemplate", "CheckButton" },
    { "UIRadioButtonTemplate",               "CheckButton" },
    { "OptionsSliderTemplate",               "Slider" },
    { "UISliderTemplateWithLabels",          "Slider" },
    { "MinimalSliderTemplate",               "Slider" },
    { "UIPanelScrollFrameTemplate",          "ScrollFrame" },
    { "ScrollFrameTemplate",                 "ScrollFrame" },
    { "BackdropTemplate",                    "Frame" },
    { "UIPanelDialogTemplate",               "Frame" },
    { "UIPanelCloseButton",                  "Button" },
    { "UIPanelButtonTemplate",               "Button" },
    { "UIMenuButtonStretchTemplate",         "Button" },
    { "SecureActionButtonTemplate",          "Button" },
}

local UNITS = { "player", "target", "pet", "party1", "party2", "raid1" }

-- ─── formatting ──────────────────────────────────────────────────────────────

-- ForeverProbe's Show/Describe, so a secret value renders as <secret> instead
-- of throwing. Strings stay quoted, as the recorded sections always had them.
local function fmt(v)
    if type(v) == "table" then return Probe.Describe(v, 2) end
    return Probe.Show(v)
end

-- Call fn, never throw. Returns a printable string of everything it returned.
-- Kept local rather than Probe:Try: the sections record this string, and
-- Probe:Try logs a line of its own for MISSING and ERROR.
local function try(fn, ...)
    if type(fn) ~= "function" then return "API MISSING" end
    local packed = Probe.Pack(pcall(fn, ...))
    if not packed[1] then return "ERROR: " .. Probe.Show(packed[2], true) end
    if packed.n <= 1 then return "<no return>" end
    local parts = {}
    for i = 2, packed.n do parts[#parts + 1] = fmt(packed[i]) end
    return table.concat(parts, ", ")
end

local g_section
local function rec(key, value)
    local sec = sections[g_section]
    if not sec then sec = {} sections[g_section] = sec end
    sec[key] = value
    say(string.format("%-54s %s", (g_section or "?") .. "." .. tostring(key), tostring(value)))
end

local function head(name)
    g_section = name
    sections[name] = {}
    say("== " .. name .. " ==")
end

-- ─── probes ──────────────────────────────────────────────────────────────────

local P = {}

function P.client()
    head("client")
    local v, build, bdate, toc = GetBuildInfo()
    rec("GetBuildInfo", string.format("version=%s build=%s date=%s tocVersion=%s",
        tostring(v), tostring(build), tostring(bdate), tostring(toc)))
    rec("WOW_PROJECT_ID", tostring(WOW_PROJECT_ID) ..
        " (MAINLINE=" .. tostring(WOW_PROJECT_MAINLINE) .. ")")
    rec("locale", GetLocale())
    rec("playerLevel", tostring(UnitLevel("player")))
    local _, cls = UnitClass("player")
    rec("playerClass", tostring(cls))
end

function P.events()
    head("events")
    local f = CreateFrame("Frame")
    local bad = 0
    for _, ev in ipairs(EVENTS) do
        local ok, err = pcall(f.RegisterEvent, f, ev)
        rec(ev, ok and "OK" or ("THROWS: " .. tostring(err)))
        if ok then
            pcall(f.UnregisterEvent, f, ev)
        else
            bad = bad + 1
            say("  " .. ev .. " THROWS")
        end
    end
    say("  " .. #EVENTS .. " probed, " .. bad .. " unusable")
end

function P.auras()
    head("auras")
    rec("C_UnitAuras", tostring(C_UnitAuras ~= nil))
    rec("UnitBuff_global", tostring(UnitBuff ~= nil))
    rec("AuraUtil", tostring(AuraUtil ~= nil))
    rec("C_Secrets", tostring(C_Secrets ~= nil))
    rec("inCombat", tostring(InCombatLockdown()))
    if C_Secrets then
        rec("ShouldAurasBeSecret", try(C_Secrets.ShouldAurasBeSecret))
        -- GetSpellAuraSecrecy returns a number; without the enum it means
        -- nothing. Dump whichever enum the client actually has.
        for _, enumName in ipairs({ "SpellAuraSecrecy", "AuraSecrecy", "SecretLevel" }) do
            if Enum and Enum[enumName] then
                rec("Enum." .. enumName, fmt(Enum[enumName]))
            end
        end
        local fns = {}
        for k, v in pairs(C_Secrets) do
            if type(v) == "function" then fns[#fns + 1] = k end
        end
        table.sort(fns)
        rec("C_Secrets functions", table.concat(fns, ", "))
        if C_Secrets.GetSpellAuraSecrecy then
            for _, s in ipairs(SPELLS) do
                rec("GetSpellAuraSecrecy:" .. s.name, try(C_Secrets.GetSpellAuraSecrecy, s.id))
            end
        end
    end
    if not C_UnitAuras then
        say("  C_UnitAuras MISSING")
        return
    end

    for _, unit in ipairs(UNITS) do
        if UnitExists(unit) then
            rec(unit .. ":GetAuraDataByIndex(1,HELPFUL)",
                try(C_UnitAuras.GetAuraDataByIndex, unit, 1, "HELPFUL"))
            rec(unit .. ":GetBuffDataByIndex(1)",
                try(C_UnitAuras.GetBuffDataByIndex, unit, 1))
            local n = 0
            pcall(function()
                for i = 1, 40 do
                    if not C_UnitAuras.GetAuraDataByIndex(unit, i, "HELPFUL") then break end
                    n = i
                end
            end)
            rec(unit .. ":helpfulCount", tostring(n))
            for _, s in ipairs(SPELLS) do
                local r = try(C_UnitAuras.GetAuraDataBySpellName, unit, s.name, "HELPFUL")
                if r ~= "nil" and r ~= "API MISSING" then
                    rec(unit .. ":byName:" .. s.name, r)
                end
            end
        else
            rec(unit, "does not exist")
        end
    end
    say("  combat=" .. tostring(InCombatLockdown()) ..
        " secret=" .. (C_Secrets and try(C_Secrets.ShouldAurasBeSecret) or "?")
        .. "  (/fp steps pp auras reads it in and out of combat)")
end

function P.spells()
    head("spells")
    rec("C_Spell", tostring(C_Spell ~= nil))
    rec("GetSpellInfo_global", tostring(GetSpellInfo ~= nil))
    for _, s in ipairs(SPELLS) do
        if C_Spell then
            rec("byID:" .. s.id .. " (" .. s.name .. ")", try(C_Spell.GetSpellInfo, s.id))
            rec("byName:" .. s.name, try(C_Spell.GetSpellInfo, s.name))
            rec("texByName:" .. s.name, try(C_Spell.GetSpellTexture, s.name))
        end
    end
    local rangeUnit = UnitExists("party1") and "party1" or "target"
    rec("rangeUnit", rangeUnit .. " exists=" .. tostring(UnitExists(rangeUnit)))
    if C_Spell then
        rec("IsSpellInRange(name,unit)", try(C_Spell.IsSpellInRange, "Power Word: Fortitude", rangeUnit))
        rec("IsSpellInRange(id,unit)", try(C_Spell.IsSpellInRange, 1243, rangeUnit))
        rec("IsSpellInRange(unknownName)", try(C_Spell.IsSpellInRange, "Prayer of Fortitude", rangeUnit))
        rec("IsSpellInRange(self)", try(C_Spell.IsSpellInRange, "Power Word: Fortitude", "player"))
        rec("SpellHasRange(PWF)", try(C_Spell.SpellHasRange, "Power Word: Fortitude"))
    end
    rec("IsSpellInRange_global", tostring(IsSpellInRange ~= nil))
    say("  check whether the three Prayer IDs resolve at all")
end

function P.spellbook()
    head("spellbook")
    rec("C_SpellBook", tostring(C_SpellBook ~= nil))
    rec("GetNumSpellTabs_global", tostring(GetNumSpellTabs ~= nil))
    local bank = Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player
    rec("Enum.SpellBookSpellBank.Player", tostring(bank))
    if not C_SpellBook then return end
    for _, s in ipairs(SPELLS) do
        rec("IsSpellKnown:" .. s.name, try(C_SpellBook.IsSpellKnown, s.id, bank))
        rec("IsSpellInSpellBook:" .. s.name, try(C_SpellBook.IsSpellInSpellBook, s.id, bank, false))
        rec("KnownOrInBook:" .. s.name, try(C_SpellBook.IsSpellKnownOrInSpellBook, s.id))
    end
    rec("IsSpellKnown_global(1243)", try(IsSpellKnown, 1243))
    rec("GetNumSpellBookSkillLines", try(C_SpellBook.GetNumSpellBookSkillLines))
    if C_SpellBook.GetNumSpellBookSkillLines then
        local ok, n = pcall(C_SpellBook.GetNumSpellBookSkillLines)
        if ok and type(n) == "number" then
            for i = 1, n do
                rec("skillLine[" .. i .. "]", try(C_SpellBook.GetSpellBookSkillLineInfo, i))
            end
        end
    end
    -- Does anything still expose the "Rank N" subtext GetPrayerRank() parses?
    if C_SpellBook.GetSpellBookItemName then
        local names = {}
        pcall(function()
            for i = 1, 300 do
                local nm, sub = C_SpellBook.GetSpellBookItemName(i, bank)
                if not nm then break end
                names[#names + 1] = nm .. ((sub and sub ~= "") and (" [" .. sub .. "]") or "")
            end
        end)
        rec("spellbookWalk:count", tostring(#names))
        rec("spellbookWalk:all", table.concat(names, " | "))
        say("  spellbook walk saw " .. #names .. " entries (rank subtext in [] if present)")
    end
end

function P.templates()
    head("templates")
    local bad = 0
    for _, entry in ipairs(TEMPLATES) do
        local tpl, frameType = entry[1], entry[2]
        local ok, res = pcall(CreateFrame, frameType, nil, UIParent, tpl)
        if ok and res then
            -- A template that does not exist does NOT throw: CreateFrame just
            -- hands back a bare frame. Look for something the template brings.
            local looksApplied = (res.Left ~= nil) or (res.Text ~= nil) or (res.text ~= nil)
                or (res.SetBackdrop ~= nil) or (res.GetThumbTexture and res:GetThumbTexture() ~= nil)
                or (res.GetNormalTexture and res:GetNormalTexture() ~= nil)
                or (res.ScrollBar ~= nil) or (res.GetAttribute ~= nil and frameType == "Button")
            rec(tpl, looksApplied and "OK" or "created, but no template regions - may not exist")
            pcall(res.Hide, res)
        else
            bad = bad + 1
            rec(tpl, "THROWS as " .. frameType .. ": " .. tostring(res))
            say("  " .. tpl .. " THROWS")
        end
    end
    say("  " .. #TEMPLATES .. " probed, " .. bad .. " threw")
end

function P.names()
    head("names")
    rec("C_PlayerInfo", tostring(C_PlayerInfo ~= nil))
    if C_PlayerInfo then
        rec("ShouldDisplaySurname", try(C_PlayerInfo.ShouldDisplaySurname))
    end
    for _, unit in ipairs({ "player", "target", "party1", "party2", "raid1" }) do
        if UnitExists(unit) then
            rec(unit .. ":UnitName", try(UnitName, unit))
            rec(unit .. ":UnitFullName", try(UnitFullName, unit))
            rec(unit .. ":GetUnitName(true)", try(GetUnitName, unit, true))
            rec(unit .. ":GetUnitName(false)", try(GetUnitName, unit, false))
            rec(unit .. ":UnitNameUnmodified", try(UnitNameUnmodified, unit))
            rec(unit .. ":UnitGUID", try(UnitGUID, unit))
            if C_PlayerInfo then
                rec(unit .. ":C_PlayerInfo.GetName", try(C_PlayerInfo.GetName, unit))
            end
        end
    end
    if IsInRaid() then
        rec("GetRaidRosterInfo(1)", try(GetRaidRosterInfo, 1))
    else
        rec("GetRaidRosterInfo", "not in a raid")
    end
    rec("GetNumGroupMembers", try(GetNumGroupMembers))
    rec("IsInRaid", try(IsInRaid))
    say("  target another player, then run /fp pp names again")
end

function P.misc()
    head("misc")
    for _, id in ipairs(ITEMS) do
        rec("GetItemIconByID:" .. id, C_Item and try(C_Item.GetItemIconByID, id) or "no C_Item")
        rec("C_Item.GetItemInfo:" .. id, C_Item and try(C_Item.GetItemInfo, id) or "no C_Item")
        rec("GetItemCount:" .. id, C_Item and try(C_Item.GetItemCount, id) or "no C_Item")
    end
    rec("GetItemIcon_global", tostring(GetItemIcon ~= nil))
    rec("GetItemInfo_global", tostring(GetItemInfo ~= nil))
    rec("C_Container", tostring(C_Container ~= nil))
    rec("GetInstanceInfo", try(GetInstanceInfo))
    rec("GetRealZoneText", try(GetRealZoneText))
    rec("RAID_CLASS_COLORS", tostring(RAID_CLASS_COLORS ~= nil))
    rec("Settings.RegisterCanvasLayoutCategory",
        tostring(Settings ~= nil and Settings.RegisterCanvasLayoutCategory ~= nil))
    rec("Settings.OpenToCategory", tostring(Settings ~= nil and Settings.OpenToCategory ~= nil))
    rec("InterfaceOptions_AddCategory", tostring(InterfaceOptions_AddCategory ~= nil))
    rec("MouseIsOver", tostring(MouseIsOver ~= nil))
    rec("UnitIsConnected(player)", try(UnitIsConnected, "player"))
end

-- ─── secure click-cast test button ───────────────────────────────────────────

local g_btn
local function BuildSecureButton()
    if g_btn then g_btn:Show() return end
    if InCombatLockdown() then
        say("can't build the button in combat")
        return
    end

    local b = CreateFrame("Button", "PriestlyProbeSecureBtn", UIParent,
        "SecureActionButtonTemplate")
    b:SetSize(230, 44)
    b:SetPoint("CENTER", UIParent, "CENTER", 0, 160)
    b:SetMovable(true)
    b:EnableMouse(true)
    b:RegisterForDrag("MiddleButton")
    b:SetScript("OnDragStart", function(s) s:StartMoving() end)
    b:SetScript("OnDragStop", function(s) s:StopMovingOrSizing() end)
    -- Both edges, matching what Priestly's rows register. With Down only this
    -- button is dead on a release-click client - so it would fail the very
    -- check it exists to support, and look like the addon was broken.
    b:RegisterForClicks("LeftButtonDown", "RightButtonDown",
                        "LeftButtonUp", "RightButtonUp")

    local bg = b:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.10, 0.10, 0.20, 0.95)
    local txt = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    txt:SetPoint("CENTER")
    txt:SetText("PROBE  L: PW:F on party1/self\nR: PW:F on self   (middle-drag to move)")

    local unit = UnitExists("party1") and "party1" or "player"
    b:SetAttribute("type1", "spell")
    b:SetAttribute("spell1", "Power Word: Fortitude")
    b:SetAttribute("unit1", unit)
    b:SetAttribute("type2", "spell")
    b:SetAttribute("spell2", "Power Word: Fortitude")
    b:SetAttribute("unit2", "player")

    -- Exactly Priestly's pattern: mutate secure attributes from an insecure
    -- PreClick, out of combat only.
    b:SetScript("PreClick", function(self, btn)
        if InCombatLockdown() then
            say("PreClick " .. tostring(btn) .. " IN COMBAT - attributes left as-is")
            return
        end
        local u = UnitExists("party1") and "party1" or "player"
        local ok, err = pcall(self.SetAttribute, self, "unit1", u)
        say("PreClick " .. tostring(btn) .. " SetAttribute(unit1=" .. u .. ") -> " ..
            (ok and "ok" or ("" .. tostring(err) .. "")))
    end)
    b:SetScript("PostClick", function(self, btn)
        say("PostClick " .. tostring(btn) .. " combat=" .. tostring(InCombatLockdown()))
    end)

    g_btn = b
    say("secure button created - click it and watch for an actual cast")
    say("then pull something and click it again IN COMBAT")
end

function P.secure()
    head("secure")
    rec("SecureHandlerWrapScript", tostring(SecureHandlerWrapScript ~= nil))
    rec("RegisterStateDriver", tostring(RegisterStateDriver ~= nil))
    rec("loadstring_untainted", tostring(_G.loadstring_untainted ~= nil))
    rec("InCombatLockdown", try(InCombatLockdown))
    local ok, err = pcall(BuildSecureButton)
    rec("buildButton", ok and "OK" or ("ERROR: " .. tostring(err)))

    -- Recorded for reference only. Priestly registers BOTH mouse edges and
    -- lets the client's secure handler pick: it performs the action when
    -- `down == useOnKeyDown`, so exactly one edge ever fires. What these CVars
    -- say no longer changes what the addon does.
    rec("C_CVar", tostring(C_CVar ~= nil))
    rec("C_CVar.GetCVarBool", tostring(C_CVar ~= nil and C_CVar.GetCVarBool ~= nil))
    rec("GetCVarBool_global", tostring(_G.GetCVarBool ~= nil))
    rec("C_CVar.GetCVar", tostring(C_CVar ~= nil and C_CVar.GetCVar ~= nil))
    rec("GetCVar_global", tostring(_G.GetCVar ~= nil))
    local getStr = (C_CVar and C_CVar.GetCVar) or _G.GetCVar
    if getStr then
        rec("ActionButtonUseKeyDown_str", try(getStr, "ActionButtonUseKeyDown"))
    end
    local getBool = (C_CVar and C_CVar.GetCVarBool) or _G.GetCVarBool
    if getBool then
        local gotIt, value = pcall(getBool, "ActionButtonUseKeyDown")
        rec("ActionButtonUseKeyDown", gotIt
            and (tostring(value) .. " (" .. type(value) .. ")")
            or ("THROWS: " .. tostring(value)))
    else
        say("  no CVar API here - which no longer matters:")
        say("  the rows register both edges and the client picks one.")
    end

    -- The other edge can still reach the press-and-hold release path, which
    -- looks up "typerelease" - an attribute Priestly never sets, so it casts
    -- nothing. This records whether that path is even live here.
    if getBool then
        rec("ActionButtonUseKeyHeldSpell", try(getBool, "ActionButtonUseKeyHeldSpell"))
    end

    rec("MANUAL", "did the click cast? out of combat / in combat - record by hand")
    rec("MANUAL_edge", "use /fp steps pp click - it tests both edges without changing a setting")
end

-- ─── encounter journal ───────────────────────────────────────────────────────
-- Where the instance list comes from. The names have to match what
-- GetInstanceInfo() returns when you actually zone in, so they are read from
-- the client rather than transcribed from a website - Forever adds dungeons
-- and raids that exist in no Vanilla list.

function P.journal()
    head("journal")

    rec("EJ_GetNumTiers", try(EJ_GetNumTiers))
    rec("EJ_GetInstanceByIndex", tostring(EJ_GetInstanceByIndex ~= nil))
    rec("C_EncounterJournal", tostring(C_EncounterJournal ~= nil))

    if not EJ_GetInstanceByIndex then
        say("  no encounter journal on this client")
        return
    end

    -- Measured on this client: EJ_GetNumTiers() returns 0 while
    -- EJ_GetInstanceByIndex works fine. `(ok and n) or 1` leaves numTiers at 0
    -- because ZERO IS TRUTHY in Lua, `for tier = 1, 0` never runs, and the
    -- probe silently records nothing - the exact trap AGENTS.md documents, in
    -- the tool built to answer a question that matters.
    local okTiers, reported = pcall(EJ_GetNumTiers)
    local numTiers = 1
    local implicitTier = true
    if okTiers and type(reported) == "number" and reported >= 1 then
        numTiers = reported
        implicitTier = false
    end
    rec("tiersReported", tostring(okTiers and reported or "error"))
    rec("tiersEnumerated", tostring(numTiers) ..
        (implicitTier and " (no tiers; listing whatever is current)" or ""))

    for tier = 1, numTiers do
        local tierName = tier
        if EJ_GetTierInfo then
            local ok, nm = pcall(EJ_GetTierInfo, tier)
            if ok and nm then tierName = nm end
        end
        -- With no tiers to choose from there is nothing to select, and
        -- demanding a selection would throw away the listing that does work.
        local selected = implicitTier
            or (EJ_SelectTier and pcall(EJ_SelectTier, tier))
        if not implicitTier and numTiers > 1 and not selected then
            rec("tier" .. tostring(tierName) .. ".WARNING",
                "EJ_SelectTier failed - the instances below may be another tier's")
            say("  could not select tier " .. tostring(tierName) ..
                "; treat its list as unreliable")
        end

        for _, isRaid in ipairs({ false, true }) do
            local kind = isRaid and "raid" or "dungeon"
            local i, found = 1, 0
            while i <= 60 do
                local ok, instanceID, name = pcall(EJ_GetInstanceByIndex, i, isRaid)
                if not ok or not instanceID then break end
                found = found + 1
                rec(string.format("tier%s.%s[%d]", tostring(tierName), kind, i),
                    string.format("id=%s name=%s", tostring(instanceID), tostring(name)))
                i = i + 1
            end
            say(string.format("  tier %s: %d %ss", tostring(tierName), found, kind))
        end
    end

end

-- Where am I standing right now? The INSTANCE_DB keys must match this exactly.
function P.here()
    local name, instanceType, difficultyID, difficultyName, maxPlayers,
          _, _, instanceMapID = GetInstanceInfo()
    -- Key the section by where we are, so walking several instances
    -- accumulates rather than each run erasing the last.
    head("here." .. tostring(name or "unknown"))
    rec("GetInstanceInfo.name", tostring(name))
    rec("GetInstanceInfo.instanceType", tostring(instanceType))
    rec("GetInstanceInfo.difficultyName", tostring(difficultyName))
    rec("GetInstanceInfo.maxPlayers", tostring(maxPlayers))
    rec("GetInstanceInfo.instanceMapID", tostring(instanceMapID))
    rec("GetRealZoneText", try(GetRealZoneText))
    rec("GetZoneText", try(GetZoneText))
    rec("GetSubZoneText", try(GetSubZoneText))
    say("  run this INSIDE each instance - the name above is the key to use,")
    say("  and instanceMapID is what issue #12 wants instead")
end

-- ─── click-edge test bench ──────────────────────────────────────────
-- Answers the two questions the addon's click registration rests on, WITHOUT
-- changing any client setting.
--
-- The secure handler performs the action when `down == useOnKeyDown`, where
-- useOnKeyDown is the button's own **attribute** if it has one and only falls
-- back to GetCVarBool("ActionButtonUseKeyDown") when it does not. So setting
-- that attribute on a test button simulates a client configured the other way,
-- for that button alone. No /console, nothing to remember to set back.
--
--   A  no attribute     - follows the CVar. This is what Priestly's rows do.
--   B  useOnKeyDown=true  - forces the keydown branch.
--   C  useOnKeyDown=false - forces the keyup branch: what the people who
--                           reported "single click does nothing" have.
--
-- All three register BOTH edges, exactly as the rows do. Casts are counted
-- from UNIT_SPELLCAST_SENT, which fires whether or not the cast lands, so the
-- count is dispatches and not outcomes.
--
-- Expected on a healthy client: every button reports exactly 1.
--   0 on C  -> the keyup branch does not work here and the fix is wrong.
--   2 anywhere -> one click is casting twice, and reagents are being burned.

local g_bench, g_benchCount, g_benchWho, g_benchAt = nil, 0, nil, 0
-- What each button reported for its last click, for the click procedure to check.
local g_benchResults = {}
local g_benchFrame
-- Every click gets a number, and a delayed callback carries the number of the
-- click that scheduled it. Without that, a watchdog left over from an earlier
-- click reports against whatever is being measured NOW - closing a later
-- measurement before its cast arrives and printing "that branch does not
-- dispatch" about a healthy button. Timers cannot be cancelled here, so they
-- have to be able to recognise that they are stale.
local g_benchSeq = 0

-- `seq` is the click this callback was scheduled for. Omit it to report
-- whatever is open right now, which is what the press-time flush wants.
local function BenchReport(seq)
    if seq and seq ~= g_benchSeq then return end
    if not g_benchWho then return end
    local n, who = g_benchCount, g_benchWho
    g_benchWho = nil
    say(string.format("  %s: %d cast(s) sent for that click", who, n))
    g_benchResults[who] = n
    rec("click." .. who, tostring(n))
    if n == 0 then
        say("    that branch does not dispatch on this client")
    elseif n > 1 then
        say("    DOUBLE CAST - two reagents per click")
    end
end

-- A new measurement: forget what the buttons reported, and make every timer
-- already queued for an earlier click stale, so a late report from before the
-- reset cannot land in the new run.
local function ResetBench()
    for k in pairs(g_benchResults) do g_benchResults[k] = nil end
    g_benchWho, g_benchCount = nil, 0
    g_benchSeq = g_benchSeq + 1
end

local function MakeBenchButton(parent, key, label, y, useOnKeyDown)
    local b = CreateFrame("Button", "PriestlyProbeBench" .. key, parent,
        "SecureActionButtonTemplate")
    b:SetSize(250, 30)
    b:SetPoint("TOP", parent, "TOP", 0, y)
    b:EnableMouse(true)
    -- Both edges, as Priestly's rows do.
    b:RegisterForClicks("LeftButtonDown", "RightButtonDown",
                        "LeftButtonUp", "RightButtonUp")

    local bg = b:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.12, 0.12, 0.24, 0.95)
    local txt = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    txt:SetPoint("CENTER")
    txt:SetText(label)

    b:SetAttribute("type1", "spell")
    b:SetAttribute("spell1", "Power Word: Fortitude")
    b:SetAttribute("unit1", "player")
    if useOnKeyDown ~= nil then b:SetAttribute("useOnKeyDown", useOnKeyDown) end

    -- PreClick fires on BOTH edges now, so one physical click arrives as two
    -- calls: press, then release.
    --
    -- Report after the RELEASE, never on a timer from the press. A forced-keyup
    -- button casts on release, so a fixed window from the press closes first
    -- on any click held longer than that - and the bench reports 0, which reads
    -- as "this branch is dead on this client" about a button that works
    -- perfectly. That is the one wrong answer this tool must not give, since
    -- it would argue for reverting a correct fix.
    --
    -- `down` says which edge when the client passes it. When it does not, a
    -- call arriving while a click is still open is the release.
    b:SetScript("PreClick", function(_, _, down)
        local isPress = (down == true) or (down == nil and g_benchWho == nil)
        if isPress then
            BenchReport()   -- flush anything still open, before the seq moves
            g_benchSeq = g_benchSeq + 1
            g_benchAt, g_benchCount, g_benchWho = GetTime(), 0, key
            -- Safety net for a client that only ever delivers one edge, so the
            -- bench says something rather than nothing. Long enough that no
            -- ordinary click, however deliberate, can trip it - and scoped to
            -- this click, so it cannot close a later one.
            local mine = g_benchSeq
            C_Timer.After(10, function() BenchReport(mine) end)
        else
            -- Released. Give the release-edge cast a moment to be sent.
            local mine = g_benchSeq
            C_Timer.After(0.3, function() BenchReport(mine) end)
        end
    end)
    return b
end

local function BuildBench()
    if g_bench then g_bench:Show() return end
    if InCombatLockdown() then
        say("can't build the bench in combat")
        return
    end

    g_benchFrame = CreateFrame("Frame")
    local ok = pcall(g_benchFrame.RegisterEvent, g_benchFrame, "UNIT_SPELLCAST_SENT")
    rec("UNIT_SPELLCAST_SENT", ok and "OK" or "THROWS - counts will all read 0")
    g_benchFrame:SetScript("OnEvent", function(_, _, unit)
        if unit == "player" and g_benchWho then
            g_benchCount = g_benchCount + 1
        end
    end)

    local f = CreateFrame("Frame", "PriestlyProbeBench", UIParent)
    f:SetSize(266, 150)
    f:SetPoint("CENTER", UIParent, "CENTER", 0, -60)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(s) s:StartMoving() end)
    f:SetScript("OnDragStop", function(s) s:StopMovingOrSizing() end)
    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0.85)

    local hdr = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hdr:SetPoint("TOP", f, "TOP", 0, -8)
    hdr:SetText("click each once - drag to move")

    MakeBenchButton(f, "A", "A  follows your setting", -30, nil)
    MakeBenchButton(f, "B", "B  forced keydown",        -64, true)
    MakeBenchButton(f, "C", "C  forced keyup",          -98, false)

    g_bench = f
end

function P.click()
    head("click")
    local okBuild, err = pcall(BuildBench)
    rec("buildBench", okBuild and "OK" or ("ERROR: " .. tostring(err)))
    if not okBuild then return end
    say("  click A, B and C once each, left button.")
    say("  each should report exactly 1 cast.")
    say("  C is the one that matters - it is the setting the people who")
    say("  reported dead clicks are running, simulated without changing yours.")
end

-- ─── commands ────────────────────────────────────────────────────────────────

local ORDER = { "client", "events", "templates", "spells", "spellbook", "auras", "names", "misc", "journal" }

local HELP = {
    client = "build, project, locale, class",
    events = "which events RegisterEvent accepts",
    templates = "which frame templates exist",
    spells = "spell lookups and range",
    spellbook = "spellbook walk, rank subtext",
    auras = "aura reads (/fp steps pp auras: in and out of combat)",
    names = "unit name formats (target another player first)",
    misc = "items, containers, settings API",
    journal = "the encounter journal's instance list",
    here = "where you stand now (run inside each instance)",
    secure = "build the secure click-cast test button",
    click = "build the click-edge test bench",
}

local function runSection(name)
    local ok, err = pcall(P[name])
    if not ok then say(name .. " probe ERRORED: " .. tostring(err)) end
end

for _, name in ipairs({ "client", "events", "templates", "spells", "spellbook", "auras", "names",
                        "misc", "journal", "here", "secure", "click" }) do
    Probe:Command(name, function() runSection(name) end, HELP[name])
end

local function clearSections()
    for k in pairs(sections) do sections[k] = nil end   -- in place: the saved table stays bound
end

Probe:Command("all", function()
    clearSections()
    for _, name in ipairs(ORDER) do runSection(name) end
    say("done. /reload writes it to WTF\\Account\\<id>\\SavedVariables\\PriestlyProbe.lua")
    say("then /fp steps pp secure (click-cast button), click (both mouse edges), persist (full exit)")
end, "every section but here, secure and click")

Probe:Command("clear", function()
    Probe:ClearLog(); clearSections(); ResetBench()
    say("log, sections and click results cleared")
end,
    "empty the saved log and sections")

Probe:Command("hide", function()
    if g_btn then g_btn:Hide() end
    if g_bench then g_bench:Hide() end
end, "hide the secure button and the click bench")

-- Must NOT capture here. Capturing latches, so a caller that beats
-- PLAYER_LOGIN - another addon running this from its own ADDON_LOADED
-- - would freeze the answer at "nothing arrived" for the session, and
-- the counter would not advance either, so the NEXT session reads the
-- same number and the client looks broken. That is the exact false
-- negative this probe was rebuilt to stop reporting.
Probe:Command("sv", function()
    say("== SavedVariables persistence ==")
    if not svCaptured then
        say("  Not captured yet. This is read at PLAYER_LOGIN, because the")
        say("  client runs the saved file after the addon's own files. Ask again")
        say("  once you are in the world.")
        return
    end
    say("  account-wide table arrived at load: " .. (SV_ACCOUNT_ARRIVED and "YES" or "NO"))
    say("  per-character table arrived at load: " .. (SV_CHAR_ARRIVED and "YES" or "NO"))
    say("  launches recorded before this one: account=" .. SV_ACCOUNT_BEFORE ..
        " character=" .. SV_CHAR_BEFORE)
    say("  launches now: account=" .. PriestlyProbePersist.launches ..
        " character=" .. PriestlyProbeChar.launches)
    -- The probe cannot know whether this session followed a /reload or a
    -- full restart, and the answer depends on which. So it reports what
    -- came back and says what that means under each procedure.
    if SV_ACCOUNT_BEFORE == 0 and SV_CHAR_BEFORE == 0 then
        say("  Nothing was read back. Expected on the very first run.")
        say("  Otherwise this is a real failure, whether it followed /reload or a")
        say("  full exit: SavedVariables are re-read from disk either way.")
        say("  (Captured at PLAYER_LOGIN. Read at file scope - as this probe did")
        say("  until 2026-09-25 - it always says NO: the client runs the saved")
        say("  file after the addon's own files.)")
    else
        say("  A value came back. What it means depends on what you did:")
        say("  - after only /reload: inconclusive. Settings have been seen to")
        say("    survive /reload on this client and still be lost on a real restart.")
        say("  - after a FULL exit and relaunch: SavedVariables load on this build.")
        say("  (/fp steps pp persist walks the full-exit check and records it.)")
    end
end, "did SavedVariables come back at login")

Probe:Command("cvar", function()
    say("== CVar persistence ==")
    say("  CVar API: " .. tostring(CVAR_API))
    say("  " .. tostring(CVAR_NOTE))
    say("  value that arrived: " .. tostring(CVAR_ARRIVED))
    say("  launches recorded before this one: " .. tostring(CVAR_BEFORE))
    say("  launches now: " .. tostring(CVAR_BEFORE + 1))
    local info = (C_CVar and C_CVar.GetCVarInfo) or _G.GetCVarInfo
    if info then
        say("  GetCVarInfo: " .. try(info, CVAR_NAME))
    end
    local loaded = C_CVar and C_CVar.AreCVarsLoaded
    if loaded then say("  AreCVarsLoaded: " .. try(loaded)) end
    -- As above: the probe cannot tell a /reload from a real restart, so it
    -- must not guess. Assuming "/reload" would report Blizzard's eventual
    -- fix as inconclusive forever; assuming "restart" is how CVars were
    -- once wrongly recorded as a working store (AltStable PR #33).
    if CVAR_BEFORE == 0 then
        say("  Nothing came back. Expected on the very first run.")
        say("  Otherwise, if this run follows a FULL exit and relaunch, CVars do")
        say("  not persist on this build.")
    else
        say("  A value came back. What it means depends on what you did:")
        say("  - after only /reload: inconclusive. /reload keeps the client")
        say("    running, so the value may simply still be in memory.")
        say("  - after a FULL exit and relaunch: CVars persist on this build.")
    end
end, "did the launch-counting CVar come back at login")

-- ─── procedures ──────────────────────────────────────────────────────────────

-- The login capture is latched, so calling it here is safe whichever of this
-- and the PLAYER_LOGIN handler runs first after a relaunch.
local function persistReport()
    CaptureSavedVariables()
    return string.format("account arrived=%s before=%d; character arrived=%s before=%d; cvar %s before=%d",
        tostring(SV_ACCOUNT_ARRIVED), SV_ACCOUNT_BEFORE, tostring(SV_CHAR_ARRIVED), SV_CHAR_BEFORE,
        tostring(CVAR_NOTE), CVAR_BEFORE)
end

Probe:Steps("persist", {
    rev = 2,
    title = "Do SavedVariables and CVars survive a full exit?",
    { text = "Reading this launch's counters.", auto = true, run = persistReport },
    { text = "Exit the client fully (NOT /reload) and relaunch. This resumes at login.", reload = "exit" },
    -- One check per store, so a lost CVar cannot hide behind a SavedVariables PASS.
    { text = "SavedVariables after the relaunch: did both counters come back?", auto = true, run = persistReport,
      check = function()
          return SV_ACCOUNT_BEFORE > 0 and SV_CHAR_BEFORE > 0,
              "account before=" .. SV_ACCOUNT_BEFORE .. " character before=" .. SV_CHAR_BEFORE
      end },
    { text = "CVar after the relaunch: did its counter come back?", auto = true,
      run = function() return tostring(CVAR_NOTE) .. "; before=" .. tostring(CVAR_BEFORE) end,
      check = function()
          if CVAR_API ~= "present" then return false, "no usable CVar API: " .. tostring(CVAR_API) end
          return CVAR_BEFORE > 0, tostring(CVAR_NOTE) .. "; before=" .. tostring(CVAR_BEFORE)
      end },
})

local function combatState() return InCombatLockdown() and "in combat" or "out of combat" end

Probe:Steps("auras", {
    rev = 1,
    title = "Aura reads, out of combat and in",
    { text = "Out of combat, with a party member targeted if you can. Press Run.",
      button = "Run auras", run = function() P.auras(); return combatState() end },
    { text = "Pull something. Once in combat, press Run again.",
      button = "Run in combat", run = function() P.auras(); return combatState() end },
})

Probe:Steps("secure", {
    rev = 1,
    title = "The secure click-cast button",
    { text = "Building the test button (middle-drag moves it).", auto = true,
      run = function() P.secure(); return g_btn ~= nil end },
    { text = "Left-click the button out of combat. Did Power Word: Fortitude cast?",
      ask = true, screenshot = "secure button" },
    { text = "Right-click it (casts on yourself). Did it cast?", ask = true },
    { text = "Pull something and left-click the button IN COMBAT. Did it cast?", ask = true },
})

Probe:Steps("click", {
    rev = 1,
    title = "One cast per click on each edge setting",
    { text = "Building the click bench.", auto = true,
      run = function() ResetBench(); P.click(); return g_bench ~= nil end },
    { text = "Left-click A, B and C once each. Each should report exactly 1 cast in the console "
          .. "(C is the keyup branch the dead-click reports run). Then press Next.",
      check = function()
          local r = g_benchResults
          return r.A == 1 and r.B == 1 and r.C == 1,
              "A=" .. tostring(r.A) .. " B=" .. tostring(r.B) .. " C=" .. tostring(r.C)
      end },
})

-- ─── boot ────────────────────────────────────────────────────────────────────

local boot = CreateFrame("Frame")
Probe:RegisterEvents(boot, { "ADDON_LOADED", "PLAYER_LOGIN" })
boot:SetScript("OnEvent", function(_, event, name)
    if event == "ADDON_LOADED" then
        if name ~= ADDON then return end
        Probe:Ready()
        -- Saved tables only here, never at file scope: the client loads
        -- SavedVariables after this file runs and would replace them.
        if type(PriestlyProbeDB) ~= "table" then PriestlyProbeDB = {} end
        if type(PriestlyProbeDB.log) ~= "table" then PriestlyProbeDB.log = {} end
        if type(PriestlyProbeDB.sections) ~= "table" then PriestlyProbeDB.sections = {} end
        PriestlyProbeDB.lines = nil          -- the flat log from before ForeverProbe; the host's log replaces it
        sections = PriestlyProbeDB.sections
        Probe:UseLog(PriestlyProbeDB.log, MAX_LOG)
        return
    end
    -- PLAYER_LOGIN. First, before anything reads or writes those tables.
    CaptureSavedVariables()
    PriestlyProbeChar.lastCharacter = (GetUnitName and GetUnitName("player", false)) or "?"
    say("loaded. /fp pp lists the commands, /fp steps pp the procedures.")
    say("  SavedVariables seen at load: account=" .. (SV_ACCOUNT_ARRIVED and "yes" or "no") ..
        " character=" .. (SV_CHAR_ARRIVED and "yes" or "no") ..
        "  (launch #" .. PriestlyProbePersist.launches .. ")")
end)

NS._test = { Probe = Probe }                 -- the test seam, never on _G
