-- ============================================================================
-- Priestly  –  Pally Power–style Priest buff manager
-- TBC Classic Anniversary  ·  /priestly [show|hide|help]
--
-- Main frame rows (per group, per buff):
--   [Icon] [██████████████  2  27:54]   ← left-click = group Prayer
--                                        ← right-click = single on 1st missing
--                                        ← mouseover = popover
--
-- Popover (left panel, on mouseover):
--   [PrayerIcon]  Prayer of Fortitude
--   ──────────────────────────────────
--   R [ClassIcon] Name           27:54  ← left-click = single buff
--   R [ClassIcon] Name            MISS  ← right-click = group Prayer
-- ============================================================================

local addonName = "Priestly"
local VERSION = (C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata)(addonName, "Version") or "dev"

-- ─── Layout constants ────────────────────────────────────────────────────────
local ICON_W     = 16
local BAR_W      = 91
local ROW_H      = 15
local ROW_W      = ICON_W + BAR_W       -- 107
local GRP_HDR_H  = 10
local FRAME_W    = ROW_W + 12           -- 119
local ROW_X      = 5
local HDR_H      = 24                   -- styled header bar height
local FTR_H      = 14                   -- reagent footer height

local POP_W      = 174
local POP_ROW_H  = 22
local POP_HDR_H  = 24

local MAX_GROUPS  = 9
local MAX_DEFS    = 3
local MAX_ROWS    = MAX_GROUPS * MAX_DEFS   -- 27
local MAX_MEMBERS = 8

-- Reagent item IDs
local HOLY_CANDLE_ID   = 17028   -- rank 1 Prayer of Fortitude
local SACRED_CANDLE_ID = 17029   -- rank 2+ Prayer of Fortitude
local LIGHT_FEATHER_ID = 17056   -- Levitate

-- Get item icon reliably (works even if item not in bags)
local function ItemIcon(itemID)
    -- GetItemIcon works without cache in TBC Anniversary
    if GetItemIcon then
        local icon = GetItemIcon(itemID)
        if icon then return icon end
    end
    -- Fallback: try GetItemInfo
    local _, _, icon = GetItemInfo(itemID)
    if icon then return icon end
    -- Last resort fallback
    return "Interface\\Icons\\INV_Misc_QuestionMark"
end

-- Returns r,g,b for a percentage (0.0 – 1.0)
-- Matches PallyPower's GetSeverityColor: smooth green→yellow→red gradient
local function TimerColor(pct)
    if pct >= 0.5 then
        return (1.0 - pct) * 2, 1.0, 0.0
    else
        return 1.0, pct * 2, 0.0
    end
end

-- ─── Class icon textures (modern engine, TBC Anniversary) ────────────────────
local CLASS_ICONS = {
    WARRIOR  = "Interface\\Icons\\ClassIcon_Warrior",
    PALADIN  = "Interface\\Icons\\ClassIcon_Paladin",
    HUNTER   = "Interface\\Icons\\ClassIcon_Hunter",
    ROGUE    = "Interface\\Icons\\ClassIcon_Rogue",
    PRIEST   = "Interface\\Icons\\ClassIcon_Priest",
    SHAMAN   = "Interface\\Icons\\ClassIcon_Shaman",
    MAGE     = "Interface\\Icons\\ClassIcon_Mage",
    WARLOCK  = "Interface\\Icons\\ClassIcon_Warlock",
    DRUID    = "Interface\\Icons\\ClassIcon_Druid",
    PET_HUNTER  = "Interface\\Icons\\Ability_Hunter_BeastCall",
    PET_WARLOCK = "Interface\\Icons\\Spell_Shadow_SummonImp",
    PET_PRIEST  = "Interface\\Icons\\Spell_Shadow_Shadowfiend",
    PET_MAGE    = "Interface\\Icons\\Spell_Frost_SummonWaterElemental_2",
    PET         = "Interface\\Icons\\Ability_Hunter_BeastCall",
}

-- ─── Buff definitions ────────────────────────────────────────────────────────
local DEFS = {
    {
        id          = "fort",
        grp         = "Prayer of Fortitude",
        sngl        = "Power Word: Fortitude",
        names       = { "Power Word: Fortitude", "Prayer of Fortitude" },
        fallbackIcon= "Interface\\Icons\\Spell_Holy_WordFortitude",
        duration    = 3600,
        always      = true,
    },
    {
        id          = "spirit",
        grp         = "Prayer of Spirit",
        sngl        = "Divine Spirit",
        names       = { "Divine Spirit", "Prayer of Spirit" },
        fallbackIcon= "Interface\\Icons\\Spell_Holy_PrayerOfSpirit",
        duration    = 3600,
        needsKnown  = true,
    },
    {
        id          = "shadow",
        grp         = "Prayer of Shadow Protection",
        sngl        = "Shadow Protection",
        names       = { "Shadow Protection", "Prayer of Shadow Protection" },
        fallbackIcon= "Interface\\Icons\\Spell_Holy_PrayerOfShadowProtection",
        duration    = 1200,
        optional    = true,
    },
}

-- ─── State ───────────────────────────────────────────────────────────────────
local g_Main, g_Pop
local g_Vis      = false
local g_Moved    = false
local g_RefQ     = false
local g_InitDone = false
local g_Ticker   = 0
local g_IsPriest = false

local g_GHdrs = {}   -- FontStrings [1..MAX_GROUPS]
local g_Rows  = {}   -- Buttons     [1..MAX_ROWS]
local g_PRows = {}   -- Buttons     [1..MAX_MEMBERS]

local CloseUI, UpdateUI, UpdatePopover, InitUI, RefreshTimers, ScheduleRefresh

-- ─── Global hooks for PriestlyConfig.lua ────────────────────────────────────

-- ScheduleRefresh is forward-declared above and assigned later; expose via wrapper
function Priestly_ScheduleRefresh()
    if ScheduleRefresh then ScheduleRefresh() end
end

-- Force a full UI rebuild (used when config changes affect layout)
function Priestly_ForceRebuild()
    if InCombatLockdown() then return end
    local t = 0
    local f = CreateFrame("Frame")
    f:SetScript("OnUpdate", function(self, dt)
        t = t + dt
        if t >= 0.1 then
            self:SetScript("OnUpdate", nil)
            if UpdateUI then UpdateUI() end
        end
    end)
end

