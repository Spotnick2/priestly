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
    WoW.itemCounts  = {}         -- [itemID] = count, treated as sitting in bag 0
    WoW.itemsUncached = {}       -- [itemID] = true -> GetItemInfo returns nothing
    WoW.itemsRequested = {}      -- [itemID] = true once the addon asked for it
    WoW.bags        = {}         -- [bagID] = { {itemID=, stackCount=}, ... }
    WoW.messages    = {}         -- everything printed to DEFAULT_CHAT_FRAME
    WoW.badEvents   = {}         -- event names RegisterEvent should throw on
    WoW.refusedEvents = {}       -- event names RegisterEvent should return false for
    WoW.timers      = {}
    WoW.mouseOver   = {}         -- [frame] = true; drives frame:IsMouseOver()
    WoW.centers     = {}         -- [frame] = x; drives frame:GetCenter()
    WoW.screenWidth = 1920       -- what UIParent:GetWidth() reports
    WoW.ejNumTiers  = 0          -- what this client actually reports
    WoW.ejSelectThrows = false
    WoW.ejDungeons  = {}         -- { { id =, name = }, ... }
    WoW.ejRaids     = {}
    WoW.byNameBlind = false      -- simulate GetAuraDataBySpellName not resolving
    WoW.auraReadsThrow = false   -- combat secrecy: index reads throw
    WoW.aurasAreSecret = false   -- combat secrecy: the struct's fields throw

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

