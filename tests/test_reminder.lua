-- The Reminder module: what shows when, the class list, the group's feasts and cauldrons, its pages.

local T = dofile(HERE .. "/stubs.lua")
local check, eq, W, fire, flush = T.check, T.eq, T.W, T.fire, T.flush
T.captureChat()

-- a Frost mage with a two-handed weapon, in the open world
W.units.player = { class = "MAGE" }
W.specs = { { 62, "Arcane" }, { 63, "Fire" }, { 64, "Frost" } }
W.specIndex = 3
W.known = { [1459] = true, [31687] = true }
W.equip = { [16] = 1001 }
W.itemInfo = { [1001] = { 2, "INVTYPE_2HWEAPON" }, [1002] = { 4, "INVTYPE_SHIELD" } }

local CK = T.boot()
check(T.loaded.CombatKit_Reminder == nil, "off by default: never loaded")
CK.SetModuleEnabled("Reminder", true)
flush()
local RM = CK.modules.Reminder
local L = CK.L
check(RM and RM.enabled and RM.IsRunning(), "switched on: loaded and running")
eq(RM.classes, nil, "the class lists are dropped once the player's is made")
check(RM.db.where.dungeon and RM.db.where.raid and not RM.db.where.world, "dungeons and raids by default")

local function shown()
	local frame, icons = RM.GetDisplay()
	local list = {}
	if not frame or not frame:IsShown() then return list end
	for _, b in ipairs(icons) do
		if b:IsShown() then list[#list + 1] = { label = b.label:GetText(), text = b.text:GetText(), icon = b.icon:GetTexture() } end
	end
	return list
end
local function find(label)
	for _, r in ipairs(shown()) do if r.label == label then return r end end
end
local AI, ELEMENTAL = "spell1459", "spell31687"

-- ---------------------------------------------------------------- where and when
eq(#shown(), 0, "open world: nothing")
W.inInstance, W.instanceType, W.difficultyID = true, "party", 0
fire("PLAYER_ENTERING_WORLD")
eq(#shown(), 0, "a hub city reads as a dungeon of difficulty 0: nothing")
W.difficultyID = 2
fire("PLAYER_ENTERING_WORLD")
check(find(L["Flask"]) and find(L["Food"]) and find(L["Weapon oil"]), "a dungeon: flask, food, weapon oil")
check(find(AI) and find(ELEMENTAL), "the group buff and the Water Elemental")
check(not find(L["Augment rune"]), "no augment rune in the bags: not reminded")
check(not find(L["Off-hand oil"]), "no off hand: no off-hand oil")
eq(find(L["Flask"]).icon, "itemicon" .. RM.FLASK.items[1], "no flask in the bags: the first flask's icon")
W.bags = { [245931] = 2, [259085] = 1 }
fire("BAG_UPDATE_DELAYED")
eq(find(L["Flask"]).icon, "itemicon245931", "the icon of the flask in the bags")
check(find(L["Augment rune"]), "a rune in the bags: reminded")

-- ---------------------------------------------------------------- the consumables
W.playerAuras = { [1235111] = { expirationTime = W.now + 3000 } }
fire("UNIT_AURA", "player")
check(not find(L["Flask"]), "flasked: gone")
W.playerAuras[1235111].expirationTime = W.now + 230
fire("UNIT_AURA", "player")
eq(find(L["Flask"]) and find(L["Flask"]).text, "4m", "under five minutes left: back, with the time")
RM.db.expiring = 0; RM.Refresh()
check(not find(L["Flask"]), "running out switched off: only a missing one counts")
RM.db.expiring = 5
W.playerAuras[1235111].expirationTime = W.now + 1200
W.difficultyID = 23
RM.Refresh()
eq(find(L["Flask"]) and find(L["Flask"]).text, "20m", "a Mythic entrance: a flask that would not last a key is topped up now")
W.difficultyID = 2
RM.Refresh()
check(not find(L["Flask"]), "a heroic dungeon: twenty minutes are plenty")
W.playerAuras[1235111].expirationTime = W.now + 3000
RM.Refresh()

W.buffList = { { icon = 135000, expirationTime = 0 }, { icon = 136000, expirationTime = W.now + 3000 } }
fire("UNIT_AURA", "player")
check(not find(L["Food"]), "a buff with the food icon: fed")
W.playerAuras[1264426] = { expirationTime = W.now + 3000 }
fire("UNIT_AURA", "player")
check(not find(L["Augment rune"]), "the rune's buff: gone")

W.tempEnchant = { [16] = { 8052, 3000000 } }
fire("UNIT_INVENTORY_CHANGED", "player")
check(not find(L["Weapon oil"]), "oiled: gone")
local paperdoll = C_PaperDollInfo
C_PaperDollInfo = nil
fire("UNIT_INVENTORY_CHANGED", "player")
check(not find(L["Weapon oil"]), "without the newer enchant API the old one is asked")
W.tempEnchant = nil
fire("UNIT_INVENTORY_CHANGED", "player")
check(find(L["Weapon oil"]), "and tells a weapon without oil too")
C_PaperDollInfo = paperdoll
W.bags[237369] = 1
fire("BAG_UPDATE_DELAYED")
eq(find(L["Weapon oil"]).icon, "itemicon243734", "a weightstone in the bags does not go on a sword: not its icon")
W.itemInfo[1001][3] = 5
fire("PLAYER_EQUIPMENT_CHANGED")
eq(find(L["Weapon oil"]).icon, "itemicon237369", "on a mace it does")
W.itemInfo[1001][3] = nil
W.bags[237369] = nil
W.itemInfo[1003] = { 2, "INVTYPE_RANGED", 2 }
W.equip[16] = 1003
fire("PLAYER_EQUIPMENT_CHANGED")
check(find(L["Weapon oil"]), "a bow takes oil or ammunition too")
W.equip[16] = 1001
W.tempEnchant = { [16] = { 8052, 3000000 } }
fire("UNIT_INVENTORY_CHANGED", "player")
W.equip[17] = 1002
fire("PLAYER_EQUIPMENT_CHANGED")
check(not find(L["Off-hand oil"]), "a shield takes no oil")
W.equip[17] = 1001
fire("PLAYER_EQUIPMENT_CHANGED")
check(find(L["Off-hand oil"]), "an off-hand weapon does")
W.equip[17] = nil

-- ---------------------------------------------------------------- the class
W.units.pet = {}
fire("UNIT_PET", "player")
check(not find(ELEMENTAL), "the elemental is out")
W.specIndex = 1
W.units.pet = nil
fire("PLAYER_SPECIALIZATION_CHANGED", "player")
check(not find(ELEMENTAL), "Arcane: no elemental wanted")
W.specIndex = 3
W.units.pet = {}
W.playerAuras[1459] = { expirationTime = W.now + 3000 }
fire("UNIT_AURA", "player")
check(not find(AI), "solo with Arcane Intellect: fine")
W.groupSize = 3
W.units.party1, W.units.party2 = {}, {}
W.unitAuras = { party1 = { [1459] = { expirationTime = W.now + 3000 } } }
fire("GROUP_ROSTER_UPDATE")
eq(find(AI) and find(AI).text, "1", "one of three lacks it: the icon says 1")
W.units.party2.far = true
fire("UNIT_AURA", "party2")
check(not find(AI), "out of reach: not counted")
W.units.party2.far = nil
RM.SetClassItem("intellect", false)
check(not find(AI), "the group buff switched off on its own")
RM.SetClassItem("intellect", true)
W.unitAuras.party2 = { [1459] = { expirationTime = W.now + 3000 } }
RM.Refresh()
eq(#shown(), 0, "everything in place: no row")

-- ---------------------------------------------------------------- combat, the visit, a ready check
W.playerAuras[1235111] = nil
W.units.pet = nil
W.combat = true
fire("PLAYER_REGEN_DISABLED")
eq(#shown(), 0, "in combat: nothing")
W.combat = false
fire("PLAYER_REGEN_ENABLED")
check(not find(L["Flask"]), "after the first combat: consumables keep quiet")
check(find(ELEMENTAL), "class reminders still show")
fire("READY_CHECK")
check(find(L["Flask"]), "a ready check brings them back")
fire("READY_CHECK_FINISHED")
check(not find(L["Flask"]), "and takes them away when it ends")
W.instanceType, W.difficultyID = "raid", 14
fire("ZONE_CHANGED_NEW_AREA")
check(find(L["Flask"]), "a raid: after a pull the consumables show again")
RM.db.raidAgain = false; RM.Refresh()
check(not find(L["Flask"]), "unless that is switched off")
RM.db.raidAgain = true
W.instanceType, W.difficultyID = "party", 2
fire("ZONE_CHANGED_NEW_AREA")
fire("PLAYER_ENTERING_WORLD")
check(not find(L["Flask"]), "a loading screen into the same instance: still the same visit")
local realInfo = GetInstanceInfo
GetInstanceInfo = function() return "Elsewhere", W.instanceType, W.difficultyID end
fire("PLAYER_ENTERING_WORLD")
check(find(L["Flask"]), "another instance: a new visit")
GetInstanceInfo = realInfo
W.aurasSecret = true
fire("UNIT_AURA", "player")
check(not find(L["Flask"]) and find(ELEMENTAL), "auras hidden: a missing flask cannot be told; the pet (no aura) still can")
W.secretSpells = {}
fire("UNIT_AURA", "player")
check(find(L["Flask"]), "asked spell by spell, the flask's aura is not hidden: judged after all")
W.secretSpells, W.aurasSecret = nil, nil
W.buffScanError = true
local foodBuff = W.buffList[2]
W.buffList[2] = nil
fire("UNIT_AURA", "player")
check(find(L["Food"]), "the buffs cannot be looked through, no Well Fed by ID: food missing")
W.playerAuras[1219182] = { expirationTime = W.now + 3000 }
fire("UNIT_AURA", "player")
check(not find(L["Food"]), "a Well Fed asked for by ID: fed")
W.playerAuras[1219182] = nil
W.playerAuras[1219187] = { expirationTime = W.now + 10 }
fire("UNIT_AURA", "player")
check(not find(L["Food"]), "eating: no reminder meanwhile")
W.playerAuras[1219187] = nil
W.buffScanError = nil
W.buffList[2] = foodBuff
W.units.player.dead = true
fire("PLAYER_DEAD")
eq(#shown(), 0, "dead: nothing")
W.units.player.dead = nil
fire("PLAYER_ALIVE")
W.resting = true
fire("PLAYER_UPDATE_RESTING")
eq(#shown(), 0, "in a resting area: nothing")
W.resting = nil
fire("PLAYER_UPDATE_RESTING")
check(#shown() > 0, "out of the resting area: back")
fire("ENCOUNTER_START", 2900, "Boss", 16, 20)
eq(#shown(), 0, "a boss pull: hidden at once, before combat")
fire("ENCOUNTER_END", 2900, "Boss", 16, 20, 1)
check(#shown() > 0, "the encounter over: back")
W.flying = true
fire("PLAYER_UPDATE_RESTING")
eq(#shown(), 0, "flying: nothing")
W.flying = nil
W.units.pet = {}
W.playerAuras[1235111] = { expirationTime = W.now + 3000 }
fire("PLAYER_UPDATE_RESTING")
eq(#shown(), 0, "all set again")

-- ---------------------------------------------------------------- what the group puts down
fire("CHAT_MSG_EMOTE", "Someone prepares a |cffffffff|Hitem:242744::::::::90:::::|h[Hearty Quel'dorei Medley]|h|r!")
local feast = find(L["Feast"])
check(feast and feast.icon == "itemicon242744" and feast.text == "3:00", "a feast link in chat: the feast, counting down")
W.buffList[2].expirationTime = W.now + 100
fire("UNIT_AURA", "player")
check(find(L["Feast"]) and not find(L["Food"]), "your own food runs out: its reminder steps aside while the feast is down")
W.buffList[2].expirationTime = W.now + 3590
fire("UNIT_AURA", "player")
check(not find(L["Feast"]) and not find(L["Food"]), "eaten from it (a fresh Well Fed): gone")
W.now = W.now + 181
T.runLongTimers()
check(not find(L["Feast"]), "three minutes later it is gone anyway")
W.itemNames = { [242272] = "Quel'dorei Medley", [242744] = "Hearty Quel'dorei Medley" }
W.buffList[2].expirationTime = W.now + 3000
fire("CHAT_MSG_SYSTEM", "Someone prepares a Hearty Quel'dorei Medley.")
eq(find(L["Feast"]) and find(L["Feast"]).icon, "itemicon242744", "named without a link: the longest name that fits")
W.combat = true
fire("PLAYER_REGEN_DISABLED")
W.now = W.now + 181
T.runLongTimers()
fire("CHAT_MSG_EMOTE", "Someone prepares a Quel'dorei Medley.")
W.combat = false
fire("PLAYER_REGEN_ENABLED")
check(not find(L["Feast"]), "a feast line in combat is not read")
RM.SetShared("feast", false)
fire("CHAT_MSG_EMOTE", "Someone prepares a Quel'dorei Medley.")
check(not find(L["Feast"]), "the feast alert switched off")
RM.SetShared("feast", true)
check(not find(L["Feast"]), "and one put down meanwhile is not kept for later")

W.bags[245931] = nil
fire("UNIT_SPELLCAST_SUCCEEDED", "nameplate3", "Cast-1", 1240195)
fire("UNIT_SPELLCAST_SUCCEEDED", "party1", "Cast-2", T.SECRET)
check(not find(L["Flask cauldron"]), "a cast outside the group, or one the game keeps secret: nothing")
fire("UNIT_SPELLCAST_SUCCEEDED", "party1", "Cast-3", 1240195)
local cauldron = find(L["Flask cauldron"])
check(cauldron and cauldron.icon == "itemicon241318" and cauldron.text == "5:00", "a group member casts the cauldron: shown, five minutes")
W.playerAuras[1235111] = nil
fire("UNIT_AURA", "player")
check(not find(L["Flask"]), "your own flask reminder steps aside meanwhile")
W.bags[245929] = 1
fire("BAG_UPDATE_DELAYED")
check(not find(L["Flask cauldron"]), "a flask taken from it: the cauldron goes")
check(not find(L["Flask"]), "and after this dungeon's first pull your own flask keeps quiet")
fire("READY_CHECK")
check(find(L["Flask"]), "until a ready check: the flask still to drink")
fire("READY_CHECK_FINISHED")
W.bags[245929] = nil
W.bags[245931] = 2
W.playerAuras[1235111] = { expirationTime = W.now + 3000 }
W.now = W.now + 301
T.runLongTimers()
eq(#shown(), 0, "all gone again")

-- ---------------------------------------------------------------- the class lists themselves
local fake = { classes = {} }
function fake.Known(id) return W.known[id] or false end
function fake.FirstKnown(ids) for _, id in ipairs(ids) do if fake.Known(id) then return id end end end
for _, file in ipairs({ "Rogue", "Shaman", "Warrior", "Warlock", "Hunter", "DeathKnight", "Druid", "Paladin", "Priest", "Evoker", "Mage" }) do
	local chunk = assert(loadfile(ROOT .. "/Modules/Reminder/Classes/" .. file .. ".lua"))
	chunk("CombatKit_Reminder", fake)
end
local classes = 0
for _ in pairs(fake.classes) do classes = classes + 1 end
eq(classes, 11, "eleven classes have a list")
W.known = { [2823] = true, [315584] = true, [3408] = true }
local rogue = fake.classes.ROGUE()
eq(rogue[1].need(), 1, "one lethal poison")
eq(rogue[1].spell(), 2823, "Deadly Poison's icon when it is known")
W.known[381801] = true
eq(rogue[1].need(), 2, "Dragon-Tempered Blades: two lethal poisons")
eq(rogue[2].need(), 1, "but never more than are known")
W.known = { [192106] = true }
local shaman = fake.classes.SHAMAN()
eq(#shaman[2].auras(), 4, "without Elemental Orbit, Earth Shield on yourself counts as the shield")
W.known[383010] = true
eq(#shaman[2].auras(), 2, "with it, only Lightning or Water Shield")
W.known = { [1459] = true, [31687] = true }

-- ---------------------------------------------------------------- settings pages
SlashCmdList.COMBATKIT("")
local main = CK.Options.GetFrame()
main.tabs.Reminder:Click()
local body = main.bodies.Reminder
local function go(node)
	for _, row in ipairs(main.treeRows) do
		if row:IsShown() and row.section == "Reminder" and row.node == node then row:Click() end
	end
end
local page = body.pages.consumables
check(page:IsShown() and page.consumables.flask:GetChecked(), "the first page: the consumables")
W.playerAuras[1235111] = nil
W.combat = true
fire("PLAYER_REGEN_DISABLED")
W.combat = false
fire("PLAYER_REGEN_ENABLED")
check(not find(L["Flask"]), "after a pull in a dungeon: quiet")
W.instanceType, W.difficultyID = "raid", 14
RM.Refresh()
check(find(L["Flask"]), "in a raid: back")
page.raidAgain:Click()
eq(RM.db.raidAgain, false, "raids again: off")
check(not find(L["Flask"]), "then a raid keeps quiet too")
page.raidAgain:Click()
page.consumables.flask:Click()
check(not find(L["Flask"]), "the flask reminder switched off")
page.consumables.flask:Click()
page.shared.cauldron:Click()
eq(RM.db.shared.cauldron, false, "the cauldron alert switched off from the page")
page.shared.cauldron:Click()

go("where")
local where = body.pages.where
check(where:IsShown() and where.boxes.whereraid:GetChecked() and where.boxes.sharedWherebg:GetChecked()
	and not where.boxes.wherebg:GetChecked(), "where: raids for yours, battlegrounds for the group's only")
where.boxes.whereraid:Click()
eq(RM.db.where.raid, false, "unticked is saved as false, not as a missing key")
eq(#shown(), 0, "raids unticked: nothing")
where.boxes.whereraid:Click()

go("class")
local class = body.pages.class
local first = class.items[1]
check(class:IsShown() and first:IsShown() and first.key == "intellect", "your class: its reminders, the group buff first")
check(class.items[2]:IsShown() and not class.items[3]:IsShown(), "two for a mage")
W.playerAuras[1459] = nil
RM.Refresh()
check(find(AI), "Arcane Intellect missing")
first:Click()
eq(RM.db.off.intellect, true, "switched off on its own")
check(not find(AI), "gone")
first:Click()
eq(RM.db.off.intellect, nil, "on again")
W.playerAuras[1459] = { expirationTime = W.now + 3000 }
RM.Refresh()

body.test:Click()
check(RM.IsTesting() and #shown() == 4, "the test button: the sample row")
eq(body.test:GetText(), L["Stop test"], "the button now ends the test")
body.test:Click()
check(not RM.IsTesting() and find(L["Flask"]) and #shown() == 1, "test over: the real row again")
go("display")
check(body.pages.display:IsShown(), "the display page")
body.pages.display.unlock:Click()
check(not RM.IsLocked() and #shown() == 4, "unlocked: the sample row, to drag")
main:Hide()
check(RM.IsLocked() and not RM.IsTesting(), "closing the window locks it again")

-- ---------------------------------------------------------------- click to use
local function logged(entry) local n = 0 for _, l in ipairs(W.log) do if l == entry then n = n + 1 end end return n end
local _, _, buttons = RM.GetDisplay()
check(buttons[1] and buttons[1]:IsShown(), "a button over the flask")
eq(buttons[1]:GetAttribute("type"), "item", "it uses an item")
eq(buttons[1]:GetAttribute("item"), "item:245931", "the flask in the bags")
eq(W.drivers.visibility, "[combat] hide; show", "a state driver hides the buttons in combat")
W.tempEnchant = nil
W.bags[243734] = 1
fire("UNIT_INVENTORY_CHANGED", "player")
eq(find(L["Weapon oil"]) and buttons[2]:GetAttribute("item"), "item:243734", "the oil in the bags")
eq(buttons[2]:GetAttribute("target-slot"), 16, "on the main hand")
W.tempEnchant = { [16] = { 8052, 3000000 } }
W.playerAuras[1459] = nil
fire("UNIT_INVENTORY_CHANGED", "player")
local ai
for i, b in ipairs(buttons) do if b:IsShown() and b:GetAttribute("spell") == 1459 then ai = i end end
check(ai and buttons[ai]:GetAttribute("type") == "spell", "the group buff: a click casts it")
fire("PLAYER_REGEN_DISABLED")   -- as in the game: before combat lockdown starts
check(not buttons[1]:IsShown(), "combat starts: the buttons are put away")
fire("PLAYER_REGEN_ENABLED")
check(buttons[1]:IsShown(), "combat over: back")
RM.db.click = false; RM.Refresh()
check(not buttons[1]:IsShown(), "click to use switched off")
RM.db.click = true; RM.Refresh()

-- ---------------------------------------------------------------- the HUD and the sound
RM.db.hud = true; RM.Refresh()
local hud = CK.HUD.GetFrame()
local hudRows = hud and hud.sections.reminder and hud.sections.reminder.rows
check(hudRows and hudRows[1].value:GetText() == L["Flask"], "rows on the HUD")
RM.db.icons = false; RM.Refresh()
local frame = RM.GetDisplay()
check(not frame:IsShown() and hud.sections.reminder:IsShown(), "icons off: the HUD alone")
check(not buttons[1]:IsShown(), "no icons, nothing to click")
RM.db.icons = true; RM.db.hud = false; RM.Refresh()
check(not hud.sections.reminder:IsShown(), "HUD rows off")

RM.db.sound = "RAID_WARNING"
W.playerAuras[1235111] = { expirationTime = W.now + 3000 }
RM.Refresh()
W.now = W.now + 10
W.playerAuras[1235111] = nil
RM.Refresh()
eq(logged("sound:8959"), 1, "a reminder that appears: the sound")
W.now = W.now + 10
fire("PLAYER_REGEN_DISABLED")
fire("PLAYER_REGEN_ENABLED")
eq(logged("sound:8959"), 1, "the same one back after combat: no sound")
RM.db.sound = ""

-- ---------------------------------------------------------------- custom reminders
eq(RM.AddCustom("abc"), "No spell with that ID.", "not a number: refused")
eq(RM.AddCustom(77777, "missing", "me"), nil, "a custom reminder")
check(find("spell77777"), "it shows while the buff is missing")
eq(RM.AddCustom(77777, "missing", "me"), "Already in the list.", "twice: refused")
W.playerAuras[66666] = { expirationTime = 0 }
RM.AddCustom(66666, "present", "me")
check(find("spell66666"), "present on you: shown")
RM.db.hud = true; RM.Refresh()
local red
for _, r in ipairs(hud.sections.reminder.rows) do
	if r.value:IsShown() and (r.value:GetText() or ""):find("spell66666", 1, true) then red = r.value:GetText():find("^|c") end
end
check(red, "in red: something to undo")
RM.db.hud = false
RM.AddCustom(55555, "missing", "group")
eq(find("spell55555") and find("spell55555").text, "3", "on the group: everyone near lacks it")
SlashCmdList.COMBATKIT("")
main.tabs.Reminder:Click()
go("class")
local custom = body.pages.class
check(custom:IsShown() and custom.rows[3]:IsShown() and not custom.rows[4]:IsShown(), "the page lists the three")
custom.rows[1].remove:Click()
eq(#RM.CustomList(), 2, "one removed")
check(not find("spell77777"), "and gone from the row")
custom.id:SetText("44444")
custom.add:Click()
eq(#RM.CustomList(), 3, "one added from the page")
for id = 1, 7 do RM.AddCustom(1000 + id, "missing", "me") end
eq(RM.AddCustom(2000, "missing", "me"), "The list is full.", "ten per class at most")
RM.db.custom = {}
RM.Refresh()
main:Hide()

-- ---------------------------------------------------------------- /ckreminder
SlashCmdList.CKREMINDER("")
check(T.said("scenario raid") and T.said("temporary enchant on slot 16: 8052") and T.said("last feast or cauldron cast: by party1"),
	"/ckreminder says what the module sees, and how a feast or cauldron was seen")

-- ---------------------------------------------------------------- off
CK.SetModuleEnabled("Reminder", false)
eq(#shown(), 0, "off: nothing on screen")
check(not RM.IsRunning(), "not running")

T.releaseChat()
return T.report("reminder [" .. (LOCALE or "enUS") .. "]")
