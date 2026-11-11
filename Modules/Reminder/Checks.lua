local ADDON, ns = ...

-- ===========================================================================
-- Reading the game. Every answer is one of three: yes, no, or "cannot tell"
-- (nil); a reminder that cannot tell shows nothing. 12.x hides some auras
-- from addons ("secret"), in combat and, in 12.1, in raids and keys even out
-- of combat, spell by spell. So:
--   - auras are asked for by spell ID, never scanned out of an event;
--   - an aura the game hands back is there, even if its time is hidden (then
--     only its running out cannot be judged);
--   - an aura it does not hand back is missing only if that spell's aura is
--     not hidden right now; otherwise "cannot tell";
--   - looking through all buffs one by one (the food icon) is only tried
--     where the game allows it, and a refusal falls back to IDs.
-- The newer API is used where 12.1 keeps the old one only as a fallback that
-- a setting can switch off (spells known, weapon enchants).
-- ===========================================================================

local MAIN, OFF = 16, 17   -- INVSLOT_MAINHAND, INVSLOT_OFFHAND
ns.MAIN, ns.OFF = MAIN, OFF
local WEAPON_CLASS = 2     -- Enum.ItemClass.Weapon
local FOREVER = math.huge
ns.FOREVER = FOREVER

local function Secret(v) return issecretvalue ~= nil and issecretvalue(v) end
ns.Secret = Secret

-- True while the game hides auras from addons as a whole
function ns.AurasHidden()
	if not (C_Secrets and C_Secrets.ShouldAurasBeSecret) then return false end
	local ok, hidden = pcall(C_Secrets.ShouldAurasBeSecret)
	if not ok or Secret(hidden) then return true end
	return hidden and true or false
end

-- Is this spell's aura hidden right now? Asked of the spell where the game
-- can say, else of auras as a whole.
local function SpellHidden(id)
	if C_Secrets and C_Secrets.ShouldSpellAuraBeSecret then
		local ok, hidden = pcall(C_Secrets.ShouldSpellAuraBeSecret, id)
		if ok and not Secret(hidden) then return hidden and true or false end
		return true
	end
	return ns.AurasHidden()
end
ns.SpellHidden = SpellHidden

-- Seconds an aura has left: FOREVER for one without an end, nil when hidden
local function Left(aura)
	local expires = aura.expirationTime
	if expires == nil or Secret(expires) then return nil end
	if expires == 0 then return FOREVER end
	return math.max(0, expires - GetTime())
end

-- One of the player's auras by spell ID: the aura, false, or nil (cannot tell)
local function PlayerAura(id)
	local ok, aura = pcall(C_UnitAuras.GetPlayerAuraBySpellID, id)
	if not ok then return nil end
	if aura then return aura end
	if SpellHidden(id) then return nil end
	return false
end

-- How many of `ids` the player has, and the least time left among those whose
-- time can be read (nil when none can). nil when any of them cannot be told.
function ns.PlayerAuras(ids)
	local count, least = 0, nil
	for _, id in ipairs(ids) do
		local aura = PlayerAura(id)
		if aura == nil then return nil end
		if aura then
			count = count + 1
			local left = Left(aura)
			if left then least = least and math.min(least, left) or left end
		end
	end
	return count, least
end

-- One of `ids` on the player, any of them doing: 1 and the most time left on one (FOREVER when
-- its time is hidden), or 0; nil when none is there and one of them cannot be told
function ns.PlayerAnyAura(ids)
	local best, unknown = nil, false
	for _, id in ipairs(ids) do
		local aura = PlayerAura(id)
		if aura == nil then
			unknown = true
		elseif aura then
			local left = Left(aura) or FOREVER
			best = best and math.max(best, left) or left
		end
	end
	if best then return 1, best end
	if unknown then return nil end
	return 0
end

local EATING = {}
for _, id in ipairs(ns.EATING) do EATING[id] = true end

