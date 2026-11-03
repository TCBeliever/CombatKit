local ADDON, ns = ...

ns.classes.ROGUE = function()
	local LETHAL    = { 2823, 315584, 8679, 381664 }   -- Deadly, Instant, Wound, Amplifying Poison
	local NONLETHAL = { 3408, 381637, 5761 }           -- Crippling, Atrophic, Numbing Poison
	local BLADES    = 381801                           -- Dragon-Tempered Blades: two of each kind
	-- how many of a kind to have on: one, two with the talent, never more than are known
	local function Need(list)
		local known = 0
		for _, id in ipairs(list) do
			if ns.Known(id) then known = known + 1 end
		end
		return math.min(ns.Known(BLADES) and 2 or 1, known)
	end
	return {
		{ key = "lethal", kind = "buff", label = "Lethal poison", spell = function() return ns.FirstKnown(LETHAL) end,
			auras = LETHAL, need = function() return Need(LETHAL) end },
		{ key = "nonlethal", kind = "buff", label = "Non-lethal poison", spell = function() return ns.FirstKnown(NONLETHAL) end,
			auras = NONLETHAL, need = function() return Need(NONLETHAL) end },
	}
end
