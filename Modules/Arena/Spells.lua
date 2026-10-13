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
-- `notOnSelf` marks an external that cannot be cast on oneself, so its holder
-- is never its caster. Area buffs (Darkness, Barrier) land on several allies
-- at once; the tracker folds those into one use.
--
-- Spell and aura IDs, cooldowns and the names behind them are the game's own
-- data, as the client reports them on 12.1.
-- ===========================================================================

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
		External(51052, 120, { aura = 145629 }),  -- Anti-Magic Zone
	},
	DEMONHUNTER = {
		Self(198589, 60, { aura = 212800 }),   -- Blur
		Self(196555, 180),                     -- Netherwalk
		Self(187827, 120),                     -- Metamorphosis (Vengeance)
		External(196718, 300, { aura = 209426 }), -- Darkness
	},
	DRUID = {
		Self(22812, 60),                       -- Barkskin
		Self(61336, 180, { charges = 2 }),     -- Survival Instincts
		External(102342, 90),                  -- Ironbark
	},
	EVOKER = {
		Self(363916, 90),                      -- Obsidian Scales
		Self(374348, 90),                      -- Renewing Blaze
		External(357170, 60),                  -- Time Dilation
		External(374227, 120),                 -- Zephyr
	},
	HUNTER = {
		Self(186265, 180),                     -- Aspect of the Turtle
		Self(264735, 90),                      -- Survival of the Fittest
	},
	MAGE = {
		Self(45438, 240),                      -- Ice Block
		Self(342245, 60, { aura = 342246 }),   -- Alter Time
		Self(110959, 120, { aura = 110960 }),  -- Greater Invisibility
		Self(55342, 120),                      -- Mirror Image
	},
	MONK = {
		Self(115203, 360),                     -- Fortifying Brew
		Self(122783, 90),                      -- Diffuse Magic
		Self(122278, 120),                     -- Dampen Harm
		Self(122470, 90, { aura = 125174 }),   -- Touch of Karma
		External(116849, 120),                 -- Life Cocoon
	},
	PALADIN = {
		Self(642, 300),                        -- Divine Shield
		Self(498, 60),                         -- Divine Protection
		Self(31850, 90),                       -- Ardent Defender
		Self(86659, 180),                      -- Guardian of Ancient Kings
		External(1022, 300),                   -- Blessing of Protection
		External(6940, 120, { notOnSelf = true }), -- Blessing of Sacrifice
	},
	PRIEST = {
		Self(47585, 120),                      -- Dispersion
		Self(19236, 90),                       -- Desperate Prayer
		External(33206, 180),                  -- Pain Suppression
		External(47788, 180),                  -- Guardian Spirit
		External(62618, 180, { aura = 81782 }),   -- Power Word: Barrier
	},
	ROGUE = {
		Self(31224, 120),                      -- Cloak of Shadows
		Self(5277, 120),                       -- Evasion
	},
	SHAMAN = {
		Self(108271, 120),                     -- Astral Shift
		External(98008, 180, { aura = 325174 }),  -- Spirit Link Totem
	},
	WARLOCK = {
		Self(104773, 180),                     -- Unending Resolve
		Self(108416, 60),                      -- Dark Pact
	},
	WARRIOR = {
		Self(118038, 120),                     -- Die by the Sword
		Self(184364, 120),                     -- Enraged Regeneration
		Self(871, 180),                        -- Shield Wall
		Self(12975, 180),                      -- Last Stand
		External(97462, 180, { aura = 97463 }),   -- Rallying Cry
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
		ns.SPELL_BY_ID[def.id] = def
		ns.CLASSES_WITH[def.id] = ns.CLASSES_WITH[def.id] or {}
		ns.CLASSES_WITH[def.id][class] = true
	end
end

-- the definitions a teammate of this class gets, in list order
function ns.SpellsFor(class, withExternals)
	local out = {}
	for _, def in ipairs(ns.SPELLS[class] or {}) do
		if withExternals or def.kind == "self" then out[#out + 1] = def end
	end
	return out
end

-- the base cooldown in seconds: the client's answer, or the list's
function ns.BaseCooldown(def)
	if GetSpellBaseCooldown then
		local ok, ms = pcall(GetSpellBaseCooldown, def.id)
		if ok and type(ms) == "number" and ms > 0 then return ms / 1000 end
	end
	return def.cd
end
