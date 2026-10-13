-- The Arena module: the tracker's estimates driven by a fake backend (rounds,
-- teammates changing, externals and who cast them, charges and refreshes,
-- mid-round starts, the self-test), the rows, the settings page.

local T = dofile(HERE .. "/stubs.lua")
local check, eq, W, fire, flush = T.check, T.eq, T.W, T.fire, T.flush
T.captureChat()

local CK = T.boot()
check(T.loaded.CombatKit_Arena == nil, "off by default: never loaded")
CK.SetModuleEnabled("Arena", true)
local AR = CK.modules.Arena
check(AR and AR.enabled and AR.IsRunning(), "switched on: loaded and running")
local TR = AR.Tracker

-- a backend that reports what the test says
local fake = { watches = {}, started = false }
function fake.Start(cb) fake.cb = cb; fake.started = true end
function fake.Stop() fake.started = false end
function fake.SetWatch(unit, defs) fake.watches[unit] = defs end
AR.UseBackend(fake)

local function shown(unit, id, at, initial) W.now = at; fake.cb.Shown(unit, id, at, initial) end
local function hidden(unit, id, at) W.now = at; fake.cb.Hidden(unit, id, at) end
local function expired(unit, id, at) W.now = at; fake.cb.Expired(unit, id, at) end
local function state(unit, id, at)
	W.now = at or W.now
	local t = TR.Get(unit)
	local e = t and t.spells[id]
	if not e then return "none" end
	return TR.State(e, W.now)
end

-- ---------------------------------------------------------------- out in the world: nothing
check(not fake.started, "outside an arena the backend is not started")
check(next(AR.UI.Rows()) == nil or not AR.UI.Rows().player:IsShown(), "no row outside an arena")

