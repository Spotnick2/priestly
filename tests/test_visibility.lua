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


------------------------------------------------------------
-- A roster arriving before PLAYER_LOGIN has ever run is not a join
--
-- FIRST in this file on purpose. The guard is "have we ever seen the roster?",
-- and the answer starts as "no" when the file loads - so any section that has
-- already dispatched a login has answered it and could not tell a correct
-- starting value from a wrong one. This section can, and it is the only one
-- that can.
--
-- Reachable: the events are registered at file scope, and unlike Wildly and
-- Magely, Priestly does not discard non-login events before it knows the
-- player's class - so the roster branch really does run here.
------------------------------------------------------------

setup(0)
Priestly_SetWindowVisible(false)
WoW.groupMembers = 5
WoW.dispatch("GROUP_ROSTER_UPDATE")
settle()
H.eq(Priestly_WindowVisible(), false, "a roster arriving before login is not a join")
WoW.dispatch("PLAYER_LOGIN")
settle()
H.check(not shown(), "and the window the player closed stays closed")

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

-- A real invite still reopens it, once we have actually seen them alone.
WoW.groupMembers = 0
WoW.dispatch("GROUP_ROSTER_UPDATE")
settle()
WoW.groupMembers = 3
WoW.dispatch("GROUP_ROSTER_UPDATE")
settle()
H.check(shown(), "a real invite later in the session still reopens it")
H.eq(Priestly_WindowVisible(), true, "and that is remembered")

------------------------------------------------------------
-- The two ways a few seconds' grace would still have got this wrong
--
-- The first version of this guard gave the roster five seconds after
-- PLAYER_LOGIN to arrive. That is a guess at the wrong question: it has to be
-- longer than the slowest loading screen and shorter than a real invite, and
-- when it is wrong it fails silently and looks exactly like the bug. Asking
-- whether we have EVER seen the roster needs no clock.
------------------------------------------------------------

-- A loading screen longer than any grace period would have been. The clock is
-- not consulted at all now, so thirty seconds between login and the roster
-- changes nothing.
setup(0)
Priestly_SetWindowVisible(false)
WoW.dispatch("PLAYER_LOGIN")
settle()
WoW.time = WoW.time + 300
WoW.groupMembers = 5
WoW.dispatch("GROUP_ROSTER_UPDATE")
settle()
H.eq(Priestly_WindowVisible(), false,
    "however long the world takes to load, the first roster is not a join")
H.check(not shown(), "and the window stays closed")

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
