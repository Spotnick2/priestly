-- ============================================================================
-- PriestlyCompat.lua  -  the WoW: Forever (1.60.1) API surface, in one place.
--
-- Forever is Vanilla content running on the Retail/Mainline codebase, so the
-- APIs Priestly grew up on (UnitBuff, GetSpellInfo, the spell-tab walk,
-- GetItemIcon) are gone. Adapters live here, in our own namespace - never as
-- injected globals, which would change capability detection for every other
-- addon and make us load-order dependent.
--
-- Consuming files take file-local aliases at the top so their call sites stay
-- as they were:
--     local API = Priestly.API
--
-- Only the contracts Priestly actually consumes are implemented. This is not a
-- historical-API emulator.
-- ============================================================================

Priestly = Priestly or {}

local API = {}
Priestly.API = API

local floor, max, huge = math.floor, math.max, math.huge

-- ─── events ──────────────────────────────────────────────────────────────────
-- Unknown event names THROW on RegisterEvent on this client, so registration is
-- guarded. Failures are recorded and printed - a silently missing handler is
-- worse than a noisy one.

-- Kept for diagnosis (`/dump Priestly.API.eventFailures`) rather than consumed
-- by the addon: the failure itself is reported in chat when it happens.
API.eventFailures = {}

function API.RegisterEvents(frame, ...)
    local failed
    for i = 1, select("#", ...) do
        local ev = select(i, ...)
        local ok, err = pcall(frame.RegisterEvent, frame, ev)
        if not ok then
            API.eventFailures[ev] = tostring(err)
            failed = failed and (failed .. ", " .. ev) or ev
        end
    end
    if failed and DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage(
            "|cff99ddff[Priestly]|r |cffff6666unsupported events skipped:|r " .. failed)
    end
    return failed == nil
end

-- ─── auras ───────────────────────────────────────────────────────────────────
-- UnitBuff / UnitDebuff / AuraUtil are gone; C_UnitAuras returns a struct.
-- Player auras are additionally unreadable while tainted in combat, which the
-- caller handles through a cache - here we only report the condition.

local C_UnitAuras = C_UnitAuras
local C_Secrets = C_Secrets

function API.AurasAreSecret()
    if C_Secrets and C_Secrets.ShouldAurasBeSecret then
        local ok, secret = pcall(C_Secrets.ShouldAurasBeSecret)
        return ok and secret or false
    end
    return false
end

-- Read one aura and match it against `names`, with every single touch of the
-- returned data inside the pcall.
--
-- That is stronger than it looks. On this client a secret value throws not
-- only when a field is read off it but when it is *compared* or even
-- truth-tested: `if aura then` on a secret table, or `nm == name` on a secret
-- string, raises exactly like a field access. Guarding only the read - which is
-- what an earlier version of this file did - leaves the test one line later
-- unprotected.
--
-- Returns one of:
--   "HIT", remaining, duration, expirationTime, matchedName
--   "MISS"     - an aura is there, but not one of ours
--   "EMPTY"    - no aura in that slot, so the walk can stop
--   "BLOCKED"  - the client would not let us look
local function matchAura(getter, names, ...)
    local packed = { pcall(function(...)
        local aura = getter(...)
        if not aura then return "EMPTY" end

        local nm = aura.name
        local matched
        for j = 1, #names do
            if names[j] and nm == names[j] then
                matched = names[j]
                break
            end
        end
        if not matched then return "MISS" end

        local dur = aura.duration or 0
        local exp = aura.expirationTime or 0
        local remaining
        if exp == 0 then
            remaining = huge          -- permanent, not expired
        else
            remaining = max(0, exp - GetTime())
        end
        return "HIT", remaining, dur, exp, matched
    end, ...) }

    if not packed[1] then return "BLOCKED" end
    return packed[2], packed[3], packed[4], packed[5], packed[6]
end

