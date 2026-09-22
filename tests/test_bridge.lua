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
        if code:find("=%s*API%.[%a_][%w_]*%s*$") or code:find("=%s*API%.[%a_][%w_]*%s*;") then
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

-- A library that threw partway through its compat layer: registered, but
-- without the functions defined after the error.
local halfLoaded = setmetatable({}, { __call = function()
    return { API = { RegisterEventsReported = function() return true end } }
end })
loaded, err, chat = loadWithout(halfLoaded)
H.check(not loaded, "a library that failed to load completely is refused too")
H.check(chat:find("completely", 1, true), "and reported as that, not as missing: " .. chat)

-- An older copy that loaded completely but predates Settings (r3) or Engine
-- (r4): refused at the door, not as a nil call when Priestly builds them.
local r3Shaped = setmetatable({}, { __call = function()
    return { API = { RegisterEventsReported = function() return true end,
                     ClickEdges = function() end } }
end })
loaded, err, chat = loadWithout(r3Shaped)
H.check(not loaded, "a library without Settings is refused")
H.check(chat:find("completely", 1, true), "with the same message: " .. chat)

local r4Shaped = setmetatable({}, { __call = function()
    return { API = { RegisterEventsReported = function() return true end,
                     ClickEdges = function() end },
             Settings = { New = function() end } }
end })
loaded, err, chat = loadWithout(r4Shaped)
H.check(not loaded, "a library without Engine is refused")
H.check(chat:find("completely", 1, true), "with the same message: " .. chat)

-- Engine.lua threw after defining Engine.New but before its methods, so its
-- last line - the engineMinor marker - never ran. Accepting it would fail
-- later as "attempt to call method 'GroupStat' (a nil value)" mid-refresh.
local halfEngine = setmetatable({}, { __call = function()
    return { API = { RegisterEventsReported = function() return true end,
                     ClickEdges = function() end },
             Settings = { New = function() end }, settingsMinor = 5,
             Engine = { New = function() end } }
end })
loaded, err, chat = loadWithout(halfEngine)
H.check(not loaded, "an Engine.lua that did not load to the end is refused")
H.check(chat:find("completely", 1, true), "with the same message: " .. chat)

local halfSettings = setmetatable({}, { __call = function()
    return { API = { RegisterEventsReported = function() return true end,
                     ClickEdges = function() end },
             Settings = { New = function() end },
             Engine = { New = function() end }, engineMinor = 5 }
end })
loaded, err, chat = loadWithout(halfSettings)
H.check(not loaded, "and so is a Settings.lua that did not")

-- A complete library, as LibStub reports it: its markers equal its MINOR.
local function shaped(minor, markers)
    local l = { API = { RegisterEventsReported = function() return true end,
                        ClickEdges = function() end },
                Settings = { New = function() end }, Engine = { New = function() end },
                UI = { New = function() end } }
    for k, v in pairs(markers) do l[k] = v end
    return setmetatable({}, { __call = function() return l, minor end })
end
local ALL9 = { compatMinor = 9, settingsMinor = 9, engineMinor = 9, uiMinor = 9 }
loaded = loadWithout(shaped(9, ALL9))
H.check(loaded, "a library whose every marker equals its MINOR is accepted")

-- A complete, self-consistent copy that is simply too old: one MINOR behind
-- what this build needs (NEEDS_MINOR). Behaviour is what changes between
-- them - r9 lists who still needs the buff while the popover cannot open -
-- and behaviour cannot be feature-detected, so the floor is a version check.
loaded, err, chat = loadWithout(shaped(8,
    { compatMinor = 8, settingsMinor = 8, engineMinor = 8, uiMinor = 8 }))
H.check(not loaded, "a complete library older than the one this build needs is refused")
H.check(chat:find("completely", 1, true), "with the reinstall message: " .. chat)

-- Another addon loaded a newer copy first, and its UI.lua threw partway:
-- LibStub reports that newer MINOR, but uiMinor is still the older copy's,
-- over a half-replaced UI. Present is not enough - it has to be the ACTIVE
-- copy's.
loaded, err, chat = loadWithout(shaped(8,
    { compatMinor = 8, settingsMinor = 8, engineMinor = 8, uiMinor = 7 }))
H.check(not loaded, "a marker left by an older copy is refused")
H.check(chat:find("completely", 1, true), "as a library that failed to load completely: " .. chat)
loaded = loadWithout(shaped(8, { compatMinor = 7, settingsMinor = 8, engineMinor = 8, uiMinor = 8 }))
H.check(not loaded, "including Compat.lua's own marker")
loaded = loadWithout(shaped(7, { settingsMinor = 7, engineMinor = 7, uiMinor = 7 }))
H.check(not loaded, "and a Compat.lua that never reached its last line")

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
