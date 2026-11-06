-- The Reminder module for a Retribution paladin: the Rites are Lightsmith's (Holy and
-- Protection), so a Retribution paladin knows neither; the class page still names them.

local T = dofile(HERE .. "/stubs.lua")
local check, eq, W, fire = T.check, T.eq, T.W, T.fire
T.captureChat()

local DEVOTION, SANCTIFICATION = 465, 433568
W.units.player = { class = "PALADIN" }
W.specs = { { 65, "Holy" }, { 66, "Protection" }, { 70, "Retribution" } }
W.specIndex = 3
W.known = { [DEVOTION] = true }
W.playerAuras = { [DEVOTION] = { expirationTime = 0 } }
W.equip = { [16] = 1001 }
W.itemInfo = { [1001] = { 2, "INVTYPE_2HWEAPON" } }
local CK = T.boot()
CK.SetModuleEnabled("Reminder", true)
local RM = CK.modules.Reminder
fire("PLAYER_ENTERING_WORLD")

local function items()
	local ok, list = pcall(RM.ClassItems)
	check(ok, "the class page's items: " .. tostring(not ok and list or "ok"))
	local by = {}
	for _, item in ipairs(ok and list or {}) do by[item.key] = item end
	return by
end

local by = items()
check(by.rite and not by.rite.now, "no Rite known: on the page, not in use")
eq(by.rite and by.rite.label, "spell" .. SANCTIFICATION, "no Rite known: named after the first")
eq(by.rite and by.rite.icon, "icon" .. SANCTIFICATION, "no Rite known: its icon")
check(by.aura and by.aura.now, "Devotion Aura known: in use")

-- a paladin who knows no aura yet (a new character): still named, not in use
W.known = {}
fire("SPELLS_CHANGED")
by = items()
check(by.aura and not by.aura.now and by.aura.label == "spell" .. DEVOTION, "no aura known: named after the first, not in use")

-- ---------------------------------------------------------------- Holy: the beacons
local LIGHT, FAITH = 53563, 156910
W.specIndex = 1
W.known = { [DEVOTION] = true, [LIGHT] = true, [FAITH] = true }
W.inInstance, W.instanceType = true, "scenario"
fire("PLAYER_SPECIALIZATION_CHANGED", "player")
local function shown(label)
	local frame, icons = RM.GetDisplay()
	if not frame or not frame:IsShown() then return false end
	for _, b in ipairs(icons) do
		if b:IsShown() and b.label:GetText() == label then return true end
	end
	return false
end
check(not shown("spell" .. FAITH) and not shown("spell" .. LIGHT), "solo: no beacons")
-- a delve with a follower: you and one other
W.groupSize = 2
W.units.party1 = { class = "ROGUE" }
fire("GROUP_ROSTER_UPDATE")
check(shown("spell" .. LIGHT), "one other: Beacon of Light on them")
check(not shown("spell" .. FAITH), "one other: no second target for Beacon of Faith")
W.unitAuras = { party1 = { [LIGHT] = { sourceUnit = "player", expirationTime = 0 } } }
fire("UNIT_AURA", "party1")
check(not shown("spell" .. LIGHT), "Light on them: fine")
-- a dungeon group
W.groupSize = 3
W.units.party2 = { class = "WARRIOR" }
fire("GROUP_ROSTER_UPDATE")
check(shown("spell" .. FAITH), "two others: Beacon of Faith wanted")
W.playerAuras[FAITH] = { sourceUnit = "player", expirationTime = 0 }
fire("UNIT_AURA", "player")
check(not shown("spell" .. FAITH), "Faith on yourself counts")

T.releaseChat()
return T.report("reminder paladin [" .. (LOCALE or "enUS") .. "]")
