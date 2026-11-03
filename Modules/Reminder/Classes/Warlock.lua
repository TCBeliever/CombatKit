local ADDON, ns = ...

ns.classes.WARLOCK = function()
	local SACRIFICE, SACRIFICED = 108503, 196099      -- Grimoire of Sacrifice, the buff it leaves
	local DEMONS = { 30146, 691, 697, 688, 366222 }   -- Felguard, Felhunter, Voidwalker, Imp, Sayaad
	return {
		-- with Grimoire of Sacrifice the demon is there to be given up for the buff
		{ key = "sacrifice", kind = "buff", spell = SACRIFICE, auras = { SACRIFICED } },
		{ key = "demon", kind = "pet", spell = function() return ns.FirstKnown(DEMONS) end,
			When = function() return not ns.Known(SACRIFICE) end },
		-- Soulstone on someone in the group (yourself counts), unless it is cooling down after use
		{ key = "soulstone", kind = "ally", spell = 20707, auras = { 20707 }, cooldown = true, self = true },
	}
end
