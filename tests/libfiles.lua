------------------------------------------------------------
-- libfiles.lua - the one reader of the embedded libraries' XML.
--
-- Several tools need to know which files a library consists of: the test
-- harness loads them, run.ps1 syntax-checks them, deploy.ps1 copies them, and
-- CI checks the release zip carries them. They used to parse the XML
-- separately, with five slightly different rules, which would have split the
-- moment the library adds an <Include>: CI would ship a file the harness never
-- loaded. Everything reads the list from here instead.
--
-- Two libraries are embedded side by side: LibGroupBuffs-1.0 and LibGlass-1.0,
-- the glass material LibGroupBuffs' window draws with. Both are read by the
-- same rules.
--
-- Rules, matching how the client reads the file:
--   * comments are removed first, including ones spanning several lines;
--   * <Script file=...> and <Include file=...> are followed in document order;
--   * paths are relative to the XML they appear in, and use backslashes in the
--     XML, forward slashes here;
--   * an <Include> is itself a file that ships, and is read recursively.
--
-- As a module:  local L = dofile("tests/libfiles.lua")
--               local load, ship = L.resolve(root, nil, glassRoot)
--               local gload, gship = L.glass(glassRoot)
-- As a script:  lua tests/libfiles.lua <root> load|ship [<LibGlass root>]
--               lua tests/libfiles.lua --glass <LibGlass root> load|ship
--   load  - the Lua files, in the order the client runs them
--   ship  - every file that must be present: XMLs, Lua files, and for
--           LibGlass its LICENSE and textures
--   Exits non-zero, naming the file, if anything listed does not exist.
------------------------------------------------------------

local L = {}

L.ENTRY = "LibGroupBuffs-1.0.xml"
L.GLASS_ENTRY = "LibGlass-1.0.xml"

local function read(path)
    local f = io.open(path, "rb")
    if not f then return nil end
    local s = f:read("*a")
    f:close()
    return s
end

local function dirOf(rel)
    return rel:match("^(.*)/[^/]*$") or ""
end

local function join(dir, file)
    return (dir == "" and file) or (dir .. "/" .. file)
end

-- "LibGroupBuffs" or "LibGlass", from the entry's file name, for messages.
local function nameOf(entry)
    return entry:match("^(.-)%-%d") or entry
end

