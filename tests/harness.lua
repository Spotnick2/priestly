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

-- A whole file as text with CRLF normalised, or nil if it does not exist. The
-- one reader for the tests: they used to carry four copies that disagreed
-- about CRLF and about whether a missing file was an error.
function H.readFile(path)
    local f = io.open(path, "rb")
    if not f then return nil end
    local s = f:read("*a")
    f:close()
    return (s:gsub("\r\n", "\n"))
end

-- The addon's own Lua files, in the order Priestly.toc loads them. Read from
-- the TOC so a new file cannot be missed by the tests that scan every file.
function H.tocFiles()
    local files = {}
    local toc = assert(H.readFile("Priestly.toc"), "Priestly.toc not found - run from the repo root")
    for line in (toc .. "\n"):gmatch("([^\n]*)\n") do
        local file = line:match("^%s*([^#%s][^%s]*%.lua)%s*$")
        if file then files[#files + 1] = file end
    end
    return files
end

-- Where LibGroupBuffs-1.0 is checked out. tests/run.ps1 sets LIBGROUPBUFFS to
-- the path it resolved (and prints it); running a test file by hand falls back
-- to the sibling checkout. There is deliberately no vendored copy to fall back
-- to: a stale one would make the suite pass against code that no longer ships.
function H.libraryRoot()
    return ((os.getenv("LIBGROUPBUFFS") or "../LibGroupBuffs"):gsub("\\", "/"):gsub("/$", ""))
end

-- Where LibGlass-1.0 is checked out: LIBGLASS (run.ps1 and CI set it), else
-- the sibling checkout. Fails loudly when it is not there - a missing
-- material is not something to skip.
function H.libGlassRoot()
    local root = (os.getenv("LIBGLASS") or "../LibGlass"):gsub("\\", "/"):gsub("/$", "")
    local f = io.open(root .. "/LibGlass-1.0.xml", "rb")
    if not f then
        error("LibGlass checkout not found at " .. root .. " (no LibGlass-1.0.xml): clone "
              .. "github.com/Spotnick2/LibGlass next to this repository or set LIBGLASS", 0)
    end
    f:close()
    return root
end

-- Load a file or stop the run, naming it. A test that silently skipped a
-- missing file is how a load error in the client can pass a green suite.
-- The arguments are what the client passes an addon's file: its name and
-- the addon's private table.
local function run(path, ...)
    local chunk, err = loadfile(path)
    if not chunk then error("cannot load " .. path .. ": " .. tostring(err), 3) end
    chunk(...)
end

-- The files the TOC's library lines load, in order: LibGlass's, then
-- LibGroupBuffs', as full paths - read with tests/libfiles.lua, the same
-- reader run.ps1, deploy.ps1 and CI use. LibGroupBuffs is checked against the
-- LibGlass it draws from: a texture it names that LibGlass lacks fails here.
function H.libraryScripts()
    local L = dofile("tests/libfiles.lua")
    local glassRoot, root = H.libGlassRoot(), H.libraryRoot()
    local files = {}
    local ok, load = pcall(L.glass, glassRoot)
    if not ok then error(tostring(load), 2) end
    for _, file in ipairs(load) do files[#files + 1] = glassRoot .. "/" .. file end
    ok, load = pcall(L.resolve, root, nil, glassRoot)
    if not ok then
        -- Only a MISSING checkout gets the "check your checkout" advice.
        -- resolve also fails when a texture is undeclared, and telling someone
        -- with a perfectly good clone to re-clone it sends them away from the
        -- one line that says what is actually wrong.
        local why = tostring(load)
        if why:find("not found in", 1, true) then
            why = why .. ". Check LibGroupBuffs out next to this repository "
                .. "(../LibGroupBuffs) or set LIBGROUPBUFFS to its path."
        end
        error(why, 2)
    end
    for _, file in ipairs(load) do files[#files + 1] = root .. "/" .. file end
    return files
end

-- Load everything the TOC loads, in its order: LibGlass, then LibGroupBuffs,
-- then Priestly's files. Each gets ("Priestly", ns), as in the client.
function H.loadAddon()
    local ns = {}
    for _, path in ipairs(H.libraryScripts()) do run(path, "Priestly", ns) end
    for _, file in ipairs(H.tocFiles()) do run(file, "Priestly", ns) end
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
