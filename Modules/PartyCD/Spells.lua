local ADDON, ns = ...

-- ===========================================================================
-- What is watched, by hand: each class's abilities that matter in an arena.
--
-- An entry says two separate things.
--
-- How it is seen (`seen`, by the constructor): where the aura the ability
-- leaves shows up, and what that says about who cast it.
--
--   Caster      on the teammate who cast it (Blur, Divine Shield): the holder
--               is the caster
--   Ally        on one teammate, possibly the caster (Pain Suppression)
--   OtherAlly   on one teammate who cannot be the caster (Blessing of
--               Sacrifice, Intervene; the game's data marks them)
--   Allies      on several teammates from one use (Darkness, Rallying Cry):
--               every sighting within `window` seconds is that use, and such a
--               use never corrects the cooldown estimate
--   Enemy       on an opponent, as it is cast (Kidney Shot), watched on arena1-3
--   Enemies     on opponents walking into an area for `window` seconds (Solar
--               Beam, Ring of Frost)
--   EnemyLater  on an opponent up to `fuse` seconds after the cast (a trap, a
--               totem, a sigil): the player's own cast still explains it
--
-- What it is for (`tags`, a string of one or more words, the main one first):
--
--   defense   keeps someone alive: damage taken down, an immunity, a healing
--             cooldown, a way out of a stun, a fear or a silence (not out of a
--             root or a slow)
--   burst     more damage, the caster's or a teammate's
--   control   an opponent who cannot act or cannot hit: stun, fear,
--             polymorph, silence, disarm
--   other     whatever is none of the three
--
-- The spells page groups by the main tag (defense, burst, control, other); the
-- halo's colour follows it too, yellow instead for `big` (an immunity or a
-- large external). Every ability tagged burst is `noLearn` as well (a burst
-- cooldown is often cut or reset by what the player does); a healing cooldown
-- that was one before keeps it by hand.
--
-- The key: every entry is keyed by `id`, the spell the player casts (the
-- button), never by the aura it leaves. The cooldown, the talents that change
-- it, the icon and name, the player's own cast event, the slot of the
-- detection and the tick on the spells page all go by it. What is seen on a
-- unit is listed under it as `aura` / `auras`: one ability, any number of
-- auras (`aura` when it differs from the spell: Blur casts 198589, the buff is
-- 212800). When the same ability is also cast as another spell (a PvP
-- talent's version, a talent that swaps the button), `casts` lists those IDs.
-- A PvP talent may change an ability by a script the data does not show
-- (Spellwarden, Diamond Ice): its own spell then has no effect naming the
-- version it brings, which sits next to it among the spell IDs.
--
-- `external` (from how it is seen: on someone else than the caster) marks an
-- ability that may be another teammate's: the sample rows show it with the
-- shared-estimate mark; an entry says `external = false` when it is mostly the
-- caster's own (Anti-Magic Shell).
--
-- `cd` is the base cooldown in seconds and `charges` the charges, used only
-- when the game's data (TalentData.lua, generated from the data files) has no
-- entry; the teammate's talents may change them, which inspect takes care of.
-- `extraCharge` says a talent can add a charge, `noLearn` that something other
-- than the cooldown can bring the ability back (a reset, a talent's shorter
-- version), so two close uses prove nothing about the cooldown.
--
-- On by default is every ability with a base cooldown of a minute or more;
-- the shorter ones are off until ticked on the spells page (Settings > Party
-- CD > Spells), which keeps the rows to what decides a fight.
--
-- `specs` names the specializations that have the ability at all (spec IDs:
-- Blood 250, Frost DK 251, Unholy 252, Havoc 577, Vengeance 581, Devourer
-- 1480, Balance 102, Feral 103, Guardian 104, Restoration druid 105,
-- Devastation 1467, Preservation 1468, Augmentation 1473, Beast Mastery 253,
-- Marksmanship 254, Survival 255, Arcane 62, Fire 63, Frost mage 64,
-- Brewmaster 268, Windwalker 269, Mistweaver 270, Holy paladin 65, Protection
-- paladin 66, Retribution 70, Discipline 256, Holy priest 257, Shadow 258,
-- Assassination 259, Outlaw 260, Subtlety 261, Elemental 262, Enhancement 263,
-- Restoration shaman 264, Affliction 265, Demonology 266, Destruction 267,
-- Arms 71, Fury 72, Protection warrior 73), as the talent trees give them
-- (tools/talentdata.py checks it); once inspect knows a teammate's spec, the
-- others leave the row. Without it the whole class has the ability; a talent
-- the spec's tree offers and the teammate did not take is found by inspect as
-- well.
--
-- Within a class the entries run by main tag, then by how they are seen: the
-- order of the icons in a row.
--
-- Spell and aura IDs, cooldowns and the names behind them are the game's own
-- data, as the client reports them on 12.1.
-- ===========================================================================

local function set(...)
	local t = {}
	for i = 1, select("#", ...) do t[select(i, ...)] = true end
	return t
end

local function Def(seen, id, cd, tags, extra)
	local d = { id = id, cd = cd, seen = seen, tags = {} }
	for word in tags:gmatch("%S+") do d.tags[#d.tags + 1] = word end
	if extra then for k, v in pairs(extra) do d[k] = v end end
	return d
end
local function Caster(id, cd, tags, extra) return Def("caster", id, cd, tags, extra) end
local function Ally(id, cd, tags, extra) return Def("ally", id, cd, tags, extra) end
local function OtherAlly(id, cd, tags, extra) return Def("otherAlly", id, cd, tags, extra) end
local function Allies(id, cd, window, tags, extra)
	local d = Def("allies", id, cd, tags, extra)
	d.window = window
	return d
end
local function Enemy(id, cd, tags, extra) return Def("enemy", id, cd, tags, extra) end
local function Enemies(id, cd, window, tags, extra)
	local d = Def("enemies", id, cd, tags, extra)
	d.window = window
	return d
end
local function EnemyLater(id, cd, fuse, tags, extra)
	local d = Def("enemyLater", id, cd, tags, extra)
	d.fuse = fuse
	return d
end

ns.SPELLS = {
	DEATHKNIGHT = {
		Caster(48792, 120, "defense"),          -- Icebound Fortitude
		Caster(49039, 120, "defense"),          -- Lichborne
		Caster(55233, 90, "defense", { specs = set(250) }),  -- Vampiric Blood
		Ally(48707, 60, "defense", { auras = { 48707, 410358 }, external = false }),  -- Anti-Magic Shell; Spellwarden (PvP talent) puts it on an ally as 410358, but it stays the DK's own
		Allies(51052, 240, 8, "defense", { aura = 145629 }),  -- Anti-Magic Zone
		Caster(49028, 120, "burst defense", { aura = 81256, specs = set(250) }),  -- Dancing Rune Weapon
		Caster(51271, 45, "burst", { specs = set(251) }),  -- Pillar of Frost
		Caster(42650, 90, "burst", { specs = set(252) }),  -- Army of the Dead
		Enemy(221562, 45, "control"),           -- Asphyxiate
		Enemy(47476, 45, "control"),            -- Strangulate
		Enemy(207167, 60, "control"),           -- Blinding Sleet
		Enemy(91797, 90, "control", { specs = set(252) }),  -- Monstrous Blow: the transformed ghoul's stun
	},
	DEMONHUNTER = {
		Caster(198589, 60, "defense", { aura = 212800, extraCharge = true, specs = set(577, 1480) }),  -- Blur
		Caster(187827, 120, "defense", { noLearn = true, specs = set(581) }),  -- Metamorphosis (Vengeance): a talent gives a short one too
		Allies(196718, 300, 8, "defense", { aura = 209426 }),  -- Darkness
		Enemy(204021, 60, "defense", { auras = { 207771, 207744 }, specs = set(581) }),  -- Fiery Brand: a defensive, but its debuff sits on the opponent (aura IDs to confirm in game)
		Caster(191427, 120, "burst", { aura = 162264, specs = set(577) }),  -- Metamorphosis (Havoc)
		Caster(370965, 90, "burst", { specs = set(577) }),  -- The Hunt
		Enemy(179057, 45, "control", { specs = set(577, 581) }),  -- Chaos Nova
		Enemy(217832, 45, "control", { auras = { 217832, 221527 }, casts = { 221527 } }),  -- Imprison, or the PvP talent's version
		Enemy(205630, 60, "control", { specs = set(577, 581) }),  -- Illidan's Grasp (PvP talent)
		Enemy(1234195, 45, "control", { specs = set(1480) }),  -- Void Nova
		EnemyLater(207684, 120, 3, "control", { aura = 207685 }),  -- Sigil of Misery
		Caster(188501, 30, "other"),            -- Spectral Sight
	},
	DRUID = {
		Caster(22812, 60, "defense"),           -- Barkskin
		Caster(61336, 180, "defense", { extraCharge = true, specs = set(103, 104) }),  -- Survival Instincts: a second charge from the guardian passive or a talent
		Caster(740, 180, "defense", { specs = set(105) }),  -- Tranquility
		Caster(473909, 90, "defense", { specs = set(105) }),  -- Ancient of Lore (PvP talent)
		Ally(102342, 90, "defense", { specs = set(105) }),  -- Ironbark
		Caster(194223, 180, "burst", { auras = { 194223, 102560, 383410, 390414 }, casts = { 102560, 383410, 390414 }, specs = set(102) }),  -- Celestial Alignment, or Incarnation; Orbital Strike turns them into 383410 and 390414
		Caster(106951, 180, "burst", { auras = { 106951, 102543 }, casts = { 102543 }, specs = set(103) }),  -- Berserk, or Incarnation
		Caster(5217, 30, "burst", { specs = set(103) }),  -- Tiger's Fury
		Caster(50334, 180, "burst", { auras = { 50334, 102558 }, casts = { 102558 }, specs = set(104) }),  -- Berserk (Guardian), or Incarnation, which replaces it
		Enemy(5211, 60, "control"),             -- Mighty Bash
		Enemy(99, 30, "control"),               -- Incapacitating Roar
		Enemy(22570, 30, "control", { aura = 203123 }),  -- Maim: the stun is 203123
		Enemy(209749, 30, "control", { specs = set(102) }),  -- Faerie Swarm (PvP talent)
		Enemies(78675, 60, 8, "control", { aura = 81261, specs = set(102) }),  -- Solar Beam
		Ally(29166, 180, "other"),              -- Innervate
	},
	EVOKER = {
		Caster(363916, 90, "defense", { extraCharge = true }),  -- Obsidian Scales
		Caster(370960, 180, "defense", { specs = set(1468) }),  -- Emerald Communion (PvP talent)
		Ally(357170, 60, "defense", { extraCharge = true, specs = set(1468) }),  -- Time Dilation
		Ally(378441, 45, "defense"),            -- Time Stop (PvP talent)
		Allies(374227, 120, 8, "defense"),      -- Zephyr
		Allies(363534, 240, 1, "defense", { specs = set(1468) }),  -- Rewind
		Caster(375087, 120, "burst", { specs = set(1467) }),  -- Dragonrage
		Caster(357210, 120, "burst", { specs = set(1467, 1468) }),  -- Deep Breath (Augmentation's is replaced by Breath of Eons)
	},
	HUNTER = {
		Caster(186265, 180, "defense", { big = true }),  -- Aspect of the Turtle
		Caster(264735, 90, "defense", { extraCharge = true }),  -- Survival of the Fittest
		Ally(53480, 120, "defense"),            -- Roar of Sacrifice
		Caster(19574, 90, "burst", { specs = set(253) }),  -- Bestial Wrath
		Caster(288613, 120, "burst", { specs = set(254) }),  -- Trueshot
		Caster(1250646, 90, "burst", { specs = set(255) }),  -- Takedown
		Enemy(19577, 60, "control", { auras = { 24394, 1258508 }, specs = set(253, 255) }),  -- Intimidation
		Enemy(213691, 30, "control"),           -- Scatter Shot (PvP talent)
		Enemy(407028, 45, "control", { aura = 407032, specs = set(255) }),  -- Sticky Tar Bomb (PvP talent)
		EnemyLater(187650, 30, 60, "control", { auras = { 3355, 203337 } }),  -- Freezing Trap: the trap holds its target with 3355, or 203337 with Diamond Ice (PvP talent); armed on the ground for a minute
		EnemyLater(109248, 45, 10, "control", { aura = 117526 }),  -- Binding Shot: the stun is 117526, when the target leaves the tether
	},
	MAGE = {
		Caster(45438, 240, "defense", { auras = { 45438, 414658 }, big = true, extraCharge = true, noLearn = true }),  -- Ice Block, or Ice Cold; Cold Snap resets it
		Caster(342245, 60, "defense", { aura = 342246 }),  -- Alter Time
		Caster(110959, 120, "defense", { auras = { 110960, 113862 } }),  -- Greater Invisibility
		Caster(55342, 120, "defense"),          -- Mirror Image
		Caster(11426, 30, "defense", { specs = set(64) }),  -- Ice Barrier
		Caster(235313, 30, "defense", { specs = set(63) }),  -- Blazing Barrier
		Caster(235450, 30, "defense", { specs = set(62) }),  -- Prismatic Barrier
		Caster(365350, 90, "burst", { auras = { 365350, 365362 }, specs = set(62) }),  -- Arcane Surge
		Caster(190319, 120, "burst", { specs = set(63) }),  -- Combustion
		Enemy(31661, 45, "control"),            -- Dragon's Breath
		Enemies(113724, 45, 10, "control", { aura = 82691 }),  -- Ring of Frost
		EnemyLater(389794, 45, 6, "control", { aura = 389831, specs = set(64) }),  -- Snowdrift (PvP talent): the stun is 389831, after standing in it
		Allies(414664, 300, 1, "other"),        -- Mass Invisibility
	},
	MONK = {
		Caster(115203, 360, "defense", { auras = { 115203, 120954 } }),  -- Fortifying Brew
		Caster(122470, 90, "defense", { aura = 125174, specs = set(269) }),  -- Touch of Karma
		Caster(354540, 90, "defense", { specs = set(268) }),  -- Nimble Brew (PvP talent)
		Caster(132578, 120, "defense", { specs = set(268) }),  -- Invoke Niuzao, the Black Ox
		Caster(322118, 120, "defense", { specs = set(270) }),  -- Invoke Yu'lon, the Jade Serpent
		Caster(325197, 120, "defense", { auras = { 325197, 343818 }, noLearn = true, specs = set(270) }),  -- Invoke Chi-Ji, the Red Crane
		Ally(116849, 120, "defense", { big = true, specs = set(270) }),  -- Life Cocoon
		Caster(1249625, 90, "burst", { charges = 2, specs = set(269) }),  -- Zenith
		Enemy(119381, 60, "control"),           -- Leg Sweep
		Enemy(115078, 45, "control"),           -- Paralysis
		Enemy(198898, 30, "control", { aura = 198909 }),  -- Song of Chi-Ji: the disorient is 198909
		Enemy(233759, 45, "control", { specs = set(269) }),  -- Grapple Weapon (PvP talent)
		Ally(116841, 30, "other"),              -- Tiger's Lust
	},
	PALADIN = {
		Caster(642, 300, "defense", { big = true }),  -- Divine Shield
		Caster(498, 60, "defense", { auras = { 498, 403876 }, casts = { 403876 }, specs = set(65, 70) }),  -- Divine Protection (Retribution's is 403876)
		Caster(31850, 90, "defense", { specs = set(66) }),  -- Ardent Defender
		Caster(86659, 180, "defense", { extraCharge = true, specs = set(66) }),  -- Guardian of Ancient Kings
		Caster(31821, 180, "defense", { specs = set(65) }),  -- Aura Mastery: the aura on the paladin
		Caster(389539, 120, "defense", { specs = set(66) }),  -- Sentinel
		Caster(228049, 240, "defense", { big = true, specs = set(66) }),  -- Guardian of the Forgotten Queen (PvP talent): the aura on the paladin; the ally's to confirm in game
		Caster(216331, 60, "defense burst", { specs = set(65) }),  -- Avenging Crusader
		Ally(1022, 300, "defense", { auras = { 1022, 204018 }, big = true }),  -- Blessing of Protection, or of Spellwarding
		Ally(210256, 60, "defense", { specs = set(70) }),  -- Blessing of Sanctuary (PvP talent)
		OtherAlly(6940, 120, "defense", { auras = { 6940, 199448 }, casts = { 199448 } }),  -- Blessing of Sacrifice; Ultimate Sacrifice (PvP talent) turns it into 199448
		Caster(31884, 120, "burst"),            -- Avenging Wrath
		Enemy(853, 45, "control"),              -- Hammer of Justice
		Enemy(115750, 90, "control", { aura = 105421 }),  -- Blinding Light
	},
	PRIEST = {
		Caster(47585, 120, "defense", { big = true, specs = set(258) }),  -- Dispersion
		Caster(19236, 90, "defense"),           -- Desperate Prayer
		Caster(64843, 180, "defense", { specs = set(257) }),  -- Divine Hymn: the channel on the priest
		Caster(421453, 240, "defense", { specs = set(256) }),  -- Ultimate Penitence
		Caster(200183, 120, "defense", { noLearn = true, specs = set(257) }),  -- Apotheosis
		Ally(33206, 180, "defense", { big = true, extraCharge = true, specs = set(256) }),  -- Pain Suppression
		Ally(47788, 180, "defense", { big = true, specs = set(257) }),  -- Guardian Spirit
		Allies(62618, 180, 10, "defense", { aura = 81782, specs = set(256) }),  -- Power Word: Barrier
		Caster(228260, 120, "burst", { aura = 194249, specs = set(258) }),  -- Voidform
		Ally(10060, 120, "burst"),              -- Power Infusion
		Enemy(8122, 40, "control"),             -- Psychic Scream
		Enemy(15487, 30, "control", { specs = set(258) }),  -- Silence
		Enemy(88625, 60, "control", { auras = { 200196, 200200 }, specs = set(257) }),  -- Holy Word: Chastise: incapacitate, or stun with Censure
	},
	ROGUE = {
		Caster(31224, 120, "defense", { big = true }),  -- Cloak of Shadows
		Caster(5277, 120, "defense"),           -- Evasion
		Caster(13750, 180, "burst", { specs = set(260) }),  -- Adrenaline Rush
		Caster(121471, 90, "burst", { specs = set(261) }),  -- Shadow Blades
		Enemy(360194, 120, "burst", { specs = set(259) }),  -- Deathmark: the mark on the opponent
		Enemy(385627, 60, "burst", { specs = set(259) }),  -- Kingsbane: on the opponent
		Enemy(408, 30, "control"),              -- Kidney Shot
		Enemy(2094, 120, "control"),            -- Blind
		Enemy(207777, 45, "control"),           -- Dismantle (PvP talent)
	},
	SHAMAN = {
		Caster(108271, 120, "defense"),         -- Astral Shift
		Caster(108280, 180, "defense", { specs = set(264) }),  -- Healing Tide Totem
		Caster(409293, 120, "defense"),         -- Burrow (PvP talent)
		Caster(114052, 180, "defense", { noLearn = true, specs = set(264) }),  -- Ascendance (Restoration)
		Allies(98008, 180, 6, "defense", { aura = 325174, specs = set(264) }),  -- Spirit Link Totem
		Caster(114050, 180, "burst", { specs = set(262) }),  -- Ascendance (Elemental)
		Caster(114051, 180, "burst", { specs = set(263) }),  -- Ascendance (Enhancement)
		Caster(191634, 60, "burst", { specs = set(262) }),  -- Stormkeeper
		Enemy(51514, 30, "control", { auras = { 51514, 210873, 211004, 211010, 211015, 269352, 277778, 277784, 309328 } }),  -- Hex, in every look
		Enemy(118345, 40, "control", { specs = set(262) }),  -- Pulverize: the Primal Earth Elemental's stun
		Enemy(305483, 45, "control", { aura = 305485 }),  -- Lightning Lasso (PvP talent): the stun is 305485
		EnemyLater(192058, 60, 3, "control", { aura = 118905 }),  -- Capacitor Totem
		Caster(79206, 120, "other"),            -- Spiritwalker's Grace
	},
	WARLOCK = {
		Caster(104773, 180, "defense"),         -- Unending Resolve
		Caster(108416, 60, "defense"),          -- Dark Pact
		Caster(212295, 45, "defense"),          -- Nether Ward (PvP talent)
		Caster(205180, 120, "burst", { specs = set(265) }),  -- Summon Darkglare
		Caster(265187, 60, "burst", { specs = set(266) }),  -- Summon Demonic Tyrant
		Caster(442726, 60, "burst", { specs = set(265, 267) }),  -- Malevolence
		EnemyLater(1122, 120, 2, "burst control", { aura = 22703, specs = set(267) }),  -- Summon Infernal: the stun where it lands
		Enemy(6789, 45, "control"),             -- Mortal Coil
		Enemy(30283, 60, "control"),            -- Shadowfury
		Enemy(5484, 40, "control"),             -- Howl of Terror
		Enemy(6358, 30, "control"),             -- Seduction: the Succubus
		Enemy(89766, 30, "control", { specs = set(266) }),  -- Axe Toss: the Felguard
	},
	WARRIOR = {
		Caster(118038, 120, "defense", { specs = set(71) }),  -- Die by the Sword
		Caster(184364, 120, "defense", { specs = set(72) }),  -- Enraged Regeneration
		Caster(871, 180, "defense", { extraCharge = true, specs = set(73) }),  -- Shield Wall
		Caster(12975, 180, "defense", { specs = set(73) }),  -- Last Stand
		Caster(384100, 60, "defense"),          -- Berserker Shout
		OtherAlly(3411, 30, "defense", { aura = 147833 }),  -- Intervene: the buff on the ally is 147833
		Allies(97462, 180, 10, "defense", { aura = 97463 }),  -- Rallying Cry
		Caster(107574, 90, "burst"),            -- Avatar
		Caster(1719, 90, "burst", { specs = set(72) }),  -- Recklessness
		Caster(227847, 90, "burst", { specs = set(71, 72) }),  -- Bladestorm
		Enemy(107570, 30, "control", { aura = 132169 }),  -- Storm Bolt: the stun is 132169
		Enemy(46968, 40, "control", { aura = 132168 }),  -- Shockwave
		Enemy(5246, 90, "control"),             -- Intimidating Shout
		Enemy(236077, 45, "control"),           -- Disarm (PvP talent)
	},
}

-- Racial abilities, by the race (UnitRace's second value) and its race ID (for
-- the race's name). Shown on the spells page under "Racial" for a look; not
-- watched yet: teammates' races are not read and the PvP trinket's shared
-- cooldown (category 1166: Stoneform, Fireblood) is still to be measured
-- (docs/PartyCD-next.md, B). Cooldowns and auras are the game's data.
-- `defaultOff` keeps an ability off by default whatever its cooldown.
ns.RACIALS = {
	{ race = "Dwarf", raceID = 3, Caster(20594, 120, "defense", { aura = 65116 }) },  -- Stoneform: the buff is 65116
	{ race = "DarkIronDwarf", raceID = 34, Caster(265221, 120, "defense", { aura = 265226 }) },  -- Fireblood: the buff is 265226
	{ race = "NightElf", raceID = 4, Caster(58984, 120, "defense") },  -- Shadowmeld (defense or other: to decide)
	{ race = "Orc", raceID = 2, Caster(33697, 120, "burst", { casts = { 20572, 33702 }, auras = { 33697, 20572, 33702 }, defaultOff = true }) },  -- Blood Fury, in each class's version
	{ race = "Troll", raceID = 8, Caster(26297, 180, "burst", { defaultOff = true }) },  -- Berserking
	{ race = "MagharOrc", raceID = 36, Caster(274738, 120, "burst", { auras = { 274739, 274740, 274741, 274742 }, defaultOff = true }) },  -- Ancestral Call: one of four buffs
	{ race = "Pandaren", raceID = 24, Enemy(107079, 120, "control") },  -- Quaking Palm
	{ race = "Tauren", raceID = 6, Enemy(20549, 90, "control") },  -- War Stomp
	{ race = "KulTiran", raceID = 32, Enemy(287712, 150, "control") },  -- Haymaker
	{ race = "HighmountainTauren", raceID = 28, Enemy(255654, 120, "control", { aura = 255723 }) },  -- Bull Rush: the stun is 255723
}

-- where each way of being seen looks: on an opponent, or on the teammates; and
-- whether the aura lands on someone else than the caster (an external)
local ON_ENEMY = { enemy = true, enemies = true, enemyLater = true }
local ON_OTHERS = { ally = true, otherAlly = true, allies = true }

local function Complete(def)
	def.auras = def.auras or { def.aura or def.id }
	def.aura = def.auras[1]
	def.charges = def.charges or 1
	def.tag = def.tags[1]
	def.onEnemy = ON_ENEMY[def.seen] or false
	if def.external == nil then def.external = ON_OTHERS[def.seen] or false end   -- an entry may say otherwise
	for _, t in ipairs(def.tags) do
		if t == "burst" then def.noLearn = true end
	end
end

-- the racial definitions, in list order, each knowing its race
ns.RACIAL_LIST = {}
for _, r in ipairs(ns.RACIALS) do
	local def = r[1]
	def.race, def.raceID = r.race, r.raceID
	Complete(def)
	ns.RACIAL_LIST[#ns.RACIAL_LIST + 1] = def
end

-- every definition by spell ID, and the classes that have it
ns.SPELL_BY_ID = {}
ns.SPELL_BY_CAST = {}   -- a spell ID the ability is cast as, when not its own
ns.CLASSES_WITH = {}
for class, list in pairs(ns.SPELLS) do
	for _, def in ipairs(list) do
		def.class = class
		Complete(def)
		ns.SPELL_BY_ID[def.id] = def
		for _, cast in ipairs(def.casts or {}) do ns.SPELL_BY_CAST[cast] = def end
		ns.CLASSES_WITH[def.id] = ns.CLASSES_WITH[def.id] or {}
		ns.CLASSES_WITH[def.id][class] = true
	end
end

-- whether a definition carries this tag, main or not
function ns.HasTag(def, tag)
	for _, t in ipairs(def.tags) do if t == tag then return true end end
	return false
end

-- on unless ticked off: a base cooldown of this many seconds or more
ns.DEFAULT_ON_COOLDOWN = 60

function ns.DefaultOn(def)
	if def.defaultOff then return false end
	return ns.BaseCooldown(def) >= ns.DEFAULT_ON_COOLDOWN
end

-- whether an ability is watched, under `picked` ([spellID] = true | false: the
-- spells page's ticks; no entry: the default)
function ns.Picked(def, picked)
	local v = picked and picked[def.id]
	if v == nil then return ns.DefaultOn(def) end
	return v
end

-- the definitions a teammate of this class gets, in list order, under a
-- selection { picked = { [spellID] = bool } } (anything else: every tick at
-- its default)
function ns.SpellsFor(class, sel)
	if type(sel) ~= "table" then sel = {} end
	local out = {}
	for _, def in ipairs(ns.SPELLS[class] or {}) do
		if ns.Picked(def, sel.picked) then out[#out + 1] = def end
	end
	return out
end

-- the same, split by where the aura is looked for: on the teammates, or on an
-- opponent
function ns.FriendlyDefs(defs)
	local out = {}
	for _, def in ipairs(defs) do if not def.onEnemy then out[#out + 1] = def end end
	return out
end

function ns.EnemyDefs(defs)
	local out = {}
	for _, def in ipairs(defs) do if def.onEnemy then out[#out + 1] = def end end
	return out
end

-- the base cooldown in seconds and the base charges: the game's data
-- (TalentData.lua) when it has the ability, the list's values otherwise
local function Base(def)
	local data = ns.TalentData
	return data and data.base and data.base[def.id]
end

function ns.BaseCooldown(def)
	local b = Base(def)
	return b and b.cd or def.cd
end

-- whether a teammate under a stun, a fear or a disorient could still have cast
-- it (the game's data marks a few: Barkskin, Dispersion, Unending Resolve)
function ns.CastableUnderControl(def)
	local b = Base(def)
	return b and b.underControl or false
end

function ns.BaseCharges(def)
	local b = Base(def)
	return b and b.charges or def.charges or 1
end
