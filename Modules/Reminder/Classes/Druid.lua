local ADDON, ns = ...

ns.classes.DRUID = function()
	return {
		{ key = "mark", kind = "group", spell = 1126, auras = { 1126 } },   -- Mark of the Wild
		{ key = "symbiotic", kind = "ally", spell = 474750, auras = { 474750 } },   -- Symbiotic Relationship
		-- Balance out of every form: Moonkin Form. Travel, cat or bear form is left alone.
		{ key = "moonkin", kind = "buff", spell = 24858, auras = { 24858 }, spec = { [102] = true },
			When = function() return (GetShapeshiftForm() or 0) == 0 end },
	}
end
