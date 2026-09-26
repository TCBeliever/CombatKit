local ADDON, ns = ...

-- L is filled by ns.ApplyLocale: enUS first, then the chosen locale on top.
-- A missing key reads as itself, so plain English sentences need no enUS
-- entry; only symbolic keys do. Modules and the options add their own strings
-- with ns.AddLocale when they load, so nothing is held for a module that is off.
local L = setmetatable({}, { __index = function(t, k) return k end })
ns.L = L
ns.locales = { enUS = {}, zhTW = {} }

ns.LANGUAGES = {
	{ code = nil,    key = "LANG_auto" },
	{ code = "enUS", label = "English" },
	{ code = "zhTW", label = "繁體中文" },
}

local wanted   -- the language in force: "enUS" | "zhTW" | anything else reads as English

-- Fill L for `code`.
function ns.ApplyLocale(code)
	wanted = code
	for k in pairs(L) do L[k] = nil end
	for k, v in pairs(ns.locales.enUS) do L[k] = v end
	local ov = ns.locales[code]
	if ov and ov ~= ns.locales.enUS then
		for k, v in pairs(ov) do L[k] = v end
	end
	ns.activeLocale = (ov and code) or "enUS"
end

-- Strings of a module or of the options, added when it loads.
function ns.AddLocale(code, strings)
	local target = ns.locales[code]
	if not target then return end
	for k, v in pairs(strings) do target[k] = v end
	ns.ApplyLocale(wanted)
end

-- Text that is set once (labels, buttons, check boxes) is bound to its key so
-- a language switch can set it again. Everything else is refreshed anyway.
local bound = {}

local function SetBoundText(widget, key)
	if widget.SetLabel then widget:SetLabel(L[key]) else widget:SetText(L[key]) end
end

function ns.Bind(widget, key)
	bound[#bound + 1] = { widget, key }
	SetBoundText(widget, key)
	return widget
end

-- code: "enUS" | "zhTW" | nil (follow the game)
function ns.SetLanguage(code)
	ns.db.settings.locale = code
	ns.ApplyLocale(code or GetLocale())
	for _, b in ipairs(bound) do SetBoundText(b[1], b[2]) end
	ns.RefreshOptions()
	ns.HUD.Refresh()
end

wanted = GetLocale()

ns.AddLocale("enUS", {
	["MOD_Loadout"]     = "Loadout",
	["MOD_Stats"]       = "Stats",
	["MOD_Range"]       = "Range",
	["MOD_Misc"]        = "Extras",
	["FEAT_RightClick"]  = "Disable right click in combat",
	["FEAT_CombatAlert"] = "Combat alert",
	["HUD_HINT"]        = "Right click: settings. Drag to move, Ctrl + mouse wheel to resize.",
	["LANG_auto"]       = "Auto (game language)",
	["Slash hint"]      = "/ck opens the settings.",
})

ns.AddLocale("zhTW", {
	["MOD_Loadout"]     = "自動換裝",
	["MOD_Stats"]       = "顯示屬性",
	["MOD_Range"]       = "顯示距離",
	["MOD_Misc"]        = "額外功能",
	["FEAT_RightClick"]  = "戰鬥中停用右鍵",
	["FEAT_CombatAlert"] = "進戰鬥提醒",
	["HUD_HINT"]        = "右鍵：設定。拖曳移動，Ctrl + 滾輪縮放。",
	["LANG_auto"]       = "自動（跟隨遊戲語言）",
	["Slash hint"]      = "輸入 /ck 開啟設定。",
	["Open settings"]                   = "開啟設定",
	["%s is not installed."]            = "%s 沒有安裝。",
	["Could not load %s (%s)."]         = "無法載入 %s（%s）。",
})