-- Returns status, remaining, duration, expirationTime.
--
--   "HAS"     - the unit has one of `names`
--   "NONE"    - the unit demonstrably does not
--   "BLOCKED" - the client would not let us look
--
-- `names` is a list of localized spell names: the single and group forms of one
-- buff apply the same tracked aura under two different names.
--
-- BLOCKED is deliberately distinct from NONE. Auras are secret while tainted in
-- combat on this client, and reporting "not buffed" because we were not allowed
-- to look sends you casting for no reason. Note that we *attempt* the read
-- either way rather than refusing whenever ShouldAurasBeSecret() is true: if
-- the restriction turns out not to cover party and raid helpful auras, we keep
-- live data instead of coasting on a cache.
function API.ReadBuff(unit, names)
    if not unit or not UnitExists(unit) then return "NONE" end
    if not C_UnitAuras then return "BLOCKED" end

    local fastPathBlocked = false

    -- Fast path: ask by name rather than walking every aura.
    if C_UnitAuras.GetAuraDataBySpellName then
        for i = 1, #names do
            if names[i] then
                local st, rem, dur, exp, matched = matchAura(
                    C_UnitAuras.GetAuraDataBySpellName, names, unit, names[i], "HELPFUL")
                if st == "HIT" then return "HAS", rem, dur, exp, matched end
                if st == "BLOCKED" then fastPathBlocked = true end
            end
        end
    end

    -- A by-name miss is NOT trusted as "not buffed". C_Spell.GetSpellInfo(name)
    -- only resolves spells the player knows on this client, and if the by-name
    -- aura lookup shares that resolution then a priest who has not learned
    -- Prayer of Fortitude would never see it on people another priest buffed.
    -- So confirm an absence by walking. The walk stops at the first empty slot,
    -- so it costs roughly "number of buffs on that unit" iterations.
    local byIndex = C_UnitAuras.GetAuraDataByIndex or C_UnitAuras.GetBuffDataByIndex
    if not byIndex then return "BLOCKED" end

    local sawAny, walkBlocked = false, false
    for i = 1, 40 do
        local st, rem, dur, exp, matched = matchAura(byIndex, names, unit, i, "HELPFUL")
        if st == "BLOCKED" then
            walkBlocked = true
            break
        end
        if st == "EMPTY" then break end
        sawAny = true
        if st == "HIT" then return "HAS", rem, dur, exp, matched end
    end

    -- Only the WALK decides absence. A throw from the fast path says nothing
    -- about the unit if the walk then completed and proved the buff is not
    -- there - latching that flag would pin the member on "unknown" forever.
    if walkBlocked then return "BLOCKED" end
    if fastPathBlocked and not sawAny then return "BLOCKED" end
    -- Secrecy may hide auras by handing back an empty list rather than
    -- throwing. Seeing nothing at all while it is active is not evidence of
    -- being unbuffed.
    if not sawAny and API.AurasAreSecret() then return "BLOCKED" end
    return "NONE"
end

-- ─── spells ──────────────────────────────────────────────────────────────────
-- GetSpellInfo returned a tuple; C_Spell.GetSpellInfo returns a struct.

local C_Spell = C_Spell

local function spellInfo(spell)
    if not spell or not C_Spell or not C_Spell.GetSpellInfo then return nil end
    local ok, info = pcall(C_Spell.GetSpellInfo, spell)
    if ok then return info end
    return nil
end
API.SpellInfo = spellInfo

-- Localized name for a spell ID, or nil if the client does not know that spell
-- at all (the Prayer ranks may simply not exist in this version).
function API.SpellName(spellID)
    local info = spellInfo(spellID)
    return info and info.name or nil
end

function API.SpellIcon(spell, fallback)
    local info = spellInfo(spell)
    if info and info.iconID then return info.iconID end
    if C_Spell and C_Spell.GetSpellTexture then
        local ok, tex = pcall(C_Spell.GetSpellTexture, spell)
        if ok and tex then return tex end
    end
    return fallback or ""
end