-- A UNIT_AURA payload whose fields are secret values. Measured on the live
-- client, `isFullUpdate` comes back as a <secret boolean> and
-- `updatedAuraInstanceIDs` as a <secret table>, and on this client a secret
-- value throws when it is TRUTH-TESTED, not only when it is read. Lua has no
-- way to make a boolean throw on `if x then`, so the closest model is a field
-- access that raises - which exercises the same guard.
function WoW.SecretUpdateInfo()
    return setmetatable({}, {
        __index = function(_, k)
            error("attempt to perform boolean test on field '" .. tostring(k)
                .. "' (a secret boolean value, while execution tainted by 'Test')", 2)
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

-- Run pending C_Timer callbacks.
--
-- With `advance`, move the clock forward by that many seconds and run only
-- what comes due, oldest first - which is how a test says "this much time
-- passed", catches a callback that fires too early, and lets a timer from an
-- earlier action still be pending while a later one is measured. Without it,
-- everything runs, which is what most tests want.
function WoW.flushTimers(advance)
    local target = advance and (WoW.time + advance) or nil
    local pending = WoW.timers
    WoW.timers = {}

    if not target then
        for _, t in ipairs(pending) do t.fn() end
        return
    end

    table.sort(pending, function(a, b) return a.at < b.at end)
    for _, t in ipairs(pending) do
        if t.at <= target then
            WoW.time = t.at          -- callbacks see the time they ran at
            t.fn()
        else
            WoW.timers[#WoW.timers + 1] = t
        end
    end
    WoW.time = target
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
    f.HookScript = function(self, ev, fn)
        local existing = self._scripts[ev]
        if existing then
            self._scripts[ev] = function(...) existing(...) fn(...) end
        else
            self._scripts[ev] = fn
        end
        return self
    end
    f.RegisterForClicks = function(self, ...) self._clicks = { ... } return self end
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
    f.StartMoving = function(self) self._moving = true return self end
    f.StopMovingOrSizing = function(self) self._moving = false return self end
    f.IsVisible = function(self) return self._shown end
    f.IsMouseEnabled = function(self) return true end
    -- The client declares `RegisterEvent(eventName:cstring) -> registered:bool`
    -- and throws on a name it does not know. WoW.badEvents models the throw,
    -- WoW.refusedEvents a refusal by return value.
    f.RegisterEvent = function(self, ev)
        if type(ev) ~= "string" then error("bad argument #1 to 'RegisterEvent'", 2) end
        if WoW.badEvents[ev] then error("unknown event " .. tostring(ev), 2) end
        if WoW.refusedEvents[ev] then return false end
        local set = WoW.events[self]
        if not set then set = {} WoW.events[self] = set end
        set[ev] = true
        return true
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
    f.SetPoint = function(self, point, rel, relPoint, x, y)
        -- SetPoint(point, x, y) is the short form, and a number in the second
        -- slot is the only thing that distinguishes it from
        -- SetPoint(point, relativeTo, relativePoint). Slot it wrongly and an
        -- offset is recorded as a relative frame.
        if type(rel) == "number" then
            rel, relPoint, x, y = nil, nil, rel, relPoint
        end
        self._points = self._points or {}
        self._points[#self._points + 1] = { point, rel, relPoint, x, y }
        return self
    end
    f.ClearAllPoints = function(self) self._points = nil return self end
    -- Reports what was actually set, so a test can assert where a frame went.
    -- The FIRST anchor, which is what the client's GetPoint() returns - it is
    -- GetPoint(1), not "the most recent one".
    f.GetPoint = function(self)
        local p = self._points and self._points[1]
        if not p then return "CENTER", nil, "CENTER", 0, 0 end
        return p[1], p[2], p[3], p[4], p[5]
    end
    -- Set WoW.zeroHeights to model a FontString that has not been laid out
    -- yet, which is what the live client reports inside a scroll child during
    -- OnShow.
    f.GetStringHeight = function() return WoW.zeroHeights and 0 or 12 end
    f.GetWidth = function(self) return self == UIParent and WoW.screenWidth or 100 end
    -- nil until a test places the frame, which is what the live client returns
    -- before layout - a case the caller has to handle.
    f.GetCenter = function(self)
        local x = WoW.centers[self]
        if not x then return nil end
        return x, 300
    end
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

-- Records what was put in it, so a test can assert what the player is told.
-- Falling through to the catch-all no-op meant tooltip text was invisible to
-- the suite - it could be wrong, or absent, and nothing would notice.
GameTooltip = makeFrame("GameTooltip")
GameTooltip.SetOwner = function(self, owner, anchor)
    self._owner, self._anchor, self._lines = owner, anchor, {}
    return self
end
GameTooltip.SetText = function(self, text)
    self._lines = { text }
    return self
end
GameTooltip.AddLine = function(self, text)
    self._lines = self._lines or {}
    self._lines[#self._lines + 1] = text
    return self
end
GameTooltip.AddDoubleLine = function(self, left, right)
    return GameTooltip.AddLine(self, tostring(left) .. "  " .. tostring(right))
end
function WoW.clearTooltip()
    GameTooltip:Hide()
    GameTooltip._lines = nil
end

-- Everything the tooltip is showing, colour codes stripped.
function WoW.tooltipText()
    if not GameTooltip:IsShown() then return "" end
    local joined = table.concat(GameTooltip._lines or {}, " / ")
    return (joined:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
end
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
    -- Scheduled against the virtual clock, not by raw delay: two callbacks can
    -- share a delay and still come due at different moments, which is the only
    -- way to model a timer left over from an earlier action.
    After = function(delay, fn)
        WoW.timers[#WoW.timers + 1] = { at = WoW.time + (tonumber(delay) or 0), fn = fn }
    end,
    NewTimer  = function() return { Cancel = function() end } end,
    NewTicker = function() return { Cancel = function() end } end,
}

Enum = {
    SpellBookSpellBank = { Player = 0, Pet = 1 },
    -- The reagent bag sits past the ordinary 0..NUM_BAG_SLOTS range.
    BagIndex = { Backpack = 0, ReagentBag = 5 },
}

WOW_PROJECT_MAINLINE = 1
WOW_PROJECT_ID = 1
NUM_BAG_SLOTS = 4                -- measured on this client

function GetTime() return WoW.time end
function GetLocale() return WoW.locale end
function GetBuildInfo() return "1.60.1", WoW.build, "Sep 17 2026", 16001 end
function InCombatLockdown() return WoW.inCombat end
-- NOT defined on purpose: MouseIsOver does not exist on this client. The stub
-- must model the client's absences, not just its presences - defining it here
-- is what let a call to it survive into a shipped build.
function strtrim(s) return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", "")) end
-- A string.match alias the client defines. LibStub.lua uses it; confirmed in
-- the global-functions section of the API dump. The alias itself, so the
-- optional `init` argument behaves as it does on the client.
strmatch = string.match

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
        local aura = list and list[index] or nil
        if aura and WoW.aurasAreSecret then return WoW.SecretAura() end
        return aura
    end,
    GetBuffDataByIndex = function(unit, index)
        local list = liveAuras(unit)
        local aura = list and list[index] or nil
        if aura and WoW.aurasAreSecret then return WoW.SecretAura() end
        return aura
    end,
    -- Set WoW.aurasAreSecret to hand back aura structs whose fields throw,
    -- rather than throwing from the getter itself - the other shape secrecy
    -- can take.
    GetAuraDataBySpellName = function(unit, name, filter)
        -- Set WoW.byNameBlind = true to simulate the by-name lookup failing to
        -- resolve a spell the player does not know, which is the reason
        -- API.ReadBuff never trusts a by-name miss.
        if WoW.byNameBlind then return nil end
        -- Under secrecy this one returns nil rather than throwing.
        if WoW.auraReadsThrow then return nil end
        local list = WoW.auras[unit]
        if not list then return nil end
        for _, aura in ipairs(list) do
            if aura.name == name
                and (aura.expirationTime == 0 or aura.expirationTime > WoW.time) then
                if WoW.aurasAreSecret then return WoW.SecretAura() end
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

-- Bag 0 holds whatever WoW.itemCounts names; WoW.bags places items in a
-- specific bag. Forever's carried inventory includes the reagent bag at
-- Enum.BagIndex.ReagentBag, which is outside the 0..NUM_BAG_SLOTS range.
local function bagContents(bag)
    if bag == 0 then
        local out = {}
        for itemID, count in pairs(WoW.itemCounts) do
            out[#out + 1] = { itemID = itemID, stackCount = count }
        end
        for _, entry in ipairs(WoW.bags[0] or {}) do out[#out + 1] = entry end
        return out
    end
    return WoW.bags[bag] or {}
end

local function carriedBags()
    local ids = { 0, 1, 2, 3, 4, 5 }
    return ids
end

C_Item = {
    GetItemIconByID = function(itemID) return "icon:" .. tostring(itemID) end,
    -- Returns NOTHING on a cache miss, not nil - the live behaviour, and the
    -- reason API.ItemInfo checks the cache first instead of trusting a nil.
    GetItemInfo = function(itemID)
        if WoW.itemsUncached[itemID] then return end
        return "Item " .. tostring(itemID), "link", 3, 1, 1, "", "", 20, "",
            "icon:" .. tostring(itemID)
    end,
    IsItemDataCachedByID = function(itemID) return not WoW.itemsUncached[itemID] end,
    RequestLoadItemDataByID = function(itemID) WoW.itemsRequested[itemID] = true end,
    GetItemQualityColor = function(quality)
        return 0.1 * quality, 0.2, 0.3, "quality" .. tostring(quality)
    end,
    -- The live API answers for the whole carried inventory, reagent bag
    -- included.
    GetItemCount = function(itemID)
        local total = 0
        for _, bag in ipairs(carriedBags()) do
            for _, entry in ipairs(bagContents(bag)) do
                if entry.itemID == itemID then total = total + (entry.stackCount or 0) end
            end
        end
        return total
    end,
}

C_Container = {
    GetContainerNumSlots = function(bag)
        return #bagContents(bag) > 0 and 16 or 0
    end,
    GetContainerItemInfo = function(bag, slot)
        return bagContents(bag)[slot]
    end,
}

------------------------------------------------------------

-- Encounter journal. Measured on build 69913: EJ_GetNumTiers returns 0 while
-- EJ_GetInstanceByIndex works, which is the case the probe has to survive.
WoW = WoW or {}
function EJ_GetNumTiers() return WoW.ejNumTiers or 0 end
function EJ_SelectTier(tier)
    if WoW.ejSelectThrows then error("EJ_SelectTier is not available", 2) end
    WoW.ejSelectedTier = tier
end
function EJ_GetTierInfo(tier) return "Tier " .. tostring(tier) end
function EJ_GetInstanceByIndex(index, isRaid)
    local list = (isRaid and WoW.ejRaids) or WoW.ejDungeons
    local entry = list and list[index]
    if not entry then return nil end
    return entry.id, entry.name
end

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
    -- The probe records whether these exist; the addon no longer needs them,
    -- because the secure handler does the keydown/keyup gating itself.
    C_CVar = true, GetCVarBool = true, GetCVar = true,
    SetCVar = true, RegisterCVar = true, GetCVarInfo = true,
    -- Globals the probe deliberately tests for the presence of.
    C_EncounterJournal = true, EJ_GetNumTiers = true, EJ_SelectTier = true,
    EJ_GetTierInfo = true, EJ_GetInstanceByIndex = true,
    -- The probe's own saved variables, which start nil like any others.
    PriestlyProbePersist = true, PriestlyProbeChar = true,
    PriestlyProbeCopyFrame = true, PriestlyProbeBench = true,
    PriestlyProbeBenchA = true, PriestlyProbeBenchB = true,
    PriestlyProbeBenchC = true,
    -- Addon-owned globals that legitimately start out nil.
    PriestlyDB = true, PriestlyProbeDB = true, PriestlySVCheck = true,
    -- LibStub.lua looks itself up before it exists.
    LibStub = true,
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
