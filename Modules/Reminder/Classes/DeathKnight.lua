local ADDON, ns = ...

ns.classes.DEATHKNIGHT = function()
	-- every rune the Runeforge still offers; any one of them will do
	local RUNES = { [3368] = true, [3370] = true, [3847] = true, [6241] = true, [6242] = true, [6244] = true, [6245] = true }
	local LOOK = 53344   -- Rune of the Fallen Crusader: the icon
	return {
		-- every death knight has the Runeforge: nothing to be known first
		{ key = "rune", kind = "runeforge", label = "Runeforge", spell = LOOK, known = false, slot = ns.MAIN, enchants = RUNES },
		{ key = "rune2", kind = "runeforge", label = "Off-hand rune", spell = LOOK, known = false, slot = ns.OFF, enchants = RUNES },
		{ key = "ghoul", kind = "pet", spell = 46584, spec = { [252] = true } },   -- Unholy: Raise Dead, the ghoul that stays
	}
end
