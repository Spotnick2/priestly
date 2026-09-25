------------------------------------------------------------
-- test_config_seam.lua - one write path for PriestlyDB, and the two checks
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

-- Pinned here as LITERALS, not read from the source. Every check below takes
-- its builds from the constants, so a stale constant satisfies all of them
-- while the addon warns at every real login on the build people are actually
-- running - and, worse, treats that build as one where saved settings work,
-- so a relog to character select can announce a fix that never happened.
-- Moving the client forward has to be a two-file edit, and this is the file
-- that says so.
-- MEASURED and CLIENT agree again - 70009 was re-probed in game on
-- 2026-09-25, aura secrecy in a fight and secure click-casting included - so
-- the login notice is silent. BROKEN does NOT follow them: it names the last
-- build where saved settings were broken, and 70009 fixed that. They are
-- allowed to differ, and this file covers them differing, which is how the
-- two detectors were shown not to be wired together.
local MEASURED = "70009"
local BROKEN = "69977"
local CLIENT = "70009"  -- what .build.info reports; what the stub must model
local FIXED = "70123"   -- any build other than the three above

H.eq(TC.MEASURED_ON_BUILD, MEASURED,
    "the source says Priestly was measured on the build these tests measure it on")
H.eq(TC.SV_BROKEN_ON_BUILD, BROKEN,
    "and on the build where saved settings are known not to come back")

-- The stub's default build is the one every other test file runs under, so a
-- stale default quietly models a client that no longer exists - and a test
-- asserting "no build warning at a default login" would be asserting it
-- against the wrong build. AGENTS.md says to keep them equal; this is what
-- makes that true rather than remembered.
-- The stub models the CLIENT, not whichever build Priestly last re-probed:
-- it is the default every other test file runs under, so a stale one hides
-- from all of them what a player actually sees - including, right now, a
-- login notice.
WoW.reset()
H.eq(WoW.build, CLIENT, "the stub models the build the client is on")

------------------------------------------------------------
-- The setters
------------------------------------------------------------

WoW.reset()
PriestlyDB = nil
Priestly_EnsureDefaults()

local changed = {}
local realHook = Priestly_OnConfigChanged
Priestly_OnConfigChanged = function(key) changed[#changed + 1] = key end

Priestly_SetConfig("frameAlpha", 0.5)
H.eq(PriestlyDB.frameAlpha, 0.5, "SetConfig assigns")
H.eq(changed[#changed], "frameAlpha", "and reports the key")

-- Set first, so clearing it is an actual change the test can see fail.
Priestly_SetConfig("pos", { point = "RIGHT", x = 1, y = 2 })
H.check(PriestlyDB.pos ~= nil, "a position is stored")
Priestly_SetConfig("pos", nil)
H.eq(PriestlyDB.pos, nil, "SetConfig can clear a key that was set")
H.eq(changed[#changed], "pos", "and reports the clear")

-- An unchanged value is not a change. UpdateUI sets `visible` on every
-- refresh; without this the hook runs on the aura hot path.
local count = #changed
Priestly_SetConfig("frameAlpha", 0.5)
H.eq(#changed, count, "setting the same value again does not report")

Priestly_SetShadowInstance("Scholomance", false)
H.eq(PriestlyDB.shadowInstances["Scholomance"], false, "SetShadowInstance writes one entry")
H.eq(changed[#changed], "shadowInstances", "reported under the table's own key")
count = #changed
Priestly_SetShadowInstance("Scholomance", false)
H.eq(#changed, count, "and an unchanged instance does not report either")

-- The learned-duration cache is replaced from inside a getter, so it has to
-- report there or it never reports at all.
PriestlyDB.learnedDurations = { build = "old" }
count = #changed
Priestly_GetLearnedDuration("Power Word: Fortitude")
H.eq(changed[#changed], "learnedDurations", "replacing the duration cache reports")

PriestlyDB = nil
Priestly_SetConfig("lockFrame", true)
H.eq(PriestlyDB and PriestlyDB.lockFrame, true, "SetConfig survives a missing table")

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

local SAVED = { "PriestlyDB", "PriestlySVCheck" }
local CS = dofile(H.libraryRoot() .. "/tests/config_scan.lua")

H.eq(#CS.Scan("synthetic", "PriestlyDB.lockFrame = true", SAVED), 1,
    "the scanner catches a direct PriestlyDB write")
H.eq(#CS.Scan("synthetic", "PriestlySVCheck.svLoadCheck = {}", SAVED), 1,
    "and a direct PriestlySVCheck write")
H.eq(#CS.Scan("synthetic", "local p = PriestlyDB.pos", SAVED), 0, "but not a read")

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
    PriestlyDB, PriestlySVCheck = nil, nil
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
H.check(type(PriestlyDB.svLoadCheck) == "table", "the per-character marker is written")
H.check(type(PriestlySVCheck.svLoadCheck) == "table", "and the account-wide one")
H.eq(PriestlyDB.svLoadCheck.build, BROKEN, "with the build it was written on")

-- The broken build, marker still in memory: that is a relog or a /reload
-- being served from the client's cache. Neither may announce.
before = #WoW.messages
Priestly_HandleEnteringWorld(true, false)
H.eq(saidSettings(before), "",
    "on the broken build a returning marker is the client's cache, not a fix")
Priestly_HandleEnteringWorld(false, true)
H.eq(saidSettings(before), "", "and a /reload never announces")

-- A zone change is neither, and must not touch the marker.
local marker = PriestlyDB.svLoadCheck
Priestly_HandleEnteringWorld(false, false)
H.check(PriestlyDB.svLoadCheck == marker, "a zone change leaves the marker alone")

-- The fix: a new build, and the marker came back on a real login.
WoW.build = FIXED
before = #WoW.messages
Priestly_HandleEnteringWorld(true, false)
local msg = said(before)
H.check(msg:find("came back", 1, true), "a real login on a new build announces it: " .. msg)
H.check(msg:find("fully exited", 1, true), "conditional on a full exit: " .. msg)
H.check(msg:find("proves nothing", 1, true), "and says a relog or /reload proves nothing: " .. msg)
H.check(msg:find("per-character", 1, true) and msg:find("account-wide", 1, true),
    "naming the scopes that came back: " .. msg)
H.check(msg:find(FIXED, 1, true), "and the build: " .. msg)

-- Once only: the latch persists by then, because the store works.
before = #WoW.messages
Priestly_HandleEnteringWorld(true, false)
H.check(not said(before):find("came back", 1, true), "it does not repeat at the next login")

-- Account-wide fixed on its own is worth knowing: it is what #9 moves back to.
freshSession(FIXED)
PriestlySVCheck = { svLoadCheck = { stamp = "then", build = FIXED } }
before = #WoW.messages
Priestly_HandleEnteringWorld(true, false)
msg = said(before)
H.check(msg:find("account-wide", 1, true) and not msg:find("per-character", 1, true),
    "a fix to account-wide storage alone is reported as that: " .. msg)

-- Wired to the real event, not just callable.
freshSession(BROKEN)
WoW.dispatch("PLAYER_ENTERING_WORLD", true, false)
H.check(type(PriestlyDB.svLoadCheck) == "table", "PLAYER_ENTERING_WORLD drives the check")

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
H.eq(PriestlyDB.warnedBuild, nil, "and records nothing that could silence it")

H.done("test_config_seam")
