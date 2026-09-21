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

local function ReadFile(path)
    local f = assert(io.open(path, "rb"))
    local s = f:read("*a")
    f:close()
    return s
end

------------------------------------------------------------
-- Priestly.API IS the library's API - not a copy of it
------------------------------------------------------------

local lib = LibStub("LibGroupBuffs-1.0")
H.check(lib ~= nil, "LibGroupBuffs-1.0 is loaded")
H.check(API == lib.API, "Priestly.API is the library's API table itself")

------------------------------------------------------------
-- Every API function Priestly calls exists in the library
--
-- The point of the library is one copy. If Priestly calls something the
-- library does not have, it only fails when that code path runs in game - so
-- read the source and check every call.
------------------------------------------------------------

local used = {}
for _, file in ipairs({ "Priestly.lua", "PriestlyConfig.lua" }) do
    for name in ReadFile(file):gmatch("API%.([%a_][%w_]*)") do used[name] = true end
end
local count = 0
for name in pairs(used) do
    count = count + 1
    H.check(type(API[name]) == "function",
        "Priestly calls API." .. name .. ", so the library must provide it")
end
H.check(count >= 10, "the scan found Priestly's API calls: " .. count)

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

------------------------------------------------------------
-- A missing library stops loading, with a message that says why
--
-- No fallback copy: running on a stale duplicate is the drift this removes.
------------------------------------------------------------

local savedLibStub = LibStub
LibStub = nil
local loaded, err = pcall(dofile, "PriestlyCompat.lua")
H.check(not loaded, "PriestlyCompat refuses to load without the library")
H.check(tostring(err):find("LibGroupBuffs-1.0", 1, true), "naming it: " .. tostring(err))
LibStub = savedLibStub

H.done("test_bridge")
