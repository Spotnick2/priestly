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
-- No fallback copy lives here on purpose. If the library is missing, loading
-- stops with a message that says so, instead of running on a stale duplicate.
-- ============================================================================

Priestly = Priestly or {}

local lib = LibStub and LibStub("LibGroupBuffs-1.0", true)
if not lib then
    error("Priestly: LibGroupBuffs-1.0 did not load. Libs\LibGroupBuffs-1.0 is missing from "
        .. "the addon folder - reinstall Priestly, or run Tools/deploy.ps1 with the library "
        .. "checked out next to the repository.")
end

Priestly.API = lib.API

-- Event registration, with the failures reported.
--
-- The library returns the event names this client rejected rather than
-- printing them, because a library has no business writing to another addon's
-- chat frame. Reporting them is Priestly's job: a silently missing handler is
-- worse than a noisy one, and RegisterEvent throws on unknown names here.
function Priestly.RegisterEvents(frame, ...)
    local ok, failed = lib.API.RegisterEvents(frame, ...)
    if not ok and failed and DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage("|cff99ddff[Priestly]|r |cffff6666unsupported events skipped:|r "
            .. table.concat(failed, ", "))
    end
    return ok, failed
end
