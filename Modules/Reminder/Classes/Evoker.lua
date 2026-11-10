local ADDON, ns = ...

ns.classes.EVOKER = function()
	-- Blessing of the Bronze: one cast, a different buff for each class it lands on
	local BRONZE = { 381732, 381741, 381746, 381748, 381749, 381750, 381751, 381752, 381753, 381754, 381756, 381757, 381758 }
	return {
		{ key = "bronze", kind = "group", spell = 364342, auras = BRONZE, short = "Blessing" },
		{ key = "source", kind = "ally", spell = 369459, auras = { 369459 } },   -- Source of Magic, on a healer
	}
end
