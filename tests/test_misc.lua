-- The Misc module: two small features, each switched on its own, sharing one
-- load-on-demand addon that is only loaded while at least one of them is on.

local T = dofile(HERE .. "/stubs.lua")
local check, eq, W, fire, flush = T.check, T.eq, T.W, T.fire, T.flush
T.captureChat()

local function logged(entry) for _, l in ipairs(W.log) do if l == entry then return true end end return false end

local CK = T.boot()
check(T.loaded.CombatKit_Misc == nil, "both features off: the addon is never loaded")
eq(CK.IsModuleEnabled("Misc"), false, "and the module counts as off")

-- ---------------------------------------------------------------- combat alert
CK.SetFeatureEnabled("Misc", "CombatAlert", true)
check(T.loaded.CombatKit_Misc ~= nil, "the first feature switched on loads the addon")
local MI = CK.modules.Misc
eq(MI.GetFeatureState("CombatAlert"), "on", "combat alert: on")
eq(MI.GetFeatureState("RightClick"), "off", "right click: still off, although its code is loaded")
eq(W.drivers.mov, nil, "so nothing of it is set up")

local alert = T.frames.CombatKitCombatAlert
W.combat = true; fire("PLAYER_REGEN_DISABLED")
eq(alert.text:GetText(), "<Entering Combat>", "entering combat: the text, English in every language")
W.combat = false; fire("PLAYER_REGEN_ENABLED")
eq(alert.text:GetText(), "<Leaving Combat>", "leaving combat: the other text")

MI.AlertSettings().enterText = "PULL"
eq(MI.AlertText("enter"), "PULL", "the player's own text wins")
MI.AlertSettings().enterText = nil
eq(MI.AlertText("enter"), "<Entering Combat>", "without one, the built-in text")

-- ---------------------------------------------------------------- right click: secure, so never in combat
W.log = {}
W.combat = true
CK.SetFeatureEnabled("Misc", "RightClick", true)
eq(MI.GetFeatureState("RightClick"), "waiting", "switched on in combat: it waits")
check(not logged("driver:on"), "nothing protected is touched in combat")
check(T.said(CK.L["FEAT_RightClick"]), "and the chat says it will start later")
W.combat = false; fire("PLAYER_REGEN_ENABLED")
eq(MI.GetFeatureState("RightClick"), "on", "started when combat ended")
eq(W.drivers.mov, "[combat,@mouseover,exists]1;0", "the state driver watches combat + mouseover")
local state = T.frames.CombatKitRightClickState
check(state.__attributes["_onstate-mov"]:find("CombatKitMouselookButton", 1, true), "and binds right click to the mouselook button")
local button = T.frames.CombatKitMouselookButton
button:GetScript("OnClick")(button, "RightButton", true)
button:GetScript("OnClick")(button, "RightButton", false)
check(logged("mouselook:start") and logged("mouselook:stop"), "which turns the camera while held")

W.log = {}
W.combat = true
CK.SetFeatureEnabled("Misc", "RightClick", false)
eq(MI.GetFeatureState("RightClick"), "waiting", "switched off in combat: it waits too")
check(not logged("driver:off"), "still nothing protected is touched")
W.combat = false; fire("PLAYER_REGEN_ENABLED")
check(logged("driver:off") and logged("bindings:cleared"), "stopped and unbound when combat ended")
eq(MI.GetFeatureState("RightClick"), "off", "off")

-- ---------------------------------------------------------------- settings page
SlashCmdList.COMBATKIT("")
local main = CK.Options.GetFrame()
local function treeRow(section, node)
	for _, row in ipairs(main.treeRows) do
		if row:IsShown() and row.section == section and row.node == node then return row end
	end
end
main.tabs.Misc:Click()
check(treeRow("Misc", "CombatAlert") ~= nil and treeRow("Misc", "misc") ~= nil and treeRow("Misc", "RightClick") == nil,
	"a page for the feature with settings, and 'Misc' for those that are only a switch")
