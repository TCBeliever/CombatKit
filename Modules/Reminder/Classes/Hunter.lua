local ADDON, ns = ...

ns.classes.HUNTER = function()
	local BOND = 1223323   -- Unbreakable Bond: Marksmanship with a pet
	return {
		-- Call Pet: Beast Mastery and Survival always, Marksmanship with the talent
		{ key = "pet", kind = "pet", spell = 883, When = function()
			local spec = ns.SpecID()
			return spec == 253 or spec == 255 or (spec == 254 and ns.Known(BOND))
		end },
	}
end
