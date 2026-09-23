local CK = CombatKit

-- Everything the settings window says. Module names and what modules say
-- themselves (HUD, chat) live with the core and the modules.

CK.AddLocale("enUS", {
	-- window
	["MODULES_DESC"]  = "A module that is off uses no memory.",
	["RELOAD_NOTE"]   = "Reload the UI to free the memory.",
	["STATE_missing"] = "not installed",
	["STATE_stale"]   = "reload needed",
	["STATE_waiting"] = "changes when combat ends",

	["MODDESC_Loadout"] = "Switches talents and gear to match the scenario you are in, set up per spec.",
	["MODDESC_Stats"]   = "Your stats on the HUD.",
	["MODDESC_Range"]   = "Distance to your target, focus and mouseover.",
	["FEATDESC_RightClick"]  = "In combat, right click no longer interacts with or targets the unit under the cursor, so turning the camera never switches your target. Back to normal when combat ends.",
	["FEATDESC_CombatAlert"] = "A short text when you enter and leave combat.",

	-- loadout pages: only what the name does not already say; none at all is fine
	["SCN_DESC_world"]   = "Outside instances, story scenarios included.",
	["SCN_DESC_delve"]   = "",
	["SCN_DESC_dungeon"] = "Every difficulty.",
	["SCN_DESC_raid"]    = "Every difficulty, world boss lairs included.",
	["SCN_DESC_arena"]   = "Skirmishes, 2v2, 3v3, Solo Shuffle.",
	["SCN_DESC_bg"]      = "Random, epic, rated, Battleground Blitz.",
	["LIST_SEP"]         = ", ",

	["STATS_DESC"]      = "Tick the stats to show; the arrows change their order.",

	["Outline: none"]  = "None",
	["Outline: thin"]  = "Thin",
	["Outline: thick"] = "Thick",

	["PAGE_debug"]      = "Debug",
	["PAGE_DESC_debug"] = "Simulate another scenario to test your setup. Nothing here is saved; a reload clears it.",

	["SPLIT_TIP_pve"] = "Lists open world, delves, dungeons and raids separately. Each keeps using the PvE settings until you give it its own.",
	["SPLIT_TIP_pvp"] = "Lists arena and battlegrounds separately. Each keeps using the PvP settings until you give it its own.",
	["AUTOSPEC_TIP"]  = "The moment you enter, switches to the spec picked below; its talents and gear are the ones set here. In a group it never takes you out of the role the group gave you. Switching spec yourself afterwards is left alone.",
	["AUTO_TIP"]      = "Once when you enter a scenario and once when you change spec. What you change by hand afterwards is left alone: the HUD turns amber and a click on it applies again. Off: nothing switches until you click the HUD.",
	["EARLY_TIP"]     = "When a PvP match or a dungeon finder group pops, the HUD already shows what that scenario wants. Nothing is switched until you click it: you may still decline.",
	["DRYRUN_TIP"]    = "Says in chat what would be switched, and switches nothing.",
	["SWITCH_NOW_TIP"] = "Switches to the spec picked above and applies the talents and gear shown, right now. In combat it waits for combat to end.",
	["ENTER_TIP"]     = "Runs the check as if you had just entered the scenario.",
})

