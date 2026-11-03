local CK = CombatKit

-- What the module shows on screen: the names above the icons. A class buff is
-- named by the game (its spell's name, in the client's language); these are
-- the reminders that stand for more than one spell or item. The settings page
-- keeps its own strings in CombatKit_Options.

CK.AddLocale("enUS", {
	["REMINDER_HUD_TIP"] = "What is missing before a pull. Left click: the Reminder settings.",
})

CK.AddLocale("zhTW", {
	["REMINDER_HUD_TIP"]  = "開怪前缺的東西。左鍵：Reminder 設定。",
	["Healthstone"]       = "治療石",
	["Flask"]             = "精煉藥劑",
	["Food"]              = "食物",
	["Augment rune"]      = "增強符文",
	["Weapon oil"]        = "武器油",
	["Off-hand oil"]      = "副手武器油",
	["Feast"]             = "大餐",
	["Flask cauldron"]    = "精煉藥劑大鍋",
	["Lethal poison"]     = "致命毒藥",
	["Non-lethal poison"] = "非致命毒藥",
	["Runeforge"]         = "符文熔鑄",
	["Off-hand rune"]     = "副手符文",
})
