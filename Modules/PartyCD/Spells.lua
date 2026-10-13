local ADDON, ns = ...

-- ===========================================================================
-- What is watched, by hand: each class's abilities that matter in an arena.
-- Three kinds, by where the aura the ability leaves can be seen:
--
--   self      the buff lands on the caster (Blur, Divine Shield, Combustion)
--   external  the buff lands on an ally (Pain Suppression, Ironbark)
--   enemy     the debuff lands on an opponent (Kidney Shot, Hex): a crowd
--             control, watched on arena1-3
--
-- For external and enemy, who cast it is worked out from who could have
-- (Tracker.lua). `role` is what the ability is for, and how the spells page
-- groups it: "defensive" (self and external, the default), "offensive" (a
-- burst cooldown) or "cc" (every enemy one).
--
-- `aura` is the aura the ability leaves when it differs from the spell (Blur
-- casts 198589, the buff is 212800); `auras` lists them when it can leave one
-- of several (a talent's version, another look). The slot filter takes them
-- all and the spell itself. `cd` is the base cooldown in seconds, used only
-- when the client cannot say (GetSpellBaseCooldown); the teammate's talents
-- may change it, which inspect takes care of. `charges` when the base ability
-- has more than one.
-- `glow` colours the halo while the aura is up: "defensive" (green, the
-- default), "major" (yellow: immunities and the big externals), "burst" (red,
-- every offensive cooldown), "cc" (violet, every crowd control).
-- `notOnSelf` marks an external that cannot be cast on oneself, so its holder
-- is never its caster. `area` with `lasts` marks an aura that a ground effect
-- puts on whoever stands in it for that many seconds: units walk in and out,
-- so every sighting within that time is the same use, and such a use never
-- corrects the cooldown estimate. `delayed` is how long, in seconds, the
-- effect can wait after the cast before it lands (a trap on the ground, a
-- totem's or a sigil's fuse): the player's own cast still explains it.
-- `extraCharge` says a talent can add a charge, `noLearn` that something
-- other than the cooldown can bring the ability back (a reset, a talent's
-- shorter version, a cooldown cut by what the player does), so two close uses
-- prove nothing about the cooldown. Every offensive cooldown is noLearn.
--
-- `specs` names the specializations that have the ability at all (spec IDs:
-- Blood 250, Frost DK 251, Unholy 252, Havoc 577, Vengeance 581, Devourer
-- 1480, Balance 102, Feral 103, Guardian 104, Restoration druid 105,
-- Devastation 1467, Preservation 1468, Beast Mastery 253, Marksmanship 254,
-- Survival 255, Arcane 62, Fire 63, Frost mage 64, Brewmaster 268, Windwalker
-- 269, Mistweaver 270, Holy paladin 65, Protection paladin 66, Retribution 70,
-- Discipline 256, Holy priest 257, Shadow 258, Outlaw 260, Subtlety 261,
-- Elemental 262, Enhancement 263, Restoration shaman 264, Affliction 265,
-- Destruction 267, Arms 71, Fury 72, Protection warrior 73); once inspect
-- knows a teammate's spec, the others leave the row. Without it the whole
-- class has the ability; a talent the spec's tree offers and the teammate did
-- not take is found by inspect as well.
--
-- Spell and aura IDs, cooldowns and the names behind them are the game's own
-- data, as the client reports them on 12.1.
-- ===========================================================================

local function set(...)
	local t = {}
	for i = 1, select("#", ...) do t[select(i, ...)] = true end
	return t
end

local function Def(kind, role, id, cd, extra)
	local d = { id = id, cd = cd, kind = kind, role = role }
	if extra then for k, v in pairs(extra) do d[k] = v end end
	return d
end
local function Self(id, cd, extra) return Def("self", "defensive", id, cd, extra) end
local function External(id, cd, extra) return Def("external", "defensive", id, cd, extra) end
-- a burst cooldown: a buff on the caster
local function Burst(id, cd, extra)
	local d = Def("self", "offensive", id, cd, extra)
	d.glow, d.noLearn = "burst", true
	return d
end
-- a crowd control: a debuff on an opponent
local function CC(id, cd, extra)
	local d = Def("enemy", "cc", id, cd, extra)
	d.glow = "cc"
	return d
end

ns.SPELLS = {
	DEATHKNIGHT = {
		Self(48707, 60, { auras = { 48707, 410358 } }),  -- Anti-Magic Shell (410358: cast on an ally)
		Self(48792, 120),                      -- Icebound Fortitude
		Self(49039, 120),                      -- Lichborne
		Self(55233, 90, { specs = set(250) }), -- Vampiric Blood
		External(51052, 120, { aura = 145629, area = true, lasts = 8 }),  -- Anti-Magic Zone
		CC(221562, 45),                        -- Asphyxiate
		CC(47476, 45),                         -- Strangulate
		Burst(49028, 120, { aura = 81256, specs = set(250) }),  -- Dancing Rune Weapon
		Burst(51271, 45, { specs = set(251) }),  -- Pillar of Frost
		Burst(207289, 90, { specs = set(252) }), -- Unholy Assault
	},
	DEMONHUNTER = {
		Self(198589, 60, { aura = 212800, extraCharge = true }),  -- Blur
		Self(196555, 180, { glow = "major" }), -- Netherwalk
		Self(187827, 120, { noLearn = true, specs = set(581) }), -- Metamorphosis (Vengeance): a talent gives a short one too
		External(196718, 300, { aura = 209426, area = true, lasts = 8 }), -- Darkness
		CC(179057, 45, { specs = set(577, 1480) }),  -- Chaos Nova
		CC(217832, 45),                        -- Imprison
		CC(207684, 120, { aura = 207685, delayed = 3 }),  -- Sigil of Misery
		Burst(191427, 120, { aura = 162264, specs = set(577) }),  -- Metamorphosis (Havoc)
	},
	DRUID = {
		Self(22812, 60),                       -- Barkskin
		Self(61336, 180, { charges = 2, specs = set(103, 104) }),  -- Survival Instincts
		External(102342, 90, { specs = set(105) }),  -- Ironbark
		CC(5211, 60),                          -- Mighty Bash
		CC(99, 30),                            -- Incapacitating Roar
		CC(78675, 60, { aura = 81261, area = true, lasts = 8, specs = set(102) }),  -- Solar Beam
		Burst(194223, 180, { auras = { 194223, 102560 }, specs = set(102) }),  -- Celestial Alignment, or Incarnation
		Burst(106951, 180, { auras = { 106951, 102543 }, specs = set(103) }),  -- Berserk, or Incarnation
	},
	EVOKER = {
		Self(363916, 90, { extraCharge = true }),  -- Obsidian Scales
		Self(374348, 90),                      -- Renewing Blaze
		External(357170, 60, { extraCharge = true, specs = set(1468) }),  -- Time Dilation
		External(374227, 120, { area = true, lasts = 8 }),  -- Zephyr
		Burst(375087, 120, { specs = set(1467) }),  -- Dragonrage
	},
	HUNTER = {
		Self(186265, 180, { glow = "major" }), -- Aspect of the Turtle
		Self(264735, 90, { extraCharge = true }),  -- Survival of the Fittest
		CC(3355, 30, { delayed = 60 }),        -- Freezing Trap: armed on the ground for a minute
		CC(19577, 60, { aura = 24394 }),       -- Intimidation
		Burst(19574, 90, { specs = set(253) }),  -- Bestial Wrath
		Burst(288613, 120, { specs = set(254) }), -- Trueshot
		Burst(360952, 120, { specs = set(255) }), -- Coordinated Assault
	},
	MAGE = {
		Self(45438, 240, { auras = { 45438, 414658 }, noLearn = true, extraCharge = true, glow = "major" }),  -- Ice Block, or Ice Cold; Cold Snap resets it
		Self(342245, 60, { aura = 342246 }),   -- Alter Time
		Self(110959, 120, { auras = { 110960, 113862 } }),  -- Greater Invisibility
		Self(55342, 120),                      -- Mirror Image
		CC(31661, 45, { specs = set(63) }),    -- Dragon's Breath
		CC(113724, 45, { aura = 82691, area = true, lasts = 10 }),  -- Ring of Frost
		Burst(365350, 90, { auras = { 365350, 365362 }, specs = set(62) }),  -- Arcane Surge
		Burst(190319, 120, { specs = set(63) }), -- Combustion
		Burst(12472, 120, { specs = set(64) }),  -- Icy Veins
	},
	MONK = {
		Self(115203, 360, { auras = { 115203, 120954 } }),  -- Fortifying Brew
		Self(122783, 90),                      -- Diffuse Magic
		Self(122278, 120),                     -- Dampen Harm
		Self(122470, 90, { aura = 125174, specs = set(269) }),  -- Touch of Karma
		Self(115176, 300, { specs = set(268) }), -- Zen Meditation
		External(116849, 120, { glow = "major", specs = set(270) }),  -- Life Cocoon
		CC(119381, 60),                        -- Leg Sweep
		CC(115078, 45),                        -- Paralysis
	},
	PALADIN = {
		Self(642, 300, { glow = "major" }),    -- Divine Shield
		Self(498, 60, { auras = { 498, 403876 }, specs = set(65, 70) }),  -- Divine Protection
		Self(31850, 90, { specs = set(66) }),  -- Ardent Defender
		Self(86659, 180, { extraCharge = true, specs = set(66) }),  -- Guardian of Ancient Kings
		Self(184662, 90, { specs = set(70) }), -- Shield of Vengeance (the client gives no base cooldown)
		External(1022, 300, { auras = { 1022, 204018 }, glow = "major" }),  -- Blessing of Protection, or of Spellwarding
		External(6940, 120, { notOnSelf = true }), -- Blessing of Sacrifice
		CC(853, 45),                           -- Hammer of Justice
		CC(115750, 90, { aura = 105421 }),     -- Blinding Light
		Burst(31884, 120, { auras = { 31884, 231895 } }),  -- Avenging Wrath, or Crusade
	},
	PRIEST = {
		Self(47585, 120, { glow = "major", specs = set(258) }),  -- Dispersion
		Self(19236, 90),                       -- Desperate Prayer
		Self(47536, 90, { specs = set(256) }), -- Rapture
		External(33206, 180, { extraCharge = true, glow = "major", specs = set(256) }),  -- Pain Suppression
		External(47788, 180, { glow = "major", specs = set(257) }),  -- Guardian Spirit
		External(62618, 180, { aura = 81782, area = true, lasts = 10, specs = set(256) }),  -- Power Word: Barrier
		CC(8122, 40),                          -- Psychic Scream
		CC(64044, 45, { specs = set(258) }),   -- Psychic Horror
		CC(15487, 30, { specs = set(258) }),   -- Silence
		Burst(228260, 120, { auras = { 194249, 391109 }, specs = set(258) }),  -- Voidform, or Dark Ascension
		Burst(200183, 120, { specs = set(257) }),  -- Apotheosis
	},
	ROGUE = {
		Self(31224, 120, { glow = "major" }),  -- Cloak of Shadows
		Self(5277, 120),                       -- Evasion
		CC(408, 30),                           -- Kidney Shot
		CC(2094, 120),                         -- Blind
		Burst(13750, 180, { specs = set(260) }),  -- Adrenaline Rush
		Burst(121471, 90, { specs = set(261) }),  -- Shadow Blades
	},
	SHAMAN = {
		Self(108271, 120),                     -- Astral Shift
		Self(108270, 180, { aura = 114893 }),  -- Stone Bulwark Totem
		External(98008, 180, { aura = 325174, area = true, lasts = 6, specs = set(264) }),  -- Spirit Link Totem
		CC(192058, 60, { aura = 118905, delayed = 3 }),  -- Capacitor Totem
		CC(51514, 30, { auras = { 51514, 210873, 211004, 211010, 211015, 269352, 277778, 277784, 309328 } }),  -- Hex, in every look
		Burst(114050, 180, { specs = set(262) }),  -- Ascendance (Elemental)
		Burst(114051, 180, { specs = set(263) }),  -- Ascendance (Enhancement)
	},
	WARLOCK = {
		Self(104773, 180),                     -- Unending Resolve
		Self(108416, 60),                      -- Dark Pact
		CC(6789, 45),                          -- Mortal Coil
		CC(30283, 60),                         -- Shadowfury
		CC(5484, 40),                          -- Howl of Terror
		Burst(113860, 120, { specs = set(265) }),  -- Dark Soul: Misery
		Burst(113858, 120, { specs = set(267) }),  -- Dark Soul: Instability
	},
	WARRIOR = {
		Self(118038, 120, { specs = set(71) }),  -- Die by the Sword
		Self(184364, 120, { specs = set(72) }),  -- Enraged Regeneration
		Self(871, 180, { extraCharge = true, specs = set(73) }),  -- Shield Wall
		Self(12975, 180, { specs = set(73) }), -- Last Stand
		External(97462, 180, { aura = 97463, area = true, lasts = 10 }),  -- Rallying Cry
		CC(107570, 30),                        -- Storm Bolt
		CC(46968, 40, { aura = 132168 }),      -- Shockwave
		CC(5246, 90),                          -- Intimidating Shout
		Burst(107574, 90, { specs = set(71, 73) }),  -- Avatar
		Burst(1719, 90, { specs = set(72) }),  -- Recklessness
	},
}

-- every definition by spell ID, and the classes that have it
ns.SPELL_BY_ID = {}
ns.CLASSES_WITH = {}
for class, list in pairs(ns.SPELLS) do
	for _, def in ipairs(list) do
		def.class = class
		def.auras = def.auras or { def.aura or def.id }
		def.aura = def.auras[1]
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
		if (sel.externals or def.kind ~= "external") and not disabled[def.id] then out[#out + 1] = def end
	end
	return out
end

-- the same, split by where the aura is looked for: on the teammate (self and
-- external) or on an opponent (enemy)
function ns.FriendlyDefs(defs)
	local out = {}
	for _, def in ipairs(defs) do if def.kind ~= "enemy" then out[#out + 1] = def end end
	return out
end

function ns.EnemyDefs(defs)
	local out = {}
	for _, def in ipairs(defs) do if def.kind == "enemy" then out[#out + 1] = def end end
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
