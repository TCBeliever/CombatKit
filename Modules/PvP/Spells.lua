local ADDON, ns = ...

-- ===========================================================================
-- What is tracked: a teammate's defensive cooldowns, by class and spec.
--
-- An ability is detected by the buff it leaves (`auras`), never by a cast
-- event: since 12.0.5 other players' casts are hidden from addons. `cd` is the
-- base cooldown; `mods` are the talents that change it, applied when the
-- teammate's talents were read by inspecting (Cooldowns.lua). The list of
-- mods is a subset: a talent not listed leaves the base cooldown, and the icon
-- may come back a little late. Beta: numbers to confirm in game.
--
--   role = "defensive" (default) | "offensive": a burst cooldown, shown after
--          the defensives; the settings can hide them.
--   kind = "self": the buff lands on the caster; only the caster is watched.
--   kind = "ally": an external, or a zone every ally stands in; every friendly
--                  unit is watched and the use is credited to the teammate
--                  whose class has the spell (Tracker.Owner).
--   kind = "enemy": a crowd control; its debuff is watched on every enemy
--                  arena unit and credited the same way (role "cc").
--   delayed: the effect can land long after the cast (a trap, a totem).
--   specs: nil = the whole class.  dur: how long the buff lasts (seconds).
--   charges: uses before the recovery starts (default 1).
--   excludeCaster: cannot be cast on oneself; the holder is never the caster.
--   targeted: with more than one charge, a use on another target is a
--             separate charge even while the first buff is still up.
--   mods: { talent = spellID of the talent, kind = "flat" | "percent" | "charges",
--           amount = seconds | percent | charges, perRank = amount is per rank,
--           pvp = a PvP talent, specs = only for these specs }
-- ===========================================================================

local S = {}
ns.Spells = S

local function A(id, name, cd, dur, more)
	local a = { id = id, name = name, cd = cd, dur = dur, kind = "self", role = "defensive", auras = { id } }
	if more then for k, v in pairs(more) do a[k] = v end end
	return a
end

local function set(...)
	local t = {}
	for i = 1, select("#", ...) do t[select(i, ...)] = true end
	return t
end

local function flat(talent, seconds, more)
	local m = { talent = talent, kind = "flat", amount = seconds }
	if more then for k, v in pairs(more) do m[k] = v end end
	return m
end
local function percent(talent, pct, more)
	local m = { talent = talent, kind = "percent", amount = pct }
	if more then for k, v in pairs(more) do m[k] = v end end
	return m
end
local function charges(talent, n)
	return { talent = talent, kind = "charges", amount = n }
end
-- a crowd control: a debuff on an enemy
local function E(id, name, cd, dur, more)
	local a = A(id, name, cd, dur, more)
	a.kind, a.role = "enemy", "cc"
	return a
end
-- a burst cooldown
local function O(id, name, cd, dur, more)
	local a = A(id, name, cd, dur, more)
	a.role = "offensive"
	return a
end