-- Called when the solo checkbox is toggled in config
function Priestly_OnSoloToggle(enabled)
    if InCombatLockdown() then return end
    if enabled then
        -- Solo enabled: show the frame immediately
        if not g_Vis and g_IsPriest then
            local t = 0
            local f = CreateFrame("Frame")
            f:SetScript("OnUpdate", function(self, dt)
                t = t + dt
                if t >= 0.1 then
                    self:SetScript("OnUpdate", nil)
                    if PriestlyDB then PriestlyDB.visible = true end
                    if UpdateUI then UpdateUI() end
                end
            end)
        end
    else
        -- Solo disabled: close if not in a group
        if GetNumGroupMembers() == 0 then
            if CloseUI then CloseUI() end
        end
    end
end

-- Apply frame alpha from config
function Priestly_ApplyAlpha()
    local alpha = Priestly_GetFrameAlpha and Priestly_GetFrameAlpha() or 0.96
    if g_Main then
        g_Main:SetBackdropColor(0.04, 0.04, 0.10, alpha)
    end
    if g_Pop then
        g_Pop:SetBackdropColor(0.05, 0.05, 0.12, alpha)
    end
end

-- ─── Utilities ───────────────────────────────────────────────────────────────

local function After(delay, fn)
    local t = 0
    local f = CreateFrame("Frame")
    f:SetScript("OnUpdate", function(self, dt)
        t = t + dt
        if t >= delay then self:SetScript("OnUpdate", nil); fn() end
    end)
end

local function FmtTime(s)
    if not s or s <= 0 then return "" end
    if s > 9998 then return "" end
    return string.format("%d:%02d", math.floor(s / 60), math.floor(s % 60))
end

local function SpellIcon(spellName, fallback)
    local _, _, ic = GetSpellInfo(spellName)
    return ic or fallback or ""
end

local function CountItem(itemID)
    local total = 0
    for bag = 0, 4 do
        local slots = C_Container.GetContainerNumSlots(bag) or 0
        for slot = 1, slots do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and info.itemID == itemID then
                total = total + (info.stackCount or 0)
            end
        end
    end
    return total
end

local function BuffRem(unit, names)
    if not UnitExists(unit) then return 0, 0 end
    for i = 1, 40 do
        local bName, _, _, _, dur, exp = UnitBuff(unit, i)
        if not bName then break end
        for _, n in ipairs(names) do
            if bName == n then
                local rem = (not exp or exp == 0) and 9999 or math.max(0, exp - GetTime())
                local d   = dur or 0
                return rem, d
            end
        end
    end
    return 0, 0
end

-- "IN_RANGE" | "OUT_RANGE" | "OFFLINE" | "UNKNOWN"
local function RangeStatus(unit, spellName)
    if not UnitExists(unit) then return "UNKNOWN" end
    if not UnitIsConnected(unit) then return "OFFLINE" end
    local r = IsSpellInRange(spellName, unit)
    if r == 1 then return "IN_RANGE"
    elseif r == 0 then return "OUT_RANGE"
    else return "UNKNOWN" end
end

-- Can we actually buff this unit right now?
local function IsValidTarget(unit)
    if not UnitExists(unit) then return false end
    if not UnitIsConnected(unit) then return false end
    if UnitIsDeadOrGhost(unit) then return false end
    return true
end

local function ClassColor(classFile)
    local c = RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
    if c then return c.r, c.g, c.b end
    return 0.80, 0.80, 0.80
end

local function KnowsSpell(spellName)
    local ok, res = pcall(function()
        if not GetNumSpellTabs then return true end
        for t = 1, GetNumSpellTabs() do
            local _, _, off, num = GetSpellTabInfo(t)
            for i = 1, num do
                if GetSpellBookItemName(off + i, BOOKTYPE_SPELL) == spellName then
                    return true
                end
            end
        end
        return false
    end)
    return (not ok) or res
end

-- Returns the icon for the player's spec
-- Shadow (Shadowform) > Discipline (Power Infusion) > dominant tree
local function GetSpecIcon()
    if KnowsSpell("Shadowform") then
        return "Interface\\Icons\\Spell_Shadow_ShadowWordPain"
    end
    if KnowsSpell("Power Infusion") then
        return "Interface\\Icons\\Spell_Holy_WordFortitude"
    end
    if KnowsSpell("Circle of Healing") then
        return "Interface\\Icons\\Spell_Holy_GuardianSpirit"
    end
    local ok, result = pcall(function()
        local maxPts, icon = 0, nil
        local n = GetNumTalentTabs and GetNumTalentTabs() or 0
        for i = 1, n do
            local _, tabIcon, spent = GetTalentTabInfo(i)
            if spent and spent > maxPts then maxPts = spent; icon = tabIcon end
        end
        return icon
    end)
    return (ok and result) or CLASS_ICONS.PRIEST or "Interface\\Icons\\Spell_Holy_WordFortitude"
end

-- ─── Data ────────────────────────────────────────────────────────────────────

-- Pet group number (always sorted last)
local PET_GROUP = 99

-- Determine pet "class" based on owner's class for icon display
local function PetClass(ownerUnit)
    if not ownerUnit then return "PET" end
    local _, cls = UnitClass(ownerUnit)
    if cls == "HUNTER"  then return "PET_HUNTER"  end
    if cls == "WARLOCK" then return "PET_WARLOCK" end
    if cls == "PRIEST"  then return "PET_PRIEST"  end
    if cls == "MAGE"    then return "PET_MAGE"    end
    return "PET"
end

