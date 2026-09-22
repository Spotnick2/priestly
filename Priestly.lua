-- ============================================================================
-- Priestly Forever  –  Pally Power–style Priest buff manager
-- World of Warcraft: Forever 1.60.1  ·  /priestly [show|hide|help]
--
-- Every removed/moved API goes through Priestly.API (PriestlyCompat.lua).
--
-- Main frame rows (per group, per buff):
--   [Icon] [██████████████  2  27:54]   ← left-click = group Prayer, or the
--                                          single buff when no Prayer exists
--                                        ← right-click = single on 1st missing
--                                        ← mouseover = popover
--
-- Popover (left panel, on mouseover):
--   [PrayerIcon]  Prayer of Fortitude
--   ──────────────────────────────────
--   R [ClassIcon] Name           27:54  ← left-click = group Prayer on them
--   R [ClassIcon] Name            MISS  ← right-click = single buff
--   R [ClassIcon] Name               ?  ← aura unreadable (combat secrecy)
-- ============================================================================

local addonName = "Priestly"

-- ─── Compat layer (PriestlyCompat.lua, loaded first) ─────────────────────────
local API = Priestly.API

-- PriestlyCompat.lua has already said in chat why Priestly cannot start if the
-- shared library is missing. Stop here rather than building half an addon and
-- failing further down, far from the cause.
if not API then return end

local VERSION = API.AddonVersion(addonName)

-- ─── Sizes ───────────────────────────────────────────────────────────────────
-- The window is LibGroupBuffs' UI.lua; it sizes its own pools from the worst
-- roster the engine can produce. Priestly decides one number: how many members
-- a popover lists, which is also how many pets share a pet row.
local MAX_MEMBERS = 8

-- Reagent item IDs
local HOLY_CANDLE_ID   = 17028   -- rank 1 Prayer of Fortitude
local SACRED_CANDLE_ID = 17029   -- rank 2+ Prayer of Fortitude
local LIGHT_FEATHER_ID = 17056   -- Levitate

-- Get item icon reliably (works even if item not in bags)
-- Library functions are looked up through API at call time, never copied into
-- a local when the file loads. API is the table LibGroupBuffs shares with
-- every addon that embeds it: if a newer copy loads after Priestly (Wildly and
-- Magely load later, alphabetically), it upgrades that table in place, and a
-- copy taken here would keep running the old version beside the new one.
-- tests/test_bridge.lua fails on a new capture.
local function ItemIcon(...) return API.ItemIcon(...) end

-- The priest class icon: the spec icon when no spec spell is known, and a
-- popover member whose class the client does not report.
local PRIEST_ICON = "Interface\\Icons\\ClassIcon_Priest"

