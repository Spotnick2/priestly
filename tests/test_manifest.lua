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
-- Settings are ACCOUNT-WIDE, shared by every character (#9). They were, until
-- #8 moved them per-character because this client wrote account-wide
-- SavedVariables and never read them back; build 70009 fixed that
-- (docs/FOREVER-PROBE.md section 11), so the workaround is over.
--
-- The per-character name stays declared, and that is load-bearing rather than
-- leftover: it holds what players configured under those releases, it is what
-- the migration seeds the shared table from and what `/priestly adopt`
-- re-reads, and a variable the TOC stops declaring may never be handed back
-- at all. Priestly writes no settings key to it again.
--
-- One live table in each scope also lets the load check watch both mechanisms,
-- which is all the old PriestlySVCheck marker table existed for.
------------------------------------------------------------

H.eq(directive("SavedVariables"), "PriestlyAccountDB, PriestlySVCheck",
    "settings are account-wide, which is what #9 decided once the client could load them")
-- PriestlySVCheck is not a store any more. It stays declared because the
-- account scope's load-check history lives in it, and an undeclared variable
-- may never be handed back - losing the latch that says this player was
-- already told the settings bug was fixed.
H.check(tostring(directive("SavedVariables")):find("PriestlySVCheck", 1, true) ~= nil,
    "and the old marker table is still declared, so its load-check latch can be inherited")
H.eq(directive("SavedVariablesPerCharacter"), "PriestlyDB",
    "and the per-character table stays declared, because the migration reads it")
-- Substring, deliberately: "PriestlyAccountDB" does not contain "PriestlyDB",
-- so this catches the double declaration however the list is punctuated. A
-- version of this check that looked for "PriestlyDB," passed against exactly
-- the mistake it names.
H.check(not tostring(directive("SavedVariables")):find("PriestlyDB", 1, true),
    "and PriestlyDB is not ALSO declared account-wide - one name cannot live in two scopes")

------------------------------------------------------------
-- Load order
--
-- LibGlass-1.0 first: LibGroupBuffs' lib:New refuses to make an instance
-- while LibGlass is missing or half-loaded. Then LibGroupBuffs-1.0, then
-- PriestlyCompat, which asks it for Priestly's instance; both other files take
-- file-local aliases from that at load time. Anything out of order and they
-- get nil.
------------------------------------------------------------

local entries = {}
for _, line in ipairs(toc) do
    if line:match("%.[lx][um][al]$") and not line:match("^##") then entries[#entries + 1] = line end
end

local GLASS_XML = "Libs\\LibGlass-1.0\\LibGlass-1.0.xml"
local LIB_XML = "Libs\\LibGroupBuffs-1.0\\LibGroupBuffs-1.0.xml"
H.eq(entries[1], GLASS_XML, "the glass material loads first, through its own XML")
H.eq(entries[2], LIB_XML, "then the shared library that draws with it")
H.eq(entries[3], "PriestlyCompat.lua", "then the bridge that asks it for Priestly's instance")
H.eq(entries[4], "PriestlyConfig.lua", "then the config, which reads Priestly.API at file scope")
H.eq(entries[5], "Priestly.lua", "then the addon proper")
H.eq(#entries, 5, "and nothing else loads")

------------------------------------------------------------
-- Both libraries are embedded, pinned, and never committed
--
-- The TOC paths, the .pkgmeta externals keys and .gitignore have to agree, or
-- the release zip is missing a library while every local check passes. Each
-- external is read BY PATH (tests/pkgmeta.lua): with two of them, "the first
-- tag: in the file" is LibGlass's.
------------------------------------------------------------

local P = dofile("tests/pkgmeta.lua")
local externals = P.externals() or {}
local function embeds(path, xml, url)
    local ext = externals[path]
    H.check(ext ~= nil, ".pkgmeta embeds " .. path)
    ext = ext or {}
    H.eq(path:gsub("/", "\\") .. "\\" .. xml, entries[path:find("LibGlass", 1, true) and 1 or 2],
        "which is exactly where the TOC loads " .. xml .. " from")
    H.eq(ext.url, url, "from its repository")
    -- A tag, or a full commit SHA while a pin is being piloted. Read as the
    -- packager reads it, the whole rest of the line, so an inline comment -
    -- which the packager keeps in the ref - fails here.
    local pinned = (ext.kind == "tag" and tostring(ext.ref):match("^r%d+$"))
        or (ext.kind == "commit" and tostring(ext.ref):match("^%x+$") and #ext.ref == 40)
    H.check(pinned, path .. " is pinned to an r<N> tag or a full commit, so a release cannot "
        .. "change under its own source: " .. tostring(ext.kind) .. " " .. tostring(ext.ref))
    return ext
end
local glass = embeds("Libs/LibGlass-1.0", "LibGlass-1.0.xml", "https://github.com/Spotnick2/LibGlass")
local gb = embeds("Libs/LibGroupBuffs-1.0", "LibGroupBuffs-1.0.xml",
    "https://github.com/Spotnick2/LibGroupBuffs")
local external = "Libs/LibGroupBuffs-1.0"
local n = 0
for _ in pairs(externals) do n = n + 1 end
H.eq(n, 2, "and nothing else is embedded")
-- LibGlass by tag, never `latest` (newest by creation date, else branch HEAD).
H.eq(glass.kind, "tag", "LibGlass is pinned by tag: " .. tostring(glass.ref))

-- The bridge refuses a library older than the behaviour this build needs, and
-- that floor has to be the library actually shipped: pinning a newer one
-- while the floor stays behind means a player with the older library
-- installed gets an addon that starts and quietly misbehaves, which is what
-- the floor exists to prevent. (The opposite, a floor ahead of the pin,
-- refuses to start at all.)
--
-- A tag names its MINOR. A commit does not, so for a commit pin the MINOR is
-- read from that commit in the library checkout's history (`git show`) - not
-- from its working tree, which may be any branch.
local needs = tonumber((H.readFile("PriestlyCompat.lua") or "")
    :match("local NEEDS_MINOR = (%d+)"))
H.check(needs ~= nil, "PriestlyCompat declares the oldest library it works against")
local pinnedMinor
if gb.kind == "tag" then
    pinnedMinor = tonumber(tostring(gb.ref):match("^r(%d+)$"))
else
    -- Only a full hex SHA reaches the shell (the pin check above requires one),
    -- so nothing in .pkgmeta can become part of a command.
    local sha = tostring(gb.ref):match("^%x+$")
    local cmd = 'git -C "' .. H.libraryRoot() .. '" show ' .. tostring(sha) .. ":LibGroupBuffs.lua"
    local src = ""
    if sha and #sha == 40 then
        local pipe = io.popen(cmd .. " 2>&1")
        src = pipe and pipe:read("*a") or ""
        if pipe then pipe:close() end
    end
    pinnedMinor = tonumber(src:match('local MAJOR, MINOR = "LibGroupBuffs%-1%.0", (%d+)'))
    H.check(pinnedMinor ~= nil, "the pinned commit's MINOR could be read with `" .. cmd
        .. "` - the library checkout must have that commit: " .. src:sub(1, 200))
end
H.eq(needs, pinnedMinor,
    "and it is the MINOR .pkgmeta pins: " .. tostring(gb.kind) .. " " .. tostring(gb.ref)
    .. " vs NEEDS_MINOR " .. tostring(needs))

-- lib:New arrived in r26, and the bridge has no other way in: below r26 it
-- would read every healthy library as "failed to load completely" and
-- Priestly would refuse to start for everyone. Rolling the pin back is the
-- way that happens, and this is what stops it landing quietly.
H.check(needs ~= nil and needs >= 26,
    "the floor is r26 or newer, which is where lib:New came from: " .. tostring(needs))

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
-- assurance.
--
-- Read from the library's own list rather than copied, so it cannot drift: a
-- dev file added there, ignored there, and therefore invisible to CI's
-- packager, fails HERE instead of shipping in the next CurseForge release.
-- Dot-paths are skipped - both packagers prune those, which the published zip
-- confirms: its 46 files were exactly the non-dot files at that tag.
local function mirror(path, root)
    local libPkgmeta = H.readFile(root .. "/.pkgmeta")
    H.check(libPkgmeta ~= nil, path .. ": the library checkout has a .pkgmeta to mirror")
    local mirrored, inIgnore = 0, false
    for line in (libPkgmeta or ""):gmatch("[^\r\n]+") do
        if line:match("^ignore:%s*$") then
            inIgnore = true
        -- A top-level comment does not end a YAML list; a later ignore entry
        -- can still follow it and must be mirrored here.
        elseif line:match("^%S") and not line:match("^#") then
            inIgnore = false
        elseif inIgnore then
            local entry = line:match("^%s+%-%s+(%S+)")
            if entry and entry:sub(1, 1) ~= "." then
                mirrored = mirrored + 1
                H.check(ignored(path .. "/" .. entry),
                    path .. "/" .. entry .. " is ignored from here too, not left to the library's own list")
            end
        end
    end
    H.check(mirrored >= 4, path .. ": the library's ignore list was read: " .. mirrored .. " entries")
end
mirror(external, H.libraryRoot())
mirror("Libs/LibGlass-1.0", H.libGlassRoot())

H.done("test_manifest")
