local ADDON, ns = ...

ns.classes.HUNTER = function()
	local BOND = 1223323   -- Unbreakable Bond: Marksmanship with a pet
	local CALLS = { 883, 83242, 83243, 83244, 83245 }   -- Call Pet 1 to 5
	-- the pet a Call Pet brings, from the stable: its icon and name; nothing while the stable is not read
	local function Look(spell)
		for slot, id in ipairs(CALLS) do
			if id == spell then return ns.StablePet(slot) end
		end
	end
	-- the name above the icon: "Pet 2", short of Call Pet 2
	local function Name(spell)
		for slot, id in ipairs(CALLS) do
			if id == spell then return string.format(CombatKit.L["Pet %d"], slot) end
		end
	end
	-- on the settings page: the pet by its name, else its slot
	local function Title(spell)
		local _, name = Look(spell)
		return string.format(CombatKit.L["Summon pet (%s)"], name or Name(spell) or "?")
	end
	return {
		-- Beast Mastery and Survival always, Marksmanship with the talent; the pet you called last in
		-- this spec, else the first
		{ key = "pet", kind = "pet", spell = CALLS[1], options = CALLS, Look = Look, Name = Name, Title = Title, When = function()
			local spec = ns.SpecID()
			return spec == 253 or spec == 255 or (spec == 254 and ns.Known(BOND))
		end },
	}
end
