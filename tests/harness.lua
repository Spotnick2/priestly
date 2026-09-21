------------------------------------------------------------
-- harness.lua - tiny assertion harness + addon loader.
--
--     local H = dofile("tests/harness.lua")
--     H.loadAddon()
--     H.eq(actual, expected, "what this proves")
--     H.done("test_thing")
--
-- Run from the repo root so the relative paths resolve.
------------------------------------------------------------

local H = { run = 0, failures = 0 }

function H.check(cond, msg)
    H.run = H.run + 1
    if not cond then
        H.failures = H.failures + 1
        print("  FAIL: " .. (msg or "assertion failed"))
    end
end

function H.eq(a, b, msg)
    H.check(a == b, (msg or "values differ") ..
        "  (expected " .. tostring(b) .. ", got " .. tostring(a) .. ")")
end

function H.near(a, b, tol, msg)
    tol = tol or 0.001
    H.check(type(a) == "number" and math.abs(a - b) <= tol,
        (msg or "values differ") .. "  (expected ~" .. tostring(b) .. ", got " .. tostring(a) .. ")")
end

-- Load the addon in TOC order, once.
function H.loadAddon()
    assert(loadfile("PriestlyCompat.lua"))()
    assert(loadfile("PriestlyConfig.lua"))()
    assert(loadfile("Priestly.lua"))()
    return Priestly._test, Priestly._testConfig, Priestly.API
end

-- The three buffs, by the IDs Priestly.lua uses.
H.SPELL = {
    FORT_SINGLE   = 1243,  FORT_GROUP   = 21562,
    SPIRIT_SINGLE = 14752, SPIRIT_GROUP = 27681,
    SHADOW_SINGLE = 976,   SHADOW_GROUP = 27683,
}
H.NAME = {
    FORT_SINGLE   = "Power Word: Fortitude",
    FORT_GROUP    = "Prayer of Fortitude",
    SPIRIT_SINGLE = "Divine Spirit",
    SPIRIT_GROUP  = "Prayer of Spirit",
    SHADOW_SINGLE = "Shadow Protection",
    SHADOW_GROUP  = "Prayer of Shadow Protection",
}

-- Teach the stub client every spell name, and make `known` (a list of keys
-- into H.SPELL) the ones the player actually has.
function H.TeachSpells(known)
    for key, id in pairs(H.SPELL) do
        WoW.DefineSpell(id, H.NAME[key])
    end
    for _, key in ipairs(known or {}) do
        WoW.Know(H.SPELL[key], H.NAME[key])
    end
end

-- Combat aura secrecy as measured on the live client: the flag is set AND
-- every index read throws, while the by-name lookup quietly returns nil.
function H.secrecy(on)
    WoW.secret = on and true or false
    WoW.auraReadsThrow = on and true or false
    WoW.inCombat = on and true or false
end

function H.done(name)
    if H.failures > 0 then
        print(string.format("%s: %d/%d FAILED", name, H.failures, H.run))
        os.exit(1)
    end
    print(string.format("%s: %d tests passed", name, H.run))
end

return H
