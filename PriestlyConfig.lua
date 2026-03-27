-- ============================================================================
-- PriestlyConfig.lua  –  Options panel for Priestly
-- Integrates into Interface → AddOns in TBC Anniversary (modern engine)
-- ============================================================================

local ADDON_NAME = "Priestly"

-- ─── Default configuration ──────────────────────────────────────────────────

local DEFAULTS = {
    trackFort       = true,
    trackSpirit     = true,
    shadowMode      = "detect",   -- "always" | "detect" | "instance"
    showSolo        = false,
    trackPets       = true,
    frameAlpha      = 0.96,
    shadowInstances = nil,
}

-- ─── Instance databases ─────────────────────────────────────────────────────
-- { "Instance Name", "category", defaultEnabled, "Tooltip: boss encounters" }
-- Instance names must match GetInstanceInfo() return values.

local TBC_INSTANCE_DB = {
    -- ── TBC Raids ────────────────────────────────────────────────────────────
    { "Karazhan",             "Raids", true,
      "Prince Malchezaar (Shadow Nova, SW:P), Netherspite (Netherbreath), Shade of Aran (Shadow Bolts), Nightbane (Smoking Blast)" },
    { "Gruul's Lair",         "Raids", false,
      "No significant shadow damage encounters." },
    { "Magtheridon's Lair",   "Raids", true,
      "Channelers cast Shadow Bolt Volley during phase 1." },
    { "Serpentshrine Cavern", "Raids", true,
      "Leotheras the Blind (Inner Demons), Fathom-Lord Karathress (Shadow Bolt adds)." },
    { "Tempest Keep",         "Raids", false,
      "Primarily Arcane/Fire damage. Void Reaver is Arcane." },
    { "Hyjal Summit",        "Raids", true,
      "Kaz'rogal (Shadow Bolt Volley, Mark), Azgalor (Doom, Rain of Fire), Archimonde (Grip of the Legion)." },
    { "Black Temple",        "Raids", true,
      "Teron Gorefiend (Shadow of Death), Gurtogg Bloodboil (Fel Acid Breath), Mother Shahraz (all beams are Shadow), Illidan (Shadow Blast P2, Dark Barrage)." },
    { "Sunwell Plateau",     "Raids", true,
      "M'uru (Darkness, Void Sentinels), Entropius (Shadow Bolt Volley, Negative Energy), Kil'jaeden (Shadow Spike, Legion Lightning)." },
    { "Zul'Aman",            "Raids", false,
      "Hex Lord Malacrass can shadow bolt. Generally not required." },

    -- ── TBC Dungeons ─────────────────────────────────────────────────────────
    { "Hellfire Ramparts",       "Dungeons", false,
      "No significant shadow damage." },
    { "The Blood Furnace",       "Dungeons", true,
      "Keli'dan the Breaker (Shadow Bolt Volley)." },
    { "The Shattered Halls",     "Dungeons", true,
      "Grand Warlock Nethekurse (Shadow Bolt, Shadow Cleave, Dark Spin)." },
    { "The Slave Pens",          "Dungeons", false,
      "Primarily Nature damage." },
    { "The Underbog",            "Dungeons", false,
      "Primarily Nature damage." },
    { "The Steamvault",          "Dungeons", false,
      "No significant shadow damage." },
    { "Mana-Tombs",              "Dungeons", true,
      "Pandemonius (Shadow Bolt, Dark Shell)." },
    { "Auchenai Crypts",         "Dungeons", true,
      "Exarch Maladaar (Shadow Word: Pain, Ribbon of Souls). Heavy shadow trash." },
    { "Sethekk Halls",           "Dungeons", true,
      "Darkweaver Syth (Shadow Shock, Shadow elementals)." },
    { "Shadow Labyrinth",        "Dungeons", true,
      "Ambassador Hellmaw (Shadow Bolt), Grandmaster Vorpil (Shadow Bolt Volley), Murmur (Murmur's Touch)." },
    { "Old Hillsbrad Foothills", "Dungeons", false,
      "No significant shadow damage." },
    { "The Black Morass",        "Dungeons", false,
      "No significant shadow damage." },
    { "The Mechanar",            "Dungeons", false,
      "Primarily Arcane/Fire damage." },
    { "The Botanica",            "Dungeons", false,
      "No significant shadow damage." },
    { "The Arcatraz",            "Dungeons", true,
      "Zereketh the Unbound (Shadow Bolt Volley, Void Zone), Harbinger Skyriss (Mind Rend)." },
    { "Magisters' Terrace",      "Dungeons", true,
      "Priestess Delrissa (Shadow Priest add), Kael'thas Sunstrider (Gravity Lapse shadow component)." },
}

