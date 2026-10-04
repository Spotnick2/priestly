------------------------------------------------------------
-- pkgmeta.lua - the one reader of .pkgmeta's externals.
--
-- Two libraries are embedded, each with its own url and pin. Reading "the
-- first tag:" in the file - which test_manifest.lua, run.ps1 and CI all did
-- while there was one external - would now read LibGlass's pin as
-- LibGroupBuffs'. So every reader asks for an external BY ITS PATH, here.
--
-- Values are read the way the packager reads them: the whole rest of the line.
-- Its YAML reader keeps an inline "# comment" as part of the value
-- (`commit: 562da7b   # x` became that whole ref), so a comment there must
-- show up here too, not only when the packager fails.
--
-- As a module:  local P = dofile("tests/pkgmeta.lua")
--               local ext = P.externals()["Libs/LibGlass-1.0"]
--               -- ext.url, ext.kind ("tag" or "commit"), ext.ref
-- As a script:  lua tests/pkgmeta.lua <path> [url|kind|ref]
--   Prints the field (default: "<kind> <ref>"); exits non-zero, saying why,
--   if that external or the field is missing.
------------------------------------------------------------

local P = {}

function P.externals(path)
    local f = io.open(path or ".pkgmeta", "rb")
    if not f then return nil, (path or ".pkgmeta") .. " not found" end
    local text = f:read("*a"):gsub("\r", "")
    f:close()

    local out, inExternals, current = {}, false, nil
    for line in (text .. "\n"):gmatch("([^\n]*)\n") do
        if line:match("^externals:%s*$") then
            inExternals = true
        elseif line:match("^%S") and not line:match("^#") then
            inExternals, current = false, nil
        elseif inExternals then
            local key = line:match("^  ([^%s#][^:]*):%s*$")
            if key then
                current = { path = key }
                out[key] = current
            elseif current then
                local field, value = line:match("^    (%a+):%s*(.-)%s*$")
                if field == "url" then
                    current.url = value
                elseif field == "tag" or field == "commit" then
                    current.kind, current.ref = field, value
                end
            end
        end
    end
    return out
end

-- Script entry point, for run.ps1, deploy.ps1 and CI. Matched on the file
-- name, as libfiles.lua is.
if arg and arg[0] and arg[0]:match("pkgmeta%.lua$")
    and not arg[0]:match("[%w_]pkgmeta%.lua$") then
    local key, field = arg[1], arg[2]
    if not key then
        io.stderr:write("usage: lua pkgmeta.lua <external path> [url|kind|ref]\n")
        os.exit(2)
    end
    local all, err = P.externals()
    local ext = all and all[key]
    if not ext then
        io.stderr:write(err or (".pkgmeta declares no external at " .. key), "\n")
        os.exit(1)
    end
    local value
    if field then value = ext[field] else value = ext.kind and (ext.kind .. " " .. tostring(ext.ref)) end
    if not value or value == "" then
        io.stderr:write(".pkgmeta's " .. key .. " has no " .. (field or "tag/commit pin") .. "\n")
        os.exit(1)
    end
    print(value)
end

return P
