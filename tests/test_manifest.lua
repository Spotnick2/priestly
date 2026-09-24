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
-- Measured on build 1.60.1.69913: this client writes SavedVariables and never
-- reads them back - account-wide AND per-character - so every session starts
-- from defaults. (An earlier note here said per-character storage loads. It
-- does not; that was concluded from reading the saved file, which always looks
-- populated because EnsureDefaults rewrites every default each session.)
--
-- So this directive does not make settings persist today. It stays because it
-- is no worse than account-wide, and it is where settings will be read from
-- once Blizzard fixes the loader. Issue #9 tracks the client fix, #35 the
-- preparation for it. If you are changing storage, read both first.
------------------------------------------------------------

H.eq(directive("SavedVariablesPerCharacter"), "PriestlyDB",
    "PriestlyDB is declared per character - no worse than account-wide while neither loads")
-- The only account-wide variable is the load check's marker, so the addon can
-- tell when account-wide storage is fixed (#9 wants to move back to it).
H.eq(directive("SavedVariables"), "PriestlySVCheck",
    "the only account-wide variable is the load-check marker")
H.check(not tostring(directive("SavedVariables")):find("PriestlyDB", 1, true),
    "and PriestlyDB is not ALSO declared account-wide - one variable cannot live in both")

------------------------------------------------------------
-- Load order
--
-- LibGroupBuffs-1.0 provides the compat layer, and PriestlyCompat exposes it
-- as Priestly.API; both other files take file-local aliases from it at load
-- time. Anything out of order and they get nil.
------------------------------------------------------------

local entries = {}
for _, line in ipairs(toc) do
    if line:match("%.[lx][um][al]$") and not line:match("^##") then entries[#entries + 1] = line end
end

local LIB_XML = "Libs\\LibGroupBuffs-1.0\\LibGroupBuffs-1.0.xml"
H.eq(entries[1], LIB_XML, "the shared library loads first, through its own XML")
H.eq(entries[2], "PriestlyCompat.lua", "then the bridge that exposes it as Priestly.API")
H.eq(entries[3], "PriestlyConfig.lua", "then the config, which reads Priestly.API at file scope")
H.eq(entries[4], "Priestly.lua", "then the addon proper")
H.eq(#entries, 4, "and nothing else loads")

------------------------------------------------------------
-- The library is embedded, pinned, and never committed
--
-- The TOC path, the .pkgmeta externals key and .gitignore have to agree, or
-- the release zip is missing the library while every local check passes.
------------------------------------------------------------

local pkgmeta = H.readFile(".pkgmeta") or ""
local external = pkgmeta:match("externals:%s*\n%s+([^\n:]+):")
H.eq(external, "Libs/LibGroupBuffs-1.0", ".pkgmeta embeds the library at Libs/LibGroupBuffs-1.0")
H.eq(external and (external:gsub("/", "\\") .. "\\LibGroupBuffs-1.0.xml"), LIB_XML,
    "which is exactly where the TOC loads it from")
H.check(pkgmeta:find("url: https://github.com/Spotnick2/LibGroupBuffs", 1, true) ~= nil,
    "from the LibGroupBuffs repository")
local tag = pkgmeta:match("\n%s+tag:%s*(%S+)")
H.check(tag ~= nil and tag:match("^r%d+$") ~= nil,
    "pinned to a library tag, so a release cannot change under its own source: " .. tostring(tag))

-- The bridge refuses a library older than the behaviour this build needs, and
-- that floor has to be the tag actually shipped: pinning a newer tag while the
-- floor stays behind means a player with the older library installed gets an
-- addon that starts and quietly misbehaves, which is what the floor exists to
-- prevent. (The opposite, a floor ahead of the pin, refuses to start at all.)
local needs = tonumber((H.readFile("PriestlyCompat.lua") or "")
    :match("local NEEDS_MINOR = (%d+)"))
H.check(needs ~= nil, "PriestlyCompat declares the oldest library it works against")
H.eq(needs, tonumber(tostring(tag):match("^r(%d+)$")),
    "and it is the tag .pkgmeta pins: " .. tostring(tag) .. " vs NEEDS_MINOR " .. tostring(needs))

local libIgnored = false
for line in ((H.readFile(".gitignore") or "") .. "\n"):gmatch("([^\n]*)\n") do
    if line == "Libs/" then libIgnored = true end
end
H.check(libIgnored, "and Libs/ is git-ignored, so no vendored copy can creep back in")

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

-- Every Lua pattern character escaped, not just the dot: a path like
-- Libs/LibGroupBuffs-1.0/tests carries a `-`, which is a quantifier in a
-- pattern, so a name-only escape silently matches nothing and the check
-- passes for the wrong reason.
local function ignored(name)
    local literal = name:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%1")
    for _, line in ipairs(pkg) do
        if line:match("^%s*%-%s*" .. literal .. "%s*$") then return true end
    end
    return false
end

for _, name in ipairs({ "AGENTS.md", "CLAUDE.md", "tests", "Tools", "docs", ".github" }) do
    H.check(ignored(name), name .. " stays out of the release zip")
end

-- The library's dev files have to be named HERE as well, because the packager
-- that builds the release does not apply an external's own ignore list - the
-- v2.0.6 download carried the library's tests and notes, 46 files instead of
-- 7. Harmless (nothing there loads) but it made the library's .pkgmeta a false
-- assurance, so these entries are the real guarantee and must not be dropped.
for _, name in ipairs({ "Libs/LibGroupBuffs-1.0/tests", "Libs/LibGroupBuffs-1.0/AGENTS.md",
                        "Libs/LibGroupBuffs-1.0/CLAUDE.md", "Libs/LibGroupBuffs-1.0/README.md",
                        "Libs/LibGroupBuffs-1.0/.pkgmeta" }) do
    H.check(ignored(name), name .. " is ignored from here, not left to the library's own list")
end

H.done("test_manifest")
