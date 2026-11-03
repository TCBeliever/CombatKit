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
-- own, and your own spell IDs (custom) whenever they are missing. A buff with
-- less than a few minutes left counts as missing. What the group puts down
-- (a feast, a flask cauldron) is Shared.lua's. Nothing in combat, while dead,
-- in a vehicle or on a flight, in a resting area, in a running key or
-- encounter, or right after a loading screen; only in the scenarios the
-- player picked.
--
-- A class list (Classes/*.lua) holds entries:
--   { key = what its switch is saved under,
--     kind = "group" | "buff" | "ally" | "avoid" | "pet" | "imbue" | "runeforge",
--     spell = ID or function() -> ID: the icon, the name, what has to be known
--             and what a click casts,
--     known = false: nothing to be known first,
--     spec = { [specID] = true }, When = function() -> bool: more conditions,
--     auras = IDs or function() -> IDs (group, buff, ally, avoid),
--     need = n or function() -> n: how many of the auras (buff; 1),
--     form = true: the stance bar counts as well as the aura (buff, avoid),
--     cooldown = true: not while the spell cools down (ally), self = true: on yourself counts (ally),
--     slot = slot or function() -> slot, enchants = { [enchantID] = true } (imbue, runeforge),
--     label = locale key, for a reminder that stands for several spells }
-- "group": your buff on everyone near. "buff": on yourself. "ally": yours on
-- someone else in the group. "avoid": a buff to drop (its name in red). "pet":
-- a pet out. "imbue": a temporary enchant of yours on a weapon (the weapon oil
-- reminder leaves that slot alone). "runeforge": a permanent enchant.
-- ===========================================================================

local SETTLE = 4     -- seconds after a loading screen before anything is judged
local KEY_RUN = 35 * 60   -- at a Mythic entrance, a consumable that would not last a key run counts as running out
local FOREVER = math.huge
local MYTHIC = 23    -- the Mythic dungeon difficulty, where keys are run
ns.CUSTOM_MAX = 10   -- custom reminders per class

-- ---------------------------------------------------------------------------
-- Saved data (CombatKitReminderDB, account-wide)
-- ---------------------------------------------------------------------------

ns.defaults = {
	where       = { dungeon = true, raid = true },              -- scenario keys your reminders show in
	sharedWhere = { dungeon = true, raid = true, bg = true },   -- and the group's feasts and cauldrons
	consumables = { flask = true, food = true, rune = true, oil = true, healthstone = true },
	raidAgain   = true,   -- in a raid the consumables show again whenever combat ends
	shared      = { feast = true, cauldron = true },
	off         = {},     -- class reminders switched off: [key] = true
	expiring    = 5,      -- minutes: a buff with less left counts as missing; 0 = only when gone
	-- { { id=, when = "missing" | "present", who = "me" | "group", class = token }, ... }
	custom      = {},
	icons       = true,   -- the row of icons on screen
	hud         = false,  -- the same as rows on the HUD
	click       = true,   -- a click on an icon casts its spell or uses its item
	sound       = "",     -- a SOUNDKIT key played when a reminder appears; "" = none
	size        = 36,
	point = "CENTER", relPoint = "CENTER", x = 0, y = 140,
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

local function InitDB()
	if type(CombatKitReminderDB) ~= "table" then CombatKitReminderDB = {} end
	ns.db = FillDefaults(CombatKitReminderDB, ns.defaults)
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

local KINDS = {}

function KINDS.group(e, soon)
	local missing, total = ns.GroupMissing(Value(e.auras), soon)
	if not missing or missing == 0 then return nil end
	return true, total > 1 and tostring(missing) or nil
end

function KINDS.buff(e, soon)
	local auras = Value(e.auras)
	local count, least = ns.PlayerAuras(auras)
	if e.form and InForm(auras) then count = math.max(count or 0, 1) end
	return Judge(count, Value(e.need) or 1, least, soon)
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

function KINDS.avoid(e)
	local auras = Value(e.auras)
	local count = ns.PlayerAuras(auras)
	if (count and count > 0) or (e.form and InForm(auras)) then return true, nil, true end
end

function KINDS.pet()
	if not ns.HasPet() then return true end
end

function KINDS.imbue(e, soon)
	local slot = Value(e.slot)
	if not ns.Weapon(slot) then return nil end
	local id, left = ns.TempEnchant(slot)
	if id == nil or id == true then return nil end   -- unreadable, or there but which one is hidden
	if not id or not e.enchants[id] then return true end
	return Judge(1, 1, left, soon)
end

function KINDS.runeforge(e)
	if not ns.Weapon(e.slot) then return nil end
	local id = ns.PermanentEnchant(e.slot)
	if id ~= nil and not e.enchants[id] then return true end
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

-- oil, stone or ammunition: the first in the bags that goes on that weapon
local function OilFor(slot)
	local function Fits(item) return ns.Fits(item, slot) end
	return function()
		local item = ns.InBags(ns.OIL.items, Fits)
		return ns.ItemIcon(item or ns.OIL.items[1])
	end, function()
		local item = ns.InBags(ns.OIL.items, Fits)
		return item and { kind = "item", id = item, slot = slot } or nil
	end
end

local function BuildChecks()
	checks = {}
	local function Add(key, group, icon, label, Get, action, applies)
		checks[#checks + 1] = { key = key, group = group, icon = icon, label = label, Get = Get, action = action,
			Applies = applies }
	end

	Add("flask", "consumable", FromBags(ns.FLASK), L["Flask"], function(soon)
		if not ns.db.consumables.flask then return nil end
		local count, least = ns.PlayerAuras(ns.FLASK.auras)
		return Judge(count, 1, least, soon)
	end, UseFromBags(ns.FLASK))
	Add("food", "consumable", ns.FOOD_ICON, L["Food"], function(soon)
		if not ns.db.consumables.food then return nil end
		local left, eating = ns.FoodState()
		if left == nil or eating then return nil end   -- eating: on its way
		return Judge(left and 1 or 0, 1, left or nil, soon)
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
	-- a warlock makes their own; anyone else takes one from the warlock in the group
	Add("healthstone", "consumable", FromBags(ns.HEALTHSTONE), L["Healthstone"], function()
		if not ns.db.consumables.healthstone or ns.InBags(ns.HEALTHSTONE.items) then return nil end
		if ns.Known(ns.HEALTHSTONE.create) or ns.GroupHas("WARLOCK") then return true end
	end, function()
		if ns.Known(ns.HEALTHSTONE.create) then return { kind = "spell", id = ns.HEALTHSTONE.create } end
	end)

	-- the player's class: its list is made once, then the other classes' lists go
	local _, class = UnitClass("player")
	playerClass = class
	local make = ns.classes and ns.classes[class]
	classEntries = make and make() or {}
	ns.classes = nil
	for _, e in ipairs(classEntries) do
		local function Spell() return Value(e.spell) end
		Add(e.key, "class",
			function() return ns.SpellIcon(Spell()) end,
			e.label and L[e.label] or function() return ns.SpellName(Spell()) end,
			function(soon)
				if ns.db.off[e.key] then return nil end
				local applies, spell = Applies(e)
				if not applies then return nil end
				return KINDS[e.kind](e, soon, spell)
			end,
			not NO_CLICK[e.kind] and function()
				local spell = Spell()
				local slot = e.kind == "imbue" and Value(e.slot) or nil
				return spell and { kind = "spell", id = spell, slot = slot } or nil
			end or nil,
			function() return (Applies(e)) end)
	end
end

-- Your class's reminders, for the settings: { { key=, label=, icon=, now = applies right now, on= }, ... }
function ns.ClassItems()
	local items = {}
	for _, c in ipairs(checks) do
		if c.group == "class" then
			items[#items + 1] = { key = c.key, label = Value(c.label), icon = Value(c.icon), now = c.Applies(),
				on = not ns.db.off[c.key] }
		end
	end
	return items
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
	if c.who == "group" then
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

local function CustomGroup()
	for _, c in ipairs(ns.CustomList()) do
		if c.who == "group" then return true end
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

-- The kit's scenario; grouped players in the 12.x hub cities read as being in
-- a dungeon of difficulty 0, which is no dungeon
function ns.Scenario()
	local key = CK.DetectScenario()
	if key == "dungeon" then
		local _, _, difficultyID = GetInstanceInfo()
		if not difficultyID or difficultyID == 0 then return "world" end
	end
	return key
end

-- What keeps the reminders hidden right now, or nil
local function Blocked()
	if loading then return "loading screen" end
	if InCombatLockdown() or UnitAffectingCombat("player") then return "combat" end
	if UnitIsDeadOrGhost("player") then return "dead" end
	if (UnitInVehicle and UnitInVehicle("player")) or (UnitOnTaxi and UnitOnTaxi("player")) then return "vehicle or flight" end
	if IsResting() then return "resting area" end
	if IsFlying and IsFlying() then return "flying" end
	if encounter then return "encounter" end
	if C_ChallengeMode and CK.Flag(C_ChallengeMode.IsChallengeModeActive) then return "key running" end
	if CK.Flag(IsEncounterInProgress) then return "encounter" end
	return nil
end

local driver = CreateFrame("Frame")

-- Everyone's auras matter for a group buff, a buff put on others, a custom one on the group
local function GroupAuras()
	local db = ns.db
	for _, e in ipairs(classEntries) do
		if (e.kind == "group" or e.kind == "ally") and not db.off[e.key] then return true end
	end
	return CustomGroup()
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

local function Entry(c, text, warn)
	local action = c.action and ns.db.click and c.action() or nil
	return { key = c.key, icon = Value(c.icon), label = Value(c.label), text = text, warn = warn, action = action }
end

local function Evaluate()
	pending = false
	if not running then return end
	local db = ns.db
	local key = ns.Scenario()
	local reminders = db.where[key] and true or false
	local shared = db.sharedWhere[key] and (db.shared.feast or db.shared.cauldron) and true or false
	Watch((reminders or shared) and not InCombatLockdown())
	due = nil
	if Blocked() then
		Plan()
		ns.ShowReminders({}, true)   -- hidden for now, not gone: no sound when they come back
		return
	end
	-- the group's feast or cauldron first: that is where to go now
	local list, up = {}, {}
	if shared then ns.SharedReminders(key, list, up) end
	if reminders then
		local soon, consumable = Soon(key)
		local consumables = not pulled or readyCheck or (db.raidAgain and key == "raid")
		for _, c in ipairs(checks) do
			-- your own food or flask steps aside while the group's is down
			local aside = (c.key == "food" and up.feast) or (c.key == "flask" and up.cauldron)
			if (c.group == "class" or consumables) and not aside then
				local show, text, warn = c.Get(c.group == "consumable" and consumable or soon)
				if show then list[#list + 1] = Entry(c, text, warn) end
			end
		end
		for _, c in ipairs(ns.CustomList()) do
			local show, text, warn = Custom(c, soon)
			if show then
				list[#list + 1] = { key = "custom" .. c.id, icon = ns.SpellIcon(c.id), label = ns.SpellName(c.id),
					text = text, warn = warn,
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
	say("scenario %s (%s, difficulty %s); your reminders here: %s, the group's feasts and cauldrons here: %s", key,
		tostring(instanceType), tostring(difficultyID), Yes(db.where[key]), Yes(db.sharedWhere[key]))
	say("hidden by: %s; first combat seen: %s; ready check: %s; consumables now: %s; consumables running out within %d min",
		Blocked() or "nothing", Yes(pulled), Yes(readyCheck),
		Yes(not pulled or readyCheck or (db.raidAgain and key == "raid")), math.floor(select(2, Soon(key)) / 60))
	say("auras secret as a whole: %s; per spell (%s): flask %s, Well Fed %s", Yes(ns.AurasHidden()),
		(C_Secrets and C_Secrets.ShouldSpellAuraBeSecret) and "asked" or "no such API",
		Yes(ns.SpellHidden(ns.FLASK.auras[1])), Yes(ns.SpellHidden(ns.WELL_FED[1])))
	local soon, consumable = Soon(key)
	for _, c in ipairs(checks) do
		local state
		if c.Applies and not c.Applies() then
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
	ns.SetSharedListening(SharedOn())
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
	ns.SetLocked(true)
	ns.SetTesting(false)
	ns.ShowReminders({})
	CK.HUD.RemoveSection(ns.hudSection.key)
end
