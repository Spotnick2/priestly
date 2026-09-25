-- ============================================================================
-- PriestlyConfig.lua  –  Options panel for Priestly Forever
-- Registers through Retail's Settings framework (WoW: Forever 1.60.1)
-- ============================================================================

local ADDON_NAME = "Priestly"
local API = Priestly.API

-- PriestlyCompat.lua has already said in chat why Priestly cannot start if the
-- shared library is missing. Stop here rather than building half an addon and
-- failing further down, far from the cause.
if not API then return end

-- ─── Default configuration ──────────────────────────────────────────────────

local DEFAULTS = {
    trackFort       = true,
    trackSpirit     = true,
    shadowMode      = "detect",   -- "always" | "detect" | "instance"
    showSolo        = false,
    trackPets       = true,
    frameAlpha      = 0.96,
    popoverSide     = "auto",     -- "auto" | "left" | "right"
    lockFrame       = false,
    showClickHints  = true,
}

-- Deliberately NOT in DEFAULTS: a nil value creates no key, so the pairs()
-- backfill below would never see them. Each is initialised by hand in
-- Priestly_EnsureDefaults:
--   shadowInstances   -- [instanceName] = tracked
--   learnedDurations  -- [spellName] = seconds, scoped to a client build
--   flavor            -- migration marker
--
-- And one that must NEVER be in DEFAULTS, or it stops working:
--   svLoadCheck       -- proof the client read the file; see the load check

