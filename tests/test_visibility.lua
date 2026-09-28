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
-- Logging in alone and THEN being invited still reopens the window
--
-- The regression the roster guard nearly shipped. "Have we ever seen the
-- roster?" answers the login catch-up correctly, but on its own it costs the
-- thing it was protecting: log in alone, get invited, and if the client sent
-- no zero-member roster in between, the invite IS the first observation - so
-- it would not count as joining, and the window would stay shut for the rest
-- of the session.
--
-- GROUP_JOINED is the client saying you joined rather than us inferring it.
-- Note there is deliberately NO zero-member roster update here: that is the
-- whole point, and a test that sent one would pass without the event.
------------------------------------------------------------

setup(0)
Priestly_SetWindowVisible(false)
WoW.dispatch("PLAYER_LOGIN")        -- a fresh session: nothing seen yet
settle()
H.check(not shown(), "logging in alone with the window closed leaves it closed")

WoW.groupMembers = 3
WoW.dispatch("GROUP_JOINED")
WoW.dispatch("GROUP_ROSTER_UPDATE")
settle()
H.check(shown(), "and an invite after it reopens the window")
H.eq(Priestly_WindowVisible(), true, "and is remembered as the player's preference")

-- The event does not make the catch-up roster a join: it is not sent for one.
setup(0)
Priestly_SetWindowVisible(false)
WoW.dispatch("PLAYER_LOGIN")
settle()
WoW.groupMembers = 5
WoW.dispatch("GROUP_ROSTER_UPDATE")   -- no GROUP_JOINED: the client caught up
settle()
H.check(not shown(), "a roster catching up without a join event is still not a join")
H.eq(Priestly_WindowVisible(), false, "and the close still stands")

-- And the latch is spent, not sticky: the next roster change is ordinary
-- churn, not a second join.
setup(0)
Priestly_SetWindowVisible(false)
WoW.dispatch("PLAYER_LOGIN")
settle()
WoW.groupMembers = 2
WoW.dispatch("GROUP_JOINED")
WoW.dispatch("GROUP_ROSTER_UPDATE")
settle()
Priestly_SetWindowVisible(false)
T.CloseUI(true)
settle()
WoW.groupMembers = 3
WoW.dispatch("GROUP_ROSTER_UPDATE")
settle()
H.check(not shown(), "a third member arriving is not another join")

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

------------------------------------------------------------
-- A settings change does not reopen a window the player closed
--
-- Priestly_ForceRebuild runs on EVERY settings change - the shadow mode, an
-- instance checkbox, adopting another character's settings - and it used to
-- call ui:Open unconditionally. So closing the window and then touching any
-- setting brought it straight back.
--
-- Wildly's review found this and fixed it there and in Magely. Priestly had
-- the same code and kept it, which is the second defect this duplication has
-- produced (LibGroupBuffs#22).
------------------------------------------------------------

setup(2)
WoW.dispatch("PLAYER_LOGIN")
settle()
H.check(shown(), "the window is open to begin with")

T.CloseUI(true)                    -- the player closes it
settle()
H.check(not shown(), "and closed when the player says so")
Priestly_ForceRebuild()
settle()
H.check(not shown(), "a settings change does not bring it back")
H.eq(Priestly_WindowVisible(), false, "and the preference is untouched")

-- A window that closed ITSELF - no rows to show - is not a close the player
-- asked for, so a setting that could give it rows again may reopen it.
--
-- The window is really OPENED and then driven to zero rows, rather than a
-- CloseUI(false) call standing in for it. The first version of this called
-- CloseUI on a window that had never been shown, so "an empty window closes
-- itself" was true before the section began and the reopen was from a
-- never-opened state - neither of which is the case being described.
setup(2)
Priestly_SetConfig("showSolo", true)
WoW.dispatch("PLAYER_LOGIN")
settle()
H.check(shown(), "the window is open, with a group to show")

-- Every buff switched off: UI:Update finds no rows and closes it ITSELF,
-- without recording a close the player asked for.
Priestly_SetConfig("trackFort", false)
Priestly_SetConfig("trackSpirit", false)
Priestly_ForceRebuild()
settle()
H.check(not shown(), "a window with nothing to show closes itself")
H.eq(Priestly_WindowVisible(), true, "and does not call that the player's doing")

-- ...and a setting that gives it rows again brings it back, which is the whole
-- point of telling the two kinds of close apart.
Priestly_SetConfig("trackFort", true)
Priestly_ForceRebuild()
settle()
H.check(shown(), "and a setting that gives it rows again reopens it")

-- ...and not for somebody the addon is not for. Nothing would appear anyway -
-- a non-priest has no rows, so Update closes the window straight back - but
-- /priestly config has no class gate, so without this every config click on a
-- warrior in a group scheduled a full rebuild to produce nothing.
setup(2)
WoW.SetUnit("player", { name = "Tanky Person", guid = "P0", class = "WARRIOR" })
WoW.dispatch("PLAYER_LOGIN")
settle()
Priestly_SetWindowVisible(true)
local rebuilds = #WoW.timers
Priestly_ForceRebuild()
H.eq(#WoW.timers, rebuilds, "a settings change on a non-priest schedules nothing")

------------------------------------------------------------
-- The solo toggle is honoured in combat, not dropped
--
-- ui:Open and ui:Close both remember what was asked and carry it out when the
-- fight ends, so there is nothing to protect against here - and returning
-- early meant ticking the box mid-fight did nothing at all, silently. Wildly
-- and Magely already worked this way.
------------------------------------------------------------

setup(0)
Priestly_SetWindowVisible(false)
WoW.dispatch("PLAYER_LOGIN")
settle()
WoW.inCombat = true
-- Through the setting, the way the checkbox does it: the handler is what the
-- config calls AFTER writing showSolo, and a test that only calls the handler
-- leaves the window with no reason to have rows. The first version of this
-- passed only because an earlier section had replaced Priestly_ShowSolo with a
-- stub and never put it back - so the assertion was resting on a leak, and
-- would have broken silently if the sections were ever reordered.
Priestly_SetConfig("showSolo", true)
Priestly_OnSoloToggle(true)
settle()
H.eq(Priestly_WindowVisible(), true,
    "ticking solo mode in combat is recorded, not dropped")
WoW.inCombat = false
WoW.dispatch("PLAYER_REGEN_ENABLED")
settle()
H.check(shown(), "and the window it asked for arrives when the fight ends")

H.done("test_visibility")