-- IsSpellInRange used to return 1 / 0 / nil. C_Spell.IsSpellInRange returns
-- true / false / nil, and `0` is truthy in Lua - a mechanical port of the old
-- `if r == 1` / `elseif r == 0` ladder silently reports everything as unknown.
-- Tri-state string keeps the call sites honest.
function API.SpellRange(unit, spell)
    if not unit or not UnitExists(unit) then return "UNKNOWN" end
    if not UnitIsConnected(unit) then return "OFFLINE" end
    if not spell then return "UNKNOWN" end

    local r
    if C_Spell and C_Spell.IsSpellInRange then
        local ok, res = pcall(C_Spell.IsSpellInRange, spell, unit)
        if ok then r = res end
    end
    if r == nil then return "UNKNOWN" end
    if r == true or r == 1 then return "IN_RANGE" end
    return "OUT_RANGE"
end

-- ─── spellbook ───────────────────────────────────────────────────────────────
-- GetNumSpellTabs / GetSpellTabInfo / GetSpellBookItemName(BOOKTYPE_SPELL) are
-- gone. C_SpellBook answers by spell ID; the by-name walk is kept only for the
-- rank subtext, which nothing else exposes.

local C_SpellBook = C_SpellBook
local BANK = Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player

-- Accepts a spell ID (preferred - locale proof) or a localized name.
function API.KnowsSpell(spell)
    if not spell then return false end

    if type(spell) == "number" and C_SpellBook then
        if C_SpellBook.IsSpellKnown then
            local ok, known = pcall(C_SpellBook.IsSpellKnown, spell, BANK)
            if ok and known then return true end
        end
        if C_SpellBook.IsSpellInSpellBook then
            local ok, inBook = pcall(C_SpellBook.IsSpellInSpellBook, spell, BANK, false)
            if ok and inBook then return true end
        end
        if C_SpellBook.IsSpellKnownOrInSpellBook then
            local ok, known = pcall(C_SpellBook.IsSpellKnownOrInSpellBook, spell)
            if ok and known then return true end
        end
        return false
    end

    -- Name form: walk the book. Used for spells we have no ID for.
    if C_SpellBook and C_SpellBook.GetSpellBookItemName then
        local found = false
        pcall(function()
            for i = 1, 300 do
                local nm = C_SpellBook.GetSpellBookItemName(i, BANK)
                if not nm then break end
                if nm == spell then found = true return end
            end
        end)
        return found
    end
    return false
end

-- Highest known rank of a spell, parsed out of the spellbook subtext
-- ("Rank 3"). Returns 0 when the spell is unknown, and 1 when it is known but
-- this client does not expose ranks at all.
function API.GetSpellRank(spellName)
    if not spellName then return 0 end
    if not (C_SpellBook and C_SpellBook.GetSpellBookItemName) then
        return API.KnowsSpell(spellName) and 1 or 0
    end
    local rank = 0
    pcall(function()
        for i = 1, 300 do
            local nm, sub = C_SpellBook.GetSpellBookItemName(i, BANK)
            if not nm then break end
            if nm == spellName then
                local r = sub and tonumber(tostring(sub):match("(%d+)")) or 1
                if r > rank then rank = r end
            end
        end
    end)
    return rank
end

-- ─── items ───────────────────────────────────────────────────────────────────
-- C_Item.GetItemIcon is a FALSE FRIEND: it takes an ItemLocation. The by-ID
-- form is GetItemIconByID.

local C_Item = C_Item
local QUESTION_MARK = "Interface\\Icons\\INV_Misc_QuestionMark"

function API.ItemIcon(itemID)
    if not itemID then return QUESTION_MARK end
    if C_Item and C_Item.GetItemIconByID then
        local ok, icon = pcall(C_Item.GetItemIconByID, itemID)
        if ok and icon then return icon end
    end
    if C_Item and C_Item.GetItemInfo then
        local ok, _, _, _, _, _, _, _, _, _, icon = pcall(C_Item.GetItemInfo, itemID)
        if ok and icon then return icon end
    end
    return QUESTION_MARK
end

-- ─── mouse ───────────────────────────────────────────────────────────────────
-- The MouseIsOver(frame) global is gone here. Every frame carries an
-- :IsMouseOver() method, which is what it wrapped anyway.

