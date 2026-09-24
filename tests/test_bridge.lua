------------------------------------------------------------
-- test_bridge.lua - Priestly on top of LibGroupBuffs-1.0.
--
-- The compat layer lives in the shared library now, and its own tests live
-- there (LibGroupBuffs/tests/test_compat.lua). What is left to check here is
-- the join: that Priestly really uses the library, that every API it calls
-- exists there, and that the one behaviour Priestly owns - reporting rejected
-- events in chat - still happens.
--
--   & 'C:\Program Files (x86)\Lua\5.1\lua.exe' tests\test_bridge.lua
------------------------------------------------------------

dofile("tests/wow_stubs.lua")
local H = dofile("tests/harness.lua")
local T, TC, API = H.loadAddon()

-- Every Lua file the TOC loads, and each one's source with comments removed.
local SOURCES = {}
for _, file in ipairs(H.tocFiles()) do
    local code = {}
    for line in (H.readFile(file) .. "\n"):gmatch("([^\n]*)\n") do
        code[#code + 1] = (line:gsub("%-%-.*$", ""))
    end
    SOURCES[file] = code
end

------------------------------------------------------------
-- Priestly.API IS the library's API - not a copy of it
------------------------------------------------------------

local lib = LibStub("LibGroupBuffs-1.0")
H.check(lib ~= nil, "LibGroupBuffs-1.0 is loaded")
H.check(API == lib.API, "Priestly.API is the library's API table itself")
H.check(Priestly.Settings == lib.Settings, "and Priestly.Settings its Settings")
H.check(Priestly.Engine == lib.Engine, "and Priestly.Engine its Engine")
H.check(Priestly.UI == lib.UI, "and Priestly.UI its UI")

------------------------------------------------------------
-- Every API function Priestly calls exists in the library
--
-- The point of the library is one copy. If Priestly calls something the
-- library does not have, it only fails when that code path runs in game - so
-- read the source and check every call.
------------------------------------------------------------

local used = {}
for file, lines in pairs(SOURCES) do
    for _, code in ipairs(lines) do
        for name in code:gmatch("%f[%w_]API%.([%a_][%w_]*)") do used[name] = file end
    end
end
local count = 0
for name, file in pairs(used) do
    count = count + 1
    if name == "eventFailures" or name == "eventFailuresByOwner" then
        H.check(type(API[name]) == "table",
            file .. " reads API." .. name .. ", so the library must provide it")
    else
        H.check(type(API[name]) == "function",
            file .. " calls API." .. name .. ", so the library must provide it")
    end
end
-- Most API calls moved into the library with the engine and the window, so
-- this is only a floor proving the scan reads the files at all.
H.check(count >= 5, "the scan found Priestly's API calls: " .. count)

------------------------------------------------------------
-- No library function is copied into a local
--
-- API is the table LibGroupBuffs shares with every addon that embeds it, and
-- a newer copy loading later upgrades it in place. `local F = API.F` taken at
-- load time would keep running the old version beside the new one. Call
-- through API, or wrap: `local function F(...) return API.F(...) end`.
------------------------------------------------------------

local captures = {}
for file, lines in pairs(SOURCES) do
    for n, code in ipairs(lines) do
        -- Qualified forms count too: `local F = Priestly.API.F` and
        -- `local F = lib.API.F` copy exactly the same function.
        if code:find("=%s*[%w_%.]-%f[%w_]API%.[%a_][%w_]*%s*$")
            or code:find("=%s*[%w_%.]-%f[%w_]API%.[%a_][%w_]*%s*;") then
            captures[#captures + 1] = file .. ":" .. n .. "  " .. code
        end
    end
end
H.eq(#captures, 0, "no file copies a library function into a local: " .. table.concat(captures, " | "))

------------------------------------------------------------
-- Events are registered only through Priestly.RegisterEvents
--
-- The library prints nothing, and a bare frame:RegisterEvent throws on an
-- unknown name or returns false. Any registration that skips
-- Priestly.RegisterEvents - library call or bare method - can leave a handler
-- silently dead, so neither may appear outside the wrapper.
------------------------------------------------------------

local direct = {}
for file, lines in pairs(SOURCES) do
    for n, code in ipairs(lines) do
        -- PriestlyCompat.lua is the wrapper itself, the one allowed caller.
        if file ~= "PriestlyCompat.lua" and (code:find("%f[%w_]API%.RegisterEvents%w*%s*%(")
                                             or code:find(":RegisterEvent%s*%(")) then
            direct[#direct + 1] = file .. ":" .. n .. "  " .. code
        end
    end
end
H.eq(#direct, 0, "nothing registers events except through Priestly.RegisterEvents: " .. table.concat(direct, " | "))

------------------------------------------------------------
-- Rejected events are reported in chat
--
-- The library returns them instead of printing, because it must not write to
-- another addon's chat frame. A silently missing handler is worse than a
-- noisy one, so Priestly prints them.
------------------------------------------------------------

WoW.reset()
local f = CreateFrame("Frame")
local before = #WoW.messages
local ok, failed = Priestly.RegisterEvents(f, "PLAYER_LOGIN", "UNIT_AURA")
H.eq(ok, true, "known events register cleanly")
H.eq(#WoW.messages, before, "and print nothing")

WoW.badEvents.NOT_A_REAL_EVENT = true
before = #WoW.messages
ok, failed = Priestly.RegisterEvents(f, "UNIT_PET", "NOT_A_REAL_EVENT")
H.eq(ok, false, "a rejected event name is reported")
H.check(WoW.events[f].UNIT_PET == true, "the good event still registered")
H.eq(failed and failed[1], "NOT_A_REAL_EVENT", "the caller gets the rejected name")
local said = table.concat(WoW.messages, " ", before + 1, #WoW.messages)
H.check(said:find("NOT_A_REAL_EVENT", 1, true), "and it is printed, not silent: " .. said)
H.check(Priestly.eventFailures.NOT_A_REAL_EVENT ~= nil,
    "and recorded in Priestly's own table - the library's is shared by every addon")
H.check(API.eventFailuresByOwner.Priestly.NOT_A_REAL_EVENT ~= nil,
    "and in the library under Priestly's name")

-- The client can also refuse by returning false; that must be just as loud.
WoW.refusedEvents.REFUSED_EVENT = true
before = #WoW.messages
ok, failed = Priestly.RegisterEvents(f, "REFUSED_EVENT")
H.eq(ok, false, "a false return is a rejection too")
said = table.concat(WoW.messages, " ", before + 1, #WoW.messages)
H.check(said:find("REFUSED_EVENT", 1, true), "and it is printed: " .. said)

------------------------------------------------------------
-- A missing library stops loading, with a message that says why
--
-- No fallback copy: running on a stale duplicate is the drift this removes.
------------------------------------------------------------

local savedLibStub, savedPriestly = LibStub, Priestly

local function loadWithout(libStubValue)
    LibStub = libStubValue
    Priestly = nil
    local before = #WoW.messages
    local loaded, err = pcall(dofile, "PriestlyCompat.lua")
    local chat = table.concat(WoW.messages, " ", before + 1, #WoW.messages)
    return loaded, tostring(err), chat
end

local loaded, err, chat = loadWithout(nil)
H.check(not loaded, "PriestlyCompat refuses to load without the library")
H.check(err:find("Libs\\LibGroupBuffs-1.0", 1, true),
    "the error names the real folder, backslash intact: " .. err)
-- Lua errors are hidden by default on this client, so the error alone would
-- leave a player looking at an addon that silently does nothing.
H.check(chat:find("cannot start", 1, true) and chat:find("missing", 1, true),
    "and a player is told in chat, where they will see it: " .. chat)

-- What the bridge does with each answer.
--
-- Which copies are usable is the library's question now: lib.Status walks its
-- own list of files and says "ok", "incomplete" or "too-old". Priestly's job
-- is to react - refuse, and say the right thing to the player - and that is
-- all this file tests. The twelve "complete except one piece" cases moved to
-- the library, where a new runtime file gets covered without editing any
-- consumer (LibGroupBuffs#20).
local FLOOR = tonumber((H.readFile("PriestlyCompat.lua") or ""):match("NEEDS_MINOR = (%d+)"))
H.check(FLOOR ~= nil, "the bridge declares the oldest library it works against")

local function answering(status, minor)
    local l = { API = { RegisterEventsReported = function() return true end,
                        ClickEdges = function() end },
                Settings = { New = function() end }, Engine = { New = function() end },
                UI = { New = function() end },
                Status = status and function() return status, minor end or nil }
    return setmetatable({}, { __call = function() return l, minor end })
end

loaded = loadWithout(answering("ok", FLOOR))
H.check(loaded, "a library that says it is ok is accepted")

loaded, err, chat = loadWithout(answering("incomplete", FLOOR))
H.check(not loaded, "one that says it is incomplete is refused")
H.check(chat:find("completely", 1, true), "as a failed load: " .. chat)

loaded, err, chat = loadWithout(answering("too-old", FLOOR - 1))
H.check(not loaded, "and one that says it is too old")
H.check(chat:find("r" .. (FLOOR - 1), 1, true) and chat:find("r" .. FLOOR, 1, true),
    "naming the version in use and the one needed: " .. chat)
H.check(not chat:find("completely", 1, true), "without claiming a failed load: " .. chat)
H.check(chat:find("Reinstalling", 1, true),
    "and pointing at Priestly's own copy, which is the only thing that can be behind: " .. chat)

-- A copy too old to have Status at all. Its absence is the answer, and which
-- answer depends on the version: behind the floor is too-old, at or above it
-- means the file that installs Status threw.
loaded, err, chat = loadWithout(answering(nil, FLOOR - 1))
H.check(not loaded, "a copy without Status, below the floor, is refused")
H.check(chat:find("r" .. (FLOOR - 1), 1, true) and not chat:find("completely", 1, true),
    "as too old rather than broken: " .. chat)

loaded, err, chat = loadWithout(answering(nil, FLOOR))
H.check(not loaded, "a copy without Status at the floor is refused too")
H.check(chat:find("completely", 1, true),
    "as a failed load, because the file that installs Status is the last one: " .. chat)

-- The real load order: an older copy loaded first is UPGRADED, not refused
--
-- The fakes above call the bridge directly, which is not how the game gets
-- here. Priestly's TOC loads its own copy of the library BEFORE this file, so
-- another addon's older copy has already been upgraded by LibStub when the
-- bridge runs - which is why a version below the floor means Priestly's own
-- copy never registered, not that somebody else's is in the way.
------------------------------------------------------------

do
    local root = H.libraryRoot()
    local fixtures = root .. "/tests/fixtures/"
    local older = {}
    for _, name in ipairs({ "Compat", "Settings", "Engine", "UI" }) do
        older[#older + 1] = fixtures .. name .. "-r9.lua"
    end
    local haveFixtures = true
    for _, path in ipairs(older) do
        local f = io.open(path, "r")
        if f then f:close() else haveFixtures = false end
    end
    H.check(haveFixtures, "the library checkout carries its r9 fixtures to load first")

    if haveFixtures then
        LibStub = savedLibStub
        Priestly = nil
        -- A LibStub with nothing registered, the way a session starts.
        local stub = loadfile(root .. "/LibStub/LibStub.lua")
        LibStub = nil
        stub()

        for _, path in ipairs(older) do loadfile(path)() end
        local _, before = LibStub:GetLibrary("LibGroupBuffs-1.0")
        H.eq(before, 9, "another addon's r9 copy registered first")

        -- Now Priestly's own, as its TOC does.
        local L = dofile("tests/libfiles.lua")
        for _, file in ipairs(select(2, pcall(L.resolve, root))) do
            loadfile(root .. "/" .. file)()
        end
        local _, after = LibStub:GetLibrary("LibGroupBuffs-1.0")
        H.check(after > before, "and Priestly's copy upgrades it to r" .. tostring(after))

        local before2 = #WoW.messages
        local ok = pcall(dofile, "PriestlyCompat.lua")
        H.check(ok, "so the bridge accepts it, despite the older copy having loaded first")
        H.eq(#WoW.messages, before2, "and says nothing to the player")
        H.check(Priestly.API ~= nil, "with the upgraded library in place")
    end

    LibStub, Priestly = savedLibStub, savedPriestly
end

-- The other two files stop before building anything, so a missing library is
-- one message rather than a cascade of errors and half-made frames.
Priestly = {}
local frames = 0
local realCreateFrame = CreateFrame
CreateFrame = function(...) frames = frames + 1 return realCreateFrame(...) end
for _, file in ipairs({ "PriestlyConfig.lua", "Priestly.lua" }) do
    local ok, why = pcall(dofile, file)
    H.check(ok, file .. " returns quietly when Priestly.API is missing: " .. tostring(why))
end
H.eq(frames, 0, "and creates no frames")
CreateFrame = realCreateFrame

LibStub, Priestly = savedLibStub, savedPriestly

H.done("test_bridge")
