local ADDON, ns = ...

-- ===========================================================================
-- What is watched: the defensive cooldowns of each class that matter in an
-- arena, by hand, nothing else. Two kinds:
--
--   self      the buff lands on the caster (Blur, Divine Shield, Ice Block)
--   external  the buff lands on an ally (Pain Suppression, Ironbark); who cast
--             it is worked out from who could have (Tracker.lua)
--
-- `aura` is the aura the ability leaves when it differs from the spell (Blur
-- casts 198589, the buff is 212800); the slot filter takes both. `cd` is the
-- base cooldown in seconds, used only when the client cannot say
-- (GetSpellBaseCooldown); the teammate's talents may shorten it, which inspect
-- will take care of. `charges` when the base ability has more than one.
-- `glow` colours the halo while the buff is up: "defensive" (green, the
-- default), "major" (yellow: immunities and the big externals), "burst"
-- (red, for offensive cooldowns when they come).
-- `notOnSelf` marks an external that cannot be cast on oneself, so its holder
-- is never its caster. `area` with `lasts` marks a buff that a ground effect
-- or an aura puts on whoever stands in it for that many seconds: allies walk
-- in and out, so every sighting within that time is the same use, and such a
-- use never corrects the cooldown estimate. `extraCharge` says a talent can
-- add a charge, `noLearn` that something other than the cooldown can bring
-- the ability back (a reset, a talent's shorter version), so two close uses
-- prove nothing about the cooldown.
--
-- `specs` names the specializations that have the ability at all (spec IDs:
-- Havoc 577, Vengeance 581, Feral 103, Guardian 104, Restoration druid 105,
-- Preservation 1468, Windwalker 269, Mistweaver 270, Holy paladin 65,
-- Protection paladin 66, Retribution 70, Discipline 256, Holy priest 257,
-- Shadow 258, Restoration shaman 264, Arms 71, Fury 72, Protection warrior 73);
-- once inspect knows a teammate's spec, the others leave the row. Without it
-- the whole class has the ability; a talent the spec's tree offers and the
-- teammate did not take is found by inspect as well.
--
-- Spell and aura IDs, cooldowns and the names behind them are the game's own
-- data, as the client reports them on 12.1.
-- ===========================================================================

local function set(...)
	local t = {}
	for i = 1, select("#", ...) do t[select(i, ...)] = true end
	return t
end

local function Self(id, cd, extra)
	local d = { id = id, cd = cd, kind = "self" }
	if extra then for k, v in pairs(extra) do d[k] = v end end
	return d
end

local function External(id, cd, extra)
	local d = { id = id, cd = cd, kind = "external" }
	if extra then for k, v in pairs(extra) do d[k] = v end end
	return d
end

ns.SPELLS = {
	DEATHKNIGHT = {
		Self(48707, 60),                       -- Anti-Magic Shell
		Self(48792, 120),                      -- Icebound Fortitude
		Self(49039, 120),                      -- Lichborne
		External(51052, 120, { aura = 145629, area = true, lasts = 8 }),  -- Anti-Magic Zone
	},
	DEMONHUNTER = {
		Self(198589, 60, { aura = 212800, extraCharge = true }),  -- Blur
		Self(196555, 180, { glow = "major" }), -- Netherwalk
		Self(187827, 120, { noLearn = true, specs = set(581) }), -- Metamorphosis (Vengeance): a talent gives a short one too
		External(196718, 300, { aura = 209426, area = true, lasts = 8 }), -- Darkness
	},
	DRUID = {
		Self(22812, 60),                       -- Barkskin
		Self(61336, 180, { charges = 2, specs = set(103, 104) }), -- Survival Instincts
		External(102342, 90, { specs = set(105) }), -- Ironbark
	},
	EVOKER = {
		Self(363916, 90, { extraCharge = true }),  -- Obsidian Scales
		Self(374348, 90),                      -- Renewing Blaze
		External(357170, 60, { extraCharge = true, specs = set(1468) }),  -- Time Dilation
		External(374227, 120, { area = true, lasts = 8 }),  -- Zephyr
	},
	HUNTER = {
		Self(186265, 180, { glow = "major" }), -- Aspect of the Turtle
		Self(264735, 90, { extraCharge = true }),  -- Survival of the Fittest
	},
	MAGE = {
		Self(45438, 240, { noLearn = true, extraCharge = true, glow = "major" }),  -- Ice Block: Cold Snap resets it
		Self(342245, 60, { aura = 342246 }),   -- Alter Time
		Self(110959, 120, { aura = 110960 }),  -- Greater Invisibility
		Self(55342, 120),                      -- Mirror Image
	},
	MONK = {
		Self(115203, 360),                     -- Fortifying Brew
		Self(122783, 90),                      -- Diffuse Magic
		Self(122278, 120),                     -- Dampen Harm
		Self(122470, 90, { aura = 125174, specs = set(269) }), -- Touch of Karma
		External(116849, 120, { glow = "major", specs = set(270) }),  -- Life Cocoon
	},
	PALADIN = {
		Self(642, 300, { glow = "major" }),    -- Divine Shield
		Self(498, 60, { specs = set(65, 70) }), -- Divine Protection
		Self(31850, 90, { specs = set(66) }), -- Ardent Defender
		Self(86659, 180, { extraCharge = true, specs = set(66) }),  -- Guardian of Ancient Kings
		External(1022, 300, { glow = "major" }),  -- Blessing of Protection
		External(6940, 120, { notOnSelf = true }), -- Blessing of Sacrifice
	},
	PRIEST = {
		Self(47585, 120, { glow = "major", specs = set(258) }),  -- Dispersion
		Self(19236, 90),                       -- Desperate Prayer
		External(33206, 180, { extraCharge = true, glow = "major", specs = set(256) }),  -- Pain Suppression
		External(47788, 180, { glow = "major", specs = set(257) }),  -- Guardian Spirit
		External(62618, 180, { aura = 81782, area = true, lasts = 10, specs = set(256) }),  -- Power Word: Barrier
	},
	ROGUE = {
		Self(31224, 120, { glow = "major" }),  -- Cloak of Shadows
		Self(5277, 120),                       -- Evasion
	},
	SHAMAN = {
		Self(108271, 120),                     -- Astral Shift
		External(98008, 180, { aura = 325174, area = true, lasts = 6, specs = set(264) }),  -- Spirit Link Totem
	},
	WARLOCK = {
		Self(104773, 180),                     -- Unending Resolve
		Self(108416, 60),                      -- Dark Pact
	},
	WARRIOR = {
		Self(118038, 120, { specs = set(71) }), -- Die by the Sword
		Self(184364, 120, { specs = set(72) }), -- Enraged Regeneration
		Self(871, 180, { extraCharge = true, specs = set(73) }),  -- Shield Wall
		Self(12975, 180, { specs = set(73) }), -- Last Stand
		External(97462, 180, { aura = 97463, area = true, lasts = 10 }),  -- Rallying Cry
	},
}

-- every definition by spell ID, and the classes that have it
ns.SPELL_BY_ID = {}
ns.CLASSES_WITH = {}
for class, list in pairs(ns.SPELLS) do
	for _, def in ipairs(list) do
		def.class = class
		def.aura = def.aura or def.id
		def.charges = def.charges or 1
		def.glow = def.glow or "defensive"
		ns.SPELL_BY_ID[def.id] = def
		ns.CLASSES_WITH[def.id] = ns.CLASSES_WITH[def.id] or {}
		ns.CLASSES_WITH[def.id][class] = true
	end
end

-- the definitions a teammate of this class gets, in list order, under a
-- selection { externals = bool, disabled = { [spellID] = true } } (a bare
-- boolean stands for the externals flag alone)
function ns.SpellsFor(class, sel)
	if type(sel) ~= "table" then sel = { externals = sel } end
	local disabled = sel.disabled or {}
	local out = {}
	for _, def in ipairs(ns.SPELLS[class] or {}) do
		if (sel.externals or def.kind == "self") and not disabled[def.id] then out[#out + 1] = def end
	end
	return out
end

-- the base cooldown in seconds: the client's answer when it is a plain,
-- sensible number of milliseconds, the list's otherwise
function ns.BaseCooldown(def)
	if GetSpellBaseCooldown then
		local ok, ms = pcall(GetSpellBaseCooldown, def.id)
		if ok and type(ms) == "number" and (type(canaccessvalue) ~= "function" or canaccessvalue(ms)) then
			local okC, seconds = pcall(function() return ms / 1000 end)
			if okC and seconds >= 5 and seconds <= 1200 then return seconds end
		end
	end
	return def.cd
end
