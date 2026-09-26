local CK = CombatKit

-- What the module itself says: names, HUD texts, chat. The settings pages keep
-- their own strings in CombatKit_Options.

CK.AddLocale("enUS", {
	["GROUP_pve"] = "PvE",
	["GROUP_pvp"] = "PvP",

	["SCN_world"]   = "Open world",
	["SCN_delve"]   = "Delves",
	["SCN_dungeon"] = "Dungeons / M+",
	["SCN_raid"]    = "Raids",
	["SCN_arena"]   = "Arena",
	["SCN_bg"]      = "Battlegrounds / rated",
	["SCN_SHORT_bg"] = "Battlegrounds",

	["ROLE_TANK"]    = "tank",
	["ROLE_HEALER"]  = "healer",
	["ROLE_DAMAGER"] = "damage",

	["LOADOUT_HINT"] = "Left click: switch now.",
	["DRYRUN_MSG"]   = "Dry run: spec %s, talents %s, gear %s.",
	["faked"]        = "simulated",
})

CK.AddLocale("zhTW", {
	["SCN_world"]   = "開放世界",
	["SCN_delve"]   = "探究",
	["SCN_dungeon"] = "地城/M+",
	["SCN_raid"]    = "Raid",
	["SCN_arena"]   = "Arena",
	["SCN_bg"]      = "戰場/積分戰場",
	["SCN_SHORT_bg"] = "戰場",

	["ROLE_TANK"]    = "坦克",
	["ROLE_HEALER"]  = "治療",
	["ROLE_DAMAGER"] = "傷害輸出",

	["LOADOUT_HINT"] = "左鍵：立即切換。",
	["DRYRUN_MSG"]   = "模擬：專精 %s，天賦 %s，裝備 %s。",

	-- HUD
	["Talents"]        = "天賦",
	["Gear"]           = "裝備",
	["Ready"]          = "就緒",
	["Applying"]       = "套用中",
	["Stand still"]    = "站定後切換",
	["After combat"]   = "戰鬥後套用",
	["Click to switch"] = "點擊切換",
	["Not set up"]     = "未設定",
	["missing"]        = "已不存在",
	["faked"]          = "模擬",
	["Queue: %s"]      = "排到：%s",
	["Scenario"]       = "場景",
	["Settings from"]  = "設定來源",
	["Spec on entering"] = "進入時專精",
	["Status"]         = "狀態",

	-- chat
	["In combat. It will be applied when combat ends."] = "戰鬥中，脫離戰鬥後套用。",
	["Could not switch specialization."] = "無法切換專精。",
	["Could not equip %s."] = "無法換上 %s。",
	["Not switching to %s: your role in this group is %s."] = "沒有切換到%s：你在這個隊伍的職責是%s。",
	["Could not load the talent loadout: %s"] = "無法載入天賦配置：%s",
	["unknown reason"] = "原因不明",
	["%s interrupted. Click the HUD to apply again."] = "%s被中斷。要套用時點一下 HUD。",
	["Spec change"]   = "專精切換",
	["Talent change"] = "天賦變更",
})