-- specs: DK 250 251 252 | DH 577 581 1480 | Druid 102 103 104 105 | Evoker 1467 1468 1473
-- Hunter 253 254 255 | Mage 62 63 64 | Monk 268 269 270 | Paladin 65 66 70
-- Priest 256 257 258 | Rogue 259 260 261 | Shaman 262 263 264 | Warlock 265 266 267 | Warrior 71 72 73
S.BY_CLASS = {
	DEATHKNIGHT = {
		A(48707, "Anti-Magic Shell", 60, 5, { auras = { 48707, 410358 },
			mods = { flat(205727, 20), flat(410320, 10, { pvp = true }), flat(457574, -20) } }),
		A(48792, "Icebound Fortitude", 120, 8),
		A(55233, "Vampiric Blood", 90, 10, { specs = set(250) }),
		A(49039, "Lichborne", 120, 10, { mods = { flat(389682, 30), flat(437122, 30) } }),
		A(51052, "Anti-Magic Zone", 240, 8, { kind = "ally", auras = { 145629 }, mods = { flat(374383, 60) } }),
		O(49028, "Dancing Rune Weapon", 120, 8, { mods = { percent(233412, 50, { pvp = true, specs = set(250) }), flat(377637, 30) }, auras = { 81256 }, specs = set(250) }),
		O(51271, "Pillar of Frost", 45, 12, { mods = { flat(1218603, -15, { pvp = true }) }, specs = set(251) }),
		O(207289, "Unholy Assault", 90, 20, { specs = set(252) }),
		E(221562, "Asphyxiate", 45, 4),
		E(47476, "Strangulate", 45, 4),
	},
	DEMONHUNTER = {
		A(198589, "Blur", 60, 10, { mods = { charges(1266307, 1) }, auras = { 212800, 196555 }, specs = set(577, 1480) }),
		A(196718, "Darkness", 300, 8, { kind = "ally", auras = { 209426 }, mods = { flat(389783, 120) } }),
		A(187827, "Metamorphosis", 120, 15, { specs = set(581) }),
		O(191427, "Metamorphosis", 120, 20, { auras = { 162264 }, specs = set(577) }),
		E(179057, "Chaos Nova", 45, 2, { specs = set(577, 1480) }),
		E(217832, "Imprison", 45, 4),
		E(207684, "Sigil of Misery", 120, 4, { auras = { 207685 }, delayed = true }),
	},
	DRUID = {
		A(22812, "Barkskin", 60, 8, { mods = { percent(203965, 12, { specs = set(104) }) } }),
		A(61336, "Survival Instincts", 180, 6, { mods = { percent(203965, 12, { specs = set(104) }) }, specs = set(103, 104), charges = 2 }),
		A(102342, "Ironbark", 90, 12, { kind = "ally", specs = set(105), mods = { flat(382552, 20) } }),
		O(194223, "Celestial Alignment", 180, 15, { mods = { flat(468743, 60), charges(468743, 1), flat(390378, 60) }, auras = { 194223, 102560 }, specs = set(102) }),
		O(106951, "Berserk", 180, 15, { mods = { flat(391174, 60) }, auras = { 106951, 102543 }, specs = set(103) }),
		E(5211, "Mighty Bash", 60, 4),
		E(99, "Incapacitating Roar", 30, 3),
		E(78675, "Solar Beam", 60, 8, { auras = { 81261 }, specs = set(102) }),
	},
	EVOKER = {
		A(363916, "Obsidian Scales", 90, 12, { mods = { percent(412713, 10, { specs = set(1473) }), charges(375406, 1) } }),
		A(357170, "Time Dilation", 60, 8, { kind = "ally", specs = set(1468), targeted = true,
			mods = { charges(376204, 1), flat(376204, 10) } }),   -- Just in Time
		A(374227, "Zephyr", 120, 8, { mods = { percent(412713, 10, { specs = set(1473) }) }, kind = "ally" }),
		O(375087, "Dragonrage", 120, 14, { specs = set(1467) }),
	},
	HUNTER = {
		A(186265, "Aspect of the Turtle", 180, 8, { mods = { flat(266921, 15), flat(1258485, 30) } }),
		A(264735, "Survival of the Fittest", 90, 6, { mods = { charges(459450, 1) } }),
		O(19574, "Bestial Wrath", 90, 15, { mods = { flat(231548, 60) }, specs = set(253) }),
		O(288613, "Trueshot", 120, 15, { mods = { flat(260404, 30) }, specs = set(254) }),
		O(360952, "Coordinated Assault", 120, 20, { specs = set(255) }),
		E(3355, "Freezing Trap", 30, 8, { mods = { flat(343247, 5) }, delayed = true }),
		E(19577, "Intimidation", 60, 3, { auras = { 24394 } }),
	},
	MAGE = {
		A(45438, "Ice Block", 240, 10, { auras = { 45438, 414658 }, mods = { flat(382424, 30), charges(1244110, 1), flat(1244110, 30), flat(1265517, 30) } }),
		A(342245, "Alter Time", 60, 10, { auras = { 342246 }, mods = { flat(342249, 5), flat(1255166, 10) } }),
		A(110959, "Greater Invisibility", 120, 3, { mods = { flat(210476, 60) }, auras = { 110960, 113862 } }),
		A(55342, "Mirror Image", 120, 40, { mods = { flat(1244025, 30) } }),
		O(365350, "Arcane Surge", 90, 15, { auras = { 365350, 365362 }, specs = set(62) }),
		O(190319, "Combustion", 120, 12, { mods = { flat(1254194, 60) }, specs = set(63) }),
		O(12472, "Icy Veins", 120, 20, { specs = set(64) }),
		E(31661, "Dragon's Breath", 45, 3, { mods = { flat(387807, 5) }, specs = set(63) }),
		E(113724, "Ring of Frost", 45, 8, { mods = { flat(387807, 5) }, auras = { 82691 }, delayed = true }),
	},
	MONK = {
		A(115203, "Fortifying Brew", 360, 15, { auras = { 115203, 120954 }, mods = { percent(202107, 50, { pvp = true, specs = set(268) }), flat(388813, 30) } }),
		A(122783, "Diffuse Magic", 90, 6),
		A(122278, "Dampen Harm", 120, 10),
		A(122470, "Touch of Karma", 90, 10, { auras = { 125174 }, specs = set(269) }),
		A(116849, "Life Cocoon", 120, 12, { kind = "ally", specs = set(270), mods = { flat(202424, 45, { pvp = true }) } }),
		A(115176, "Zen Meditation", 300, 8, { specs = set(268) }),
		E(119381, "Leg Sweep", 60, 3, { mods = { flat(344359, 10) } }),
		E(115078, "Paralysis", 45, 4, { mods = { flat(344359, 15) } }),
	},
	PALADIN = {
		A(642, "Divine Shield", 300, 8, { mods = { percent(378425, 15, { specs = set(66) }), percent(114154, 30) } }),
		A(498, "Divine Protection", 60, 8, { auras = { 498, 403876 }, specs = set(65, 70), mods = { percent(114154, 30) } }),
		A(1022, "Blessing of Protection", 300, 10, { mods = { percent(216853, 33, { pvp = true, specs = set(66) }), flat(384909, 60), percent(378425, 15, { specs = set(66) }) }, kind = "ally", auras = { 1022, 204018 } }),
		A(6940, "Blessing of Sacrifice", 120, 12, { mods = { percent(216853, 33, { pvp = true, specs = set(66) }), flat(384820, 60) }, kind = "ally", excludeCaster = true }),
		A(31850, "Ardent Defender", 90, 8, { specs = set(66) }),
		A(86659, "Guardian of Ancient Kings", 180, 8, { mods = { charges(1246481, 1) }, specs = set(66) }),
		A(184662, "Shield of Vengeance", 90, 15, { specs = set(70) }),
		O(31884, "Avenging Wrath", 120, 20, { mods = { percent(204074, 50, { specs = set(66) }), flat(1241511, 30) }, auras = { 31884, 231895 } }),
		E(853, "Hammer of Justice", 45, 6, { mods = { flat(234299, 15) } }),
		E(115750, "Blinding Light", 90, 6, { auras = { 105421 } }),
	},
	PRIEST = {
		A(33206, "Pain Suppression", 180, 8, { mods = { charges(373035, 1) }, kind = "ally", specs = set(256), targeted = true }),
		A(47788, "Guardian Spirit", 180, 10, { kind = "ally", specs = set(257) }),
		A(62618, "Power Word: Barrier", 180, 10, { kind = "ally", auras = { 81782 }, specs = set(256) }),
		A(47536, "Rapture", 90, 8, { specs = set(256) }),
		A(47585, "Dispersion", 120, 6, { specs = set(258), mods = { flat(288733, 30) } }),
		A(19236, "Desperate Prayer", 90, 10, { mods = { flat(238100, 20) } }),
		O(228260, "Voidform", 120, 20, { auras = { 194249, 391109 }, specs = set(258) }),
		O(200183, "Apotheosis", 120, 20, { specs = set(257) }),
		E(8122, "Psychic Scream", 40, 8, { mods = { flat(196704, 10) } }),
		E(64044, "Psychic Horror", 45, 4, { specs = set(258) }),
		E(15487, "Silence", 30, 4, { specs = set(258) }),
	},
	ROGUE = {
		A(31224, "Cloak of Shadows", 120, 5, { mods = { percent(441415, 10) } }),
		A(5277, "Evasion", 120, 10),
		O(13750, "Adrenaline Rush", 180, 20, { specs = set(260) }),
		O(121471, "Shadow Blades", 90, 16, { mods = { percent(354825, 20, { pvp = true }) }, specs = set(261) }),
		E(408, "Kidney Shot", 30, 6),
		E(2094, "Blind", 120, 8, { mods = { percent(256165, 25, { specs = set(260) }), percent(200733, 50), percent(441415, 10) } }),
	},
	SHAMAN = {
		A(108271, "Astral Shift", 120, 12, { mods = { flat(381647, 30) } }),
		A(98008, "Spirit Link Totem", 180, 6, { kind = "ally", auras = { 325174 }, specs = set(264) }),
		A(108270, "Stone Bulwark Totem", 180, 30, { auras = { 114893 } }),
		O(114050, "Ascendance", 180, 15, { mods = { flat(381785, 45), flat(462440, 60) }, specs = set(262) }),
		O(114051, "Ascendance", 180, 15, { mods = { flat(381785, 45), flat(462440, 60), flat(384444, 60) }, specs = set(263) }),
		E(192058, "Capacitor Totem", 60, 3, { auras = { 118905 }, delayed = true }),
		E(51514, "Hex", 30, 8, { mods = { flat(204268, 15) }, auras = { 51514, 210873, 211004, 211010, 211015, 269352, 277778, 277784, 309328 } }),
	},
	WARLOCK = {
		A(104773, "Unending Resolve", 180, 8, { mods = { flat(386659, 45) } }),
		A(108416, "Dark Pact", 60, 20, { mods = { flat(386686, 15) } }),
		O(113860, "Dark Soul: Misery", 120, 20, { specs = set(265) }),
		O(113858, "Dark Soul: Instability", 120, 20, { specs = set(267) }),
		E(6789, "Mortal Coil", 45, 4),
		E(30283, "Shadowfury", 60, 3, { mods = { flat(264874, 15), flat(1270255, 15) } }),
		E(5484, "Howl of Terror", 40, 8, { mods = { flat(429072, 10), flat(1270255, 5) } }),
	},
	WARRIOR = {
		A(118038, "Die by the Sword", 120, 8, { mods = { flat(383338, 30), percent(391271, 10) }, specs = set(71) }),
		A(184364, "Enraged Regeneration", 120, 8, { specs = set(72) }),
		A(871, "Shield Wall", 180, 8, { mods = { charges(397103, 1), flat(397103, 60) }, specs = set(73) }),
		A(12975, "Last Stand", 180, 15, { specs = set(73) }),
		A(97462, "Rallying Cry", 180, 10, { mods = { flat(235941, 120, { pvp = true }) }, kind = "ally", auras = { 97463 } }),
		O(107574, "Avatar", 90, 20, { specs = set(71, 73) }),
		O(1719, "Recklessness", 90, 12, { specs = set(72) }),
		E(107570, "Storm Bolt", 30, 4, { mods = { percent(391271, 10) } }),
		E(46968, "Shockwave", 40, 2, { auras = { 132168 } }),
		E(5246, "Intimidating Shout", 90, 8, { mods = { flat(424742, 15) } }),
	},
}

