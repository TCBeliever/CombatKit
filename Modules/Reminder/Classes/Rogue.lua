local ADDON, ns = ...

ns.classes.ROGUE = function()
	local DEADLY, INSTANT, WOUND, AMPLIFYING = 2823, 315584, 8679, 381664
	local CRIPPLING, ATROPHIC, NUMBING = 3408, 381637, 5761
	local LETHAL    = { DEADLY, INSTANT, WOUND, AMPLIFYING }
	local NONLETHAL = { CRIPPLING, ATROPHIC, NUMBING }
	local BLADES    = 381801                           -- Dragon-Tempered Blades: two of each kind
	-- how many of a kind to have on: one, two with the talent, never more than are known
	local function Need(list)
		local known = 0
		for _, id in ipairs(list) do
			if ns.Known(id) then known = known + 1 end
		end
		return math.min(ns.Known(BLADES) and 2 or 1, known)
	end
	-- What the guides recommend, first choice first (Icy Veins and Wowhead 12.1.5, October 2026, with
	-- Skill-Capped for PvP and the top players' talents on murlok.io; read 2026-11-03). The hero tree
	-- changes nothing. Atrophic and Numbing share a talent node: whichever is known is the one. In
	-- PvP the lethal becomes Wound; Assassination's second (Deadly) is read from the top players'
	-- talents, no guide names it.
	-- Either spec may be asked about (the settings page shows each one's). A list is as long
	-- as the spec wants poisons of the kind: two for Assassination, which takes Dragon-Tempered
	-- Blades, one for the others.
	local function Lethal(side, spec)
		spec = spec or ns.SpecID()
		if side == "pvp" then return spec == 259 and { WOUND, DEADLY } or { WOUND } end
		return spec == 259 and { DEADLY, AMPLIFYING } or { INSTANT }
	end
	local function NonLethal(side, spec)
		spec = spec or ns.SpecID()
		if side == "pvp" then return spec == 259 and { CRIPPLING, ATROPHIC } or { CRIPPLING } end
		local node = ns.FirstKnown({ ATROPHIC, NUMBING }) or ATROPHIC   -- one talent node: the one taken
		return spec == 259 and { node, CRIPPLING } or { node }
	end
	-- The name above the icon: the poison a click puts on, short of "Poison" in English (Deadly);
	-- the zhTW names are four characters as they are. The settings page names the kind.
	local function Name(spell)
		local name = ns.SpellName(spell)
		return name and (name:gsub(" Poison$", "")) or nil
	end
	local L = CombatKit.L
	return {
		{ key = "lethal", kind = "buff", choose = true, guide = Lethal, Name = Name,
			Title = function() return L["Lethal poison"] end,
			spell = function() return ns.KnownOrFirst(LETHAL) end,
			auras = LETHAL, need = function() return Need(LETHAL) end },
		{ key = "nonlethal", kind = "buff", choose = true, guide = NonLethal, Name = Name,
			Title = function() return L["Non-lethal poison"] end,
			spell = function() return ns.KnownOrFirst(NONLETHAL) end,
			auras = NONLETHAL, need = function() return Need(NONLETHAL) end },
	}
end
