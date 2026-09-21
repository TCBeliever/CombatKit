local ADDON, ns = ...
local CK = CombatKit
local L = CK.L

CK.NewModule("Stats", ns)

-- ===========================================================================
-- Your stats as lines on the HUD.
--
-- Since 12.0.5 the player's own stat APIs return "secret" numbers while unit
-- stats are restricted (combat, encounters, Mythic+, PvP matches). Addon code
-- may not compute with a secret, compare it or format it, but it may hand it
-- to FontString:SetFormattedText and let the game format it. So:
--   * a value that comes straight from one API stays live in combat: the HUD
--     row carries { fmt, num } and the number is never looked at here;
--   * a value that needs arithmetic (movement speed, picking the highest crit)
--     is worked out while it is readable and shown from memory while it is not.
-- ===========================================================================

local function IsSecret(v) return issecretvalue ~= nil and issecretvalue(v) end

-- First two returns of an API that may not exist on this client
local function Call(fn, ...)
	if type(fn) ~= "function" then return nil end
	local ok, a, b = pcall(fn, ...)
	if not ok then return nil end
	return a, b
end
local function Call3(fn, ...)
	if type(fn) ~= "function" then return nil end
	local ok, a, b, c = pcall(fn, ...)
	if not ok then return nil end
	return a, b, c
end

local BASE_SPEED = BASE_MOVEMENT_SPEED or 7
local CR_VERS = CR_VERSATILITY_DAMAGE_DONE or 29

local critSource = "melee"   -- which crit was highest the last time all three could be read
local CRIT = {
	spell  = function() return Call(GetSpellCritChance, 2) end,
	melee  = function() return Call(GetCritChance) end,
	ranged = function() return Call(GetRangedCritChance) end,
}

-- Movement speed as a percentage of the normal run speed. While moving: how
-- fast you are. Skyriding has its own source, GetUnitSpeed says 0 there. Standing
-- still: how fast you would be, which is what the character sheet shows.
local function SpeedPercent()
	if type(GetUnitSpeed) ~= "function" then return nil end
	local ok, current, run, flight, swim = pcall(GetUnitSpeed, "player")
	if not ok or current == nil or IsSecret(current) then return current end
	local speed = current
	local gliding, _, forward = Call3(C_PlayerInfo and C_PlayerInfo.GetGlidingInfo)
	if not IsSecret(gliding) and gliding and forward and not IsSecret(forward) then
		speed = forward
	elseif current == 0 then
		local vehicle = Call(GetUnitSpeed, "vehicle")
		if vehicle and not IsSecret(vehicle) and vehicle > 0 then speed = vehicle
		elseif Call(IsFlying) then speed = flight
		elseif Call(IsSwimming) then speed = swim
		else speed = run end
	end
	if speed == nil or IsSecret(speed) then return speed end
	return speed / BASE_SPEED * 100
end

-- 1 strength, 2 agility, 4 intellect: the sixth return of the spec info
local function PrimaryStatIndex()
	local SI = C_SpecializationInfo
	if not (SI and SI.GetSpecialization and SI.GetSpecializationInfo) then return 1 end
	local ok, _, _, _, _, _, primary = pcall(SI.GetSpecializationInfo, SI.GetSpecialization())
	return ok and primary or 1
end