-- Through all buffs, where the game allows it: the food buff's time left
-- (false: none), and whether the player is eating. nil when refused.
local function ScanFood()
	local get = C_UnitAuras and C_UnitAuras.GetAuraDataByIndex
	if not get or ns.AurasHidden() then return nil end
	local left, eating = false, false
	for i = 1, 255 do
		local ok, aura = pcall(get, "player", i, "HELPFUL")
		if not ok then return nil end
		if not aura then return left, eating end
		local icon, spell = aura.icon, aura.spellId
		if Secret(icon) or Secret(spell) then return nil end
		if icon == ns.FOOD_ICON then left = Left(aura) or FOREVER end
		if EATING[spell] then eating = true end
	end
	return left, eating
end

-- The food buff: its time left (FOREVER when there but its time is hidden),
-- false when there is none, nil when that cannot be told; and whether the
-- player is eating right now. A buff the IDs do not know (a new food) is
-- still found where the buffs can be looked through.
function ns.FoodState()
	local left, eating = ScanFood()
	if left ~= nil then return left, eating end
	-- the game would not let the buffs be looked through: ask for each by ID
	local eat = ns.PlayerAuras(ns.EATING)
	eating = eat ~= nil and eat > 0
	local count, least = ns.PlayerAuras(ns.WELL_FED)
	if count == nil then return nil, eating end
	if count > 0 then return least or FOREVER, eating end
	return false, eating
end

-- The Refreshment the player is eating now: its spell, or nil
function ns.EatingSpell()
	for _, id in ipairs(ns.EATING) do
		if PlayerAura(id) then return id end
	end
end

-- Does `unit` (someone in the group) have one of `ids` with more than
-- `atLeast` seconds left? One whose time is hidden counts. nil: cannot tell.
local function UnitCovered(unit, ids, atLeast)
	local unknown = false
	for _, id in ipairs(ids) do
		local ok, aura = pcall(C_UnitAuras.GetUnitAuraBySpellID, unit, id)
		if not ok then return nil end
		if aura then
			local left = Left(aura)
			if left == nil or left > atLeast then return true end
		elseif SpellHidden(id) then
			unknown = true
		end
	end
	if unknown then return nil end
	return false
end

