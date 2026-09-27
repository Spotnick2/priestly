------------------------------------------------------------
-- test_config_seam.lua - one write path for PriestlyAccountDB, and the two checks
-- that watch for the client being fixed or updated (issue #35).
--
-- Nothing an addon wrote survived a real restart until build 70009 fixed it.
-- Every settings change still goes through Priestly_SetConfig: players on
-- older builds are still losing everything, and the migration back to
-- account-wide storage (issue #9) then lands in one place.
--
--   & 'C:\Program Files (x86)\Lua\5.1\lua.exe' tests\test_config_seam.lua
------------------------------------------------------------

dofile("tests/wow_stubs.lua")
local H = dofile("tests/harness.lua")
local T, TC = H.loadAddon()

-- Pinned here as LITERALS, not read from the source: the checks below take
-- their builds from the constant, so a stale constant would satisfy all of
-- them while the addon warned at every real login on the build people are
-- actually running. Moving the client forward has to be a two-file edit, and
-- this is the file that says so.
--
-- MEASURED and CLIENT agree today - 70009 was re-probed in game on
-- 2026-09-25, aura secrecy in a fight and secure click-casting included - so
-- the login notice is silent. They part again the moment the client patches.
--
-- BROKEN is no longer a constant the addon declares. Since LibGroupBuffs r14
-- the settings check reads the marker's own recorded build rather than a
-- build the host names, so BROKEN here is a test fixture and means only "a
-- build older than the one running" - which is what makes a returning marker
-- news. Nothing below depends on WHICH build it is.
local MEASURED = "70009"
local BROKEN = "69977"
local CLIENT = "70009"  -- what .build.info reports; what the stub must model
local CLIENT_DATE = "Sep 23 2026"   -- what GetBuildInfo reports on it
local FIXED = "70123"   -- any build other than the three above

H.eq(TC.MEASURED_ON_BUILD, MEASURED,
    "the source says Priestly was measured on the build these tests measure it on")
-- No constant for the settings check any more: r14 reads the marker's own
-- recorded build. BROKEN below is a test fixture, not something the addon
-- declares - it is just "a build older than the one running", which is what
-- makes a returning marker news.
H.eq(TC.SV_BROKEN_ON_BUILD, nil,
    "and carries no build constant for the settings check, which r14 decides itself")

-- The stub's default build is the one every other test file runs under, so a
-- stale default quietly models a client that no longer exists - and a test
-- asserting "no build warning at a default login" would be asserting it
-- against the wrong build. AGENTS.md says to keep them equal; this is what
-- makes that true rather than remembered.
-- The stub models the CLIENT, not whichever build Priestly last re-probed:
-- it is the default every other test file runs under, so a stale one hides
-- from all of them what a player actually sees. They agree today, and the
-- notice is silent; the moment the client patches they part again, and every
-- test in the suite should see what the player sees.
WoW.reset()
H.eq(WoW.build, CLIENT, "the stub models the build the client is on")
-- The date moves with it, and was NOT pinned until a review pointed out that
-- it could drift back silently while the number stayed right. It comes from
-- GetBuildInfo in the /pprobe run, not from the executable's timestamp, which
-- is a day later and was wrong here once.
H.eq(select(3, GetBuildInfo()), CLIENT_DATE, "and the date that build reports")

------------------------------------------------------------
-- The setters
------------------------------------------------------------

WoW.reset()
PriestlyAccountDB = nil
Priestly_EnsureDefaults()

local changed = {}
local realHook = Priestly_OnConfigChanged
Priestly_OnConfigChanged = function(key) changed[#changed + 1] = key end

Priestly_SetConfig("frameAlpha", 0.5)
H.eq(PriestlyAccountDB.frameAlpha, 0.5, "SetConfig assigns")
H.eq(changed[#changed], "frameAlpha", "and reports the key")

-- Set first, so clearing it is an actual change the test can see fail.
Priestly_SetConfig("pos", { point = "RIGHT", x = 1, y = 2 })
H.check(PriestlyAccountDB.pos ~= nil, "a position is stored")
Priestly_SetConfig("pos", nil)
H.eq(PriestlyAccountDB.pos, nil, "SetConfig can clear a key that was set")
H.eq(changed[#changed], "pos", "and reports the clear")

-- An unchanged value is not a change. UpdateUI sets `visible` on every
-- refresh; without this the hook runs on the aura hot path.
local count = #changed
Priestly_SetConfig("frameAlpha", 0.5)
H.eq(#changed, count, "setting the same value again does not report")

Priestly_SetShadowInstance("Scholomance", false)
H.eq(PriestlyAccountDB.shadowInstances["Scholomance"], false, "SetShadowInstance writes one entry")
H.eq(changed[#changed], "shadowInstances", "reported under the table's own key")
count = #changed
Priestly_SetShadowInstance("Scholomance", false)
H.eq(#changed, count, "and an unchanged instance does not report either")

-- The learned-duration cache is replaced from inside a getter, so it has to
-- report there or it never reports at all.
PriestlyAccountDB.learnedDurations = { build = "old" }
count = #changed
Priestly_GetLearnedDuration("Power Word: Fortitude")
H.eq(changed[#changed], "learnedDurations", "replacing the duration cache reports")

PriestlyAccountDB = nil
Priestly_SetConfig("lockFrame", true)
H.eq(PriestlyAccountDB and PriestlyAccountDB.lockFrame, true, "SetConfig survives a missing table")

Priestly_OnConfigChanged = realHook

------------------------------------------------------------
-- The source scan
--
-- A behavioural test cannot catch a new direct write: it works perfectly well.
-- So every file the TOC loads is read, and any assignment into Priestly's
-- saved tables outside a `config-owner` region fails the run.
--
-- The scanner is LibGroupBuffs' tests/config_scan.lua, loaded from the same
-- library checkout the rest of the suite runs against (CI clones the pinned
-- tag). Its own tests cover the shapes it must catch; the cases here only
-- prove it is wired to Priestly's names.
------------------------------------------------------------

local SAVED = { "PriestlyAccountDB", "PriestlyDB" }
local CS = dofile(H.libraryRoot() .. "/tests/config_scan.lua")

H.eq(#CS.Scan("synthetic", "PriestlyAccountDB.lockFrame = true", SAVED), 1,
    "the scanner catches a direct PriestlyAccountDB write")
H.eq(#CS.Scan("synthetic", "PriestlyDB.lockFrame = true", SAVED), 1,
    "and a direct write to the legacy per-character table, which is read-only now")
H.eq(#CS.Scan("synthetic", "local p = PriestlyAccountDB.pos", SAVED), 0, "but not a read")

-- Every file the TOC loads, read from the TOC so a new one cannot be missed.
local files = H.tocFiles()
H.check(#files >= 3, "the TOC lists the addon's files: " .. table.concat(files, ", "))

-- Owner regions must stay few, or the scan stops meaning anything. Each file's
-- count is pinned, so adding one has to be done here on purpose.
local expectedRegions = { ["PriestlyConfig.lua"] = 3 }
for _, path in ipairs(files) do
    local src = H.readFile(path)
    H.check(src ~= nil, path .. " is readable")
    local bad, regions = CS.Scan(path, src or "", SAVED)
    H.check(#bad == 0, path .. " writes its saved tables only through the setters: " ..
        table.concat(bad, " | "))
    H.eq(regions, expectedRegions[path] or 0, path .. " has the expected owner regions "
        .. "(PriestlyConfig: the saved-table accessors, EnsureDefaults, the duration cache)")
end

------------------------------------------------------------
-- svLoadCheck: has Blizzard fixed it?
------------------------------------------------------------

H.eq(TC.DEFAULTS.svLoadCheck, nil,
    "svLoadCheck is NOT in DEFAULTS - if it were, EnsureDefaults would recreate it " ..
    "every session and the check could never tell a real load from a fresh start")

local function said(fromIndex)
    if #WoW.messages <= fromIndex then return "" end
    return table.concat(WoW.messages, " | ", fromIndex + 1, #WoW.messages)
end

-- Everything except the build notice, which is the OTHER detector: it fires on
-- any build but MEASURED_ON_BUILD, which currently includes the broken one.
-- The checks below are about the settings announcement, so they say so.
local function saidSettings(fromIndex)
    local out = {}
    for i = fromIndex + 1, #WoW.messages do
        if not WoW.messages[i]:find("tested on game build", 1, true) then
            out[#out + 1] = WoW.messages[i]
        end
    end
    return table.concat(out, " | ")
end

local function freshSession(build)
    WoW.reset()
    WoW.build = build
    PriestlyAccountDB, PriestlyDB = nil, nil
    Priestly_EnsureDefaults()
end

-- Today, broken build, nothing loaded: nothing announced, markers written.
freshSession(BROKEN)
local before = #WoW.messages
Priestly_HandleEnteringWorld(true, false)
H.eq(saidSettings(before), "", "no marker at login, nothing announced - today's state")
-- The two detectors, on one login: the client is on a build nobody re-probed,
-- and on that same build saved settings are known not to come back. One speaks
-- and the other stays quiet.
H.check(said(before):find("tested on", 1, true),
    "the build notice still fires on the broken build, which is not the measured one")
H.check(type(PriestlyAccountDB.svLoadCheck) == "table", "the per-character marker is written")
H.check(type(PriestlyDB.svLoadCheck) == "table",
    "and the per-character one, so both mechanisms are watched")
H.eq(PriestlyAccountDB.svLoadCheck.build, BROKEN, "with the build it was written on")

-- The broken build, marker still in memory: that is a relog or a /reload
-- being served from the client's cache. Neither may announce.
before = #WoW.messages
Priestly_HandleEnteringWorld(true, false)
H.eq(saidSettings(before), "",
    "on the broken build a returning marker is the client's cache, not a fix")
Priestly_HandleEnteringWorld(false, true)
H.eq(saidSettings(before), "", "and a /reload never announces")

-- A zone change is neither, and must not touch the marker.
local marker = PriestlyAccountDB.svLoadCheck
Priestly_HandleEnteringWorld(false, false)
H.check(PriestlyAccountDB.svLoadCheck == marker, "a zone change leaves the marker alone")

-- The fix, and what proves it: the marker comes back carrying a DIFFERENT
-- build from the one running. A build only changes when the client is
-- patched, and a patch requires a full exit, so the process that held the
-- cache is gone - which is why this can be stated plainly now instead of
-- hedged. That is the library's job as of r14; Priestly passes no constant
-- into the decision any more.
WoW.build = FIXED
before = #WoW.messages
Priestly_HandleEnteringWorld(true, false)
local msg = said(before)
H.check(msg:find("came back", 1, true), "a real login on a new build announces it: " .. msg)
H.check(msg:find(BROKEN, 1, true) and msg:find(FIXED, 1, true),
    "naming the build it was saved on and the one it was read on: " .. msg)
H.check(msg:find("fully restarted", 1, true),
    "and why that settles it - the game restarted in between: " .. msg)
H.check(msg:find("is fixed", 1, true), "so it says so plainly: " .. msg)
H.check(msg:find("per-character", 1, true) and msg:find("account-wide", 1, true),
    "naming the scopes that came back: " .. msg)
H.check(not msg:find("proves nothing", 1, true),
    "with the old hedge gone, because a relog cannot produce this: " .. msg)

-- Once: the marker is rewritten with the build running now, so every later
-- login this session reads its own build back and has nothing to report.
before = #WoW.messages
Priestly_HandleEnteringWorld(true, false)
H.check(not said(before):find("came back", 1, true), "it does not repeat at the next login")

-- One scope coming back alone is reported as that scope - the two are
-- separate mechanisms and a client can fix one without the other, which is
-- why settings live in one and the legacy table is still watched in the
-- other. The marker has to carry an OLDER build: one stamped with the build
-- already running is what a relog looks like, and r15 says nothing to that.
freshSession(FIXED)
PriestlyAccountDB = { svLoadCheck = { stamp = "then", build = BROKEN } }
before = #WoW.messages
Priestly_HandleEnteringWorld(true, false)
msg = said(before)
H.check(msg:find("account-wide", 1, true) and not msg:find("per-character", 1, true),
    "the settings store coming back alone is reported as account-wide: " .. msg)

freshSession(FIXED)
PriestlyDB = { svLoadCheck = { stamp = "then", build = BROKEN } }
before = #WoW.messages
Priestly_HandleEnteringWorld(true, false)
msg = said(before)
H.check(msg:find("per-character", 1, true) and not msg:find("account-wide", 1, true),
    "and the legacy table coming back alone is reported as per-character: " .. msg)

-- Wired to the real event, not just callable.
freshSession(BROKEN)
WoW.dispatch("PLAYER_ENTERING_WORLD", true, false)
H.check(type(PriestlyAccountDB.svLoadCheck) == "table", "PLAYER_ENTERING_WORLD drives the check")

------------------------------------------------------------
-- MEASURED_ON_BUILD: did the client update?
------------------------------------------------------------

freshSession(MEASURED)
before = #WoW.messages
Priestly_HandleEnteringWorld(true, false)
H.eq(said(before), "", "the measured build is silent")

freshSession(FIXED)
before = #WoW.messages
Priestly_HandleEnteringWorld(false, true)
H.check(not said(before):find("tested on", 1, true), "a /reload never shows the build warning")
before = #WoW.messages
WoW.dispatch("PLAYER_LOGIN")
H.check(not said(before):find("tested on", 1, true),
    "nor does PLAYER_LOGIN, which fires on /reload too")

before = #WoW.messages
Priestly_HandleEnteringWorld(true, false)
msg = said(before)
H.check(msg:find(FIXED, 1, true) and msg:find(MEASURED, 1, true),
    "a real login on a new build warns, naming both: " .. msg)
H.check(msg:find("report", 1, true), "worded for players: " .. msg)
H.check(not msg:find("pprobe", 1, true) and not msg:find("MEASURED_ON_BUILD", 1, true),
    "with no developer instructions a player cannot act on: " .. msg)

-- Not latched: it repeats at every real login until MEASURED_ON_BUILD is
-- bumped. A notice shown once and missed would leave the addon running on
-- stale findings with nothing left to say so.
before = #WoW.messages
Priestly_HandleEnteringWorld(true, false)
H.check(said(before):find("tested on", 1, true),
    "it warns again at the next real login, until someone re-measures")
H.eq(PriestlyAccountDB.warnedBuild, nil, "and records nothing that could silence it")

------------------------------------------------------------
-- Settings moved back account-wide (#9), and what that owes players
--
-- #8 moved them per character because this client never read account-wide
-- SavedVariables back. 70009 fixed that, so they are shared again - and the
-- one thing that must not happen is the move resetting a configured player,
-- which is the failure the per-character move was made to avoid in the first
-- place.
------------------------------------------------------------

-- `drop` is a list of keys to leave out. It cannot be done through `over`:
-- `{ pos = nil }` is an empty table in Lua, so an override that means "this
-- character never had one" silently means nothing at all.
local function configuredCharacter(over, drop)
    local legacy = {
        flavor = "forever",
        frameAlpha = 0.5,
        lockFrame = true,
        shadowMode = "always",
        shadowInstances = { ["Scholomance"] = true },
        learnedDurations = { build = "70009", fort = 3600 },
        pos = { point = "LEFT", x = 3, y = 4 },
    }
    for k, v in pairs(over or {}) do legacy[k] = v end
    for _, key in ipairs(drop or {}) do legacy[key] = nil end
    return legacy
end

-- The upgrade: a character configured under the per-character releases logs
-- in, and their settings become everyone's.
WoW.reset()
PriestlyAccountDB, PriestlyDB = nil, configuredCharacter()
Priestly_EnsureDefaults()
H.eq(PriestlyAccountDB.frameAlpha, 0.5, "the seed carries a changed setting across")
H.eq(PriestlyAccountDB.lockFrame, true, "including one whose default is false")
H.eq(PriestlyAccountDB.shadowMode, "always", "and a non-default choice")
H.eq(PriestlyAccountDB.shadowInstances["Scholomance"], true, "and the instance list")
H.eq(PriestlyAccountDB.learnedDurations.fort, 3600, "and what it learned about this build")
H.eq(PriestlyAccountDB.pos.x, 3, "and the window position")

-- Copied, not shared: a later change must not reach into the backup, or the
-- one thing a player can fall back on quietly tracks the thing they changed.
PriestlyAccountDB.shadowInstances["Scholomance"] = false
PriestlyAccountDB.pos.x = 99
H.eq(PriestlyDB.shadowInstances["Scholomance"], true, "the legacy instance list is untouched")
H.eq(PriestlyDB.pos.x, 3, "and so is its saved position")

-- The second character: their own old settings do NOT overwrite the shared
-- ones. Whoever logged in first decided, and silently re-deciding every login
-- would make the shared table depend on who played last.
WoW.reset()
PriestlyDB = configuredCharacter({ frameAlpha = 0.11, shadowMode = "detect" })
Priestly_EnsureDefaults()
H.eq(PriestlyAccountDB.frameAlpha, 0.5, "a second character does not overwrite the shared value")
H.eq(PriestlyAccountDB.shadowMode, "always", "nor any other key")

-- /priestly adopt is how that character wins instead, on purpose.
local copied = Priestly_AdoptCharacterSettings()
H.check(copied > 0, "adopt copies this character's settings over the shared ones")
H.eq(PriestlyAccountDB.frameAlpha, 0.11, "so the shared value is now theirs")
H.eq(PriestlyAccountDB.shadowMode, "detect", "for every key, not just the first")

-- Adopt with nothing to adopt says nothing happened rather than wiping.
WoW.reset()
PriestlyAccountDB, PriestlyDB = nil, nil
Priestly_EnsureDefaults()
PriestlyAccountDB.frameAlpha = 0.77
H.eq(Priestly_AdoptCharacterSettings(), 0, "a character with no old settings adopts nothing")
H.eq(PriestlyAccountDB.frameAlpha, 0.77, "and the shared settings are left alone")

-- A fresh install on a fixed client: nothing to seed, just defaults.
WoW.reset()
PriestlyAccountDB, PriestlyDB = nil, nil
Priestly_EnsureDefaults()
H.eq(PriestlyAccountDB.frameAlpha, TC.DEFAULTS.frameAlpha, "a first run gets the defaults")
H.eq(PriestlyAccountDB.flavor, "forever", "and the flavor marker")

-- The load check's marker must never be seeded across: it describes the table
-- it lives in, and copying one character's would claim a load that scope
-- never had.
WoW.reset()
PriestlyAccountDB = nil
PriestlyDB = configuredCharacter({ svLoadCheck = { stamp = "then", build = "69913" } })
Priestly_EnsureDefaults()
H.eq(PriestlyAccountDB.svLoadCheck, nil, "the seed leaves the load-check marker behind")

-- A per-character table the player never configured - one the load check
-- created on its own - is not a settings backup and must not seed anything.
WoW.reset()
PriestlyAccountDB = nil
PriestlyDB = { svLoadCheck = { stamp = "then", build = "70009" } }
Priestly_EnsureDefaults()
H.eq(PriestlyAccountDB.frameAlpha, TC.DEFAULTS.frameAlpha,
    "a legacy table with no settings in it seeds nothing")

-- A table with settings but NO flavor is a TBC-era profile - that absence is
-- what triggers the TBC migration - and it is the profile most in need of
-- carrying across. An earlier version of this seed used `flavor` as its
-- "somebody configured this" marker and refused exactly this case.
WoW.reset()
PriestlyAccountDB = nil
PriestlyDB = { frameAlpha = 0.2, lockFrame = true, trackSpirit = false }
Priestly_EnsureDefaults()
H.eq(PriestlyAccountDB.frameAlpha, 0.2, "a TBC-era profile, with no flavor, is carried across")
H.eq(PriestlyAccountDB.trackSpirit, false, "every setting of it")
H.eq(PriestlyAccountDB.flavor, "forever",
    "and the flavor migration then runs over what it brought")

-- Once the shared table is configured, a second character cannot fill a key
-- it happens to be missing - a setting added by a later version, or one the
-- player cleared. Whoever seeded decided; the rest is theirs to change in the
-- options panel, not to have back-filled from whichever alt logged in.
WoW.reset()
PriestlyAccountDB, PriestlyDB = nil, configuredCharacter()
Priestly_EnsureDefaults()
PriestlyAccountDB.shadowMode = nil
PriestlyDB = configuredCharacter({ shadowMode = "instance" })
Priestly_EnsureDefaults()
H.eq(PriestlyAccountDB.shadowMode, TC.DEFAULTS.shadowMode,
    "a missing key is filled by the DEFAULT, not by another character's value")


-- An alt that never configured anything must not claim the shared table. It
-- still runs EnsureDefaults at login - every character does, priest or not -
-- and the first version of this seed treated the `flavor` that writes as
-- "somebody configured this", which locked the real settings out for good.
WoW.reset()
PriestlyAccountDB, PriestlyDB = nil, nil
Priestly_EnsureDefaults()                      -- the alt logs in first
H.eq(PriestlyAccountDB.flavor, "forever", "the alt's login stamps the flavor marker")
H.eq(PriestlyAccountDB[TC.SEED_MARKER], nil, "but claims nothing to seed from")

PriestlyDB = configuredCharacter()             -- now the configured priest
Priestly_EnsureDefaults()
H.eq(PriestlyAccountDB.frameAlpha, 0.5, "so the priest's settings still come across")
H.eq(PriestlyAccountDB.lockFrame, true, "all of them")
H.check(PriestlyAccountDB[TC.SEED_MARKER] ~= nil, "and the shared table records who from")

-- `visible` is this session's window state, not a preference to share: one
-- character closing the window must not close it for every character.
WoW.reset()
PriestlyAccountDB, PriestlyDB = nil, configuredCharacter({ visible = false })
Priestly_EnsureDefaults()
H.eq(PriestlyAccountDB.visible, nil,
    "the shared table never holds the window state - it stays with the character")
H.eq(PriestlyDB.visible, false, "which is where the closed window is still recorded")

-- The account scope's load-check latch used to live in PriestlySVCheck. It is
-- not a store any more, but dropping its marker would un-latch a fix this
-- player was already told about, and the next patch would tell them again.
WoW.reset()
PriestlyAccountDB, PriestlyDB = nil, nil
PriestlySVCheck = { svLoadCheck = { stamp = "then", build = "70009", loads = true } }
Priestly_EnsureDefaults()
local inherited = PriestlyAccountDB.svLoadCheck
H.check(type(inherited) == "table", "the old marker is inherited at all")
H.eq(inherited and inherited.loads, true, "with its latch")
H.eq(inherited and inherited.build, "70009", "and the build it was written on")
PriestlySVCheck.svLoadCheck.build = "changed"
H.eq(inherited and inherited.build, "70009", "by value, not by reference")

-- Adopt REPLACES: a key this character never set falls back to the default,
-- rather than keeping whichever other character's value is sitting there.
WoW.reset()
PriestlyAccountDB, PriestlyDB = nil, configuredCharacter()
Priestly_EnsureDefaults()
Priestly_SetConfig("showClickHints", false)    -- the first character's choice
PriestlyDB = configuredCharacter(nil, { "showClickHints" })
H.check(Priestly_AdoptCharacterSettings() > 0, "the second character adopts")
H.eq(PriestlyAccountDB.showClickHints, TC.DEFAULTS.showClickHints,
    "a setting they never had reverts to the default, not the other character's")

-- Adopt says whether the options panel is now showing stale values: it is
-- built once and never re-synced, so the honest answer is that a reload is
-- needed rather than letting it disagree with the addon.
WoW.reset()
PriestlyAccountDB, PriestlyDB = nil, configuredCharacter()
Priestly_EnsureDefaults()
local _, stale = Priestly_AdoptCharacterSettings()
H.eq(stale, false, "with the panel never opened, nothing is stale")

-- A saved file is text on disk: it can come back with a table inside itself.
-- Copying it must not recurse off the end of the stack, which would abort
-- login before the defaults are backfilled.
WoW.reset()
PriestlyAccountDB = nil
local loop = { frameAlpha = 0.33 }
loop.self = loop
PriestlyDB = loop
H.check(pcall(Priestly_EnsureDefaults), "a self-referential saved table does not blow the stack")
H.eq(PriestlyAccountDB.frameAlpha, 0.33, "and its settings still come across")

-- The slash command itself, not just the function under it: the branch, both
-- messages and the count are the whole user-facing surface of this feature.
WoW.reset()
PriestlyAccountDB, PriestlyDB = nil, configuredCharacter()
Priestly_EnsureDefaults()
before = #WoW.messages
SlashCmdList["PRIESTLY"]("adopt")
said2 = table.concat(WoW.messages, " | ", before + 1, #WoW.messages)
H.check(said2:find("every character", 1, true), "/priestly adopt reports what it did: " .. said2)
H.check(said2:find("applied", 1, true), "with a count: " .. said2)

WoW.reset()
PriestlyAccountDB, PriestlyDB = nil, nil
Priestly_EnsureDefaults()
before = #WoW.messages
SlashCmdList["PRIESTLY"]("adopt")
said2 = table.concat(WoW.messages, " | ", before + 1, #WoW.messages)
H.check(said2:find("Nothing to adopt", 1, true),
    "and says so plainly when there is nothing: " .. said2)

-- The move announces itself, once, naming the character it took: an addon
-- whose settings just changed under the player should say why.
WoW.reset()
PriestlyAccountDB, PriestlyDB = nil, configuredCharacter()
WoW.SetUnit("player", { name = "Karuzo Elegia" })
before = #WoW.messages
Priestly_EnsureDefaults()
said2 = table.concat(WoW.messages, " | ", before + 1, #WoW.messages)
H.check(said2:find("shared by all your characters", 1, true), "the seed says so: " .. said2)
H.check(said2:find("Karuzo Elegia", 1, true), "naming where they came from: " .. said2)
before = #WoW.messages
Priestly_EnsureDefaults()
H.eq(#WoW.messages, before, "and only once")

-- A second configured character is TOLD its own settings are still there,
-- once, rather than left looking at an addon that reset itself.
PriestlyDB = configuredCharacter({ frameAlpha = 0.25 })
before = #WoW.messages
Priestly_EnsureDefaults()
said2 = table.concat(WoW.messages, " | ", before + 1, #WoW.messages)
H.check(said2:find("adopt", 1, true), "the other character is pointed at adopt: " .. said2)
before = #WoW.messages
Priestly_EnsureDefaults()
H.eq(#WoW.messages, before, "once for that character, not at every login")

-- Adopt has to APPLY what it copied, not just store it. The panel is built
-- once and never re-synced, and the window reads its opacity and rows when
-- told to - so without these calls the player sees the old setup and a chat
-- line claiming the new one.
WoW.reset()
PriestlyAccountDB, PriestlyDB = nil, configuredCharacter()
Priestly_EnsureDefaults()
local applied = { alpha = 0, rebuild = 0, changed = {} }
local realAlpha, realRebuild = Priestly_ApplyAlpha, Priestly_ForceRebuild
local realHook = Priestly_OnConfigChanged
Priestly_ApplyAlpha = function() applied.alpha = applied.alpha + 1 end
Priestly_ForceRebuild = function() applied.rebuild = applied.rebuild + 1 end
Priestly_OnConfigChanged = function(key) applied.changed[key] = true end

PriestlyDB = configuredCharacter({ frameAlpha = 0.31 })
Priestly_AdoptCharacterSettings()
H.check(applied.alpha > 0, "adopt re-applies the window opacity")
H.check(applied.rebuild > 0, "and rebuilds the rows")
H.check(applied.changed.frameAlpha, "and reports the keys it changed, so anything watching sees")
H.check(applied.changed.shadowMode, "every one of them, not just the first")

Priestly_ApplyAlpha, Priestly_ForceRebuild = realAlpha, realRebuild
Priestly_OnConfigChanged = realHook

-- The alt that matters is not one with NO table - every character that ran a
-- per-character release has one, filled with every default and the whole
-- instance list by EnsureDefaults. Treating that as "configured" let a
-- never-touched alt claim the shared settings and lock the real ones out.
local function defaultsOnlyCharacter()
    local t = {}
    for key, value in pairs(TC.DEFAULTS) do t[key] = value end
    t.flavor = "forever"
    t.shadowInstances = {}
    for _, entry in ipairs(TC.INSTANCE_DB) do t.shadowInstances[entry[1]] = entry[3] end
    return t
end

WoW.reset()
PriestlyAccountDB, PriestlyDB = nil, defaultsOnlyCharacter()
Priestly_EnsureDefaults()
H.eq(PriestlyAccountDB[TC.SEED_MARKER], nil,
    "an alt holding nothing but the defaults claims nothing")

PriestlyDB = configuredCharacter()
Priestly_EnsureDefaults()
H.eq(PriestlyAccountDB.frameAlpha, 0.5, "so the configured character still seeds afterwards")

-- One changed key is enough to count as configured, including an instance
-- choice that differs from what the list ships with.
WoW.reset()
PriestlyAccountDB = nil
local justOneInstance = defaultsOnlyCharacter()
justOneInstance.shadowInstances[TC.INSTANCE_DB[1][1]] = not TC.INSTANCE_DB[1][3]
PriestlyDB = justOneInstance
Priestly_EnsureDefaults()
H.check(PriestlyAccountDB[TC.SEED_MARKER] ~= nil,
    "but a single instance ticked differently is a configured character")

-- Adopt has to clear what this character never had, not only reset the keys
-- with defaults: a window position from whoever seeded first would otherwise
-- survive "use THIS character's settings".
WoW.reset()
PriestlyAccountDB, PriestlyDB = nil, configuredCharacter()
Priestly_EnsureDefaults()
H.eq(PriestlyAccountDB.pos.x, 3, "the first character's position is shared")
PriestlyDB = configuredCharacter({ frameAlpha = 0.42 }, { "pos" })
Priestly_AdoptCharacterSettings()
H.eq(PriestlyAccountDB.pos, nil, "adopting a character that had none clears it")
H.eq(PriestlyAccountDB.frameAlpha, 0.42, "while taking what it did have")

-- The order that catches the seed out: an alt logs in first and claims
-- nothing, the player then sets up the shared settings by hand, and only
-- afterwards does a character with an old profile arrive. Those are
-- deliberate choices about the shared table and a seed must not undo them.
WoW.reset()
PriestlyAccountDB, PriestlyDB = nil, defaultsOnlyCharacter()
Priestly_EnsureDefaults()                         -- the alt
Priestly_SetConfig("frameAlpha", 0.23)            -- chosen in the options panel
Priestly_SetShadowInstance(TC.INSTANCE_DB[1][1], not TC.INSTANCE_DB[1][3])

PriestlyDB = configuredCharacter()                -- the old profile arrives
before = #WoW.messages
Priestly_EnsureDefaults()
H.eq(PriestlyAccountDB.frameAlpha, 0.23, "a deliberate shared setting is not overwritten")
H.eq(PriestlyAccountDB[TC.SEED_MARKER], nil, "and nothing claims to have seeded")

-- It is offered instead, so the player can still have it.
said2 = table.concat(WoW.messages, " | ", before + 1, #WoW.messages)
H.check(said2:find("adopt", 1, true), "the character is told adopt will use its own: " .. said2)
H.check(Priestly_AdoptCharacterSettings() > 0, "and adopt honours that")
H.eq(PriestlyAccountDB.frameAlpha, 0.5, "replacing the chosen value on purpose")

-- The bookkeeping keys describe the SHARED table, so they are never carried
-- from a character's own. One character's "the player set this up" must not
-- arrive as the account's.
WoW.reset()
PriestlyAccountDB = nil
PriestlyDB = configuredCharacter({ [TC.CHOICE_MARKER] = true, [TC.SEED_MARKER] = "Someone" })
Priestly_EnsureDefaults()
H.eq(PriestlyAccountDB[TC.CHOICE_MARKER], nil, "a legacy table's choice marker is not carried")
H.check(PriestlyAccountDB[TC.SEED_MARKER] ~= "Someone",
    "nor its record of who seeded - this seed sets that itself")

-- A choice whose RESULT is a default is still a choice: turn a buff off and
-- back on, or press Reset Defaults, and every value matches DEFAULTS again
-- while the player has plainly set the shared settings up. Comparing values
-- cannot see that, so the act itself is recorded.
WoW.reset()
PriestlyAccountDB, PriestlyDB = nil, defaultsOnlyCharacter()
Priestly_EnsureDefaults()                          -- the alt
Priestly_SetConfig("trackFort", false)             -- changed...
Priestly_SetConfig("trackFort", TC.DEFAULTS.trackFort)   -- ...and changed back
H.eq(PriestlyAccountDB.trackFort, TC.DEFAULTS.trackFort, "the value is back to the default")

PriestlyDB = configuredCharacter({ trackFort = false })
Priestly_EnsureDefaults()
H.eq(PriestlyAccountDB.trackFort, TC.DEFAULTS.trackFort,
    "and a later character's old profile does not undo the choice")
H.eq(PriestlyAccountDB[TC.SEED_MARKER], nil, "nothing seeded over it")

-- The instance tab counts too, including setting one back to its default.
WoW.reset()
PriestlyAccountDB, PriestlyDB = nil, defaultsOnlyCharacter()
Priestly_EnsureDefaults()
local firstInstance = TC.INSTANCE_DB[1][1]
Priestly_SetShadowInstance(firstInstance, TC.INSTANCE_DB[1][3])
PriestlyDB = configuredCharacter({ frameAlpha = 0.66 })
Priestly_EnsureDefaults()
H.eq(PriestlyAccountDB.frameAlpha, TC.DEFAULTS.frameAlpha,
    "an instance choice, even one that equals the default, protects the shared settings")

H.done("test_config_seam")
