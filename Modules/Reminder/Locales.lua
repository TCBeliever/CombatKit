local CK = CombatKit

-- What the module shows on screen: the names above the icons. A class buff is
-- named by the game (its spell's name, in the client's language); these are
-- the reminders that stand for more than one spell or item. The settings page
-- keeps its own strings in CombatKit_Options.

CK.AddLocale("enUS", {
	["REMINDER_HUD_TIP"] = "Missing consumables and buffs. Left click: the Reminder settings.",
	-- names above an icon: short enough for one line at the icon's width
	["Lethal poison"]     = "Lethal",
	["Non-lethal poison"] = "Non-lethal",
})

CK.AddLocale("zhTW", {
	["REMINDER_HUD_TIP"]  = "缺少的消耗品與增益。左鍵：Reminder 設定。",
	["Healthstone"]       = "治療石",
	["Flask"]             = "精煉",
	["Food"]              = "食物",
	["Augment rune"]      = "增強符文",
	["Weapon oil"]        = "武器油",
	["Off-hand oil"]      = "副手武器油",
	["Feast"]             = "大餐",
	["Flask cauldron"]    = "精煉大鍋",
	["Lethal poison"]     = "致命",
	["Non-lethal poison"] = "非致命",
	["Main-hand rune"]    = "主手符文",
	["Off-hand rune"]     = "副手符文",
	["Rune to change"]    = "該換符文",
})
