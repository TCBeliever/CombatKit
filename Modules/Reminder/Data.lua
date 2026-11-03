local ADDON, ns = ...

-- ===========================================================================
-- The consumables, as the game's data has them (DB2, build 12.1.5.70688).
-- Several addons' lists gave the candidates; every ID here is one the data
-- puts in its category, and the current expansion's whole range is taken, not
-- what one list happened to carry. Items are ordered best first: the icon of
-- a reminder is the first one in the bags.
-- ===========================================================================

-- Flasks: the aura each gives. The fleeting and the crafted flask of a kind
-- give the same one. The profession phials (Haranir) are left out on purpose:
-- they help gathering, not a pull.
ns.FLASK = {
	auras = {
		1235057,   -- Flask of Thalassian Resistance
		1235108,   -- Flask of the Magisters
		1235110,   -- Flask of the Blood Knights
		1235111,   -- Flask of the Shattered Sun
		1239355,   -- Vicious Thalassian Flask of Honor (battlegrounds and arena)
	},
	items = {
		241326, 241327, 245929, 245928,   -- Shattered Sun: crafted, fleeting
		241324, 241325, 245931, 245930,   -- Blood Knights
		241322, 241323, 245933, 245932,   -- Magisters
		241320, 241321, 245926, 245927,   -- Thalassian Resistance
		241334,                           -- Vicious Thalassian Flask of Honor
	},
}

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
}

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
