local ADDON, ns = ...

ns.classes.DEATHKNIGHT = function()
	local FC, RAZORICE, STONESKIN, SANGUINATION, APOCALYPSE = 3368, 3370, 3847, 6241, 6245
	-- every rune the Runeforge still offers; any one of them will do
	local RUNES = { [FC] = true, [RAZORICE] = true, [STONESKIN] = true, [SANGUINATION] = true, [6242] = true,
		[6244] = true, [APOCALYPSE] = true }
	-- the spell that puts a rune on: its icon, and its name in the client's language
	local SPELLS = { [FC] = 53344, [RAZORICE] = 53343, [STONESKIN] = 62158, [SANGUINATION] = 326805, [APOCALYPSE] = 327082 }
	local SHATTERING, FROSTBANE = 207057, 455993   -- Shattering Blade, Frostbane
	-- What the guides recommend (Icy Veins and Wowhead 12.1.5, October 2026; the top players' runes on
	-- murlok.io and u.gg agree; read 2026-11-03): one rune for a two-hander, a pair for two weapons (either
	-- hand, the top players do both). The hero tree changes nothing; for Frost, Shattering Blade and
	-- Frostbane do. Frost in PvE dual wields, in PvP takes a two-hander: Icy Veins' Razorice for a
	-- two-hander in PvE is left out. Blood in PvP has no guide; the most used rune stands in.
	local function Guide(side)
		local spec = ns.SpecID()
		if spec == 250 then return { SANGUINATION } end
		if spec == 252 then return { APOCALYPSE } end
		if spec == 251 then
			if not ns.Weapon(ns.OFF) then return { FC } end
			if side == "pvp" or ns.Known(SHATTERING) or ns.Known(FROSTBANE) then return { RAZORICE, FC } end
			return { STONESKIN, FC }
		end
	end
	local LOOK = 53344   -- Rune of the Fallen Crusader: the icon until there is a rune to name
	return {
		-- every death knight has the Runeforge: nothing to be known first
		{ key = "rune", kind = "runeforge", label = "Main-hand rune", spell = LOOK, known = false, slot = ns.MAIN, enchants = RUNES,
			guide = Guide, runeSpells = SPELLS },
		-- only Frost dual wields (Dual Wield 674 is Frost's alone, DB2 SpecializationSpells)
		{ key = "rune2", kind = "runeforge", label = "Off-hand rune", spell = LOOK, known = false, slot = ns.OFF, enchants = RUNES,
			guide = Guide, runeSpells = SPELLS, spec = { [251] = true }, When = function() return ns.Weapon(ns.OFF) ~= nil end },
		{ key = "ghoul", kind = "pet", spell = 46584, spec = { [252] = true } },   -- Unholy: Raise Dead, the ghoul that stays
	}
end
