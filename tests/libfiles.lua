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
function L.resolve(root, entry)
    entry = entry or L.ENTRY
    local load, ship, seen = {}, {}, {}

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
                if not read(root .. "/" .. rel) then
                    error("LibGroupBuffs: " .. xmlRel .. " lists " .. rel .. ", which is not in " .. root, 0)
                end
                load[#load + 1] = rel
                ship[#ship + 1] = rel
            end
        end
    end

    visit(entry)
    return load, ship
end

-- Script entry point, for run.ps1, deploy.ps1 and CI.
if arg and arg[0] and arg[0]:match("libfiles%.lua$") then
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
