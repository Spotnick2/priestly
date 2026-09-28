------------------------------------------------------------
-- libfiles.lua - the one reader of LibGroupBuffs-1.0.xml.
--
-- Several tools need to know which files the library consists of: the test
-- harness loads them, run.ps1 syntax-checks them, deploy.ps1 copies them, and
-- CI checks the release zip carries them. They used to parse the XML
-- separately, with five slightly different rules, which would have split the
-- moment the library adds an <Include>: CI would ship a file the harness never
-- loaded. Everything reads the list from here instead.
--
-- Rules, matching how the client reads the file:
--   * comments are removed first, including ones spanning several lines;
--   * <Script file=...> and <Include file=...> are followed in document order;
--   * paths are relative to the XML they appear in, and use backslashes in the
--     XML, forward slashes here;
--   * an <Include> is itself a file that ships, and is read recursively.
--
-- As a module:  local L = dofile("tests/libfiles.lua")
--               local load, ship = L.resolve(root)
-- As a script:  lua tests/libfiles.lua <root> load|ship
--   load  - the Lua files, in the order the client runs them
--   ship  - every file that must be present: XMLs and Lua files
--   Exits non-zero, naming the file, if anything listed does not exist.
------------------------------------------------------------

local L = {}

L.ENTRY = "LibGroupBuffs-1.0.xml"

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

-- Returns load (Lua files, in order) and ship (every required file), both as
-- paths relative to root. Raises an error naming any missing file.
-- Named here rather than globbed, so a texture that stops being drawn stops
-- being shipped, and one that is added has to be added deliberately. This is
-- a third copy of a list the library also keeps, so `resolve` below reads the
-- library's own source and checks the two agree BOTH ways: a texture a newer
-- revision starts drawing is one this list does not have, and a dev deploy
-- would quietly leave it out and draw the window with a hole in it.
L.MEDIA = {
    "Media/body_mask.tga", "Media/body_mask_small.tga",
    "Media/rim5.tga", "Media/rim5_small.tga",
    "Media/rim_dark5.tga", "Media/rim_dark5_small.tga",
    "Media/shadow.tga", "Media/shadow_small.tga",
    "Media/bar_mask.tga", "Media/bar_fill.tga", "Media/bar_edge.tga",
    "Media/gloss.tga", "Media/grain.tga", "Media/sheen2.tga",
}

function L.resolve(root, entry)
    entry = entry or L.ENTRY
    local load, ship, seen, sources = {}, {}, {}, {}

    local function visit(xmlRel)
        if seen[xmlRel] then return end
        seen[xmlRel] = true
        local text = read(root .. "/" .. xmlRel)
        if not text then error("LibGroupBuffs: " .. xmlRel .. " not found in " .. root, 0) end
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
                    error("LibGroupBuffs: " .. xmlRel .. " lists " .. rel .. ", which is not in " .. root, 0)
                end
                sources[rel] = src
                load[#load + 1] = rel
                ship[#ship + 1] = rel
            end
        end
    end

    visit(entry)

    -- Textures are not in any XML: the client loads them by PATH, when the
    -- glass material draws. They still have to be in the addon folder, so a
    -- dev deploy copies them like everything else - and a missing one is a
    -- window drawn with holes in it, which no Lua error announces.
    local listed = {}
    for _, rel in ipairs(L.MEDIA) do
        if not read(root .. "/" .. rel) then
            error("LibGroupBuffs: " .. rel .. " is missing from " .. root
                .. " - the glass material draws it", 0)
        end
        listed[rel] = true
        ship[#ship + 1] = rel
    end

    -- The other direction, which is the one that goes wrong quietly. Nothing
    -- above notices a texture the library ADDED: every file this list names
    -- exists, so it passes, while the new one is never copied. So read what
    -- the library's own source draws and require this list to cover it. Both
    -- spellings the material uses: `MEDIA .. "name"` at the draw, and the
    -- `= "name", <thing>Margin` entries in Glass.SIZES.
    local drawn = {}
    for _, rel in ipairs(load) do
        local src = sources[rel] or ""
        for name in src:gmatch('MEDIA %.%. "([%w_]+)"') do drawn["Media/" .. name .. ".tga"] = rel end
        for name in src:gmatch('= "([%w_]+)", [%w]*[Mm]argin') do drawn["Media/" .. name .. ".tga"] = rel end
    end
    for rel, by in pairs(drawn) do
        if not listed[rel] then
            error("LibGroupBuffs: " .. by .. " draws " .. rel
                .. ", which tests/libfiles.lua does not ship - add it to L.MEDIA", 0)
        end
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
    local root, mode = arg[1], arg[2]
    if not root or (mode ~= "load" and mode ~= "ship") then
        io.stderr:write("usage: lua libfiles.lua <library root> load|ship\n")
        os.exit(2)
    end
    local ok, load, ship = pcall(L.resolve, root)
    if not ok then
        io.stderr:write(tostring(load) .. "\n")
        os.exit(1)
    end
    for _, f in ipairs(mode == "load" and load or ship) do print(f) end
end

return L
