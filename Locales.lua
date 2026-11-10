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
	["MOD_PartyCD"]     = "Party CD (beta)",
	["TAB_PartyCD"]     = "Party CD",
	["MOD_Misc"]        = "Extras",
	["MOD_Reminder"]    = "Reminder",
	["MODDESC_Loadout"] = "Switches talents and gear to match the scenario you are in, set up per spec.",
	["MODDESC_Stats"] = "Your stats on the HUD.",
	["MODDESC_Range"] = "Display range for target, focus and mouseover.",
	["MODDESC_PartyCD"] = "Your teammates' cooldowns, tracked.",
	["MODDESC_Reminder"] = "Remind of missing consumables and class buffs.",
	["SCN_world"]   = "Open world",
	["SCN_delve"]   = "Delves",
	["SCN_dungeon"] = "Dungeons / M+",
	["SCN_raid"]    = "Raids",
	["SCN_arena"]   = "Arena",
	["SCN_bg"]      = "Battlegrounds / rated",
	["SCN_SHORT_bg"] = "Battlegrounds",
	["FEAT_RightClick"]  = "Disable right click in combat",
	["FEAT_CombatAlert"] = "Combat alert",
	["FEAT_SapIcon"]     = "Mark sappable enemy players",
	["HUD_HINT"]        = "Right click: settings. Drag to move, Ctrl + mouse wheel to resize.",
	["LANG_auto"]       = "Auto (game language)",
	["SWITCH_OFF"]      = "Off",
	["SWITCH_ON"]       = "On",
	["Slash hint"]      = "/ck opens the settings.",
	["LANDING_FIRST"]   = "Welcome to CombatKit.\nLoad only the modules you use: one that is not loaded costs nothing. Settings later in Options > AddOns or /ck.",
	["LANDING_NEW"]     = "This version has new modules. Load only the ones you use: one that is not loaded costs nothing. Settings later in Options > AddOns or /ck.",
})

ns.AddLocale("zhTW", {
	["MOD_Loadout"]     = "自動換裝",
	["MOD_Stats"]       = "顯示屬性",
	["MOD_Range"]       = "顯示距離",
	["MOD_PartyCD"]     = "隊友冷卻 (beta)",
	["TAB_PartyCD"]     = "隊友冷卻",
	["MOD_Misc"]        = "額外功能",
	["MOD_Reminder"]    = "Reminder",
	["MODDESC_Loadout"] = "依所在場景自動切換天賦與裝備，每個專精各自設定。",
	["MODDESC_Stats"] = "在 HUD 上顯示你的屬性數值。",
	["MODDESC_Range"] = "顯示與目標、專注目標、滑鼠指向單位的距離。",
	["MODDESC_PartyCD"] = "隊友技能冷卻監控。",
	["MODDESC_Reminder"] = "提醒缺少的消耗品與職業增益。",
	["SCN_world"]   = "開放世界",
	["SCN_delve"]   = "探究",
	["SCN_dungeon"] = "地城/M+",
	["SCN_raid"]    = "團本",
	["SCN_arena"]   = "競技場",
	["SCN_bg"]      = "戰場/積分戰場",
	["SCN_SHORT_bg"] = "戰場",
	["FEAT_RightClick"]  = "戰鬥中停用右鍵",
	["FEAT_CombatAlert"] = "進戰鬥提醒",
	["FEAT_SapIcon"]     = "標示可悶棍的敵方玩家",
	["HUD_HINT"]        = "右鍵：設定。拖曳移動，Ctrl + 滾輪縮放。",
	["LANG_auto"]       = "自動（跟隨遊戲語言）",
	["SWITCH_OFF"]      = "關",
	["SWITCH_ON"]       = "開",
	["Slash hint"]      = "輸入 /ck 開啟設定。",
	["Open settings"]                   = "開啟設定",
	["Go to settings"]                  = "進入設定",
	["%s is not installed."]            = "%s 沒有安裝。",
	["Could not load %s (%s)."]         = "無法載入 %s（%s）。",
	["LANDING_FIRST"]   = "歡迎使用 CombatKit。\n按需載入你要用的模組，沒載入的不消耗效能。後續設定在「選項 > 插件」或 /ck。",
	["LANDING_NEW"]     = "這版有新的模組。按需載入你要用的，沒載入的不消耗效能。後續設定在「選項 > 插件」或 /ck。",
	["Apply"]           = "套用",
	["Later"]           = "稍後再說",
})
