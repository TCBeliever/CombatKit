local ADDON, ns = ...

ns.classes.SHAMAN = function()
	local LIGHTNING, WATER, EARTH, EARTH_SELF = 192106, 52127, 974, 383648
	local ORBIT = 383010   -- Elemental Orbit: Earth Shield on yourself next to the other shield
	local function Orbit() return ns.Known(ORBIT) end
	return {
		{ key = "skyfury", kind = "group", spell = 462854, auras = { 462854 } },   -- Skyfury
		-- Lightning or Water Shield; without Elemental Orbit, Earth Shield on yourself is the one shield instead
		{ key = "shield", kind = "buff", spell = function() return ns.FirstKnown({ WATER, LIGHTNING }) end,
			auras = function()
				if Orbit() then return { LIGHTNING, WATER } end
				return { LIGHTNING, WATER, EARTH, EARTH_SELF }
			end },
		{ key = "earthself", kind = "buff", spell = EARTH, auras = { EARTH_SELF, EARTH }, When = Orbit },
		-- Restoration in a group: Earth Shield on someone else too (the tank, mostly)
		{ key = "earthally", kind = "ally", spell = EARTH, auras = { EARTH }, spec = { [264] = true } },
		-- weapon imbues; Flametongue goes in the off hand when that holds a weapon
		{ key = "windfury", kind = "imbue", spell = 33757, slot = ns.MAIN, enchants = { [5401] = true } },    -- Windfury Weapon
		{ key = "flametongue", kind = "imbue", spell = 318038, enchants = { [5400] = true },                      -- Flametongue Weapon
			slot = function() return ns.Weapon(ns.OFF) and ns.OFF or ns.MAIN end },
		{ key = "earthliving", kind = "imbue", spell = 382021, slot = ns.MAIN, enchants = { [6498] = true } },   -- Earthliving Weapon
	}
end
