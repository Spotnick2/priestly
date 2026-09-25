-- ============================================================================
-- PriestlyCompat.lua  -  the bridge to LibGroupBuffs-1.0's compat layer.
--
-- Every removed or moved API on WoW: Forever 1.60.1 now lives in the shared
-- library (Libs\LibGroupBuffs-1.0, loaded first by the TOC), so Priestly,
-- Wildly and Magely stop keeping three copies that drift. This file only
-- exposes it under the name the rest of Priestly already uses:
--
--     local API = Priestly.API
--
-- No fallback copy lives here on purpose. If the library is missing or broken,
-- Priestly says so in chat and does not start, instead of running on a stale
-- duplicate.
-- ============================================================================

Priestly = Priestly or {}

-- The oldest library this build of Priestly works against. A floor, not a
-- feature check: behaviour changes cannot be feature-detected. r10 remembers
-- a confirmed absence, so the in-combat list can name who was missing rather
-- than shrugging; r12 answers for itself whether a copy is usable, which is
-- what lib.Status below is. Keep this equal to the tag .pkgmeta pins;
-- tests/test_manifest.lua checks that.
local NEEDS_MINOR = 14

-- Is this copy usable? The library answers, from its own list of files, so
-- the marker names and entry points are no longer Priestly's business - this
-- file used to carry them, and got it wrong (#52). A copy older than r12 has
-- no Status to ask, which is itself an answer: either it is too old for this
-- build, or its last file threw before installing it.
--
-- That reading REQUIRES NEEDS_MINOR >= 12, the release Status arrived in. Drop
-- the floor below that - rolling the pin back, say - and a healthy older
-- library with no Status would be called incomplete, and Priestly would
-- refuse to start for everyone. tests/test_manifest.lua holds the floor at 12
-- or above for exactly that reason.
-- Called under pcall: it is library code, reading a shared table that another
-- copy may have left half-built, and a throw here would skip the chat message
-- below - leaving Priestly silently dead, since this client hides Lua errors
-- by default. That is the one failure this file exists to prevent. What it
-- threw goes to the developers' error, not the player's line.
local lib, minor
if LibStub then lib, minor = LibStub("LibGroupBuffs-1.0", true) end
local status, statusError
if lib and type(lib.Status) == "function" then
    local asked, answer = pcall(lib.Status, NEEDS_MINOR)
    if asked then status = answer else status, statusError = "incomplete", answer end
end
if lib and not status then
    status = (type(minor) == "number" and minor < NEEDS_MINOR) and "too-old" or "incomplete"
end

local problem, advice
if not lib then
    problem = "the LibGroupBuffs-1.0 library is missing from Priestly's Libs folder"
    advice = "Reinstalling Priestly should fix it."
elseif status == "too-old" then
    -- The TOC loads Priestly's own copy of the library before this file, and
    -- LibStub UPGRADES an older copy another addon loaded first - so a lower
    -- version here cannot be another addon's doing. It means Priestly's own
    -- bundled copy never registered: the Libs folder is missing, damaged, or
    -- stale. Nothing crashed, though, so this must not read as a crash, and it
    -- must not send the player off to update other addons.
    problem = "the LibGroupBuffs-1.0 library in Priestly's Libs folder is r" .. tostring(minor)
        .. ", and this version of Priestly needs r" .. NEEDS_MINOR
        .. " - its own copy did not load"
    advice = "Reinstalling Priestly should fix it."
elseif status ~= "ok" then
    problem = "the LibGroupBuffs-1.0 library failed to load completely"
    advice = "Reinstalling Priestly should fix it."
end

if problem then
    -- Said in chat, not only thrown: Lua errors are hidden by default on this
    -- client, and without this line the addon would just be silently dead.
    -- PriestlyConfig.lua and Priestly.lua both check Priestly.API and stop
    -- before building anything, so there is exactly one message.
    if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage("|cff99ddff[Priestly]|r |cffff6666Priestly cannot start:|r "
            .. problem .. ". " .. advice)
    end
    error("Priestly: " .. problem .. " (Libs\\LibGroupBuffs-1.0"
        .. (statusError and ("; lib.Status threw: " .. tostring(statusError)) or "")
        .. "). Developers: check out "
        .. "LibGroupBuffs next to the repository and run Tools/deploy.ps1.")
end

Priestly.API = lib.API
-- The settings write path and the client-fix watches; PriestlyConfig.lua
-- builds Priestly's settings object from it.
Priestly.Settings = lib.Settings
-- The buff engine; Priestly.lua builds Priestly's engine from it.
Priestly.Engine = lib.Engine
-- The buff window; Priestly.lua builds Priestly's from it.
Priestly.UI = lib.UI

-- Priestly's own record of the events this client rejected, for
-- `/dump Priestly.eventFailures`. The library also keeps it, as
-- API.eventFailuresByOwner.Priestly; this copy is the short name to type.
Priestly.eventFailures = Priestly.eventFailures or {}

-- How Priestly tells the player. The library never prints - it has no
-- business writing to another addon's chat frame - so it calls this with the
-- names the client rejected, whether it threw or returned false.
local function ReportRejected(failed)
    local mine = lib.API.eventFailuresByOwner and lib.API.eventFailuresByOwner.Priestly or {}
    for _, ev in ipairs(failed) do
        Priestly.eventFailures[ev] = mine[ev] or true
    end
    if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage("|cff99ddff[Priestly]|r |cffff6666unsupported events skipped:|r "
            .. table.concat(failed, ", "))
    end
end

-- Event registration, with the failures reported. Priestly code must use this,
-- never the library's registration directly (tests/test_bridge.lua enforces
-- it), so the reporter is never left out.
function Priestly.RegisterEvents(frame, ...)
    return lib.API.RegisterEventsReported(frame, "Priestly", ReportRejected, ...)
end
