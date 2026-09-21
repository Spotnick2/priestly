------------------------------------------------------------
-- test_manifest.lua - assertions about Priestly.toc itself.
--
-- The TOC is not Lua and nothing else in the suite can see it, but two of its
-- lines are load-bearing in ways that are invisible until a player notices
-- something missing: which files load and in what order, and where settings
-- are stored.
--
--   & 'C:\Program Files (x86)\Lua\5.1\lua.exe' tests\test_manifest.lua
------------------------------------------------------------

dofile("tests/wow_stubs.lua")
local H = dofile("tests/harness.lua")

local toc = {}
do
    local f = assert(io.open("Priestly.toc", "r"), "Priestly.toc is missing")
    for line in f:lines() do toc[#toc + 1] = (line:gsub("%s+$", "")) end
    f:close()
end

local function directive(name)
    -- Escape the name: "X-Curse-Project-ID" contains "-", which is a Lua
    -- pattern quantifier, so an unescaped match silently finds nothing.
    local escaped = name:gsub("(%W)", "%%%1")
    for _, line in ipairs(toc) do
        local value = line:match("^##%s*" .. escaped .. ":%s*(.*)$")
        if value then return value end
    end
    return nil
end

local function hasLine(pattern)
    for _, line in ipairs(toc) do
        if line:find(pattern, 1, true) then return true end
    end
    return false
end

------------------------------------------------------------
-- Interface version
------------------------------------------------------------

H.eq(directive("Interface"), "16001",
    "WoW: Forever 1.60.1 is interface 16001 - the %d%02d%02d form, not the transposed 11601 "
    .. "that circulates in the wild")

------------------------------------------------------------
-- Settings storage
--
-- Measured on build 1.60.1.69913: this client writes SavedVariables but never
-- reads ACCOUNT-WIDE ones back, so every session starts from defaults.
-- SavedVariablesPerCharacter does load. Declaring PriestlyDB account-wide
-- again would silently stop every setting from persisting, and the file on
-- disk would still look perfectly correct - which is why this is asserted
-- rather than left to be noticed.
--
-- This is a workaround for a client bug, not a permanent design decision:
-- issue #9 tracks revisiting it once account-wide variables load again. If you
-- are here because you are changing this back, read #9 first - existing
-- per-character settings need seeding across, or everyone's configuration
-- resets a second time.
------------------------------------------------------------

H.eq(directive("SavedVariablesPerCharacter"), "PriestlyDB",
    "PriestlyDB is stored per character, because account-wide storage does not load here")
H.check(directive("SavedVariables") == nil,
    "and is not ALSO declared account-wide - one variable cannot live in both")

------------------------------------------------------------
-- Load order
--
-- PriestlyCompat defines Priestly.API, and both other files take file-local
-- aliases from it at load time. If it is not first they get nil.
------------------------------------------------------------

local files = {}
for _, line in ipairs(toc) do
    if line:match("%.lua$") and not line:match("^##") then files[#files + 1] = line end
end

H.eq(files[1], "PriestlyCompat.lua", "the compat layer loads first")
H.eq(files[2], "PriestlyConfig.lua", "then the config, which reads Priestly.API at file scope")
H.eq(files[3], "Priestly.lua", "then the addon proper")
H.eq(#files, 3, "and nothing else ships")

------------------------------------------------------------
-- Packaging
------------------------------------------------------------

H.eq(directive("Version"), "@project-version@",
    "the packager substitutes the version; deploy.ps1 rewrites it only in the deployed copy")
H.check(directive("X-Curse-Project-ID") ~= nil, "the CurseForge project is declared")
H.check(hasLine("Priestly"), "the title mentions the addon")

------------------------------------------------------------
-- The packaged zip must not carry internal documents
------------------------------------------------------------

local pkg = {}
do
    local f = assert(io.open(".pkgmeta", "r"), ".pkgmeta is missing")
    for line in f:lines() do pkg[#pkg + 1] = line end
    f:close()
end

local function ignored(name)
    for _, line in ipairs(pkg) do
        if line:match("^%s*%-%s*" .. name:gsub("%.", "%%.") .. "%s*$") then return true end
    end
    return false
end

for _, name in ipairs({ "AGENTS.md", "CLAUDE.md", "tests", "Tools", "docs", ".github" }) do
    H.check(ignored(name), name .. " stays out of the release zip")
end

H.done("test_manifest")
