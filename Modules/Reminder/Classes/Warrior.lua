local ADDON, ns = ...

ns.classes.WARRIOR = function()
	local BATTLE, BERSERKER, DEFENSIVE = 386164, 386196, 386208
	return {
		{ key = "shout", kind = "group", spell = 6673, auras = { 6673 } },   -- Battle Shout
		-- a stance: Battle (Arms) or Berserker (Fury); Defensive Stance counts as one too. A stance
		-- sits on the stance bar (form = true), which is read as well as the aura.
		{ key = "stance", kind = "buff", spell = function() return ns.KnownOrFirst({ BATTLE, BERSERKER }) end,
			auras = { BATTLE, BERSERKER, DEFENSIVE }, form = true },
		-- Defensive Stance on Arms or Fury, not tanking: time to leave it
		{ key = "defensive", kind = "avoid", spell = DEFENSIVE, auras = { DEFENSIVE }, form = true, spec = { [71] = true, [72] = true },
			When = function() return ns.Role() ~= "TANK" end },
	}
end
