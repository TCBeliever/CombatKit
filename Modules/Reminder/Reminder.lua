local ADDON, ns = ...
local CK = CombatKit
local L = CK.L

CK.NewModule("Reminder", ns)

-- ===========================================================================
-- Reminder: an icon for each thing missing before a pull.
--
-- Your consumables (flask, food, augment rune, weapon oil, healthstone) at
-- the entrance, until the first combat of the visit; in a raid again
-- whenever combat ends (a boss down, a buff run out); a ready check brings
-- them back anywhere while it runs. A Mythic+ run needs nothing more: once
-- the key runs nothing shows. Your class's reminders, each switched on its
-- own, and your own spell IDs (custom) whenever they are missing; in a
-- battleground only until the first fight, and again after each death. A buff with
-- less than a few minutes left counts as missing. What the group puts down
-- (a feast, a flask cauldron) is Shared.lua's. Nothing in combat, while dead,
-- in a vehicle or on a flight, in a running key or encounter, or right after
-- a loading screen; in a resting area only a death knight's runes; only in
-- the scenarios the player picked. A dungeon or raid far below you (legacy
-- loot, or you are levelling) plays as the open world.
--
-- A class list (Classes/*.lua) holds entries:
--   { key = what its switch is saved under,
--     kind = "group" | "buff" | "ally" | "avoid" | "pet" | "imbue" | "runeforge" | "make",
--     spell = ID or function() -> ID: the icon, the name, what has to be known
--             and what a click casts,
--     known = false: nothing to be known first,
--     spec = { [specID] = true }, When = function() -> bool: more conditions,
--     auras = IDs or function() -> IDs (group, buff, ally, avoid),
--     need = n or function() -> n: how many of the auras (buff; 1),
--     form = true: the stance bar counts as well as the aura (buff, avoid),
--     cooldown = true: not while the spell cools down (ally), self = true: on yourself counts (ally),
--     choose = true: several spells to pick from; a click casts one not on yet (buff),
--     options = IDs or function() -> IDs: the spells to pick one from (a demon, an aura); a click
--               casts the one you cast last in this setup, or Prefer(side)'s when it names one;
--               Alt over the icon shows the others,
--     Look = function(spell) -> icon, name: the icon (and name) of what a spell brings (a hunter's pets),
--     Name = function(spell) -> text: the name above the icon, where the spell's own is too long,
--     Title = function(spell) -> text: its name on the settings page, where the icon's is too short,
--     buffs = IDs: the imbue's own buff, which counts as well as its enchant (imbue),
--     felguard = true: Demonology with Summon Felguard needs a Felguard out, in PvE (pet),
--     items = IDs: what the spell makes, one of which is to be in the bags (make),
--     guide = function(side) -> IDs: what the guides recommend for this spec on "pve" or "pvp": the
--             spells a choose entry casts first, or the runes for the weapons (runeforge, with
--             runeSpells = { [enchant] = the spell that puts it on }),
--     slot = slot or function() -> slot, enchants = { [enchantID] = true } (imbue, runeforge),
--     label = locale key, for a reminder that stands for several spells }
-- "group": your buff on everyone near in a raid or Mythic+, on you anywhere
-- else. "buff": on yourself. "ally": yours on
-- someone else in the group. "avoid": a buff to drop (its name in red). "pet":
-- a pet out. "imbue": a temporary enchant of yours on a weapon (the weapon oil
-- reminder leaves that slot alone). "runeforge": a permanent enchant (a rune
-- another setup of yours had, still on, shows in red).
-- ===========================================================================

local SETTLE = 4     -- seconds after a loading screen before anything is judged
local KEY_RUN = 35 * 60   -- at a Mythic entrance, a consumable that would not last a key run counts as running out
local FOREVER = math.huge
local MYTHIC = 23    -- the Mythic dungeon difficulty, where keys are run
local KEYSTONE = 8   -- a key's own difficulty, still in force once it ends
local DEMONOLOGY = 266
ns.CUSTOM_MAX = 10   -- custom reminders per class

-- ---------------------------------------------------------------------------
-- Saved data (CombatKitReminderDB, account-wide)
-- ---------------------------------------------------------------------------

ns.defaults = {
	-- the scenario keys each kind shows in: your consumables, your class's reminders (and your custom
	-- ones), the group's feasts and cauldrons
	-- PvP: a healthstone only. Not in a battleground by default: a warlock is near in almost every one,
	-- a Soulwell rarely is.
	consumablesWhere = { dungeon = true, raid = true, arena = true, bg = false },
	classWhere  = { dungeon = true, raid = true, delve = true, world = true, arena = true, bg = true },
	sharedWhere = { dungeon = true, raid = true, bg = true },
	consumables = { flask = true, food = true, rune = true, oil = true, healthstone = true },
	-- per setup (spec and PvE or PvP), what you used last: ["<specID>/pve"] = { flask = aura,
	-- oil16 / oil17 = enchant, food = item, rune16 / rune17 = enchant, [a choose entry's key] = { spells } }
	used        = {},
	shared      = { feast = true, cauldron = true },
	off         = {},     -- class reminders switched off: [key] = true
	expiring    = 5,      -- minutes, 0 to 60: a buff with less left counts as missing; 0 = only when gone
	-- { { id=, when = "missing" | "present", who = "me" | "group", class = token }, ... }
	custom      = {},
	icons       = true,   -- the row of icons on screen
	hud         = false,  -- the same as rows on the HUD
	click       = true,   -- a click on an icon casts its spell or uses its item
	glow        = true,   -- thin dashes running round each icon
	sound       = "",     -- a SOUNDKIT key played when a reminder appears; "" = none
	size        = 54,
	-- centred, 140 below the top edge, kept from the top so a shorter screen has it too: clear of the
	-- score at the top of a battleground (80, where the user put it on 2026-11-03, sat on it)
	point = "CENTER", relPoint = "TOP", x = 0, y = -140,
	-- a hunter's or warlock's pet below `below` percent: a line of its own, in combat too: the icon
	-- (if asked) and the text beside it, the text as large as `fontSize`. Where the user dragged it
	-- on 2026-11-04, rounded: 370 above the middle of the screen.
	petHealth = { on = true, below = 40, icon = true, fontSize = 20, point = "CENTER", relPoint = "CENTER", x = 0, y = 370 },
}

-- Fill missing keys in `dst` from `defaults` (never overwrites existing values).
local function FillDefaults(dst, defaults)
	for k, v in pairs(defaults) do
		if type(v) == "table" then
			if type(dst[k]) ~= "table" then dst[k] = {} end
			FillDefaults(dst[k], v)
		elseif dst[k] == nil then
			dst[k] = v
		end
	end
	return dst
end

-- of the saved data: 2 made the icons half as large again (36 was the first default), 3 moved the row's
-- default place up from the middle of the screen (the centre, 140 up, was the first), 4 keeps what you
-- used per spec and PvE or PvP (it was per spec, which became PvE), 5 gives consumables and class
-- reminders a scenario list each (one list held both; dropped, the new lists start from their defaults),
-- 6 turns the healthstone off in battlegrounds (on from 1.5.0's default, a day before), 7 moves the
-- row's default place down, clear of a battleground's score (80 below the top was the default)
local VERSION = 7

local function InitDB()
	if type(CombatKitReminderDB) ~= "table" then CombatKitReminderDB = {} end
	local saved = CombatKitReminderDB
	local fresh = next(saved) == nil
	ns.db = FillDefaults(saved, ns.defaults)
	local was = saved.version or 1
	if not fresh and was < 2 and saved.size == 36 then saved.size = 54 end
	if not fresh and was < 3 and saved.relPoint == "CENTER" and saved.x == 0 and saved.y == 140 then
		saved.relPoint, saved.y = ns.defaults.relPoint, ns.defaults.y
	end
	if was < 4 then
		for k, v in pairs(saved.used) do
			if type(k) == "number" then
				saved.used[k .. "/pve"] = saved.used[k .. "/pve"] or v
				saved.used[k] = nil
			end
		end
	end
	if was < 5 then saved.where = nil end
	if not fresh and was < 6 then saved.consumablesWhere.bg = false end
	if not fresh and was < 7 and saved.point == "CENTER" and saved.relPoint == "TOP" and saved.x == 0 and saved.y == -80 then
		saved.y = ns.defaults.y
	end
	-- 0 to 60 minutes (it was 0 to 15)
	saved.expiring = math.max(0, math.min(60, tonumber(saved.expiring) or ns.defaults.expiring))
	saved.version = VERSION
end

-- ---------------------------------------------------------------------------
-- The checks: each answers whether its reminder shows, and what it says
-- ---------------------------------------------------------------------------

-- { { key=, group = "consumable" | "class", icon=, label=, action=,
--     Get = function(soon) -> show, text, warn, Applies = function() -> bool } }
local checks
local classEntries    -- the player's class list
local playerClass

local function Value(v)
	if type(v) == "function" then return v() end
	return v
end

local function TimeLeft(seconds)
	if seconds >= 60 then return string.format("%dm", math.ceil(seconds / 60)) end
	return string.format("%ds", math.ceil(seconds))
end

-- When to look again by itself: the earliest moment something crosses into
-- "running out", or a time shown on an icon wants its next minute. Each look
-- starts it afresh.
local due

local function Due(seconds)
	if seconds and seconds > 0 then due = due and math.min(due, seconds) or seconds end
end

-- Missing, or running out within `soon` seconds?
local function Judge(count, need, least, soon)
	if count == nil then return nil end
	if count < need then return true end
	if least and least ~= FOREVER then
		if least <= soon then
			Due(least > 60 and (least - 60 * math.floor(least / 60)) + 0.1 or 1)   -- the minute shown changes
			return true, TimeLeft(least)
		end
		Due(least - soon)
	end
end

-- Is the player in one of `ids` by the stance bar?
local function InForm(ids)
	local stance = ns.Stance()
	if stance == 0 then return false end
	for _, id in ipairs(ids) do
		if id == stance then return true end
	end
	return false
end

-- Does a class entry concern this character right now? Also returns its spell.
local function Applies(e)
	local spell = Value(e.spell)
	if not spell then return false end
	if e.known ~= false and not ns.Known(spell) then return false end
	if e.spec and not e.spec[ns.SpecID() or 0] then return false end
	if e.When and not e.When() then return false end
	return true, spell
end

-- PvE or PvP: arena and battlegrounds are PvP, everything else PvE. A spec
-- often brings other things to each (poisons, runes, a demon).
local function Side()
	local key = ns.Scenario()
	return (key == "arena" or key == "bg") and "pvp" or "pve"
end

-- Consumables are for PvE: in an arena or a battleground they are neither
-- shown nor learned from. A healthstone is the exception: it is taken from a
-- Soulwell in an arena too.
local function ForHere(c, side)
	return c.group ~= "consumable" or side == "pve" or c.key == "healthstone"
end

-- The setup in force: the spec and the side, "<specID>/pve"
local function Setup() return (ns.SpecID() or 0) .. "/" .. Side() end

-- What you used last in a setup (account-wide): learned from what is on you,
-- so that a click takes the same kind again and a rune of another setup is
-- told apart
local function Used(setup)
	setup = setup or Setup()
	local used = ns.db.used
	used[setup] = used[setup] or {}
	return used[setup]
end

-- The one of a "choose" entry's spells to cast next: one not on you yet,
-- those you had on last time in this setup first, then the guides', then the
-- list's order
local function Pick(e)
	local order, seen = {}, {}
	for _, id in ipairs(Used()[e.key] or {}) do order[#order + 1] = id end
	for _, id in ipairs(e.guide and e.guide(Side()) or {}) do order[#order + 1] = id end
	for _, id in ipairs(Value(e.auras)) do order[#order + 1] = id end
	local first
	for _, id in ipairs(order) do
		if not seen[id] and ns.Known(id) then
			seen[id] = true
			first = first or id
			if ns.PlayerAuras({ id }) == 0 then return id end
		end
	end
	return first
end

-- The one of an "options" entry's spells to cast: the one Prefer names (a Felguard for
-- Demonology), else the one you cast last in this setup, while you still know it
local function Chosen(e)
	local prefer = e.Prefer and e.Prefer(Side())
	if prefer then return prefer end
	local mine = (Used()[e.key] or {})[1]
	if mine and ns.Known(mine) then return mine end
end

-- Does a buff for the whole group have to be on everyone here? In a raid and in Mythic+ (a
-- Mythic dungeon, a key slotted or run) yes; anywhere else yours on you is enough: the buff was
-- put up, and whoever joined or died since is not worth an icon.
local function WholeGroup()
	local key = ns.Scenario()
	if key == "raid" then return true end
	if key ~= "dungeon" then return false end
	local _, _, difficultyID = GetInstanceInfo()
	if difficultyID == MYTHIC or difficultyID == KEYSTONE then return true end
	return C_ChallengeMode and CK.Flag(C_ChallengeMode.HasSlottedKeystone) or false
end
ns.WholeGroup = WholeGroup

local KINDS = {}

function KINDS.group(e, soon)
	local auras = Value(e.auras)
	if not WholeGroup() then
		local count, left = ns.PlayerAnyAura(auras)
		return Judge(count, 1, left, soon)
	end
	local missing, total = ns.GroupMissing(auras, soon)
	if not missing or missing == 0 then return nil end
	return true, total > 1 and tostring(missing) or nil
end

function KINDS.buff(e, soon)
	local auras = Value(e.auras)
	local count, least = ns.PlayerAuras(auras)
	if e.form and InForm(auras) then count = math.max(count or 0, 1) end
	local need = Value(e.need) or 1
	-- a choice made in full (every poison wanted is on): remembered for this spec
	if e.choose and count and need > 0 and count >= need then
		local on = {}
		for _, id in ipairs(auras) do
			if ns.PlayerAuras({ id }) == 1 then on[#on + 1] = id end
		end
		Used()[e.key] = on
	end
	return Judge(count, need, least, soon)
end

function KINDS.ally(e, soon, spell)
	if not ns.Grouped() then return nil end
	if e.cooldown then
		local cooling = ns.OnCooldown(spell)
		if cooling ~= false then
			Due(cooling and cooling + 0.5)   -- looked at again once it is back
			return nil
		end
	end
	local on, left = ns.OnAlly(Value(e.auras), e.self)
	if on == nil then return nil end
	return Judge(on and 1 or 0, 1, left, soon)
end

-- a spell that makes an item to carry (a warlock's healthstones): while none of them is in the bags
function KINDS.make(e)
	if not ns.InBags(Value(e.items)) then return true end
end

function KINDS.avoid(e)
	local auras = Value(e.auras)
	local count = ns.PlayerAuras(auras)
	if (count and count > 0) or (e.form and InForm(auras)) then return true, nil, true end
end

function KINDS.pet(e)
	-- on a mount the pet may be away (after a flight it comes back only once you get off), and
	-- the game brings it back by itself: nothing to remind of until you dismount
	if IsMounted and IsMounted() then return nil end
	if not ns.HasPet() then return true end
	-- Demonology with Summon Felguard: the demon out has to be a Felguard, in PvE (in PvP
	-- a warlock brings whichever demon the match wants)
	if e.felguard and Side() == "pve" and ns.SpecID() == DEMONOLOGY and ns.Known(ns.FELGUARD.summon) then
		local creature = ns.PetCreature()
		if creature and not ns.FELGUARD.creatures[creature] then
			return true, nil, true, L["Felguard"]
		end
	end
end

-- On either hand: which hand an imbue goes on is the game's business. Its
-- own buff counts as well, should the enchant not be read.
function KINDS.imbue(e, soon)
	if not ns.Weapon(Value(e.slot)) then return nil end
	local unknown, best = false, nil
	for _, slot in ipairs({ ns.MAIN, ns.OFF }) do
		if ns.Weapon(slot) then
			local id, left = ns.TempEnchant(slot)
			if id == nil or id == true then
				unknown = true   -- unreadable, or there but which one is hidden
			elseif id and e.enchants[id] then
				best = math.max(best or 0, left or FOREVER)
			end
		end
	end
	if not best and e.buffs then
		local count, least = ns.PlayerAuras(e.buffs)
		if count == nil then unknown = true elseif count > 0 then best = least or FOREVER end
	end
	if best then return Judge(1, 1, best, soon) end
	if not unknown then return true end
end

-- A rune, any rune; but one this setup did not have last time, which another
-- setup had (your other spec, or this spec's PvP or PvE), is still that
-- setup's: time to runeforge again
function KINDS.runeforge(e)
	if not ns.Weapon(e.slot) then return nil end
	local id = ns.PermanentEnchant(e.slot)
	if id == nil then return nil end
	if not e.enchants[id] then
		-- none: name the rune to put on, the one of last time, else the guides'
		local rune = Used()["rune" .. e.slot]
		if not rune and e.guide then
			local guide = e.guide(Side()) or {}
			local other = ns.PermanentEnchant(e.slot == ns.MAIN and ns.OFF or ns.MAIN)
			rune = guide[1]
			if #guide > 1 then
				-- a pair: whichever the other hand does not have yet
				if other == guide[1] then rune = guide[2]
				elseif other ~= guide[2] and e.slot == ns.OFF then rune = guide[2] end
			end
		end
		local spell = rune and e.runeSpells and e.runeSpells[rune]
		if spell then return true, nil, nil, ns.SpellName(spell), ns.SpellIcon(spell) end
		return true
	end
	local key, setup = "rune" .. e.slot, Setup()
	local mine = Used(setup)[key]
	if mine and id ~= mine then
		for other, u in pairs(ns.db.used) do
			if other ~= setup and u[key] == id then return true, nil, true, L["Rune to change"] end
		end
	end
	Used(setup)[key] = id
end

-- a click casts the spell, except where that would not help: a stance to leave, the Runeforge
local NO_CLICK = { avoid = true, runeforge = true }

-- A weapon slot one of the class's own imbues is meant for
local function Imbued(slot)
	for _, e in ipairs(classEntries) do
		if e.kind == "imbue" and Applies(e) and Value(e.slot) == slot then return true end
	end
	return false
end

local function Oil(slot)
	return function(soon)
		if not ns.db.consumables.oil then return nil end
		if not ns.Weapon(slot) or Imbued(slot) then return nil end
		local id, left = ns.TempEnchant(slot)
		if id == nil then return nil end
		if not id then return true end
		if ns.OIL.byEnchant[id] then Used()["oil" .. slot] = id end
		return Judge(1, 1, left, soon)
	end
end

local function FromBags(list) return function() return ns.ItemIcon(ns.InBags(list.items) or list.items[1]) end end
-- a click uses the first one in the bags; on a weapon slot, on that weapon
local function UseFromBags(list, slot)
	return function()
		local item = ns.InBags(list.items)
		return item and { kind = "item", id = item, slot = slot } or nil
	end
end

-- oil, stone or ammunition that goes on that weapon: the kind you used last
-- on that hand in this spec, else the first in the bags
local function OilFor(slot)
	local function Fits(item) return ns.Fits(item, slot) end
	local function Item()
		local mine = ns.OIL.byEnchant[Used()["oil" .. slot] or 0]
		return (mine and ns.InBags(mine, Fits)) or ns.InBags(ns.OIL.items, Fits)
	end
	return function() return ns.ItemIcon(Item() or ns.OIL.items[1]) end, function()
		local item = Item()
		return item and { kind = "item", id = item, slot = slot } or nil
	end
end

-- the flask you drank last in this spec (a fleeting one first), else the first in the bags
local function FlaskItem()
	local mine = ns.FLASK.byAura[Used().flask or 0]
	return (mine and ns.InBags(mine)) or ns.InBags(ns.FLASK.items)
end

-- the food you ate last in this spec, else the best in the bags
local function FoodItem()
	local mine = Used().food
	if mine and ns.InBags({ mine }) then return mine end
	return ns.InBags(ns.FOOD.items)
end

local function BuildChecks()
	checks = {}
	local function Add(key, group, icon, label, Get, action, applies)
		checks[#checks + 1] = { key = key, group = group, icon = icon, label = label, Get = Get, action = action,
			Applies = applies }
		return checks[#checks]
	end

	Add("flask", "consumable", function() return ns.ItemIcon(FlaskItem() or ns.FLASK.items[1]) end, L["Flask"], function(soon)
		if not ns.db.consumables.flask then return nil end
		local count, least = ns.PlayerAuras(ns.FLASK.auras)
		if count and count > 0 then
			for _, aura in ipairs(ns.FLASK.auras) do
				if ns.PlayerAuras({ aura }) == 1 then Used().flask = aura; break end
			end
		end
		return Judge(count, 1, least, soon)
	end, function()
		local item = FlaskItem()
		return item and { kind = "item", id = item } or nil
	end)
	Add("food", "consumable", function()
		local item = FoodItem()
		return item and ns.ItemIcon(item) or ns.FOOD_ICON
	end, L["Food"], function(soon)
		if not ns.db.consumables.food then return nil end
		local left, eating = ns.FoodState()
		if eating then   -- on its way; and now it is known what you eat
			local item = ns.FOOD.byEating[ns.EatingSpell() or 0]
			if item then Used().food = item end
			return nil
		end
		if left == nil then return nil end
		return Judge(left and 1 or 0, 1, left or nil, soon)
	end, function()
		local item = FoodItem()
		return item and { kind = "item", id = item } or nil
	end)
	Add("rune", "consumable", FromBags(ns.RUNE), L["Augment rune"], function(soon)
		if not ns.db.consumables.rune or not ns.InBags(ns.RUNE.items) then return nil end
		local count, least = ns.PlayerAuras(ns.RUNE.auras)
		return Judge(count, 1, least, soon)
	end, UseFromBags(ns.RUNE))
	local icon, action = OilFor(ns.MAIN)
	Add("oil", "consumable", icon, L["Weapon oil"], Oil(ns.MAIN), action)
	icon, action = OilFor(ns.OFF)
	Add("oil2", "consumable", icon, L["Off-hand oil"], Oil(ns.OFF), action)
	-- one to take from the warlock in the group (from the Soulwell: nothing to click); a warlock
	-- makes their own, which is a class reminder of theirs
	Add("healthstone", "consumable", FromBags(ns.HEALTHSTONE), L["Healthstone"], function()
		if not ns.db.consumables.healthstone or ns.InBags(ns.HEALTHSTONE.items) then return nil end
		if not ns.Known(ns.HEALTHSTONE.create) and ns.GroupHas("WARLOCK") then return true end
	end).note = L["TIP_SOULWELL"]

	-- the player's class: its list is made once, then the other classes' lists go
	local _, class = UnitClass("player")
	playerClass = class
	local make = ns.classes and ns.classes[class]
	classEntries = make and make() or {}
	ns.classes = nil
	for _, e in ipairs(classEntries) do
		local function Spell() return Value(e.spell) end
		local function Cast()
			if e.choose then return Pick(e) or Spell() end
			if e.options then return Chosen(e) or Spell() end
			return Spell()
		end
		local function Icon(spell)
			local look = e.Look and e.Look(spell)
			return look or ns.SpellIcon(spell)
		end
		local check = Add(e.key, "class",
			function() return Icon(Cast()) end,
			e.label and L[e.label] or function()
				local spell = Cast()
				return e.Name and e.Name(spell) or ns.SpellName(spell)
			end,
			function(soon)
				if ns.db.off[e.key] then return nil end
				local applies, spell = Applies(e)
				if not applies then return nil end
				return KINDS[e.kind](e, soon, spell)
			end,
			not NO_CLICK[e.kind] and function()
				local spell = Cast()
				local slot = e.kind == "imbue" and Value(e.slot) or nil
				return spell and { kind = "spell", id = spell, slot = slot } or nil
			end or nil,
			function() return (Applies(e)) end)
		check.warn = e.kind == "avoid"
		check.short = e.short and L[e.short]   -- the name above the icon, where the spell's is too long
		check.spec = e.spec
		check.kind = e.kind
		check.withPet = e.kind == "pet" or e.withPet   -- the settings page's pet section, where a class has one
		check.Spell = Spell
		check.Cast = Cast
		check.Title = e.Title and function() return e.Title(Cast()) end
		-- the others to pick from, known and not the one a click casts (nor, of poisons, one on you
		-- already): { { kind = "spell", id=, slot=, icon=, name= }, ... }
		if (e.options or e.choose) and not NO_CLICK[e.kind] then
			check.Options = function(current)
				local list = {}
				for _, id in ipairs(Value(e.options or e.auras) or {}) do
					if id ~= current and ns.Known(id) and not (e.choose and ns.PlayerAuras({ id }) == 1) then
						local icon, name = Icon(id), e.Look and select(2, e.Look(id)) or nil
						list[#list + 1] = { kind = "spell", id = id, icon = icon, name = name,
							slot = e.kind == "imbue" and Value(e.slot) or nil }
					end
				end
				return list
			end
		end
		-- the guides' names for this setup, for the settings page
		if e.guide then
			-- for your spec, or another (spec): yours as far as your talents go, another's as the guides have it.
			-- The names, and the first one's spell (its icon).
			check.Guide = function(spec)
				local mine = not spec or spec == ns.SpecID()
				local guide = e.guide(Side(), spec) or {}
				if e.runeSpells then
					-- the rune for this hand: of a pair, the first for the main hand, the second for the off hand;
					-- a single rune is for a two-hander, and leaves the off hand none
					local id = guide[e.slot == ns.OFF and 2 or 1]
					local spell = id and (e.runeSpells[id] or id)
					return spell and ns.SpellName(spell) or nil, spell
				end
				local names, first, want = {}, nil, mine and e.need and Value(e.need) or math.huge
				for _, id in ipairs(guide) do
					if (not mine or ns.Known(id)) and #names < want then
						names[#names + 1] = ns.SpellName(id)
						first = first or id
					end
				end
				return #names > 0 and table.concat(names, " + ") or nil, first
			end
		end
	end
end

-- Your class's reminders, for the settings (and AuraLab): { { key=, label=, icon=, spell=, now = applies
-- right now, on=, spec = { [specID] = true } for some specs only, else nil, kind=, withPet = listed with
-- the pet where the page has a pet section }, ... }
function ns.ClassItems()
	local items = {}
	for _, c in ipairs(checks) do
		if c.group == "class" then
			local now = c.Applies()
			-- the guides' pick only where it would be used now; and each spec's, for the page to show
			-- under that spec
			local guides, guideIcons
			if c.Guide then
				guides, guideIcons = {}, {}
				for _, s in ipairs(ns.ClassSpecs()) do
					if not c.spec or c.spec[s.id] then
						local text, spell = c.Guide(s.id)
						guides[s.id], guideIcons[s.id] = text, spell and ns.SpellIcon(spell)
					end
				end
			end
			items[#items + 1] = { key = c.key, label = Value(c.label), title = c.Title and c.Title(), icon = Value(c.icon),
			spell = c.Spell(), now = now,
				on = not ns.db.off[c.key], warn = c.warn, guide = now and c.Guide and c.Guide() or nil, guides = guides,
				guideIcons = guideIcons, spec = c.spec, kind = c.kind, withPet = c.withPet }
		end
	end
	return items
end

-- Is a pet of yours meant to be out (your class's pet reminder applies), and the class's
-- token: for the pet's health
function ns.PetExpected()
	for _, e in ipairs(classEntries or {}) do
		if e.kind == "pet" and (Applies(e)) then return true, playerClass end
	end
	return false, playerClass
end

-- The icon of one of your consumables (the one in your bags, else the kind's own), or of what the
-- group puts down, for the settings page
function ns.ConsumableIcon(key)
	for _, c in ipairs(checks) do
		if c.key == key then return Value(c.icon) end
	end
	local shared = (key == "feast" and ns.FEAST) or (key == "cauldron" and ns.CAULDRON)
	return shared and ns.ItemIcon(shared.items[1]) or nil
end

-- Your class's specs in the game's order: { { id=, name=, icon= }, ... }
function ns.ClassSpecs()
	local specs = {}
	for i = 1, 5 do
		-- past the last spec the client answers an empty record, or nothing
		local id, name, _, icon = C_SpecializationInfo.GetSpecializationInfo(i)
		if not id or id == 0 then break end
		specs[#specs + 1] = { id = id, name = name, icon = icon }
	end
	return specs
end

function ns.SetClassItem(key, on)
	ns.db.off[key] = (not on) or nil
	ns.Refresh()
end

-- ---------------------------------------------------------------------------
-- Custom reminders: spell IDs of the player's own, per class
-- ---------------------------------------------------------------------------

-- The custom reminders of the player's class
function ns.CustomList()
	local list = {}
	for _, c in ipairs(ns.db.custom) do
		if c.class == playerClass then list[#list + 1] = c end
	end
	return list
end

-- Adds one; returns nil, or why it was not added (a locale key)
function ns.AddCustom(id, when, who)
	id = tonumber(id)
	if not id or id <= 0 or not ns.SpellName(id) then return "No spell with that ID." end
	local mine = ns.CustomList()
	if #mine >= ns.CUSTOM_MAX then return "The list is full." end
	for _, c in ipairs(mine) do
		if c.id == id then return "Already in the list." end
	end
	table.insert(ns.db.custom, { id = id, when = when == "present" and "present" or "missing",
		who = who == "group" and "group" or "me", class = playerClass })
	ns.Refresh()
end

function ns.RemoveCustom(entry)
	for i, c in ipairs(ns.db.custom) do
		if c == entry then table.remove(ns.db.custom, i); break end
	end
	ns.Refresh()
end

-- show, text, warn for one custom reminder
local function Custom(c, soon)
	local ids = { c.id }
	-- one missing on the group follows the class's group buffs: everyone only in a raid or Mythic+
	if c.who == "group" and (c.when == "present" or WholeGroup()) then
		local missing, total = ns.GroupMissing(ids, c.when == "missing" and soon or 0)
		if missing == nil then return nil end
		if c.when == "missing" then
			if missing > 0 then return true, total > 1 and tostring(missing) or nil end
		elseif missing < total then
			return true, total > 1 and tostring(total - missing) or nil, true
		end
		return nil
	end
	local count, least = ns.PlayerAuras(ids)
	if c.when == "present" then
		if count and count > 0 then return true, nil, true end
		return nil
	end
	return Judge(count, 1, least, soon)
end

local function CustomGroup(whole)
	for _, c in ipairs(ns.CustomList()) do
		if c.who == "group" and (whole or c.when == "present") then return true end
	end
	return false
end

-- ---------------------------------------------------------------------------
-- When: the scenario, the visit, what keeps everything hidden
-- ---------------------------------------------------------------------------

local running = false
local loading = true       -- a loading screen was just passed
local pulled = false       -- combat was seen during this visit
local visit                -- the instance this visit is in
local readyCheck = false
local encounter = false    -- from ENCOUNTER_START: hidden at once, before combat lockdown
local pending = false
local plan = 0             -- the timer of the next look by itself; a newer one makes older ones void
local watching             -- what UNIT_AURA is registered for: nil, "player", "group"

function ns.IsRunning() return running end
function ns.Watching() return watching end

-- Instances scaled up to you whatever their age: Timewalking, a Mythic dungeon (the season's
-- keys take old dungeons too), a key (DifficultyUtil.ID)
local SCALED = { [MYTHIC] = true, [KEYSTONE] = true, [24] = true, [33] = true }

-- Below the top level the account reaches (levelling)? The level and the top, for /ckreminder
local function Levelling()
	local level = UnitLevel and UnitLevel("player")
	local top = GetMaxLevelForPlayerExpansion and GetMaxLevelForPlayerExpansion()
	if type(level) ~= "number" or type(top) ~= "number" or ns.Secret(level) or ns.Secret(top) then return false end
	return level > 0 and level < top, level, top
end

-- A dungeon or raid far below you: any of them while you level, or one the game gives legacy
-- loot in (two expansions back or more, outlevelled) unless it is scaled up to you
local function Low()
	if Levelling() then return true end
	local _, _, difficultyID = GetInstanceInfo()
	if SCALED[difficultyID] then return false end
	return C_Loot and CK.Flag(C_Loot.IsLegacyLootModeEnabled) or false
end

-- The kit's scenario; grouped players in the 12.x hub cities read as being in
-- a dungeon of difficulty 0, which is no dungeon. A dungeon or raid far below
-- you plays as the open world: no consumables, the class reminders as there.
function ns.Scenario()
	local key = CK.DetectScenario()
	if key == "dungeon" then
		local _, _, difficultyID = GetInstanceInfo()
		if not difficultyID or difficultyID == 0 then return "world" end
	end
	if (key == "dungeon" or key == "raid") and Low() then return "world" end
	return key
end

-- What keeps the reminders hidden right now, or nil
local function Blocked()
	if loading then return "loading screen" end
	if InCombatLockdown() or UnitAffectingCombat("player") then return "combat" end
	if UnitIsDeadOrGhost("player") then return "dead" end
	if (UnitInVehicle and UnitInVehicle("player")) or (UnitOnTaxi and UnitOnTaxi("player")) then return "vehicle or flight" end
	if IsFlying and IsFlying() then return "flying" end
	if encounter then return "encounter" end
	if C_ChallengeMode and CK.Flag(C_ChallengeMode.IsChallengeModeActive) then return "key running" end
	if CK.Flag(IsEncounterInProgress) then return "encounter" end
	-- last: a resting area hides all but what belongs there (RESTING)
	if IsResting() then return "resting area" end
	return nil
end

-- What still shows in a resting area (a city, an inn): a death knight's runes, which
-- are put on at leisure, out of any fight, and last until changed
local RESTING = { runeforge = true }

local driver = CreateFrame("Frame")

-- Everyone's auras matter for a buff put on others, a custom one present on the group, and,
-- where it has to be on everyone, a group buff or a custom one missing on the group
local function GroupAuras()
	local db = ns.db
	local whole = WholeGroup()
	for _, e in ipairs(classEntries) do
		if (e.kind == "ally" or (e.kind == "group" and whole)) and not db.off[e.key] then return true end
	end
	return CustomGroup(whole)
end

-- UNIT_AURA only while there is something to look at: in a scenario that
-- shows reminders, out of combat
local function Watch(on)
	local want = on and (GroupAuras() and "group" or "player") or nil
	if want == watching then return end
	watching = want
	driver:UnregisterEvent("UNIT_AURA")
	if want == "group" then
		driver:RegisterEvent("UNIT_AURA")
	elseif want == "player" then
		driver:RegisterUnitEvent("UNIT_AURA", "player")
	end
end

local function Plan()
	plan = plan + 1
	if not due then return end
	local mine = plan
	C_Timer.After(due, function()
		if plan == mine then ns.Queue(0) end
	end)
end

-- How far ahead "running out" looks right now: for everything, and for the
-- consumables, which at a Mythic entrance (before the first pull) look as far
-- ahead as a key run: what would run out during the key is topped up now.
-- Class buffs keep the usual window: a Soulstone never lasts a key run.
local function Soon(key)
	local soon = ns.db.expiring * 60
	local consumable = soon
	if soon > 0 and key == "dungeon" and not pulled then
		local _, _, difficultyID = GetInstanceInfo()
		local slotted = C_ChallengeMode and CK.Flag(C_ChallengeMode.HasSlottedKeystone)
		if difficultyID == MYTHIC or slotted then consumable = math.max(soon, KEY_RUN) end
	end
	return soon, consumable
end

-- What one icon shows. `tip`: what its tooltip describes ({ kind=, id= }), whether or not a
-- click uses it; none where the check names something else (a rune to put on).
-- `options`: the others a click could cast instead, for the chooser. `note`: what to do where a
-- click does nothing (a healthstone is taken from the Soulwell).
local function Entry(c, text, warn, label, icon)
	local act = c.action and c.action() or nil
	local tip = act
	if not tip and c.Cast and not (label or icon) then
		local spell = c.Cast()
		tip = spell and { kind = "spell", id = spell } or nil
	end
	local action = ns.db.click and act or nil
	return { key = c.key, icon = icon or Value(c.icon), label = label or c.short or Value(c.label), text = text, warn = warn,
		action = action, tip = tip, kind = c.kind or c.group, note = c.note,
		options = action and c.Options and c.Options(action.id) or nil }
end

local function Evaluate()
	pending = false
	if not running then return end
	local db = ns.db
	local key = ns.Scenario()
	local consumablesHere = db.consumablesWhere[key] and true or false
	local classHere = db.classWhere[key] and true or false
	local shared = db.sharedWhere[key] and (db.shared.feast or db.shared.cauldron) and true or false
	Watch((consumablesHere or classHere or shared) and not InCombatLockdown())
	due = nil
	local blocked = Blocked()
	local resting = blocked == "resting area"
	if blocked and not (resting and classHere) then
		Plan()
		ns.ShowReminders({}, true)   -- hidden for now, not gone: no sound when they come back
		return
	end
	if resting then
		-- only what belongs in a city or an inn
		consumablesHere, shared = false, false
	end
	if key == "bg" and pulled then
		-- a battleground: before the gates open and once after each death, until the next fight;
		-- the group's feast or cauldron still the moment it goes down
		consumablesHere, classHere = false, false
	end
	-- the group's feast or cauldron first: that is where to go now
	local list, up = {}, {}
	if shared then ns.SharedReminders(key, list, up) end
	if consumablesHere or classHere then
		local soon, consumable = Soon(key)
		-- a raid: whenever combat ends
		local consumables = consumablesHere and (not pulled or readyCheck or key == "raid")
		local side = Side()
		for _, c in ipairs(checks) do
			-- your own food or flask steps aside while the group's is down
			local aside = (c.key == "food" and up.feast) or (c.key == "flask" and up.cauldron)
			local here = c.group == "consumable" and consumables or c.group == "class" and classHere
			if resting and not RESTING[c.kind] then here = false end
			if here and ForHere(c, side) and not aside then
				local show, text, warn, label, icon = c.Get(c.group == "consumable" and consumable or soon)
				if show then list[#list + 1] = Entry(c, text, warn, label, icon) end
			end
		end
		-- custom reminders sit on the class page, and follow its scenarios (not in a resting area)
		for _, c in ipairs(classHere and not resting and ns.CustomList() or {}) do
			local show, text, warn = Custom(c, soon)
			if show then
				list[#list + 1] = { key = "custom" .. c.id, icon = ns.SpellIcon(c.id), label = ns.SpellName(c.id),
					text = text, warn = warn, tip = { kind = "spell", id = c.id }, kind = "custom",
					action = db.click and c.when == "missing" and ns.Known(c.id) and { kind = "spell", id = c.id } or nil }
			end
		end
	end
	for _, r in ipairs(list) do
		if r.expires then Due(r.expires - GetTime() + 0.5) end
	end
	Plan()
	ns.ShowReminders(list)
end

-- Look again shortly; whatever else asks meanwhile is answered by the same look
function ns.Queue(delay)
	if pending or not running then return end
	pending = true
	C_Timer.After(delay or 0.2, Evaluate)
end

-- after a change of the settings: at once
function ns.Refresh()
	pending = false
	Evaluate()
end

-- ---------------------------------------------------------------------------
-- /ckreminder: what the module sees, to check it in game
-- ---------------------------------------------------------------------------

local function Yes(v) return v and "yes" or "no" end

function ns.Report()
	local say = CK.Msg
	if not running then
		say("Reminder is off.")
		return
	end
	local db = ns.db
	local key = ns.Scenario()
	local _, instanceType, difficultyID = GetInstanceInfo()
	say("scenario %s (%s, difficulty %s); here: consumables %s, class %s, the group's feasts and cauldrons %s", key,
		tostring(instanceType), tostring(difficultyID), Yes(db.consumablesWhere[key]), Yes(db.classWhere[key]),
		Yes(db.sharedWhere[key]))
	say("hidden by: %s; first combat seen: %s; ready check: %s; consumables now: %s; consumables running out within %d min",
		Blocked() or "nothing", Yes(pulled), Yes(readyCheck),
		Yes(not pulled or readyCheck or key == "raid"), math.floor(select(2, Soon(key)) / 60))
	say("group buffs wanted on: %s; auras listened to: %s", WholeGroup() and "everyone" or "you", tostring(watching or "none"))
	local levelling, level, top = Levelling()
	say("far below you (plays as the open world): levelling %s (level %s of %s), legacy loot %s",
		Yes(levelling), tostring(level), tostring(top), Yes(C_Loot and CK.Flag(C_Loot.IsLegacyLootModeEnabled)))
	say("auras secret as a whole: %s; per spell (%s): flask %s, Well Fed %s", Yes(ns.AurasHidden()),
		(C_Secrets and C_Secrets.ShouldSpellAuraBeSecret) and "asked" or "no such API",
		Yes(ns.SpellHidden(ns.FLASK.auras[1])), Yes(ns.SpellHidden(ns.WELL_FED[1])))
	local soon, consumable = Soon(key)
	local side = Side()
	for _, c in ipairs(checks) do
		local state
		if not ForHere(c, side) then
			state = "PvE only"
		elseif c.Applies and not c.Applies() then
			state = "not for you now"
		else
			local show, text, warn = c.Get(c.group == "consumable" and consumable or soon)
			state = show and ("SHOWS" .. (text and (" " .. text) or "") .. (warn and " (red)" or "")) or "fine or cannot tell"
		end
		say("  %s: %s", tostring(Value(c.label)), state)
	end
	for _, c in ipairs(ns.CustomList()) do
		local show, text = Custom(c, soon)
		say("  %s (custom %d): %s", tostring(ns.SpellName(c.id)), c.id, show and ("SHOWS" .. (text and (" " .. text) or "")) or "fine or cannot tell")
	end
	for _, slot in ipairs({ ns.MAIN, ns.OFF }) do
		local id, left = ns.TempEnchant(slot)
		say("temporary enchant on slot %d: %s%s", slot, tostring(id), left and string.format(" (%d s)", left) or "")
	end
	say("enchant API: %s; old one: %s", (C_PaperDollInfo and C_PaperDollInfo.GetTemporaryEnchantmentInfo) and "yes" or "no",
		GetWeaponEnchantInfo and "still there" or "gone")
	say("stance bar: %s", tostring(ns.Stance()))
	for _, slot in ipairs({ ns.MAIN, ns.OFF }) do
		if ns.Weapon(slot) then say("permanent enchant on slot %d: %s", slot, tostring(ns.PermanentEnchant(slot))) end
	end
	local parts = {}
	for k, v in pairs(Used()) do
		parts[#parts + 1] = k .. " " .. (type(v) == "table" and table.concat(v, "+") or tostring(v))
	end
	table.sort(parts)
	say("remembered for this spec: %s", #parts > 0 and table.concat(parts, ", ") or "nothing yet")
	local food, eating = ns.FoodState()
	say("food buff: %s; eating: %s", food == nil and "cannot tell" or food == false and "none"
		or food == FOREVER and "there (time hidden)" or (math.floor(food / 60) .. " min left"), Yes(eating))
	-- the two ways a feast or cauldron is seen going down; which of them works is still to be learned
	local seen = ns.LastSeen()
	if seen.chat then
		say("last feast or cauldron in chat: %s, item %d, %d s ago: %s", seen.chat.event, seen.chat.item,
			math.floor(GetTime() - seen.chat.at), seen.chat.line)
	else
		say("no feast or cauldron seen in chat this session")
	end
	if seen.cast then
		say("last feast or cauldron cast: by %s, item %d, %d s ago", seen.cast.unit, seen.cast.item, math.floor(GetTime() - seen.cast.at))
	else
		say("no feast or cauldron cast seen this session")
	end
end

SLASH_CKREMINDER1 = "/ckreminder"
SlashCmdList.CKREMINDER = function() ns.Report() end

-- ---------------------------------------------------------------------------
-- Events
-- ---------------------------------------------------------------------------

local EVENTS = {
	"PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA",
	"PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED",
	"PLAYER_DEAD", "PLAYER_ALIVE", "PLAYER_UNGHOST", "PLAYER_UPDATE_RESTING",
	"UNIT_INVENTORY_CHANGED", "PLAYER_EQUIPMENT_CHANGED", "UNIT_PET", "BAG_UPDATE_DELAYED",
	"GROUP_ROSTER_UPDATE", "PLAYER_SPECIALIZATION_CHANGED", "TRAIT_CONFIG_UPDATED", "SPELLS_CHANGED",
	"UPDATE_SHAPESHIFT_FORM", "READY_CHECK", "READY_CHECK_FINISHED",
	"CHALLENGE_MODE_START", "CHALLENGE_MODE_COMPLETED", "ENCOUNTER_START", "ENCOUNTER_END",
	"UNIT_ENTERED_VEHICLE", "UNIT_EXITED_VEHICLE", "PLAYER_CONTROL_LOST", "PLAYER_CONTROL_GAINED",
	"PLAYER_MOUNT_DISPLAY_CHANGED",
	-- what makes an instance far below you: the top level reached, legacy loot rules coming in late
	"PLAYER_LEVEL_UP", "LEGACY_LOOT_RULES_CHANGED",
}

local handlers = {}

function handlers.PLAYER_ENTERING_WORLD()
	local name, _, _, _, _, _, _, instanceID = GetInstanceInfo()
	local here = tostring(instanceID or name)
	if here ~= visit then visit, pulled = here, false end
	loading, encounter = true, false
	ns.ShowReminders({}, true)
	-- auras, spells and the instance can lag behind the loading screen
	C_Timer.After(SETTLE, function()
		loading = false
		ns.Queue(0)
	end)
end

function handlers.PLAYER_REGEN_DISABLED()
	pulled = true
	Watch(false)
	ns.ClearClicks()             -- still allowed here: combat lockdown starts right after
	ns.ShowReminders({}, true)   -- at once: nothing shows in combat
end

-- back from a battleground's graveyard: one more look, until the next fight
function handlers.PLAYER_DEAD()
	if ns.Scenario() == "bg" then pulled = false end
	ns.Queue(0.5)
end

function handlers.PLAYER_REGEN_ENABLED()
	ns.ClearClicks()   -- buttons that could not be hidden as combat began
	ns.Queue(1)
end

function handlers.ENCOUNTER_START()
	encounter = true
	ns.ClearClicks()
	ns.ShowReminders({}, true)
end

function handlers.ENCOUNTER_END()
	encounter = false
	ns.Queue(1)
end

function handlers.READY_CHECK()
	readyCheck = true
	ns.Queue(0)
end

function handlers.READY_CHECK_FINISHED()
	readyCheck = false
	ns.Queue(0)
end

local function Mine(unit) return unit == "player" end
local function Grouped(unit)
	return unit:find("^party%d") ~= nil or unit:find("^raid%d") ~= nil
end

-- the group's auras change all the time in a raid: those are looked at once a second at most
function handlers.UNIT_AURA(unit)
	if Mine(unit) then ns.Queue(0.3) elseif Grouped(unit) then ns.Queue(1) end
end
function handlers.UNIT_INVENTORY_CHANGED(unit) if Mine(unit) then ns.Queue(0.3) end end
function handlers.UNIT_PET(unit) if Mine(unit) then ns.Queue(0.5) end end

-- your own casts (registered for the player alone): one of an "options" entry's spells is the
-- one to cast next time in this setup, however it was cast (the icon, the chooser, a key)
function handlers.UNIT_SPELLCAST_SUCCEEDED(unit, _, spell)
	if not Mine(unit) or type(spell) ~= "number" or ns.Secret(spell) then return end
	for _, e in ipairs(classEntries or {}) do
		for _, id in ipairs(e.options and Value(e.options) or {}) do
			if id == spell then
				Used()[e.key] = { spell }
				ns.Queue(0.3)
				return
			end
		end
	end
end
function handlers.UNIT_ENTERED_VEHICLE(unit) if Mine(unit) then ns.Queue(0.3) end end
handlers.UNIT_EXITED_VEHICLE = handlers.UNIT_ENTERED_VEHICLE

driver:SetScript("OnEvent", function(_, event, ...)
	if handlers[event] then
		handlers[event](...)
	else
		ns.Queue(0.5)
	end
end)

-- ---------------------------------------------------------------------------
-- Module on / off
-- ---------------------------------------------------------------------------

local function SharedOn() return ns.db.shared.feast or ns.db.shared.cauldron end

-- a switch for the group's feasts or cauldrons, from the settings
function ns.SetShared(kind, on)
	ns.db.shared[kind] = on and true or false
	ns.SetSharedListening(running and SharedOn())
	ns.Refresh()
end

function ns.OnEnable()
	if not ns.db then InitDB() end
	if not checks then BuildChecks() end
	running = true
	watching = nil
	-- an event this client does not know raises an error on registration
	for _, e in ipairs(EVENTS) do pcall(driver.RegisterEvent, driver, e) end
	pcall(driver.RegisterUnitEvent, driver, "UNIT_SPELLCAST_SUCCEEDED", "player")
	ns.SetSharedListening(SharedOn())
	ns.PetHealthStart(true)
	CK.HUD.AddSection(ns.hudSection)
	-- switched on mid-session there is no loading screen to wait for
	loading = false
	ns.Queue(1)
end

function ns.OnDisable()
	running = false
	driver:UnregisterAllEvents()
	watching = nil
	ns.SetSharedListening(false)
	ns.PetHealthStart(false)
	ns.SetLocked(true)
	ns.SetTesting(false)
	ns.ShowReminders({})
	CK.HUD.RemoveSection(ns.hudSection.key)
end