local VANILLA_INSTANCE_DB = {
    -- ── Vanilla Raids ────────────────────────────────────────────────────────
    { "Naxxramas",               "Raids", true,
      "Gothik the Harvester (Shadow Bolt), Loatheb (Inevitable Doom), Four Horsemen (Mark of Zeliek), Kel'Thuzad (Shadow Fissure, Frost Blast)." },
    { "Blackwing Lair",          "Raids", true,
      "Nefarian (Shadow Flame), Vaelastrasz (Burning Adrenaline has shadow component)." },
    { "Temple of Ahn'Qiraj",    "Raids", true,
      "Twin Emperors (Shadow Bolt), C'Thun (Dark Glare), Ouro (Shadow damage on submerge)." },
    { "Zul'Gurub",               "Raids", true,
      "High Priest Venoxis (Shadow Bolt Volley), Hakkar (Corrupted Blood, Life Drain)." },
    { "Ruins of Ahn'Qiraj",     "Raids", false,
      "Ossirian (Shadow damage component). Generally not required." },
    { "Molten Core",             "Raids", false,
      "Primarily Fire damage throughout." },
    { "Onyxia's Lair",           "Raids", false,
      "Primarily Fire damage (Breath, Fireball)." },

    -- ── Vanilla Dungeons ─────────────────────────────────────────────────────
    { "Scholomance",             "Dungeons", true,
      "Darkmaster Gandling (Shadow damage), Rattlegore, heavy shadow trash throughout." },
    { "Stratholme",              "Dungeons", true,
      "Baron Rivendare (Shadow Bolt), Baroness Anastari (Shadow Bolt), undead shadow casters." },
    { "Dire Maul",               "Dungeons", true,
      "Immol'thar (Shadow Bolt, Portal of Immol'thar). West wing warlocks cast shadow." },
    { "The Temple of Atal'Hakkar","Dungeons", true,
      "Shade of Eranikus (Shadow Bolt Volley), Jammal'an the Prophet (Shadow Bolt)." },
    { "Upper Blackrock Spire",   "Dungeons", false,
      "Some shadow casters. Generally not required." },
    { "Lower Blackrock Spire",   "Dungeons", false,
      "Some shadow casters. Generally not required." },
    { "Blackrock Depths",        "Dungeons", false,
      "Ambassador Flamelash (shadow), scattered shadow casters. Generally not required." },
    { "Maraudon",                "Dungeons", false,
      "Princess Theradras (shadow component). Low-level instance." },
    { "Razorfen Downs",          "Dungeons", false,
      "Amnennar the Coldbringer (shadow/frost). Low-level instance." },
    { "Shadowfang Keep",         "Dungeons", false,
      "Arugal (Shadow Bolt, Void Bolt). Low-level instance." },
}

-- ─── Ensure defaults ────────────────────────────────────────────────────────

function Priestly_EnsureDefaults()
    if not PriestlyDB then PriestlyDB = {} end
    for k, v in pairs(DEFAULTS) do
        if PriestlyDB[k] == nil then
            PriestlyDB[k] = v
        end
    end
    if PriestlyDB.shadowInstances == nil then
        PriestlyDB.shadowInstances = {}
        for _, entry in ipairs(TBC_INSTANCE_DB) do
            PriestlyDB.shadowInstances[entry[1]] = entry[3]
        end
        for _, entry in ipairs(VANILLA_INSTANCE_DB) do
            PriestlyDB.shadowInstances[entry[1]] = entry[3]
        end
    end
    -- If upgrading from an older version, backfill any new instances
    for _, entry in ipairs(TBC_INSTANCE_DB) do
        if PriestlyDB.shadowInstances[entry[1]] == nil then
            PriestlyDB.shadowInstances[entry[1]] = entry[3]
        end
    end
    for _, entry in ipairs(VANILLA_INSTANCE_DB) do
        if PriestlyDB.shadowInstances[entry[1]] == nil then
            PriestlyDB.shadowInstances[entry[1]] = entry[3]
        end
    end
    PriestlyDB.shadowBosses = nil  -- migration