-- ─── One write path for PriestlyDB ─────────────────────────────────────────────
--
-- Nothing an addon writes survives a real client restart on this build -
-- account-wide and per-character SavedVariables, and CVars too (issue #9,
-- docs/FOREVER-PROBE.md section 11). The fix is Blizzard's. Until it lands,
-- every settings change goes through one setter anyway, so that whatever the
-- fix needs - a migration, a validation pass, a different store - lands in one
-- place instead of in each handler.
--
-- The setter, the check that notices the fix and the check that notices a new
-- client build are shared by every addon on LibGroupBuffs-1.0 (Settings.lua,
-- issue #3). Priestly supplies what is its own: the saved tables, the builds
-- it was measured on, and how it speaks in chat.
--
-- Priestly_OnConfigChanged is empty on purpose. It fires once per instance
-- during Select All, so whatever fills it later must be cheap, or debounce.
--
-- The contract, enforced by a source scan in tests/test_config_seam.lua: no
-- file writes PriestlyDB or PriestlySVCheck directly except inside a
-- `config-owner` region - the code that creates the tables, seeds defaults,
-- runs migrations and keeps the learned-duration cache. Everything else calls
-- one of the setters below.

-- Which build Priestly's notes on this beta were measured on, and the build
-- where SavedVariables are measured broken. In the SOURCE, because it is the
-- one thing that survives a restart here. Bump MEASURED_ON_BUILD after
-- re-measuring (AGENTS.md); the library warns at every real login until then.
--
-- These two are INDEPENDENT, and right now they differ. The installed client
-- is 70009 (.build.info, wow_classic_beta 1.60.1.70009), patched 2026-09-24,
-- and NEITHER constant has caught up with it yet - see below for what each
-- one is still waiting on.
--
-- MEASURED_ON_BUILD stays 69913 until /pprobe is re-run on 69977. The two
-- API dumps are identical sets - documented functions, events, enums and
-- structures, widget methods, namespace functions - but matching declarations
-- cannot show that aura secrecy, secure click casting or any other RUNTIME
-- finding still behaves the same way. The login notice is the reminder that
-- they have not been re-checked, so silencing it is the one thing not to do.
--
-- SV_BROKEN_ON_BUILD is 69977 because that one IS measured, and it needs its
-- own instrument: a dump lists the same symbols whether or not the client
-- reads the file back. PriestlyProbe counts its own loads and appends a stamp
-- per load, and the account-wide file the client wrote on 2026-09-24 holds
-- launches = 1 and a single stamp, 11:00:02. Both a /reload and a relog hand
-- the table back in-process, so either would have left two stamps; a prior
-- session's file was on disk to load (the 2026-09-21 measurement read it).
-- One stamp means the addon saw nothing at load on a real client start.
-- Priestly's own svLoadCheck, written 11:00:10 in that same session, records
-- the build as 69977. Still broken there.
--
-- 70009 then patched, and settings appear to come back: AltStable's launch
-- counter moved 3 -> 4 account-wide and 1 -> 2 per-character, and Priestly's
-- markers returned and announced. What is NOT yet shown is a full exit
-- between those two sessions - a logout to character select writes saved
-- variables too - so this constant stays at 69977 until a quit-and-relaunch
-- is measured. Being wrong here in the optimistic direction is what #57 was
-- about. LibGroupBuffs#30 settles the question without a constant at all, by
-- comparing the marker's own recorded build with the one running.
--
-- The test pins both literally, so a build that moves on cannot pass by
-- agreeing with itself.
local MEASURED_ON_BUILD = "69913"
local SV_BROKEN_ON_BUILD = "69977"

-- config-owner: begin
-- The two saved tables, created on first use. PriestlyDB holds the settings
-- (per character); PriestlySVCheck is a small account-wide table declared only
-- so the load check can watch that scope too - account-wide storage is what
-- #9 wants to move back to once it works.
local function CharacterStore()
    if not PriestlyDB then PriestlyDB = {} end
    return PriestlyDB
end

local function AccountCheckStore()
    if not PriestlySVCheck then PriestlySVCheck = {} end
    return PriestlySVCheck
end
-- config-owner: end

function Priestly_OnConfigChanged(key)
end

local settings = Priestly.Settings.New({
    owner = ADDON_NAME,
    scopes = {
        { label = "per-character", get = CharacterStore },
        { label = "account-wide",  get = AccountCheckStore },
    },
    measuredOnBuild = MEASURED_ON_BUILD,
    svBrokenOnBuild = SV_BROKEN_ON_BUILD,
    report = function(text, kind)
        if not DEFAULT_CHAT_FRAME then return end
        if kind == "settingsLoaded" then text = "|cff55ff55" .. text .. "|r" end
        DEFAULT_CHAT_FRAME:AddMessage("|cff99ddff[Priestly]|r " .. text)
    end,
    -- Looked up at call time, not captured: the hook is Priestly's extension
    -- point, and whatever replaces it later (or a test) must be the one called.
    onChanged = function(key) Priestly_OnConfigChanged(key) end,
})

-- An unchanged value is not a change: UpdateUI sets `visible` on every
-- refresh, which would otherwise run the hook on the aura hot path. Tables
-- are always reported.
function Priestly_SetConfig(key, value)
    settings:Set(key, value)
end

-- One entry of the Shadow Protection instance list.
function Priestly_SetShadowInstance(name, tracked)
    settings:SetIn("shadowInstances", name, tracked)
end

-- ─── Instance databases ─────────────────────────────────────────────────────
-- { "Instance Name", "category", defaultEnabled, "Tooltip: boss encounters" }
-- Instance names must match GetInstanceInfo() return values.

-- What is reachable on Forever, not what existed in Vanilla. The legacy raids
-- beyond Onyxia's Lair are not listed because they are not in the game.
--
-- Dungeons are ordered by level, which is how a player thinks about them.
-- Entries marked NEW are Forever's own content: nothing is known about their
-- encounters, so they carry an honest tooltip rather than an invented one.
--
-- A checked instance describes the INSTANCE, not the player: whether its bosses
-- deal meaningful shadow damage. It says nothing about whether the buff is
-- available, because ActiveDefs already refuses to build a row for a spell the
-- priest has not learned - so checking a level 22 dungeon costs a level 22
-- priest nothing, and is simply correct for the level 60 one running it.
--
-- MULTI-WING INSTANCES ARE ONE ENTRY. Scarlet Monastery, Maraudon, Dire Maul,
-- Stratholme and Blackrock Spire each have several entrances, but
-- GetInstanceInfo() reports one name for all of them - so a key per wing would
-- give several that never match anything.
--
-- CAUTION: these names are the keys matched against GetInstanceInfo(), and a
-- name that is wrong fails silently - so CheckCurrentInstance announces any
-- instance it does not recognise, turning that into a report rather than a
-- mystery.
--
-- MEASURED so far, with `/pprobe here`:
--   "Ruins of Lordaeron"  instanceMapID 2999, party, 5 players  (2026-09-20)
--
-- Everything else is unverified. Most is above the current level cap and
-- cannot be measured yet. Blizzard's roster writes "The Hall of Thanes" and
-- "Alcaz Prison", which is what is used here - but a forum roster is not the
-- client, and only GetInstanceInfo() settles it.
-- Note the apostrophes are ASCII ('), not typographic - a detail that costs
-- nothing to get right and everything to get wrong. `/pprobe here` inside an
-- instance prints the exact string. Issue #12 covers matching on map ID
-- instead, which is both verifiable and locale-proof.
local INSTANCE_DB = {
    -- ── Raids, by size ───────────────────────────────────────────────
    { "The Barrow Deeps", "Raids", true,
      "10 player. NEW in Forever. Encounters are not catalogued yet - pre-checked because a raid "
      .. "is where missing Shadow Protection costs the most, while an unnecessary row costs "
      .. "little." },
    { "Hyjal Summit",    "Raids", true,
      "20 player. NEW in Forever. Encounters are not catalogued yet - pre-checked for the same "
      .. "reason. Note this is Forever's own raid, not the TBC one of the same name." },
    { "Onyxia's Lair",   "Raids", false,
      "40 player. Primarily Fire damage (Breath, Fireball)." },

    -- ── Dungeons, by level ───────────────────────────────────────────
    { "Ragefire Chasm",  "Dungeons", true,
      "Levels 13-18. Jergosh the Invoker casts Shadow Bolt and Curse of Weakness." },
    { "The Hall of Thanes", "Dungeons", false,
      "Levels 13-18. NEW in Forever. Encounters are not catalogued yet." },
    { "Ruins of Lordaeron", "Dungeons", false,
      "Levels 15-20. NEW in Forever. Encounters are not catalogued yet." },
    { "Wailing Caverns", "Dungeons", false,
      "Levels 15-25. Primarily Nature and poison damage." },
    { "The Deadmines",   "Dungeons", false,
      "Levels 18-23. Primarily physical and Fire damage." },
    { "Shadowfang Keep", "Dungeons", true,
      "Levels 22-30. Arugal (Shadow Bolt, Void Bolt), Wolf Master Nandos, and shadow casters "
      .. "throughout." },
    { "The Stockade",    "Dungeons", false,
      "Levels 22-30. Primarily physical damage." },
    { "Excavation Site: Wetlands", "Dungeons", false,
      "Levels 24-29. NEW in Forever. Encounters are not catalogued yet." },
    { "Blackfathom Deeps", "Dungeons", false,
      "Levels 24-32. Twilight Lord Kelris casts Mind Blast; the rest is Nature and Frost." },
    { "City of Dalaran", "Dungeons", false,
      "Levels 28-33. NEW in Forever. Encounters are not catalogued yet." },
    { "Scarlet Monastery", "Dungeons", true,
      "Levels 28-45, all four wings. Bloodmage Thalnos (Shadow Bolt) in the Graveyard; the "
      .. "Armory and Cathedral are physical. One entry because GetInstanceInfo() reports every "
      .. "wing under the same name." },
    { "Gnomeregan",      "Dungeons", false,
      "Levels 29-38. Primarily Nature, Fire and mechanical damage." },
    { "Razorfen Kraul",  "Dungeons", false,
      "Levels 30-40. Primarily Nature and poison damage." },
    { "The Drowned City", "Dungeons", false,
      "Levels 35-40. NEW in Forever. Encounters are not catalogued yet." },
    { "Krol'Dok Stronghold", "Dungeons", false,
      "Levels 40-45. NEW in Forever. Encounters are not catalogued yet." },
    { "Razorfen Downs",  "Dungeons", true,
      "Levels 40-50. Amnennar the Coldbringer deals Shadow and Frost damage; the rest is Nature." },
    { "Uldaman",         "Dungeons", false,
      "Levels 42-52. Primarily physical, Nature and Arcane damage." },
    { "Zul'Farrak",      "Dungeons", true,
      "Levels 44-54. Witch Doctor Zum'rah casts Shadow Bolt; the rest is Nature and physical." },
    { "Maraudon",        "Dungeons", false,
      "Levels 45-57, all entrances. Princess Theradras has a Shadow component; the rest is "
      .. "Nature. One entry: GetInstanceInfo() does not distinguish the entrances." },
    { "Alcaz Prison",    "Dungeons", false,
      "Levels 48-53. NEW in Forever. Encounters are not catalogued yet." },
    { "The Temple of Atal'Hakkar", "Dungeons", true,
      "Levels 50-60. Shade of Eranikus (Shadow Bolt Volley), Jammal'an the Prophet (Shadow "
      .. "Bolt). Known to players as the Sunken Temple." },
    { "Blackrock Depths", "Dungeons", false,
      "Levels 52-60. Ambassador Flamelash and scattered shadow casters. Generally not required." },
    { "Blackrock Spire", "Dungeons", false,
      "Levels 55-60, Lower and Upper. Some shadow casters, generally not required. One entry "
      .. "because both halves share an instance name." },
    { "Blackmaw Hold",   "Dungeons", false,
      "Levels 55-60. NEW in Forever. Encounters are not catalogued yet." },
    { "Dire Maul",       "Dungeons", true,
      "Levels 58-60, all wings. Immol'thar (Shadow Bolt, Portal of Immol'thar); the West wing "
      .. "warlocks cast Shadow throughout." },
    { "Scholomance",     "Dungeons", true,
      "Levels 58-60. Darkmaster Gandling, Rattlegore, and heavy shadow trash throughout." },
    { "Stratholme",      "Dungeons", true,
      "Levels 58-60, both sides. Baron Rivendare (Shadow Bolt), Baroness Anastari (Shadow Bolt), "
      .. "undead shadow casters throughout." },
    { "Shaper's Terrace", "Dungeons", false,
      "Levels 58-60. NEW in Forever. Encounters are not catalogued yet." },
}

-- ─── Ensure defaults ────────────────────────────────────────────────────────

local FLAVOR = "forever"

-- Resolved once per session (see Priestly_EnsureDefaults) so that learning a
-- duration does not call GetBuildInfo for every member of every group.
local g_Build

-- config-owner: begin
function Priestly_EnsureDefaults()
    if not PriestlyDB then PriestlyDB = {} end
    -- A client build can only change across a restart, which means a fresh
    -- login, which means this runs again. Re-resolving here is what keeps the
    -- cached build honest while keeping GetBuildInfo off the aura hot path.
    g_Build = nil
    for k, v in pairs(DEFAULTS) do
        if PriestlyDB[k] == nil then
            PriestlyDB[k] = v
        end
    end

    if PriestlyDB.shadowInstances == nil then
        PriestlyDB.shadowInstances = {}
    end

    -- One-time migration off the TBC line: drop the instances that build knew
    -- about, and the durations it learned, neither of which mean anything here.
    if PriestlyDB.flavor ~= FLAVOR then
        local known = {}
        for _, entry in ipairs(INSTANCE_DB) do known[entry[1]] = true end
        for name in pairs(PriestlyDB.shadowInstances) do
            if not known[name] then PriestlyDB.shadowInstances[name] = nil end
        end
        PriestlyDB.learnedDurations = nil
        PriestlyDB.flavor = FLAVOR
    end

    -- Deliberately NOT pruning unknown keys on every load. An entry the current
    -- list does not name is inert - nothing reads shadowInstances except
    -- CheckCurrentInstance, which looks up the zone you are standing in - so
    -- pruning buys tidiness and costs real data: install an older build once,
    -- or hand-edit an instance the list is missing, and every choice for those
    -- entries is gone with no way to get it back.

    -- Backfill instances added since this profile was written
    for _, entry in ipairs(INSTANCE_DB) do
        if PriestlyDB.shadowInstances[entry[1]] == nil then
            PriestlyDB.shadowInstances[entry[1]] = entry[3]
        end
    end

    PriestlyDB.shadowBosses = nil  -- migration
end
-- config-owner: end

-- ─── Learned buff durations ─────────────────────────────────────────────────
--
-- Forever's durations match neither TBC nor Vanilla and are still moving
-- during the beta, so the values in DEFS are only seeds: whatever a live aura
-- reports wins. Replacement goes in BOTH directions - pinning "the longest we
-- ever saw" would survive a duration nerf and quietly mis-colour every bar -
-- and the whole table is discarded when the client build changes.

-- config-owner: begin
local function DurationStore()
    if not PriestlyDB then return nil end
    if not g_Build then g_Build = (API and API.ClientBuild()) or "?" end
    local store = PriestlyDB.learnedDurations
    if not store or store.build ~= g_Build then
        store = { build = g_Build }
        PriestlyDB.learnedDurations = store
        -- Replaced from inside a getter, so it reports here or not at all.
        settings:Changed("learnedDurations")
    end
    return store
end

function Priestly_LearnDuration(spellName, seconds)
    if not spellName or not seconds or seconds <= 0 then return end
    local store = DurationStore()
    if not store then return end
    -- Almost every call re-learns the value we already have; only write when it
    -- actually changed.
    if store[spellName] == seconds then return end
    store[spellName] = seconds
    -- A write through a local alias, which the source scan cannot see, so it
    -- reports by hand.
    settings:Changed("learnedDurations")
end
-- config-owner: end

function Priestly_GetLearnedDuration(spellName)
    if not spellName then return nil end
    local store = DurationStore()
    return store and store[spellName] or nil
end

-- ─── Instance-based shadow detection ────────────────────────────────────────

local g_InShadowInstance = false

-- Instances we have already complained about, so the message appears once per
-- session rather than on every zone-in.
local g_ReportedUnknown = {}

local function CheckCurrentInstance()
    -- Out in the world this returns the CONTINENT ("Eastern Kingdoms" while
    -- standing in Undercity), not an empty string, so the name alone is not a
    -- test for "am I in an instance". instanceType is "none" outdoors and
    -- "party"/"raid" inside one - gate on that rather than relying on the
    -- continent never matching an entry in INSTANCE_DB.
    local name, instanceType = GetInstanceInfo()
    if not name or name == "" or instanceType == "none" then
        g_InShadowInstance = false
        return
    end

    local saved = PriestlyDB and PriestlyDB.shadowInstances
    g_InShadowInstance = (saved and saved[name] == true) or false

    -- The list is keyed on exact instance names that mostly cannot be verified
    -- until the level cap rises, and a wrong key fails SILENTLY - the mode
    -- simply never fires, with nothing to explain why. So say something. This
    -- turns an invisible bug into a bug report, and the players standing in
    -- these instances are the only ones who can measure them.
    --
    -- Narrowly, though. Battlegrounds and arenas report an instanceType too,
    -- and asking for their names would be asking for entries that do not
    -- belong in a shadow-damage list. And a player who has not chosen "by
    -- instance" is being warned about a feature they are not using - worse,
    -- being marked as already told, so the warning would never appear when
    -- they did turn it on.
    local relevantType = (instanceType == "party" or instanceType == "raid")
    local modeActive = PriestlyDB and PriestlyDB.shadowMode == "instance"
    if relevantType and modeActive
        and saved and saved[name] == nil and not g_ReportedUnknown[name]
    then
        g_ReportedUnknown[name] = true
        if DEFAULT_CHAT_FRAME then
            DEFAULT_CHAT_FRAME:AddMessage(
                "|cff99ddff[Priestly]|r does not recognise this instance: |cffffffff\"" ..
                tostring(name) .. "\"|r - Shadow Protection's \"by instance\" mode cannot " ..
                "work here. Please report that name so it can be added.")
        end
    end
end

function Priestly_ShouldShowShadow(groups, ord)
    if not PriestlyDB then return false end
    local mode = PriestlyDB.shadowMode or "detect"
    if mode == "always" then return true end
    if mode == "detect" then
        -- Names come from Priestly.lua's DEFS, which resolves them from spell
        -- IDs at runtime, so this stays correct in every locale.
        local names = Priestly.shadowAuraNames
        if groups and ord and names then
            for _, gn in ipairs(ord) do
                for _, m in ipairs(groups[gn] or {}) do
                    local status = API.ReadBuff(m.unit, names)
                    if status == "HAS" then return true end
                    -- A refused read is not evidence that nobody has it; making
                    -- the row vanish mid-fight would be worse than leaving it.
                    if status == "BLOCKED" then return true end
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

-- True when the window must not be dragged. Checked in the drag handler
-- rather than by unregistering the drag, which keeps this clear of the secure
-- frame rules and safe to toggle in combat.
function Priestly_FrameLocked()
    return PriestlyDB and PriestlyDB.lockFrame == true
end

-- Whether a row explains what its clicks will cast, on hover.
function Priestly_ShowClickHints()
    return not (PriestlyDB and PriestlyDB.showClickHints == false)
end

-- "auto" | "left" | "right". Auto means "wherever there is room", decided
-- fresh each time the popover opens - see PopoverSide in Priestly.lua.
function Priestly_PopoverSide()
    return (PriestlyDB and PriestlyDB.popoverSide) or "auto"
end

function Priestly_ShowSolo()
    return PriestlyDB and PriestlyDB.showSolo == true
end

-- ─── Has Blizzard fixed it? Did the client update? ──────────────────────────
--
-- Both checks live in LibGroupBuffs-1.0's Settings.lua. The load check keeps a
-- `svLoadCheck` marker in each scope - written every session, never in
-- DEFAULTS - and says so once when one comes back on a real login on a build
-- other than SV_BROKEN_ON_BUILD. The build check warns at every real login on
-- a build other than MEASURED_ON_BUILD, deliberately unlatched.

function Priestly_CheckClientBuild()
    settings:CheckBuild()
end

-- PLAYER_LOGIN fires on /reload too and cannot tell the two apart.
-- PLAYER_ENTERING_WORLD can: on 1.60.1.69913 it carries (isInitialLogin,
-- isReloadingUi), checked against the API dump. It also fires on every zone
-- change with both false, which is ignored.
function Priestly_HandleEnteringWorld(isInitialLogin, isReloadingUi)
    settings:HandleEnteringWorld(isInitialLogin, isReloadingUi)
end

-- ─── Instance detection events ──────────────────────────────────────────────

local detectFrame = CreateFrame("Frame", "PriestlyInstanceDetector")
Priestly.RegisterEvents(detectFrame,
    "PLAYER_LOGIN", "ZONE_CHANGED_NEW_AREA", "PLAYER_ENTERING_WORLD")
detectFrame:SetScript("OnEvent", function(self, event, isInitialLogin, isReloadingUi)
    if event == "PLAYER_LOGIN" then
        Priestly_EnsureDefaults()
        CheckCurrentInstance()
    else
        if event == "PLAYER_ENTERING_WORLD" then
            Priestly_HandleEnteringWorld(isInitialLogin, isReloadingUi)
        end
        CheckCurrentInstance()
        if Priestly_ScheduleRefresh then Priestly_ScheduleRefresh() end
    end
end)

-- ═════════════════════════════════════════════════════════════════════════════
-- OPTIONS PANEL  –  Two tabs: Settings | Instances
-- ═════════════════════════════════════════════════════════════════════════════

local panel = CreateFrame("Frame", "PriestlyOptionsPanel")
panel.name = ADDON_NAME

-- ─── Widget helpers ─────────────────────────────────────────────────────────
--
-- The TBC build leaned on InterfaceOptionsCheckButtonTemplate and
-- OptionsSliderTemplate. Neither is part of the Retail UI this client ships,
-- and a missing template makes CreateFrame throw - a load blocker, not a
-- cosmetic problem. So: ask for a template, accept that it may not be there,
-- and draw our own art when it is not.

local CHECK_ART = {
    normal    = "Interface\\Buttons\\UI-CheckBox-Up",
    pushed    = "Interface\\Buttons\\UI-CheckBox-Down",
    highlight = "Interface\\Buttons\\UI-CheckBox-Highlight",
    checked   = "Interface\\Buttons\\UI-CheckBox-Check",
}

-- Returns frame, templateApplied.
--
-- Never returns nil: callers go straight on to :SetPoint() and a nil here would
-- just move the load-blocking error one line down, which is the opposite of the
-- point. If the template is missing we fall back to a bare frame; if even that
-- fails nothing about the UI can work anyway, so let it raise.
local function SafeFrame(frameType, name, parent, template, proof)
    if template then
        local ok, f = pcall(CreateFrame, frameType, name, parent, template)
        if ok and f then
            -- `proof` names a region the template is supposed to bring. Without
            -- it we cannot tell an applied template from a missing one, because
            -- a missing template does not throw - CreateFrame just returns a
            -- bare frame (docs/FOREVER-PROBE.md).
            local applied = true
            if proof then
                applied = f[proof] ~= nil
                    or (f.GetName and f:GetName() and _G[f:GetName() .. proof] ~= nil)
            end
            return f, applied
        end
    end
    return CreateFrame(frameType, name, parent), false
end

-- A check button that looks right whether or not the template exists, with a
-- label we own (template label fields have moved around between UI versions).
local function MakeCheckButton(parent, name, label, labelWidth)
    local cb, templated = SafeFrame("CheckButton", name, parent, "UICheckButtonTemplate", "text")
    cb:SetSize(24, 24)
    if not templated then
        cb:SetNormalTexture(CHECK_ART.normal)
        cb:SetPushedTexture(CHECK_ART.pushed)
        cb:SetHighlightTexture(CHECK_ART.highlight)
        cb:SetCheckedTexture(CHECK_ART.checked)
    end
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    fs:SetPoint("LEFT", cb, "RIGHT", 2, 0)
    fs:SetJustifyH("LEFT")
    if labelWidth then fs:SetWidth(labelWidth) end
    fs:SetText(label or "")
    cb.label = fs
    return cb
end

-- GetStringHeight returns 0 for a FontString that has not been laid out yet,
-- which is the normal state inside a scroll child built during OnShow. `0 or 16`
-- is 0 in Lua, so every one of these needs a real check or the next control
-- lands on top of the text.
local function TextHeight(fs, fallback)
    local h = fs and fs:GetStringHeight()
    if not h or h <= 0 then return fallback or 16 end
    return h
end

-- One rebuild per click. ForceRebuild already re-runs everything
-- ScheduleRefresh would, so asking for both queued two complete passes - roster
-- gather, aura scan, SetAttribute on every secure row - 250ms apart.
local function RefreshShadowRow()
    if Priestly_ForceRebuild then Priestly_ForceRebuild() end
end

local function MakeHeader(parent, yRef, text, width)
    yRef.v = yRef.v - 14
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    fs:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, yRef.v)
    fs:SetText(text)
    local textH = TextHeight(fs)
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
    local cb = MakeCheckButton(parent, "PriestlyCB_"..dbKey, label)
    cb:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, yRef.v)
    cb:SetChecked(PriestlyDB[dbKey] ~= false)
    cb:SetScript("OnClick", function(self)
        Priestly_SetConfig(dbKey, self:GetChecked() and true or false)
        if onChange then onChange(self:GetChecked()) end
        RefreshShadowRow()
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
    yRef.v = yRef.v - (TextHeight(fs) + 6)
    return fs
end

local function MakeRadioGroup(parent, yRef, options, currentKey, onSelect)
    local radios = {}
    for _, opt in ipairs(options) do
        yRef.v = yRef.v - 4
        -- UIRadioButtonTemplate ships on this client, but fall back to the
        -- checkbox art rather than risk a load-blocking CreateFrame throw.
        local rb, templated = SafeFrame("CheckButton", "PriestlyRB_"..opt.key, parent,
            "UIRadioButtonTemplate", "text")
        rb:SetPoint("TOPLEFT", parent, "TOPLEFT", 4, yRef.v)
        if not templated then
            rb:SetSize(20, 20)
            rb:SetNormalTexture(CHECK_ART.normal)
            rb:SetHighlightTexture(CHECK_ART.highlight)
            rb:SetCheckedTexture(CHECK_ART.checked)
        end
        local textObj = rb.text or rb.Text or (rb:GetName() and _G[rb:GetName().."Text"])
        if not textObj then
            textObj = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            textObj:SetPoint("LEFT", rb, "RIGHT", 4, 0)
            textObj:SetJustifyH("LEFT")
        end
        textObj:SetText(opt.label)
        textObj:SetFontObject("GameFontHighlight")
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

-- Changing which instances count can add or remove the Shadow Protection row,
-- so every control that touches the list has to ask for the same refresh - the
-- bulk buttons used to update the detector and stop there, leaving the row
-- stale until something unrelated rebuilt the UI.
local function BuildInstanceTab(parent, instanceDB, panelWidth)
    local scroll = SafeFrame("ScrollFrame", parent:GetName().."Scroll", parent,
        "UIPanelScrollFrameTemplate")
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
        "Instances are pre-checked when their bosses deal significant shadow damage - or, for " ..
        "Forever's own raids, because nothing is known about them yet and a raid is where " ..
        "missing the buff costs the most. " ..
        "Either way the row only appears once you have learned Shadow Protection.|r")
    iy.v = iy.v - (TextHeight(desc, 32) + 10)

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

            -- The index restarts per category, so a per-category suffix would
            -- give Naxxramas and Scholomance the same global name and _G would
            -- keep only one of them.
            local icb = MakeCheckButton(child,
                "PriestlyInst_" .. parent:GetName() .. "_" .. instName:gsub("%W", ""),
                instName, COL_W - 28)
            icb:SetPoint("TOPLEFT", child, "TOPLEFT", xOff, yOff)
            icb:SetChecked(PriestlyDB.shadowInstances[instName] == true)
            icb._instName = instName

            icb:SetScript("OnClick", function(self)
                Priestly_SetShadowInstance(self._instName, self:GetChecked() and true or false)
                CheckCurrentInstance()
                RefreshShadowRow()
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
    local btnAll = SafeFrame("Button", parent:GetName().."All", child, "UIPanelButtonTemplate")
    btnAll:SetSize(90, 22)
    btnAll:SetPoint("TOPLEFT", child, "TOPLEFT", 0, iy.v)
    btnAll:SetText("Select All")
    btnAll:SetScript("OnClick", function()
        for _, entry in ipairs(instanceDB) do
            Priestly_SetShadowInstance(entry[1], true)
        end
        for _, cb in ipairs(allCheckboxes) do cb:SetChecked(true) end
        CheckCurrentInstance()
        RefreshShadowRow()
    end)

    local btnNone = SafeFrame("Button", parent:GetName().."None", child, "UIPanelButtonTemplate")
    btnNone:SetSize(90, 22)
    btnNone:SetPoint("LEFT", btnAll, "RIGHT", 8, 0)
    btnNone:SetText("Deselect All")
    btnNone:SetScript("OnClick", function()
        for _, entry in ipairs(instanceDB) do
            Priestly_SetShadowInstance(entry[1], false)
        end
        for _, cb in ipairs(allCheckboxes) do cb:SetChecked(false) end
        CheckCurrentInstance()
        RefreshShadowRow()
    end)

    local btnDefaults = SafeFrame("Button", parent:GetName().."Defaults", child, "UIPanelButtonTemplate")
    btnDefaults:SetSize(110, 22)
    btnDefaults:SetPoint("LEFT", btnNone, "RIGHT", 8, 0)
    btnDefaults:SetText("Reset Defaults")
    btnDefaults:SetScript("OnClick", function()
        for _, entry in ipairs(instanceDB) do
            Priestly_SetShadowInstance(entry[1], entry[3])
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
        RefreshShadowRow()
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
    verFs:SetText("|cff555577" ..
        API.AddonVersion(ADDON_NAME)
        .. "|r")

    -- ── Tab bar ─────────────────────────────────────────────────────────────
    local TAB_Y = -38
    local tabNames = { "Settings", "Instances" }
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
        local btnW = 100
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

    local settingsScroll = SafeFrame("ScrollFrame", "PriestlySettingsScroll", panel,
        "UIPanelScrollFrameTemplate")
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
    y.v = y.v - (TextHeight(shadowDesc) + 8)

    MakeRadioGroup(settingsChild, y, {
        { key = "always",   label = "Always show Shadow Protection" },
        { key = "detect",   label = "Show when detected on a group member" },
        { key = "instance", label = "Show by instance (configure in the |cff99ddffInstances|r tab)" },
    }, PriestlyDB.shadowMode, function(key)
        Priestly_SetConfig("shadowMode", key)
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

    -- Template-free slider. OptionsSliderTemplate belongs to the Classic
    -- options UI and is not guaranteed here; the track and fill above are
    -- already ours, so all this needs is a thumb and the input handling.
    local alphaSlider = CreateFrame("Slider", "PriestlyAlphaSlider", settingsChild)
    alphaSlider:SetPoint("TOPLEFT", settingsChild, "TOPLEFT", 4, y.v)
    alphaSlider:SetSize(SLIDER_W + 8, 18)
    alphaSlider:SetOrientation("HORIZONTAL")
    alphaSlider:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
    local thumb = alphaSlider:GetThumbTexture()
    if thumb then thumb:SetSize(16, 18) end
    alphaSlider:SetMinMaxValues(0.20, 1.00)
    alphaSlider:SetValueStep(0.05)
    if alphaSlider.SetObeyStepOnDrag then alphaSlider:SetObeyStepOnDrag(true) end
    alphaSlider:SetValue(PriestlyDB.frameAlpha or 0.96)

    local lowTxt = settingsChild:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    lowTxt:SetPoint("TOPLEFT", alphaSlider, "BOTTOMLEFT", 2, 2)
    lowTxt:SetText("20%")
    local highTxt = settingsChild:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    highTxt:SetPoint("TOPRIGHT", alphaSlider, "BOTTOMRIGHT", -2, 2)
    highTxt:SetText("100%")

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
        Priestly_SetConfig("frameAlpha", value)
        alphaVal:SetText(string.format("%d%%", value * 100))
        UpdateFill()
        if Priestly_ApplyAlpha then Priestly_ApplyAlpha() end
    end)

    alphaSlider:HookScript("OnShow", function() C_Timer.After(0.02, UpdateFill) end)
    C_Timer.After(0.1, UpdateFill)

    y.v = y.v - 40
    MakeDesc(settingsChild, y,
        "Controls the background opacity of the main Priestly frame and popover.", 4)

    y.v = y.v - 6
    MakeCheckbox(settingsChild, y, "Lock frame position", "lockFrame")
    MakeDesc(settingsChild, y,
        "Stops the window being dragged by the header. |cff999999/priestly reset|r still recentres "
        .. "it, so a locked window can always be recovered.")
    MakeCheckbox(settingsChild, y, "Show click hints on mouseover", "showClickHints")
    MakeDesc(settingsChild, y,
        "Hovering a row explains what each mouse button will cast, and on whom. What left-click "
        .. "does depends on which spells you know, so it is worth reading once.")

    y.v = y.v - 10
    local sideLabel = settingsChild:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    sideLabel:SetPoint("TOPLEFT", settingsChild, "TOPLEFT", 0, y.v)
    sideLabel:SetText("Popover Side")
    -- Reserve the label's own height, as every sibling does. MakeRadioGroup
    -- anchors a ~20px button by its TOPLEFT and only subtracts 4 of its own,
    -- so a smaller step here puts the first radio through the label.
    y.v = y.v - 18

    MakeRadioGroup(settingsChild, y, {
        { key = "auto",  label = "Automatic - open it wherever there is room" },
        { key = "left",  label = "Always on the left" },
        { key = "right", label = "Always on the right" },
    }, Priestly_PopoverSide(), function(key)
        Priestly_SetConfig("popoverSide", key)
        -- The side is chosen fresh every time the popover opens, so the next
        -- hover would pick this up on its own. The rebuild is for the popover
        -- that is open right now: UpdateUI re-anchors it, so the change shows
        -- without having to move the mouse away and back.
        if Priestly_ForceRebuild then Priestly_ForceRebuild() end
    end)

    MakeDesc(settingsChild, y,
        "Which side of the frame the per-member popover opens on. Automatic follows the frame: "
        .. "put Priestly on the left of your screen and the popover opens to the right.", 4)

    settingsChild:SetHeight(math.abs(y.v) + 20)

    -- ═════════════════════════════════════════════════════════════════════════
    -- TAB 2: Instances
    -- ═════════════════════════════════════════════════════════════════════════

    local instContainer = CreateFrame("Frame", "PriestlyInstanceContainer", panel)
    instContainer:SetPoint("TOPLEFT", panel, "TOPLEFT", 14, CONTENT_TOP)
    instContainer:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -14, 10)
    tabFrames[2] = instContainer

    BuildInstanceTab(instContainer, INSTANCE_DB, PANEL_W)

    -- ── Default to Settings tab ─────────────────────────────────────────────
    SelectTab(1)
end

panel:SetScript("OnShow", function(self) BuildPanel(self) end)

-- ─── Register ───────────────────────────────────────────────────────────────

-- Retail's Settings framework only. InterfaceOptions_AddCategory belongs to
-- the UI this client replaced.
local function RegisterPanel()
    if Settings and Settings.RegisterCanvasLayoutCategory then
        local category = Settings.RegisterCanvasLayoutCategory(panel, panel.name)
        Settings.RegisterAddOnCategory(category)
        panel._category = category
    end
end

local regFrame = CreateFrame("Frame")
Priestly.RegisterEvents(regFrame, "PLAYER_LOGIN")
regFrame:SetScript("OnEvent", function()
    Priestly_EnsureDefaults()
    RegisterPanel()
end)

function Priestly_OpenConfig()
    if Settings and Settings.OpenToCategory and panel._category then
        Settings.OpenToCategory(panel._category:GetID())
    else
        DEFAULT_CHAT_FRAME:AddMessage(
            "|cff99ddff[Priestly]|r Options are in Game Menu > Options > AddOns > Priestly.")
    end
end

-- ─── Test seam ───────────────────────────────────────────────────────────────

Priestly._testConfig = {
    TextHeight    = TextHeight,
    reportedUnknown = function() return g_ReportedUnknown end,
    INSTANCE_DB   = INSTANCE_DB,
    DEFAULTS      = DEFAULTS,
    FLAVOR        = FLAVOR,
    DurationStore = DurationStore,
    CheckCurrentInstance = CheckCurrentInstance,
    inShadowInstance = function() return g_InShadowInstance end,
    MEASURED_ON_BUILD = MEASURED_ON_BUILD,
    SV_BROKEN_ON_BUILD = SV_BROKEN_ON_BUILD,
}
