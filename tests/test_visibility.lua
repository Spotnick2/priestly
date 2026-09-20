------------------------------------------------------------
-- test_visibility.lua - when the window opens itself, and when it must not.
--
-- Closing the window is a preference, and the addon also opens itself when you
-- join a group. Those two rules meet in a few places where the wrong one used
-- to win: a deliberate close was overwritten on the next login or roster
-- update, and a show asked for during combat was dropped entirely.
--
--   & 'C:\Program Files (x86)\Lua\5.1\lua.exe' tests\test_visibility.lua
------------------------------------------------------------

dofile("tests/wow_stubs.lua")
local H = dofile("tests/harness.lua")
local T = H.loadAddon()

local function setup(groupSize)
    WoW.reset()
    -- The addon's own module state survives between sections of this file,
    -- where a real login always starts with nothing on screen. Close first so
    -- each section is testing the open, not inheriting one.
    WoW.inCombat = false
    T.CloseUI(false)
    PriestlyDB = nil
    Priestly_EnsureDefaults()
    H.TeachSpells({ "FORT_SINGLE" })
    T.RefreshSpellData()
    WoW.SetUnit("player", { name = "Karuzo Elegia", guid = "P0", class = "PRIEST" })
    WoW.SetUnit("party1", { name = "Zoruka Mortalis", guid = "P1", class = "WARRIOR" })
    WoW.groupMembers = groupSize or 2
end

local function shown()
    local main = T.mainFrame()
    return main ~= nil and main:IsShown() and not main._combatHidden
end

local function settle()
    WoW.flushTimers()
    WoW.flushTimers()   -- a deferred UpdateUI can queue another
end

------------------------------------------------------------
-- Login opens the window for a priest in a group
------------------------------------------------------------

setup(2)
WoW.dispatch("PLAYER_LOGIN")
settle()
H.check(shown(), "a priest logging in inside a group gets the window")

------------------------------------------------------------
-- ...but not if it was deliberately closed
------------------------------------------------------------

setup(2)
PriestlyDB.visible = false
WoW.dispatch("PLAYER_LOGIN")
settle()
H.check(not shown(), "a window closed on purpose stays closed across a reload")
H.eq(PriestlyDB.visible, false, "and the preference is not overwritten")

------------------------------------------------------------
-- Roster churn does not reopen a closed window...
------------------------------------------------------------

setup(2)
WoW.dispatch("PLAYER_LOGIN")
settle()
H.check(shown(), "open to start with")

T.CloseUI(true)                     -- /priestly hide
H.check(not shown(), "closed by hand")
H.eq(PriestlyDB.visible, false, "which is remembered")

WoW.groupMembers = 3                -- somebody else joins the existing group
WoW.SetUnit("party2", { name = "Sten Thornbeard", guid = "P2" })
WoW.dispatch("GROUP_ROSTER_UPDATE")
settle()
H.check(not shown(), "a third member joining does not reopen it")
H.eq(PriestlyDB.visible, false, "and does not overwrite the preference")

------------------------------------------------------------
-- ...but joining a group does, because that is the advertised behaviour
------------------------------------------------------------

WoW.groupMembers = 0
WoW.dispatch("GROUP_ROSTER_UPDATE")
settle()
H.check(not shown(), "leaving the group leaves it closed")

WoW.groupMembers = 2
WoW.dispatch("GROUP_ROSTER_UPDATE")
settle()
H.check(shown(), "joining a group reopens it - that is what the addon promises")
H.eq(PriestlyDB.visible, true, "and the preference follows")

------------------------------------------------------------
-- A show asked for during combat happens when combat ends
------------------------------------------------------------

setup(2)
WoW.dispatch("PLAYER_LOGIN")
settle()
T.CloseUI(true)
H.check(not shown(), "closed")

WoW.inCombat = true
SlashCmdList["PRIESTLY"]("show")
settle()
H.check(not shown(), "the window cannot be built during combat lockdown")

WoW.inCombat = false
WoW.dispatch("PLAYER_REGEN_ENABLED")
settle()
H.check(shown(), "so the request is honoured the moment combat ends, not dropped")

------------------------------------------------------------
-- Toggling
------------------------------------------------------------

setup(2)
WoW.dispatch("PLAYER_LOGIN")
settle()
H.check(shown(), "open")
SlashCmdList["PRIESTLY"]("")        -- bare /priestly toggles
settle()
H.check(not shown(), "toggles closed")
SlashCmdList["PRIESTLY"]("")
settle()
H.check(shown(), "and back open")

H.done("test_visibility")
