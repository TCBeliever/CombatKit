-- The Reminder module for a death knight: any rune, but one your other spec
-- had, still on after a spec change, is shown in red.

local T = dofile(HERE .. "/stubs.lua")
local check, eq, W, fire = T.check, T.eq, T.W, T.fire
T.captureChat()

local RAZORICE, APOCALYPSE = 3370, 6245
W.units.player = { class = "DEATHKNIGHT" }
W.specs = { { 250, "Blood" }, { 251, "Frost" }, { 252, "Unholy" } }
W.specIndex = 2
W.known = {}
W.equip = { [16] = 1001 }
W.itemInfo = { [1001] = { 2, "INVTYPE_2HWEAPON", 8 } }
W.permEnchant = { [16] = RAZORICE }
W.inInstance, W.instanceType, W.difficultyID = true, "party", 2
local CK = T.boot()
CK.SetModuleEnabled("Reminder", true)
local RM = CK.modules.Reminder
local L = CK.L
RM.db.consumables = { flask = false, food = false, rune = false, oil = true, healthstone = false }
fire("PLAYER_ENTERING_WORLD")
local function find(label)
	local frame, icons, buttons = RM.GetDisplay()
	if not frame or not frame:IsShown() then return nil end
	for i, b in ipairs(icons) do
		if b:IsShown() and b.label:GetText() == label then
			return { text = b.text:GetText(), icon = b.icon:GetTexture(), button = buttons[i] }
		end
	end
end

local function spec(i) W.specIndex = i; fire("PLAYER_SPECIALIZATION_CHANGED", "player") end

local OTHER = L["Rune of another setup"]
check(not find(L["Runeforge"]) and not find(OTHER), "Frost with Razorice: fine")
eq(RM.db.used["251/pve"].rune16, RAZORICE, "remembered for Frost in PvE")
spec(3)
check(not find(OTHER), "Unholy, never seen before: no judgement yet")
W.permEnchant[16] = APOCALYPSE
fire("PLAYER_EQUIPMENT_CHANGED")
eq(RM.db.used["252/pve"].rune16, APOCALYPSE, "Unholy runeforged: Apocalypse remembered")
spec(2)
check(find(OTHER), "back to Frost, Apocalypse still on: Unholy's rune, in red")
W.permEnchant[16] = RAZORICE
fire("PLAYER_EQUIPMENT_CHANGED")
check(not find(OTHER), "runeforged again: fine")

-- PvP is a setup of its own: the same spec may bring another rune there
W.instanceType = "arena"
RM.db.consumablesWhere.arena = true   -- ticked, and still no weapon oil there
W.permEnchant[16] = APOCALYPSE
fire("PLAYER_ENTERING_WORLD")
check(not find(OTHER), "Frost in an arena, first time: Apocalypse learned for PvP")
check(not find(L["Weapon oil"]), "no weapon oil reminder in an arena: consumables are for PvE")
eq(RM.db.used["251/pvp"].rune16, APOCALYPSE, "kept apart from PvE")
W.instanceType = "party"
fire("PLAYER_ENTERING_WORLD")
check(find(OTHER), "a dungeon with the PvP rune still on: in red")
W.permEnchant[16] = RAZORICE
fire("PLAYER_EQUIPMENT_CHANGED")
W.permEnchant[16] = 0
fire("PLAYER_EQUIPMENT_CHANGED")
check(find(L["Runeforge"]) == nil and find("spell53343"), "Frost, two-hander, no rune: the rune of last time named (Razorice)")

-- a new character's view: nothing remembered, the guides decide
RM.db.used = {}
fire("PLAYER_EQUIPMENT_CHANGED")
check(find("spell53344"), "Frost two-hander, nothing remembered: the guides' Fallen Crusader")
W.equip[17] = 1002
W.itemInfo[1002] = { 2, "INVTYPE_WEAPON", 7 }
W.itemInfo[1001] = { 2, "INVTYPE_WEAPON", 7 }
W.permEnchant[17] = 0
fire("PLAYER_EQUIPMENT_CHANGED")
check(find("spell62158") and find("spell53344"), "two weapons: Stoneskin Gargoyle and Fallen Crusader")
W.permEnchant[16] = 3368
fire("PLAYER_EQUIPMENT_CHANGED")
check(find("spell62158") and not find("spell53344"), "Fallen Crusader on the main hand: the off hand gets Stoneskin")
W.known[207057] = true
W.permEnchant[16] = 0
fire("PLAYER_EQUIPMENT_CHANGED")
RM.db.used = {}
fire("PLAYER_EQUIPMENT_CHANGED")
check(find("spell53343"), "with Shattering Blade: Razorice")
W.known[207057], W.known[455993] = nil, true
RM.db.used = {}
fire("PLAYER_EQUIPMENT_CHANGED")
check(find("spell53343") and find("spell53344"), "with Frostbane instead: Razorice and Fallen Crusader too")

-- a two-hander: Fallen Crusader, Frostbane or not
W.equip[17] = nil
W.itemInfo[1001] = { 2, "INVTYPE_2HWEAPON", 8 }
RM.db.used = {}
fire("PLAYER_EQUIPMENT_CHANGED")
check(find("spell53344") and not find("spell53343"), "a two-hander with Frostbane: Fallen Crusader")
W.known[455993] = nil
spec(3)
RM.db.used = {}
fire("PLAYER_EQUIPMENT_CHANGED")
check(find("spell327082"), "Unholy: Apocalypse")

T.releaseChat()
return T.report("reminder dk [" .. (LOCALE or "enUS") .. "]")
