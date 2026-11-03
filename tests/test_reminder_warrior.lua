-- The Reminder module for a warrior: a stance read off the stance bar, the
-- Defensive Stance warning, spells known through the newer spell book API.

local T = dofile(HERE .. "/stubs.lua")
local check, eq, W, fire = T.check, T.eq, T.W, T.fire
T.captureChat()

local BATTLE, DEFENSIVE, SHOUT = 386164, 386208, 6673
W.units.player = { class = "WARRIOR" }
W.specs = { { 71, "Arms" }, { 72, "Fury" }, { 73, "Protection" } }
W.known = { [BATTLE] = true, [DEFENSIVE] = true, [SHOUT] = true }
W.playerAuras = { [SHOUT] = { expirationTime = W.now + 3000 } }
W.inInstance, W.instanceType, W.difficultyID = true, "party", 2
IsPlayerSpell = nil   -- gone with 12.1's fallback setting off: the spell book API answers

local CK = T.boot()
CK.SetModuleEnabled("Reminder", true)
local RM = CK.modules.Reminder
RM.db.consumables = { flask = false, food = false, rune = false, oil = false, healthstone = false }
fire("PLAYER_ENTERING_WORLD")

local function find(label)
	local frame, icons = RM.GetDisplay()
	if not frame or not frame:IsShown() then return nil end
	for _, b in ipairs(icons) do
		if b:IsShown() and b.label:GetText() == label then return b end
	end
end
local STANCE, LEAVE = "spell" .. BATTLE, "spell" .. DEFENSIVE

check(find(STANCE), "no stance: Battle Stance, known through the spell book API")
W.form, W.formSpell = 1, BATTLE
fire("UPDATE_SHAPESHIFT_FORM")
check(not find(STANCE), "in Battle Stance by the stance bar, though no aura says so: fine")
W.form, W.formSpell = 2, DEFENSIVE
fire("UPDATE_SHAPESHIFT_FORM")
check(not find(STANCE) and find(LEAVE), "Defensive Stance on Arms: a stance, but one to leave")
W.inGroup, W.role = true, "TANK"
fire("GROUP_ROSTER_UPDATE")
check(not find(LEAVE), "tanking: no warning")
W.inGroup, W.role = nil, nil
W.specIndex = 3
fire("PLAYER_SPECIALIZATION_CHANGED", "player")
check(not find(LEAVE), "Protection: no warning")

T.releaseChat()
return T.report("reminder warrior [" .. (LOCALE or "enUS") .. "]")
