local ADDON, ns = ...

-- ===========================================================================
-- The consumables, as the game's data has them (DB2, build 12.1.5.70688).
-- Several addons' lists gave the candidates; every ID here is one the data
-- puts in its category, and the current expansion's whole range is taken, not
-- what one list happened to carry. Items are ordered best first: the icon of
-- a reminder is the first one in the bags.
-- ===========================================================================

-- Flasks: the aura each gives, and the items that give it. The fleeting
-- flask (a cauldron's, free) comes before the crafted one, the better quality
-- first. The profession phials (Haranir) are left out on purpose: they help
-- gathering, not a pull; so is the PvP flask (Vicious Thalassian Flask of
-- Honor): consumables are for PvE, and it does nothing there.
ns.FLASK = {
	auras = {
		1235057,   -- Flask of Thalassian Resistance
		1235108,   -- Flask of the Magisters
		1235110,   -- Flask of the Blood Knights
		1235111,   -- Flask of the Shattered Sun
	},
	byAura = {
		[1235111] = { 245929, 245928, 241326, 241327 },   -- Shattered Sun: fleeting, crafted
		[1235110] = { 245931, 245930, 241324, 241325 },   -- Blood Knights
		[1235108] = { 245933, 245932, 241322, 241323 },   -- Magisters
		[1235057] = { 245926, 245927, 241320, 241321 },   -- Thalassian Resistance
	},
}
ns.FLASK.items = {}
for _, aura in ipairs(ns.FLASK.auras) do
	for _, item in ipairs(ns.FLASK.byAura[aura]) do ns.FLASK.items[#ns.FLASK.items + 1] = item end
end

-- Augment runes: this expansion's and the last's (which still work). Only a
-- player who has one is reminded. Tidesworn (12.1) carries an odd expansion
-- in the data, so a scan by expansion misses it; it is listed by hand.
ns.RUNE = {
	auras = { 1295329, 1264426, 1242347, 1234969, 453250 },
	items = { 274797, 259085, 246492, 243191, 224572 },   -- Tidesworn, Void-Touched, Soulgorged, Ethereal, Crystallized
}

-- Food. Every Well Fed and Hearty Well Fed of the expansion shares one icon,
-- and since the expansion's first food no other buff has it, so where the
-- buffs can be looked through, that icon is the answer, whatever new food a
-- patch adds. Where they cannot (raids and keys in 12.1 refuse it even out of
-- combat), each of the expansion's Well Fed buffs is asked for by ID. Eating
-- shows as a Refreshment buff (each food its own): no reminder meanwhile.
ns.FOOD_ICON = 136000
ns.WELL_FED = {
	1219182, 1219183, 1219184, 1219185, 1232076, 1232078, 1232080, 1232082, 1232086, 1232087, 1232089, 1232091,
	1232313, 1232316, 1232317, 1232318, 1232320, 1232321, 1232324, 1232325, 1232490, 1232491, 1232492, 1232493,
	1232496, 1232498, 1232500, 1232501, 1232582, 1232584, 1232585, 1233400, 1233401, 1233402, 1233403, 1233404,
	1233405, 1233406, 1233407, 1233408, 1233703, 1233704, 1233705, 1233706, 1233707, 1233708, 1233709, 1233710,
	1233711, 1233712, 1233713, 1233714, 1233715, 1233716, 1233717, 1233718, 1233719, 1233720, 1233721, 1233722,
	1233723, 1233724, 1233725, 1233726, 1233727, 1233728, 1233729, 1233730, 1233731, 1233732, 1233733, 1283372,
	1284616, 1284617, 1284618, 1284619, 1284641, 1284642, 1284643, 1284644, 1284647, 1284648, 1284649, 1284650,
	1285644, 1294727, 1305150, 1305151, 1305152, 1305153, 1305154, 1305155, 1305156, 1305157,
}
-- the food each Refreshment belongs to (the first item that casts it), and
-- every such food, the higher item level first: what a click eats when the
-- food you ate last is not in the bags
ns.FOOD = {
	byEating = {
		[1219187] = 235919, [1232246] = 242309, [1232249] = 242308, [1232250] = 242307, [1232251] = 242306,
		[1232252] = 242305, [1232253] = 242304, [1232256] = 242303, [1232257] = 242302, [1232481] = 242296,
		[1232483] = 242295, [1232484] = 242293, [1232485] = 242292, [1232486] = 242291, [1232487] = 242290,
		[1232488] = 242289, [1232489] = 242288, [1232901] = 242294, [1232902] = 242287, [1232903] = 242286,
		[1232905] = 242285, [1232906] = 242284, [1232907] = 242283, [1232908] = 242282, [1232909] = 242281,
		[1232910] = 242280, [1232913] = 242279, [1232914] = 242278, [1232915] = 242277, [1232916] = 242276,
		[1232917] = 242275, [1232919] = 242274, [1232925] = 242301, [1232926] = 242298, [1232927] = 242299,
		[1233738] = 242776, [1233739] = 242775, [1233740] = 242774, [1233741] = 242773, [1233742] = 242772,
		[1233743] = 242771, [1233744] = 242770, [1233745] = 242769, [1233746] = 242768, [1233747] = 242767,
		[1233748] = 242765, [1233749] = 242764, [1233750] = 242763, [1233751] = 242762, [1233752] = 242761,
		[1233753] = 242760, [1233754] = 242766, [1233755] = 242759, [1233756] = 242758, [1233757] = 242757,
		[1233758] = 242756, [1233759] = 242755, [1233760] = 242754, [1233761] = 242753, [1233762] = 242752,
		[1233763] = 242751, [1233764] = 242750, [1233765] = 242749, [1233766] = 242748, [1233767] = 242747,
		[1233768] = 242746, [1269305] = 242297,
	},
	items = {
		242274, 242275, 242276, 242277, 242278, 242280, 242281, 242282, 242283, 242284, 242285, 242286, 242287,
		242288, 242289, 242290, 242291, 242292, 242293, 242294, 242295, 242296, 242746, 242747, 242748, 242749,
		242750, 242752, 242753, 242754, 242755, 242756, 242757, 242758, 242759, 242760, 242761, 242762, 242763,
		242764, 242765, 242766, 242767, 242768, 242769, 242770, 242771, 242772, 242773, 242774, 242775, 242776,
		255847, 255848, 268679, 268680, 275258, 275259, 275260, 275261, 275262, 275263, 242297, 242298, 242299,
		242301, 242302, 242303, 242304, 242305, 242306, 242307, 242308, 242309, 235919, 242279, 242530, 242531,
		242532, 242751, 267000,
	},
}
ns.EATING = {
	1219187, 1232068, 1232070, 1232246, 1232249, 1232250, 1232251, 1232252, 1232253, 1232256, 1232257, 1232481,
	1232483, 1232484, 1232485, 1232486, 1232487, 1232488, 1232489, 1232901, 1232902, 1232903, 1232905, 1232906,
	1232907, 1232908, 1232909, 1232910, 1232913, 1232914, 1232915, 1232916, 1232917, 1232919, 1232920, 1232921,
	1232925, 1232926, 1232927, 1233738, 1233739, 1233740, 1233741, 1233742, 1233743, 1233744, 1233745, 1233746,
	1233747, 1233748, 1233749, 1233750, 1233751, 1233752, 1233753, 1233754, 1233755, 1233756, 1233757, 1233758,
	1233759, 1233760, 1233761, 1233762, 1233763, 1233764, 1233765, 1233766, 1233767, 1233768, 1233769, 1233770,
	1259662, 1269305, 1280485, 1283374, 1305158, 1305159,
}

-- Weapon oils, stones and ammunition: any temporary enchant on a weapon
-- counts, so only the items are listed, for the icon and the click, each with
-- the weapons it goes on (a mask of weapon subclasses, from the data): an oil
-- on any weapon, a whetstone on an edge, a weightstone on a blunt one,
-- ammunition on a bow, gun or crossbow. The Refulgent Razorstone is left out:
-- it is for profession tools.
local ANY, EDGE, BLUNT, SHOTS = 983039, 41923, 9264, 262156
ns.OIL = {
	items = {
		243734, 243733,   -- Thalassian Phoenix Oil
		243736, 243735,   -- Oil of Dawn
		243738, 243737,   -- Smuggler's Enchanted Edge
		257749, 257750,   -- Laced Zoomshots
		257751, 257752,   -- Weighted Boomshots
		237371, 237370,   -- Refulgent Whetstone
		237369, 237367,   -- Refulgent Weightstone
	},
	fits = {
		[243734] = ANY, [243733] = ANY, [243736] = ANY, [243735] = ANY, [243738] = ANY, [243737] = ANY,
		[257749] = SHOTS, [257750] = SHOTS, [257751] = SHOTS, [257752] = SHOTS,
		[237371] = EDGE, [237370] = EDGE, [237369] = BLUNT, [237367] = BLUNT,
	},
	-- the enchant each puts on the weapon, and the items of that kind, the better first
	byEnchant = {
		[8051] = { 243734, 243733 }, [8052] = { 243734, 243733 },   -- Thalassian Phoenix Oil
		[8053] = { 243736, 243735 }, [8054] = { 243736, 243735 },   -- Oil of Dawn
		[8055] = { 243738, 243737 }, [8056] = { 243738, 243737 },   -- Smuggler's Enchanted Edge
		[8608] = { 257750, 257749 }, [8609] = { 257750, 257749 },   -- Laced Zoomshots
		[8610] = { 257752, 257751 }, [8611] = { 257752, 257751 },   -- Weighted Boomshots
		[7905] = { 237371, 237370 }, [7906] = { 237371, 237370 },   -- Refulgent Whetstone
		[7907] = { 237369, 237367 }, [7908] = { 237369, 237367 },   -- Refulgent Weightstone
	},
}

-- The creatures Summon Felguard brings (the data's summon effect): a
-- Felguard, or its Wrathguard look
ns.FELGUARD = { summon = 30146, creatures = { [17252] = true, [58965] = true } }

-- Healthstones: a warlock makes them (Create Healthstone) and puts a Soulwell
-- down for the group; a player without one, in a group with a warlock, is
-- reminded to take one.
ns.HEALTHSTONE = {
	items = { 5512, 224464 },   -- Healthstone, Demonic Healthstone
	create = 6201,
}

-- The class reminders: Classes/<Class>.lua each adds a function here that
-- returns its class's list. Only the player's own is ever called; the module
-- then drops the table, so the other classes' code is not kept.
ns.classes = {}

-- What one player puts down for the group: a feast (3 minutes on the ground)
-- and a flask cauldron (5 minutes; it hands out fleeting flasks). `casts`:
-- the spell the one who puts it down casts, and the item it is.
ns.FEAST = {
	items = {
		242272, 242744,   -- Quel'dorei Medley, its hearty twin
		242273, 242745,   -- Blooming Feast
		255845, 266985,   -- Silvermoon Parade
		255846, 266996,   -- Harandar Celebration
		275264, 275267,   -- Amani Cornucopia
		275265, 275268,   -- Loa's Gathering
		275266, 275269,   -- Feast of Knowledge
	},
	casts = {
		[1259657] = 242272, [1278915] = 242744, [1259656] = 242273, [1278909] = 242745,
		[1259659] = 255845, [1278895] = 266985, [1259658] = 255846, [1278929] = 266996,
		[1296432] = 275264, [1303407] = 275267, [1296433] = 275265, [1303408] = 275268,
		[1296434] = 275266, [1303409] = 275269,
	},
	duration = 180,
}

ns.CAULDRON = {
	items = { 241318, 241319 },   -- Cauldron of Sin'dorei Flasks
	casts = { [1240195] = 241318, [1240019] = 241319 },
	duration = 300,
	-- what it hands out: the fleeting flasks
	takes = { 245929, 245928, 245931, 245930, 245933, 245932, 245926, 245927 },
}
