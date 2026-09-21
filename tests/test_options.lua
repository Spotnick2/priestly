------------------------------------------------------------
-- test_options.lua - build the options panel and click everything in it.
--
-- The panel is built lazily on OnShow, so until this file existed none of it
-- ran under test: not the construction, not a single checkbox, radio, slider
-- or bulk button. That put the whole options UI outside the strict-global net
-- in wow_stubs.lua, which is the one thing protecting against an API that
-- quietly went away.
--
--   & 'C:\Program Files (x86)\Lua\5.1\lua.exe' tests\test_options.lua
------------------------------------------------------------

dofile("tests/wow_stubs.lua")
local H = dofile("tests/harness.lua")
local T, TC = H.loadAddon()

WoW.reset()
PriestlyDB = nil
Priestly_EnsureDefaults()
H.TeachSpells({ "FORT_SINGLE", "SPIRIT_SINGLE", "SHADOW_SINGLE" })
T.RefreshSpellData()
WoW.SetUnit("player", { name = "Karuzo Elegia", guid = "P0", class = "PRIEST" })
WoW.SetUnit("party1", { name = "Zoruka Mortalis", guid = "P1", class = "WARRIOR" })
WoW.groupMembers = 2
T.UpdateUI()

local function click(name, ...)
    local f = _G[name]
    if not f then H.check(false, "no widget named " .. name) return end
    local fn = f._scripts and f._scripts.OnClick
    if not fn then H.check(false, name .. " has no OnClick") return end
    local ok, err = pcall(fn, f, ...)
    H.check(ok, name .. " OnClick ran: " .. tostring(err))
    return f
end

-- Did that control ask the frame to refresh? Both refresh helpers defer through
-- C_Timer, so a queued timer is the signal.
local function queued(fn, what)
    WoW.timers = {}
    fn()
    local n = #WoW.timers
    WoW.flushTimers()
    H.check(n > 0, what .. " asks the main frame to refresh")
    return n
end

------------------------------------------------------------
-- The panel builds at all
------------------------------------------------------------

local panel = _G["PriestlyOptionsPanel"]
H.check(panel ~= nil, "the options panel frame exists")
local built, err = pcall(panel._scripts.OnShow, panel)
H.check(built, "it builds on first show: " .. tostring(err))

-- Building twice must not duplicate every widget.
H.check(pcall(panel._scripts.OnShow, panel), "showing it again is a no-op")

------------------------------------------------------------
-- Settings tab
------------------------------------------------------------

PriestlyDB.trackFort = true
local cb = _G["PriestlyCB_trackFort"]
H.check(cb ~= nil, "the Fortitude checkbox was created")
cb:SetChecked(false)
click("PriestlyCB_trackFort")
H.eq(PriestlyDB.trackFort, false, "unchecking it stops tracking Fortitude")
cb:SetChecked(true)
click("PriestlyCB_trackFort")
H.eq(PriestlyDB.trackFort, true, "and checking it starts again")

for _, key in ipairs({ "trackSpirit", "trackPets", "showSolo" }) do
    local box = _G["PriestlyCB_" .. key]
    H.check(box ~= nil, key .. " has a checkbox")
    box:SetChecked(true)
    click("PriestlyCB_" .. key)
    H.eq(PriestlyDB[key], true, key .. " follows its checkbox")
end

-- Shadow Protection mode radios
for _, mode in ipairs({ "always", "detect", "instance" }) do
    click("PriestlyRB_" .. mode)
    H.eq(PriestlyDB.shadowMode, mode, "the " .. mode .. " radio selects that mode")
end
H.check(_G["PriestlyRB_always"]:GetChecked() == false,
    "selecting one radio clears the others")
H.check(_G["PriestlyRB_instance"]:GetChecked() == true, "and checks itself")

-- Lock frame. The client toggles a checkbox before OnClick fires, so the test
-- does too - firing the handler alone just re-reads whatever state it was in.
local lockBox = _G["PriestlyCB_lockFrame"]
H.check(lockBox ~= nil, "the lock checkbox was created")
lockBox:SetChecked(true)
click("PriestlyCB_lockFrame")
H.eq(PriestlyDB.lockFrame, true, "ticking it locks the frame")
lockBox:SetChecked(false)
click("PriestlyCB_lockFrame")
H.eq(PriestlyDB.lockFrame, false, "and clearing it unlocks again")

-- Popover side radios
for _, side in ipairs({ "left", "right", "auto" }) do
    click("PriestlyRB_" .. side)
    H.eq(PriestlyDB.popoverSide, side, "the " .. side .. " radio selects that side")
end
H.check(_G["PriestlyRB_auto"]:GetChecked() == true, "and auto is the one left checked")
H.check(_G["PriestlyRB_left"]:GetChecked() == false, "with the others cleared")

-- Opacity slider
local slider = _G["PriestlyAlphaSlider"]
H.check(slider ~= nil, "the opacity slider was created")
local onValue = slider._scripts.OnValueChanged
H.check(onValue ~= nil, "with a value handler")
H.check(pcall(onValue, slider, 0.5), "which runs")
H.eq(PriestlyDB.frameAlpha, 0.5, "and stores the opacity")
H.check(pcall(onValue, slider, 1.0), "at the top of its range too")
H.eq(PriestlyDB.frameAlpha, 1.0, "which is full opacity")