-- key, percent?, read() -> number (possibly secret) or nil.
-- `direct`: comes from one API untouched, so a secret can go to the HUD as it is.
ns.STATS = {
	{ key = "crit", percent = true, direct = true, read = function()
		local spell, melee, ranged = CRIT.spell(), CRIT.melee(), CRIT.ranged()
		if IsSecret(spell) or IsSecret(melee) or IsSecret(ranged) then return CRIT[critSource]() end
		local best, source = melee or 0, "melee"
		if (spell or 0) > best then best, source = spell, "spell" end
		if (ranged or 0) > best then best, source = ranged, "ranged" end
		critSource = source
		return best
	end },
	{ key = "haste",   percent = true, direct = true, read = function() return Call(GetHaste) end },
	{ key = "mastery", percent = true, direct = true, read = function() return (Call(GetMasteryEffect)) end },
	{ key = "vers", percent = true, direct = true, read = function()
		local rating, flat = Call(GetCombatRatingBonus, CR_VERS), Call(GetVersatilityBonus, CR_VERS)
		if IsSecret(rating) or IsSecret(flat) then return rating end   -- the sum cannot be made
		return (rating or 0) + (flat or 0)
	end },
	{ key = "leech",     percent = true, direct = true, read = function() return Call(GetLifesteal) end },
	{ key = "avoidance", percent = true, direct = true, read = function() return Call(GetAvoidance) end },
	{ key = "speed", percent = true, decimals = 0, read = SpeedPercent },
	{ key = "primary", decimals = 0, read = function()
		local _, effective = Call(UnitStat, "player", PrimaryStatIndex())
		return effective
	end, direct = true },
	{ key = "ilvl", decimals = 1, direct = true, read = function()
		local _, equipped = Call(GetAverageItemLevel)
		return equipped
	end },
	{ key = "armor", decimals = 0, direct = true, read = function()
		local _, effective = Call(UnitArmor, "player")
		return effective
	end },
	{ key = "dodge", percent = true, direct = true, read = function() return Call(GetDodgeChance) end },
	{ key = "parry", percent = true, direct = true, read = function() return Call(GetParryChance) end },
	{ key = "block", percent = true, direct = true, read = function() return Call(GetBlockChance) end },
	-- everything you wear taken together, as the repair bill sees it
	{ key = "durability", percent = true, decimals = 0, read = function()
		if type(GetInventoryItemDurability) ~= "function" then return nil end
		local current, full = 0, 0
		for slot = 1, 19 do
			local ok, c, f = pcall(GetInventoryItemDurability, slot)
			if ok and c and f then
				if IsSecret(c) or IsSecret(f) then return c end
				current, full = current + c, full + f
			end
		end
		if full == 0 then return nil end
		return math.floor(current * 100 / full)
	end, colour = function(value)
		if value <= 20 then return "bad" elseif value <= 50 then return "warn" end
	end },
}
ns.STAT_BY_KEY = {}
for _, s in ipairs(ns.STATS) do ns.STAT_BY_KEY[s.key] = s end

-- What a stat is called. The primary stat goes by its own name: strength, agility or intellect.
-- onHud: the HUD may be asked to use the English names (short, and what guides use)
-- whatever language the rest is in.
local function StatName(key)
	if key == "primary" then
		local index = PrimaryStatIndex()
		return "STAT_primary_" .. ((index == 2 or index == 4) and index or 1)
	end
	return "STAT_" .. key
end

function ns.StatEnglish(key)
	local name = StatName(key)
	return CK.locales.enUS[name] or name
end

function ns.StatLabel(key, onHud)
	if onHud and ns.db.english then return ns.StatEnglish(key) end
	return L[StatName(key)]
end

-- ---------------------------------------------------------------------------
-- Saved data (CombatKitStatsDB, account-wide)
--   { order = { "crit", "haste", ... every key }, shown = { crit = true, ... }, decimals = 1,
--     english = true: English stat names on the HUD }
-- ---------------------------------------------------------------------------

local DEFAULT_SHOWN = { crit = true, haste = true, mastery = true, vers = true }

