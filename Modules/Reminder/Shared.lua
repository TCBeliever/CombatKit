local ADDON, ns = ...
local CK = CombatKit
local L = CK.L

-- ===========================================================================
-- What the group puts down: a feast, a flask cauldron. Its icon shows the
-- moment someone puts one down and counts down for as long as it stays, until
-- you have taken from it. That is what everyone then eats or flasks from,
-- not what they carry, so meanwhile your own food or flask reminder steps
-- aside. Two ways to see one go down, both read out of combat only:
--   - the line the game puts in chat, naming it as a link or in the client's language;
--   - the cast of the group member who puts it down, when the game lets its
--     spell ID be read.
-- No combat case: these go down between pulls.
-- ===========================================================================

-- the kinds of chat line such an announcement can come as
local CHAT_EVENTS = { "CHAT_MSG_EMOTE", "CHAT_MSG_TEXT_EMOTE", "CHAT_MSG_MONSTER_EMOTE", "CHAT_MSG_RAID_BOSS_EMOTE",
	"CHAT_MSG_SYSTEM" }
local FRESH = 55 * 60   -- a buff with more than this left: just taken

ns.SHARED_ORDER = { "feast", "cauldron" }
ns.SHARED = {
	feast    = { data = ns.FEAST, label = "Feast" },
	cauldron = { data = ns.CAULDRON, label = "Flask cauldron" },
}

-- Has the player taken from it? Eating at the feast or eaten (a fresh Well
-- Fed); taken a flask from the cauldron (one in the bags, or a fresh flask buff).
local TAKEN = {
	feast = function()
		local left, eating = ns.FoodState()
		return eating or (left and left ~= ns.FOREVER and left > FRESH) or false
	end,
	cauldron = function()
		if ns.InBags(ns.CAULDRON.takes) then return true end
		local count, least = ns.PlayerAuras(ns.FLASK.auras)
		return count ~= nil and count > 0 and least ~= nil and least > FRESH
	end,
}

local kindOf = {}   -- item -> "feast" | "cauldron"
for kind, s in pairs(ns.SHARED) do
	for _, item in ipairs(s.data.items) do kindOf[item] = kind end
end
local names    -- { { name, item }, ... }, longest first, once every name is in
local active = {}   -- kind -> { item=, expires= }
local seen = {}     -- how one was last seen, for /ckreminder: chat = { event=, line=, at= }, cast = { unit=, at= }

local function Secret(v) return issecretvalue ~= nil and issecretvalue(v) end

-- The names in the client's language. A hearty feast's name holds the plain
-- one's, so the longest are tried first.
local function Names()
	if names then return names end
	local list, complete = {}, true
	for item in pairs(kindOf) do
		local name = C_Item.GetItemNameByID(item)
		if name and name ~= "" then
			list[#list + 1] = { name, item }
		else
			complete = false
			C_Item.RequestLoadItemDataByID(item)
		end
	end
	table.sort(list, function(a, b) return #a[1] > #b[1] end)
	if complete then names = list end
	return list
end

-- The feast or cauldron a chat line is about: its item, or nil
function ns.SharedIn(line)
	for id in line:gmatch("|Hitem:(%d+)") do
		id = tonumber(id)
		if kindOf[id] then return id end
	end
	for _, entry in ipairs(Names()) do
		if line:find(entry[1], 1, true) then return entry[2] end
	end
end

local function Put(item)
	local kind = kindOf[item]
	if not ns.db.shared[kind] then return end   -- switched off: not kept to show later either
	local duration = ns.SHARED[kind].data.duration
	active[kind] = { item = item, expires = GetTime() + duration }
	C_Timer.After(duration + 0.5, function() ns.Queue(0) end)
	ns.Queue(0)
end

local function Grouped(unit)
	return unit == "player" or unit:find("^party%d") ~= nil or unit:find("^raid%d") ~= nil
end

local driver = CreateFrame("Frame")
driver:SetScript("OnEvent", function(_, event, a1, _, a3)
	if InCombatLockdown() then return end
	if event == "UNIT_SPELLCAST_SUCCEEDED" then
		local unit, spell = a1, a3
		if type(unit) ~= "string" or Secret(unit) or Secret(spell) or not Grouped(unit) then return end
		local item = ns.FEAST.casts[spell] or ns.CAULDRON.casts[spell]
		if not item then return end
		seen.cast = { unit = unit, item = item, at = GetTime() }
		return Put(item)
	end
	local line = a1
	if type(line) ~= "string" or Secret(line) then return end
	local ok, item = pcall(ns.SharedIn, line)
	if not ok or not item then return end
	seen.chat = { event = event, line = line, item = item, at = GetTime() }
	Put(item)
end)

-- Listening only while one of the two is on
function ns.SetSharedListening(on)
	driver:UnregisterAllEvents()
	if not on then
		wipe(active)
		return
	end
	for _, e in ipairs(CHAT_EVENTS) do pcall(driver.RegisterEvent, driver, e) end
	pcall(driver.RegisterEvent, driver, "UNIT_SPELLCAST_SUCCEEDED")
	Names()   -- asks the game for the names that are not in yet
end

-- Adds to `list` the group's things to show in scenario `key`; `up[kind]` is
-- set for each one shown
function ns.SharedReminders(key, list, up)
	local db = ns.db
	for _, kind in ipairs(ns.SHARED_ORDER) do
		local a = active[kind]
		if a and GetTime() >= a.expires then
			active[kind] = nil
			a = nil
		end
		if a and db.shared[kind] and db.sharedWhere[key] and not TAKEN[kind]() then
			list[#list + 1] = { key = kind, icon = ns.ItemIcon(a.item), label = L[ns.SHARED[kind].label], expires = a.expires }
			up[kind] = true
		end
	end
end

function ns.LastSeen() return seen end
