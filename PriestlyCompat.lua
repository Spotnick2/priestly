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

-- Is the library here, and did its compat layer load to the end? ClickEdges is
-- the last function Compat.lua defines, so a file that threw partway through
-- is caught here rather than as a nil call somewhere far from the cause.
local lib = LibStub and LibStub("LibGroupBuffs-1.0", true)
local problem
if not lib then
    problem = "the LibGroupBuffs-1.0 library is missing from Priestly's Libs folder"
elseif not (type(lib.API) == "table" and type(lib.API.RegisterEvents) == "function"
            and type(lib.API.ClickEdges) == "function") then
    problem = "the LibGroupBuffs-1.0 library failed to load completely"
end

if problem then
    -- Said in chat, not only thrown: Lua errors are hidden by default on this
    -- client, and without this line the addon would just be silently dead.
    -- PriestlyConfig.lua and Priestly.lua both check Priestly.API and stop
    -- before building anything, so there is exactly one message.
    if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage("|cff99ddff[Priestly]|r |cffff6666Priestly cannot start:|r "
            .. problem .. ". Reinstalling Priestly should fix it.")
    end
    error("Priestly: " .. problem .. " (Libs\\LibGroupBuffs-1.0). Developers: check out "
        .. "LibGroupBuffs next to the repository and run Tools/deploy.ps1.")
end

Priestly.API = lib.API

-- Priestly's own record of the events this client rejected, for
-- `/dump Priestly.eventFailures`. The library's API.eventFailures is shared by
-- every addon that embeds it, so it cannot say which addon asked.
Priestly.eventFailures = Priestly.eventFailures or {}

-- Event registration, with the failures reported. Priestly code must use this,
-- never API.RegisterEvents directly (tests/test_bridge.lua enforces it): the
-- library returns the rejected names rather than printing them, because a
-- library has no business writing to another addon's chat frame, and a caller
-- that ignores the return value gets a silently dead handler.
function Priestly.RegisterEvents(frame, ...)
    local ok, failed = lib.API.RegisterEvents(frame, ...)
    if not ok and failed then
        for _, ev in ipairs(failed) do
            Priestly.eventFailures[ev] = lib.API.eventFailures and lib.API.eventFailures[ev] or true
        end
        if DEFAULT_CHAT_FRAME then
            DEFAULT_CHAT_FRAME:AddMessage("|cff99ddff[Priestly]|r |cffff6666unsupported events skipped:|r "
                .. table.concat(failed, ", "))
        end
    end
    return ok, failed
end
