local CK = CombatKit

-- What the module shows on screen: the names above the icons. A class buff is
-- named by the game (its spell's name, in the client's language); these are
-- the reminders that stand for more than one spell or item. The settings page
-- keeps its own strings in CombatKit_Options.

CK.AddLocale("enUS", {
	["REMINDER_HUD_TIP"] = "Missing consumables and buffs. Left click: the Reminder settings.",
	-- the kinds of poison, on the settings page (the icon is named for the poison itself)
	["Lethal poison"]     = "Lethal poison",
	["Non-lethal poison"] = "Non-lethal poison",
	-- tooltips over an icon: why it shows, what a click does
	["Pet health low"] = "Pet low HP",
	["Pet %d"]     = "Pet %d",
	-- above the icon, for a spell whose own name is too long: Blessing of the Bronze
	["Blessing"]   = "Blessing",
	["Summon demon (%s)"] = "Summon demon (%s)",
	["Summon pet (%s)"]   = "Summon pet (%s)",
	["TIP_LEFT"]   = "%s left",
	["TIP_MIN"]    = "%d min left",
	["TIP_SEC"]    = "%d s left",
	["TIP_GROUP"]  = "%s in the group without it",
	["TIP_CAST"]   = "Left click: cast",
	["TIP_USE"]    = "Left click: use",
	["TIP_CHOOSE"] = "Hold Alt: pick another",
	["TIP_PICK"]   = "Left click: cast it. The icon casts it from now on.",
	["TIP_SOULWELL"] = "Take one from a warlock's Soulwell.",
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
	["Lethal poison"]     = "致命毒藥",
	["Non-lethal poison"] = "非致命毒藥",
	["Main-hand rune"]    = "主手符文",
	["Off-hand rune"]     = "副手符文",
	["Rune to change"]    = "該換符文",
	["Felguard"]          = "惡魔守衛",
	["Pet %d"]            = "寵物%d",
	["Summon demon (%s)"] = "召喚惡魔（%s）",
	["Summon pet (%s)"]   = "召喚寵物（%s）",
	["Water Elemental"]   = "水元素",
	["Blessing"]          = "祝福",
	["Pet health low"]    = "寵物低血",
	["TIP_LEFT"]          = "剩 %s",
	["TIP_MIN"]           = "剩 %d 分鐘",
	["TIP_SEC"]           = "剩 %d 秒",
	["TIP_GROUP"]         = "隊伍裡有 %s 人沒有",
	["TIP_CAST"]          = "左鍵：施放",
	["TIP_USE"]           = "左鍵：使用",
	["TIP_CHOOSE"]        = "按住 Alt：換一個",
	["TIP_PICK"]          = "左鍵：施放。之後圖示改施放這個。",
	["TIP_SOULWELL"]      = "到術士的靈魂之井拿一顆。",
})