local function InitDB()
	if type(CombatKitStatsDB) ~= "table" then CombatKitStatsDB = {} end
	local db = CombatKitStatsDB
	db.decimals = db.decimals or 1
	if type(db.shown) ~= "table" then
		db.shown = {}
		for key, on in pairs(DEFAULT_SHOWN) do db.shown[key] = on end
	end
	-- keep the saved order, drop keys that no longer exist, append new ones
	local order, seen = {}, {}
	for _, key in ipairs(type(db.order) == "table" and db.order or {}) do
		if ns.STAT_BY_KEY[key] and not seen[key] then order[#order + 1] = key; seen[key] = true end
	end
	for _, s in ipairs(ns.STATS) do
		if not seen[s.key] then order[#order + 1] = s.key end
	end
	db.order = order
	ns.db = db
end

-- Move a stat one place up (-1) or down (+1) in the order.
function ns.Move(key, dir)
	local order = ns.db.order
	for i, k in ipairs(order) do
		if k == key then
			local j = i + dir
			if j >= 1 and j <= #order then order[i], order[j] = order[j], order[i] end
			return
		end
	end
end

-- ---------------------------------------------------------------------------
-- The HUD section
-- ---------------------------------------------------------------------------

local lastText = {}   -- key -> what was shown the last time the value could be read
local fromMemory = {} -- key -> true while the HUD shows that remembered text, dimmed

local function Format(stat)
	local decimals = stat.decimals or ns.db.decimals
	return "%." .. decimals .. "f" .. (stat.percent and "%%" or "")
end

local section = {
	key = "stats",
	order = 20,
	GetRows = function()
		local rows = {}
		for _, key in ipairs(ns.db.order) do
			local stat = ns.STAT_BY_KEY[key]
			if ns.db.shown[key] then
				local value = stat.read()
				local row = { label = ns.StatLabel(key, true) }
				if value == nil then
					row.value = lastText[key] or "-"
				elseif IsSecret(value) then
					if stat.direct then
						row.fmt, row.num, row.value, row.width = Format(stat), value, lastText[key], 44
					else
						row.value = CK.Skin.Text("dim", lastText[key] or "-")   -- from memory
						fromMemory[key] = true
					end
				else
					local text = string.format(Format(stat), value)
					local colour = stat.colour and stat.colour(value)
					lastText[key] = colour and CK.Skin.Text(colour, text) or text
					fromMemory[key] = nil
					row.value = lastText[key]
				end
				rows[#rows + 1] = row
			end
		end
		return rows
	end,
}

-- ---------------------------------------------------------------------------
-- Updates: events for the stats, a slow ticker for movement speed
-- ---------------------------------------------------------------------------

local UNIT_EVENTS = { "UNIT_STATS", "UNIT_AURA", "UNIT_RESISTANCES", "UNIT_ATTACK_POWER" }
local EVENTS = {
	"COMBAT_RATING_UPDATE", "MASTERY_UPDATE", "SPEED_UPDATE", "LIFESTEAL_UPDATE", "AVOIDANCE_UPDATE",
	"PLAYER_EQUIPMENT_CHANGED", "PLAYER_AVG_ITEM_LEVEL_UPDATE", "PLAYER_TALENT_UPDATE", "UPDATE_INVENTORY_DURABILITY",
	"PLAYER_SPECIALIZATION_CHANGED", "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED",
}
local THROTTLE, SPEED_TICK = 0.2, 0.2

local running, queued = false, false
local function Queue()
	if queued or not running then return end
	queued = true
	C_Timer.After(THROTTLE, function()
		queued = false
		if running then CK.HUD.Refresh() end
	end)
end

-- Movement speed has no event of its own. The tick only looks at that one
-- number and redraws the HUD when the text on it would change.
-- One chain of ticks per OnEnable: switching off and on again must not leave two.
local generation = 0
local function SpeedTick(mine)
	if not running or mine ~= generation then return end
	if ns.db.shown.speed and not queued then
		local value = SpeedPercent()
		if value ~= nil and not IsSecret(value)
			and (fromMemory.speed or string.format(Format(ns.STAT_BY_KEY.speed), value) ~= lastText.speed) then
			CK.HUD.Refresh()
		end
	end
	C_Timer.After(SPEED_TICK, function() SpeedTick(mine) end)
end

local driver = CreateFrame("Frame")
driver:SetScript("OnEvent", Queue)

function ns.OnEnable()
	if not ns.db then InitDB() end
	running = true
	for _, e in ipairs(EVENTS) do pcall(driver.RegisterEvent, driver, e) end
	for _, e in ipairs(UNIT_EVENTS) do pcall(driver.RegisterUnitEvent, driver, e, "player") end
	CK.HUD.AddSection(section)
	generation = generation + 1
	SpeedTick(generation)
end

function ns.OnDisable()
	running = false
	driver:UnregisterAllEvents()
	CK.HUD.RemoveSection("stats")
end