CK.AddLocale("zhTW", {
	-- window
	["Modules"]        = "模組",
	["Settings"]       = "設定",
	["General"]        = "一般",
	["Misc"]           = "雜項",
	["Enable"]         = "啟用",
	["MODULES_DESC"]   = "停用的模組不佔用記憶體。",
	["RELOAD_NOTE"]    = "重新載入介面後釋放記憶體。",
	["Reload UI"]      = "重新載入介面",
	["STATE_missing"]  = "未安裝",
	["STATE_stale"]    = "需重新載入介面",
	["STATE_waiting"]  = "戰鬥結束後生效",

	["MODDESC_Loadout"] = "依所在場景自動切換天賦與裝備，每個專精各自設定。",
	["MODDESC_Stats"]   = "在 HUD 上顯示你的屬性數值。",
	["MODDESC_Range"]   = "與目標、焦點、滑鼠指向單位的距離。",
	["FEATDESC_RightClick"]  = "關閉戰鬥中右鍵互動選取目標，避免轉視角時切換目標，離開戰鬥恢復。",
	["FEATDESC_CombatAlert"] = "進入與脫離戰鬥時顯示一段文字。",

	["Language"]       = "語言",
	["Window scale"]   = "視窗縮放",
	["Show the HUD"]   = "顯示 HUD",
	["Scale"]          = "縮放",
	["Background opacity"] = "背景透明度",
	["Show the border"] = "顯示邊框",
	["Font"]           = "字型",
	["Game default"]   = "遊戲預設",
	["Position"]       = "位置",
	["Lock"]           = "鎖定",
	["Reset position"] = "重設位置",

	-- loadout pages
	["SCN_DESC_world"]   = "副本外，包含劇情事件。",
	["SCN_DESC_dungeon"] = "所有難度。",
	["SCN_DESC_raid"]    = "所有難度，包含世界首領巢穴。",
	["SCN_DESC_arena"]   = "練習賽、2v2、3v3、單人亂鬥。",
	["SCN_DESC_bg"]      = "隨機、史詩、積分戰場、戰場閃擊戰。",
	["LIST_SEP"]         = "、",

	["STATS_DESC"]      = "勾選要顯示的屬性，用箭頭調整順序。",
	["Decimals"]        = "小數位數",
	["English on the HUD"] = "HUD 顯示英文",

	-- range page
	["Show"]                        = "顯示",
	["Hide when 5 yards or closer"] = "5 碼以內不顯示",
	["Font size"]                   = "字型大小",
	["Font outline"]                = "字型外框",
	["Outline: none"]               = "無",
	["Outline: thin"]               = "細外框",
	["Outline: thick"]              = "粗外框",
	["Update every"]                = "更新間隔",
	["Mouseover offset"]            = "滑鼠指向偏移",
	["Unlock"]                      = "解鎖",

	-- combat alert page
	["Text on entering"]   = "進入戰鬥的文字",
	["Text on leaving"]    = "脫離戰鬥的文字",
	["Test"]               = "測試",

	["PAGE_debug"]      = "除錯",
	["PAGE_DESC_debug"] = "模擬其他場景來測試設定。不會儲存，重新載入介面後還原。",

	["SPLIT_TIP_pve"] = "把開放世界、探究、地城/M+、Raid 分開列出。每一項在你給它自己的設定之前，仍然使用 PvE 的設定。",
	["SPLIT_TIP_pvp"] = "把 Arena 與戰場/積分戰場分開列出。每一項在你給它自己的設定之前，仍然使用 PvP 的設定。",
	["AUTOSPEC_TIP"]  = "進入的當下切到下面選中的專精，並套用這裡替它設定的天賦與裝備。在隊伍中時，不會把你切離隊伍指派給你的職責。之後你自己換專精不會被改回。",
	["AUTO_TIP"]      = "進入場景時一次、換專精時一次。之後你手動改的不會被改回：HUD 變成琥珀色，點一下 HUD 就再套用。關閉後，只有點 HUD 才會切換。",
	["EARLY_TIP"]     = "PvP 或地城搜尋器排到時，HUD 先顯示那個場景要的配置。點了才會切換：你可能還會拒絕。",
	["DRYRUN_TIP"]    = "只在聊天視窗說明會切換什麼，實際上什麼都不切。",
	["SWITCH_NOW_TIP"] = "現在就切到上面選的專精，並套用顯示的天賦與裝備。戰鬥中會等脫離戰鬥。",
	["ENTER_TIP"]     = "當作你剛進入這個場景，重新檢查一次。",

	["Options"]                  = "選項",
	["Split into scenarios"]     = "細分場景",
	["own"]                      = "自訂",
	["Use the %s settings"]      = "沿用 %s 設定",
	["Switch spec automatically"] = "自動切專精",
	["On entering: %s"]          = "進入時切到：%s",
	["auto"]                     = "自動",
	["Talent loadout"]           = "天賦配置",
	["Equipment set"]            = "裝備套裝",
	["Switch now"]               = "立即切換",
	["Not set"]                  = "不設定",
	["Open world with War Mode uses PvP"]      = "戰爭模式開啟時，開放世界使用 PvP 設定",
	["Switch talents and gear automatically"]  = "自動切換天賦與裝備",
	["Show the next scenario on a queue pop"]  = "排隊就緒時，預先顯示該場景的配置",
	["On the HUD only when something differs"] = "僅在配置不符時顯示",

	-- debug page
	["Off"]                      = "關閉",
	["Advanced"]                 = "進階",
	["Simulate scenario"]        = "模擬場景",
	["Simulate queue pop"]       = "模擬排隊就緒",
	["Simulate group role"]      = "模擬隊伍職責",
	["Simulate War Mode"]        = "模擬戰爭模式開啟",
	["Simulate a running key or match"] = "模擬鑰石／比賽進行中",
	["Dry run"]                  = "只模擬，不實際切換",
	["Debug messages in chat"]   = "在聊天視窗顯示除錯訊息",
	["Enter again"]              = "重新進入",
	["Reset all"]                = "全部重設",
})
