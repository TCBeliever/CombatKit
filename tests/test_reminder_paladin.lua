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

T.releaseChat()
return T.report("reminder paladin [" .. (LOCALE or "enUS") .. "]")
