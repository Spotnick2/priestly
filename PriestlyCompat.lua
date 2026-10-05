-- ============================================================================
-- PriestlyCompat.lua  -  the bridge to LibGroupBuffs-1.0.
--
-- Every removed or moved API on WoW: Forever 1.60.1, the buff engine, the
-- window, its open/close policy and the settings write path live in the shared
-- library (Libs\LibGroupBuffs-1.0, loaded by the TOC after LibGlass-1.0, the
-- glass material its window draws with). This file asks the library for
-- Priestly's own instance and exposes it:
--
--     Priestly.GB         the instance: GB.Engine(host), GB.UI(host),
--                         GB.Settings(spec), GB.Visibility(spec), GB.STATES, ...
--     Priestly.API        the compat layer, GB.API, under the name the rest of
--                         Priestly already uses
--
-- lib:New does the version check this file used to carry by hand: it refuses
-- a copy that did not finish loading, a missing or half-loaded LibGlass, and
-- one older than NEEDS_MINOR. No fallback copy lives here on purpose. If the
-- library is missing or refuses, Priestly says so in chat and does not start,
-- instead of running on a stale duplicate.
-- ============================================================================

Priestly = Priestly or {}

-- The oldest library this build of Priestly works against. A floor, not a
-- feature check: behaviour changes cannot be feature-detected. r26 is where
-- lib:New arrived, and r28 where lib:Refusal says why it refused; this file
-- is written against both. Keep this equal to the MINOR .pkgmeta pins;
-- tests/test_manifest.lua checks that.
local NEEDS_MINOR = 28

-- Priestly's own record of the events this client rejected, for
-- `/dump Priestly.eventFailures`. The library also keeps it, as
-- API.eventFailuresByOwner.Priestly; this copy is the short name to type.
Priestly.eventFailures = Priestly.eventFailures or {}

-- Per-kind rewording for the one reporter below, filled in by the files that
-- own each kind (PriestlyConfig.lua: newBuild, settingsLoaded). Looked up when
-- a report arrives, so a filter installed after this file loads is the one
-- that runs. A filter returns the text to print, or nil to say nothing.
Priestly.reportFilters = Priestly.reportFilters or {}

local GB

-- How Priestly tells the player. The library never prints - it has no
-- business writing to another addon's chat frame - so everything it has to
-- say arrives here: the settings checks, and with kind "events" the names
-- the client rejected, whether it threw or returned false.
local function Report(text, kind)
    if kind == "events" then
        text = tostring(text)
        -- Recorded whether or not anything can be printed: the record is what
        -- `/dump Priestly.eventFailures` reads when the line was never seen.
        local mine = GB and GB.EventFailures() or {}
        for ev, why in pairs(mine) do Priestly.eventFailures[ev] = why or true end
        -- The label in red, the names plain - whatever the library calls it.
        -- Its wording is the library's to change, so this matches the shape
        -- ("label: names"), not the words, and a line without a colon is red
        -- throughout rather than plain.
        local label, names = text:match("^([^:]*:)(.*)$")
        text = label and ("|cffff6666" .. label .. "|r" .. names) or ("|cffff6666" .. text .. "|r")
    end
    -- Before any filter: a filter may record that it spoke (newBuild does),
    -- and with no chat frame nothing was said.
    if not DEFAULT_CHAT_FRAME then return end
    local filter = Priestly.reportFilters[kind]
    if filter then text = filter(text, kind) end
    if text then DEFAULT_CHAT_FRAME:AddMessage("|cff99ddff[Priestly]|r " .. text) end
end

local lib, minor
if LibStub then lib, minor = LibStub("LibGroupBuffs-1.0", true) end

-- What a player can do about a copy that did not finish loading. The copy
-- LibStub runs is the newest any addon shipped, so it may well not be
-- Priestly's - and errors are hidden by default, so say how to see them.
local SEE_WHICH = " - one addon's copy of it failed. With /console scriptErrors 1 and /reload,"
    .. " the first error names that addon; updating or disabling it should fix this"

local FAILED = "the LibGroupBuffs-1.0 library failed to load completely. Reinstalling Priestly should fix it"

