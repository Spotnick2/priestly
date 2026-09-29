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
-- current beta cap no priest can LEARN the group spells - though the client
-- still resolves their names by ID, so they are not unresolved (see above).
local function RefreshSpellData()
    engine:RefreshSpells()
    -- PriestlyConfig's "show Shadow Protection when someone has it" mode needs
    -- the localized aura names, and it loads before this file. It needs the
    -- engine too, to read those auras through whatever aura pass is open
    -- rather than walking the roster a second time (#6) - and it cannot take
    -- either at load, hence both being published here.
    Priestly.engine = engine
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

-- ─── What names are we actually matching? ────────────────────────────────────
--
-- Spell names come from the client, by ID, so they speak whatever language it
-- does. When that fails the name stays as the English literal in DEFS, which
-- matches no aura on a localized client - every member reads as unbuffed, and
-- the addon looks exactly like a raid with no buffs. That was reported once
-- from CurseForge and never diagnosed, because nothing Priestly said named
-- the problem (#21).
--
-- So `/priestly help` prints what it is matching on. A "not working" report
-- then arrives carrying its own answer, without the reporter having to know
-- what to look for.
-- Asked at print time, never captured. The library upgrades IN PLACE: a
-- sibling addon shipping a newer copy replaces the methods this addon is
-- already running, so a version read at load would name the copy that lost.
-- That is the same rule AGENTS.md states for functions, and the line exists
-- to tell a bug report which code actually ran.
local function LiveLibraryMinor()
    if not LibStub then return "?" end
    local _, live = LibStub("LibGroupBuffs-1.0", true)
    return live or "?"
end

local FROM_NOTE = {
    resolved   = "",
    remembered = " (remembered)",
    fallback   = " |cffff6666(UNRESOLVED - English name)|r",
    unknown    = " (provenance unknown)",
}

-- Forward-declared: the report and the once-a-session warning both ask for
-- the rank, and both are written above the function that reads it. A local
-- declared further down is a GLOBAL inside a closure written above it, which
-- the strict-global stub catches at the first call rather than at load.
local GetPrayerRank

function Priestly_PrintSpellReport()
    if not DEFAULT_CHAT_FRAME then return end
    -- Asked for here, before the report is built. Whether a rank could be
    -- read is recorded as a SIDE EFFECT of reading it, and the only thing
    -- that reads one is the reagent footer - which is not drawn while the
    -- window is shut. So a solo priest whose candle vanished, who opens no
    -- window and types /priestly help to find out why, would get a report
    -- with nothing in it about the rank: silent in exactly the case someone
    -- is asking.
    GetPrayerRank()
    local report = engine:SpellReport()
    local API = Priestly.API
    DEFAULT_CHAT_FRAME:AddMessage("|cff99ddff[Priestly]|r Spell names, as this client gave them:")
    DEFAULT_CHAT_FRAME:AddMessage(string.format("  locale %s, game build %s, Priestly %s, library r%s",
        tostring(report.locale), tostring(API.ClientBuild and API.ClientBuild() or "?"),
        tostring(API.AddonVersion and API.AddonVersion("Priestly") or "?"),
        tostring(LiveLibraryMinor())))
    for _, entry in ipairs(report) do
        for _, form in ipairs(entry.forms) do
            DEFAULT_CHAT_FRAME:AddMessage(string.format("  %-7s %-6s %s%s%s",
                entry.id, form.role, tostring(form.name),
                FROM_NOTE[form.from] or "", form.known and "" or " - not learned"))
        end
    end
    if report.ranks then
        for _, r in ipairs(report.ranks) do
            DEFAULT_CHAT_FRAME:AddMessage(string.format(
                "  |cffff6666rank unreadable|r  %s  - the client says \"%s\", "
                .. "which carries no number Priestly can read",
                tostring(r.name), tostring(r.subtext)))
        end
        DEFAULT_CHAT_FRAME:AddMessage("  Rank decides which candle a Prayer "
            .. "burns, so the reagent counter stays hidden rather than count "
            .. "the wrong one. Please report this with the line above.")
    end
    if report.unresolved > 0 then
        DEFAULT_CHAT_FRAME:AddMessage("  |cffff6666" .. report.unresolved
            .. " name(s) could not be read from the client.|r Buffs Priestly cannot name are "
            .. "read as missing on everyone. Please report this with the lines above.")
    end
end

-- Said once a session, and only when something is actually broken by it: a
-- name still on its English fallback for a buff the player is tracking.
-- Deliberately not keyed on the locale - resolution can fail on an English
-- client too, and a German client whose names all resolved is fine.
local g_WarnedUnresolved = false
local g_WarnedRank = false

-- Said once a session when a rank could not be read, on the same footing as
-- an unresolved name. The reagent counter simply stops existing otherwise,
-- and "the footer disappeared" is no easier to act on than "the count looks
-- wrong" - the whole argument for not guessing the candle applies to not
-- staying quiet about it either.
local function WarnIfRankUnreadable()
    if g_WarnedRank or not DEFAULT_CHAT_FRAME then return end
    if not g_IsPriest then return end
    -- Asked for here: whether a rank could be read is recorded as a side
    -- effect of reading one, and the only thing that reads one is the reagent
    -- footer, which is not drawn while the window is shut.
    GetPrayerRank()
    local report = engine:SpellReport()
    if not report.ranks then return end
    g_WarnedRank = true
    DEFAULT_CHAT_FRAME:AddMessage("|cff99ddff[Priestly]|r |cffff6666Could not read which rank "
        .. "of a group Prayer you know.|r Rank decides which candle it burns, so the reagent "
        .. "counter is hidden rather than counting the wrong one. |cffffffff/priestly help|r "
        .. "has the details.")
end

local function WarnIfNamesUnresolved()
    if g_WarnedUnresolved or not DEFAULT_CHAT_FRAME then return end
    -- Gated HERE rather than at each caller, because the callers are events.
    -- SPELLS_CHANGED is registered as soon as the files load and can arrive
    -- before PLAYER_LOGIN, when there is no saved table yet and
    -- Priestly_IsBuffEnabled answers "enabled" for everything - so a
    -- character whose Spirit is switched off would spend the once-a-session
    -- warning before its own settings were readable. g_IsPriest is false
    -- until login, which makes it the signal for both that and the addon
    -- having nothing to say to a non-priest.
    if not g_IsPriest then return end
    local report = engine:SpellReport()
    for _, entry in ipairs(report) do
        for _, form in ipairs(entry.forms) do
            if form.from == "fallback" and Priestly_IsBuffEnabled
                and Priestly_IsBuffEnabled(entry.id) then
                g_WarnedUnresolved = true
                DEFAULT_CHAT_FRAME:AddMessage("|cff99ddff[Priestly]|r |cffff6666Could not read "
                    .. "some spell names from the game client.|r Buffs it cannot name are shown "
                    .. "as missing on everyone. |cffffffff/priestly help|r has the details.")
                return
            end
        end
    end
end

-- Both warnings, from every path that had one. They are SEPARATE latches
-- and must be tried separately: nesting the rank check inside the name check
-- put it after that function's own early return, so a priest who had already
-- been warned about a name - and then learned a Prayer whose rank will not
-- read - was never told why their reagent counter vanished. One latch spent
-- must not spend the other.
local function WarnAboutSpells()
    WarnIfRankUnreadable()
    WarnIfNamesUnresolved()
end

-- Filling the extension point PriestlyConfig leaves empty. Turning a buff ON
-- is the other moment an unresolved name starts to matter: that row reads
-- MISS on everyone from then on, and without this nothing would explain it
-- for the rest of the session. Cheap, as that hook asks: the latch returns on
-- the first line once anything has been said.
function Priestly_OnConfigChanged(key)
    if key == "trackFort" or key == "trackSpirit" then WarnAboutSpells() end
end

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

-- Highest rank of Prayer of Fortitude known: 0 if none, nil if the client
-- described the rank in a way we could not read (see GetCandleInfo).
function GetPrayerRank()
    local fort = DEFS[1]
    -- Gated on the NAME, not on hasGroup. The library clears its record of an
    -- unreadable rank when asked about a spell that is no longer in the book,
    -- and it can only do that if it is asked - returning early for a Prayer
    -- the priest does not know left the old failure standing, so a report
    -- went on naming a rank problem for a spell they had never learned.
    if not fort.grp then return 0 end
    return (API.GetSpellRank(fort.grp))
end

-- Determine which candle item ID and icon to use
-- Which candle a Prayer consumes, decided from its RANK - rank 1 burns a Holy
-- Candle, higher ranks a Sacred one.
--
-- A nil rank means the client described the rank in words we could not read a
-- number out of, so we do not know which. Showing nothing is the honest answer
-- and the safe one: naming a candle on a guess counts the wrong item in the
-- player's bags and reads as the addon being confused, with nothing saying
-- why. /priestly help says what the client actually told us (#64).
local function GetCandleInfo()
    local rank = GetPrayerRank()
    if rank == nil then return nil, nil, nil end
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
-- Rows, popover, clicks, dragging, the ticker and what combat defers are shared
-- with Wildly and Magely. Priestly supplies its title, spec icon, reagents and
-- config. WHEN the window opens is the library's too, through the policy object
-- built below; the events and slash commands here report what happened.
local ui = Priestly.UI.New({
    engine  = engine,
    owner   = addonName,
    title   = "|cff99ddffPriestly|r",
    version = VERSION,
    appearance = function() return { icon = GetSpecIcon() } end,
    unknownClassIcon = PRIEST_ICON,
    footerItems = FooterItems,
    alpha       = function() return Priestly_GetFrameAlpha and Priestly_GetFrameAlpha() or 0.96 end,
    scale       = function() return Priestly_GetFrameScale and Priestly_GetFrameScale() or 1.00 end,
    -- `Priestly_FrameLocked and` is not decoration: if PriestlyConfig fails to
    -- load, calling a nil global would throw - silently, errors are off by
    -- default here - and kill the drag. Short-circuiting leaves the window
    -- draggable, which is the safe way to be wrong.
    locked      = function() return Priestly_FrameLocked and Priestly_FrameLocked() or false end,
    popoverSide = function() return Priestly_PopoverSide and Priestly_PopoverSide() or "auto" end,
    showClickHints = function() return not Priestly_ShowClickHints or Priestly_ShowClickHints() end,
    getPos = function()
        if not PriestlyAccountDB then return nil, "PriestlyAccountDB was nil" end
        if not PriestlyAccountDB.pos then return nil, "PriestlyAccountDB.pos was nil" end
        return PriestlyAccountDB.pos
    end,
    setPos     = function(pos) SetConfig("pos", pos) end,
    setVisible = function(visible) Priestly_SetWindowVisible(visible) end,
    -- The window parents secure buttons, so in combat the client refuses to
    -- hide it (docs/FOREVER-PROBE.md section 13). Every close the PLAYER asked
    -- for - the X button, /priestly hide - lands here, so neither looks
    -- ignored.
    --
    -- Not the solo checkbox. Unticking it while alone closes the window
    -- because there is nothing left to show, which is an automatic close: it
    -- deliberately does not write "the player does not want this window", and
    -- Close only explains a close it recorded as the player's. So in combat
    -- the frame stays up until the fight ends with nothing said. Worth fixing
    -- one day - by letting Close explain an automatic close too, in the
    -- library, for all three addons - and not by marking the toggle manual,
    -- which would conflate "not while solo" with "not at all".
    onCloseDeferred = function()
        DEFAULT_CHAT_FRAME:AddMessage(
            "|cff99ddff[Priestly]|r The window closes when you leave combat.")
    end,
})

-- When the window opens itself, and when it must not. Priestly still owns its
-- events, its slash commands and its class; this decides what each of them
-- means for the window. It lived here, in Wildly and in Magely as three
-- near-identical copies, and every defect they produced was the same shape:
-- found in one addon, fixed there, and left standing in the others.
-- LibGroupBuffs#22 lists them - one place, rather than a tally in each file
-- that drifts out of step with the other two, which is how this file came to
-- claim six while the branch that wrote it had found seven.
local vis = Priestly.Visibility.New({
    ui            = ui,
    isMyClass     = function() return g_IsPriest end,
    showSolo      = function() return Priestly_ShowSolo() end,
    getPreference = function() return Priestly_WindowVisible() end,
    setPreference = function(v) Priestly_SetWindowVisible(v) end,
})

-- ─── Global hooks for PriestlyConfig.lua ────────────────────────────────────

function Priestly_ScheduleRefresh()
    ui:ScheduleRefresh()
end

-- Something may have given the window rows, or taken them away: a setting, a
-- spell learned, zoning into an instance that is on the list. The library
-- decides what that means for a window that is open, one the player closed,
-- and one that closed itself for want of rows - three cases that took five
-- separate fixes across three addons to get right once.
function Priestly_ForceRebuild()
    vis:ContentChanged()
end

-- Called when the solo checkbox is toggled in config
function Priestly_OnSoloToggle(enabled)
    vis:SoloToggled(enabled)
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
    -- The client saying you JOINED, rather than us inferring it from the
    -- roster changing. It fires: Blizzard's own UI for this build registers
    -- and acts on it (Blizzard_DamageMeter/DamageMeter.lua:78,
    -- Blizzard_QuickJoin/QuickJoin.lua:19, in C:/Projects/wow-ui-source).
    -- The roster heuristic stays as the fallback anyway - it costs nothing
    -- and covers every join we can see for ourselves.
    "GROUP_JOINED",
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
        -- Per character, not shared: see Priestly_SetWindowVisible.
        if Priestly_WindowVisible() == nil then Priestly_SetWindowVisible(true) end

        -- Resolve localized spell names and what this priest actually knows
        -- before anything reads DEFS.
        RefreshSpellData()
        -- After the first resolve, so it can only fire on a real failure.
        WarnAboutSpells()

        ui:Init()

        -- Apply configured opacity
        Priestly_ApplyAlpha()

        -- Auto-open if Priest and in a group (or solo mode) - unless the
        -- window was deliberately closed, which is a preference that should
        -- survive a reload.
        -- A new session, and the auto-open decision with it: in a group or
        -- solo mode, and never over a window the player closed.
        vis:Login()

        DEFAULT_CHAT_FRAME:AddMessage(
            "|cff99ddff[Priestly]|r Loaded. " ..
            (g_IsPriest and "Auto-opens when you join a group. " or "") ..
            "Type |cffffffff/priestly help|r for commands. " ..
            "Type |cffffffff/priestly config|r for options."
        )

    elseif event == "READY_CHECK" then
        vis:ReadyCheck()

    elseif event == "UNIT_AURA" then
        if AuraEventIsRelevant(arg1, arg2) then ui:ScheduleRefresh() end

    elseif event == "UNIT_PET" then
        -- Pet summoned or dismissed: rebuild to add/remove pet rows
        ui:ScheduleRefresh()

    elseif event == "GROUP_JOINED" then
        vis:GroupJoined()

    elseif event == "RAID_ROSTER_UPDATE" or event == "GROUP_ROSTER_UPDATE" then
        -- Priestly's own cache first, then the decision: the library reads the
        -- roster to make it, so anything the host must invalidate has to be
        -- invalidated before the call, not after.
        PruneAuraCache()
        vis:RosterChanged()

    elseif event == "PLAYER_TALENT_UPDATE" or event == "SPELLS_CHANGED" or event == "ACTIVE_TALENT_GROUP_CHANGED" then
        -- Newly learned spells change which rows exist and how they cast.
        RefreshSpellData()
        -- A spell just learned may resolve where it did not before, or fail
        -- where it did not. Latched, so this can only ever speak once.
        WarnAboutSpells()
        ui:ApplyAppearance()      -- the spec icon
        -- A rebuild: what a respec or a new spell changes is which rows
        -- exist, and the library decides whether a closed window should come
        -- back for them. In combat an open window can only move its counts,
        -- and the rebuild follows the fight.
        if ui:IsVisible() and InCombatLockdown() then
            ui:RefreshFooter()
        else
            vis:ContentChanged()
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
        DEFAULT_CHAT_FRAME:AddMessage(
            "  |cffffffff/priestly adopt|r      share THIS character's old settings with all")
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
        -- LAST, and deliberately: the login warning sends people here to copy
        -- these lines, and a default chat frame shows about ten. Printed in
        -- the middle of the dump they scroll off behind the click legend.
        Priestly_PrintSpellReport()

    elseif cmd == "config" or cmd == "options" or cmd == "settings" or cmd == "opt" then
        if Priestly_OpenConfig then Priestly_OpenConfig() end

    elseif cmd == "adopt" then
        -- Settings are account-wide again as of 70009; the first character
        -- logged in after that change seeded them. This is how a player picks
        -- a different one afterwards.
        local applied, panelStale = Priestly_AdoptCharacterSettings()
        if applied > 0 then
            DEFAULT_CHAT_FRAME:AddMessage("|cff99ddff[Priestly]|r Now using this character's "
                .. "old settings on every character (" .. applied .. " applied).")
            if panelStale then
                -- Its controls are built once and never re-read the settings,
                -- so saying nothing would leave the panel disagreeing.
                DEFAULT_CHAT_FRAME:AddMessage("|cff99ddff[Priestly]|r The options window still "
                    .. "shows the old values - |cffffffff/reload|r to refresh it.")
            end
        else
            DEFAULT_CHAT_FRAME:AddMessage("|cff99ddff[Priestly]|r Nothing to adopt: this "
                .. "character has no settings saved from before they became shared.")
        end

    elseif cmd == "reset" then
        if ui:ResetPosition() then
            DEFAULT_CHAT_FRAME:AddMessage("|cff99ddff[Priestly]|r Window position reset.")
        else
            -- Re-anchoring the window is blocked in combat: it parents secure
            -- buttons (docs/FOREVER-PROBE.md section 13), so the move waits.
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
        local p = PriestlyAccountDB and PriestlyAccountDB.pos
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
        ui:Close(true)      -- onCloseDeferred says so if combat refuses it

    elseif cmd == "show" then
        Priestly_SetWindowVisible(true)
        ui:Update()

    else
        if ui:IsVisible() then
            ui:Close(true)
        else
            Priestly_SetWindowVisible(true)
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
    -- The once-a-session latches, so a test can exercise a warning without
    -- depending on which earlier section already spent it.
    ResetWarnings    = function() g_WarnedUnresolved, g_WarnedRank = false, false end,
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