-- Returns groups[gNum] = { {unit, name, class}, ... },  ord = sorted group list
-- Pets go into PET_GROUP (99) at the bottom
local function GatherGroups()
    local g, ord = {}, {}
    local pets = {}

    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do
            local name, _, sg = GetRaidRosterInfo(i)
            if name then
                if not g[sg] then g[sg] = {}; ord[#ord + 1] = sg end
                local _, cls = UnitClass("raid"..i)
                g[sg][#g[sg] + 1] = { unit = "raid"..i, name = name, class = cls }
                local petUnit = "raidpet"..i
                if UnitExists(petUnit) then
                    pets[#pets + 1] = { unit = petUnit, name = UnitName(petUnit) or "Pet", class = PetClass("raid"..i) }
                end
            end
        end
    elseif GetNumGroupMembers() > 0 then
        g[1] = {}
        local _, pc = UnitClass("player")
        g[1][1] = { unit = "player", name = UnitName("player") or "You", class = pc }
        if UnitExists("pet") then
            pets[#pets + 1] = { unit = "pet", name = UnitName("pet") or "Pet", class = PetClass("player") }
        end
        for i = 1, GetNumGroupMembers() do
            local u = "party"..i
            if UnitExists(u) then
                local _, uc = UnitClass(u)
                g[1][#g[1] + 1] = { unit = u, name = UnitName(u) or "?", class = uc }
                local petUnit = "partypet"..i
                if UnitExists(petUnit) then
                    pets[#pets + 1] = { unit = petUnit, name = UnitName(petUnit) or "Pet", class = PetClass(u) }
                end
            end
        end
        ord[1] = 1
    elseif Priestly_ShowSolo() then
        -- Solo mode: just the player
        g[1] = {}
        local _, pc = UnitClass("player")
        g[1][1] = { unit = "player", name = UnitName("player") or "You", class = pc }
        if UnitExists("pet") then
            pets[#pets + 1] = { unit = "pet", name = UnitName("pet") or "Pet", class = PetClass("player") }
        end
        ord[1] = 1
    end

    if #pets > 0 and Priestly_TrackPets() then
        g[PET_GROUP] = pets
        ord[#ord + 1] = PET_GROUP
    end

    table.sort(ord)
    return g, ord
end

-- Returns highest rank of Prayer of Fortitude known (0 if none)
local function GetPrayerRank()
    local rank = 0
    local ok = pcall(function()
        if not GetNumSpellTabs then return end
        for t = 1, GetNumSpellTabs() do
            local _, _, off, num = GetSpellTabInfo(t)
            for i = 1, num do
                local name, sub = GetSpellBookItemName(off + i, BOOKTYPE_SPELL)
                if name == "Prayer of Fortitude" then
                    local r = sub and tonumber(sub:match("(%d+)")) or 1
                    if r > rank then rank = r end
                end
            end
        end
    end)
    return rank
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

local function ActiveDefs(groups, ord)
    local showShadow = Priestly_ShouldShowShadow(groups, ord)
    local out = {}
    for _, d in ipairs(DEFS) do
        -- Check config toggle for fort/spirit
        if not Priestly_IsBuffEnabled(d.id) then
            -- skip this buff entirely
        elseif d.always then
            out[#out + 1] = d
        elseif d.needsKnown then
            if KnowsSpell(d.grp) then out[#out + 1] = d end
        elseif d.optional then
            if showShadow then out[#out + 1] = d end
        end
    end
    return out
end

-- Returns { miss, minR, minDur, allHave, nMiss, nTotal }
local function GroupStat(members, def)
    local minR, minDur, miss = 9999, 0, {}
    for _, m in ipairs(members) do
        -- Offline/disconnected always counts as missing
        if not UnitIsConnected(m.unit) then
            miss[#miss + 1] = m
        else
            local r, d = BuffRem(m.unit, def.names)
            if r <= 0 then
                miss[#miss + 1] = m
            elseif r < minR then
                minR = r
                minDur = (d and d > 0) and d or (def.duration or 3600)
            end
        end
    end
    local allHave = (#miss == 0)
    return {
        miss    = miss,
        minR    = (minR == 9999) and 0 or minR,
        minDur  = minDur,
        allHave = allHave,
        nMiss   = #miss,
        nTotal  = #members,
    }
end

-- ─── Per-element visual updaters (used by both full rebuild and ticker) ───────

local function ApplyRowVisuals(r, st, dur)
    dur = st.minDur or dur or 3600
    local pct = (st.minR > 0 and dur > 0) and (st.minR / dur) or 0

    -- Background: flat colors matching PallyPower defaults
    -- cBuffGood     = (0, 0.7, 0)    everyone has the buff
    -- cBuffNeedSome = (1, 1, 0.5)    some missing
    -- cBuffNeedAll  = (1, 0, 0)      nobody has it
    if st.allHave then
        r.bg:SetColorTexture(0.0, 0.70, 0.0, 0.50)
    elseif st.nMiss == st.nTotal then
        r.bg:SetColorTexture(1.0, 0.0, 0.0, 0.50)
    else
        r.bg:SetColorTexture(1.0, 1.0, 0.5, 0.50)
    end

    -- Text elements
    r.timer:Hide()
    r.missAll:Hide()
    r.missCount:Hide()

    -- Show miss count next to icon when anyone is missing
    if st.nMiss > 0 then
        r.missCount:SetText(st.nMiss)
        r.missCount:Show()
    end

    if st.nMiss == st.nTotal then
        -- Everyone missing: show MISS in bar area
        r.missAll:Show()
    elseif st.minR > 0 then
        -- Some buffed: show timer
        local tr, tg, tb = TimerColor(pct)
        r.timer:SetText(FmtTime(st.minR))
        r.timer:SetTextColor(tr, tg, tb)
        r.timer:Show()
    end
end

local function ApplyPopRowVisuals(pr)
    if not pr._active then return end
    local unit  = pr._unit
    local def   = pr._def
    local rem, buffDur = BuffRem(unit, def.names)
    local has   = rem > 0
    local range = RangeStatus(unit, def.sngl)
    local dur   = (buffDur and buffDur > 0) and buffDur or (def.duration or 3600)
    local pct   = has and (rem / dur) or 0

    -- Row background: flat color by state (matching PallyPower)
    if not UnitIsConnected(unit) then
        pr.bg:SetColorTexture(0.30, 0.30, 0.30, 0.70)   -- grey for offline
    elseif has then
        pr.bg:SetColorTexture(0.0, 0.70, 0.0, 0.50)     -- green = buffed
    else
        pr.bg:SetColorTexture(1.0, 0.0, 0.0, 0.50)      -- red = missing
    end

    -- Range indicator: "R" coloured by status
    if range == "IN_RANGE" then
        pr.rangeTxt:SetText("R")
        pr.rangeTxt:SetTextColor(0.15, 1.00, 0.15)
    elseif range == "OUT_RANGE" then
        pr.rangeTxt:SetText("R")
        pr.rangeTxt:SetTextColor(1.00, 0.85, 0.10)
    elseif range == "OFFLINE" then
        pr.rangeTxt:SetText("R")
        pr.rangeTxt:SetTextColor(0.50, 0.50, 0.50)
    else
        pr.rangeTxt:SetText("?")
        pr.rangeTxt:SetTextColor(0.50, 0.50, 0.50)
    end

    -- Timer / MISS
    if has then
        local tr, tg, tb = TimerColor(pct)
        pr.timeTxt:SetText(FmtTime(rem))
        pr.timeTxt:SetTextColor(tr, tg, tb)
    else
        pr.timeTxt:SetText("MISS")
        pr.timeTxt:SetTextColor(1.00, 0.22, 0.22)
    end
end

-- ─── Ticker (called from OnUpdate every ~0.5 s) ───────────────────────────────

RefreshTimers = function()
    -- Update main-frame row colours and timers
    for _, r in ipairs(g_Rows) do
        if r._active then
            ApplyRowVisuals(r, GroupStat(r._members, r._def), r._def.duration)
        end
    end
    -- Update popover member rows
    if g_Pop and g_Pop:IsShown() then
        for _, pr in ipairs(g_PRows) do
            if pr._active then ApplyPopRowVisuals(pr) end
        end
    end
end

-- ─── Footer reagent display ──────────────────────────────────────────────────

local g_CandleID, g_CandleName  -- set once at login/talent change
local g_ShowCandle  = false
local g_ShowFeather = false

local function RefreshFooterState()
    local level = UnitLevel("player") or 0
    local candleID, candleIcon, candleName = GetCandleInfo()
    g_CandleID   = candleID
    g_CandleName = candleName
    g_ShowCandle  = (level >= 48 and candleID ~= nil)
    g_ShowFeather = KnowsSpell("Levitate")

    if g_Main and g_Main.candleBtn then
        if g_ShowCandle then
            g_Main.candleBtn.icon:SetTexture(candleIcon)
            g_Main.candleBtn._itemID = candleID
        end
    end
end

local function RefreshFooter()
    if not g_Main or not g_Main.candleBtn then return end

    if g_ShowCandle then
        local count = CountItem(g_CandleID)
        g_Main.candleBtn.countTxt:SetText(count)
        if count >= 50 then
            g_Main.candleBtn.countTxt:SetTextColor(0.20, 1.00, 0.20)
        elseif count >= 25 then
            g_Main.candleBtn.countTxt:SetTextColor(1.00, 0.88, 0.10)
        else
            g_Main.candleBtn.countTxt:SetTextColor(1.00, 0.22, 0.10)
        end
        g_Main.candleBtn:Show()
    else
        g_Main.candleBtn:Hide()
    end

    if g_ShowFeather then
        local count = CountItem(LIGHT_FEATHER_ID)
        g_Main.featherBtn.countTxt:SetText(count)
        if count > 0 then
            g_Main.featherBtn.countTxt:SetTextColor(1.00, 1.00, 1.00)
        else
            g_Main.featherBtn.countTxt:SetTextColor(0.50, 0.50, 0.50)
        end
        g_Main.featherBtn:Show()
    else
        g_Main.featherBtn:Hide()
    end
end

-- ─── UI Init (runs once) ─────────────────────────────────────────────────────

InitUI = function()
    if g_InitDone then return end
    g_InitDone = true

    -- ── Main frame ───────────────────────────────────────────────────────────
    g_Main = CreateFrame("Frame", "PriestlyMain", UIParent, "BackdropTemplate")
    g_Main:SetFrameStrata("HIGH")
    g_Main:SetClampedToScreen(true)
    g_Main:SetMovable(true)
    g_Main:SetBackdrop({
        bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 14,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    g_Main:SetBackdropColor(0.04, 0.04, 0.10, Priestly_GetFrameAlpha())
    g_Main:SetBackdropBorderColor(0.40, 0.40, 0.65, 0.85)
    g_Main:Hide()

    -- ── Styled header bar ────────────────────────────────────────────────────
    -- Dark accent strip inside the border
    local hdrBg = g_Main:CreateTexture(nil, "ARTWORK")
    hdrBg:SetColorTexture(0.07, 0.07, 0.18, 0.98)
    hdrBg:SetPoint("TOPLEFT",  g_Main, "TOPLEFT",  4, -4)
    hdrBg:SetPoint("TOPRIGHT", g_Main, "TOPRIGHT", -4, -4)
    hdrBg:SetHeight(HDR_H)

    -- Thin accent line under header
    local hdrLine = g_Main:CreateTexture(nil, "ARTWORK")
    hdrLine:SetColorTexture(0.40, 0.40, 0.65, 0.55)
    hdrLine:SetHeight(1)
    hdrLine:SetPoint("TOPLEFT",  hdrBg, "BOTTOMLEFT",  0, 0)
    hdrLine:SetPoint("TOPRIGHT", hdrBg, "BOTTOMRIGHT", 0, 0)

    -- Spec icon (left side of header bar)
    g_Main.specIcon = g_Main:CreateTexture(nil, "OVERLAY")
    g_Main.specIcon:SetSize(HDR_H - 6, HDR_H - 6)
    g_Main.specIcon:SetPoint("LEFT", hdrBg, "LEFT", 4, 0)
    g_Main.specIcon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    -- Title: "Priestly"
    local titTxt = g_Main:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    titTxt:SetPoint("LEFT",  g_Main.specIcon, "RIGHT", 3,  0)
    titTxt:SetText("|cff99ddffPriestly|r")

    -- Version: small, right of title
    local verTxt = g_Main:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    verTxt:SetPoint("LEFT",  titTxt, "RIGHT", 2, 0)
    verTxt:SetText("|cff555577v" .. VERSION .. "|r")

    -- Close button
    local xBtn = CreateFrame("Button", nil, g_Main, "UIPanelCloseButton")
    xBtn:SetPoint("TOPRIGHT", g_Main, "TOPRIGHT", 3, 3)
    xBtn:SetScale(0.6)
    xBtn:SetScript("OnClick", function() CloseUI(true) end)

    -- ── Drag handle (covers header only, so row buttons get clicks) ───────
    local drag = CreateFrame("Frame", nil, g_Main)
    drag:SetPoint("TOPLEFT",  hdrBg, "TOPLEFT",  0, 0)
    drag:SetPoint("TOPRIGHT", hdrBg, "TOPRIGHT", -16, 0)  -- leave room for X
    drag:SetHeight(HDR_H)
    drag:EnableMouse(true)
    drag:RegisterForDrag("LeftButton")
    drag:SetScript("OnDragStart", function() g_Main:StartMoving() end)
    drag:SetScript("OnDragStop",  function()
        g_Main:StopMovingOrSizing(); g_Moved = true
        -- Save position
        if PriestlyDB then
            local point, _, relPoint, x, y = g_Main:GetPoint()
            PriestlyDB.pos = { point = point, relPoint = relPoint, x = x, y = y }
        end
    end)

    -- ── Group header labels (pre-alloc) ──────────────────────────────────────
    for i = 1, MAX_GROUPS do
        local fs = g_Main:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        fs:SetTextColor(0.52, 0.52, 0.70)
        fs:Hide()
        g_GHdrs[i] = fs
    end

    -- ── Row buttons (pre-alloc) ───────────────────────────────────────────────
    for i = 1, MAX_ROWS do
        local r = CreateFrame("Button", "PriestlyRow"..i, g_Main, "SecureActionButtonTemplate")
        r:SetSize(ROW_W, ROW_H)
        r:EnableMouse(true)
        r:RegisterForClicks("LeftButtonDown", "RightButtonDown")

        r.bg = r:CreateTexture(nil, "BACKGROUND")
        r.bg:SetAllPoints()

        -- Spell icon (left)
        r.icon = r:CreateTexture(nil, "ARTWORK")
        r.icon:SetSize(ICON_W - 2, ICON_W - 2)
        r.icon:SetPoint("LEFT", r, "LEFT", 1, 0)
        r.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

        -- Timer text (right-aligned)
        r.timer = r:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        r.timer:SetPoint("RIGHT", r, "RIGHT", -3, 0)

        -- Missing count (bottom of bar, right of icon)
        r.missCount = r:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        r.missCount:SetPoint("LEFT", r, "LEFT", ICON_W + 2, 0)
        r.missCount:SetTextColor(1.0, 1.0, 1.0)

        -- "MISS" all-absent label (centred in bar area)
        r.missAll = r:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        r.missAll:SetPoint("CENTER", r, "CENTER", ICON_W / 2, 0)
        r.missAll:SetTextColor(1.0, 0.28, 0.28)
        r.missAll:SetText("MISS")

        r._active = false
        r:Hide()
        g_Rows[i] = r
    end

    -- ── Popover frame (pre-alloc) ─────────────────────────────────────────────
    g_Pop = CreateFrame("Frame", "PriestlyPopover", UIParent, "BackdropTemplate")
    g_Pop:SetFrameStrata("DIALOG")
    g_Pop:SetFrameLevel(200)
    g_Pop:SetClampedToScreen(true)
    g_Pop:SetBackdrop({
        bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    g_Pop:SetBackdropColor(0.05, 0.05, 0.12, Priestly_GetFrameAlpha())
    g_Pop:SetBackdropBorderColor(0.42, 0.42, 0.65, 1)
    -- NOTE: no EnableMouse — lets child SecureActionButtons receive clicks
    g_Pop:Hide()

    -- Popover header: buff icon
    g_Pop.hdrIcon = g_Pop:CreateTexture(nil, "ARTWORK")
    g_Pop.hdrIcon:SetSize(POP_HDR_H - 6, POP_HDR_H - 6)
    g_Pop.hdrIcon:SetPoint("TOPLEFT", g_Pop, "TOPLEFT", 7, -6)
    g_Pop.hdrIcon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    -- Popover header: buff name text
    g_Pop.hdrTxt = g_Pop:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    g_Pop.hdrTxt:SetPoint("LEFT",  g_Pop.hdrIcon, "RIGHT", 5, 0)
    g_Pop.hdrTxt:SetPoint("RIGHT", g_Pop,         "RIGHT", -6, 0)
    g_Pop.hdrTxt:SetPoint("TOP",   g_Pop,         "TOP",   0, -8)
    g_Pop.hdrTxt:SetJustifyH("LEFT")
    g_Pop.hdrTxt:SetTextColor(1.0, 0.82, 0.22)

    -- Thin divider under popover header
    local hdiv = g_Pop:CreateTexture(nil, "ARTWORK")
    hdiv:SetColorTexture(0.32, 0.32, 0.55, 0.55)
    hdiv:SetHeight(1)
    hdiv:SetPoint("TOPLEFT",  g_Pop, "TOPLEFT",  5, -(POP_HDR_H + 2))
    hdiv:SetPoint("TOPRIGHT", g_Pop, "TOPRIGHT", -5, -(POP_HDR_H + 2))

    -- Member rows in popover
    for i = 1, MAX_MEMBERS do
        local pr = CreateFrame("Button", "PriestlyPop"..i, g_Pop, "SecureActionButtonTemplate")
        pr:SetSize(POP_W - 10, POP_ROW_H)
        pr:SetPoint("TOPLEFT", g_Pop, "TOPLEFT",
            5, -(POP_HDR_H + 5) - (i - 1) * (POP_ROW_H + 2))
        pr:EnableMouse(true)
        pr:RegisterForClicks("LeftButtonDown", "RightButtonDown")
        pr:SetFrameLevel(202)  -- above g_Pop's level 200

        pr.bg = pr:CreateTexture(nil, "BACKGROUND")
        pr.bg:SetAllPoints()

        -- Range indicator ("R") — leftmost
        pr.rangeTxt = pr:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        pr.rangeTxt:SetPoint("LEFT", pr, "LEFT", 3, 0)
        pr.rangeTxt:SetWidth(13)
        pr.rangeTxt:SetJustifyH("CENTER")

        -- Class icon
        pr.classIcon = pr:CreateTexture(nil, "ARTWORK")
        pr.classIcon:SetSize(POP_ROW_H - 6, POP_ROW_H - 6)
        pr.classIcon:SetPoint("LEFT", pr.rangeTxt, "RIGHT", 2, 0)
        pr.classIcon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

        -- Player name (class coloured)
        pr.nameTxt = pr:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        pr.nameTxt:SetPoint("LEFT",  pr.classIcon, "RIGHT", 3,  0)
        pr.nameTxt:SetPoint("RIGHT", pr,           "RIGHT", -44, 0)
        pr.nameTxt:SetJustifyH("LEFT")

        -- Timer / "MISS"
        pr.timeTxt = pr:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        pr.timeTxt:SetPoint("RIGHT", pr, "RIGHT", -3, 0)
        pr.timeTxt:SetWidth(40)
        pr.timeTxt:SetJustifyH("RIGHT")

        -- PreClick: block cast if target is offline/dead
        pr:SetScript("PreClick", function(self, btn)
            if InCombatLockdown() then return end
            if not IsValidTarget(self._unit) then
                self:SetAttribute("spell1", nil)
                self:SetAttribute("spell2", nil)
            end
        end)

        -- PostClick: restore spells + refresh
        pr:SetScript("PostClick", function(self, btn)
            if InCombatLockdown() then return end
            local df = self._def
            if df then
                self:SetAttribute("spell1", df.grp)
                self:SetAttribute("spell2", df.sngl)
            end
            ScheduleRefresh()
        end)

        -- Tooltip for offline players
        pr:SetScript("OnEnter", function(self)
            if self._unit and not UnitIsConnected(self._unit) then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText(UnitName(self._unit) or "Unknown", 0.6, 0.6, 0.6)
                GameTooltip:AddLine("This player is offline", 1, 0.5, 0.5)
                GameTooltip:Show()
            end
        end)
        pr:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)

        pr._active = false
        pr:Hide()
        g_PRows[i] = pr
    end

    -- Popover hover polling: hide when mouse isn't over popover or its anchor row
    -- This replaces fragile OnLeave handlers
    g_Pop._hoverTimer = 0
    g_Pop:SetScript("OnUpdate", function(self, dt)
        if not self:IsShown() then return end
        self._hoverTimer = self._hoverTimer + dt
        if self._hoverTimer < 0.15 then return end
        self._hoverTimer = 0
        local overPop = MouseIsOver(self)
        local overAnchor = self._anchorRow and MouseIsOver(self._anchorRow)
        -- Also check if mouse is over any visible popup button
        local overChild = false
        for _, pr in ipairs(g_PRows) do
            if pr._active and pr:IsShown() and MouseIsOver(pr) then
                overChild = true
                break
            end
        end
        if not overPop and not overAnchor and not overChild then
            self:Hide()
        end
    end)

    -- ── Reagent footer ───────────────────────────────────────────────────────
    -- Thin divider
    g_Main.ftrLine = g_Main:CreateTexture(nil, "ARTWORK")
    g_Main.ftrLine:SetColorTexture(0.40, 0.40, 0.65, 0.40)
    g_Main.ftrLine:SetHeight(1)

    -- Helper: create a small reagent button with icon, count, and tooltip
    local function MakeReagentBtn(name, iconPath, itemID)
        local btn = CreateFrame("Button", name, g_Main)
        btn:SetSize(FTR_H - 2 + 24, FTR_H)  -- icon + room for count text
        btn:EnableMouse(true)
        btn._itemID = itemID

        btn.icon = btn:CreateTexture(nil, "ARTWORK")
        btn.icon:SetSize(FTR_H - 4, FTR_H - 4)
        btn.icon:SetPoint("LEFT", btn, "LEFT", 0, 0)
        btn.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        btn.icon:SetTexture(iconPath)

        btn.countTxt = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        btn.countTxt:SetPoint("LEFT", btn.icon, "RIGHT", 2, 0)

        btn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            if self._itemID then
                GameTooltip:SetItemByID(self._itemID)
            end
            GameTooltip:Show()
        end)
        btn:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)

        btn:Hide()
        return btn
    end

    g_Main.candleBtn  = MakeReagentBtn("PriestlyCandleBtn",  ItemIcon(SACRED_CANDLE_ID), SACRED_CANDLE_ID)
    g_Main.featherBtn = MakeReagentBtn("PriestlyFeatherBtn", ItemIcon(LIGHT_FEATHER_ID), LIGHT_FEATHER_ID)

    -- ── Timer ticker (0.5 s) ─────────────────────────────────────────────────
    local ftrTick = 0
    g_Main:SetScript("OnUpdate", function(self, dt)
        if not g_Vis then return end
        g_Ticker = g_Ticker + dt
        ftrTick  = ftrTick  + dt
        if g_Ticker >= 0.5 then
            g_Ticker = 0
            RefreshTimers()
        end
        if ftrTick >= 3.0 then
            ftrTick = 0
            RefreshFooter()
        end
    end)
end

-- ─── CloseUI ─────────────────────────────────────────────────────────────────

CloseUI = function(manual)
    if g_Main then g_Main:Hide() end
    if g_Pop  then g_Pop:Hide()  end
    g_Vis = false
    -- Only save "closed" state if user manually closed (not from leaving group)
    if manual and PriestlyDB then PriestlyDB.visible = false end
end

-- ─── UpdatePopover ───────────────────────────────────────────────────────────

UpdatePopover = function(anchorRow, members, def)
    if InCombatLockdown() then return end

    -- Header
    g_Pop.hdrIcon:SetTexture(SpellIcon(def.sngl, def.fallbackIcon))
    g_Pop.hdrTxt:SetText(def.grp)

    -- Track which row we're anchored to (for hover polling)
    g_Pop._anchorRow = anchorRow

    local cnt = math.min(#members, MAX_MEMBERS)
    for i = 1, cnt do
        local m  = members[i]
        local pr = g_PRows[i]

        -- Store state so the ticker can refresh this row
        pr._active = true
        pr._unit   = m.unit
        pr._def    = def

        -- Left-click  → group Prayer targeting this person (covers their group)
        pr:SetAttribute("type1",  "spell")
        pr:SetAttribute("spell1", def.grp)
        pr:SetAttribute("unit1",  m.unit)
        -- Right-click → single buff on this specific person
        pr:SetAttribute("type2",  "spell")
        pr:SetAttribute("spell2", def.sngl)
        pr:SetAttribute("unit2",  m.unit)

        -- Class icon
        local cls = m.class or "PRIEST"
        pr.classIcon:SetTexture(CLASS_ICONS[cls] or CLASS_ICONS.PRIEST)

        -- Name with class colour
        local cr, cg, cb = ClassColor(cls)
        pr.nameTxt:SetText(m.name)
        pr.nameTxt:SetTextColor(cr, cg, cb)

        ApplyPopRowVisuals(pr)
        pr:Show()
    end
    for i = cnt + 1, MAX_MEMBERS do
        g_PRows[i]._active = false
        g_PRows[i]:Hide()
    end

    local popH = POP_HDR_H + 7 + cnt * (POP_ROW_H + 2) + 6
    g_Pop:SetSize(POP_W, popH)
    g_Pop:ClearAllPoints()
    g_Pop:SetPoint("RIGHT", anchorRow, "LEFT", -4, 0)
    g_Pop:Show()
end

-- ─── UpdateUI (full layout rebuild) ──────────────────────────────────────────

UpdateUI = function()
    -- SetAttribute silently fails during combat lockdown; defer until combat ends
    if InCombatLockdown() then
        -- Just refresh visuals; full rebuild will happen on combat end
        if g_Vis then RefreshTimers() end
        return
    end
    InitUI()

    local groups, ord = GatherGroups()
    if #ord == 0 then CloseUI(); return end

    local defs = ActiveDefs(groups, ord)
    if #defs == 0 then CloseUI(); return end

    -- Refresh spec icon (handles talent respec)
    g_Main.specIcon:SetTexture(GetSpecIcon())

    -- Hide all reusable elements
    for _, r in ipairs(g_Rows)  do r._active = false; r:Hide() end
    for _, h in ipairs(g_GHdrs) do h:Hide() end

    local rowIdx = 0
    local hdrIdx = 0
    -- Start below header bar + inset padding
    local y = -(HDR_H + 6)

    for _, gNum in ipairs(ord) do
        if rowIdx >= MAX_ROWS then break end
        local members = groups[gNum]

        -- Group label (raid groups + pet group always)
        local inRaid = IsInRaid()
        if inRaid or gNum == PET_GROUP then
            hdrIdx = hdrIdx + 1
            if hdrIdx <= MAX_GROUPS then
                local hdr = g_GHdrs[hdrIdx]
                y = y - 1
                hdr:ClearAllPoints()
                hdr:SetPoint("TOPLEFT", g_Main, "TOPLEFT", ROW_X + 2, y)
                if gNum == PET_GROUP then
                    hdr:SetText("-- Pets --")
                else
                    hdr:SetText("-- Group " .. gNum .. " --")
                end
                hdr:Show()
                y = y - GRP_HDR_H
            end
        end

        -- One row per active buff
        for _, def in ipairs(defs) do
            rowIdx = rowIdx + 1
            if rowIdx > MAX_ROWS then break end

            local r   = g_Rows[rowIdx]
            local st  = GroupStat(members, def)

            -- Find valid targets (skip offline/dead)
            local validGrp = nil   -- any online member for group prayer
            local validSngl = nil  -- first online+unbuffed for single buff
            for _, m in ipairs(members) do
                if IsValidTarget(m.unit) then
                    if not validGrp then validGrp = m end
                    if not validSngl and BuffRem(m.unit, def.names) <= 0 then
                        validSngl = m
                    end
                end
            end
            -- Fallback: if all unbuffed are offline, target lowest-time online
            if not validSngl and validGrp then validSngl = validGrp end

            r:ClearAllPoints()
            r:SetPoint("TOPLEFT", g_Main, "TOPLEFT", ROW_X, y)
            r:SetSize(ROW_W, ROW_H)

            r.icon:SetTexture(SpellIcon(def.sngl, def.fallbackIcon))

            -- Store for ticker + PreClick target lookup
            r._active  = true
            r._members = members
            r._def     = def

            ApplyRowVisuals(r, st, def.duration)

            -- Left-click  → group Prayer targeting first valid member
            r:SetAttribute("type1",  "spell")
            r:SetAttribute("spell1", validGrp and def.grp or nil)
            r:SetAttribute("unit1",  validGrp and validGrp.unit or "player")
            -- Right-click → single buff on first valid missing person
            r:SetAttribute("type2",  "spell")
            r:SetAttribute("spell2", validSngl and def.sngl or nil)
            r:SetAttribute("unit2",  validSngl and validSngl.unit or "player")

            -- PreClick: refresh targets, skipping offline/dead
            r:SetScript("PreClick", function(self, btn)
                if InCombatLockdown() then return end
                local ms = self._members
                local df = self._def
                if not ms or not df then return end

                if btn == "LeftButton" then
                    -- Group prayer: find any valid member to target
                    for _, m in ipairs(ms) do
                        if IsValidTarget(m.unit) then
                            self:SetAttribute("unit1", m.unit)
                            return
                        end
                    end
                    -- Nobody valid — clear spell to prevent casting on self
                    self:SetAttribute("spell1", nil)
                else
                    -- Right-click: priority 1) unbuffed+online, 2) lowest remaining+online
                    local bestUnit, bestRem = nil, math.huge
                    for _, m in ipairs(ms) do
                        if IsValidTarget(m.unit) then
                            local rem = BuffRem(m.unit, df.names)
                            if rem <= 0 then
                                self:SetAttribute("unit2", m.unit)
                                return
                            end
                            if rem < bestRem then
                                bestRem = rem
                                bestUnit = m.unit
                            end
                        end
                    end
                    if bestUnit then
                        self:SetAttribute("unit2", bestUnit)
                    else
                        -- Nobody valid — clear spell to prevent casting on self
                        self:SetAttribute("spell2", nil)
                    end
                end
            end)

            -- PostClick: restore cleared spells + debug + refresh
            r:SetScript("PostClick", function(self, btn)
                if InCombatLockdown() then return end
                local df = self._def
                if not df then return end
                -- Restore spells that PreClick may have nilled
                self:SetAttribute("spell1", df.grp)
                self:SetAttribute("spell2", df.sngl)
                ScheduleRefresh()
            end)

            -- Mouseover: open popover
            do
                local cm, cd = members, def
                r:SetScript("OnEnter", function(self)
                    UpdatePopover(self, cm, cd)
                end)
                -- OnLeave handled by popover's polling ticker
            end

            r:Show()
            y = y - ROW_H - 1
        end
    end

    y = y - 2

    -- ── Position reagent footer (only if something to show) ──────────────
    RefreshFooterState()
    local showFooter = g_ShowCandle or g_ShowFeather
    if showFooter then
        g_Main.ftrLine:ClearAllPoints()
        g_Main.ftrLine:SetPoint("TOPLEFT",  g_Main, "TOPLEFT",  ROW_X, y)
        g_Main.ftrLine:SetPoint("TOPRIGHT", g_Main, "TOPRIGHT", -ROW_X, y)
        g_Main.ftrLine:Show()
        y = y - 2

        local xOff = ROW_X + 2
        if g_ShowCandle then
            g_Main.candleBtn:ClearAllPoints()
            g_Main.candleBtn:SetPoint("TOPLEFT", g_Main, "TOPLEFT", xOff, y)
            -- Update tooltip item ID dynamically
            g_Main.candleBtn._itemID = g_CandleID
            xOff = xOff + g_Main.candleBtn:GetWidth() + 4
        end
        if g_ShowFeather then
            g_Main.featherBtn:ClearAllPoints()
            g_Main.featherBtn:SetPoint("TOPLEFT", g_Main, "TOPLEFT", xOff, y)
        end

        y = y - FTR_H
        RefreshFooter()
    else
        g_Main.ftrLine:Hide()
        g_Main.candleBtn:Hide()
        g_Main.featherBtn:Hide()
    end

    g_Main:SetSize(FRAME_W, math.abs(y) + 2)

    if not g_Moved and not g_Main:IsShown() then
        g_Main:ClearAllPoints()
        if PriestlyDB and PriestlyDB.pos then
            local p = PriestlyDB.pos
            g_Main:SetPoint(p.point or "CENTER", UIParent, p.relPoint or "CENTER", p.x or 300, p.y or 50)
            g_Moved = true
        else
            g_Main:SetPoint("CENTER", UIParent, "CENTER", 300, 50)
        end
    end

    g_Main:Show()
    g_Vis = true
    if PriestlyDB then PriestlyDB.visible = true end
end

-- ─── Throttled roster/aura refresh ───────────────────────────────────────────

ScheduleRefresh = function()
    if g_RefQ or not g_Vis then return end
    g_RefQ = true
    After(0.35, function()
        g_RefQ = false
        if not g_Vis then return end
        if InCombatLockdown() then
            RefreshTimers()  -- visual only, no SetAttribute
        else
            UpdateUI()
        end
    end)
end

-- ─── Events ──────────────────────────────────────────────────────────────────

local evtFrame = CreateFrame("Frame", "PriestlyEvents")
evtFrame:RegisterEvent("PLAYER_LOGIN")
evtFrame:RegisterEvent("READY_CHECK")
evtFrame:RegisterEvent("UNIT_AURA")
evtFrame:RegisterEvent("UNIT_PET")
evtFrame:RegisterEvent("RAID_ROSTER_UPDATE")
evtFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
evtFrame:RegisterEvent("PLAYER_TALENT_UPDATE")
evtFrame:RegisterEvent("ACTIVE_TALENT_GROUP_CHANGED")
evtFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
evtFrame:RegisterEvent("BAG_UPDATE")
evtFrame:RegisterEvent("SPELLS_CHANGED")

evtFrame:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_LOGIN" then
        -- Check class
        local _, cls = UnitClass("player")
        g_IsPriest = (cls == "PRIEST")

        -- Initialise saved state (default: visible on Priests)
        Priestly_EnsureDefaults()
        if PriestlyDB.visible == nil then PriestlyDB.visible = true end

        InitUI()

        -- Apply configured opacity
        Priestly_ApplyAlpha()

        -- Auto-open if Priest and in a group (or solo mode)
        if g_IsPriest and (GetNumGroupMembers() > 0 or Priestly_ShowSolo()) then
            After(0.6, UpdateUI)
        end

        DEFAULT_CHAT_FRAME:AddMessage(
            "|cff99ddff[Priestly]|r Loaded. " ..
            (g_IsPriest and "Auto-opens when you join a group. " or "") ..
            "Type |cffffffff/priestly help|r for commands. " ..
            "Type |cffffffff/priestly config|r for options."
        )

    elseif event == "READY_CHECK" then
        if g_IsPriest then After(0.4, UpdateUI) end

    elseif event == "UNIT_AURA" then
        ScheduleRefresh()

    elseif event == "UNIT_PET" then
        -- Pet summoned or dismissed: rebuild to add/remove pet rows
        ScheduleRefresh()

    elseif event == "RAID_ROSTER_UPDATE" or event == "GROUP_ROSTER_UPDATE" then
        local n = GetNumGroupMembers()
        if n > 0 and not g_Vis and g_IsPriest then
            After(0.5, UpdateUI)
        elseif n == 0 and not Priestly_ShowSolo() then
            CloseUI()  -- auto-close, not manual (unless solo mode)
        elseif n == 0 and Priestly_ShowSolo() then
            ScheduleRefresh()  -- still solo, just refresh
        else
            ScheduleRefresh()
        end

    elseif event == "PLAYER_TALENT_UPDATE" or event == "SPELLS_CHANGED" or event == "ACTIVE_TALENT_GROUP_CHANGED" then
        if g_Main and g_Main.specIcon then
            g_Main.specIcon:SetTexture(GetSpecIcon())
        end
        RefreshFooterState()
        -- Full rebuild: available buffs may change on respec/dual spec swap
        if g_Vis and not InCombatLockdown() then
            After(0.3, UpdateUI)
        elseif g_Vis then
            RefreshFooter()
        end

    elseif event == "PLAYER_REGEN_ENABLED" then
        -- Combat ended: full rebuild so SetAttribute calls actually work
        if g_Vis then After(0.2, UpdateUI) end

    elseif event == "BAG_UPDATE" then
        if g_Vis then RefreshFooter() end
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
        DEFAULT_CHAT_FRAME:AddMessage("  |cffffffff/priestly help|r       this message")
        DEFAULT_CHAT_FRAME:AddMessage(c .. " Main frame rows:")
        DEFAULT_CHAT_FRAME:AddMessage("  Left-click   cast group Prayer")
        DEFAULT_CHAT_FRAME:AddMessage("  Right-click  single buff first missing person")
        DEFAULT_CHAT_FRAME:AddMessage("  Mouseover    open per-member popover")
        DEFAULT_CHAT_FRAME:AddMessage(c .. " Popover (left panel):")
        DEFAULT_CHAT_FRAME:AddMessage("  Left-click   cast group Prayer on that person")
        DEFAULT_CHAT_FRAME:AddMessage("  Right-click  single buff that person")
        DEFAULT_CHAT_FRAME:AddMessage("  R = green (in range) / yellow (out of range) / grey (offline)")
        DEFAULT_CHAT_FRAME:AddMessage("  Timer = green >50% / yellow 10-50% / red <10%")

    elseif cmd == "config" or cmd == "options" or cmd == "settings" or cmd == "opt" then
        if Priestly_OpenConfig then Priestly_OpenConfig() end

    elseif cmd == "reset" then
        if PriestlyDB then PriestlyDB.pos = nil end
        g_Moved = false
        if g_Main then
            g_Main:ClearAllPoints()
            g_Main:SetPoint("CENTER", UIParent, "CENTER", 300, 50)
        end
        DEFAULT_CHAT_FRAME:AddMessage("|cff99ddff[Priestly]|r Window position reset.")

    elseif cmd == "hide" or cmd == "close" then
        CloseUI(true)

    elseif cmd == "show" then
        if PriestlyDB then PriestlyDB.visible = true end
        UpdateUI()

    else
        if g_Vis then
            CloseUI(true)
        else
            if PriestlyDB then PriestlyDB.visible = true end
            UpdateUI()
        end
    end
end
