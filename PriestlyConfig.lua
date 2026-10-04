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
    frameScale      = 1.00,
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

-- ─── One write path for PriestlyAccountDB ─────────────────────────────────────────────
--
-- Nothing an addon wrote survived a real client restart until build 70009,
-- which fixed it - account-wide and per-character SavedVariables both. CVars
-- have NOT been re-measured there and did not persist through 69977 (issue
-- #9, docs/FOREVER-PROBE.md section 11). Players on an older build still lose
-- everything, so the single write path below stays as it is; issue #9 is
-- where moving back to account-wide storage gets decided. Until then,
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
-- file writes PriestlyAccountDB or PriestlyDB directly except inside a
-- `config-owner` region - the code that creates the tables, seeds defaults,
-- runs migrations and keeps the learned-duration cache. Everything else calls
-- one of the setters below.

-- Which build Priestly's notes on this beta were measured on, and the build
-- where SavedVariables are measured broken. In the SOURCE, because it is the
-- one thing that survives a restart here. Bump MEASURED_ON_BUILD after
-- re-measuring (AGENTS.md); the library warns at every real login until then,
-- in a development copy only - a release keeps quiet (IsDevelopmentCopy).
--
-- These two are INDEPENDENT, and right now they differ. The installed client
-- is 70009 (.build.info, wow_classic_beta 1.60.1.70009), patched 2026-09-24.
-- MEASURED_ON_BUILD is 70009 as of 2026-09-25: /apidump, /pprobe including
-- aura secrecy in a real fight and secure click-casting on both mouse edges,
-- and the SavedVariables check. There is no companion constant for the
-- settings check any more: as of LibGroupBuffs r14 it works that out from the
-- marker's own recorded build, so nothing here has to be kept current for it.
--
-- What moving it took, since a dump comparison would not have done: 69913
-- and 69977 had identical documented sets, but 70009 adds, removes and
-- changes signatures (docs/FOREVER-PROBE.md, top). Nothing this addon calls
-- was removed - and matching declarations could never have shown that aura
-- secrecy in combat or secure click-casting still behave the same way. Those
-- were measured in game, which is the only thing that settles them.
--
-- When the client next patches, the notice starts again in dev and stays until
-- someone repeats all of it. Silencing it by bumping this constant without
-- re-measuring is the one thing not to do: it is the only reminder that the
-- notes describe a client nobody is running.
--
-- Saved settings were broken through 69977 and load again on 70009
-- (docs/FOREVER-PROBE.md section 11). Priestly used to carry that build as
-- SV_BROKEN_ON_BUILD and hand it to the library, which trusted a returning
-- marker on every build except that one - so every relog on a build the
-- constant did not name announced a fix that had not happened, in three
-- addons at once.
--
-- r14 removed the need: the marker records the build it was written on, a
-- build only changes when the client is patched, and a patch requires a full
-- exit - so a marker returning under a DIFFERENT build proves the restart by
-- itself, with nothing here to keep current. The constant is gone rather than
-- left passed-and-ignored, because a dead build number invites exactly the
-- bump that caused the bug.
--
-- The test pins this literally, so a build that moves on cannot pass by
-- agreeing with itself.
local MEASURED_ON_BUILD = "70009"

-- ─── Where settings live, and how they got there ──────────────────────────────
--
-- PriestlyAccountDB, account-wide: settings are shared by every character on
-- the account. That is where they were before #8 moved them, because this
-- client wrote account-wide SavedVariables and never read them back - so
-- per-character storage was a workaround for a client bug. Build 70009 fixed
-- the bug (#9, docs/FOREVER-PROBE.md section 11).
--
-- PriestlyDB, per character, is that workaround's data. It is still DECLARED
-- in the TOC, deliberately: it is the only way to read what a player already
-- configured, and a variable the TOC stops declaring may never be handed back
-- at all. Priestly never writes a settings key to it again, so it stays as it
-- was - a backup, and what `/priestly adopt` re-seeds from.
--
-- Which character wins, when several were configured differently? The first
-- one logged in after this update seeds the shared table, and no later
-- character overwrites it. That is the only rule this code CAN implement -
-- one character's file is all the client hands over - and it is the one a
-- player can steer: log in as the character whose setup you want, run
-- `/priestly adopt`.
--
-- The per-character table is not only history: this character's window state
-- lives there too, because whether the window is open is not something to
-- share between characters. See Priestly_SetWindowVisible.
--
-- Between them the two tables give the load check one live table in each
-- scope, which is all PriestlySVCheck ever existed for as a store. It is
-- still DECLARED and read once, though - the account scope's "already told
-- them" latch is in it, and dropping that would announce the SavedVariables
-- fix to every existing player a second time. See InheritLoadCheck.

-- config-owner: begin
local SEED_MARKER = "seededFrom"     -- who the shared settings came from
local CHOICE_MARKER = "playerChose"  -- the player has set these up by hand
local OFFER_MARKER = "adoptOffered"  -- the one key written back to a legacy table

local function Announce(text)
    if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage("|cff99ddff[Priestly]|r " .. text)
    end
end

local function AccountStore()
    if not PriestlyAccountDB then PriestlyAccountDB = {} end
    return PriestlyAccountDB
end

-- Absent for anyone who never ran a per-character release, which is the
-- ordinary case from here on.
local function LegacyStore()
    if not PriestlyDB then PriestlyDB = {} end
    return PriestlyDB
end

-- A choice is an ACT, and its result can be a default: turn a buff off and
-- back on, or press Reset Defaults, and every value matches DEFAULTS again
-- while the player has plainly configured the shared settings. Comparing
-- values cannot see that, so the setters record that it happened - and an
-- automatic seed then declines even when nothing looks different.
local function RememberPlayerChose()
    AccountStore()
    PriestlyAccountDB[CHOICE_MARKER] = true
end

local function LoadCheckKey()
    return (Priestly.Settings and Priestly.Settings.LOAD_CHECK_KEY) or "svLoadCheck"
end

-- Cycle-safe: a saved file is text on disk and can be hand-edited or written
-- badly, and recursing off the end of the stack here would abort login before
-- defaults are backfilled - with client errors off, silently.
local function CopyValue(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local out = {}
    seen[value] = out
    for key, inner in pairs(value) do out[key] = CopyValue(inner, seen) end
    return out
end

-- config-owner: end

function Priestly_OnConfigChanged(key)
end

-- The build notice is for whoever has to re-measure, not for players: a
-- release that still runs on a newer client gains nothing from being told it
-- was tested on an older one, and what flags an addon out of date is the TOC's
-- Interface number, not this. So it speaks only in a development copy -
-- `dev` from Tools/deploy.ps1, or the raw packager token in an unpackaged
-- checkout. Read at call time, so a test can change the version.
local function IsDevelopmentCopy()
    local version = API.AddonVersion(ADDON_NAME)
    return version == "dev" or version == "@project-version@"
end


local settings = Priestly.Settings.New({
    owner = ADDON_NAME,
    scopes = {
        -- The settings store first: the library keeps its load-check marker
        -- in every scope, and watching both mechanisms is how a client that
        -- fixes one and not the other gets noticed.
        { label = "account-wide",  get = AccountStore },
        { label = "per-character", get = LegacyStore },
    },
    measuredOnBuild = MEASURED_ON_BUILD,
    report = function(text, kind)
        if not DEFAULT_CHAT_FRAME then return end
        if kind == "newBuild" and not IsDevelopmentCopy() then return end
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
    RememberPlayerChose()
    settings:Set(key, value)
end

-- One entry of the Shadow Protection instance list.
function Priestly_SetShadowInstance(name, tracked)
    RememberPlayerChose()
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
    { name = "The Barrow Deeps", category = "Raids", default = true,
      tooltip = "10 player. NEW in Forever. Encounters are not catalogued yet - pre-checked because a raid "
      .. "is where missing Shadow Protection costs the most, while an unnecessary row costs "
      .. "little." },
    { name = "Hyjal Summit", category = "Raids", default = true,
      tooltip = "20 player. NEW in Forever. Encounters are not catalogued yet - pre-checked for the same "
      .. "reason. Note this is Forever's own raid, not the TBC one of the same name." },
    { name = "Onyxia's Lair", category = "Raids", default = false,
      tooltip = "40 player. Primarily Fire damage (Breath, Fireball)." },

    -- ── Dungeons, by level ───────────────────────────────────────────
    { name = "Ragefire Chasm", category = "Dungeons", default = true,
      tooltip = "Levels 13-18. Jergosh the Invoker casts Shadow Bolt and Curse of Weakness." },
    { name = "The Hall of Thanes", category = "Dungeons", default = false,
      tooltip = "Levels 13-18. NEW in Forever. Encounters are not catalogued yet." },
    { name = "Ruins of Lordaeron", mapID = 2999, category = "Dungeons", default = false,
      tooltip = "Levels 15-20. NEW in Forever. Encounters are not catalogued yet." },
    { name = "Wailing Caverns", category = "Dungeons", default = false,
      tooltip = "Levels 15-25. Primarily Nature and poison damage." },
    { name = "The Deadmines", category = "Dungeons", default = false,
      tooltip = "Levels 18-23. Primarily physical and Fire damage." },
    { name = "Shadowfang Keep", category = "Dungeons", default = true,
      tooltip = "Levels 22-30. Arugal (Shadow Bolt, Void Bolt), Wolf Master Nandos, and shadow casters "
      .. "throughout." },
    { name = "The Stockade", category = "Dungeons", default = false,
      tooltip = "Levels 22-30. Primarily physical damage." },
    { name = "Excavation Site: Wetlands", category = "Dungeons", default = false,
      tooltip = "Levels 24-29. NEW in Forever. Encounters are not catalogued yet." },
    { name = "Blackfathom Deeps", category = "Dungeons", default = false,
      tooltip = "Levels 24-32. Twilight Lord Kelris casts Mind Blast; the rest is Nature and Frost." },
    { name = "City of Dalaran", category = "Dungeons", default = false,
      tooltip = "Levels 28-33. NEW in Forever. Encounters are not catalogued yet." },
    { name = "Scarlet Monastery", category = "Dungeons", default = true,
      tooltip = "Levels 28-45, all four wings. Bloodmage Thalnos (Shadow Bolt) in the Graveyard; the "
      .. "Armory and Cathedral are physical. One entry because GetInstanceInfo() reports every "
      .. "wing under the same name." },
    { name = "Gnomeregan", category = "Dungeons", default = false,
      tooltip = "Levels 29-38. Primarily Nature, Fire and mechanical damage." },
    { name = "Razorfen Kraul", category = "Dungeons", default = false,
      tooltip = "Levels 30-40. Primarily Nature and poison damage." },
    { name = "The Drowned City", category = "Dungeons", default = false,
      tooltip = "Levels 35-40. NEW in Forever. Encounters are not catalogued yet." },
    { name = "Krol'Dok Stronghold", category = "Dungeons", default = false,
      tooltip = "Levels 40-45. NEW in Forever. Encounters are not catalogued yet." },
    { name = "Razorfen Downs", category = "Dungeons", default = true,
      tooltip = "Levels 40-50. Amnennar the Coldbringer deals Shadow and Frost damage; the rest is Nature." },
    { name = "Uldaman", category = "Dungeons", default = false,
      tooltip = "Levels 42-52. Primarily physical, Nature and Arcane damage." },
    { name = "Zul'Farrak", category = "Dungeons", default = true,
      tooltip = "Levels 44-54. Witch Doctor Zum'rah casts Shadow Bolt; the rest is Nature and physical." },
    { name = "Maraudon", category = "Dungeons", default = false,
      tooltip = "Levels 45-57, all entrances. Princess Theradras has a Shadow component; the rest is "
      .. "Nature. One entry: GetInstanceInfo() does not distinguish the entrances." },
    { name = "Alcaz Prison", category = "Dungeons", default = false,
      tooltip = "Levels 48-53. NEW in Forever. Encounters are not catalogued yet." },
    { name = "The Temple of Atal'Hakkar", category = "Dungeons", default = true,
      tooltip = "Levels 50-60. Shade of Eranikus (Shadow Bolt Volley), Jammal'an the Prophet (Shadow "
      .. "Bolt). Known to players as the Sunken Temple." },
    { name = "Blackrock Depths", category = "Dungeons", default = false,
      tooltip = "Levels 52-60. Ambassador Flamelash and scattered shadow casters. Generally not required." },
    { name = "Blackrock Spire", category = "Dungeons", default = false,
      tooltip = "Levels 55-60, Lower and Upper. Some shadow casters, generally not required. One entry "
      .. "because both halves share an instance name." },
    { name = "Blackmaw Hold", category = "Dungeons", default = false,
      tooltip = "Levels 55-60. NEW in Forever. Encounters are not catalogued yet." },
    { name = "Dire Maul", category = "Dungeons", default = true,
      tooltip = "Levels 58-60, all wings. Immol'thar (Shadow Bolt, Portal of Immol'thar); the West wing "
      .. "warlocks cast Shadow throughout." },
    { name = "Scholomance", category = "Dungeons", default = true,
      tooltip = "Levels 58-60. Darkmaster Gandling, Rattlegore, and heavy shadow trash throughout." },
    { name = "Stratholme", category = "Dungeons", default = true,
      tooltip = "Levels 58-60, both sides. Baron Rivendare (Shadow Bolt), Baroness Anastari (Shadow Bolt), "
      .. "undead shadow casters throughout." },
    { name = "Shaper's Terrace", category = "Dungeons", default = false,
      tooltip = "Levels 58-60. NEW in Forever. Encounters are not catalogued yet." },
}

-- ─── Ensure defaults ────────────────────────────────────────────────────────

local FLAVOR = "forever"

-- Resolved once per session (see Priestly_EnsureDefaults) so that learning a
-- duration does not call GetBuildInfo for every member of every group.
local g_Build

-- config-owner: begin
-- Did a release configure this table? Any setting, the instance list or a
-- saved position says yes.
--
-- Configured means DIFFERENT FROM THE DEFAULTS, not merely present. The
-- per-character releases ran EnsureDefaults on every character, priest or
-- not, so every one of them has a PriestlyDB holding the whole DEFAULTS table
-- and the whole instance list. Treating a key's presence as evidence let an
-- alt nobody ever configured claim the shared settings and lock the real ones
-- out - the same failure as the first attempt, which used `flavor`: that is
-- stamped at login too. `flavor` is doubly wrong as the test, since a TBC-era
-- profile has none at all - its absence is what triggers that migration - so
-- the profile most in need of carrying across was the one refused.
local function LooksConfigured(t)
    if type(t) ~= "table" then return false end
    for key, default in pairs(DEFAULTS) do
        if t[key] ~= nil and t[key] ~= default then return true end
    end
    if t.pos ~= nil then return true end
    if type(t.shadowInstances) == "table" then
        local default = {}
        for _, entry in ipairs(INSTANCE_DB) do default[entry.name] = entry.default end
        for name, tracked in pairs(t.shadowInstances) do
            -- A name this build does not know is a TBC-era choice, and the
            -- player made it; anything else counts only if it differs.
            if default[name] == nil then
                if tracked then return true end
            elseif tracked ~= default[name] then
                return true
            end
        end
    end
    return false
end

-- Never carried across. The load check's marker describes the table it lives
-- in; `visible` is this session's window state, and one character closing the
-- window must not close it for everybody; the two markers are bookkeeping.
local function Carried(key)
    return key ~= LoadCheckKey() and key ~= "visible" and key ~= SEED_MARKER
        and key ~= OFFER_MARKER and key ~= CHOICE_MARKER and key ~= "flavor"
end

-- Settings a player would recognise as theirs - what the count reports.
-- `learnedDurations` is a cache the addon rebuilds, and the flavor migration
-- may drop it moments later, so counting it would overstate what was kept.
local function Countable(key)
    return DEFAULTS[key] ~= nil or key == "pos" or key == "shadowInstances"
end

-- Copy this character's old settings into the shared table. `force` is
-- `/priestly adopt`: the player saying this character's setup is the one they
-- want everywhere. Returns how many settings were applied.
--
-- Writes go to PriestlyAccountDB by name, not through a local alias: the
-- scanner in tests/config_scan.lua reads source text and cannot follow an
-- alias, and an unseen write is how this file's one rule gets broken quietly.
local function AdoptCharacterSettings(force)
    local legacy = PriestlyDB
    if not LooksConfigured(legacy) then return 0 end
    AccountStore()
    if not force then
        if PriestlyAccountDB[SEED_MARKER] ~= nil then return 0 end
        -- Nobody seeded, but the shared settings are not untouched either:
        -- an alt logged in first and the player then changed something in the
        -- options panel. Those are deliberate choices about the shared table,
        -- and a character logging in later must not silently undo them. The
        -- same test as for a legacy table - different from the defaults -
        -- because that is what "somebody chose this" means either side.
        if PriestlyAccountDB[CHOICE_MARKER] or LooksConfigured(PriestlyAccountDB) then
            return 0
        end
    end

    local applied = 0
    -- Replace, not merge. A key this character never set must fall back to
    -- the default rather than keep whichever other character's value happens
    -- to be sitting there - "use this character's settings" has to mean it.
    for key, default in pairs(DEFAULTS) do
        if legacy[key] == nil and PriestlyAccountDB[key] ~= default then
            PriestlyAccountDB[key] = default
            applied = applied + 1
        end
    end
    -- The optional keys have no default to fall back to, so they are cleared:
    -- a window position, an instance list or a duration cache this character
    -- never had must not be left standing from whoever seeded first.
    -- EnsureDefaults rebuilds the instance list from INSTANCE_DB afterwards.
    for _, key in ipairs({ "pos", "shadowInstances", "learnedDurations" }) do
        if legacy[key] == nil and PriestlyAccountDB[key] ~= nil then
            PriestlyAccountDB[key] = nil
            if Countable(key) then applied = applied + 1 end
        end
    end
    for key, value in pairs(legacy) do
        if Carried(key) then
            PriestlyAccountDB[key] = CopyValue(value)
            if Countable(key) then applied = applied + 1 end
        end
    end
    -- Carried deliberately, nil included: a table from the TBC line has no
    -- flavor, and copying that absence is what re-runs the migration over the
    -- instance names and learned durations it just brought with it.
    PriestlyAccountDB.flavor = legacy.flavor
    PriestlyAccountDB[SEED_MARKER] =
        (GetUnitName and GetUnitName("player", false)) or "another character"
    -- Nothing left to offer THIS character: the shared settings are its own.
    if type(PriestlyDB) == "table" then PriestlyDB[OFFER_MARKER] = true end
    return applied
end

-- ─── Window state stays with the character ───────────────────────────────────
--
-- Whether the window is open is not a preference to share: it is where you
-- left it on THIS character, and a priest you park in a city should not close
-- the window for the one you raid on. So it lives in the per-character table,
-- which is the one thing that table holds going forward. The seed leaves
-- `visible` behind for the same reason, and an upgrading character keeps its
-- own because that is where it already was.
function Priestly_WindowVisible()
    local per = LegacyStore()
    return per.visible
end

function Priestly_SetWindowVisible(visible)
    local per = LegacyStore()
    if per.visible == visible then return end
    per.visible = visible
    settings:Changed("visible")
end

-- The account scope's load-check history used to live in PriestlySVCheck,
-- which existed only to give that scope a table. Carry its marker over, or
-- the move throws away the latch saying this player was already told the
-- settings bug was fixed - and the next client patch tells them again.
local function InheritLoadCheck()
    local previous = PriestlySVCheck
    if type(previous) ~= "table" then return end
    local key = LoadCheckKey()
    if PriestlyAccountDB[key] == nil and type(previous[key]) == "table" then
        PriestlyAccountDB[key] = CopyValue(previous[key])
    end
end

function Priestly_EnsureDefaults()
    if not PriestlyAccountDB then PriestlyAccountDB = {} end
    -- Both tables: the shared settings, and the per-character one that holds
    -- this character's window state.
    LegacyStore()
    InheritLoadCheck()
    -- BEFORE the defaults below: the seed replaces a key this character never
    -- set with the DEFAULT, and it can only tell which those are while the
    -- backfill has not filled them all in.
    local seeded = AdoptCharacterSettings(false) > 0
    if seeded then
        Announce("Your settings are shared by all your characters again, starting from "
            .. tostring(PriestlyAccountDB[SEED_MARKER]) .. "'s. |cffffffff/priestly adopt|r "
            .. "on another character uses that one's instead.")
    end
    -- Nothing was taken, but this character has settings of its own: say so
    -- once, or the only sign is an addon that looks reset. Marked in the
    -- character's own table - the one bookkeeping key it ever gets - so it is
    -- said once per character rather than at every login.
    if not seeded and LooksConfigured(PriestlyDB) and PriestlyDB[OFFER_MARKER] == nil then
        PriestlyDB[OFFER_MARKER] = true
        local from = PriestlyAccountDB[SEED_MARKER]
        Announce("This character has its own settings saved from before they were shared. "
            .. (from and ("The shared ones came from " .. tostring(from) .. "; ")
                     or "The shared ones are the ones already set up; ")
            .. "|cffffffff/priestly adopt|r uses this character's for everyone instead.")
    end
    -- A client build can only change across a restart, which means a fresh
    -- login, which means this runs again. Re-resolving here is what keeps the
    -- cached build honest while keeping GetBuildInfo off the aura hot path.
    g_Build = nil
    for k, v in pairs(DEFAULTS) do
        if PriestlyAccountDB[k] == nil then
            PriestlyAccountDB[k] = v
        end
    end

    if PriestlyAccountDB.shadowInstances == nil then
        PriestlyAccountDB.shadowInstances = {}
    end

    -- One-time migration off the TBC line: drop the instances that build knew
    -- about, and the durations it learned, neither of which mean anything here.
    if PriestlyAccountDB.flavor ~= FLAVOR then
        local known = {}
        for _, entry in ipairs(INSTANCE_DB) do known[entry.name] = true end
        for name in pairs(PriestlyAccountDB.shadowInstances) do
            if not known[name] then PriestlyAccountDB.shadowInstances[name] = nil end
        end
        PriestlyAccountDB.learnedDurations = nil
        PriestlyAccountDB.flavor = FLAVOR
    end

    -- Deliberately NOT pruning unknown keys on every load. An entry the current
    -- list does not name is inert - nothing reads shadowInstances except
    -- CheckCurrentInstance, which looks up the zone you are standing in - so
    -- pruning buys tidiness and costs real data: install an older build once,
    -- or hand-edit an instance the list is missing, and every choice for those
    -- entries is gone with no way to get it back.

    -- Backfill instances added since this profile was written
    for _, entry in ipairs(INSTANCE_DB) do
        if PriestlyAccountDB.shadowInstances[entry.name] == nil then
            PriestlyAccountDB.shadowInstances[entry.name] = entry.default
        end
    end

    PriestlyAccountDB.shadowBosses = nil  -- migration
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
    if not PriestlyAccountDB then return nil end
    if not g_Build then g_Build = (API and API.ClientBuild()) or "?" end
    local store = PriestlyAccountDB.learnedDurations
    if not store or store.build ~= g_Build then
        store = { build = g_Build }
        PriestlyAccountDB.learnedDurations = store
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

-- Which INSTANCE_DB entry we are standing in, by the client's own id where
-- we have one and by name otherwise.
--
-- The id is the point of the exercise: it is identical in every locale, and a
-- French client returns French instance names, so name matching has been
-- broken for everyone not playing in English since the feature existed. It is
-- also verifiable - a name one character off fails silently, while an id
-- either matches or does not, and `/pprobe here` prints it.
--
-- Only one id is measured so far (Ruins of Lordaeron, 2999): almost every
-- zone in the list is above the current level cap. So the name is still the
-- fallback, and an entry gains its id the day somebody stands in it.
local function FindInstanceEntry(name, mapID)
    if mapID and mapID ~= 0 then
        for _, entry in ipairs(INSTANCE_DB) do
            if entry.mapID == mapID then return entry end
        end
    end
    for _, entry in ipairs(INSTANCE_DB) do
        if entry.name == name then return entry end
    end
end

local function CheckCurrentInstance()
    -- Out in the world this returns the CONTINENT ("Eastern Kingdoms" while
    -- standing in Undercity), not an empty string, so the name alone is not a
    -- test for "am I in an instance". instanceType is "none" outdoors and
    -- "party"/"raid" inside one - gate on that rather than relying on the
    -- continent never matching an entry in INSTANCE_DB.
    local name, instanceType = GetInstanceInfo()
    local mapID = select(8, GetInstanceInfo())
    if not name or name == "" or instanceType == "none" then
        g_InShadowInstance = false
        return
    end

    -- Saved settings stay keyed on the entry's NAME, which is Priestly's own
    -- English constant and not the string the client hands back. So a player's
    -- choices survive this change, and survive an id being filled in later.
    local entry = FindInstanceEntry(name, mapID)
    local saved = PriestlyAccountDB and PriestlyAccountDB.shadowInstances
    g_InShadowInstance = (entry and saved and saved[entry.name] == true) or false

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
    local modeActive = PriestlyAccountDB and PriestlyAccountDB.shadowMode == "instance"
    if relevantType and modeActive and not entry and not g_ReportedUnknown[name] then
        g_ReportedUnknown[name] = true
        if DEFAULT_CHAT_FRAME then
            -- The id as well as the name, because the id is the half that can
            -- be trusted: it is the same in every language, and pasting it
            -- into a report is enough to add the entry correctly for
            -- everybody. The name alone only fixes English clients.
            DEFAULT_CHAT_FRAME:AddMessage(
                "|cff99ddff[Priestly]|r does not recognise this instance: |cffffffff\"" ..
                tostring(name) .. "\"|r (id |cffffffff" .. tostring(mapID) ..
                "|r) - Shadow Protection's \"by instance\" mode cannot " ..
                "work here. Please report that id so it can be added.")
        end
    end
end

-- `/priestly adopt`: use THIS character's pre-70009 settings everywhere.
-- Only reachable for someone who configured this character under a
-- per-character release; for everyone else there is nothing to adopt and it
-- says so rather than pretending.
--
-- Returns how many settings were applied, and whether the options panel is
-- showing stale widgets: it is built once and its controls keep the values
-- they were built with, so the honest thing is to say a reload is needed
-- rather than silently leave the panel disagreeing with the addon.
function Priestly_AdoptCharacterSettings()
    local applied = AdoptCharacterSettings(true)
    if applied == 0 then return 0, false end

    -- The flavor migration may prune what was just copied, so run it before
    -- anything reads the result.
    Priestly_EnsureDefaults()
    CheckCurrentInstance()

    -- Report every key, so anything watching settings sees them all - the
    -- list is snapshotted first, because the hook is an extension point and
    -- one that writes a key would otherwise be mutating what we iterate.
    local keys = {}
    for key in pairs(PriestlyAccountDB) do keys[#keys + 1] = key end
    for _, key in ipairs(keys) do settings:Changed(key) end

    if Priestly_ApplyAlpha then Priestly_ApplyAlpha() end
    if Priestly_ForceRebuild then Priestly_ForceRebuild() end
    return applied, Priestly_ConfigPanelBuilt()
end

function Priestly_ShouldShowShadow(groups, ord)
    if not PriestlyAccountDB then return false end
    local mode = PriestlyAccountDB.shadowMode or "detect"
    if mode == "always" then return true end
    if mode == "detect" then
        -- Names come from Priestly.lua's DEFS, which resolves them from spell
        -- IDs at runtime, so this stays correct in every locale.
        local names = Priestly.shadowAuraNames
        -- Through the engine, so these reads join the aura pass the window
        -- opens around a rebuild. This runs from ActiveDefs, immediately
        -- before the rows ask about the same members: on a 40-man raid where
        -- nobody has the buff, that used to be a second walk of every member
        -- (#6).
        --
        -- No guard on either of those. RefreshSpellData publishes
        -- Priestly.engine BEFORE Priestly.shadowAuraNames, so `names` being
        -- set is already proof the engine is; and ReadAura arrived in r25,
        -- which PriestlyCompat's NEEDS_MINOR refuses to start below. Both
        -- checks were here while the pin was r24 and both are dead now.
        if groups and ord and names then
            local eng = Priestly.engine
            for _, gn in ipairs(ord) do
                for _, m in ipairs(groups[gn] or {}) do
                    local status = eng:ReadAura(m.unit, names)
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
    return PriestlyAccountDB and PriestlyAccountDB.trackPets ~= false
end

function Priestly_IsBuffEnabled(defId)
    if not PriestlyAccountDB then return true end
    if defId == "fort"   then return PriestlyAccountDB.trackFort   ~= false end
    if defId == "spirit" then return PriestlyAccountDB.trackSpirit  ~= false end
    return true
end

function Priestly_GetFrameAlpha()
    return PriestlyAccountDB and PriestlyAccountDB.frameAlpha or 0.96
end

-- How large the window is drawn. 1.00 is the size Priestly has always been, so
-- an upgrading player sees no change until they move the slider. The library
-- clamps whatever it gets, which is what protects the window from a 0 here.
function Priestly_GetFrameScale()
    return PriestlyAccountDB and PriestlyAccountDB.frameScale or 1.00
end

-- True when the window must not be dragged. Checked in the drag handler
-- rather than by unregistering the drag, which keeps this clear of the secure
-- frame rules and safe to toggle in combat.
function Priestly_FrameLocked()
    return PriestlyAccountDB and PriestlyAccountDB.lockFrame == true
end

-- Whether a row explains what its clicks will cast, on hover.
function Priestly_ShowClickHints()
    return not (PriestlyAccountDB and PriestlyAccountDB.showClickHints == false)
end

-- "auto" | "left" | "right". Auto means "wherever there is room", decided
-- fresh each time the popover opens - see PopoverSide in Priestly.lua.
function Priestly_PopoverSide()
    return (PriestlyAccountDB and PriestlyAccountDB.popoverSide) or "auto"
end

function Priestly_ShowSolo()
    return PriestlyAccountDB and PriestlyAccountDB.showSolo == true
end

-- ─── Has Blizzard fixed it? Did the client update? ──────────────────────────
--
-- Both checks live in LibGroupBuffs-1.0's Settings.lua. The load check keeps a
-- `svLoadCheck` marker in each scope - written every session, never in
-- DEFAULTS - and says so once when one comes back carrying a build OTHER than
-- the one running, which only a patched client can produce. The build check
-- warns at every real login on a build other than MEASURED_ON_BUILD,
-- deliberately unlatched - in a development copy only (IsDevelopmentCopy).

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
        -- A rebuild, not a refresh. A refresh never opens a closed window, and
        -- zoning is exactly when a row can APPEAR: with Shadow Protection set
        -- to "by instance", a window that closed itself outdoors for want of
        -- rows has one again the moment you step into a checked instance.
        -- ScheduleRefresh left it shut until some unrelated event happened to
        -- fire. Magely already rebuilds here, for this reason.
        if Priestly_ForceRebuild then Priestly_ForceRebuild() end
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
    cb:SetChecked(PriestlyAccountDB[dbKey] ~= false)
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

-- A labelled slider with its own track, fill and value readout.
--
-- Template-free: OptionsSliderTemplate belongs to the Classic options UI and
-- is not guaranteed here, so the track and fill are ours and the Slider frame
-- only carries a thumb and the input handling.
--
-- Written as a builder the day a SECOND slider was needed, rather than copied.
-- Two copies of sixty lines is how the window policy came to hold seven
-- defects in three addons (LibGroupBuffs#22).
local function MakeSlider(parent, y, opt)
    local SLIDER_W = 220

    local label = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, y.v)
    label:SetText(opt.label)
    y.v = y.v - 18

    local trackBg = parent:CreateTexture(nil, "BACKGROUND")
    trackBg:SetColorTexture(0.10, 0.10, 0.18, 0.95)
    trackBg:SetSize(SLIDER_W, 10)
    trackBg:SetPoint("TOPLEFT", parent, "TOPLEFT", 8, y.v - 6)

    for _, info in ipairs({
        { "TOPLEFT", "TOPRIGHT" },
        { "BOTTOMLEFT", "BOTTOMRIGHT" },
    }) do
        local t = parent:CreateTexture(nil, "BORDER")
        t:SetColorTexture(0.35, 0.35, 0.55, 0.80)
        t:SetHeight(1)
        t:SetPoint(info[1], trackBg, info[1])
        t:SetPoint(info[2], trackBg, info[2])
    end
    for _, side in ipairs({ "LEFT", "RIGHT" }) do
        local t = parent:CreateTexture(nil, "BORDER")
        t:SetColorTexture(0.35, 0.35, 0.55, 0.80)
        t:SetWidth(1)
        t:SetPoint("TOP" .. side, trackBg, "TOP" .. side)
        t:SetPoint("BOTTOM" .. side, trackBg, "BOTTOM" .. side)
    end

    local trackFill = parent:CreateTexture(nil, "ARTWORK")
    trackFill:SetColorTexture(0.40, 0.40, 0.72, 0.75)
    trackFill:SetPoint("TOPLEFT", trackBg, "TOPLEFT", 1, -1)
    trackFill:SetHeight(8)

    local slider = CreateFrame("Slider", opt.name, parent)
    slider:SetPoint("TOPLEFT", parent, "TOPLEFT", 4, y.v)
    slider:SetSize(SLIDER_W + 8, 18)
    slider:SetOrientation("HORIZONTAL")
    slider:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
    local thumb = slider:GetThumbTexture()
    if thumb then thumb:SetSize(16, 18) end
    slider:SetMinMaxValues(opt.min, opt.max)
    slider:SetValueStep(opt.step)
    if slider.SetObeyStepOnDrag then slider:SetObeyStepOnDrag(true) end

    local function saved()
        local v = PriestlyAccountDB and PriestlyAccountDB[opt.key]
        return type(v) == "number" and v or opt.default
    end
    slider:SetValue(saved())

    local lowTxt = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    lowTxt:SetPoint("TOPLEFT", slider, "BOTTOMLEFT", 2, 2)
    lowTxt:SetText(opt.lowText)
    local highTxt = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    highTxt:SetPoint("TOPRIGHT", slider, "BOTTOMRIGHT", -2, 2)
    highTxt:SetText(opt.highText)

    local valTxt = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    valTxt:SetPoint("LEFT", slider, "RIGHT", 10, 0)
    valTxt:SetText(opt.format(saved()))

    local function UpdateFill()
        local lo, hi = slider:GetMinMaxValues()
        local pct = (slider:GetValue() - lo) / (hi - lo)
        trackFill:SetWidth(math.max(1, pct * (SLIDER_W - 2)))
    end

    -- Snapped to the step here as well as on the slider: SetValueStep does not
    -- bind on every path, and a value between steps writes a setting no other
    -- control can produce.
    local snap = 1 / opt.step
    slider:SetScript("OnValueChanged", function(self, value)
        value = math.floor(value * snap + 0.5) / snap
        Priestly_SetConfig(opt.key, value)
        valTxt:SetText(opt.format(value))
        UpdateFill()
        if opt.onChange then opt.onChange(value) end
    end)

    slider:HookScript("OnShow", function() C_Timer.After(0.02, UpdateFill) end)
    C_Timer.After(0.1, UpdateFill)

    y.v = y.v - 40
    if opt.desc then MakeDesc(parent, y, opt.desc, 4) end
    return slider
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
        local cat = entry.category
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
            local instName    = entry.name
            local tooltip     = entry.tooltip or ""
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
            icb:SetChecked(PriestlyAccountDB.shadowInstances[instName] == true)
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
            Priestly_SetShadowInstance(entry.name, true)
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
            Priestly_SetShadowInstance(entry.name, false)
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
            Priestly_SetShadowInstance(entry.name, entry.default)
        end
        for _, cb in ipairs(allCheckboxes) do
            if cb._instName then
                for _, entry in ipairs(instanceDB) do
                    if entry.name == cb._instName then
                        cb:SetChecked(entry.default)
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
    }, PriestlyAccountDB.shadowMode, function(key)
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
    MakeSlider(settingsChild, y, {
        name    = "PriestlyAlphaSlider",
        label   = "Frame Opacity",
        key     = "frameAlpha",
        min     = 0.20, max = 1.00, step = 0.05, default = 0.96,
        format  = function(v) return string.format("%d%%", v * 100) end,
        lowText = "20%", highText = "100%",
        desc    = "Controls the background opacity of the main Priestly frame and popover.",
        onChange = function() if Priestly_ApplyAlpha then Priestly_ApplyAlpha() end end,
    })

    MakeSlider(settingsChild, y, {
        name    = "PriestlyScaleSlider",
        label   = "Frame Size",
        key     = "frameScale",
        min     = 0.70, max = 2.00, step = 0.05, default = 1.00,
        format  = function(v) return string.format("%d%%", v * 100) end,
        lowText = "70%", highText = "200%",
        desc    = "How large the window is drawn. Priestly's sizes were chosen for a different "
            .. "client, and this one's interface scale can make them look small - so this is here "
            .. "rather than asking you to change the game's whole UI scale.",
        -- A rebuild rather than applying it here: both frames parent secure
        -- buttons, so the library refuses to resize them mid-fight and carries
        -- it out when the fight ends.
        onChange = function() if Priestly_ForceRebuild then Priestly_ForceRebuild() end end,
    })

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

-- Its controls are created once, with the values they had then, and nothing
-- re-syncs them - so a change made outside the panel leaves it disagreeing.
-- `/priestly adopt` asks this so it can say a reload is needed rather than
-- let the panel quietly lie.
function Priestly_ConfigPanelBuilt()
    return panel._built == true
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
    -- The key that records which character the shared settings came from.
    -- Exported so a test names it once rather than spelling it everywhere.
    SEED_MARKER = SEED_MARKER,
    CHOICE_MARKER = CHOICE_MARKER,
}
