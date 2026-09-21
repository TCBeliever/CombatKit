-- The Range module: the range ladder, the combat fallback, its saved settings,
-- its page.

local T = dofile(HERE .. "/stubs.lua")
local check, eq, W, fire, flush = T.check, T.eq, T.W, T.fire, T.flush
T.captureChat()

-- saved earlier: a few settings, the rest comes from the defaults
CombatKitRangeDB = { fontSize = 22, units = { target = { enabled = true, point = "CENTER", relPoint = "CENTER", x = 40, y = -90 } } }

local CK = T.boot()
check(T.loaded.CombatKit_Range == nil, "off by default: never loaded")
CK.SetModuleEnabled("Range", true)
local RG = CK.modules.Range
check(RG and RG.enabled and RG.IsRunning(), "switched on: loaded and running")

-- ---------------------------------------------------------------- saved settings
eq(RG.db.fontSize, 22, "what was saved is kept")
eq(RG.db.units.target.x, 40, "positions included")
eq(RG.db.units.focus.x, 385, "what was never saved comes from the defaults")

-- ---------------------------------------------------------------- the ladder
W.units.target = { friendly = false, yards = 27 }
eq(RG.GetUnitRange("target"), 30, "hostile at 27 yards: farther than the 25 item, within the 30 item")
W.units.target.yards = 4
eq(RG.GetUnitRange("target"), 5, "melee range")
W.units.target.yards = 95
eq(RG.GetUnitRange("target"), 100, "hostile units reach up to 100")
W.units.focus = { friendly = true, yards = 38 }
eq(RG.GetUnitRange("focus"), 40, "friendly ladder")
eq(RG.GetUnitRange("mouseover"), 0, "no unit, no number")

-- in combat the item API is blocked for friendly units: the spell book answers
W.spells = { { 1001, 30 }, { 1002, 15 } }
fire("SPELLS_CHANGED")
W.combat = true
W.units.focus.yards = 12
eq(RG.GetUnitRange("focus"), 15, "friendly in combat: the shortest own spell that reaches")
W.units.focus.yards = 35
eq(RG.GetUnitRange("focus"), 0, "beyond every short spell: nothing to show")
W.units.target.yards = 27
eq(RG.GetUnitRange("target"), 30, "hostile units keep using the ladder in combat")
W.combat = false

local r, g, b = RG.GetRangeColor(45); check(r == 1 and g == 0, "beyond 40: red")
r, g, b = RG.GetRangeColor(4); check(r == 0.9 and g == 0.9, "melee: grey")

-- ---------------------------------------------------------------- display
local target = T.frames.CombatKitRange_target
check(target and target:IsShown(), "the target box exists")
eq(target.__font, nil, "mock frames carry no font; the text does")
eq(target.text.__font[2], 22, "font size from the settings")
RG.UpdateUnit("target")
eq(target.text:GetText(), 30, "the number is shown")
RG.db.hideMelee = true; W.units.target.yards = 3; RG.UpdateUnit("target")
eq(target.text:GetText(), "", "hidden at 5 yards or closer when asked")
W.units.target.yards = 27

-- ---------------------------------------------------------------- settings page
SlashCmdList.COMBATKIT("")
local main = CK.Options.GetFrame()
local function treeRow(section, node)
	for _, row in ipairs(main.treeRows) do
		if row:IsShown() and row.section == section and row.node == node then return row end
	end
end
main.tabs.Range:Click()
local page = main.bodies.Range
check(page.units.target:GetChecked(), "target: on")
page.units.target:Click()
eq(RG.db.units.target.enabled, false, "unticked")
check(not target:IsShown(), "its box is gone")
page.units.target:Click()

page.unlock:Click()
check(not RG.IsLocked(), "unlocked")
eq(target.text:GetText(), "35", "every box shows a sample to drag")
main:Hide()
check(RG.IsLocked(), "closing the window locks them again")
eq(target.text:GetText(), "", "and the sample is gone")

-- ---------------------------------------------------------------- off
CK.SetModuleEnabled("Range", false)
check(not target:IsShown() and not RG.IsRunning(), "off: nothing on screen, nothing running")

T.releaseChat()
return T.report("range [" .. (LOCALE or "enUS") .. "]")