-- Everyone in the group, the player included (in a raid as one of the raid units)
local function Members()
	local units = { "player" }
	local n = GetNumGroupMembers and GetNumGroupMembers() or 0
	if IsInRaid and IsInRaid() then
		units = {}
		for i = 1, n do units[#units + 1] = "raid" .. i end
	elseif n > 1 then
		for i = 1, n - 1 do units[#units + 1] = "party" .. i end
	end
	return units
end

local function Online(unit) return UnitExists(unit) and UnitIsConnected(unit) end
local function Near(unit)
	return unit == "player" or (Online(unit) and not UnitIsDeadOrGhost(unit) and UnitIsVisible(unit))
end

function ns.Grouped() return (GetNumGroupMembers and GetNumGroupMembers() or 0) > 1 end

-- The group members a buff of yours can reach: in the group, online, alive and near
local function GroupUnits()
	local near = {}
	for _, unit in ipairs(Members()) do
		if Near(unit) then near[#near + 1] = unit end
	end
	return near
end

-- How many group members lack all of `ids` or have less than `atLeast`
-- seconds of them left, out of how many: nil when any cannot be told.
function ns.GroupMissing(ids, atLeast)
	local missing, units = 0, GroupUnits()
	for _, unit in ipairs(units) do
		local covered = UnitCovered(unit, ids, atLeast)
		if covered == nil then return nil end
		if not covered then missing = missing + 1 end
	end
	return missing, #units
end

-- One of `ids` that the player put on `unit`: the aura, false, or nil. Asked
-- by name with the "cast by me" filter where the game has it, so the caster
-- never has to be read (it may be hidden); else by ID and its caster.
local function MineOn(unit, id)
	local byName = C_UnitAuras.GetAuraDataBySpellName
	local name = ns.SpellName(id)
	if byName and name then
		local ok, aura = pcall(byName, unit, name, "HELPFUL|PLAYER")
		if not ok then return nil end
		if aura then return aura end
	else
		local ok, aura = pcall(C_UnitAuras.GetUnitAuraBySpellID, unit, id)
		if not ok then return nil end
		if aura then
			local source = aura.sourceUnit
			if Secret(source) then return nil end
			if source and UnitIsUnit(source, "player") then return aura end
		end
	end
	if SpellHidden(id) then return nil end
	return false
end

-- One of `ids` that the player put on someone else in the group (or on
-- themselves too, with `self`): true and the most time left on one, or
-- false. nil when that cannot be told: an aura hidden, or someone out of
-- sight or dead who may be the one who has it.
function ns.OnAlly(ids, self)
	local best, seen, unseen = nil, false, false
	for _, unit in ipairs(Members()) do
		local me = UnitIsUnit(unit, "player")
		if (self or not me) and (me or Online(unit)) then
			if not Near(unit) then
				unseen = true
			else
				for _, id in ipairs(ids) do
					local aura = MineOn(unit, id)
					if aura == nil then return nil end
					if aura then
						seen = true
						local left = Left(aura) or FOREVER
						best = best and math.max(best, left) or left
					end
				end
			end
		end
	end
	if seen then return true, best end
	if unseen then return nil end
	return false
end

-- Is someone near in the group of `class` (a class token)?
function ns.GroupHas(class)
	for _, unit in ipairs(Members()) do
		if not UnitIsUnit(unit, "player") and Near(unit) then
			local _, token = UnitClass(unit)
			if token == class then return true end
		end
	end
	return false
end

-- ---------------------------------------------------------------------------
-- Spells, stances, spec, pet
-- ---------------------------------------------------------------------------

-- Is `id` known? Every way the client offers is asked: a learned spell or
-- talent, a spell in the spell book, and the old global while 12.1 still
-- keeps it (it is gone when its fallback setting is off).
function ns.Known(id)
	local book = C_SpellBook or {}
	local ways = { book.IsSpellKnown, book.IsSpellInSpellBook, IsPlayerSpell }
	for i = 1, 3 do
		if ways[i] then
			local ok, known = pcall(ways[i], id)
			if ok and known and not Secret(known) then return true end
		end
	end
	return false
end

-- The first of `ids` the player knows, or nil
function ns.FirstKnown(ids)
	for _, id in ipairs(ids) do
		if ns.Known(id) then return id end
	end
end

-- The first of `ids` the player knows, else the first of them: a reminder that knows none is
-- still named and shown on the settings page, and does not apply
function ns.KnownOrFirst(ids)
	return ns.FirstKnown(ids) or ids[1]
end

-- The spell of the stance or form the player is in, from the stance bar: 0 for none
function ns.Stance()
	local index = GetShapeshiftForm and GetShapeshiftForm() or 0
	if not index or index == 0 or not GetShapeshiftFormInfo then return 0 end
	local _, _, _, spell = GetShapeshiftFormInfo(index)
	return spell or 0
end

-- Is a spell cooling down, beyond a global cooldown? Its seconds left, false, or nil when unreadable
function ns.OnCooldown(id)
	local ok, info = pcall(C_Spell.GetSpellCooldown, id)
	if not ok or type(info) ~= "table" then return nil end
	local start, duration = info.startTime, info.duration
	if Secret(start) or Secret(duration) then return nil end
	if (duration or 0) <= 1.5 then return false end
	return math.max(0, start + duration - GetTime())
end

function ns.SpecID()
	local index = C_SpecializationInfo.GetSpecialization()
	if not index then return nil end
	return (C_SpecializationInfo.GetSpecializationInfo(index))
end

-- The role the group gave the player, or nil (solo, no roles, unreadable)
function ns.Role()
	if not IsInGroup() then return nil end
	local ok, role = pcall(UnitGroupRolesAssigned, "player")
	if not ok or Secret(role) or role == "NONE" then return nil end
	return role
end

-- A living pet out. In combat either answer may be secret: an unreadable "dead" counts as alive
-- (the health shows the rest), an unreadable "there" as not there.
function ns.HasPet()
	local there = UnitExists("pet")
	if Secret(there) or not there then return false end
	local dead = UnitIsDeadOrGhost("pet")
	if Secret(dead) then return true end
	return not dead
end

-- What a summoning spell brings, by the spell's name without "Summon" (Summon Imp: Imp)
function ns.SummonedName(spell)
	local name = ns.SpellName(spell)
	if not name then return nil end
	return (name:gsub("^召喚", ""):gsub("^Summon ", ""))
end

-- A hunter's pet in one of the five slots Call Pet 1 to 5 bring: its icon and name, or nothing
-- while the stable cannot be read
function ns.StablePet(slot)
	if not (C_StableInfo and C_StableInfo.GetStablePetInfo) then return nil end
	local ok, info = pcall(C_StableInfo.GetStablePetInfo, slot)
	if not ok or type(info) ~= "table" then return nil end
	local icon, name = info.icon, info.name
	if Secret(icon) or Secret(name) then return nil end
	return icon, type(name) == "string" and name or nil
end

-- The creature the pet is, from its GUID; nil when that cannot be read
function ns.PetCreature()
	local guid = UnitGUID("pet")
	if type(guid) ~= "string" or Secret(guid) then return nil end
	return tonumber(guid:match("^%a+%-%d+%-%d+%-%d+%-%d+%-(%d+)%-"))
end

-- ---------------------------------------------------------------------------
-- Weapons
-- ---------------------------------------------------------------------------

-- The item in a weapon slot when it is a weapon (a shield or an off-hand
-- frill is not), and its weapon subclass
function ns.Weapon(slot)
	local item = GetInventoryItemID("player", slot)
	if not item then return nil end
	local _, _, _, _, _, classID, subclassID = C_Item.GetItemInfoInstant(item)
	if classID ~= WEAPON_CLASS then return nil end
	return item, subclassID
end

-- Does an oil, stone or ammunition go on the weapon in `slot`?
function ns.Fits(item, slot)
	local _, subclass = ns.Weapon(slot)
	local mask = ns.OIL.fits[item]
	if not (subclass and mask) then return false end
	return math.floor(mask / 2 ^ subclass) % 2 == 1
end

-- The temporary enchant on a weapon slot (oil, stone, a class imbue): its
-- enchant ID (true when it is there but which one is hidden) and its seconds
-- left (nil when hidden); false when there is none; nil when unreadable.
function ns.TempEnchant(slot)
	local get = C_PaperDollInfo and C_PaperDollInfo.GetTemporaryEnchantmentInfo
	if get then
		local ok, info = pcall(get, slot)
		if not ok then return nil end
		if type(info) ~= "table" then return false end
		local id, ms = info.enchantID, info.remainingTimeMs
		if Secret(id) then id = true end
		if Secret(ms) then ms = nil end
		return id or true, ms and ms / 1000 or nil
	end
	if not GetWeaponEnchantInfo then return nil end
	local ok, hasMain, mainLeft, _, mainID, hasOff, offLeft, _, offID = pcall(GetWeaponEnchantInfo)
	if not ok then return nil end
	local has, left, id
	if slot == MAIN then has, left, id = hasMain, mainLeft, mainID else has, left, id = hasOff, offLeft, offID end
	if Secret(has) then return nil end
	if not has then return false end
	if Secret(id) then id = true end
	if Secret(left) then left = nil end
	return id or true, left and left / 1000 or nil
end

-- The permanent enchant on a slot, from the item's link
function ns.PermanentEnchant(slot)
	local link = GetInventoryItemLink("player", slot)
	if not link or Secret(link) then return nil end
	local enchant = link:match("item:%d+:(%d*)")
	return tonumber(enchant) or 0
end

-- ---------------------------------------------------------------------------
-- Bags and names
-- ---------------------------------------------------------------------------

-- The first of `items` in the bags (that `Keep(item)` accepts, if given), or nil
function ns.InBags(items, Keep)
	for _, item in ipairs(items) do
		local ok, count = pcall(C_Item.GetItemCount, item)
		if ok and count and not Secret(count) and count > 0 and (not Keep or Keep(item)) then return item end
	end
end

function ns.ItemIcon(item)
	return C_Item.GetItemIconByID and C_Item.GetItemIconByID(item) or nil
end

function ns.SpellIcon(id) return id and C_Spell.GetSpellTexture(id) or nil end
function ns.SpellName(id) return id and C_Spell.GetSpellName(id) or nil end
