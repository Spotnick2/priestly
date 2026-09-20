------------------------------------------------------------
-- wow_stubs.lua
--
-- Minimal World of Warcraft: Forever API surface so Priestly's files can be
-- loaded and unit-tested under stock Lua 5.1 (the interpreter WoW uses), with
-- no game client.
--
-- Only what the addon touches at load time, plus the APIs the functions under
-- test call. Tests drive behaviour through the exported `WoW` table:
--
--     dofile("tests/wow_stubs.lua")     -- FIRST, in every test file
--     WoW.reset()
--     WoW.SetUnit("party1", { name = "Karuzo Elegia", class = "MAGE" })
--     WoW.SetAura("party1", "Power Word: Fortitude", 3600, 1200)
--
-- Frames record their secure attributes, so tests can assert what a click
-- would actually have cast.
------------------------------------------------------------

WoW = {}
local WoW = WoW

-- Event registrations are a load-time fact, not per-test state: the addon
-- registers once when its files load, so WoW.reset() must not wipe them or
-- WoW.dispatch would find nothing to fire at.
WoW.events = {}              -- [frame] = { [event] = true }

------------------------------------------------------------
-- State
------------------------------------------------------------

function WoW.reset()
    WoW.time        = 10000
    WoW.inCombat    = false
    WoW.secret      = false      -- C_Secrets.ShouldAurasBeSecret()
    WoW.build       = "69913"
    WoW.locale      = "enUS"
    WoW.units       = {}         -- [unit] = { name, guid, class, connected, dead, level }
    WoW.auras       = {}         -- [unit] = { auraData, ... }
    WoW.knownSpells = {}         -- [spellID] = true
    WoW.spells      = {}         -- [spellID] = { name, iconID }
    WoW.spellbook   = {}         -- { { name, subText }, ... }
    WoW.range       = {}         -- [unit] = true | false | nil
    WoW.inRaid      = false
    WoW.groupMembers = 0
    WoW.raidRoster  = {}         -- { { name, rank, subgroup }, ... }
    WoW.instanceName = ""
    WoW.instanceType = nil       -- nil = derive from instanceName
    WoW.itemCounts  = {}         -- [itemID] = count in bags
    WoW.messages    = {}         -- everything printed to DEFAULT_CHAT_FRAME
    WoW.badEvents   = {}         -- event names RegisterEvent should throw on
    WoW.timers      = {}
    WoW.mouseOver   = {}         -- [frame] = true; drives frame:IsMouseOver()
    WoW.byNameBlind = false      -- simulate GetAuraDataBySpellName not resolving
    WoW.auraReadsThrow = false   -- combat secrecy: index reads throw

    WoW.SetUnit("player", { name = "Priestly Testcase", class = "PRIEST", level = 20 })
end

function WoW.SetUnit(unit, info)
    info = info or {}
    WoW.units[unit] = {
        name      = info.name or unit,
        guid      = info.guid or ("GUID-" .. (info.name or unit)),
        class     = info.class or "PRIEST",
        connected = info.connected ~= false,
        dead      = info.dead or false,
        level     = info.level or 20,
    }
    return WoW.units[unit]
end

function WoW.RemoveUnit(unit)
    WoW.units[unit] = nil
    WoW.auras[unit] = nil
end

-- duration/remaining in seconds; remaining nil means "permanent" (exp 0).
function WoW.SetAura(unit, name, duration, remaining, spellID)
    local list = WoW.auras[unit]
    if not list then list = {} WoW.auras[unit] = list end
    list[#list + 1] = {
        name           = name,
        duration       = duration or 0,
        expirationTime = remaining and (WoW.time + remaining) or 0,
        spellId        = spellID,
        isHelpful      = true,
    }
end

-- An aura struct whose fields throw, the way a secret one does. The UNIT_AURA
-- payload carries these, so anything reading .name off it must be guarded.
function WoW.SecretAura()
    return setmetatable({}, {
        __index = function()
            error("Auras cannot be accessed when secret while tainted by 'Test'", 2)
        end,
    })
end

function WoW.ClearAuras(unit)
    WoW.auras[unit] = nil
end

