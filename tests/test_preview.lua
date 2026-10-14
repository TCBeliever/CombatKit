-- The Party CD sample rows out in the world: a teammate without a frame gets
-- a stand-in box where their frame would be, from DandersFrames' settings
-- next to the player's frame, or from the player's frame alone; a real frame
-- wins; nothing to stand next to leaves the loose rows; a round in progress
-- switches the samples off.

local T = dofile(HERE .. "/stubs.lua")
local check, eq, W = T.check, T.eq, T.W
T.captureChat()

CombatKitPartyCDDB = {}
local CK = T.boot()
CK.SetModuleEnabled("PartyCD", true)
local AR = CK.modules.PartyCD
local UI = AR.UI
W.units.player = { friendly = true }

-- DandersFrames draws the player's frame and says how it lays the party out
local df = T.Mock("Frame", "DandersFramesPlayer")
df:SetAttribute("unit", "player")
df:Show()
DandersFrames_GetAllFrames = function() return { df } end
local layout = { frameWidth = 130, frameHeight = 100, frameSpacing = 2, frameScale = 1, growDirection = "HORIZONTAL", growthAnchor = "CENTER" }
DandersFrames_GetPartyConfig = function() return layout end

AR.SetTest(true)
local rows, stand = UI.Rows(), UI.StandIns()
check(rows.player.anchor == df and rows.player:IsShown(), "the player's row hangs on the real frame")
check(stand.party1 and stand.party1:IsShown() and rows.party1.anchor == stand.party1, "party1: a stand-in, and the row hangs on it")
check(stand.party2 and stand.party2:IsShown() and rows.party2.anchor == stand.party2, "party2 as well")
local p = stand.party1.__point
check(p[2] == df and p[1] == "TOPLEFT" and p[3] == "TOPLEFT", "a stand-in is placed from the player's frame's corner")
eq(p[4], 132, "one frame and a gap to the right")
eq(p[5], 0, "on the same line")
p = stand.party2.__point
eq(p[4], -132, "grown from the centre: the second on the other side")
check(not rows.party1.bg:IsShown(), "an anchored row has no drag background")
check(stand.party1.label.__text:find("Test", 1, true) or stand.party1.label.__text:find("測試", 1, true), "the stand-in says it is a sample")

-- a real teammate: their frame wins, the stand-in goes
W.units.party1 = { friendly = true, class = "DRUID", guid = "Player-9-DRUID" }
local dfp1 = T.Mock("Frame", "DandersFramesParty1")
dfp1:SetAttribute("unit", "party1")
dfp1:Show()
DandersFrames_GetAllFrames = function() return { df, dfp1 } end
UI.Refresh()
check(rows.party1.anchor == dfp1 and not stand.party1:IsShown(), "a real frame: the row hangs on it, the stand-in is hidden")
check(stand.party2:IsShown(), "party2 still has a stand-in")

-- the party drawn downwards: stand-ins stack below
layout.growDirection = "VERTICAL"
UI.Refresh()
p = stand.party2.__point
eq(p[4], 0, "vertical: no sideways step")
eq(p[5], 102, "grown from the centre: one frame and a gap up")
layout.growthAnchor = "START"
UI.Refresh()
eq(stand.party2.__point[5], -204, "grown from the start: two frames and two gaps down")
layout.growDirection = "HORIZONTAL"
UI.Refresh()
eq(stand.party2.__point[4], 264, "and sideways: two frames over")
layout.growthAnchor = "CENTER"

-- the frames scaled: the stand-ins with them
layout.frameScale = 0.5
UI.Refresh()
eq(stand.party2.__point[4], -66, "half scale: half the step")
layout.frameScale = 1

-- without DandersFrames: the player's frame alone, stand-ins the same size below it
DandersFrames_GetAllFrames, DandersFrames_GetPartyConfig = nil, nil
W.units.party1 = nil
PlayerFrame = T.Mock("Frame", "PlayerFrame")
PlayerFrame:SetAttribute("unit", "player")
PlayerFrame:Show()
UI.Refresh()
p = stand.party1.__point
check(stand.party1:IsShown() and p[2] == PlayerFrame, "the game's player frame: a stand-in next to it")
eq(p[4], 0, "below it")
eq(p[5], -42, "one frame's height and a small gap down")
eq(stand.party2.__point[5], -84, "the second another frame down")

-- nothing of the player's own on screen: nothing to stand next to, the loose rows stay
PlayerFrame:Hide()
UI.Refresh()
check(not stand.party1:IsShown() and rows.party1:IsShown() and rows.party1.anchor == nil, "no frame of the player's: the loose row, no stand-in")

-- not attached to frames: no stand-ins either
PlayerFrame:Show()
AR.db.attach = false
UI.Refresh()
check(not stand.party1:IsShown() and rows.party1.anchor == nil, "not attached: loose rows, no stand-in")
AR.db.attach = true
UI.Refresh()
check(stand.party1:IsShown(), "attached again: the stand-in is back")

-- the samples switched off: the stand-ins go
AR.SetTest(false)
check(not stand.party1:IsShown() and not stand.party2:IsShown(), "test off: no stand-ins")
check(not rows.party1:IsShown(), "and no rows out in the world")

-- unlocked for dragging (not testing): loose rows as before, no stand-ins
AR.SetLocked(false)
check(rows.party1:IsShown() and not stand.party1:IsShown(), "unlocked: the rows show, without stand-ins")
AR.SetLocked(true)

-- a round in progress: the samples switch themselves off
AR.SetTest(true)
check(AR.IsTesting(), "test on in the world")
W.inInstance, W.instanceType, W.matchState = true, "arena", 3
UI.Refresh()
check(not AR.IsTesting() and not stand.party1:IsShown(), "a round in progress: the samples are off and the stand-ins gone")
W.inInstance, W.instanceType, W.matchState = false, nil, 0
PlayerFrame = nil

return T.report("preview " .. LOCALE)