S.BY_ID = {}
for class, list in pairs(S.BY_CLASS) do
	for _, a in ipairs(list) do
		a.class = class
		S.BY_ID[a.id] = a
	end
end

-- the role each spec plays: with the spec unknown, the role the group assigned narrows the list
S.ROLE_OF = {
	[250] = "TANK", [581] = "TANK", [104] = "TANK", [268] = "TANK", [66] = "TANK", [73] = "TANK",
	[105] = "HEALER", [1468] = "HEALER", [270] = "HEALER", [65] = "HEALER", [256] = "HEALER", [257] = "HEALER", [264] = "HEALER",
}
local function RoleOf(spec) return S.ROLE_OF[spec] or "DAMAGER" end

-- The abilities of a class, narrowed to a spec when it is known, else to the
-- specs of the role (TANK | HEALER | DAMAGER) when that is.
function S.For(class, spec, role)
	local list, out = S.BY_CLASS[class], {}
	if not list then return out end
	for _, a in ipairs(list) do
		local keep = not a.specs
		if not keep then
			if spec then
				keep = a.specs[spec] == true
			elseif role == "TANK" or role == "HEALER" or role == "DAMAGER" then
				for sp in pairs(a.specs) do
					if RoleOf(sp) == role then keep = true end
				end
			else
				keep = true
			end
		end
		if keep then out[#out + 1] = a end
	end
	return out
end

-- Does this class have the spell at all? (For crediting an external.)
function S.ClassHas(class, id)
	local a = S.BY_ID[id]
	return a ~= nil and a.class == class
end
