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
    -- Both: the window state lives in the per-character table now, and a
    -- section that left it closed would otherwise decide the next one.
    PriestlyAccountDB, PriestlyDB = nil, nil
    Priestly_EnsureDefaults()
    H.TeachSpells({ "FORT_SINGLE" })
    T.RefreshSpellData()
    WoW.SetUnit("player", { name = "Karuzo Elegia", guid = "P0", class = "PRIEST" })
    WoW.SetUnit("party1", { name = "Zoruka Mortalis", guid = "P1", class = "WARRIOR" })
    WoW.groupMembers = groupSize or 2
end

-- Logically open, which is what the addon's policy is about. In combat the
-- frame can still be on screen after a close, because the client refuses to
-- hide a frame that parents secure buttons.
local function shown()
    local main = T.mainFrame()
    return main ~= nil and main:IsShown() and T.ui:IsVisible()
end

local function settle()
    WoW.flushTimers()
    WoW.flushTimers()   -- a deferred UpdateUI can queue another
end

-- Past the few seconds after login in which a roster arriving is the client
-- catching up rather than the player joining. Wildly and Magely have the same
-- helper, for the same reason.
local function afterLogin() WoW.time = WoW.time + 30 end

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
afterLogin()
WoW.dispatch("GROUP_ROSTER_UPDATE")
settle()
H.check(shown(), "joining a group reopens it - that is what the addon promises")

------------------------------------------------------------
-- A roster arriving just after login is the client catching up, not a join
--
-- GetNumGroupMembers() can still read 0 at PLAYER_LOGIN while already in a
-- group, and the roster lands a moment later. That 0-to-n change looked
-- exactly like joining - the one thing that reopens a window the player
-- deliberately closed - so logging in already grouped with the window shut
-- reopened it AND overwrote the preference, every single login.
--
-- Wildly and Magely fixed this when their review found it; Priestly had the
-- same code and did not, which is what sharing by copying does.
------------------------------------------------------------

setup(0)                       -- the client has not caught up yet
Priestly_SetWindowVisible(false)
WoW.dispatch("PLAYER_LOGIN")
settle()
H.check(not shown(), "a priest who closed the window does not get it back at login")

WoW.groupMembers = 5           -- ...and now the roster arrives
WoW.dispatch("GROUP_ROSTER_UPDATE")
settle()
H.check(not shown(),
    "the roster catching up a moment later does not count as joining")
H.eq(Priestly_WindowVisible(), false,
    "and the deliberate close is still the player's preference")

-- A real invite, once things have settled, still reopens it.
afterLogin()
WoW.groupMembers = 0
WoW.dispatch("GROUP_ROSTER_UPDATE")
settle()
WoW.groupMembers = 3
WoW.dispatch("GROUP_ROSTER_UPDATE")
settle()
H.check(shown(), "a real invite later in the session still reopens it")
H.eq(Priestly_WindowVisible(), true, "and that is remembered")
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