-- Returns load (Lua files, in order) and ship (every XML and Lua file), both
-- as paths relative to root, plus each loaded file's source. Raises an error
-- naming any missing file.
local function readXml(root, entry)
    local lib = nameOf(entry)
    local load, ship, seen, sources = {}, {}, {}, {}

    local function visit(xmlRel)
        if seen[xmlRel] then return end
        seen[xmlRel] = true
        local text = read(root .. "/" .. xmlRel)
        if not text then error(lib .. ": " .. xmlRel .. " not found in " .. root, 0) end
        ship[#ship + 1] = xmlRel
        text = text:gsub("<!%-%-.-%-%->", "")
        local dir = dirOf(xmlRel)
        for tag, file in text:gmatch("<(%a+)%s+file%s*=%s*\"([^\"]+)\"") do
            local rel = join(dir, (file:gsub("\\", "/")))
            if tag == "Include" then
                visit(rel)
            elseif tag == "Script" then
                local src = read(root .. "/" .. rel)
                if not src then
                    error(lib .. ": " .. xmlRel .. " lists " .. rel .. ", which is not in " .. root, 0)
                end
                sources[rel] = src
                load[#load + 1] = rel
                ship[#ship + 1] = rel
            end
        end
    end

    visit(entry)
    return load, ship, sources
end

-- The textures a library's source names, as { ["Media/name.tga"] = file }.
-- Every form a texture is named in: `MEDIA .. "name"` and a local
-- `media .. "name"` at a draw, a SIZES-style `= "name", <thing>Margin` entry,
-- a Mask() argument, and the field forms. The first version of this knew only
-- the first form and SIZES, and missed bar_mask - which is passed to Mask(),
-- the form used most.
function L.drawn(load, sources)
    local drawn = {}
    for _, rel in ipairs(load) do
        -- Comments stripped first: a commented-out draw is not a draw, and
        -- leaving one in would demand a texture nothing uses.
        local src = (sources[rel] or ""):gsub("%-%-[^\n]*", "")
        local function found(pattern)
            for name in src:gmatch(pattern) do drawn["Media/" .. name .. ".tga"] = rel end
        end
        found('[Mm][Ee][Dd][Ii][Aa] %.%. "([%w_]+)"')
        found('= "([%w_]+)", [%w]*[Mm]argin')
        found('Mask%([^,]+, "([%w_]+)"')
        found('mask%s*=%s*"([%w_]+)"')
        found('rim%s*=%s*"([%w_]+)"')
        found('dark%s*=%s*"([%w_]+)"')
        found('shadow%s*=%s*"([%w_]+)"')
    end
    return drawn
end

-- LibGroupBuffs-1.0 (or another entry, by the same rules). Returns load and
-- ship.
--
-- `glassRoot`, when given, is the LibGlass the library draws from. Since r26
-- LibGroupBuffs ships no textures: it draws LibGlass's, through the instance's
-- MEDIA path. The names are still written in its source, so they are read
-- there and each one is required in LibGlass's Media/ - a texture LibGlass
-- drops, or one LibGroupBuffs starts naming that LibGlass never had, fails
-- here instead of drawing the window with a hole in it, which no Lua error
-- announces.
function L.resolve(root, entry, glassRoot)
    entry = entry or L.ENTRY
    local load, ship, sources = readXml(root, entry)
    if glassRoot then
        local count = 0
        for tex, by in pairs(L.drawn(load, sources)) do
            count = count + 1
            if not read(glassRoot .. "/" .. tex) then
                error(nameOf(entry) .. ": " .. by .. " draws " .. tex
                    .. ", which the LibGlass at " .. glassRoot .. " does not have", 0)
            end
        end
        -- A scan that finds nothing proves nothing. The library draws its
        -- bars with at least bar_mask, gloss and bar_edge.
        if count < 3 then
            error(nameOf(entry) .. ": the texture scan found only " .. count .. " drawn textures in "
                .. root .. " - its patterns no longer match the source", 0)
        end
    end
    return load, ship
end

-- LibGlass-1.0: its XML and the files it loads, then LICENSE (MIT: the notice
-- travels with the code) and every texture its own source names. Returns
-- load and ship.
function L.glass(root)
    local load, ship, sources = readXml(root, L.GLASS_ENTRY)
    if not read(root .. "/LICENSE") then error("LibGlass: LICENSE not found in " .. root, 0) end
    ship[#ship + 1] = "LICENSE"
    local textures = {}
    for tex in pairs(L.drawn(load, sources)) do textures[#textures + 1] = tex end
    table.sort(textures)
    if #textures < 10 then
        error("LibGlass: the texture scan found only " .. #textures .. " textures in " .. root
            .. " - its patterns no longer match the source", 0)
    end
    for _, tex in ipairs(textures) do
        if not read(root .. "/" .. tex) then
            error("LibGlass: its source draws " .. tex .. ", which is not in " .. root, 0)
        end
        ship[#ship + 1] = tex
    end
    return load, ship
end

-- Script entry point, for run.ps1, deploy.ps1 and CI.
-- Run as a script, not loaded as a module. Matched on the file NAME: an
-- unanchored "libfiles%.lua$" also matched `tests/test_libfiles.lua`, which
-- then printed this usage and exited before the test could run. A path
-- separator is neither a letter nor an underscore, so this accepts
-- `tests/libfiles.lua` while rejecting `test_libfiles.lua`.
if arg and arg[0] and arg[0]:match("libfiles%.lua$")
    and not arg[0]:match("[%w_]libfiles%.lua$") then
    local glass = arg[1] == "--glass"
    local root, mode, glassRoot
    if glass then root, mode = arg[2], arg[3] else root, mode, glassRoot = arg[1], arg[2], arg[3] end
    if not root or (mode ~= "load" and mode ~= "ship") then
        io.stderr:write("usage: lua libfiles.lua <LibGroupBuffs root> load|ship [<LibGlass root>]\n"
            .. "       lua libfiles.lua --glass <LibGlass root> load|ship\n")
        os.exit(2)
    end
    local ok, load, ship
    if glass then
        ok, load, ship = pcall(L.glass, root)
    else
        ok, load, ship = pcall(L.resolve, root, nil, glassRoot)
    end
    if not ok then
        io.stderr:write(tostring(load) .. "\n")
        os.exit(1)
    end
    for _, f in ipairs(mode == "load" and load or ship) do print(f) end
end

return L