function WoW.Know(spellID, name, subText)
    WoW.knownSpells[spellID] = true
    if name then
        WoW.spells[spellID] = { name = name, iconID = 100000 + spellID }
        WoW.spellbook[#WoW.spellbook + 1] = { name = name, subText = subText }
    end
end

-- Make a spell exist in the client's spell database without the player knowing
-- it (GetSpellInfo resolves, IsSpellKnown does not).
function WoW.DefineSpell(spellID, name)
    WoW.spells[spellID] = { name = name, iconID = 100000 + spellID }
end

function WoW.flushTimers()
    local pending = WoW.timers
    WoW.timers = {}
    for _, fn in ipairs(pending) do fn() end
end

------------------------------------------------------------
-- Frames
------------------------------------------------------------

local function makeFrame(name)
    local f = { _attr = {}, _scripts = {}, _name = name, _shown = false }
    local function chain() return f end

    f.GetName = function(self) return self._name end
    f.SetScript = function(self, ev, fn) self._scripts[ev] = fn return self end
    f.GetScript = function(self, ev) return self._scripts[ev] end
    f.HookScript = function(self, ev, fn) return self end
    f.SetAttribute = function(self, k, v) self._attr[k] = v return self end
    f.GetAttribute = function(self, k) return self._attr[k] end
    f.Show = function(self) self._shown = true return self end
    f.Hide = function(self) self._shown = false return self end
    f.IsShown = function(self) return self._shown end
    -- Predicates must be explicit: the catch-all __index below returns a
    -- function for any unknown method, and a function is truthy, so an
    -- undefined frame:IsFoo() would silently answer "yes" forever.
    f.IsMouseOver = function(self) return WoW.mouseOver[self] == true end
    f.SetClampedToScreen = function(self, v) self._clamped = v return self end
    f.IsVisible = function(self) return self._shown end
    f.IsMouseEnabled = function(self) return true end
    f.RegisterEvent = function(self, ev)
        if WoW.badEvents[ev] then error("unknown event " .. tostring(ev), 2) end
        local set = WoW.events[self]
        if not set then set = {} WoW.events[self] = set end
        set[ev] = true
        return self
    end
    f.UnregisterEvent = function(self, ev)
        local set = WoW.events[self]
        if set then set[ev] = nil end
        return self
    end
    f.CreateTexture    = function() return makeFrame() end
    f.CreateFontString = function() return makeFrame() end
    f.CreateAnimationGroup = function() return makeFrame() end
    f.GetThumbTexture  = function() return makeFrame() end
    f.GetPoint = function() return "CENTER", nil, "CENTER", 0, 0 end
    -- Set WoW.zeroHeights to model a FontString that has not been laid out
    -- yet, which is what the live client reports inside a scroll child during
    -- OnShow.
    f.GetStringHeight = function() return WoW.zeroHeights and 0 or 12 end
    f.GetWidth = function() return 100 end
    f.GetHeight = function() return 20 end
    f.GetChecked = function(self) return self._checked end
    f.SetChecked = function(self, v) self._checked = v return self end
    f.GetMinMaxValues = function() return 0, 1 end
    f.GetValue = function(self) return self._value or 0 end
    f.SetValue = function(self, v) self._value = v return self end
    f.GetID = function() return 1 end

    -- Anything else called as a method is a no-op returning the frame. But an
    -- underscore-prefixed key is one of the ADDON's own private fields, and the
    -- stub must not invent those: handing back a function makes every unset
    -- flag (`_combatHidden`, `_active`, `_category`) read as true, which is how
    -- a test can assert a state the addon is not actually in.
    setmetatable(f, {
        __index = function(_, k)
            if type(k) == "string" and k:sub(1, 1) == "_" then return nil end
            return chain
        end,
    })
    return f
end
WoW.makeFrame = makeFrame

-- Fire a registered event handler on one specific frame.
function WoW.fire(frame, event, ...)
    local fn = frame and frame._scripts and frame._scripts.OnEvent
    if fn then fn(frame, event, ...) end
end

-- Fire an event the way the game does: to EVERY frame registered for it. The
-- addon has three event frames (main, instance detector, options registration)
-- and firing only one leaves the others in a state the game never produces -
-- which looks like an addon bug when a test then trips over it.
function WoW.dispatch(event, ...)
    local targets = {}
    for frame, events in pairs(WoW.events) do
        if events[event] then targets[#targets + 1] = frame end
    end
    for _, frame in ipairs(targets) do
        WoW.fire(frame, event, ...)
    end
    return #targets
end

------------------------------------------------------------
-- Globals the addon expects at load
------------------------------------------------------------

-- What each template actually brings with it. Without this the catch-all
-- __index invents `rb.text` as a function, the options panel then calls
-- :SetText on it, and the panel can never be built under test - which is how
-- the whole options UI stayed outside the strict-global net.
local TEMPLATE_REGIONS = {
    UICheckButtonTemplate               = { "text" },
    InterfaceOptionsCheckButtonTemplate = { "Text" },
    UIRadioButtonTemplate               = { "text" },
    OptionsSliderTemplate               = { "Low", "High", "Text" },
    UISliderTemplateWithLabels          = { "Low", "High", "Text" },
    MinimalSliderTemplate               = { "Low", "High" },
    UIPanelButtonTemplate               = { "Text" },
    UIPanelScrollFrameTemplate          = { "ScrollBar" },
    ScrollFrameTemplate                 = { "ScrollBar" },
}

function CreateFrame(frameType, name, parent, template)
    local f = makeFrame(name)
    if name then _G[name] = f end
    f._type = frameType
    f._template = template
    local regions = template and TEMPLATE_REGIONS[template]
    if regions then
        for _, key in ipairs(regions) do
            f[key] = makeFrame(name and (name .. key) or nil)
        end
    end
    return f
end

UIParent = nil            -- assigned below, after CreateFrame exists
UNKNOWNOBJECT = "Unknown"
BOOKTYPE_SPELL = "spell"

RAID_CLASS_COLORS = setmetatable({}, {
    __index = function() return { r = 0.5, g = 0.5, b = 0.5 } end,
})

DEFAULT_CHAT_FRAME = {
    AddMessage = function(_, msg) WoW.messages[#WoW.messages + 1] = msg end,
}

GameTooltip = makeFrame("GameTooltip")
SlashCmdList = {}

-- Present on the live client, so the options panel's real registration and
-- OpenToCategory paths are the ones the tests exercise.
Settings = {
    RegisterCanvasLayoutCategory = function(frame, name)
        return { GetID = function() return 42 end, name = name }
    end,
    RegisterAddOnCategory = function() end,
    OpenToCategory = function(id) WoW.settingsOpenedTo = id end,
}

C_Timer = {
    After = function(_, fn) WoW.timers[#WoW.timers + 1] = fn end,
    NewTimer  = function() return { Cancel = function() end } end,
    NewTicker = function() return { Cancel = function() end } end,
}

Enum = { SpellBookSpellBank = { Player = 0, Pet = 1 } }

WOW_PROJECT_MAINLINE = 1
WOW_PROJECT_ID = 1

function GetTime() return WoW.time end
function GetLocale() return WoW.locale end
function GetBuildInfo() return "1.60.1", WoW.build, "Sep 17 2026", 16001 end
function InCombatLockdown() return WoW.inCombat end
-- NOT defined on purpose: MouseIsOver does not exist on this client. The stub
-- must model the client's absences, not just its presences - defining it here
-- is what let a call to it survive into a shipped build.
function strtrim(s) return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", "")) end
function date(fmt) return "2026-09-20 00:00:00" end

C_AddOns = {
    GetAddOnMetadata = function(_, key)
        if key == "Version" then return "2.0.0-test" end
        return nil
    end,
}

------------------------------------------------------------
-- Units
------------------------------------------------------------

local function unitInfo(unit) return unit and WoW.units[unit] or nil end

function UnitExists(unit) return unitInfo(unit) ~= nil end
function UnitIsConnected(unit)
    local u = unitInfo(unit)
    return u ~= nil and u.connected
end
function UnitIsDeadOrGhost(unit)
    local u = unitInfo(unit)
    return u ~= nil and u.dead
end
-- Measured on build 69913: UnitName returns the joined name only for the
-- player. For any other unit it returns the FIRST name, with the surname where
-- the realm normally sits. GetUnitName is the one that joins them for both.
function UnitName(unit)
    local u = unitInfo(unit)
    if not u then return nil end
    if unit == "player" then return u.name end
    local first, surname = u.name:match("^(%S+)%s+(%S+)$")
    if first then return first, surname end
    return u.name
end
function GetUnitName(unit, showServer)
    local u = unitInfo(unit)
    return u and u.name or nil
end
UnitFullName = UnitName
UnitNameUnmodified = UnitName
function UnitGUID(unit)
    local u = unitInfo(unit)
    return u and u.guid or nil
end
function UnitClass(unit)
    local u = unitInfo(unit)
    if not u then return nil, nil end
    return u.class, u.class
end
function UnitLevel(unit)
    local u = unitInfo(unit)
    return u and u.level or 1
end

function IsInRaid() return WoW.inRaid end
function GetNumGroupMembers() return WoW.groupMembers end
function GetRaidRosterInfo(i)
    local e = WoW.raidRoster[i]
    if not e then return nil end
    return e.name, e.rank or 0, e.subgroup or 1
end
function GetInstanceInfo()
    -- Outdoors the live client returns the continent name with instanceType
    -- "none" - it does not return an empty name.
    local t = WoW.instanceType
    if not t then t = (WoW.instanceName == "" and "none") or "party" end
    return WoW.instanceName, t, 0, "", 5, 0, false, 0, 0
end
function GetRealZoneText() return WoW.instanceName end

------------------------------------------------------------
-- C_UnitAuras
------------------------------------------------------------

-- Measured on build 69913: once combat taints an addon, EVERY aura read
-- throws ("Auras cannot be accessed when secret while tainted by '<addon>'")
-- for every unit - while GetAuraDataBySpellName merely returns nil, which
-- looks exactly like "not buffed".
local function liveAuras(unit)
    if WoW.auraReadsThrow then
        error("Auras cannot be accessed when secret while tainted by 'Test'", 2)
    end
    local list = WoW.auras[unit]
    if not list then return nil end
    local out = {}
    for _, aura in ipairs(list) do
        if aura.expirationTime == 0 or aura.expirationTime > WoW.time then
            out[#out + 1] = aura
        end
    end
    return out
end

C_UnitAuras = {
    GetAuraDataByIndex = function(unit, index, filter)
        local list = liveAuras(unit)
        return list and list[index] or nil
    end,
    GetBuffDataByIndex = function(unit, index)
        local list = liveAuras(unit)
        return list and list[index] or nil
    end,
    GetAuraDataBySpellName = function(unit, name, filter)
        -- Set WoW.byNameBlind = true to simulate the by-name lookup failing to
        -- resolve a spell the player does not know, which is the reason
        -- API.GetBuff never trusts a by-name miss.
        if WoW.byNameBlind then return nil end
        -- Under secrecy this one returns nil rather than throwing.
        if WoW.auraReadsThrow then return nil end
        local list = WoW.auras[unit]
        if not list then return nil end
        for _, aura in ipairs(list) do
            if aura.name == name
                and (aura.expirationTime == 0 or aura.expirationTime > WoW.time) then
                return aura
            end
        end
        return nil
    end,
}

C_Secrets = {
    ShouldAurasBeSecret = function() return WoW.secret end,
    GetSpellAuraSecrecy = function() return false end,
}

------------------------------------------------------------
-- C_Spell / C_SpellBook
------------------------------------------------------------

local function findSpell(spell)
    if type(spell) == "number" then return WoW.spells[spell], spell end
    for id, info in pairs(WoW.spells) do
        if info.name == spell then return info, id end
    end
    return nil, nil
end

C_Spell = {
    -- Measured on build 69913: by ID this resolves any spell in the client's
    -- database; by NAME it resolves only spells the player knows. Resolving a
    -- name for an unlearned spell must therefore fail here too, or the tests
    -- would bless a lookup direction the live client rejects.
    GetSpellInfo = function(spell)
        local info, id = findSpell(spell)
        if not info then return nil end
        if type(spell) ~= "number" and not WoW.knownSpells[id] then return nil end
        return { name = info.name, iconID = info.iconID, castTime = 0 }
    end,
    GetSpellTexture = function(spell)
        local info, id = findSpell(spell)
        if not info then return nil end
        if type(spell) ~= "number" and not WoW.knownSpells[id] then return nil end
        return info.iconID
    end,
    IsSpellInRange = function(spell, unit)
        -- The live API answers nil for a spell the player does not know, the
        -- same as for a missing unit.
        local info, id = findSpell(spell)
        if not info or not WoW.knownSpells[id] then return nil end
        -- WoW.range[unit] is a boolean, or a table keyed by spell name when a
        -- test needs the spells to differ - the Prayers reach 40 yards where
        -- the single-target forms reach 30.
        local r = WoW.range[unit]
        if type(r) == "table" then return r[info.name] end
        return r
    end,
    SpellHasRange = function() return true end,
}

C_SpellBook = {
    IsSpellKnown = function(spellID) return WoW.knownSpells[spellID] == true end,
    IsSpellInSpellBook = function(spellID) return WoW.knownSpells[spellID] == true end,
    IsSpellKnownOrInSpellBook = function(spellID) return WoW.knownSpells[spellID] == true end,
    GetNumSpellBookSkillLines = function() return 1 end,
    GetSpellBookSkillLineInfo = function() return { name = "General", itemIndexOffset = 0,
        numSpellBookItems = #WoW.spellbook } end,
    GetSpellBookItemName = function(index)
        local e = WoW.spellbook[index]
        if not e then return nil end
        return e.name, e.subText
    end,
}

------------------------------------------------------------
-- Items / containers
------------------------------------------------------------

C_Item = {
    GetItemIconByID = function(itemID) return "icon:" .. tostring(itemID) end,
    GetItemInfo = function(itemID)
        return "Item " .. tostring(itemID), "link", 1, 1, 1, "", "", 20, "",
            "icon:" .. tostring(itemID)
    end,
    GetItemCount = function(itemID) return WoW.itemCounts[itemID] or 0 end,
}

C_Container = {
    GetContainerNumSlots = function(bag) return bag == 0 and 16 or 0 end,
    GetContainerItemInfo = function(bag, slot)
        if bag ~= 0 then return nil end
        local i = 0
        for itemID, count in pairs(WoW.itemCounts) do
            i = i + 1
            if i == slot then
                return { itemID = itemID, stackCount = count }
            end
        end
        return nil
    end,
}

------------------------------------------------------------

UIParent = makeFrame("UIParent")

------------------------------------------------------------
-- Strict globals
--
-- Everything above is stubbed because it was *verified present* on the live
-- client (see docs/FOREVER-PROBE.md). So any global the addon reads that is
-- not stubbed is either a genuine typo or - the interesting case - an API that
-- quietly went away in the move to the Retail codebase. `MouseIsOver` was
-- exactly that: still called, nil on this client, and it only surfaced as a
-- Lua error on mouseover in game.
--
-- Reading an unstubbed global now fails the test run. To add one: confirm it
-- exists with Tools/PriestlyProbe and stub it, or list it here as deliberately
-- absent.
------------------------------------------------------------

local KNOWN_ABSENT = {
    -- Gone on this client; the addon may probe for them but must not depend
    -- on them.
    MouseIsOver = true, UnitBuff = true, UnitDebuff = true,
    GetSpellInfo = true, GetSpellTexture = true, IsSpellInRange = true,
    GetItemIcon = true, GetItemInfo = true, GetItemCount = true,
    GetNumSpellTabs = true, GetSpellTabInfo = true, GetSpellBookItemName = true,
    GetNumTalentTabs = true, GetTalentTabInfo = true, IsSpellKnown = true,
    GetAddOnMetadata = true, InterfaceOptions_AddCategory = true,
    InterfaceOptionsFrame_OpenToCategory = true,
    loadstring_untainted = true, SecureHandlerWrapScript = true,
    -- Addon-owned globals that legitimately start out nil.
    PriestlyDB = true, PriestlyProbeDB = true,
    Priestly_ScheduleRefresh = true, Priestly_ForceRebuild = true,
    Priestly_ApplyAlpha = true, Priestly_OnSoloToggle = true,
    Priestly_LearnDuration = true, Priestly_GetLearnedDuration = true,
    Priestly_EnsureDefaults = true, Priestly_ShowSolo = true,
    Priestly_TrackPets = true, Priestly_IsBuffEnabled = true,
    Priestly_ShouldShowShadow = true, Priestly_GetFrameAlpha = true,
    Priestly_OpenConfig = true, Priestly = true,
    -- Lua/runtime names the test files themselves touch.
    arg = true, jit = true,
}

function WoW.strictGlobals()
    setmetatable(_G, {
        __index = function(_, k)
            if KNOWN_ABSENT[k] then return nil end
            error("read of undefined global '" .. tostring(k) ..
                "' - stub it (only if the probe confirms it exists) or add it to " ..
                "KNOWN_ABSENT in tests/wow_stubs.lua", 2)
        end,
    })
end

function WoW.allowGlobal(name) KNOWN_ABSENT[name] = true end

WoW.reset()
WoW.strictGlobals()