-- ─── Buff definitions ────────────────────────────────────────────────────────
--
-- Spell IDs are the source of truth: names are resolved from them at runtime
-- (locale-proof), with the enUS literals as the fallback when the client does
-- not know the spell at all. The group "Prayer of X" spells may simply not
-- exist in this version - nothing here assumes they do.
--
-- `duration` is only a seed for the timer gradient. The real value is learned
-- from live auras (by the engine's BuffRem) because Forever's durations differ from
-- both TBC and Vanilla and are still moving during the beta.
local DEFS = {
    {
        id          = "fort",
        grpID       = 21562,
        snglID      = 1243,
        grp         = "Prayer of Fortitude",
        sngl        = "Power Word: Fortitude",
        fallbackIcon= "Interface\\Icons\\Spell_Holy_WordFortitude",
        duration    = 3600,
    },
    {
        id          = "spirit",
        grpID       = 27681,
        snglID      = 14752,
        grp         = "Prayer of Spirit",
        sngl        = "Divine Spirit",
        fallbackIcon= "Interface\\Icons\\Spell_Holy_PrayerOfSpirit",
        duration    = 3600,
    },
    {
        id          = "shadow",
        grpID       = 27683,
        snglID      = 976,
        grp         = "Prayer of Shadow Protection",
        sngl        = "Shadow Protection",
        fallbackIcon= "Interface\\Icons\\Spell_Holy_PrayerOfShadowProtection",
        duration    = 600,
        visibility  = "shadow",   -- also gated by the Shadow Protection mode
    },
}

-- ─── The buff engine (LibGroupBuffs-1.0's Engine.lua) ─────────────────────
--
-- Aura reads and the combat-secrecy cache, durations, the roster, group stats,
-- target picking, click mapping and UNIT_AURA filtering are shared with Wildly
-- and Magely. Priestly supplies what is its own: DEFS, its config, the Shadow
-- Protection mode and where learned durations are stored. The UI below calls
-- the engine through these thin locals, which look the method up at call time
-- so a newer embedded copy of the library is the one that runs.
local engine = Priestly.Engine.New({
    defs       = DEFS,
    bucketSize = MAX_MEMBERS,           -- pets are split into popover-sized buckets
    showSolo      = function() return Priestly_ShowSolo() end,
    trackPets     = function() return Priestly_TrackPets() end,
    isBuffEnabled = function(defId) return Priestly_IsBuffEnabled(defId) end,
    isVisible = function(def, groups, ord)
        if def.visibility ~= "shadow" then return true end
        return Priestly_ShouldShowShadow(groups, ord)
    end,
    learnDuration   = function(spell, secs) Priestly_LearnDuration(spell, secs) end,
    learnedDuration = function(spell) return Priestly_GetLearnedDuration(spell) end,
})

local ST_HAS     = Priestly.Engine.STATES.HAS
local ST_MISSING = Priestly.Engine.STATES.MISSING
local ST_UNKNOWN = Priestly.Engine.STATES.UNKNOWN
local PET_GROUP  = Priestly.Engine.PET_GROUP

-- Resolve localized names and what this priest knows. Rerun on SPELLS_CHANGED
-- and talent changes: what a priest knows changes as they level, and at the
-- current beta cap the group spells do not exist at all.
local function RefreshSpellData()
    engine:RefreshSpells()
    -- PriestlyConfig's "show Shadow Protection when someone has it" mode needs
    -- the localized aura names, and it loads before this file.
    for _, d in ipairs(DEFS) do
        if d.id == "shadow" then Priestly.shadowAuraNames = d.names end
    end
end

local function ClickSpells(def) return engine:ClickSpells(def) end
local function BuffRem(unit, def) return engine:BuffRem(unit, def) end
local function DurationFor(...) return engine:DurationFor(...) end
local function PruneAuraCache() return engine:PruneCache() end
local function IsValidTarget(unit) return engine:IsValidTarget(unit) end
local function PickTarget(...) return engine:PickTarget(...) end
local function GatherGroups() return engine:GatherGroups() end
local function ActiveDefs(groups, ord) return engine:ActiveDefs(groups, ord) end
local function MembersFor(def, members) return engine:MembersFor(def, members) end
local function GroupStat(members, def) return engine:GroupStat(members, def) end
local function AuraEventIsRelevant(unit, updateInfo)
    return engine:AuraEventIsRelevant(unit, updateInfo)
end

-- ─── State ───────────────────────────────────────────────────────────────────
local g_IsPriest = false
local g_LastGroupSize = 0

-- Settings writes go through PriestlyConfig's single write path (issue #35).
-- Guarded like every other cross-file helper in this file: if PriestlyConfig
-- failed to load, a bare call would throw from a drag or a refresh instead of
-- quietly doing nothing.
local function SetConfig(key, value)
    if Priestly_SetConfig then Priestly_SetConfig(key, value) end
end

local function KnowsSpell(...) return API.KnowsSpell(...) end

-- Returns the icon for the player's spec.
-- Shadow (Shadowform) > Discipline (Power Infusion) > Holy (Circle of Healing).
-- The old talent-tree fallback is gone: GetNumTalentTabs / GetTalentTabInfo do
-- not exist on Mainline and nothing confirmed replaces them for Vanilla trees.
local SPEC_ICON_SPELLS = {
    { id = 15473, icon = "Interface\\Icons\\Spell_Shadow_ShadowWordPain" },   -- Shadowform
    { id = 10060, icon = "Interface\\Icons\\Spell_Holy_WordFortitude" },      -- Power Infusion
    { id = 724,   icon = "Interface\\Icons\\Spell_Holy_SummonLightwell" },    -- Lightwell
}

local function GetSpecIcon()
    for _, s in ipairs(SPEC_ICON_SPELLS) do
        if KnowsSpell(s.id) then return s.icon end
    end
    return PRIEST_ICON
end

-- ─── Data ────────────────────────────────────────────────────────────────────

-- Returns highest rank of Prayer of Fortitude known (0 if none)
local function GetPrayerRank()
    local fort = DEFS[1]
    if not fort.hasGroup then return 0 end
    return API.GetSpellRank(fort.grp)
end

-- Determine which candle item ID and icon to use
local function GetCandleInfo()
    local rank = GetPrayerRank()
    if rank <= 0 then return nil, nil, nil end
    if rank == 1 then
        return HOLY_CANDLE_ID, ItemIcon(HOLY_CANDLE_ID), "Holy Candle"
    else
        return SACRED_CANDLE_ID, ItemIcon(SACRED_CANDLE_ID), "Sacred Candle"
    end
end

-- ─── Reagent footer ──────────────────────────────────────────────────────────
-- What the footer shows, decided from what the priest actually knows. The old
-- "level >= 48" gate was a TBC content assumption; knowing the spell at all is
-- the real condition, and at the current cap nobody knows a Prayer. The
-- library draws the buttons, counts and tooltips.

local LEVITATE_ID = 1706

local function FooterItems()
    local items = {}
    local candleID, candleIcon = GetCandleInfo()
    if candleID then
        items[#items + 1] = {
            itemID = candleID, icon = candleIcon, usedBy = "the group Prayers",
            color = function(count)
                if count >= 50 then return 0.20, 1.00, 0.20 end
                if count >= 25 then return 1.00, 0.88, 0.10 end
                return 1.00, 0.22, 0.10
            end,
        }
    end
    if KnowsSpell(LEVITATE_ID) then
        items[#items + 1] = {
            itemID = LIGHT_FEATHER_ID, icon = ItemIcon(LIGHT_FEATHER_ID), usedBy = "Levitate",
            color = function(count)
                if count > 0 then return 1.00, 1.00, 1.00 end
                return 0.50, 0.50, 0.50
            end,
        }
    end
    return items
end

-- ─── The window (LibGroupBuffs-1.0's UI.lua) ─────────────────────────────────
--
-- Rows, popover, clicks, combat parking, dragging and the ticker are shared
-- with Wildly and Magely. Priestly supplies its title, spec icon, reagents and
-- config, and decides when the window opens; the events and slash commands
-- below call the ui's methods.
local ui = Priestly.UI.New({
    engine  = engine,
    owner   = addonName,
    title   = "|cff99ddffPriestly|r",
    version = VERSION,
    appearance = function() return { icon = GetSpecIcon() } end,
    unknownClassIcon = PRIEST_ICON,
    footerItems = FooterItems,
    alpha       = function() return Priestly_GetFrameAlpha and Priestly_GetFrameAlpha() or 0.96 end,
    -- `Priestly_FrameLocked and` is not decoration: if PriestlyConfig fails to
    -- load, calling a nil global would throw - silently, errors are off by
    -- default here - and kill the drag. Short-circuiting leaves the window
    -- draggable, which is the safe way to be wrong.
    locked      = function() return Priestly_FrameLocked and Priestly_FrameLocked() or false end,
    popoverSide = function() return Priestly_PopoverSide and Priestly_PopoverSide() or "auto" end,
    showClickHints = function() return not Priestly_ShowClickHints or Priestly_ShowClickHints() end,
    getPos = function()
        if not PriestlyDB then return nil, "PriestlyDB was nil" end
        if not PriestlyDB.pos then return nil, "PriestlyDB.pos was nil" end
        return PriestlyDB.pos
    end,
    setPos     = function(pos) SetConfig("pos", pos) end,
    setVisible = function(visible) SetConfig("visible", visible) end,
})

-- ─── Global hooks for PriestlyConfig.lua ────────────────────────────────────

function Priestly_ScheduleRefresh()
    ui:ScheduleRefresh()
end

-- Force a full UI rebuild (used when config changes affect layout)
function Priestly_ForceRebuild()
    if InCombatLockdown() then return end
    ui:Open(0.1)
end

-- Called when the solo checkbox is toggled in config
function Priestly_OnSoloToggle(enabled)
    if InCombatLockdown() then return end
    if enabled then
        if not ui:IsVisible() and g_IsPriest then
            SetConfig("visible", true)
            ui:Open(0.1)
        end
    elseif GetNumGroupMembers() == 0 then
        ui:Close()
    end
end

-- Apply frame alpha from config
function Priestly_ApplyAlpha()
    ui:ApplyAppearance()
end

-- ─── Events ──────────────────────────────────────────────────────────────────

-- RegisterEvent throws on an unknown event name on this client, so every
-- registration goes through the compat helper, which reports what it skipped
-- rather than leaving a handler silently dead.
local evtFrame = CreateFrame("Frame", "PriestlyEvents")
Priestly.RegisterEvents(evtFrame,
    "PLAYER_LOGIN",
    "READY_CHECK",
    "UNIT_AURA",
    "UNIT_PET",
    "RAID_ROSTER_UPDATE",
    "GROUP_ROSTER_UPDATE",
    "PLAYER_TALENT_UPDATE",
    "ACTIVE_TALENT_GROUP_CHANGED",
    "PLAYER_REGEN_ENABLED",
    "BAG_UPDATE",
    "SPELLS_CHANGED")

-- UNIT_AURA filtering is the engine's (AuraEventIsRelevant above): only group
-- units, and on a partial update only Priestly's own spells.

evtFrame:SetScript("OnEvent", function(self, event, arg1, arg2)
    if event == "PLAYER_LOGIN" then
        -- Check class
        local _, cls = UnitClass("player")
        g_IsPriest = (cls == "PRIEST")

        -- Initialise saved state (default: visible on Priests)
        Priestly_EnsureDefaults()
        if PriestlyDB.visible == nil then SetConfig("visible", true) end

        -- Resolve localized spell names and what this priest actually knows
        -- before anything reads DEFS.
        RefreshSpellData()

        ui:Init()

        -- Apply configured opacity
        Priestly_ApplyAlpha()

        -- Auto-open if Priest and in a group (or solo mode) - unless the
        -- window was deliberately closed, which is a preference that should
        -- survive a reload.
        g_LastGroupSize = GetNumGroupMembers()
        if g_IsPriest and PriestlyDB.visible ~= false
            and (g_LastGroupSize > 0 or Priestly_ShowSolo())
        then
            ui:Open(0.6)
        end

        DEFAULT_CHAT_FRAME:AddMessage(
            "|cff99ddff[Priestly]|r Loaded. " ..
            (g_IsPriest and "Auto-opens when you join a group. " or "") ..
            "Type |cffffffff/priestly help|r for commands. " ..
            "Type |cffffffff/priestly config|r for options."
        )

    elseif event == "READY_CHECK" then
        -- A ready check is a good moment to rebuff, but not a reason to
        -- override someone who closed the window.
        if g_IsPriest and (not PriestlyDB or PriestlyDB.visible ~= false) then
            ui:Open(0.4)
        end

    elseif event == "UNIT_AURA" then
        if AuraEventIsRelevant(arg1, arg2) then ui:ScheduleRefresh() end

    elseif event == "UNIT_PET" then
        -- Pet summoned or dismissed: rebuild to add/remove pet rows
        ui:ScheduleRefresh()

    elseif event == "RAID_ROSTER_UPDATE" or event == "GROUP_ROSTER_UPDATE" then
        PruneAuraCache()
        local n = GetNumGroupMembers()
        -- Joining a group is the one case that reopens a window the user
        -- closed: that is the addon's advertised behaviour. Any other roster
        -- churn leaves a deliberate close alone.
        local joined = (g_LastGroupSize == 0 and n > 0)
        g_LastGroupSize = n
        if joined then SetConfig("visible", true) end
        if n > 0 and not ui:IsVisible() and g_IsPriest
            and (joined or not PriestlyDB or PriestlyDB.visible ~= false)
        then
            ui:Open(0.5)
        elseif n == 0 and not Priestly_ShowSolo() then
            ui:Close()  -- auto-close, not manual (unless solo mode)
        else
            ui:ScheduleRefresh()  -- including staying solo: just refresh
        end

    elseif event == "PLAYER_TALENT_UPDATE" or event == "SPELLS_CHANGED" or event == "ACTIVE_TALENT_GROUP_CHANGED" then
        -- Newly learned spells change which rows exist and how they cast.
        RefreshSpellData()
        ui:ApplyAppearance()      -- the spec icon
        -- Full rebuild: available buffs and reagents may change on a respec.
        -- In combat only the counts can move; the rebuild follows the fight.
        if ui:IsVisible() and not InCombatLockdown() then
            ui:Open(0.3)
        elseif ui:IsVisible() then
            ui:RefreshFooter()
        end

    elseif event == "PLAYER_REGEN_ENABLED" then
        -- Unpark, then the rebuild combat deferred - including a show asked
        -- for while locked down.
        ui:OnCombatEnd()

    elseif event == "BAG_UPDATE" then
        if ui:IsVisible() then ui:RefreshFooter() end
    end
end)

-- ─── Slash commands ──────────────────────────────────────────────────────────

SLASH_PRIESTLY1 = "/priestly"
SlashCmdList["PRIESTLY"] = function(msg)
    local cmd = strtrim(msg or ""):lower()

    if cmd == "help" then
        local c = "|cff99ddff[Priestly]|r"
        DEFAULT_CHAT_FRAME:AddMessage(c .. " Commands:")
        DEFAULT_CHAT_FRAME:AddMessage("  |cffffffff/priestly|r            toggle window")
        DEFAULT_CHAT_FRAME:AddMessage("  |cffffffff/priestly show|r       force open")
        DEFAULT_CHAT_FRAME:AddMessage("  |cffffffff/priestly hide|r       close")
        DEFAULT_CHAT_FRAME:AddMessage("  |cffffffff/priestly config|r     open options panel")
        DEFAULT_CHAT_FRAME:AddMessage("  |cffffffff/priestly reset|r      reset window position")
        DEFAULT_CHAT_FRAME:AddMessage("  |cffffffff/priestly pos|r        why the window is where it is")
        DEFAULT_CHAT_FRAME:AddMessage("  |cffffffff/priestly help|r       this message")
        -- Describe the mapping that is actually live: without the group
        -- Prayers (the whole current level range) left-click is single-target.
        local anyGroup = false
        for _, d in ipairs(DEFS) do
            if d.hasGroup then anyGroup = true break end
        end
        DEFAULT_CHAT_FRAME:AddMessage(c .. " Main frame rows:")
        if anyGroup then
            DEFAULT_CHAT_FRAME:AddMessage("  Left-click   cast group Prayer")
            DEFAULT_CHAT_FRAME:AddMessage("  Right-click  single buff first missing person")
        else
            DEFAULT_CHAT_FRAME:AddMessage("  Left-click   buff the first person missing it")
            DEFAULT_CHAT_FRAME:AddMessage("  Right-click  same (no group Prayer known yet)")
        end
        DEFAULT_CHAT_FRAME:AddMessage("  Mouseover    open per-member popover")
        DEFAULT_CHAT_FRAME:AddMessage(c .. " Popover (left panel):")
        if anyGroup then
            DEFAULT_CHAT_FRAME:AddMessage("  Left-click   cast group Prayer on that person")
            DEFAULT_CHAT_FRAME:AddMessage("  Right-click  single buff that person")
        else
            DEFAULT_CHAT_FRAME:AddMessage("  Left/Right   buff that person")
        end
        DEFAULT_CHAT_FRAME:AddMessage("  R = green (in range) / yellow (out of range) / grey (offline)")
        DEFAULT_CHAT_FRAME:AddMessage("  Timer = green >50% / yellow 10-50% / red <10%")
        DEFAULT_CHAT_FRAME:AddMessage("  ? = buff state unreadable right now (combat aura secrecy)")

    elseif cmd == "config" or cmd == "options" or cmd == "settings" or cmd == "opt" then
        if Priestly_OpenConfig then Priestly_OpenConfig() end

    elseif cmd == "reset" then
        if ui:ResetPosition() then
            DEFAULT_CHAT_FRAME:AddMessage("|cff99ddff[Priestly]|r Window position reset.")
        else
            -- Moving the window in combat could bring parked, invisible
            -- buttons back on screen, so the move waits for the fight to end.
            DEFAULT_CHAT_FRAME:AddMessage(
                "|cff99ddff[Priestly]|r Window position reset - it moves when combat ends.")
        end
        -- Reset deliberately ignores the lock, so a locked window dragged
        -- somewhere unreachable can always be recovered. The trap is what
        -- comes next: the window is now centred AND still locked, so dragging
        -- it anywhere does nothing and every reload puts it back here. Without
        -- this line that reads exactly like "the position is not saved".
        if Priestly_FrameLocked() then
            DEFAULT_CHAT_FRAME:AddMessage(
                "|cff99ddff[Priestly]|r |cffffcc00The window is locked|r - untick " ..
                "|cffffffffLock frame position|r in |cffffffff/priestly config|r to move it.")
        end

    elseif cmd == "pos" then
        -- Diagnostic for "the window does not remember where I put it".
        local p = PriestlyDB and PriestlyDB.pos
        DEFAULT_CHAT_FRAME:AddMessage("|cff99ddff[Priestly]|r position diagnostic:")
        DEFAULT_CHAT_FRAME:AddMessage("  saved: " .. (p and string.format(
            "%s/%s  %.1f, %.1f", tostring(p.point), tostring(p.relPoint),
            tonumber(p.x) or 0/0, tonumber(p.y) or 0/0) or "|cffff6666nothing saved|r"))
        local restore = ui:RestoreInfo()
        DEFAULT_CHAT_FRAME:AddMessage("  last restore: " .. tostring(restore.log))
        if restore.skips > 0 then
            DEFAULT_CHAT_FRAME:AddMessage(string.format(
                "    (%d refresh%s since, which leave the position alone)",
                restore.skips, restore.skips == 1 and "" or "es"))
        end
        local main = ui:MainFrame()
        if main then
            local pt, rel, relPt, x, y = main:GetPoint()
            DEFAULT_CHAT_FRAME:AddMessage(string.format(
                "  frame now: %s/%s  %.1f, %.1f  (relativeTo %s)",
                tostring(pt), tostring(relPt), tonumber(x) or 0/0, tonumber(y) or 0/0,
                rel and (rel.GetName and rel:GetName() or "unnamed") or "nil"))
        else
            DEFAULT_CHAT_FRAME:AddMessage("  frame now: |cffff6666not built|r")
        end
        DEFAULT_CHAT_FRAME:AddMessage("  locked: " ..
            tostring(Priestly_FrameLocked and Priestly_FrameLocked() or false))

    elseif cmd == "hide" or cmd == "close" then
        -- The window parents secure buttons, so in combat the client refuses
        -- to hide it (docs/FOREVER-PROBE.md section 13). Saying so beats a
        -- command that looks ignored.
        if not ui:Close(true) then
            DEFAULT_CHAT_FRAME:AddMessage(
                "|cff99ddff[Priestly]|r The window closes when you leave combat.")
        end

    elseif cmd == "show" then
        SetConfig("visible", true)
        ui:Update()

    else
        if ui:IsVisible() then
            if not ui:Close(true) then
                DEFAULT_CHAT_FRAME:AddMessage(
                    "|cff99ddff[Priestly]|r The window closes when you leave combat.")
            end
        else
            SetConfig("visible", true)
            ui:Update()
        end
    end
end

-- ─── Test seam ───────────────────────────────────────────────────────────────
-- Harmless in game; tests/ reaches the file-locals through this.

Priestly._test = {
    DEFS             = DEFS,
    RefreshSpellData = RefreshSpellData,
    ClickSpells      = ClickSpells,
    ActiveDefs       = ActiveDefs,
    GatherGroups     = GatherGroups,
    GroupStat        = GroupStat,
    BuffRem          = BuffRem,
    PickTarget       = PickTarget,
    DurationFor      = DurationFor,
    PruneAuraCache   = PruneAuraCache,
    IsValidTarget    = IsValidTarget,
    GetPrayerRank    = GetPrayerRank,
    GetCandleInfo    = GetCandleInfo,
    FooterItems      = FooterItems,
    AuraEventIsRelevant = AuraEventIsRelevant,
    auraCache        = function() return engine.cache end,
    engine           = engine,
    ui               = ui,
    MembersFor       = MembersFor,
    states           = { HAS = ST_HAS, MISSING = ST_MISSING, UNKNOWN = ST_UNKNOWN },
    -- The library's formatting helpers, under the names the tests use.
    TimerColor       = function(...) return Priestly.UI.TimerColor(...) end,
    Pct              = function(...) return Priestly.UI.Pct(...) end,
    FmtTime          = function(...) return Priestly.UI.FmtTime(...) end,
    -- Whole-UI seam: tests drive a rebuild and then read the secure
    -- attributes off the rows to see what a click would actually cast.
    UpdateUI         = function() return ui:Update() end,
    UpdatePopover    = function(...) return ui:UpdatePopover(...) end,
    PopoverSide      = function(row) return ui:PopoverSide(row) end,
    ShowClickHint    = function(row) return ui:ShowClickHint(row) end,
    GroupLabel       = function(gNum) return ui:GroupLabel(gNum) end,
    rows             = function() return ui.rows end,
    popRows          = function() return ui.popRows end,
    mainFrame        = function() return ui.main end,
    popFrame         = function() return ui.pop end,
    eventFrame       = function() return evtFrame end,
    CloseUI          = function(...) return ui:Close(...) end,
    RefreshTimers    = function() return ui:RefreshTimers() end,
    RefreshFooter    = function() return ui:RefreshFooter() end,
    -- The footer's buttons are anonymous; find one by the item it shows.
    footerButton     = function(itemID)
        for _, btn in ipairs(ui.footerBtns) do
            if btn._itemID == itemID and btn:IsShown() then return btn end
        end
    end,
}