end

-- ─── Instance-based shadow detection ────────────────────────────────────────

local g_InShadowInstance = false

local function CheckCurrentInstance()
    local name = GetInstanceInfo()
    if not name or name == "" then
        g_InShadowInstance = false
        return
    end
    g_InShadowInstance = (PriestlyDB
        and PriestlyDB.shadowInstances
        and PriestlyDB.shadowInstances[name] == true)
end

function Priestly_ShouldShowShadow(groups, ord)
    if not PriestlyDB then return false end
    local mode = PriestlyDB.shadowMode or "detect"
    if mode == "always" then return true end
    if mode == "detect" then
        if groups and ord then
            for _, gn in ipairs(ord) do
                for _, m in ipairs(groups[gn]) do
                    if UnitExists(m.unit) then
                        for i = 1, 40 do
                            local bName = UnitBuff(m.unit, i)
                            if not bName then break end
                            if bName == "Shadow Protection" or bName == "Prayer of Shadow Protection" then
                                return true
                            end
                        end
                    end
                end
            end
        end
        return false
    end
    if mode == "instance" then return g_InShadowInstance end
    return false
end

function Priestly_TrackPets()
    return PriestlyDB and PriestlyDB.trackPets ~= false
end

function Priestly_IsBuffEnabled(defId)
    if not PriestlyDB then return true end
    if defId == "fort"   then return PriestlyDB.trackFort   ~= false end
    if defId == "spirit" then return PriestlyDB.trackSpirit  ~= false end
    return true
end

function Priestly_GetFrameAlpha()
    return PriestlyDB and PriestlyDB.frameAlpha or 0.96
end

function Priestly_ShowSolo()
    return PriestlyDB and PriestlyDB.showSolo == true
end

-- ─── Instance detection events ──────────────────────────────────────────────

local detectFrame = CreateFrame("Frame", "PriestlyInstanceDetector")
detectFrame:RegisterEvent("PLAYER_LOGIN")
detectFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
detectFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
detectFrame:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_LOGIN" then
        Priestly_EnsureDefaults()
        CheckCurrentInstance()
    else
        CheckCurrentInstance()
        if Priestly_ScheduleRefresh then Priestly_ScheduleRefresh() end
    end
end)

-- ═════════════════════════════════════════════════════════════════════════════
-- OPTIONS PANEL  –  Three tabs: Settings | TBC Instances | Vanilla Instances
-- ═════════════════════════════════════════════════════════════════════════════

local panel = CreateFrame("Frame", "PriestlyOptionsPanel")
panel.name = ADDON_NAME

-- ─── Widget helpers ─────────────────────────────────────────────────────────

local function MakeHeader(parent, yRef, text, width)
    yRef.v = yRef.v - 14
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    fs:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, yRef.v)
    fs:SetText(text)
    local textH = fs:GetStringHeight() or 16
    yRef.v = yRef.v - textH - 2
    local line = parent:CreateTexture(nil, "ARTWORK")
    line:SetColorTexture(0.40, 0.40, 0.65, 0.45)
    line:SetHeight(1)
    line:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, yRef.v)
    line:SetWidth(width or 480)
    yRef.v = yRef.v - 8
end

