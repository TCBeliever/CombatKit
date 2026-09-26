-- UI smoke test: the kit loaded as the game does, then the settings window and
-- the HUD driven through their handlers against mock frames. Layout is not
-- verified; nil calls, wrong names and broken handlers are.

local T = dofile(HERE .. "/stubs.lua")
local check, eq, W, fire, flush = T.check, T.eq, T.W, T.fire, T.flush
T.captureChat()

local HAVOC, VENG = 577, 581
local function wear(id) for k, s in pairs(W.sets) do s[2] = (k == id) end end

W.specIndex = 1; W.activeConfig[HAVOC] = 101; wear(1)
CombatKitLoadoutDB = { settings = { auto = true } }   -- off by default; these tests are about the switching
local CK = T.boot()
fire("PLAYER_ENTERING_WORLD")
local LO = CK.modules.Loadout
local C, L, Skin = LO.char, CK.L, CK.Skin

local function pick(dropdown, want)   -- open a dropdown and click the item whose value is `want`
	dropdown:Click()
	local list = T.frames.CombatKitOptionList
	check(list and list:IsShown(), "option list opens")
	for _, b in ipairs(list.buttons) do
		if b:IsShown() and b.item.value == want then b:Click(); return true end
	end
	return false
end
local function offered(dropdown, want)
	dropdown:Click()
	local list = T.frames.CombatKitOptionList
	local found = false
	for _, b in ipairs(list.buttons) do
		if b:IsShown() and b.item.value == want then found = true end
	end
	list:Hide()
	return found
end