------------------------------------------------------------
-- Tabs
------------------------------------------------------------

for _, tab in ipairs({ "PriestlyTab1", "PriestlyTab2" }) do
    click(tab)
end

------------------------------------------------------------
-- Instances tab
------------------------------------------------------------

local function instBox(instName)
    return "PriestlyInst_PriestlyInstanceContainer_" .. instName:gsub("%W", "")
end

local box = _G[instBox("Scholomance")]
H.check(box ~= nil, "each instance gets a checkbox")
box:SetChecked(false)
click(instBox("Scholomance"))
H.eq(PriestlyDB.shadowInstances["Scholomance"], false, "unchecking one saves it")

-- Two instances from different categories must not share a global name: the
-- suffix used to be a per-category index, so The Barrow Deeps (Raids #1) and
-- Ragefire Chasm (Dungeons #1) collided and _G kept only one.
H.check(_G[instBox("The Barrow Deeps")] ~= nil, "a raid checkbox exists")
H.check(_G[instBox("The Barrow Deeps")] ~= _G[instBox("Ragefire Chasm")],
    "and is a different frame from the first dungeon's")

------------------------------------------------------------
-- Hooked handlers
--
-- The instance tooltips and the slider's OnShow are installed with HookScript
-- rather than SetScript. The stub used to discard hooks outright, so none of
-- them ran under test and they sat outside the strict-global net.
------------------------------------------------------------

local function runHandler(name, script, ...)
    local f = _G[name]
    if not f then H.check(false, "no widget named " .. name) return end
    local fn = f._scripts and f._scripts[script]
    if not fn then H.check(false, name .. " has no " .. script) return end
    local ok, err = pcall(fn, f, ...)
    H.check(ok, name .. " " .. script .. " ran: " .. tostring(err))
end

runHandler(instBox("Scholomance"), "OnEnter")   -- tooltip with encounter notes
runHandler(instBox("Scholomance"), "OnLeave")
runHandler(instBox("Hyjal Summit"), "OnEnter")
runHandler(instBox("Hyjal Summit"), "OnLeave")
runHandler("PriestlyAlphaSlider", "OnShow")
WoW.flushTimers()                                -- the OnShow hook defers its work

------------------------------------------------------------
-- The bulk buttons must refresh the frame, not just the detector
--
-- In "instance" mode, whether the current instance is checked decides whether
-- the Shadow Protection row exists. Select All / Deselect All / Reset Defaults
-- used to update the detector and stop there, so the row stayed stale until
-- something unrelated rebuilt the UI.
------------------------------------------------------------

PriestlyDB.shadowMode = "instance"
WoW.instanceName = "Scholomance"
WoW.instanceType = "party"

queued(function() click(instBox("Scholomance")) end, "ticking one instance")

queued(function() click("PriestlyInstanceContainerAll") end, "Select All")
for _, entry in ipairs(TC.INSTANCE_DB) do
    H.check(PriestlyDB.shadowInstances[entry[1]] == true, "Select All checked " .. entry[1])
end
H.check(TC.inShadowInstance() == true, "and the detector caught up")

queued(function() click("PriestlyInstanceContainerNone") end, "Deselect All")
H.check(TC.inShadowInstance() == false, "nothing is a shadow instance now")

queued(function() click("PriestlyInstanceContainerDefaults") end, "Reset Defaults")
H.eq(PriestlyDB.shadowInstances["Scholomance"], true, "Reset Defaults restored the default")
H.eq(PriestlyDB.shadowInstances["Onyxia's Lair"], false, "...including the unchecked ones")
H.check(TC.inShadowInstance() == true, "and the detector caught up again")

WoW.instanceType = nil

------------------------------------------------------------
-- Layout measurement before the text has been laid out
--
-- GetStringHeight is 0 for a FontString that has not been laid out yet, which
-- is the normal state inside a scroll child built during OnShow. `0 or 16` is
-- 0 in Lua, so an unguarded measurement reserves only the padding and the next
-- control lands on top of the text.
------------------------------------------------------------

local flat = WoW.makeFrame()
flat.GetStringHeight = function() return 0 end
H.eq(TC.TextHeight(flat), 16, "a zero height falls back to a readable default")
H.eq(TC.TextHeight(flat, 32), 32, "callers can pick their own fallback")

local tall = WoW.makeFrame()
tall.GetStringHeight = function() return 24 end
H.eq(TC.TextHeight(tall), 24, "a real height is used as-is")
H.eq(TC.TextHeight(nil), 16, "and a missing FontString does not error")

-- The panel must build when every measurement comes back zero.
WoW.zeroHeights = true
H.check(pcall(function()
    local p2 = _G["PriestlyOptionsPanel"]
    p2._built = nil                     -- force a rebuild
    p2._scripts.OnShow(p2)
end), "the panel builds even when no text has been measured yet")
WoW.zeroHeights = false

------------------------------------------------------------
-- Opening the panel
------------------------------------------------------------

-- The panel registers itself with the Settings framework on login, which is
-- what OpenToCategory needs.
WoW.dispatch("PLAYER_LOGIN")
WoW.flushTimers()
H.check(pcall(Priestly_OpenConfig), "Priestly_OpenConfig runs")
H.eq(WoW.settingsOpenedTo, 42, "and opens the registered category")

H.done("test_options")
