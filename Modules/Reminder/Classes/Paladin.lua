local ADDON, ns = ...

ns.classes.PALADIN = function()
	local AURAS = { 465, 317920, 32223 }   -- Devotion, Concentration, Crusader Aura
	local RITES = { 433568, 433583 }       -- Rite of Sanctification, Rite of Adjuration
	return {
		{ key = "aura", kind = "buff", spell = function() return ns.FirstKnown(AURAS) end, auras = AURAS },
		-- the rites are Lightsmith's, a hero tree of Holy and Protection
		{ key = "rite", kind = "imbue", spell = function() return ns.FirstKnown(RITES) end, slot = ns.MAIN,
			enchants = { [7143] = true, [7144] = true }, spec = { [65] = true, [66] = true } },
		-- Holy in a group: Beacon of Light on someone, and Beacon of Faith with the talent
		{ key = "beacon", kind = "ally", spell = 53563, auras = { 53563 }, spec = { [65] = true } },
		{ key = "faith", kind = "ally", spell = 156910, auras = { 156910 }, spec = { [65] = true } },
	}
end
