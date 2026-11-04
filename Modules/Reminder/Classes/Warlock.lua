local ADDON, ns = ...

ns.classes.WARLOCK = function()
	local SACRIFICE, SACRIFICED = 108503, 196099      -- Grimoire of Sacrifice, the buff it leaves
	local FELGUARD = ns.FELGUARD.summon
	local DEMONS = { FELGUARD, 691, 697, 688, 366222 }   -- Felguard, Felhunter, Voidwalker, Imp, Sayaad
	return {
		-- with Grimoire of Sacrifice the demon is there to be given up for the buff; it is the demon's
		-- other way, so the settings page lists it with the demon
		{ key = "sacrifice", kind = "buff", spell = SACRIFICE, auras = { SACRIFICED }, spec = { [265] = true, [267] = true },   -- Affliction, Destruction
			withPet = true },
		-- the demon you summoned last in this spec (PvE or PvP); Demonology in PvE with Summon
		-- Felguard always the Felguard. Before you have summoned one: the first you know. The
		-- icon is named for the demon (Felguard), short of the spell (Summon Felguard).
		{ key = "demon", kind = "pet", felguard = true, options = DEMONS, Name = ns.SummonedName,
			Title = function(spell) return string.format(CombatKit.L["Summon demon (%s)"], ns.SummonedName(spell) or "?") end,
			spell = function() return ns.KnownOrFirst(DEMONS) end,
			Prefer = function(side)
				if side == "pve" and ns.SpecID() == 266 and ns.Known(FELGUARD) then return FELGUARD end
			end,
			When = function() return not ns.Known(SACRIFICE) end },
		-- Create Healthstone while there is none in the bags; anywhere, as the other class reminders
		{ key = "createstone", kind = "make", label = "Healthstone", spell = ns.HEALTHSTONE.create, items = ns.HEALTHSTONE.items },
		-- Soulstone on someone in the group (yourself counts), unless it is cooling down after use
		{ key = "soulstone", kind = "ally", spell = 20707, auras = { 20707 }, cooldown = true, self = true },
	}
end
