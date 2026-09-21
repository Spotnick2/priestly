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

local BROKEN = TC.SV_BROKEN_ON_BUILD
local MEASURED = TC.MEASURED_ON_BUILD
local FIXED = "70123"   -- any build other than the two above

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
-- So every file the TOC loads is read, and any assignment into PriestlyDB
-- outside a `config-owner` region fails the run.
--
-- This is a small hand-written scanner rather than one pattern, because a
-- pattern keeps missing shapes. The first version missed writes whose key had
-- a space, a call, `..` or arithmetic in it, multiple assignment, and a value
-- on the next line - all found in review.
------------------------------------------------------------

local function ReadFile(path)
    local f = io.open(path, "rb")
    if not f then return nil end
    local s = f:read("*a")
    f:close()
    return (s:gsub("\r\n", "\n"))
end

-- String contents blanked, so `=` and `--` inside them are ignored; then the
-- comment cut off.
local function CodeOf(line)
    local code = line:gsub('"[^"]*"', '""'):gsub("'[^']*'", "''")
    return (code:gsub("%-%-.*$", ""))
end

-- Is this piece of an assignment's left side a PriestlyDB lvalue? Bracket and
-- paren contents are dropped first, so any key expression counts:
-- `[ name ]`, `[self:GetName()]`, `[key .. "x"]`, `[i+1]`.
local function IsDBTarget(piece)
    local flat, depth = {}, 0
    for ch in piece:gmatch(".") do
        if ch == "[" or ch == "(" then
            depth = depth + 1
            if depth == 1 then flat[#flat + 1] = ch end
        elseif ch == "]" or ch == ")" then
            if depth == 1 then flat[#flat + 1] = ch end
            depth = depth - 1
        elseif depth == 0 then
            flat[#flat + 1] = ch
        end
    end
    local tail = table.concat(flat):match("([%w_%.%:%[%]%(%)]+)%s*$") or ""
    return tail == "PriestlyDB" or tail:find("^PriestlyDB[%.%[]") ~= nil
end

-- Every assignment target on one line of code. An `=` counts if it is at
-- bracket depth 0 and is not part of `==` `~=` `<=` `>=`. It may end the line,
-- with the value on the next one. The left side is cut back to the last
-- statement boundary, split on top-level commas for multiple assignment, and a
-- `local` declaration is skipped.
local function DBWritesIn(code)
    local hits, depth, from, i = 0, 0, 1, 1
    while i <= #code do
        local c = code:sub(i, i)
        if c == "(" or c == "[" or c == "{" then
            depth = depth + 1
        elseif c == ")" or c == "]" or c == "}" then
            depth = depth - 1
        elseif c == "=" and depth == 0 then
            local prev, nxt = code:sub(i - 1, i - 1), code:sub(i + 1, i + 1)
            if nxt == "=" then
                i = i + 1
            elseif prev ~= "~" and prev ~= "<" and prev ~= ">" and prev ~= "=" then
                local left = code:sub(from, i - 1)
                left = left:gsub("%f[%w_]function%f[^%w_][^(]*%b()", "\1")
                for _, kw in ipairs({ "then", "do", "else", "end", "return", "repeat" }) do
                    left = left:gsub("%f[%w_]" .. kw .. "%f[^%w_]", "\1")
                end
                left = left:gsub(";", "\1")
                local stmt = left:match("([^\1]*)$")
                if not stmt:find("^%s*local%s") then
                    local pieceDepth, piece = 0, ""
                    for ch in (stmt .. ","):gmatch(".") do
                        if ch == "(" or ch == "[" or ch == "{" then pieceDepth = pieceDepth + 1 end
                        if ch == ")" or ch == "]" or ch == "}" then pieceDepth = pieceDepth - 1 end
                        if ch == "," and pieceDepth == 0 then
                            if IsDBTarget(piece) then hits = hits + 1 end
                            piece = ""
                        else
                            piece = piece .. ch
                        end
                    end
                end
                from = i + 1
            end
        end
        i = i + 1
    end
    return hits
end

-- Violations in one file, and the number of owner regions it declares. Region
-- markers are recognised only as whole comment lines, so prose that mentions
-- them opens nothing, and they must balance.
local BEGIN = "^%s*%-%- config%-owner: begin%s*$"
local END = "^%s*%-%- config%-owner: end%s*$"

local function Scan(path, src)
    src = src or ReadFile(path)
    if not src then return { path .. " unreadable" }, 0 end
    local bad, owned, regions, n = {}, false, 0, 0
    for line in (src .. "\n"):gmatch("([^\n]*)\n") do
        n = n + 1
        if line:find(BEGIN) then
            if owned then bad[#bad + 1] = path .. ":" .. n .. "  nested owner region" end
            owned, regions = true, regions + 1
        elseif line:find(END) then
            if not owned then bad[#bad + 1] = path .. ":" .. n .. "  owner end with no begin" end
            owned = false
        elseif not owned and DBWritesIn(CodeOf(line)) > 0 then
            bad[#bad + 1] = path .. ":" .. n .. "  " .. line
        end
    end
    if owned then bad[#bad + 1] = path .. "  owner region never closed" end
    return bad, regions
end

-- The scanner must see what it is meant to see. Checked on synthetic source,
-- so a broken scanner fails here rather than silently passing every file.
for _, c in ipairs({
    { 'if x then PriestlyDB.lockFrame = true end', 1, "an inline write mid-line" },
    { 'PriestlyDB.flag = (a == b)', 1, "a write whose value contains ==" },
    { 'PriestlyDB.shadowInstances[entry[1]] = true', 1, "a key indexed by entry[1]" },
    { 'PriestlyDB.shadowInstances[ name ] = true', 1, "a key with spaces" },
    { 'PriestlyDB.shadowInstances[self:GetName()] = true', 1, "a key from a method call" },
    { 'PriestlyDB.shadowInstances[GetInstanceInfo()] = true', 1, "a key from a call" },
    { 'PriestlyDB[key .. "x"] = 1', 1, "a concatenated key" },
    { 'PriestlyDB.shadowInstances[i+1] = true', 1, "an arithmetic key" },
    { 'PriestlyDB[dbKey] = v', 1, "a variable key" },
    { 'PriestlyDB.a, x = 1, 2', 1, "multiple assignment" },
    { 'x, PriestlyDB.b = 1, 2', 1, "multiple assignment, second target" },
    { 'PriestlyDB.pos =\n    { point = p }', 1, "a value on the next line" },
    { 'x = 1; PriestlyDB.y = 2', 1, "a second statement on the line" },
    { 'local function f() PriestlyDB.x = 1 end', 1, "a write inside a one-line function" },
    { 'PriestlyDB = {}', 1, "replacing the whole table" },
    { 'if PriestlyDB.lockFrame == true then end', 0, "a comparison" },
    { 'if PriestlyDB.frameAlpha ~= 1 then end', 0, "a ~= comparison" },
    { 'if PriestlyDB.a then y = 2 end', 0, "a condition that reads it" },
    { 'local p = PriestlyDB.pos', 0, "a read into a local" },
    { 'local t = { pos = PriestlyDB.pos }', 0, "a read inside a table constructor" },
    { 'print("PriestlyDB.x = 1")', 0, "text inside a string" },
    { '-- PriestlyDB.pos = nil', 0, "a comment" },
    { '-- see the config-owner: begin/end regions\nPriestlyDB.x = 1', 1,
      "prose mentioning the marker, which opens nothing" },
    { '-- config-owner: begin\nPriestlyDB.pos = nil\n-- config-owner: end', 0,
      "a write inside an owner region" },
}) do
    H.eq(#Scan("synthetic", c[1]), c[2], "the scanner handles " .. c[3])
end

H.check(#Scan("synthetic", "-- config-owner: begin\nx = 1") > 0,
    "an owner region that never closes is an error")
H.check(#Scan("synthetic", "-- config-owner: end") > 0,
    "an end with no begin is an error")

-- Every file the TOC loads, read from the TOC so a new one cannot be missed.
local files = {}
for line in (ReadFile("Priestly.toc") .. "\n"):gmatch("([^\n]*)\n") do
    local file = line:match("^%s*([^#%s][^%s]*%.lua)%s*$")
    if file then files[#files + 1] = file end
end
H.check(#files >= 3, "the TOC lists the addon's files: " .. table.concat(files, ", "))

-- Owner regions must stay few, or the scan stops meaning anything. Each file's
-- count is pinned, so adding one has to be done here on purpose.
local expectedRegions = { ["PriestlyConfig.lua"] = 4 }
for _, path in ipairs(files) do
    local bad, regions = Scan(path)
    H.check(#bad == 0, path .. " writes PriestlyDB only through the setters: " ..
        table.concat(bad, " | "))
    H.eq(regions, expectedRegions[path] or 0, path .. " has the expected owner regions "
        .. "(PriestlyConfig: the setters, EnsureDefaults, the duration cache, the load check)")
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
H.eq(said(before), "", "no marker at login, nothing announced - today's state")
H.check(type(PriestlyDB.svLoadCheck) == "table", "the per-character marker is written")
H.check(type(PriestlySVCheck.svLoadCheck) == "table", "and the account-wide one")
H.eq(PriestlyDB.svLoadCheck.build, BROKEN, "with the build it was written on")

-- The broken build, marker still in memory: that is a relog or a /reload
-- being served from the client's cache. Neither may announce.
before = #WoW.messages
Priestly_HandleEnteringWorld(true, false)
H.eq(said(before), "",
    "on the broken build a returning marker is the client's cache, not a fix")
Priestly_HandleEnteringWorld(false, true)
H.eq(said(before), "", "and a /reload never announces")

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

before = #WoW.messages
Priestly_HandleEnteringWorld(true, false)
H.check(not said(before):find("tested on", 1, true),
    "once per build, where storage can remember it was shown")

H.done("test_config_seam")
