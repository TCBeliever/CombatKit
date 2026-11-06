local ADDON, ns = ...

ns.classes.PALADIN = function()
	local AURAS = { 465, 317920, 32223 }   -- Devotion, Concentration, Crusader Aura
	local RITES = { 433568, 433583 }       -- Rite of Sanctification, Rite of Adjuration
	return {
		-- any aura counts; a click casts the one you cast last in this spec
		{ key = "aura", kind = "buff", spell = function() return ns.KnownOrFirst(AURAS) end, auras = AURAS, options = AURAS },
		-- the rites are Lightsmith's, a hero tree of Holy and Protection
		{ key = "rite", kind = "imbue", spell = function() return ns.KnownOrFirst(RITES) end, options = RITES, slot = ns.MAIN,
			enchants = { [7143] = true, [7144] = true }, spec = { [65] = true, [66] = true } },
		-- Holy in a group: Beacon of Light on someone, and Beacon of Faith with the talent. Faith
		-- wants a second target besides Light's: not with only one other in the group (a delve
		-- with a follower), and on yourself it counts.
		{ key = "beacon", kind = "ally", spell = 53563, auras = { 53563 }, spec = { [65] = true } },
		{ key = "faith", kind = "ally", spell = 156910, auras = { 156910 }, spec = { [65] = true }, self = true,
			When = function() return (GetNumGroupMembers and GetNumGroupMembers() or 0) >= 3 end },
	}
end
