local ADDON, ns = ...

ns.classes.PRIEST = function()
	return {
		{ key = "fortitude", kind = "group", spell = 21562, auras = { 21562 } },   -- Power Word: Fortitude
		-- Shadow: Shadowform (Voidform stands in for it)
		{ key = "shadowform", kind = "buff", spell = 232698, auras = { 232698, 194249 }, form = true, spec = { [258] = true } },
	}
end
