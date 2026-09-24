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

-- Is the library here, and did the ACTIVE copy load to the end? Each runtime
-- file (Compat, Settings, Engine, UI) sets a marker on its LAST line - their
-- New() sits near the top - so a file that threw partway leaves its marker
-- unset. The marker must EQUAL the active MINOR, not merely be set: several
-- addons embed the library, and if a newer copy throws partway through UI.lua,
-- the older copy's uiMinor and half its functions are still on the shared
-- table. Checked here, with a message, rather than failing as a missing
-- method in the middle of a refresh. The markers arrived with r6, so any older
-- copy is refused the same way.
-- The oldest library this build of Priestly works against. A floor, not a
-- feature check: behaviour changes cannot be feature-detected. r7's
-- ui:Close() returns whether the window is hidden NOW, where r6's returned
-- nothing (`not nil` is true, so every close would have claimed to be waiting
-- for combat), r8 answers the player who closes a window that is still on
-- screen after Priestly closed it itself, r9 lists who still needs the buff while the
-- popover cannot open, and r10 remembers a confirmed absence so that list can
-- say who was missing. Keep this equal to the tag .pkgmeta pins;
-- tests/test_manifest.lua checks that.
local NEEDS_MINOR = 10

local lib, minor
if LibStub then lib, minor = LibStub("LibGroupBuffs-1.0", true) end
local problem, advice
if not lib then
    problem = "the LibGroupBuffs-1.0 library is missing from Priestly's Libs folder"
    advice = "Reinstalling Priestly should fix it."
elseif type(minor) == "number" and minor < NEEDS_MINOR then
    -- Nothing crashed: an older copy loaded first, most likely inside another
    -- addon that embeds this library. Saying "failed to load completely"
    -- would send the player hunting a fault that is not there.
    problem = "another addon has loaded LibGroupBuffs-1.0 r" .. minor
        .. ", and this version of Priestly needs r" .. NEEDS_MINOR .. " or newer"
    advice = "Updating your other addons - or Priestly - should fix it."
elseif not (type(minor) == "number"
            and lib.compatMinor == minor and lib.settingsMinor == minor
            and lib.engineMinor == minor and lib.uiMinor == minor
            and type(lib.API) == "table" and type(lib.API.RegisterEventsReported) == "function"
            and type(lib.API.ClickEdges) == "function"
            and type(lib.Settings) == "table" and type(lib.Settings.New) == "function"
            and type(lib.Engine) == "table" and type(lib.Engine.New) == "function"
            and type(lib.UI) == "table" and type(lib.UI.New) == "function") then
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
    error("Priestly: " .. problem .. " (Libs\\LibGroupBuffs-1.0). Developers: check out "
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
