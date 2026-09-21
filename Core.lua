local ADDON, ns = ...
local L = ns.L

-- The one global: load-on-demand modules and the options reach the core through it.
CombatKit = ns

local PREFIX = "|cff66ccffCombat|rKit: "
function ns.Msg(fmt, ...) print(PREFIX .. string.format(fmt, ...)) end

-- ---------------------------------------------------------------------------
-- Modules
--
-- Every module is its own load-on-demand addon (Modules/<Name> in the source,
-- CombatKit_<Name> when installed). A module that is off is never loaded: no
-- code, no frames, not even its saved variables. Turning one on loads it right
-- away; turning one off stops it right away, and the memory of what was loaded
-- comes back with the next reload, since the game cannot unload code.
--
-- A module's private addon table is the module object. It calls
-- CombatKit.NewModule(name, ns) and provides ns.OnEnable() / ns.OnDisable().
--
-- Things too small to deserve an addon of their own share one ("Misc"): such a
-- module lists `features`, each switched on its own, and is loaded only while
-- at least one of them is on. It also provides ns.SetFeature(feature, on).
-- ---------------------------------------------------------------------------

-- Static so the settings can list modules that are not loaded.
ns.MODULES = {
	{ name = "Loadout", default = true },
	{ name = "Stats",   default = false },
	{ name = "Range",   default = false },
	{ name = "Misc",    features = { "RightClick", "CombatAlert" } },
}
ns.MODULE_BY_NAME = {}
for _, m in ipairs(ns.MODULES) do
	m.addon = "CombatKit_" .. m.name
	ns.MODULE_BY_NAME[m.name] = m
end

ns.modules = {}   -- loaded module objects, by name
ns.slash = {}     -- "/ck <word>" handlers added by modules

function ns.NewModule(name, object)
	object.name = name
	ns.modules[name] = object
	return object
end

-- Should this module be running? With features: when any of them is on.
local function Wanted(def)
	local saved = ns.db.modules[def.name]
	if not def.features then return saved and true or false end
	for _, feature in ipairs(def.features) do
		if saved[feature] then return true end
	end
	return false
end

function ns.IsModuleEnabled(name)
	return Wanted(ns.MODULE_BY_NAME[name])
end

function ns.IsFeatureEnabled(name, feature)
	local saved = ns.db.modules[name]
	return type(saved) == "table" and saved[feature] and true or false
end

-- "on" | "off" | "stale" (off, but its code stays loaded until a reload) | "missing" (not installed)
function ns.GetModuleState(name)
	local def = ns.MODULE_BY_NAME[name]
	local module = ns.modules[name]
	if module and module.enabled then return "on" end
	if C_AddOns.DoesAddOnExist and not C_AddOns.DoesAddOnExist(def.addon) then return "missing" end
	if module then return "stale" end
	return "off"
end

-- Returns true once `addon` is in memory, and says why when it cannot be.
local function Load(addon)
	if C_AddOns.DoesAddOnExist and not C_AddOns.DoesAddOnExist(addon) then
		ns.Msg(L["%s is not installed."], addon)
		return false
	end
	-- unticked in the game's AddOns list: asking for it here means wanting it
	if C_AddOns.GetAddOnEnableState and C_AddOns.GetAddOnEnableState(addon) == 0 then
		C_AddOns.EnableAddOn(addon)
	end
	local loaded, reason = C_AddOns.LoadAddOn(addon)
	if not loaded then
		ns.Msg(L["Could not load %s (%s)."], addon, tostring(reason or "?"))
		return false
	end
	return true
end

local function StartModule(def)
	local module = ns.modules[def.name]
	if not module then
		if not Load(def.addon) then return nil end
		module = ns.modules[def.name]
		if not module then
			ns.Msg(L["Could not load %s (%s)."], def.addon, "no module")
			return nil
		end
	end
	if not module.enabled then
		module.enabled = true
		module.OnEnable()
	end
	return module
end

local function StopModule(def)
	local module = ns.modules[def.name]
	if module and module.enabled then
		module.enabled = false
		module.OnDisable()
	end
end

local function Changed()
	ns.RefreshOptions()
	ns.HUD.Refresh()
end

function ns.SetModuleEnabled(name, on)
	local def = ns.MODULE_BY_NAME[name]
	if not def or def.features then return end
	ns.db.modules[name] = on and true or false
	if on then StartModule(def) else StopModule(def) end
	Changed()
end

function ns.SetFeatureEnabled(name, feature, on)
	local def = ns.MODULE_BY_NAME[name]
	if not def or not def.features then return end
	ns.db.modules[name][feature] = on and true or false
	if Wanted(def) then
		local module = StartModule(def)   -- a fresh start reads every feature flag itself
		if module then module.SetFeature(feature, on and true or false) end
	else
		local module = ns.modules[name]
		if module and module.enabled then module.SetFeature(feature, false) end
		StopModule(def)
	end
	Changed()
end

-- ---------------------------------------------------------------------------
-- Settings window: load on demand too
-- ---------------------------------------------------------------------------

local OPTIONS_ADDON = "CombatKit_Options"

local function EnsureOptions()
	if ns.Options then return true end
	if not Load(OPTIONS_ADDON) then return false end
	if not ns.Options then
		ns.Msg(L["Could not load %s (%s)."], OPTIONS_ADDON, "no window")
		return false
	end
	return true