-- Why lib:New refused, in the words a player needs, by the code lib:Refusal
-- gives (r28, LibGroupBuffs#54) - never by the error's words, which are the
-- library's to change. Refusal returns nil when New would not refuse at all:
-- what New threw was then a bug, or a host mistake such as a second New for
-- the same owner, and reads as a failed load; its text goes to developers
-- only. So does a code this build has never heard of - the library may add
-- codes, and promises only never to rename or remove one.
local function WhyRefusedByCode(why)
    if why == nil then return FAILED end
    if why.code == "incomplete" then
        -- LibStub runs the newest copy any addon shipped, so it may well not
        -- be Priestly's: reinstalling Priestly would change nothing.
        return "the LibGroupBuffs-1.0 library (r" .. tostring(why.active) .. ") did not finish loading"
            .. SEE_WHICH
    elseif why.code == "glass-missing" then
        -- Not registered at all: no addon's copy loaded, and Priestly ships
        -- one in its own Libs folder, so it is Priestly's install.
        return "the LibGlass-1.0 library is missing from Priestly's Libs folder."
            .. " Reinstalling Priestly should fix it"
    elseif why.code == "glass-incomplete" then
        -- Registered but never ready: the newest copy threw partway. Priestly's
        -- own copy loaded, or the name would not be registered at all, so
        -- reinstalling Priestly would change nothing.
        return "the LibGlass-1.0 library (r" .. tostring(why.glassMinor) .. ") did not finish loading"
            .. SEE_WHICH
    elseif why.code == "too-old" then
        return "this version of Priestly needs the LibGroupBuffs-1.0 library r" .. NEEDS_MINOR
            .. " or newer, and the newest copy loaded is r" .. tostring(why.active)
            .. ". Reinstalling Priestly should fix it"
    end
    return FAILED
end

-- The same three facts, read from the libraries' documented markers in New's
-- order, for an active copy with no Refusal to ask: an r26 or r27 another
-- addon shipped, active because Priestly's own r28 never registered. Then the
-- copy running is behind the floor, and that is what the player hears.
local function WhyRefusedByMarkers()
    local _, active = LibStub:GetLibrary("LibGroupBuffs-1.0", true)
    if lib.ready ~= active then return WhyRefusedByCode({ code = "incomplete", active = active }) end
    local glass, glassMinor = LibStub:GetLibrary("LibGlass-1.0", true)
    if type(glass) ~= "table" then return WhyRefusedByCode({ code = "glass-missing" }) end
    if glass.ready ~= glassMinor then
        return WhyRefusedByCode({ code = "glass-incomplete", glassMinor = glassMinor })
    end
    if type(active) == "number" and active < NEEDS_MINOR then
        return WhyRefusedByCode({ code = "too-old", active = active })
    end
    return FAILED
end

local function WhyRefused()
    if type(lib.Refusal) == "function" then return WhyRefusedByCode(lib:Refusal(NEEDS_MINOR)) end
    return WhyRefusedByMarkers()
end

local problem, detail
if not lib then
    problem = "the LibGroupBuffs-1.0 library is missing from Priestly's Libs folder."
        .. " Reinstalling Priestly should fix it"
elseif type(lib.New) ~= "function" then
    -- The TOC loads Priestly's own copy of the library before this file, and
    -- LibStub UPGRADES an older copy another addon loaded first - so a copy
    -- without New cannot be another addon's doing. Below the floor, Priestly's
    -- own copy never registered; at or above it, the copy threw before New
    -- was installed. Neither is a reason to send the player off to update
    -- other addons.
    if type(minor) == "number" and minor < NEEDS_MINOR then
        problem = "the LibGroupBuffs-1.0 library in Priestly's Libs folder is r" .. tostring(minor)
            .. ", and this version of Priestly needs r" .. NEEDS_MINOR
            .. " - its own copy did not load. Reinstalling Priestly should fix it"
    else
        problem = FAILED
    end
else
    -- Under pcall: New is library code on a shared table, and its refusals are
    -- errors. A throw escaping here would skip the chat message below and
    -- leave Priestly silently dead, since this client hides Lua errors by
    -- default.
    local ok, made = pcall(lib.New, lib, { owner = "Priestly", report = Report, needs = NEEDS_MINOR })
    if ok then
        GB = made
    else
        detail = tostring(made)
        -- Under pcall too: it reads shared tables another copy may have left
        -- half-built, and a throw here must still end in the chat line.
        local asked, why = pcall(WhyRefused)
        problem = asked and why or FAILED
    end
end

if problem then
    -- Said in chat, not only thrown: Lua errors are hidden by default on this
    -- client, and without this line the addon would just be silently dead.
    -- PriestlyConfig.lua and Priestly.lua both check Priestly.API and stop
    -- before building anything, so there is exactly one message.
    if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage("|cff99ddff[Priestly]|r |cffff6666Priestly cannot start:|r "
            .. problem .. ".")
    end
    error("Priestly: " .. problem .. " (Libs\\LibGroupBuffs-1.0, Libs\\LibGlass-1.0"
        .. (detail and detail ~= problem and ("; lib:New said: " .. detail) or "")
        .. "). Developers: check out LibGroupBuffs and LibGlass next to the repository and run "
        .. "Tools/deploy.ps1.")
end

Priestly.GB = GB
Priestly.API = GB.API

-- Event registration, with the failures reported. Priestly code must use this,
-- never the library's registration directly (tests/test_bridge.lua enforces
-- it), so the reporter is never left out.
function Priestly.RegisterEvents(frame, ...)
    return GB.RegisterEvents(frame, ...)
end
