------------------------------------------------------------
-- wow_stubs.lua - Priestly's layer over the SHARED stub.
--
-- The client surface itself lives in LibGroupBuffs (tests/wow_stubs.lua), the
-- same way tests/config_scan.lua does: every absence and refusal measured on
-- this client is measured once, for three addons. Priestly kept its own copy
-- until the glass material arrived needing mask, slice and status-bar methods
-- in all three at once - which is the drift that copy was always going to
-- cause (LibGroupBuffs#21).
--
-- What stays here is what is Priestly's alone: the globals it owns, the ones
-- its probe deliberately looks for, and the Encounter Journal functions no
-- other addon in the family calls.
--
--     dofile("tests/wow_stubs.lua")     -- FIRST, in every test file
--     WoW.reset()
------------------------------------------------------------

-- Same rule as tests/harness.lua, which is not loaded yet when this runs.
local LIBRARY = os.getenv("LIBGROUPBUFFS") or "../LibGroupBuffs"
local shared = LIBRARY .. "/tests/wow_stubs.lua"
local chunk = loadfile(shared)
if not chunk then
    error("Priestly's tests need LibGroupBuffs checked out next to this repository "
        .. "(../LibGroupBuffs) or LIBGROUPBUFFS set to its path: " .. shared .. " not found", 0)
end
chunk()

-- A priest, at the level cap of this beta.
WoW.SetPlayerDefaults({ name = "Priestly Testcase", class = "PRIEST", level = 20 })

------------------------------------------------------------
-- The Encounter Journal
--
-- Only Priestly reads it, and only the probe: it is how the instance list
-- would be verified against the client instead of against hand-typed names
-- (issue #12). Modelled as absent by default, because on this client
-- EJ_SelectTier throws while EJ_GetInstanceByIndex works - the case the probe
-- exists to survive.
------------------------------------------------------------

function EJ_GetNumTiers() return WoW.ejNumTiers or 0 end
function EJ_SelectTier(tier)
    if WoW.ejSelectThrows then error("EJ_SelectTier is not available", 2) end
    WoW.ejSelectedTier = tier
end
function EJ_GetTierInfo(tier) return "Tier " .. tostring(tier) end
function EJ_GetInstanceByIndex(index, isRaid)
    local list = (isRaid and WoW.ejRaids) or WoW.ejDungeons
    local entry = list and list[index]
    if not entry then return nil end
    return entry.id, entry.name
end

------------------------------------------------------------
-- Globals that legitimately start out nil
--
-- Reading one is an error unless it is named here: the stub is the list of
-- APIs confirmed to exist on this client, and an unstubbed read is either a
-- typo or an API that quietly went away. These are Priestly's own.
------------------------------------------------------------

WoW.allowGlobal(
    -- The addon and its saved tables. PriestlyAccountDB is the settings store;
    -- PriestlyDB is the per-character one, absent for anyone who never ran the
    -- releases that used it - exactly the read the migration must survive.
    -- PriestlySVCheck is read once so the account scope inherits its
    -- load-check latch.
    "Priestly", "PriestlyAccountDB", "PriestlyDB", "PriestlySVCheck",
    -- The probe's saved variables and frames, which start nil like any others.
    "PriestlyProbeDB", "PriestlyProbePersist", "PriestlyProbeChar",
    "PriestlyProbeCopyFrame", "PriestlyProbeBench",
    "PriestlyProbeBenchA", "PriestlyProbeBenchB", "PriestlyProbeBenchC",
    -- Globals the probe deliberately tests for the presence of.
    "C_EncounterJournal", "EJ_GetNumTiers", "EJ_SelectTier",
    "EJ_GetTierInfo", "EJ_GetInstanceByIndex",
    "C_CVar", "GetCVarBool", "GetCVar", "SetCVar", "RegisterCVar", "GetCVarInfo"
)
