-- The kit itself: which addons get loaded, modules switched on and off, the
-- HUD as a container. "A module that is off costs nothing" is tested here as
-- "it is never loaded".

local T = dofile(HERE .. "/stubs.lua")
local check, eq, W, fire, flush = T.check, T.eq, T.W, T.fire, T.flush
T.captureChat()

local function loaded(name) return T.loaded[name] ~= nil end

-- ---------------------------------------------------------------- first login: defaults
-- the game's Options > AddOns list, and its panel
local registered
Settings = {
	RegisterCanvasLayoutCategory = function(panel, name) return { panel = panel, name = name } end,
	RegisterAddOnCategory = function(category) registered = category end,
}
SettingsPanel = T.Mock("Frame", "SettingsPanel")
function HideUIPanel(frame) frame:Hide() end

CombatKitLoadoutDB = { settings = { auto = true } }
local CK = T.boot()
check(loaded("CombatKit"), "the core is loaded")
check(loaded("CombatKit_Loadout"), "Loadout is on by default, so it is loaded at login")
check(not loaded("CombatKit_Options"), "the settings window is not loaded until it is opened")
for _, name in ipairs({ "CombatKit_Stats", "CombatKit_Range", "CombatKit_Misc" }) do
	check(not loaded(name), name .. " is off by default, so it is never loaded")
end
eq(CK.GetModuleState("Loadout"), "on", "state: on")
eq(CK.GetModuleState("Stats") == "off" or CK.GetModuleState("Stats") == "missing", true, "state: off (or not written yet)")
check(CombatKitLoadoutDB ~= nil, "a loaded module has its saved variables")

-- ---------------------------------------------------------------- switching a module off and on
local LO = CK.modules.Loadout
fire("PLAYER_ENTERING_WORLD")
local hud = CK.HUD.GetFrame()
check(hud and hud:IsShown() and hud.sections.loadout:IsShown(), "Loadout shows its lines on the HUD")

CK.SetModuleEnabled("Loadout", false)
eq(CK.IsModuleEnabled("Loadout"), false, "switched off")
eq(CK.GetModuleState("Loadout"), "stale", "its code stays until a reload, and the state says so")
check(not hud:IsShown(), "with no section left the HUD hides")
W.log = {}
LO.char.groups.pve.specs[577] = { setID = 1, setName = "PvE" }
W.inInstance, W.instanceType = true, "raid"
fire("PLAYER_ENTERING_WORLD")
eq(#W.log, 0, "a module that is off does not react to events any more")

CK.SetModuleEnabled("Loadout", true); flush()
eq(CK.GetModuleState("Loadout"), "on", "switched on again, without a reload")
check(hud:IsShown(), "and back on the HUD")
eq(W.log[1], "equip:1", "it picks up where the player is")

-- ---------------------------------------------------------------- a module that cannot be loaded says why
T.chat = {}
T.missing.CombatKit_Stats = true
CK.SetModuleEnabled("Stats", true)
eq(CK.GetModuleState("Stats"), "missing", "not installed")
check(T.said("CombatKit_Stats"), "and the chat says which addon is missing")
CK.SetModuleEnabled("Stats", false)
T.missing.CombatKit_Stats = nil

-- ---------------------------------------------------------------- the settings window loads on demand
T.unticked.CombatKit_Options = true
SlashCmdList.COMBATKIT("")
check(loaded("CombatKit_Options"), "/ck loads the settings, ticking them in the AddOns list if needed")
check(CK.IsOptionsShown(), "and opens them")
check(hud:IsShown(), "the HUD is visible while the window is open")
SlashCmdList.COMBATKIT("")
check(not CK.IsOptionsShown(), "/ck again closes it")

-- ---------------------------------------------------------------- HUD as a container
CK.HUD.AddSection({ key = "test", order = 50, GetRows = function()
	return { { label = "Crit", value = "23.4%" }, { label = "Haste", value = "18.0%" } }
end })
check(hud.sections.test:IsShown(), "a second section appears")
eq(hud.sections.test.rows[2].value:GetText(), "18.0%", "with its rows")
check(hud.rules[1]:IsShown(), "and a line between the two")
CK.SetModuleEnabled("Loadout", false)
check(hud:IsShown() and not hud.sections.loadout:IsShown(), "sections come and go independently")
check(not hud.rules[1]:IsShown(), "one section needs no line")
CK.db.hud.show = "never"; CK.HUD.Refresh()
check(not hud:IsShown(), "the HUD can be hidden altogether")
CK.db.hud.show = "always"
CK.HUD.RemoveSection("test")
check(not hud:IsShown(), "no sections, no HUD")

-- ---------------------------------------------------------------- the ways in besides /ck
-- (that being listed loads nothing is checked at the top: the settings window was not loaded after login)
check(registered and registered.name == "CombatKit" and registered.panel == CK.gameOptions.panel, "listed under Options > AddOns")
if CK.Options and CK.Options.IsShown() then CK.Options.GetFrame():Hide() end
SettingsPanel:Show()
CK.gameOptions.open:GetScript("OnClick")(CK.gameOptions.open)
check(loaded("CombatKit_Options") and CK.Options.IsShown(), "its button opens the kit's own window")
check(not SettingsPanel:IsShown(), "and closes the game's panel, which would cover it")
CK.Options.GetFrame():Hide()
SettingsPanel:Show(); W.combat = true
CK.gameOptions.open:GetScript("OnClick")(CK.gameOptions.open)
check(CK.Options.IsShown() and SettingsPanel:IsShown(), "in combat the game's panel is left alone: closing it is protected")
W.combat = false
CK.Options.GetFrame():Hide()
CombatKit_OnAddonCompartmentClick()
check(CK.Options.IsShown(), "the addon compartment entry opens it too")
CK.Options.GetFrame():Hide()

-- ---------------------------------------------------------------- next login: only what is on
-- (a fresh Lua state stands in for a reload; the saved variables carry over)
local saved = CombatKitDB
eq(saved.modules.Loadout, false, "the choice is saved")
eq(type(saved.modules.Misc), "table", "a module with features saves one flag per feature")

T.releaseChat()
return T.report("kit   [" .. (LOCALE or "enUS") .. "]")
