local ADDON, ns = ...

ns.classes.MAGE = function()
	return {
		{ key = "intellect", kind = "group", spell = 1459, auras = { 1459 } },        -- Arcane Intellect
		{ key = "elemental", kind = "pet", spell = 31687, spec = { [64] = true } },   -- Frost: the Water Elemental
	}
end
