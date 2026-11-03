-- The Reminder module for a warlock in a group: the pet, Grimoire of Sacrifice,
-- the Soulstone on someone else, healthstones.

local T = dofile(HERE .. "/stubs.lua")
local check, eq, W, fire, flush = T.check, T.eq, T.W, T.fire, T.flush
T.captureChat()

local IMP, SACRIFICE, SACRIFICED, SOULSTONE, CREATE = 688, 108503, 196099, 20707, 6201
W.units.player = { class = "WARLOCK" }
W.specs = { { 265, "Affliction" }, { 266, "Demonology" }, { 267, "Destruction" } }
W.known = { [IMP] = true, [SOULSTONE] = true, [CREATE] = true }
W.inInstance, W.instanceType, W.difficultyID = true, "party", 23

-- saved by the first version: its default size and place
CombatKitReminderDB = { size = 36, sound = "", point = "CENTER", relPoint = "CENTER", x = 0, y = 140,
	used = { [266] = { flask = 1235111 } } }   -- kept per spec, before PvE and PvP were told apart

local CK = T.boot()
CK.SetModuleEnabled("Reminder", true)
local RM = CK.modules.Reminder
local L = CK.L
eq(RM.db.size, 54, "a save with the first default size takes the new one")
check(RM.db.relPoint == "TOP" and RM.db.y == -80, "and the first default place the new one")
eq(RM.db.used["266/pve"] and RM.db.used["266/pve"].flask, 1235111, "what was kept per spec is now PvE's")
eq(RM.db.used[266], nil, "and no longer under the spec alone")
eq(RM.db.version, 4, "and is marked as done")
RM.db.consumables = { flask = false, food = false, rune = false, oil = false, healthstone = true }
fire("PLAYER_ENTERING_WORLD")

local function shown()
	local frame, icons, buttons = RM.GetDisplay()
	local list = {}
	if not frame or not frame:IsShown() then return list end
	for i, b in ipairs(icons) do
		if b:IsShown() then
			list[#list + 1] = { label = b.label:GetText(), text = b.text:GetText(), button = buttons[i] }
		end
	end
	return list
end
local function find(label)
	for _, r in ipairs(shown()) do if r.label == label then return r end end
end
local PET, STONE = "spell" .. IMP, "spell" .. SOULSTONE

-- ---------------------------------------------------------------- solo
check(find(PET), "no demon out: Summon Imp")
check(not find(STONE), "solo: no Soulstone to put on anyone")
local hs = find(L["Healthstone"])
check(hs, "no healthstone in the bags: make one")
eq(hs and hs.button and hs.button:GetAttribute("spell"), CREATE, "a click casts Create Healthstone")
W.bags = { [5512] = 1 }
fire("BAG_UPDATE_DELAYED")
check(not find(L["Healthstone"]), "one in the bags: fine")
W.units.pet = {}
fire("UNIT_PET", "player")
check(not find(PET), "the imp is out")

-- ---------------------------------------------------------------- in a group: the Soulstone
W.groupSize = 3
W.units.party1 = { class = "PRIEST" }
W.units.party2 = { class = "WARRIOR" }
fire("GROUP_ROSTER_UPDATE")
check(find(STONE), "grouped: the Soulstone on someone")
W.unitAuras = { party1 = { [SOULSTONE] = { sourceUnit = "party2", expirationTime = W.now + 900 } } }
fire("UNIT_AURA", "party1")
check(find(STONE), "someone else's Soulstone does not count")
W.unitAuras.party1[SOULSTONE].sourceUnit = "player"
fire("UNIT_AURA", "party1")
check(not find(STONE), "yours on the priest: fine")
W.unitAuras.party1[SOULSTONE].expirationTime = W.now + 200
fire("UNIT_AURA", "party1")
eq(find(STONE) and find(STONE).text, "4m", "running out: back, with the time")
W.unitAuras.party1 = nil
W.units.party2.far = true
fire("UNIT_AURA", "party1")
check(not find(STONE), "someone out of sight may have it: no reminder")
W.units.party2.far = nil
W.cooldowns = { [SOULSTONE] = { W.now, 600 } }
fire("GROUP_ROSTER_UPDATE")
check(not find(STONE), "cooling down after use: left alone")
W.now = W.now + 601
W.cooldowns = nil
T.runLongTimers()
check(find(STONE), "looked at again the moment it is back")
W.playerAuras = { [SOULSTONE] = { sourceUnit = "player", expirationTime = W.now + 900 } }
fire("UNIT_AURA", "player")
check(not find(STONE), "on yourself counts")
W.playerAuras = nil
fire("UNIT_AURA", "player")
RM.SetClassItem("soulstone", false)
check(not find(STONE), "the Soulstone reminder switched off")
RM.SetClassItem("soulstone", true)
check(find(STONE), "and on again")

-- ---------------------------------------------------------------- Grimoire of Sacrifice
W.known[SACRIFICE] = true
W.units.pet = nil
fire("SPELLS_CHANGED")
check(not find(PET), "with Grimoire of Sacrifice no demon is wanted")
check(find("spell" .. SACRIFICE), "but its buff is")
W.playerAuras = { [SACRIFICED] = { expirationTime = 0 } }
fire("UNIT_AURA", "player")
check(not find("spell" .. SACRIFICE), "sacrificed: fine")

-- ---------------------------------------------------------------- healthstones for everyone else
W.known[CREATE] = nil
W.bags = {}
fire("BAG_UPDATE_DELAYED")
check(not find(L["Healthstone"]), "no warlock who makes them in the group: nothing to take")
W.units.party2.class = "WARLOCK"
fire("GROUP_ROSTER_UPDATE")
hs = find(L["Healthstone"])
check(hs, "a warlock in the group: take one")
check(not (hs and hs.button and hs.button:IsShown()), "nothing to click: it is in the Soulwell")

-- ---------------------------------------------------------------- Demonology: a Felguard
W.known[SACRIFICE], W.known[30146] = nil, true
W.playerAuras = nil
W.specIndex = 2
W.units.pet = { guid = "Pet-0-3299-0-12-416-0000ABCDEF" }   -- an imp
fire("PLAYER_SPECIALIZATION_CHANGED", "player")
check(find("spell30146"), "an imp out as Demonology with Summon Felguard: Summon Felguard, in red")
W.units.pet.guid = "Pet-0-3299-0-12-17252-0000ABCDEF"
fire("UNIT_PET", "player")
check(not find("spell30146"), "a Felguard out: fine")
W.units.pet.guid = "Pet-0-3299-0-12-416-0000ABCDEF"
W.instanceType = "arena"
RM.db.where.arena = true
fire("PLAYER_ENTERING_WORLD")
check(not find("spell30146"), "an imp as Demonology in an arena: fine, PvP brings whichever demon")
W.instanceType = "party"
fire("PLAYER_ENTERING_WORLD")
W.specIndex = 1
fire("PLAYER_SPECIALIZATION_CHANGED", "player")
check(not find("spell30146"), "an imp as Affliction: fine")

T.releaseChat()
return T.report("reminder group [" .. (LOCALE or "enUS") .. "]")
