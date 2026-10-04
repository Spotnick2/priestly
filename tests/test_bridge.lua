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
H.check(Priestly.GB ~= nil and Priestly.GB == lib.instances.Priestly,
    "and Priestly.GB the instance lib:New made for Priestly")
-- The r25 bridge copied each piece onto Priestly; the instance replaces them,
-- and a copy left behind would be a second way in that skips it.
for _, name in ipairs({ "Settings", "Engine", "UI", "Visibility" }) do
    H.eq(Priestly[name], nil, "Priestly." .. name .. " is gone: constructors go through Priestly.GB")
end

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
                                             or code:find("%f[%w_]GB%.RegisterEvents%s*%(")
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
-- The label in red, the names plain - matched by the line's shape, not by the
-- library's words, which are the library's to change.
H.check(said:find("|cffff6666[^|]*:|r", 1) and not said:find("|cffff6666[^|]*REFUSED_EVENT"),
    "the label in red, the names plain: " .. said)
do
    -- A later library that words it differently keeps the same shape.
    local n = #WoW.messages
    Priestly.GB.report("rejected events: SOME_EVENT", "events")
    local reworded = table.concat(WoW.messages, " ", n + 1, #WoW.messages)
    H.check(reworded:find("|cffff6666rejected events:|r SOME_EVENT", 1, true),
        "however the library words it: " .. reworded)
end

-- With no chat frame nothing can be printed, but the record is what
-- `/dump Priestly.eventFailures` reads afterwards, and it must still be made.
do
    local chat = DEFAULT_CHAT_FRAME
    -- false, not nil: the strict stub refuses a read of a global it holds no
    -- value for, and the bridge only tests it for truth.
    DEFAULT_CHAT_FRAME = false
    WoW.badEvents.UNHEARD_EVENT = true
    local registered, why = pcall(Priestly.RegisterEvents, f, "UNHEARD_EVENT")
    DEFAULT_CHAT_FRAME = chat
    H.check(registered, "a rejection with no chat frame does not throw: " .. tostring(why))
    H.check(Priestly.eventFailures.UNHEARD_EVENT ~= nil,
        "and it is recorded in Priestly's table all the same")
end

------------------------------------------------------------
-- One reporter for everything the library says
--
-- The instance carries Priestly's reporter, and the settings object built from
-- it inherits the same one. Each kind's rewording lives with the file that
-- owns it (Priestly.reportFilters); a kind nobody rewords is printed as is.
------------------------------------------------------------

local function reported(text, kind)
    local n = #WoW.messages
    Priestly.GB.report(text, kind)
    return table.concat(WoW.messages, " ", n + 1, #WoW.messages)
end
said = reported("Settings are saved again.", "settingsLoaded")
H.check(said:find("[Priestly]", 1, true) and said:find("|cff55ff55Settings are saved again.|r", 1, true),
    "a settingsLoaded message is printed in green, with Priestly's prefix: " .. said)
said = reported("something new to say", "aKindFromALaterLibrary")
H.check(said:find("something new to say", 1, true),
    "and a kind this build has no filter for is still said, not dropped: " .. said)

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

local FLOOR = tonumber((H.readFile("PriestlyCompat.lua") or ""):match("NEEDS_MINOR = (%d+)"))
H.check(FLOOR ~= nil, "the bridge declares the oldest library it works against")

-- A copy with no New at all. The TOC loads Priestly's own copy first, so this
-- is Priestly's copy not having registered (below the floor) or having
-- thrown before New was installed (at or above it). Either way the player is
-- pointed at Priestly, not at other addons.
local function withoutNew(minor)
    local l = { API = {} }
    return setmetatable({}, { __call = function() return l, minor end })
end

loaded, err, chat = loadWithout(withoutNew(FLOOR - 1))
H.check(not loaded, "a copy without New, below the floor, is refused")
H.check(chat:find("r" .. (FLOOR - 1), 1, true) and chat:find("r" .. FLOOR, 1, true),
    "as too old, naming the version in use and the one needed: " .. chat)
H.check(not chat:find("completely", 1, true), "without claiming a failed load: " .. chat)
H.check(chat:find("Reinstalling", 1, true),
    "and pointing at Priestly's own copy, the only thing that can be behind: " .. chat)

loaded, err, chat = loadWithout(withoutNew(FLOOR))
H.check(not loaded, "a copy without New at the floor is refused too")
H.check(chat:find("completely", 1, true), "as a failed load: " .. chat)

------------------------------------------------------------
-- What the bridge does with each answer from lib:New
--
-- Which copies are usable is the library's question: lib:New refuses a copy
-- that did not finish loading, a missing or half-loaded LibGlass, and one
-- older than the floor, and its own tests cover how it decides
-- (LibGroupBuffs tests/test_new.lua). Priestly's job is to ask with its
-- floor, refuse to start, and tell the player - so these run against the real
-- library, put into each state, rather than a fake that could agree with a
-- bridge asking the wrong question.
------------------------------------------------------------

LibStub, Priestly = savedLibStub, savedPriestly
local GB_MAJOR, GLASS_MAJOR = "LibGroupBuffs-1.0", "LibGlass-1.0"

-- Load the bridge again on the real library. New is once per owner, so the
-- instance the first load made is set aside for the duration and put back.
local function reload()
    local held = lib.instances.Priestly
    lib.instances.Priestly = nil
    Priestly = nil
    local before = #WoW.messages
    local ok, why = pcall(dofile, "PriestlyCompat.lua")
    local said = table.concat(WoW.messages, " ", before + 1, #WoW.messages)
    local made = Priestly and Priestly.GB
    lib.instances.Priestly = held
    Priestly = savedPriestly
    return ok, tostring(why), said, made
end

do
    local ok, why, said, made = reload()
    H.check(ok, "the real library, as loaded, is accepted: " .. why)
    H.eq(said, "", "and nothing is said to the player")
    H.eq(made and made.needs, FLOOR, "and the floor is what the bridge asked New for")
    H.eq(made and made.owner, "Priestly", "under Priestly's own name")
end

-- Another addon's newer copy threw partway: registered, never ready.
do
    local ready = lib.ready
    lib.ready = -1
    local ok, why, said = reload()
    lib.ready = ready
    H.check(not ok, "a library that did not finish loading is refused")
    H.check(said:find("cannot start", 1, true) and said:find("did not finish loading", 1, true),
        "and the player is told so, in the library's words: " .. said)
    H.check(why:find("did not finish loading", 1, true),
        "with the same reason in the error for developers: " .. why)
end

-- LibGlass missing outright, then present but half-loaded. Either way the
-- window cannot draw, so Priestly must not start.
do
    local glass, glassMinor = LibStub.libs[GLASS_MAJOR], LibStub.minors[GLASS_MAJOR]
    LibStub.libs[GLASS_MAJOR], LibStub.minors[GLASS_MAJOR] = nil, nil
    local ok, why, said = reload()
    LibStub.libs[GLASS_MAJOR], LibStub.minors[GLASS_MAJOR] = glass, glassMinor
    H.check(not ok, "a missing LibGlass is refused")
    H.check(said:find("cannot start", 1, true) and said:find(GLASS_MAJOR, 1, true),
        "naming LibGlass to the player: " .. said)
    -- Priestly ships LibGlass itself, so this is its own install, and the
    -- library's wording for it is an instruction to developers.
    H.check(said:find("Reinstalling Priestly", 1, true),
        "pointing them at reinstalling Priestly: " .. said)
    H.check(not said:find("load its XML", 1, true) and not said:find("embed it", 1, true),
        "not at editing load order: " .. said)
    H.check(why:find("lib:New said:", 1, true) and why:find("embed it", 1, true),
        "while developers still get the library's own reason: " .. why)

    local ready = glass.ready
    glass.ready = nil
    ok, _, said = reload()
    glass.ready = ready
    H.check(not ok, "a LibGlass that did not finish loading is refused too")
    H.check(said:find(GLASS_MAJOR, 1, true) and said:find("Reinstalling Priestly", 1, true),
        "the same way: " .. said)
end

-- A Lua error inside New - another copy left a table half-built, or a bug -
-- is not a refusal. Its file and line mean nothing to a player, and must not
-- reach chat; developers get them in the error.
do
    local realNew = lib.New
    lib.New = function() error("attempt to index field 'instances' (a nil value)") end
    local ok, why, said = reload()
    lib.New = realNew
    H.check(not ok, "a New that crashes is refused")
    H.check(said:find("failed to load completely", 1, true) and said:find("Reinstalling", 1, true),
        "as a failed load: " .. said)
    H.check(not said:find("attempt to index", 1, true) and not said:find(":%d+:"),
        "without the Lua error or its position in chat: " .. said)
    H.check(why:find("attempt to index", 1, true), "which goes to developers instead: " .. why)
end

-- A complete copy that is simply behind the floor.
do
    local minor, ready = LibStub.minors[GB_MAJOR], lib.ready
    LibStub.minors[GB_MAJOR], lib.ready = FLOOR - 1, FLOOR - 1
    local ok, _, said = reload()
    LibStub.minors[GB_MAJOR], lib.ready = minor, ready
    H.check(not ok, "a complete library below the floor is refused")
    H.check(said:find("r" .. (FLOOR - 1), 1, true) and said:find("r" .. FLOOR, 1, true),
        "naming the version in use and the one needed: " .. said)
    H.check(not said:find("did not finish", 1, true), "without claiming a failed load: " .. said)
end

-- After all of that, the real instance is the one Priestly is running on.
H.check(lib.instances.Priestly == Priestly.GB, "the refusals left Priestly's own instance alone")

------------------------------------------------------------
-- The real load order: an older copy loaded first is UPGRADED, not refused
--
-- The reloads above call the bridge directly, which is not how the game gets
-- here. Priestly's TOC loads its own copy of the library BEFORE this file, so
-- another addon's older copy has already been upgraded by LibStub when the
-- bridge runs. r25 is the copy every other consumer ships until it moves on,
-- so that is the one loaded first.
------------------------------------------------------------

do
    local root = H.libraryRoot()
    local older = {}
    for _, name in ipairs({ "Compat", "Glass", "Settings", "Engine", "UI", "Visibility" }) do
        older[#older + 1] = root .. "/tests/fixtures/" .. name .. "-r25.lua"
    end
    local haveFixtures = true
    for _, path in ipairs(older) do
        local f = io.open(path, "r")
        if f then f:close() else haveFixtures = false end
    end
    H.check(haveFixtures, "the library checkout carries its r25 fixtures to load first")

    if haveFixtures then
        Priestly = nil
        -- A LibStub with nothing registered, the way a session starts.
        local stub = loadfile(root .. "/LibStub/LibStub.lua")
        LibStub = nil
        stub()

        for _, path in ipairs(older) do loadfile(path)("SomeOtherAddon", {}) end
        local _, before = LibStub:GetLibrary(GB_MAJOR)
        H.eq(before, 25, "another addon's r25 copy registered first")

        -- Now Priestly's own, as its TOC does: LibGlass, then LibGroupBuffs.
        local resolved, files = pcall(H.libraryScripts)
        H.check(resolved, "the libraries resolve: " .. tostring(files))
        for _, path in ipairs(resolved and files or {}) do loadfile(path)("Priestly", {}) end
        local _, after = LibStub:GetLibrary(GB_MAJOR)
        H.check(after > before, "and Priestly's copy upgrades it to r" .. tostring(after))

        local before2 = #WoW.messages
        local ok, why = pcall(dofile, "PriestlyCompat.lua")
        H.check(ok, "so the bridge accepts it, despite the older copy having loaded first: "
            .. tostring(why))
        H.eq(#WoW.messages, before2, "and says nothing to the player")
        H.check(Priestly.API ~= nil and Priestly.GB ~= nil, "with the upgraded library in place")
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

------------------------------------------------------------
-- Every hook the source reads GUARDED is a global the stub allows
--
-- `if Priestly_OpenConfig then` exists because PriestlyConfig.lua can fail to
-- load while Priestly.lua carries on. Under the strict-global stub a name not
-- on the allow-list does not read as nil - it throws - so a guard whose name
-- is missing can never be exercised, and the branch it protects is untested
-- while looking covered. The list and the guards are checked against each
-- other here rather than kept in step by hand.
------------------------------------------------------------

-- The source JOINED, not line by line, and every boolean position - not
-- just `if X` and `X and`. The first version of this scan matched only those
-- two forms on single lines, and missed both
-- `not Priestly_ShowClickHints or Priestly_ShowClickHints()` and a guard whose
-- `and` sits on the next line. A check that half-covers the thing it claims
-- to make impossible is worse than none, because AGENTS.md and the README
-- now both say the drift cannot happen.
local guarded = {}
for file, lines in pairs(SOURCES) do
    local joined = table.concat(lines, " ")
    local function find(pattern)
        for name in joined:gmatch(pattern) do guarded[name] = file end
    end
    find("[^%w_](Priestly_[%a_][%w_]*)%s+and[%s(]")
    find("[^%w_](Priestly_[%a_][%w_]*)%s+or[%s(]")
    find("[^%w_](Priestly_[%a_][%w_]*)%s+then[%s(]")
    find("%f[%w_]not%s+(Priestly_[%a_][%w_]*)")
    find("%f[%w_]if%s+(Priestly_[%a_][%w_]*)")
    find("%f[%w_]elseif%s+(Priestly_[%a_][%w_]*)")
end
local nGuarded = 0
for name, file in pairs(guarded) do
    nGuarded = nGuarded + 1
    H.check(WoW.hostGlobals[name],
        file .. " reads " .. name .. " guarded, so tests/wow_stubs.lua must allow it as nil")
end
H.check(nGuarded >= 5,
    "and the scan found the guards rather than nothing: " .. nGuarded)

H.done("test_bridge")