treeRow("Misc", "CombatAlert"):Click()
local page = main.bodies.Misc
check(page.enable:GetChecked() and page.alert:IsShown(), "the alert is on: its switch is ticked, its settings show")
treeRow("Misc", "misc"):Click()
local rc = page.simple.RightClick
check(page.misc:IsShown() and not page.enable:IsShown() and not page.alert:IsShown(), "the Misc page: only its list of switches")
check(not rc.check:GetChecked(), "right click is off")
eq(rc.check.label:GetText(), CK.L["FEAT_RightClick"], "named for what it does")
eq(rc.desc:GetText(), CK.L["FEATDESC_RightClick"], "with the details underneath")
rc.check:Click()
eq(MI.GetFeatureState("RightClick"), "on", "ticked: switched on from the Misc page")
check(rc.check:GetChecked(), "and the box stays ticked")
eq(W.drivers.mov, "[combat,@mouseover,exists]1;0", "every unit under the cursor is covered, corpses included")
rc.check:Click()
eq(MI.GetFeatureState("RightClick"), "off", "and off again")
treeRow("Misc", "CombatAlert"):Click()
check(page.enable:IsShown() and not page.misc:IsShown(), "back on a feature's own page")
eq(page.enter:GetText(), "<Entering Combat>", "the text box shows what will be said")
page.enter:SetText("GO"); page.enter:GetScript("OnEditFocusLost")(page.enter)
eq(MI.AlertSettings().enterText, "GO", "a changed text is saved")
page.enter:SetText(""); page.enter:GetScript("OnEditFocusLost")(page.enter)
eq(MI.AlertSettings().enterText, nil, "an emptied one falls back to the built-in text")
eq(page.enter:GetText(), "<Entering Combat>", "which the box shows again")

-- a button plays it as it will appear: entering first, leaving on the next click
page.play:Click()
eq(alert.text:GetText(), "<Entering Combat>", "play once: the entering text")
page.play:Click()
eq(alert.text:GetText(), "<Leaving Combat>", "again: the leaving text")

page.test:Click()
check(MI.IsAlertTesting(), "test mode: the text stays on screen to be dragged")
page.play:Click()
check(not MI.IsAlertTesting() and not page.test:GetChecked(), "playing it ends the drag mode first")
eq(alert.text:GetText(), "<Entering Combat>", "and plays")

-- it can float up while it shows: off unless ticked
local fades = alert.fade.__plays
check(not page.rise:GetChecked() and alert.rise.__plays == nil, "motion: off by default, so far the text has only faded")
page.rise:Click()
eq(MI.AlertSettings().rise, true, "ticked: saved")
page.play:Click()
check(alert.fade.__plays == fades + 1 and alert.rise.__plays == 1, "and the text floats up as it fades")
page.rise:Click()
check(not MI.AlertSettings().rise and not page.rise:GetChecked(), "and off again")
page.test:Click()
eq(alert.text:GetAlpha(), 1, "fully visible")
main:Hide()
check(not MI.IsAlertTesting(), "closing the window ends it")

-- the features are switched on their own pages only; the last one off takes the module with it
SlashCmdList.COMBATKIT("")
main.tabs.Misc:Click(); treeRow("Misc", "CombatAlert"):Click()
page.enable:Click()
eq(CK.IsModuleEnabled("Misc"), false, "the last feature off: the module is off")
check(main.tabs.Misc.dimmed, "its tab is dimmed")
check(not page.enable:GetChecked() and not page.alert:IsShown(), "the feature's page is down to its switch")
check(page.state:GetText():find(CK.L["STATE_stale"], 1, true), "which says that its code leaves with a reload")
main.tabs.kit:Click(); treeRow("kit", "modules"):Click()
local mods = main.bodies.kit.pages.modules
check(mods.reload:IsShown(), "the modules page offers that reload, although it does not list the features")
main.tabs.Misc:Click(); treeRow("Misc", "CombatAlert"):Click()
page.enable:Click()
check(CK.IsFeatureEnabled("Misc", "CombatAlert") and page.alert:IsShown() and not main.tabs.Misc.dimmed, "which brings it all back")
page.enable:Click()
check(not alert:IsShown(), "nothing left on screen")
eq(CK.GetModuleState("Misc"), "stale", "its code goes with the next reload")

T.releaseChat()
return T.report("misc  [" .. (LOCALE or "enUS") .. "]")
