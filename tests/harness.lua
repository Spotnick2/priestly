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
-- Where LibGroupBuffs-1.0 is checked out. tests/run.ps1 sets LIBGROUPBUFFS to
-- the path it resolved (and prints it); running a test file by hand falls back
-- to the sibling checkout. There is deliberately no vendored copy to fall back
-- to: a stale one would make the suite pass against code that no longer ships.
function H.libraryRoot()
    return os.getenv("LIBGROUPBUFFS") or "../LibGroupBuffs"
end

local function readFile(path)
    local f = io.open(path, "rb")
    if not f then return nil end
    local s = f:read("*a")
    f:close()
    return s
end

-- Load a file or stop the run, naming it. A test that silently skipped a
-- missing file is how a load error in the client can pass a green suite.
local function run(path)
    local chunk, err = loadfile(path)
    if not chunk then error("cannot load " .. path .. ": " .. tostring(err), 3) end
    chunk()
end

-- Load everything the TOC loads, in its order: the library through its own
-- XML, exactly as the client reads it, then Priestly's files.
function H.loadAddon()
    local root = H.libraryRoot()
    local xml = readFile(root .. "/LibGroupBuffs-1.0.xml")
    if not xml then
        error("LibGroupBuffs-1.0 not found at " .. root .. ". Check it out next to this "
            .. "repository (../LibGroupBuffs) or set LIBGROUPBUFFS to its path.", 2)
    end
    xml = xml:gsub("<!%-%-.-%-%->", "")
    for file in xml:gmatch('<Script%s+file="([^"]+)"') do
        run(root .. "/" .. file:gsub("\\", "/"))
    end

    for line in (readFile("Priestly.toc") .. "\n"):gmatch("([^\n]*)\n") do
        local file = line:match("^%s*([^#%s][^%s]*%.lua)%s*$")
        if file then run(file) end
    end
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