local function MakeCheckbox(parent, yRef, label, dbKey, onChange)
    yRef.v = yRef.v - 4
    local cb = CreateFrame("CheckButton", "PriestlyCB_"..dbKey, parent, "InterfaceOptionsCheckButtonTemplate")
    cb:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, yRef.v)
    cb.Text:SetText(label)
    cb:SetChecked(PriestlyDB[dbKey] ~= false)
    cb:SetScript("OnClick", function(self)
        PriestlyDB[dbKey] = self:GetChecked() and true or false
        if onChange then onChange(self:GetChecked()) end
        if Priestly_ScheduleRefresh then Priestly_ScheduleRefresh() end
        if Priestly_ForceRebuild then Priestly_ForceRebuild() end
    end)
    yRef.v = yRef.v - 26
    return cb
end

local function MakeDesc(parent, yRef, text, indent)
    indent = indent or 32
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fs:SetPoint("TOPLEFT", parent, "TOPLEFT", indent, yRef.v)
    fs:SetWidth(440)
    fs:SetJustifyH("LEFT")
    fs:SetText("|cff999999"..text.."|r")
    yRef.v = yRef.v - (fs:GetStringHeight() + 6)
    return fs
end

local function MakeRadioGroup(parent, yRef, options, currentKey, onSelect)
    local radios = {}
    for _, opt in ipairs(options) do
        yRef.v = yRef.v - 4
        local rb = CreateFrame("CheckButton", "PriestlyRB_"..opt.key, parent, "UIRadioButtonTemplate")
        rb:SetPoint("TOPLEFT", parent, "TOPLEFT", 4, yRef.v)
        local textObj = rb.text or rb.Text or _G[rb:GetName().."Text"]
        if textObj then
            textObj:SetText(opt.label)
            textObj:SetFontObject("GameFontHighlight")
        end
        rb._key = opt.key
        radios[#radios+1] = rb
        rb:SetScript("OnClick", function(self)
            for _, other in ipairs(radios) do
                other:SetChecked(other._key == self._key)
            end
            onSelect(self._key)
        end)
        yRef.v = yRef.v - 22
    end
    -- Set initial state AFTER all are built
    for _, rb in ipairs(radios) do
        rb:SetChecked(rb._key == currentKey)
    end
    return radios
end

-- ─── Instance tab builder (shared between TBC and Vanilla) ──────────────────

local function BuildInstanceTab(parent, instanceDB, panelWidth)
    local scroll = CreateFrame("ScrollFrame", parent:GetName().."Scroll", parent, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 0, 0)
    scroll:SetPoint("BOTTOMRIGHT", -16, 0)

    local child = CreateFrame("Frame", parent:GetName().."Child")
    child:SetSize(panelWidth, 800)
    scroll:SetScrollChild(child)

    local iy = { v = 0 }

    iy.v = iy.v - 4
    local desc = child:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    desc:SetPoint("TOPLEFT", child, "TOPLEFT", 0, iy.v)
    desc:SetWidth(panelWidth - 20)
    desc:SetJustifyH("LEFT")
    desc:SetText("|cff999999When Shadow Protection is set to \"by instance\" in Settings, " ..
        "it activates when you zone into a checked instance. " ..
        "Hover an instance name for encounter details. " ..
        "Pre-checked instances have bosses with significant shadow damage.|r")
    iy.v = iy.v - (desc:GetStringHeight() + 10)

    -- Group by category
    local categories = {}
    local catOrder = {}
    for _, entry in ipairs(instanceDB) do
        local cat = entry[2]
        if not categories[cat] then
            categories[cat] = {}
            catOrder[#catOrder+1] = cat
        end
        categories[cat][#categories[cat]+1] = entry
    end

    local COL_W  = 220
    local COL_GAP = 20
    local ROW_H  = 24
    local allCheckboxes = {}

    for _, cat in ipairs(catOrder) do
        MakeHeader(child, iy, cat, panelWidth)

        local entries = categories[cat]
        local numCols = 2
        local numRows = math.ceil(#entries / numCols)
        local startY = iy.v

        for idx, entry in ipairs(entries) do
            local instName    = entry[1]
            local tooltip     = entry[4] or ""
            local col = math.floor((idx - 1) / numRows)
            local row = (idx - 1) % numRows
            local xOff = col * (COL_W + COL_GAP)
            local yOff = startY - row * ROW_H

            local icb = CreateFrame("CheckButton", "PriestlyInst_"..parent:GetName().."_"..idx, child, "InterfaceOptionsCheckButtonTemplate")
            icb:SetPoint("TOPLEFT", child, "TOPLEFT", xOff, yOff)
            icb.Text:SetText(instName)
            icb.Text:SetJustifyH("LEFT")
            icb.Text:SetWidth(COL_W - 28)
            icb:SetChecked(PriestlyDB.shadowInstances[instName] == true)
            icb._instName = instName

            icb:SetScript("OnClick", function(self)
                PriestlyDB.shadowInstances[self._instName] = self:GetChecked() and true or false
                CheckCurrentInstance()
                if Priestly_ScheduleRefresh then Priestly_ScheduleRefresh() end
            end)

            -- Tooltip on hover showing encounter info
            if tooltip ~= "" then
                icb:HookScript("OnEnter", function(self)
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:AddLine(self._instName, 1.0, 0.82, 0.22)
                    GameTooltip:AddLine(" ")
                    GameTooltip:AddLine("Shadow encounters:", 0.60, 0.60, 0.85)
                    -- Word-wrap the tooltip text
                    GameTooltip:AddLine(tooltip, 1, 1, 1, true)
                    GameTooltip:Show()
                end)
                icb:HookScript("OnLeave", function()
                    GameTooltip:Hide()
                end)
            end

            allCheckboxes[#allCheckboxes+1] = icb
        end

        iy.v = startY - numRows * ROW_H - 4
    end

    -- Buttons row
    iy.v = iy.v - 6
    local btnAll = CreateFrame("Button", parent:GetName().."All", child, "UIPanelButtonTemplate")
    btnAll:SetSize(90, 22)
    btnAll:SetPoint("TOPLEFT", child, "TOPLEFT", 0, iy.v)
    btnAll:SetText("Select All")
    btnAll:SetScript("OnClick", function()
        for _, entry in ipairs(instanceDB) do
            PriestlyDB.shadowInstances[entry[1]] = true
        end
        for _, cb in ipairs(allCheckboxes) do cb:SetChecked(true) end
        CheckCurrentInstance()
    end)

    local btnNone = CreateFrame("Button", parent:GetName().."None", child, "UIPanelButtonTemplate")
    btnNone:SetSize(90, 22)
    btnNone:SetPoint("LEFT", btnAll, "RIGHT", 8, 0)
    btnNone:SetText("Deselect All")
    btnNone:SetScript("OnClick", function()
        for _, entry in ipairs(instanceDB) do
            PriestlyDB.shadowInstances[entry[1]] = false
        end
        for _, cb in ipairs(allCheckboxes) do cb:SetChecked(false) end
        CheckCurrentInstance()
    end)

    local btnDefaults = CreateFrame("Button", parent:GetName().."Defaults", child, "UIPanelButtonTemplate")
    btnDefaults:SetSize(110, 22)
    btnDefaults:SetPoint("LEFT", btnNone, "RIGHT", 8, 0)
    btnDefaults:SetText("Reset Defaults")
    btnDefaults:SetScript("OnClick", function()
        for _, entry in ipairs(instanceDB) do
            PriestlyDB.shadowInstances[entry[1]] = entry[3]
        end
        for _, cb in ipairs(allCheckboxes) do
            if cb._instName then
                for _, entry in ipairs(instanceDB) do
                    if entry[1] == cb._instName then
                        cb:SetChecked(entry[3])
                        break
                    end
                end
            end
        end
        CheckCurrentInstance()
    end)

    iy.v = iy.v - 30
    child:SetHeight(math.abs(iy.v) + 20)

    return scroll
end

-- ─── Build the panel ────────────────────────────────────────────────────────

local function BuildPanel(panel)
    if panel._built then return end
    panel._built = true
    Priestly_EnsureDefaults()

    local PANEL_W = 490

    -- ── Title ───────────────────────────────────────────────────────────────
    local titleFs = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    titleFs:SetPoint("TOPLEFT", panel, "TOPLEFT", 14, -14)
    titleFs:SetText("|cff99ddffPriestly|r")

    local verFs = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    verFs:SetPoint("LEFT", titleFs, "RIGHT", 6, 0)
    verFs:SetText("|cff555577v0.2|r")

    -- ── Tab bar ─────────────────────────────────────────────────────────────
    local TAB_Y = -38
    local tabNames = { "Settings", "TBC Instances", "Vanilla Instances" }
    local tabButtons = {}
    local tabFrames  = {}

    local function SelectTab(idx)
        for i, btn in ipairs(tabButtons) do
            if i == idx then
                btn:SetNormalFontObject("GameFontHighlight")
                btn.bg:SetColorTexture(0.15, 0.15, 0.25, 0.90)
                btn.underline:Show()
            else
                btn:SetNormalFontObject("GameFontNormalSmall")
                btn.bg:SetColorTexture(0.08, 0.08, 0.15, 0.60)
                btn.underline:Hide()
            end
        end
        for i, f in ipairs(tabFrames) do
            if i == idx then f:Show() else f:Hide() end
        end
    end

    local tabX = 14
    for i, name in ipairs(tabNames) do
        local btnW = (i == 1) and 90 or 120
        local btn = CreateFrame("Button", "PriestlyTab"..i, panel)
        btn:SetSize(btnW, 24)
        btn:SetPoint("TOPLEFT", panel, "TOPLEFT", tabX, TAB_Y)
        btn:SetNormalFontObject("GameFontNormalSmall")
        btn:SetText(name)

        btn.bg = btn:CreateTexture(nil, "BACKGROUND")
        btn.bg:SetAllPoints()
        btn.bg:SetColorTexture(0.08, 0.08, 0.15, 0.60)

        btn.underline = btn:CreateTexture(nil, "ARTWORK")
        btn.underline:SetColorTexture(0.55, 0.55, 0.85, 0.80)
        btn.underline:SetHeight(2)
        btn.underline:SetPoint("BOTTOMLEFT",  btn, "BOTTOMLEFT",  2, 0)
        btn.underline:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -2, 0)
        btn.underline:Hide()

        btn:SetScript("OnClick", function() SelectTab(i) end)
        tabButtons[i] = btn
        tabX = tabX + btnW + 4
    end

    local tabSep = panel:CreateTexture(nil, "ARTWORK")
    tabSep:SetColorTexture(0.30, 0.30, 0.50, 0.40)
    tabSep:SetHeight(1)
    tabSep:SetPoint("TOPLEFT",  panel, "TOPLEFT",  14, TAB_Y - 26)
    tabSep:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -14, TAB_Y - 26)

    local CONTENT_TOP = TAB_Y - 32

    -- ═════════════════════════════════════════════════════════════════════════
    -- TAB 1: Settings
    -- ═════════════════════════════════════════════════════════════════════════

    local settingsScroll = CreateFrame("ScrollFrame", "PriestlySettingsScroll", panel, "UIPanelScrollFrameTemplate")
    settingsScroll:SetPoint("TOPLEFT", panel, "TOPLEFT", 14, CONTENT_TOP)
    settingsScroll:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -30, 10)

    local settingsChild = CreateFrame("Frame", "PriestlySettingsChild")
    settingsChild:SetSize(PANEL_W, 600)
    settingsScroll:SetScrollChild(settingsChild)
    tabFrames[1] = settingsScroll

    local y = { v = 0 }

    -- ── General ──────────────────────────────────────────────────────────────
    MakeHeader(settingsChild, y, "General", PANEL_W)
    MakeCheckbox(settingsChild, y,
        "Show when solo (always display, even outside a group)", "showSolo",
        function(enabled)
            -- Immediately show or hide via the dedicated handler
            if Priestly_OnSoloToggle then Priestly_OnSoloToggle(enabled) end
        end)
    MakeDesc(settingsChild, y,
        "The Priestly frame stays visible without a party or raid. Use /priestly hide to close.")

    -- ── Buff Tracking ────────────────────────────────────────────────────────
    MakeHeader(settingsChild, y, "Buff Tracking", PANEL_W)
    MakeCheckbox(settingsChild, y, "Track |cffffffffPower Word: Fortitude|r / Prayer of Fortitude", "trackFort")
    MakeCheckbox(settingsChild, y, "Track |cffffffffDivine Spirit|r / Prayer of Spirit", "trackSpirit")

    -- ── Shadow Protection ────────────────────────────────────────────────────
    MakeHeader(settingsChild, y, "Shadow Protection", PANEL_W)

    y.v = y.v - 2
    local shadowDesc = settingsChild:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    shadowDesc:SetPoint("TOPLEFT", settingsChild, "TOPLEFT", 0, y.v)
    shadowDesc:SetWidth(PANEL_W)
    shadowDesc:SetJustifyH("LEFT")
    shadowDesc:SetText("|cffccccccChoose when Shadow Protection appears in the buff tracker.|r")
    y.v = y.v - (shadowDesc:GetStringHeight() + 8)

    MakeRadioGroup(settingsChild, y, {
        { key = "always",   label = "Always show Shadow Protection" },
        { key = "detect",   label = "Show when detected on a group member" },
        { key = "instance", label = "Show by instance (configure in the |cff99ddffTBC / Vanilla Instances|r tabs)" },
    }, PriestlyDB.shadowMode, function(key)
        PriestlyDB.shadowMode = key
        CheckCurrentInstance()
        if Priestly_ForceRebuild then Priestly_ForceRebuild() end
    end)

    MakeDesc(settingsChild, y,
        "\"Detected\" shows it when any group member already has the buff. " ..
        "\"By instance\" activates it when you enter a checked instance.", 8)

    -- ── Pet Tracking ─────────────────────────────────────────────────────────
    MakeHeader(settingsChild, y, "Pet Tracking", PANEL_W)
    MakeCheckbox(settingsChild, y,
        "Track pets (Hunter, Warlock, Mage water elemental, Shadowfiend)", "trackPets")
    MakeDesc(settingsChild, y, "Pets appear in a separate group at the bottom of the frame.")

    -- ── Appearance ───────────────────────────────────────────────────────────
    MakeHeader(settingsChild, y, "Appearance", PANEL_W)

    y.v = y.v - 4
    local alphaLabel = settingsChild:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    alphaLabel:SetPoint("TOPLEFT", settingsChild, "TOPLEFT", 0, y.v)
    alphaLabel:SetText("Frame Opacity")
    y.v = y.v - 18

    local SLIDER_W = 220

    -- Track background
    local trackBg = settingsChild:CreateTexture(nil, "BACKGROUND")
    trackBg:SetColorTexture(0.10, 0.10, 0.18, 0.95)
    trackBg:SetSize(SLIDER_W, 10)
    trackBg:SetPoint("TOPLEFT", settingsChild, "TOPLEFT", 8, y.v - 6)

    -- Track borders
    for _, info in ipairs({
        {"TOPLEFT","TOPRIGHT",     nil, 1},    -- top
        {"BOTTOMLEFT","BOTTOMRIGHT", nil, 1},  -- bottom
    }) do
        local t = settingsChild:CreateTexture(nil, "BORDER")
        t:SetColorTexture(0.35, 0.35, 0.55, 0.80)
        t:SetHeight(info[4])
        t:SetPoint(info[1], trackBg, info[1])
        t:SetPoint(info[2], trackBg, info[2])
    end
    for _, side in ipairs({"LEFT", "RIGHT"}) do
        local t = settingsChild:CreateTexture(nil, "BORDER")
        t:SetColorTexture(0.35, 0.35, 0.55, 0.80)
        t:SetWidth(1)
        t:SetPoint("TOP"..side, trackBg, "TOP"..side)
        t:SetPoint("BOTTOM"..side, trackBg, "BOTTOM"..side)
    end

    -- Fill bar
    local trackFill = settingsChild:CreateTexture(nil, "ARTWORK")
    trackFill:SetColorTexture(0.40, 0.40, 0.72, 0.75)
    trackFill:SetPoint("TOPLEFT", trackBg, "TOPLEFT", 1, -1)
    trackFill:SetHeight(8)

    local alphaSlider = CreateFrame("Slider", "PriestlyAlphaSlider", settingsChild, "OptionsSliderTemplate")
    alphaSlider:SetPoint("TOPLEFT", settingsChild, "TOPLEFT", 4, y.v)
    alphaSlider:SetWidth(SLIDER_W + 8)
    alphaSlider:SetMinMaxValues(0.20, 1.00)
    alphaSlider:SetValueStep(0.05)
    alphaSlider:SetObeyStepOnDrag(true)
    alphaSlider:SetValue(PriestlyDB.frameAlpha or 0.96)
    alphaSlider.Low:SetText("20%")
    alphaSlider.High:SetText("100%")

    local alphaVal = settingsChild:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    alphaVal:SetPoint("LEFT", alphaSlider, "RIGHT", 10, 0)
    alphaVal:SetText(string.format("%d%%", (PriestlyDB.frameAlpha or 0.96) * 100))

    local function UpdateFill()
        local min, max = alphaSlider:GetMinMaxValues()
        local val = alphaSlider:GetValue()
        local pct = (val - min) / (max - min)
        trackFill:SetWidth(math.max(1, pct * (SLIDER_W - 2)))
    end

    alphaSlider:SetScript("OnValueChanged", function(self, value)
        value = math.floor(value * 20 + 0.5) / 20
        PriestlyDB.frameAlpha = value
        alphaVal:SetText(string.format("%d%%", value * 100))
        UpdateFill()
        if Priestly_ApplyAlpha then Priestly_ApplyAlpha() end
    end)

    alphaSlider:HookScript("OnShow", function() C_Timer.After(0.02, UpdateFill) end)
    C_Timer.After(0.1, UpdateFill)

    y.v = y.v - 40
    MakeDesc(settingsChild, y,
        "Controls the background opacity of the main Priestly frame and popover.", 4)

    settingsChild:SetHeight(math.abs(y.v) + 20)

    -- ═════════════════════════════════════════════════════════════════════════
    -- TAB 2: TBC Instances
    -- ═════════════════════════════════════════════════════════════════════════

    local tbcContainer = CreateFrame("Frame", "PriestlyTBCContainer", panel)
    tbcContainer:SetPoint("TOPLEFT", panel, "TOPLEFT", 14, CONTENT_TOP)
    tbcContainer:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -14, 10)
    tabFrames[2] = tbcContainer

    BuildInstanceTab(tbcContainer, TBC_INSTANCE_DB, PANEL_W)

    -- ═════════════════════════════════════════════════════════════════════════
    -- TAB 3: Vanilla Instances
    -- ═════════════════════════════════════════════════════════════════════════

    local vanillaContainer = CreateFrame("Frame", "PriestlyVanillaContainer", panel)
    vanillaContainer:SetPoint("TOPLEFT", panel, "TOPLEFT", 14, CONTENT_TOP)
    vanillaContainer:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -14, 10)
    tabFrames[3] = vanillaContainer

    BuildInstanceTab(vanillaContainer, VANILLA_INSTANCE_DB, PANEL_W)

    -- ── Default to Settings tab ─────────────────────────────────────────────
    SelectTab(1)
end

panel:SetScript("OnShow", function(self) BuildPanel(self) end)

-- ─── Register ───────────────────────────────────────────────────────────────

local function RegisterPanel()
    if Settings and Settings.RegisterCanvasLayoutCategory then
        local category = Settings.RegisterCanvasLayoutCategory(panel, panel.name)
        Settings.RegisterAddOnCategory(category)
        panel._category = category
    elseif InterfaceOptions_AddCategory then
        InterfaceOptions_AddCategory(panel)
    end
end

local regFrame = CreateFrame("Frame")
regFrame:RegisterEvent("PLAYER_LOGIN")
regFrame:SetScript("OnEvent", function()
    Priestly_EnsureDefaults()
    RegisterPanel()
end)

function Priestly_OpenConfig()
    if Settings and Settings.OpenToCategory and panel._category then
        Settings.OpenToCategory(panel._category:GetID())
    elseif InterfaceOptionsFrame_OpenToCategory then
        InterfaceOptionsFrame_OpenToCategory(panel)
        InterfaceOptionsFrame_OpenToCategory(panel)
    end
end