eq(#LO.GetSpecs(), 3, "an empty record past the last spec is not a spec")

-- ---------------------------------------------------------------- HUD: the Loadout section
local hud = CK.HUD.GetFrame()
check(hud and hud:IsShown(), "the HUD is there after login")
local rows = hud.sections.loadout.rows
eq(rows[1].value:GetText(), "Havoc", "row 1: the spec")
check(rows[1].right:GetText():find(L["Not set up"], 1, true), "nothing set up yet")

-- ---------------------------------------------------------------- window
SlashCmdList.COMBATKIT("")
local O = CK.Options
local main = O.GetFrame()
check(main and main:IsShown(), "/ck opens the window")
eq(main.__scale, 1.5, "the window is 1.5x by default")
local d = main.detail

local function shownRows()
	local out = {}
	for _, r in ipairs(main.treeRows) do if r:IsShown() then out[#out + 1] = r end end
	return out
end
local function treeRow(section, node)
	for _, r in ipairs(shownRows()) do
		if r.section == section and r.node == node then return r end
	end
end

local function tab(section) return main.tabs[section] end
-- open a tab and, in its tree, a page
local function go(section, node)
	tab(section):Click()
	if node then treeRow(section, node):Click() end
end

-- a tab per module and the kit's own at the right; the tree lists the pages of the open tab
check(tab("Loadout") and tab("Stats") and tab("Range") and tab("Misc") and tab("kit"), "a tab per module, and one for the kit")
eq(tab("Loadout").text:GetText(), L["MOD_Loadout"], "named after the module")
check(tab("Loadout").sel:IsShown() and not tab("kit").sel:IsShown(), "opens on the first module that is on")
check(not tab("Loadout").dimmed and tab("Stats").dimmed and tab("Misc").dimmed, "what is off has a dimmed tab")
eq(#shownRows(), 4, "a new user sees PvE and PvP, and the module's two pages")
eq(d.title:GetText(), L["GROUP_pve"], "opens on PvE while in the open world")
check(d.desc:GetText():find(L["SCN_world"], 1, true) and d.desc:GetText():find(L["SCN_raid"], 1, true), "a group is described by the scenarios it covers")

local p = main.bodies.Loadout.pages.loadout
local function specButton(specID)
	for _, b in ipairs(p.specButtons) do if b:IsShown() and b.specID == specID then return b end end
end
check(p.split:IsShown() and not p.split:GetChecked(), "the group page carries 'split into scenarios', off")
check(not p.follow:IsShown() and not p.auto:IsShown(), "a group page has neither scenario switch")
check(specButton(HAVOC) and specButton(VENG) and specButton(1480) and p.specButtons[4] == nil, "one big icon per spec, no empty fourth")

check(pick(p.talents, 101), "Havoc PvE: talents")
check(pick(p.gear, 1), "Havoc PvE: gear")
local cell = C.groups.pve.specs[HAVOC]
check(cell and cell.configID == 101 and cell.configName == "M+ AoE" and cell.setID == 1 and cell.setName == "PvE", "cell saved with names")
check(specButton(HAVOC).dot:IsShown() and not specButton(VENG).dot:IsShown(), "configured specs are marked")

specButton(VENG):Click()
eq(p.talents.text:GetText(), L["Not set"], "fields show the picked spec")
check(not offered(p.talents, 101), "its own loadouts only")
check(pick(p.talents, 201), "Vengeance PvE: talents")
eq(C.groups.pve.specs[VENG].configID, 201, "saved under the picked spec")
check(pick(p.talents, nil), "and cleared again")
eq(C.groups.pve.specs[VENG], nil, "an empty cell is removed")
specButton(HAVOC):Click()

treeRow("Loadout", "group:pvp"):Click()
eq(d.title:GetText(), L["GROUP_pvp"], "PvP selected")
check(pick(p.gear, 2), "Havoc PvP: gear")
check(p.warmode:IsShown(), "war mode option lives on the PvP page")
p.warmode:Click(); eq(C.warmodePvP, true, "war mode option on"); p.warmode:Click()
eq(#W.log, 0, "editing settings never switches anything")

-- "Switch now": what the page shows, applied on request
check(not p.switch.disabled, "Havoc PvP shows gear 2 while set 1 is worn: the button is live")
p.switch:Click(); flush()
eq(W.log[1], "equip:2", "it equips the set shown")
fire("EQUIPMENT_SWAP_FINISHED"); flush()
check(not p.switch.disabled, "already there: the button stays live, so the setup can be applied again")
W.log = {}
p.switch:Click(); flush()
eq(W.log[1], "equip:2", "and it asks once more, whatever is on")
fire("EQUIPMENT_SWAP_FINISHED"); flush()
check(not LO.IsApplying() and #W.log == 1, "once: then it is done")
specButton(1480):Click()
check(not p.switch.disabled, "another spec with nothing set up: still a spec to switch to")
specButton(HAVOC):Click()
local keep = C.groups.pvp.specs[HAVOC]
C.groups.pvp.specs[HAVOC] = nil; O.Refresh()
check(p.switch.disabled, "the current spec with nothing set up: nothing to switch to")
C.groups.pvp.specs[HAVOC] = keep; O.Refresh()
specButton(VENG):Click()
check(pick(p.talents, 201), "Vengeance PvP: talents")
check(not p.switch.disabled, "another spec is picked: live")
W.activeConfig[VENG] = nil   -- that spec last used some other loadout
W.log = {}
p.switch:Click(); flush()
eq(W.log[1], "spec:2", "it asks for the spec first")
W.specIndex = 2; fire("PLAYER_SPECIALIZATION_CHANGED"); flush()
check(W.log[2] == "talents:201", "then the talents of that spec")
W.activeConfig[VENG] = 201; fire("TRAIT_CONFIG_UPDATED"); flush()
check(not LO.IsApplying(), "done")
-- back to where the test was
W.specIndex = 1; fire("PLAYER_SPECIALIZATION_CHANGED"); flush()
C.groups.pvp.specs[VENG] = nil
wear(1); W.activeConfig[HAVOC] = 101; fire("PLAYER_EQUIPMENT_CHANGED")
specButton(HAVOC):Click()
W.log = {}

-- ---------------------------------------------------------------- splitting
treeRow("Loadout", "group:pve"):Click()
p.split:Click()
eq(C.split.pve, true, "PvE split")
eq(#shownRows(), 8, "four scenarios more")
treeRow("Loadout", "scenario:dungeon"):Click()
eq(d.title:GetText(), L["SCN_dungeon"], "dungeon selected")
check(not p.split:IsShown(), "a scenario page has no split switch")
check(p.follow:IsShown() and p.follow:GetChecked(), "uses the group's settings: on by default")
check(p.follow.label:GetText():find("PvE", 1, true), "and the label names the group")
eq(p.talents.text:GetText(), "M+ AoE", "shows the group's value")
check(p.talents.disabled, "read-only while it uses the group's")
p.talents:Click()
check(not T.frames.CombatKitOptionList:IsShown(), "a disabled dropdown does not open")
check(not p.auto:IsShown(), "dungeons have no spec switch")

p.follow:Click()
eq(C.scenarios.dungeon.custom, true, "unchecked: its own settings")
check(C.scenarios.dungeon.specs[HAVOC] and C.scenarios.dungeon.specs[HAVOC] ~= C.groups.pve.specs[HAVOC], "starts as a copy of the group's cells")
check(pick(p.gear, 3), "dungeon: different gear")
eq(C.groups.pve.specs[HAVOC].setID, 1, "the group's cell is untouched")
eq(treeRow("Loadout", "scenario:dungeon").tag:GetText(), L["own"], "the tree marks it")

-- switch spec automatically: a check box, and the big icons pick the spec
treeRow("Loadout", "scenario:world"):Click()
check(p.auto:IsShown() and not p.auto:GetChecked(), "open world offers the spec switch, off")
specButton(VENG):Click()
eq(C.scenarios.world.autoSpec, nil, "while off, an icon only picks what is edited")
specButton(HAVOC):Click()
p.auto:Click()
eq(C.scenarios.world.autoSpec, HAVOC, "checked: the picked spec becomes the target")
check(p.autoHint:IsShown() and p.autoHint:GetText():find("Havoc", 1, true), "the hint names it")
specButton(VENG):Click()
eq(C.scenarios.world.autoSpec, VENG, "while on, picking another icon moves the target")
check(specButton(VENG).tag:IsShown() and not specButton(HAVOC).tag:IsShown(), "and the tag")
p.follow:Click()
check(pick(p.talents, 201), "the fields below edit the target spec")
treeRow("Loadout", "scenario:dungeon"):Click()
specButton(HAVOC):Click()
treeRow("Loadout", "scenario:world"):Click()
eq(p.talents.text:GetText(), "Tank", "the page opens on the spec it switches to")
p.auto:Click()
eq(C.scenarios.world.autoSpec, nil, "unchecked: no spec switch")
C.scenarios.world.custom = false; C.scenarios.world.specs = {}

treeRow("Loadout", "scenario:delve"):Click()
eq(d.desc:GetText(), "", "a scenario whose name says it all has no description")
treeRow("Loadout", "group:pve"):Click()
p.split:Click()
eq(#shownRows(), 4, "collapsed")
eq(C.scenarios.dungeon.custom, true, "the scenarios keep their settings for later")

-- ---------------------------------------------------------------- Loadout options page
treeRow("Loadout", "options"):Click()
local lopt = main.bodies.Loadout.pages.options
check(lopt:IsShown() and not p:IsShown(), "only the page is shown")
lopt.auto:Click(); eq(LO.db.settings.auto, false, "auto off"); lopt.auto:Click()
eq(LO.defaults.auto, false, "a fresh install does not switch on its own")
lopt.early:Click(); eq(LO.db.settings.early, false, "early off"); lopt.early:Click()

-- ---------------------------------------------------------------- settings page: language, window size, HUD
go("kit", "general")
check(tab("kit").sel:IsShown() and not tab("Loadout").sel:IsShown(), "the kit's tab is open")
eq(#shownRows(), 3, "its tree: Modules, General, HUD")
eq(d.title:GetText(), L["General"], "general page")
local general = main.bodies.kit.pages.general
local hudPage = main.bodies.kit.pages.hud
check(hudPage.hudShow ~= nil and general.hudShow == nil, "everything about the HUD sits on its own page")
local startLocale = CK.activeLocale

check(pick(general.language, "zhTW"), "language: zhTW")
eq(CK.activeLocale, "zhTW", "applied")
eq(CK.db.settings.locale, "zhTW", "saved")
eq(hudPage.hudShow.label:GetText(), "顯示 HUD", "bound labels follow the language")
eq(d.title:GetText(), "一般", "refreshed texts follow too")
eq(LO.ScenarioName("world"), "開放世界", "module strings follow")
eq(LO.ScenarioName("dungeon"), "地城/M+", "renamed: dungeons")
eq(tab("Loadout").text:GetText(), "自動換裝", "so do the tabs")
check(pick(general.language, "enUS"), "language: English")
eq(hudPage.hudShow.label:GetText(), "Show the HUD", "and back to English")
check(pick(general.language, nil), "language: follow the game")
eq(CK.db.settings.locale, nil, "auto is stored as nothing")
eq(CK.activeLocale, startLocale, "the game's language again")

O.SetWindowScale(9); eq(CK.db.settings.windowScale, 2, "window size is capped")
O.SetWindowScale(1.2); eq(main.__scale, 1.2, "the window is rescaled")
eq(general.windowScale:GetText(), "120%", "and says so")
O.SetWindowScale(1.5)

-- ---------------------------------------------------------------- settings page: the HUD
go("kit", "hud")
eq(d.title:GetText(), "HUD", "HUD page")
check(hudPage:IsShown() and not general:IsShown(), "only that page is shown")
hudPage.locked:Click(); eq(CK.db.hud.locked, true, "locked")
local moved = false
rawset(hud, "StartMoving", function() moved = true end)
local section = hud.sections.loadout
section:GetScript("OnDragStart")(section); check(not moved, "a locked HUD does not move")
hudPage.locked:Click()
section:GetScript("OnDragStart")(section); check(moved, "an unlocked one does, dragged by a section")
section:GetScript("OnDragStop")(section)
eq(CK.db.hud.x, 10, "position saved, rounded")
eq(CK.db.hud.y, -21, "position saved, rounded (y)")
hudPage.locked:Click()   -- (re)lock for the checks below
CK.HUD.ResetPosition(); eq(CK.db.hud.y, CK.defaults.hud.y, "reset from the settings")
-- the corner the box keeps while lines come and go
eq(CK.db.hud.anchor, "TOPLEFT", "grows down and to the right by default")
check(pick(hudPage.anchor, "BOTTOMRIGHT"), "anchor: bottom right")
eq(CK.db.hud.anchor, "BOTTOMRIGHT", "saved")
eq(hudPage.anchor.text:GetText(), L["ANCHOR_BOTTOMRIGHT"], "and shown")
CK.HUD.SetAnchor("SIDEWAYS"); eq(CK.db.hud.anchor, "BOTTOMRIGHT", "only the four corners")
CK.HUD.SetAnchor("TOPLEFT")
hudPage.locked:Click()

CK.HUD.SetScale(5); eq(CK.db.hud.scale, 1.8, "scale is capped")
CK.HUD.SetScale(0.1); eq(CK.db.hud.scale, 0.6, "scale has a floor")
W.ctrl = true; section:GetScript("OnMouseWheel")(section, 1); eq(CK.db.hud.scale, 0.7, "ctrl + wheel resizes")
W.ctrl = false; section:GetScript("OnMouseWheel")(section, 1); eq(CK.db.hud.scale, 0.7, "plain wheel does not")
eq(hud.__scale, 0.7, "the frame is scaled")
eq(hudPage.hudScale:GetText(), "70%", "the settings page shows the size")

-- the HUD's look: background, border, font
eq(hud.__bg[4], 0.8, "background: 80% by default")
eq(hud.__border[4], 1, "with its border")
CK.HUD.SetBackgroundAlpha(0.04)
eq(CK.db.hud.bgAlpha, 0, "the background can go all the way to nothing")
eq(hud.__bg[4], 0, "and does")
eq(hudPage.bgAlpha:GetText(), "0%", "the page says so")
eq(hud.__border[4], 1, "the border is a switch of its own")
hudPage.border:Click()
check(CK.db.hud.border == false and hud.__border[4] == 0, "unticked: no border")
hudPage.border:Click()
eq(hud.__border[4], 1, "and back")
CK.HUD.SetBackgroundAlpha(2); eq(CK.db.hud.bgAlpha, 1, "capped at 100%")
CK.HUD.SetBackgroundAlpha(0.8)

GameFontHighlightSmall = { GetFont = function() return "Fonts\\FRIZQT__.TTF", 10, "" end }
local gameFont = (GetLocale() == "zhTW") and "Fonts\\bHEI01B.ttf" or "Fonts\\ARIALN.TTF"
check(pick(hudPage.font, gameFont), "font: one of the game's own for this client")
eq(CK.db.hud.font, gameFont, "saved as a file")
eq(rows[2].value.__font[1], gameFont, "the HUD rows use it")
eq(rows[2].value.__font[2], 10, "at the size the rows always had")
eq(hudPage.font.text:GetText(), CK.db.hud.fontName, "the page shows its name")
W.badFonts = { ["Fonts\\Gone.ttf"] = true }
CK.HUD.SetFont("Fonts\\Gone.ttf", "Gone")
eq(rows[2].value.__fontObject, "GameFontHighlightSmall", "a font file that is gone falls back to the game's font")
check(pick(hudPage.font, nil), "font: game default")
check(CK.db.hud.font == nil and rows[2].value.__fontObject == "GameFontHighlightSmall", "back to the game's own")
eq(hudPage.font.text:GetText(), L["Game default"], "and the page says so")

-- a long list (LibSharedMedia can bring dozens of fonts) scrolls instead of growing off the screen
LibStub = function() return {
	List = function() local t = {}; for i = 1, 30 do t[i] = "Font " .. i end; return t end,
	Fetch = function(_, _, name) return "Interface\\AddOns\\X\\" .. name .. ".ttf" end,
} end
hudPage.font:Click()
local list = T.frames.CombatKitOptionList
local shown = 0
for _, b in ipairs(list.buttons) do if b:IsShown() then shown = shown + 1 end end
eq(shown, 12, "twelve rows at a time")
eq(list.buttons[2].item.label, "Font 1", "starting at the top, after 'game default'")
check(list.thumb:IsShown(), "with a scroll thumb")
list:GetScript("OnMouseWheel")(list, -1)
eq(list.buttons[2].item.label, "Font 2", "the wheel scrolls")
for _ = 1, 40 do list:GetScript("OnMouseWheel")(list, -1) end
eq(list.buttons[12].item.label, "Font 30", "down to the last one, not past it")
list.buttons[12]:Click()
eq(CK.db.hud.fontName, "Font 30", "a font from the shared library can be picked")
LibStub = nil
CK.HUD.SetFont(nil)

-- the row with the icon keeps its text next to the icon; the values of the other rows are
-- flush with the right edge
eq(rows[1].value.__point[1], "TOPLEFT", "the spec name is anchored on the left")
eq(rows[1].value.__point[2], 8 + 14 + 4, "right after the icon")
check(rows[2].value.__point[1] == "TOPRIGHT" and rows[2].value.__point[2] == -8, "talents: flush with the right edge")
check(rows[3].value.__point[1] == "TOPRIGHT", "gear too")

-- ---------------------------------------------------------------- modules page
go("kit", "modules")
local mods = main.bodies.kit.pages.modules
check(mods.Loadout.check:GetChecked() and not mods.Stats.check:GetChecked(), "the page shows what is on")
check(rawget(mods, "Range") ~= nil and rawget(mods, "RightClick") == nil and rawget(mods, "CombatAlert") == nil and #mods.rows == 3,
	"modules only: the small features are switched in their own tab")
check(not mods.reload:IsShown(), "no reload note while nothing was switched off")
mods.Loadout.check:Click()
eq(CK.IsModuleEnabled("Loadout"), false, "Loadout switched off from the page")
check(mods.reload:IsShown() and mods.note:IsShown(), "now a reload frees its memory, and the page says so")
check(tab("Loadout").dimmed, "its tab is dimmed")
mods.reload:Click(); check(W.reloaded, "the button reloads")
tab("Loadout"):Click()
check(main.off:IsShown() and not main.bodies.Loadout:IsShown() and #shownRows() == 0, "the tab offers to switch it on instead of showing its pages")
eq(d.title:GetText(), L["MOD_Loadout"], "under the module's name")
eq(d.desc:GetText(), L["MODDESC_Loadout"], "and what it does")
check(main.off.state:GetText():find(L["STATE_stale"], 1, true), "its code is still loaded: said here too")
main.off.check:Click(); flush()
check(CK.IsModuleEnabled("Loadout") and not main.off:IsShown() and not tab("Loadout").dimmed, "ticked: the module is on again")
check(treeRow("Loadout", "group:pve") ~= nil and main.bodies.Loadout:IsShown(), "and its pages are back")

-- a module with a single page has no tree; the tab remembers its page while the window is open
tab("Stats"):Click()
eq(d.desc:GetText(), L["MODDESC_Stats"], "Stats is off: described")
main.off.check:Click(); flush()
check(CK.IsModuleEnabled("Stats") and main.bodies.Stats and main.bodies.Stats:IsShown(), "switched on from its tab")
check(not main.tree:IsShown(), "one page: no tree")
go("Loadout", "options")
tab("Stats"):Click(); tab("Loadout"):Click()
eq(select(2, O.GetSelection()), "options", "back on the page it was left on")
check(main.tree:IsShown(), "with its tree")
CK.SetModuleEnabled("Stats", false)

-- ---------------------------------------------------------------- debug page
main:Hide()
CK.OpenOptions("Loadout/debug")
local dbg = main.bodies.Loadout.pages.debug
check(main:IsShown() and dbg:IsShown(), "the window can be opened straight on the debug page")
-- a button per scenario and one for "off"; everything else waits behind "Advanced"
eq(#dbg.scenarioButtons, 7, "off + six scenarios")
eq(dbg.groupLabels.pve:GetText(), L["GROUP_pve"], "a line per group, named")
local world, raid, arena = dbg.scenarioButtons.world, dbg.scenarioButtons.raid, dbg.scenarioButtons.arena
check(world.__point[2] == 44 and arena.__point[2] == 44, "each line starts after the group's name")
check(world.__point[3] == raid.__point[3] and arena.__point[3] < world.__point[3], "PvE on one line, PvP on the next")
check(dbg.scenarioButtons.off.__point[3] == 0, "'off' sits on the title line")
check(dbg.scenarioButtons.off.selected and not dbg.scenarioButtons.arena.selected, "nothing pretended: 'off' is lit")
check(not dbg.advanced:IsShown(), "the rest is folded away")
dbg.advancedToggle:Click()
check(dbg.advanced:IsShown() and dbg.advancedToggle.selected, "'Advanced' unfolds it")
dbg.advancedToggle:Click()
check(not dbg.advanced:IsShown(), "and folds it again")

W.log = {}; wear(1); W.activeConfig[HAVOC] = 101
dbg.scenarioButtons.arena:Click()
check(dbg.scenarioButtons.arena.selected and not dbg.scenarioButtons.off.selected, "pretend: arena, and its button is lit")
eq(LO.GetCurrentScenario(), "arena", "detection is overridden")
flush()
eq(W.log[1], "equip:2", "entering the pretended scenario switches for real")
check(rows[1].value:GetText():find(L["faked"], 1, true), "the HUD says it is pretending")
eq(treeRow("Loadout", "debug").tag:GetText(), L["faked"], "so does the tree")

dbg.dryRun:Click()
W.log = {}; T.chat = {}
eq(dbg.advancedToggle:GetText(), L["Advanced"] .. " (1)", "'Advanced' counts what is on inside it")
dbg.scenarioButtons.raid:Click()
flush()
eq(#W.log, 0, "dry run switches nothing")
check(T.said("M+ AoE"), "but says what it would do")
dbg.dryRun:Click()

dbg.locked:Click()
W.log = {}; wear(1)
dbg.scenarioButtons.bg:Click()
flush()
eq(#W.log, 0, "a running key or match blocks switching")
dbg.locked:Click(); flush()
eq(W.log[1], "equip:2", "and it is paid once that is over")

check(pick(dbg.early, "dungeon"), "pretend: queue pop")
check(rows[1].right:GetText():find(L["SCN_dungeon"], 1, true), "the pop is on the HUD")
dbg.warmode:Click()
check(pick(dbg.role, "HEALER"), "pretend: group role")
check(LO.GetAssignedRole() == "HEALER" and LO.IsWarMode(), "group role and war mode can be pretended")
dbg.enter:Click()
dbg.reset:Click()
check(next(LO.debug) == nil, "reset clears every pretence")
check(dbg.scenarioButtons.off.selected and dbg.advancedToggle:GetText() == L["Advanced"], "and the page shows it")
eq(LO.GetCurrentScenario(), "world", "back to the real place")
flush()

-- ---------------------------------------------------------------- HUD content and visibility
wear(1); W.activeConfig[HAVOC] = 101; fire("PLAYER_EQUIPMENT_CHANGED")
eq(LO.GetStatus("world").state, "ready", "world is ready")
check(rows[1].right:GetText():find(L["Ready"], 1, true), "state: ready")
check(rows[2].value:GetText():find("M+ AoE", 1, true) and rows[2].value:GetText():find(Skin.Hex("ok"), 1, true), "talents row: name, green")
wear(2); fire("PLAYER_EQUIPMENT_CHANGED")
-- what differs takes two lines: what is worn now, then what will be applied
check(rows[3].value:GetText():find("PvP", 1, true) and rows[3].value:GetText():find(Skin.Hex("dim"), 1, true), "gear row: what is worn now, dimmed")
eq(rows[4].label:GetText():find("→", 1, true) ~= nil, true, "a second line, marked with an arrow")
check(rows[4].value:GetText():find("PvE", 1, true) and rows[4].value:GetText():find(Skin.Hex("warn"), 1, true), "with the target, amber")
check(rows[2].value:GetText():find("M+ AoE", 1, true) and not rows[2].label:GetText():find("→", 1, true), "talents still match: one line")
check(rows[1].right:GetText():find(L["Click to switch"], 1, true), "state: click to switch")
W.activeConfig[HAVOC] = 102; fire("TRAIT_CONFIG_UPDATED")
check(rows[2].value:GetText():find("Raid ST", 1, true) and rows[3].label:GetText():find("→", 1, true) and rows[3].value:GetText():find("M+ AoE", 1, true), "talents differ too: now Raid ST, then M+ AoE")
check(rows[5].value:GetText():find("PvE", 1, true), "and the gear lines moved down")
W.activeConfig[HAVOC] = 101; fire("TRAIT_CONFIG_UPDATED")

W.log = {}
section:Click("LeftButton"); flush()
eq(W.log[1], "equip:1", "left click applies")
fire("EQUIPMENT_SWAP_FINISHED")
check(rows[1].right:GetText():find(L["Ready"], 1, true), "ready again")
check(rows[3].value:GetText():find("PvE", 1, true) and (not rows[4] or not rows[4].value:IsShown()), "back to one line per item")
section:GetScript("OnEnter")(section); section:GetScript("OnLeave")(section)

go("kit", "hud")
hudPage.hudShow:Click()
eq(CK.db.hud.show, "never", "HUD: hidden")
check(hud:IsShown(), "still shown while the window is open")
section:Click("RightButton")
check(not main:IsShown(), "right click toggles the window")
check(not hud:IsShown(), "hidden once the window closes")
CK.db.hud.show = "always"
LO.db.settings.hud = "mismatch"; CK.HUD.Refresh()
check(not hud:IsShown(), "Loadout can stay off the HUD while everything matches")
wear(2); fire("PLAYER_EQUIPMENT_CHANGED")
check(hud:IsShown(), "and show up when something differs")
LO.db.settings.hud = "always"

W.battlefield[1] = { "confirm", 3, "ARENA" }; fire("UPDATE_BATTLEFIELD_STATUS")
check(rows[1].right:GetText():find(L["SCN_arena"], 1, true), "a real pop is named on the HUD")
check(rows[3].value:GetText():find("PvP", 1, true), "and the upcoming gear is shown")
W.battlefield[1] = nil; fire("UPDATE_BATTLEFIELD_STATUS")

-- ---------------------------------------------------------------- no Blizzard skin
for _, obj in ipairs(T.all) do
	local template = rawget(obj, "__template")
	if template and template ~= "BackdropTemplate" and template ~= "SecureHandlerStateTemplate" then
		check(false, "Blizzard template in use: " .. tostring(template))
	end
end
check(true, "only BackdropTemplate is used")

local wasShown = main:IsShown()
SlashCmdList.COMBATKIT("anything at all")
check(main:IsShown() ~= wasShown, "/ck with any text just toggles the window")
if main:IsShown() then main:Hide() end
CombatKit_OnAddonCompartmentClick(); check(main:IsShown(), "compartment click opens the window")

T.releaseChat()
return T.report("ui    [" .. (LOCALE or "enUS") .. "]")
