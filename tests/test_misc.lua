-- The Misc module: two small features, each switched on its own, sharing one
-- load-on-demand addon that is only loaded while at least one of them is on.

local T = dofile(HERE .. "/stubs.lua")
local check, eq, W, fire, flush = T.check, T.eq, T.W, T.fire, T.flush
T.captureChat()

local function logged(entry) for _, l in ipairs(W.log) do if l == entry then return true end end return false end

local CK = T.boot()
check(T.loaded.CombatKit_Misc == nil, "both features off: the addon is never loaded")
eq(CK.IsModuleEnabled("Misc"), false, "and the module counts as off")
CK.db.modules.Misc.SapIcon = true   -- a rogue on this account switched it on (the flags are the account's)
check(not CK.IsFeatureEnabled("Misc", "SapIcon") and not CK.IsModuleEnabled("Misc"),
	"on a demon hunter the rogue's sap icon does not count: the addon stays unloaded")
CK.db.modules.Misc.SapIcon = false

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

-- ---------------------------------------------------------------- sap icon: a rogue's, arenas and battlegrounds only
local function where(kind)
	W.inInstance, W.instanceType = kind ~= "none", kind
	fire("PLAYER_ENTERING_WORLD")
end
local function shown(plate)
	local icon = MI.SapIconOf(plate)
	return icon ~= nil and icon:IsShown()
end

W.units.nameplate1 = { friendly = false, combat = false }   -- an enemy player, out of combat
local plate1 = T.plate("nameplate1")

where("arena")
check(CK.IsFeatureAvailable("Misc", "CombatAlert") and not CK.IsFeatureAvailable("Misc", "SapIcon"), "the sap icon is a rogue's only")
CK.SetFeatureEnabled("Misc", "SapIcon", true)
check(not CK.db.modules.Misc.SapIcon and MI.GetFeatureState("SapIcon") == "off", "a demon hunter cannot switch it on")
fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
eq(MI.SapIconOf(plate1), nil, "nothing, not even an icon made")

W.units.player = { class = "ROGUE" }
where("none")
CK.SetFeatureEnabled("Misc", "SapIcon", true)
fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
eq(MI.SapIconOf(plate1), nil, "a rogue in the open world: nothing")

where("arena")
check(shown(plate1), "entering an arena: the nameplates already up are looked at, an enemy out of combat has the icon")
local icon1 = MI.SapIconOf(plate1)
eq(icon1.texture:GetTexture(), "icon6770", "Sap's own icon")
W.units.nameplate1.combat = true; fire("UNIT_FLAGS", "nameplate1")
check(not shown(plate1), "the enemy enters combat: gone")
W.units.nameplate1.combat = false; fire("UNIT_FLAGS", "nameplate1")
check(shown(plate1), "and leaves it: back")

W.units.nameplate2 = { friendly = false, npc = true }
W.units.nameplate3 = { friendly = true }
W.units.nameplate4 = { friendly = false, dead = true }
W.units.nameplate5 = { friendly = false, combat = T.SECRET }
local plate2, plate3, plate4, plate5 = T.plate("nameplate2"), T.plate("nameplate3"), T.plate("nameplate4"), T.plate("nameplate5")
for i = 2, 5 do fire("NAME_PLATE_UNIT_ADDED", "nameplate" .. i) end
check(not shown(plate2), "an NPC (a pet, a guard): nothing")
check(not shown(plate3), "a friendly player: nothing")
check(not shown(plate4), "a dead enemy, although out of combat: nothing")
check(not shown(plate5), "an enemy whose combat state the client keeps secret: nothing rather than a guess")

fire("NAME_PLATE_UNIT_REMOVED", "nameplate1")
check(not shown(plate1), "its nameplate goes: the icon with it")
W.units.nameplate6 = { friendly = false, combat = false }
T.plate("nameplate6", plate1)
fire("NAME_PLATE_UNIT_ADDED", "nameplate6")
check(shown(plate1) and MI.SapIconOf(plate1) == icon1, "the frame reused for another enemy: the same icon, shown again")
W.units.nameplate1.combat = true; fire("UNIT_FLAGS", "nameplate1")
check(shown(plate1), "the old token entering combat no longer touches it")

where("none")
check(not shown(plate1), "back in the open world: every icon hidden")
W.units.nameplate6.combat = true; fire("UNIT_FLAGS", "nameplate6")
W.units.nameplate6.combat = false; fire("UNIT_FLAGS", "nameplate6")
check(not shown(plate1), "and nothing listens there")

where("pvp")
check(shown(plate1), "a battleground counts too")
W.units.nameplate7 = { friendly = false, npc = true, npcAsPlayer = true }
local plate7 = T.plate("nameplate7")
fire("NAME_PLATE_UNIT_ADDED", "nameplate7")
check(shown(plate7), "an AI opponent of a training battleground counts as a player")

-- size and distance: the player's, on every icon at once
local s = MI.SapSettings()
check(s.size == 24 and s.x == 0 and s.y == 2, "24 pixels, centred, 2 above the nameplate by default")
eq(icon1.__size[1], 24, "made at the saved size")
check(icon1.__point[1] == "BOTTOM" and icon1.__point[2] == plate1 and icon1.__point[3] == "TOP"
	and icon1.__point[4] == 0 and icon1.__point[5] == 2, "its bottom that far above the middle of the nameplate's top")
check(icon1.__point[2] ~= nil, "on the nameplate's own frame, whichever addon draws it")
s.size, s.x, s.y = 40, -30, -10
MI.ApplySapIcon()
check(icon1.__size[1] == 40 and MI.SapIconOf(plate7).__size[1] == 40, "a new size: every icon made so far takes it")
eq(icon1.__point[4], -30, "offset X moves it sideways (left below zero)")
eq(icon1.__point[5], -10, "offset Y below zero pulls it down onto the health bar")
s.size, s.x, s.y = 24, 0, 2
MI.ApplySapIcon()

-- a preview: on every nameplate, anywhere, to set them
where("none")
MI.SetSapPreview(true)
check(shown(plate1) and shown(plate2) and shown(plate3) and shown(plate4), "preview in the open world: every nameplate on screen, NPCs and friends too")
W.units.nameplate8 = { friendly = true }
local plate8 = T.plate("nameplate8")
fire("NAME_PLATE_UNIT_ADDED", "nameplate8")
check(shown(plate8), "and one that comes up meanwhile")
MI.SetSapPreview(false)
check(not shown(plate1) and not shown(plate2) and not shown(plate8), "preview off in the open world: all gone")
where("arena")
MI.SetSapPreview(true)
MI.SetSapPreview(false)
check(shown(plate1) and not shown(plate2) and not shown(plate3), "preview off in an arena: back to the enemies you can Sap")
MI.SetSapPreview(true)
CK.SetFeatureEnabled("Misc", "SapIcon", false)
check(not MI.IsSapPreview(), "switching the feature off ends a preview")
eq(MI.GetFeatureState("SapIcon"), "off", "switched off")
check(not shown(plate1), "nothing left on the nameplates")
where("none")
W.units = {}; W.plates = {}

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

-- the sap icon has settings, so a page of its own; they wait for the switch, and for a rogue
check(treeRow("Misc", "SapIcon") == nil and page.simple.SapIcon == nil, "a demon hunter: no sap icon anywhere in the settings")
W.units.player = { class = "ROGUE" }
main.tabs.Misc:Click()
check(treeRow("Misc", "SapIcon") ~= nil and page.simple.SapIcon == nil, "a rogue: the sap icon has a page of its own")
treeRow("Misc", "SapIcon"):Click()
check(not page.enable:GetChecked() and not page.sap:IsShown(), "off by default: the page is down to its switch")
page.enable:Click()
check(page.sap:IsShown() and not page.alert:IsShown(), "on for a rogue: size, offsets and preview")
eq(page.sapSize:GetText(), "24", "the size it has")
check(page.sapX:GetText() == "0" and page.sapY:GetText() == "2", "and its offsets")
local function move(slider, v) slider.slider:GetScript("OnValueChanged")(slider.slider, v) end
move(page.sapSize, 36)
eq(MI.SapSettings().size, 36, "a new size is saved")
move(page.sapX, 25)
eq(MI.SapSettings().x, 25, "an offset X is saved")
move(page.sapY, -8)
eq(MI.SapSettings().y, -8, "and an offset Y, below zero too")
page.sapPreview:Click()
check(MI.IsSapPreview() and page.sapPreview:GetChecked(), "preview: on")
main:Hide()
check(not MI.IsSapPreview(), "closing the window ends it")
SlashCmdList.COMBATKIT("")
main.tabs.Misc:Click(); treeRow("Misc", "SapIcon"):Click()
check(not page.sapPreview:GetChecked() and page.sapSize:GetText() == "36", "open again: preview off, the size kept")
page.enable:Click()
W.units.player = nil
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