-- ---------------------------------------------------------------- into an arena: a druid and a priest
W.inInstance, W.instanceType = true, "arena"
W.units.player = { friendly = true }
W.units.party1 = { friendly = true, class = "DRUID", guid = "Player-1-DRUID" }
W.units.party2 = { friendly = true, class = "PRIEST", guid = "Player-1-PRIEST" }
W.now = 0
fire("PLAYER_ENTERING_WORLD")
check(fake.started, "entering an arena starts the backend")
check(fake.watches.party1 and #fake.watches.party1 == #AR.SpellsFor("DRUID", true), "every druid ability is watched on party1")
check(fake.watches.player and #fake.watches.player == #AR.SpellsFor("DEMONHUNTER", true), "the player's own row is watched too")
eq(state("party1", 22812), "unknown", "before the gates open nothing is known")

W.matchState = 3
fire("PVP_MATCH_STATE_CHANGED")
eq(state("party1", 22812), "ready", "the round starts: everything is ready")
eq(state("party2", 33206), "ready", "for everyone")
AR.UI.Refresh(0)
check(AR.UI.Rows().party1:IsShown() and AR.UI.Rows().party2:IsShown() and AR.UI.Rows().player:IsShown(), "three rows up")

-- ---------------------------------------------------------------- a self buff: Barkskin
shown("party1", 22812, 10)
eq(state("party1", 22812), "active", "the buff is drawn: active")
hidden("party1", 22812, 18)
local s, readyAt = state("party1", 22812, 18)
eq(s, "cooling", "the buff is gone: cooling")
eq(readyAt, 70, "ready again 60 s after it appeared, not after it ended")
eq(state("party1", 22812, 69.9), "cooling", "still cooling just before")
eq(state("party1", 22812, 70.1), "ready", "ready when the cooldown has run")

-- ---------------------------------------------------------------- charges: Survival Instincts, two of them
local s1, _, left = state("party1", 61336, 100)
eq(s1, "ready", "two charges, none used: ready")
eq(left, 2, "both charges left")
shown("party1", 61336, 100)
expired("party1", 61336, 106)
hidden("party1", 61336, 106)
s1, _, left = state("party1", 61336, 107)
eq(s1, "ready", "one charge used, one left: still ready")
eq(left, 1, "one left")
eq(TR.KnownDuration(61336), 6, "the buff's length is learned from its full course")
shown("party1", 61336, 120)
hidden("party1", 61336, 126)
s1, readyAt, left = state("party1", 61336, 127)
eq(s1, "cooling", "both charges used: cooling")
eq(left, 0, "none left")
eq(readyAt, 280, "the first charge is back 180 s after the first use")
s1, _, left = state("party1", 61336, 281)
eq(s1, "ready", "one charge back")
eq(left, 1, "and counted")
eq(state("party1", 61336, 461), "ready", "the second one recharges after the first: 280 + 180")
local _, _, left2 = state("party1", 61336, 461)
eq(left2, 2, "both back")

-- a refresh: the second use while the first buff is still up leaves no edge, but a longer buff
W.matchState = 3; fire("PVP_MATCH_STATE_CHANGED")   -- a new round, everything ready
shown("party1", 61336, 500)
expired("party1", 61336, 509)   -- 9 s, the learned length is 6: refreshed at 503
hidden("party1", 61336, 509)
s1, _, left = state("party1", 61336, 510)
eq(left, 0, "the refresh counted as the second use")
eq(s1, "cooling", "so both charges are spent")

-- ---------------------------------------------------------------- externals: Pain Suppression on the druid
W.matchState = 3; fire("PVP_MATCH_STATE_CHANGED")
shown("party1", 33206, 600)
eq(state("party2", 33206), "active", "the only priest gets the credit")
eq(state("party1", 33206), "none", "the druid has no such ability")
hidden("party1", 33206, 608)
eq(state("party2", 33206, 608), "cooling", "and the cooldown")
check(not TR.Get("party2").spells[33206].ambiguous, "unambiguous")

-- the player's own cast of an external it has is the player's, not a teammate's
W.units.player = { friendly = true, class = "PRIEST", guid = "Player-0-ME" }
fire("GROUP_ROSTER_UPDATE")
W.matchState = 3; fire("PVP_MATCH_STATE_CHANGED")
W.now = 700
fire("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-1", 33206)
shown("party1", 33206, 700.2)
eq(state("player", 33206), "active", "the player cast it a moment ago: the player's")
eq(state("party2", 33206, 700.2), "ready", "the other priest is left alone")
hidden("party1", 33206, 708)

-- no cast of ours: the player is never a candidate, the one priest teammate is
shown("party1", 33206, 900)
eq(state("party2", 33206, 900), "active", "the teammate's")
eq(state("player", 33206, 900), "ready", "not the player's: the player's casts are known")
hidden("party1", 33206, 908)

-- two priest teammates: both are credited and marked
W.units.player = { friendly = true, class = "DEMONHUNTER", guid = "Player-0-ME" }
W.units.party1 = { friendly = true, class = "PRIEST", guid = "Player-1-PRIEST-A" }
fire("GROUP_ROSTER_UPDATE")
W.matchState = 3; fire("PVP_MATCH_STATE_CHANGED")
shown("player", 33206, 950)
check(TR.Get("party1").spells[33206].ambiguous and TR.Get("party2").spells[33206].ambiguous, "two candidates: both marked")
eq(state("party1", 33206, 950), "active", "both active")
eq(state("party2", 33206, 950), "active", "both active, the other one")
hidden("player", 33206, 958)

-- a dead candidate did not cast it
W.units.party2.dead = true
W.matchState = 3; fire("PVP_MATCH_STATE_CHANGED")
shown("player", 33206, 1000)
eq(state("party1", 33206, 1000), "active", "the living priest")
eq(state("party2", 33206, 1000), "ready", "not the dead one")
check(not TR.Get("party1").spells[33206].ambiguous, "and no mark")
hidden("player", 33206, 1008)
W.units.party2.dead = nil

-- Blessing of Sacrifice cannot be on its caster: the holder is excluded
W.units.party1 = { friendly = true, class = "PALADIN", guid = "Player-1-PAL" }
W.units.party2 = { friendly = true, class = "PALADIN", guid = "Player-1-PAL2" }
fire("GROUP_ROSTER_UPDATE")
W.matchState = 3; fire("PVP_MATCH_STATE_CHANGED")
shown("party1", 6940, 1100)
eq(state("party2", 6940, 1100), "active", "the other paladin cast it")
eq(state("party1", 6940, 1100), "ready", "not the one wearing it")
hidden("party1", 6940, 1112)

-- an area buff lands on several allies within a frame: one use
shown("party1", 1022, 1200)
shown("party2", 1022, 1200.05)
check(TR.Get("party1").spells[1022].ambiguous, "two paladins could have cast Blessing of Protection")
local uses = #TR.Get("party1").spells[1022].uses
eq(uses, 1, "seen twice, one use")

-- ---------------------------------------------------------------- a teammate arrives mid round: unknown until seen
W.units.party1 = { friendly = true, class = "DRUID", guid = "Player-2-DRUID" }
fire("GROUP_ROSTER_UPDATE")
eq(state("party1", 22812, 1300), "unknown", "a new teammate: nothing known")
eq(state("party2", 642, 1300), "ready", "the one who stayed keeps his state")
shown("party1", 22812, 1310, true)
eq(state("party1", 22812, 1310), "active", "already up as we began to look: active")
hidden("party1", 22812, 1318)
eq(state("party1", 22812, 1318), "unknown", "but its start is unknown, so still unknown afterwards")
shown("party1", 22812, 1400)
hidden("party1", 22812, 1408)
eq(state("party1", 22812, 1408), "cooling", "the first use seen from the start: known from here")

-- a single charge used again sooner than the estimate: the estimate was too long
W.matchState = 3; fire("PVP_MATCH_STATE_CHANGED")
shown("party1", 22812, 1500); hidden("party1", 22812, 1508)
shown("party1", 22812, 1550); hidden("party1", 22812, 1558)
eq(TR.Get("party1").spells[22812].cd, 50, "two uses 50 s apart: the cooldown is at most 50")
local _, ra = state("party1", 22812, 1558)
eq(ra, 1600, "and the display follows")

-- what must not correct the estimate
W.units.player = { friendly = true, class = "DEMONHUNTER", guid = "Player-0-ME" }
W.units.party1 = { friendly = true, class = "DEMONHUNTER", guid = "Player-1-DH" }
W.units.party2 = { friendly = true, class = "MAGE", guid = "Player-1-MAGE" }
fire("GROUP_ROSTER_UPDATE")
W.matchState = 3; fire("PVP_MATCH_STATE_CHANGED")
-- an area buff: allies walk in and out of Darkness for 8 s; one use, no correction
shown("party2", 196718, 1700)
shown("player", 196718, 1703)
hidden("player", 196718, 1705)
shown("player", 196718, 1706)
eq(#TR.Get("party1").spells[196718].uses, 1, "allies walking in and out of an area buff: one use")
eq(TR.Get("party1").spells[196718].cd, 300, "and the estimate untouched")
shown("party2", 196718, 1720)
eq(#TR.Get("party1").spells[196718].uses, 2, "a sighting after the effect has run: another use")
eq(TR.Get("party1").spells[196718].cd, 300, "which still corrects nothing")
-- a talent may add a charge: two close uses are two charges, not a shorter cooldown
shown("party1", 198589, 1800); hidden("party1", 198589, 1810)
shown("party1", 198589, 1830); hidden("party1", 198589, 1840)
eq(TR.Get("party1").spells[198589].cd, 60, "Blur twice in 30 s: a second charge, the estimate stays")
-- a reset can bring an ability back: Ice Block twice says nothing about its cooldown
shown("party2", 45438, 1900); hidden("party2", 45438, 1910)
shown("party2", 45438, 1930); hidden("party2", 45438, 1940)
eq(TR.Get("party2").spells[45438].cd, 240, "Ice Block twice: the estimate stays")
-- two of a class: a use that may be either's corrects neither
W.units.party2 = { friendly = true, class = "DEMONHUNTER", guid = "Player-1-DH2" }
fire("GROUP_ROSTER_UPDATE")
W.matchState = 3; fire("PVP_MATCH_STATE_CHANGED")
shown("player", 196718, 2000)
shown("player", 196718, 2020)
check(TR.Get("party1").spells[196718].ambiguous and TR.Get("party2").spells[196718].ambiguous, "either demon hunter's Darkness")
eq(TR.Get("party1").spells[196718].cd, 300, "neither estimate is touched")
eq(TR.Get("party2").spells[196718].cd, 300, "neither estimate is touched, the other one")

-- ---------------------------------------------------------------- the self-test
W.units.player = { friendly = true, class = "DEMONHUNTER", guid = "Player-0-ME" }
W.units.party1 = { friendly = true, class = "DRUID", guid = "Player-3-DRUID" }
W.units.party2 = { friendly = true, class = "PRIEST", guid = "Player-3-PRIEST" }
fire("GROUP_ROSTER_UPDATE")
W.matchState = 3; fire("PVP_MATCH_STATE_CHANGED")
W.now = 2000
fire("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-2", 198589)
shown("player", 198589, 2000.02)
check(not TR.failed, "the player's own buff showed after the cast: fine")
hidden("player", 198589, 2010)
W.now = 2100; fire("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-3", 198589)
W.now = 2101; TR.SelfTestCheck(2101)
check(not TR.failed, "one miss is not yet a failure")
W.now = 2200; fire("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-4", 198589)
W.now = 2201; TR.SelfTestCheck(2201)
check(TR.failed, "two misses in a row: detection is broken")
check(T.said(CK.L["Arena: detection failed, the rows are dimmed."]), "and the player is told")
AR.UI.Refresh(2201)
check(AR.UI.Rows().party1.warn:IsShown(), "the rows carry the warning")
W.now = 2300; fire("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-5", 198589)
shown("player", 198589, 2300.02)
check(not TR.failed, "a buff that shows again clears it")

-- ---------------------------------------------------------------- the rows
AR.UI.Refresh(2300.02)
local row = AR.UI.Rows().party1
eq(#TR.Get("party1").order, #AR.SpellsFor("DRUID", true), "one icon per druid ability")
check(row.icons[1] and row.icons[1]:IsShown(), "icons are shown")
AR.db.externals = false
AR.Apply()
eq(#TR.Get("party1").order, #AR.SpellsFor("DRUID", false), "externals off: only the self buffs")
AR.db.externals = true
AR.Apply()
AR.db.showSelf = false
AR.Apply()
check(TR.Get("player") == nil, "the player's row switched off")
AR.db.showSelf = true
AR.Apply()
check(TR.Get("player") ~= nil, "and back")

-- hung on the party frame that shows the unit
eq(row.__point[2], UIParent, "no party frame around: the row sits at its own position")
local member = CreateFrame("Button", "CompactPartyFrameMember1")
member:SetAttribute("unit", "party1")
AR.Apply()
check(row.__point[1] == "TOPLEFT" and row.__point[2] == member and row.__point[3] == "TOPRIGHT" and row.__point[4] == 4,
	"party1's row hangs on the right of its frame, 4 px away")
AR.db.side = "LEFT"; AR.Apply()
check(row.__point[1] == "TOPRIGHT" and row.__point[3] == "TOPLEFT" and row.__point[4] == -4, "on the left when asked")
check(row.icons[2].__point[1] == "TOPRIGHT" and row.icons[2].__point[4] == -(AR.db.iconSize + AR.db.spacing), "and the icons grow leftwards")
AR.db.side = "BOTTOM"; AR.db.offsetAlong = 6; AR.Apply()
check(row.__point[1] == "TOPLEFT" and row.__point[3] == "BOTTOMLEFT" and row.__point[4] == 6 and row.__point[5] == -4, "below: the offset goes down, the shift goes along")
AR.db.side = "RIGHT"; AR.db.offsetAlong = 0
AR.db.maxPerRow = 2; AR.Apply()
check(row.icons[3].__point[4] == 0 and row.icons[3].__point[5] == -(AR.db.iconSize + AR.db.spacing), "more icons than fit a row: the next line")
AR.db.maxPerRow = 8
member:Hide(); AR.Apply()
eq(row.__point[2], UIParent, "a frame that is hidden: back to the loose position")
member:Show()
member:SetAttribute("unit", "raid2")
W.units.raid2 = W.units.party1
AR.Apply()
eq(row.__point[2], member, "a frame naming the same player by another token counts, by GUID")
W.units.raid2 = nil
member:SetAttribute("unit", "party1")
AR.db.attach = false; AR.Apply()
eq(row.__point[2], UIParent, "attach off: loose")
AR.db.attach = true; AR.Apply()

-- unlocked: sample rows, a loose one draggable with a background
AR.SetLocked(false)
check(not AR.IsLocked() and AR.UI.Rows().player.bg:IsShown(), "unlocked: a loose row shows its background")
check(not AR.UI.Rows().party1.bg:IsShown(), "an attached one does not")
AR.SetLocked(true)

-- ---------------------------------------------------------------- settings page
SlashCmdList.COMBATKIT("")
local main = CK.Options.GetFrame()
check(main and main:IsShown(), "the settings window opens")
main.tabs.Arena:Click()
local page = main.bodies.Arena
check(page and page.showSelf and page.iconSize, "the Arena page is built")
page.showSelf:Click()
eq(AR.db.showSelf, false, "the checkbox writes the setting")
page.showSelf:Click()
page.unlock:Click()
check(not AR.IsLocked(), "unlocked from the page")
main:Hide()
check(AR.IsLocked(), "closing the window locks the rows again")

-- ---------------------------------------------------------------- leaving the arena
W.inInstance, W.instanceType = false, "none"
fire("PLAYER_ENTERING_WORLD")
check(not fake.started, "leaving stops the backend")
check(TR.Get("party1") == nil, "and clears the teammates")
AR.UI.Refresh()
check(not AR.UI.Rows().party1:IsShown(), "no row outside")

-- the test switch: sample rows out here, with one icon of each look
SlashCmdList.COMBATKIT("")
main.tabs.Arena:Click()
page.test:Click()
check(AR.IsTesting() and AR.UI.Rows().party1:IsShown() and AR.UI.Rows().player:IsShown(), "test: the rows show in the world")
check(AR.IsLocked() and not AR.UI.Rows().player.bg:IsShown(), "without the drag background: still locked")
local sample = AR.UI.Rows().player
check(sample.icons[1].border[1]:IsShown() and sample.icons[3].mark:IsShown(), "one active, one unknown among the samples")
main:Hide()
check(not AR.IsTesting(), "closing the window ends the test")
AR.UI.Refresh()
check(not AR.UI.Rows().player:IsShown(), "and the rows are gone again")

-- ---------------------------------------------------------------- off
CK.SetModuleEnabled("Arena", false)
check(not AR.IsRunning(), "switched off: stopped")

return T.report("arena " .. LOCALE)