function API.IsMouseOver(frame)
    if not frame then return false end
    if frame.IsMouseOver then
        local ok, over = pcall(frame.IsMouseOver, frame)
        if ok then return over and true or false end
    end
    if MouseIsOver then
        local ok, over = pcall(MouseIsOver, frame)
        if ok then return over and true or false end
    end
    return false
end

-- ─── unit identity and names ─────────────────────────────────────────────────
-- Forever characters have a SURNAME, and first names are not unique: two
-- characters called Karuzo can be in the same raid. Key on GUID; display the
-- full Name-Surname. Never split a name on "-" to strip a realm - on this
-- client that eats the surname.

-- Stable identity for caching. Falls back to the unit token only when the GUID
-- is unavailable (which would make the cache entry short-lived, not wrong).
function API.UnitKey(unit)
    if not unit then return nil end
    local ok, guid = pcall(UnitGUID, unit)
    if ok and guid then return guid end
    return unit
end

-- Full display name including the surname. `fallback` is used when the unit is
-- gone (e.g. a raid roster name we already have in hand).
function API.UnitDisplayName(unit, fallback)
    if unit then
        if GetUnitName then
            local ok, nm = pcall(GetUnitName, unit, false)
            if ok and nm and nm ~= "" and nm ~= UNKNOWNOBJECT then return nm end
        end
        local ok, nm = pcall(UnitName, unit)
        if ok and nm and nm ~= "" and nm ~= UNKNOWNOBJECT then return nm end
    end
    return fallback or "?"
end

-- ─── containers ──────────────────────────────────────────────────────────────
-- GetContainerNumSlots / GetContainerItemInfo moved to C_Container, and the
-- latter returns a struct rather than positional values.

local C_Container = C_Container

-- How many of `itemID` the player is carrying.
--
-- C_Item.GetItemCount answers for the whole carried inventory in one call,
-- which is both cheaper than walking every slot and free of any assumption
-- about which bag ids exist. The bag walk is only a fallback, and it has to
-- include the reagent bag: that sits outside the 0..NUM_BAG_SLOTS range, so a
-- hardcoded `0, 4` silently reports zero for anything stored there.
function API.CountItem(itemID)
    if not itemID then return 0 end

    if C_Item and C_Item.GetItemCount then
        local ok, count = pcall(C_Item.GetItemCount, itemID)
        if ok and count then return count end
    end

    if not C_Container then return 0 end

    local bags = {}
    for bag = 0, (NUM_BAG_SLOTS or 4) do bags[#bags + 1] = bag end
    local reagentBag = Enum and Enum.BagIndex and Enum.BagIndex.ReagentBag
    if reagentBag then bags[#bags + 1] = reagentBag end

    local total = 0
    for _, bag in ipairs(bags) do
        local ok, slots = pcall(C_Container.GetContainerNumSlots, bag)
        if ok and slots then
            for slot = 1, slots do
                local gotInfo, info = pcall(C_Container.GetContainerItemInfo, bag, slot)
                if gotInfo and info and info.itemID == itemID then
                    total = total + (info.stackCount or 0)
                end
            end
        end
    end
    return total
end

-- ─── addon metadata ──────────────────────────────────────────────────────────
-- GetAddOnMetadata moved to C_AddOns.

function API.AddonVersion(addonName)
    local get = C_AddOns and C_AddOns.GetAddOnMetadata
    if get then
        local ok, version = pcall(get, addonName, "Version")
        if ok and version and version ~= "" then return version end
    end
    return "dev"
end

-- ─── client ──────────────────────────────────────────────────────────────────

-- Build number, used to invalidate anything learned from a previous patch.
function API.ClientBuild()
    local ok, _, build = pcall(GetBuildInfo)
    return ok and tostring(build) or "?"
end

-- ─── test seam ───────────────────────────────────────────────────────────────
-- Harmless in game; the unit tests reach the file-locals through it.

Priestly._testCompat = {
    matchAura = matchAura,
    spellInfo = spellInfo,
}
