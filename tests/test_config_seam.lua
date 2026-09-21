------------------------------------------------------------
-- test_config_seam.lua - one write path for PriestlyDB, and the two checks
-- that watch for the client being fixed or updated (issue #35).
--
-- Nothing an addon writes survives a real restart on this build. Until
-- Blizzard fixes it, every settings change goes through Priestly_SetConfig so
-- the fix - or the migration it needs - lands in one place.
--
--   & 'C:\Program Files (x86)\Lua\5.1\lua.exe' tests\test_config_seam.lua
------------------------------------------------------------

dofile("tests/wow_stubs.lua")
local H = dofile("tests/harness.lua")
local T, TC = H.loadAddon()

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

Priestly_SetConfig("pos", nil)
H.eq(PriestlyDB.pos, nil, "SetConfig can clear a key")
H.eq(changed[#changed], "pos", "and still reports it")

Priestly_SetShadowInstance("Scholomance", false)
H.eq(PriestlyDB.shadowInstances["Scholomance"], false, "SetShadowInstance writes one entry")
H.eq(changed[#changed], "shadowInstances", "reported under the table's own key")

PriestlyDB = nil
Priestly_SetConfig("lockFrame", true)
H.eq(PriestlyDB and PriestlyDB.lockFrame, true, "SetConfig survives a missing table")

Priestly_OnConfigChanged = realHook

------------------------------------------------------------
-- The source scan
--
-- A behavioural test cannot catch a new direct write: it works perfectly well.
-- So every shipped file is read, and any assignment into PriestlyDB outside a
-- `config-owner` region fails the run.
------------------------------------------------------------

local function ReadFile(path)
    local f = io.open(path, "rb")
    if not f then return nil end
    local s = f:read("*a")
    f:close()
    return s
end

-- Assignments on a line, wherever they sit. `=[^=]` after the target keeps
-- comparisons out without discarding the rest of the line, and the target
-- cannot contain `~ < >`, so `~=` `<=` `>=` never match. Brackets are matched
-- loosely on purpose: a first attempt at finding these writes by hand missed
-- `PriestlyDB.shadowInstances[entry[1]] = true`, three of which existed.
local function Violations(path, src)
    src = src or ReadFile(path)
    if not src then return { path .. " unreadable" } end
    local bad, owned, n = {}, false, 0
    for line in (src .. "\n"):gmatch("([^\n]*)\n") do
        n = n + 1
        if line:find("config-owner: begin", 1, true) then owned = true end
        if line:find("config-owner: end", 1, true) then owned = false end
        local code = line:gsub("%-%-.*$", "")
        if not owned then
            for _ in code:gmatch("(PriestlyDB[%.%[][%w_%.%[%]\"']*)%s*=[^=]") do
                bad[#bad + 1] = path .. ":" .. n .. "  " .. line
            end
            if code:find("PriestlyDB%s*=[^=]") then
                bad[#bad + 1] = path .. ":" .. n .. "  " .. line
            end
        end
    end
    return bad
end

-- The lint must see what it is meant to see. Checked on synthetic lines, so a
-- broken pattern fails here rather than silently passing every real file.
for _, c in ipairs({
    { 'if x then PriestlyDB.lockFrame = true end', 1, "an inline write mid-line" },
    { 'PriestlyDB.flag = (a == b)', 1, "a write whose value contains ==" },
    { 'PriestlyDB.shadowInstances[entry[1]] = true', 1, "a write indexed by entry[1]" },
    { 'PriestlyDB[dbKey] = v', 1, "a write through a variable key" },
    { 'PriestlyDB = {}', 1, "replacing the whole table" },
    { 'if PriestlyDB.lockFrame == true then end', 0, "a comparison" },
    { 'if PriestlyDB.frameAlpha ~= 1 then end', 0, "a ~= comparison" },
    { 'local p = PriestlyDB.pos', 0, "a read into a local" },
    { '-- PriestlyDB.pos = nil', 0, "a comment" },
    { '-- config-owner: begin\nPriestlyDB.pos = nil\n-- config-owner: end', 0,
      "a write inside an owner region" },
}) do
    H.eq(#Violations("synthetic", c[1]), c[2], "the lint handles " .. c[3])
end

for _, path in ipairs({ "Priestly.lua", "PriestlyConfig.lua", "PriestlyCompat.lua" }) do
    local bad = Violations(path)
    H.check(#bad == 0, path .. " writes PriestlyDB only through the setters: " ..
        table.concat(bad, " | "))
end

-- Owner regions must stay small, or the scan stops meaning anything. Count
-- them, so adding one has to be done here on purpose.
local regions = select(2, ReadFile("PriestlyConfig.lua"):gsub("config%-owner: begin", ""))
H.eq(regions, 4, "PriestlyConfig has exactly four owner regions: the setters, "
    .. "EnsureDefaults, the duration cache and the load check")
H.eq(select(2, ReadFile("Priestly.lua"):gsub("config%-owner: begin", "")), 0,
    "Priestly.lua owns no part of PriestlyDB")

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

-- Today: the file is never read, so every initial login starts without it.
WoW.reset()
PriestlyDB = nil
Priestly_EnsureDefaults()
local before = #WoW.messages
Priestly_HandleEnteringWorld(true, false)
H.eq(said(before), "", "no marker at login, nothing announced - today's state")
H.check(type(PriestlyDB.svLoadCheck) == "table", "the marker is written for next time")
H.eq(PriestlyDB.svLoadCheck.build, "69913", "with the build it was written on")

-- A /reload proves nothing: announce nothing even though the marker is there.
before = #WoW.messages
Priestly_HandleEnteringWorld(false, true)
H.eq(said(before), "", "a /reload never announces, even with a marker present")

-- A zone change is neither, and must not touch the marker.
local marker = PriestlyDB.svLoadCheck
Priestly_HandleEnteringWorld(false, false)
H.check(PriestlyDB.svLoadCheck == marker, "a zone change leaves the marker alone")

-- The fix: the marker came back on a genuine initial login.
before = #WoW.messages
Priestly_HandleEnteringWorld(true, false)
local msg = said(before)
H.check(msg:find("remembered", 1, true), "an initial login with a marker announces the fix: " .. msg)
H.check(msg:find("full exit", 1, true), "and asks for a full exit to confirm: " .. msg)
H.check(msg:find("69913", 1, true), "naming the build: " .. msg)

-- Wired to the real event, not just callable.
PriestlyDB = nil
Priestly_EnsureDefaults()
WoW.dispatch("PLAYER_ENTERING_WORLD", true, false)
H.check(type(PriestlyDB.svLoadCheck) == "table", "PLAYER_ENTERING_WORLD drives the check")

------------------------------------------------------------
-- MEASURED_ON_BUILD: did the client update?
------------------------------------------------------------

H.eq(TC.MEASURED_ON_BUILD, "69913", "the measured build lives in the source")

WoW.build = "69913"
before = #WoW.messages
Priestly_CheckClientBuild()
H.eq(said(before), "", "the measured build is silent")

WoW.build = "70123"
before = #WoW.messages
Priestly_CheckClientBuild()
msg = said(before)
H.check(msg:find("70123", 1, true) and msg:find("69913", 1, true),
    "a new build warns, naming both: " .. msg)
H.check(msg:find("MEASURED_ON_BUILD", 1, true), "and says what to bump afterwards: " .. msg)

before = #WoW.messages
WoW.dispatch("PLAYER_LOGIN")
H.check(said(before):find("70123", 1, true), "the warning fires from PLAYER_LOGIN")
WoW.build = "69913"

H.done("test_config_seam")