end

-- node: optional "Section/key" to open straight on a page
function ns.OpenOptions(node)
	if EnsureOptions() then ns.Options.Open(node) end
end

function ns.ToggleOptions()
	if EnsureOptions() then ns.Options.Toggle() end
end

-- safe to call from anywhere: nothing happens while the options are not loaded
function ns.RefreshOptions()
	if ns.Options then ns.Options.Refresh() end
end

function ns.IsOptionsShown()
	return ns.Options ~= nil and ns.Options.IsShown()
end

-- ---------------------------------------------------------------------------
-- Saved data (CombatKitDB): what the core owns. Each module keeps its own.
--
--   CombatKitDB = {
--     version  = 1,
--     settings = { windowScale=, locale= ("enUS" | "zhTW"; absent = follow the game) },
--     hud      = { show = "always" | "never", scale=, locked=, point=, relPoint=, x=, y=,
--                  bgAlpha= (0 = no background), border=, font= (file; absent = the game's), fontName= },
--     modules  = { Loadout = true, Stats = false, Misc = { RightClick = false, ... } },
--   }
-- ---------------------------------------------------------------------------

ns.defaults = {
	settings = { windowScale = 1.5 },
	hud = { show = "always", scale = 1.0, locked = false, point = "TOP", relPoint = "TOP", x = 0, y = -170,
		bgAlpha = 0.8, border = true },
}

local function InitDB()
	if type(CombatKitDB) ~= "table" then CombatKitDB = {} end
	local db = CombatKitDB
	db.version = db.version or 1
	for section, values in pairs(ns.defaults) do
		db[section] = db[section] or {}
		for k, v in pairs(values) do
			if db[section][k] == nil then db[section][k] = v end
		end
	end
	db.modules = db.modules or {}
	for _, def in ipairs(ns.MODULES) do
		if def.features then
			if type(db.modules[def.name]) ~= "table" then db.modules[def.name] = {} end
			for _, feature in ipairs(def.features) do
				if db.modules[def.name][feature] == nil then db.modules[def.name][feature] = false end
			end
		elseif db.modules[def.name] == nil then
			db.modules[def.name] = def.default
		end
	end
	ns.db = db
	ns.ApplyLocale(db.settings.locale or GetLocale())
end

-- ---------------------------------------------------------------------------
-- Events, the ways in: slash command, addon compartment, the game's AddOns list
-- ---------------------------------------------------------------------------

-- An entry in the game's own Options > AddOns list. The settings are in the kit's
-- own window, which is loaded on demand, so the entry is a button that opens it.
local function RegisterInGameOptions()
	if not (Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory) then return end
	local Skin = ns.Skin
	local panel = CreateFrame("Frame")
	local title = Skin.Label(panel, "|cff66ccffCombat|rKit", "GameFontHighlightLarge")
	title:SetPoint("TOPLEFT", 16, -16)
	local hint = ns.Bind(Skin.Label(panel, "", nil, "dim"), "Slash help")
	hint:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)

	local open = CreateFrame("Button", nil, panel, "BackdropTemplate")
	open:SetSize(150, 24)
	open:SetPoint("TOPLEFT", hint, "BOTTOMLEFT", 0, -14)
	Skin.Backdrop(open, "element")
	local text = ns.Bind(Skin.Label(open, ""), "Open settings")
	text:SetPoint("CENTER")
	open:SetScript("OnEnter", function(self) self:SetBackdropBorderColor(Skin.Color("accent")) end)
	open:SetScript("OnLeave", function(self) self:SetBackdropBorderColor(Skin.Color("border")) end)
	open:SetScript("OnClick", function()
		-- the game's panel would cover ours; closing it is not allowed in combat
		if SettingsPanel and not InCombatLockdown() then HideUIPanel(SettingsPanel) end
		ns.OpenOptions()
	end)

	local category = Settings.RegisterCanvasLayoutCategory(panel, "CombatKit")
	Settings.RegisterAddOnCategory(category)
	ns.gameOptions = { panel = panel, open = open }   -- for the tests
end

local driver = CreateFrame("Frame")
driver:RegisterEvent("ADDON_LOADED")
driver:RegisterEvent("PLAYER_LOGIN")

driver:SetScript("OnEvent", function(self, event, arg1)
	if event == "ADDON_LOADED" then
		if arg1 == ADDON then
			InitDB()
			self:UnregisterEvent("ADDON_LOADED")
		end
	elseif event == "PLAYER_LOGIN" then
		RegisterInGameOptions()
		for _, def in ipairs(ns.MODULES) do
			if Wanted(def) then StartModule(def) end
		end
		ns.HUD.Refresh()
	end
end)

SLASH_COMBATKIT1 = "/combatkit"
SLASH_COMBATKIT2 = "/ck"
SlashCmdList.COMBATKIT = function(msg)
	local word, rest = strtrim(msg or ""):lower():match("^(%S*)%s*(.-)$")
	if word == "reset" then
		ns.HUD.ResetPosition()
	elseif word == "help" then
		ns.Msg(L["Slash help"])
	elseif ns.slash[word] then
		ns.slash[word](rest)
	else
		ns.ToggleOptions()
	end
end

function CombatKit_OnAddonCompartmentClick()
	ns.ToggleOptions()
end
