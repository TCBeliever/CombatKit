local ADDON, ns = ...
local U = ns.Util

-- ===========================================================================
-- The probe: does unit U have one of the buffs in set S?
--
-- Since 12.1 the auras of other players are secret in arena: an addon may not
-- read them, but may ask the game to draw them. An AuraContainer slot with an
-- includeSpellIDs filter is such a drawing: the game fills it when the unit
-- has one of the listed buffs. The slot carries a Duration object (through a
-- status bar bound with SetDurationBar), and a Cooldown frame fed that
-- Duration shows itself when the duration is not zero and stays hidden when
-- it is. Counting OnShow turns a secret aura into one plain bit: present or
-- not. Nothing else is read.
--
-- Each answer is checked: a known positive duration must show once and a
-- zero one not at all before and after the real read, every unit has a
-- control slot whose filter is always empty and must read "no", and every
-- request is read twice, once with its filter and once with an empty one
-- (in alternating order), so a slot that still shows the previous filter's
-- aura is caught. A request whose checks fail answers nil, never a guess.
--
-- A call the client refuses (an API gone, a protected function) trips the
-- circuit of that unit's pool: its requests read unknown from then on. The
-- circuits are reset when a new arena is entered. The player's own pool is
-- the self test: when that one trips, the tracker pauses and says why.
--
-- Probe.SetBackend swaps this for another source of answers (the tests use a
-- table of buffs); the tracker only ever calls the backend.
-- ===========================================================================

local P = {}
ns.Probe = P

P.SETTLE  = 0.35   -- after a filter change, before the first read
P.OBSERVE = 0.35   -- between the two reads of one request
P.MIN_SLOTS = 6    -- a pool starts with this many; it grows to what the roster needs
P.MAX_SLOTS = 30
P.FILTER  = "HELPFUL"
P.ENEMY_FILTER = "HARMFUL|INCLUDE_NAME_PLATE_ONLY"
P.TEMPLATE = "CustomAuraContainerTemplate"

local function clock()
	local f = GetTimePreciseSec or GetTime
	return f()
end

local function plain(v) return canaccessvalue(v) == true end

-- ---------------------------------------------------------------------------
-- The real backend
-- ---------------------------------------------------------------------------

local real = { pools = {}, root = nil, fatal = nil, serial = 0 }

-- pcall with a circuit: an error trips `pool` (or the whole probe without one)
local function try(pool, what, fn, ...)
	if real.fatal or (pool and pool.refused) then return false end
	local ok, a, b = pcall(fn, ...)
	if not ok then
		local why = what .. ": " .. tostring(a)
		if pool then pool.refused = why else real.fatal = why end
		U.Log("refused", pool and pool.unit or nil, nil, why)
		return false
	end
	return true, a, b
end

local function Root()
	if real.root then return real.root end
	local f = CreateFrame("Frame", nil, UIParent)
	f:SetSize(900, 900)
	f:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 20, -100)
	f:SetAlpha(0)
	f:EnableMouse(false)
	f:Show()
	real.root = f
	return f
end

local function OnShow(slot)
	return function()
		if slot.counting then slot.shows = slot.shows + 1 else slot.stray = slot.stray + 1 end
	end
end

-- the slot's own frames: a status bar for the Duration, a Cooldown to feed it to
local function Initializer(slot)
	return function(button)
		button:SetSize(1, 1)
		local bar = CreateFrame("StatusBar", nil, button)
		bar:SetSize(1, 1)
		bar:SetPoint("TOPLEFT")
		bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
		button:SetDurationBar(bar)
		local duration = bar:GetTimerDuration()
		if duration ~= nil and plain(duration) then slot.duration = duration end
		local cd = CreateFrame("Cooldown", nil, Root())
		cd:SetSize(1, 1)
		cd:SetPoint("TOPLEFT")
		cd:SetDrawEdge(false)
		cd:SetDrawSwipe(false)
		cd:SetDrawBling(false)
		cd:SetHideCountdownNumbers(true)
		cd:EnableMouse(false)
		slot.shows, slot.stray, slot.counting = 0, 0, false
		cd:SetScript("OnShow", OnShow(slot))
		slot.cd = cd
		local positive, zero = C_DurationUtil.CreateDuration(), C_DurationUtil.CreateDuration()
		if plain(positive) and plain(zero) then
			zero:SetTimeSpan(0, 0)
			slot.positive, slot.zero = positive, zero
		end
	end
end

local function MakeSlot(pool, key)
	local slot = { unit = pool.unit, key = key, pool = pool }
	slot.created = try(pool, "AddAuraSlot", function()
		pool.container:AddAuraSlot(key, pool.filter, {
			candidateFilters = { includeSpellIDs = {} },
			initializeFrame = Initializer(slot),
		})
	end)
	return slot
end

-- usable: the game ran initializeFrame and handed out what the read needs
local function Usable(slot)
	return slot and slot.created and slot.duration ~= nil and slot.cd ~= nil and slot.positive ~= nil
end

-- The container of a unit with at least `want` slots. Frames can only be made out of combat.
local function Pool(unit, want)
	want = math.min(P.MAX_SLOTS, math.max(P.MIN_SLOTS, want or 0))
	local pool = real.pools[unit]
	if not pool then
		if InCombatLockdown() or real.fatal then return nil end
		local enemy = unit:match("^arena%d$") or unit == "target"
		pool = { unit = unit, slots = {}, filter = enemy and P.ENEMY_FILTER or P.FILTER }
		local ok = try(nil, "CreateFrame AuraContainer", function()
			local c = CreateFrame("AuraContainer", nil, Root(), P.TEMPLATE)
			c:SetSize(1, 1)
			c:SetAlpha(0)
			c:SetPoint("TOPLEFT")
			c:SetUnit(unit)
			pool.container = c
		end)
		if not ok then return nil end
		pool.control = MakeSlot(pool, "control")
		real.pools[unit] = pool
	end
	if #pool.slots < want and not InCombatLockdown() and not pool.refused then
		for i = #pool.slots + 1, want do pool.slots[i] = MakeSlot(pool, "slot" .. i) end
	end
	return pool
end

local function SetFilter(slot, ids)
	local included = {}
	if ids then for _, id in ipairs(ids) do included[id] = true end end
	return try(slot.pool, "SetAuraSlotCandidateFilters", function()
		slot.pool.container:SetAuraSlotCandidateFilters(slot.key, { includeSpellIDs = included })
	end)
end

-- how many times the Cooldown showed itself when fed `duration` (after a Clear)
local function Feed(slot, duration)
	slot.shows, slot.counting = 0, true
	local ok = try(slot.pool, "SetCooldownFromDurationObject", function()
		slot.cd:Clear()
		slot.cd:SetCooldownFromDurationObject(duration, true)
	end)
	slot.counting = false
	if not ok then return nil end
	return slot.shows
end

-- true / false, or nil when the checks around the read did not hold
local function Read(slot)
	if not Usable(slot) or slot.pool.refused then return nil end
	if slot.stray > 0 then slot.stray = 0 return nil end
	local now = clock()
	local ok = try(slot.pool, "SetTimeSpan", function()
		slot.positive:SetTimeSpan(now, now + 4)
		slot.zero:SetTimeSpan(0, 0)
	end)
	if not ok then return nil end
	if Feed(slot, slot.positive) ~= 1 or Feed(slot, slot.zero) ~= 0 then return nil end
	local count = Feed(slot, slot.duration)
	if Feed(slot, slot.zero) ~= 0 or Feed(slot, slot.positive) ~= 1 then return nil end
	if slot.stray > 0 then return nil end
	if count == 0 then return false end
	if count == 1 then return true end
	return nil
end

-- Can the probe work here at all? Makes the player's pool and reads a slot
-- with an empty filter: it must say "no". Answers ok, reason, detail; nil
-- means "not now" (combat).
function real.SelfTest()
	if real.fatal then return false, "refused", real.fatal end
	if type(canaccessvalue) ~= "function" or type(issecretvalue) ~= "function" then return false, "secrets" end
	if not (C_DurationUtil and C_DurationUtil.CreateDuration) then return false, "duration" end
	local pool = Pool("player")
	if real.fatal then return false, "refused", real.fatal end
	if not pool then return nil end
	if pool.refused then return false, "refused", pool.refused end
	local slot = pool.control
	if not Usable(slot) then return false, "api" end
	if not SetFilter(slot, nil) then return false, "refused", pool.refused end
	if Read(slot) ~= false then return false, "selftest" end
	return true
end

-- Out of combat, make the pools these units will need, sized for them.
-- needed: unit -> how many requests a scan holds for it
function real.Prepare(units, needed)
	for _, unit in ipairs(units) do Pool(unit, needed and needed[unit]) end
	return real.fatal == nil
end

-- the reason the probe as a whole is out, or nil
function real.Refused()
	if real.fatal then return real.fatal end
	local player = real.pools.player
	if player and player.refused then return player.refused end
	return nil
end

-- a new arena: every circuit closed again
function real.ResetCircuits()
	real.fatal = nil
	for _, pool in pairs(real.pools) do pool.refused = nil end
end

-- One scan: requests = { { unit=, ids= }, ... }. Takes about a second; `done`
-- gets results[i] = true | false | nil and `valid` (did every control hold).
-- Returns false when it could not start (no pool at all).
local scan
function real.Scan(requests, done)
	if scan or real.fatal then return false end
	local used, slots, controls, any = {}, {}, {}, false
	for i, r in ipairs(requests) do
		local pool = real.pools[r.unit]
		if pool and not pool.refused then
			used[r.unit] = (used[r.unit] or 0) + 1
			local slot = pool.slots[used[r.unit]]
			if Usable(slot) then   -- past the last slot: this request stays unknown this scan
				slots[i] = slot
				controls[r.unit] = pool.control
				any = true
			end
		end
	end
	if not any then return false end
	real.serial = real.serial + 1
	scan = { requests = requests, slots = slots, controls = controls, done = done, step = 0, due = 0,
		valid = true, controlsFailed = {} }
	-- the order alternates: a slot still showing the previous filter cannot pass twice
	scan.order = (real.serial % 2 == 0) and { "ids", "none" } or { "none", "ids" }
	return true
end

local function ClearFilters(s)
	for _, slot in pairs(s.slots) do SetFilter(slot, nil) end
end

local function Abort(why)
	local s = scan
	scan = nil
	ClearFilters(s)
	s.done(nil, false, why)
end

local function ApplyPhase(s, which)
	for i, slot in pairs(s.slots) do
		local ids = (which == "ids") and s.requests[i].ids or nil
		SetFilter(slot, ids)   -- a refused pool reads unknown below
	end
	return not real.fatal
end

function real.Tick(now)
	local s = scan
	if not s then return end
	if real.fatal then return Abort("refused") end
	if now < s.due then return end
	if s.step == 0 then
		if not ApplyPhase(s, s.order[1]) then return Abort("refused") end
		s.step, s.due = 1, now + P.SETTLE
	else
		-- a read: the controls first, then every slot
		local phase = { values = {} }
		for unit, control in pairs(s.controls) do
			if Read(control) ~= false then s.valid = false; s.controlsFailed[unit] = true end
		end
		for i, slot in pairs(s.slots) do phase.values[i] = Read(slot) end
		if s.step == 1 then
			s[s.order[1]] = phase
			if not ApplyPhase(s, s.order[2]) then return Abort("refused") end
			s.step, s.due = 2, now + P.OBSERVE
		else
			s[s.order[2]] = phase
			scan = nil
			ClearFilters(s)
			local results = {}
			for i = 1, #s.requests do
				local with, without = s.ids.values[i], s.none.values[i]
				if without == false and type(with) == "boolean" then results[i] = with end
			end
			s.done(results, s.valid, s.valid and nil or "controls")
		end
	end
end

function real.Busy() return scan ~= nil end

function real.Reset()
	if scan then
		local s = scan
		scan = nil
		ClearFilters(s)
	end
end

function real.Status()
	local parts = {}
	for unit, pool in pairs(real.pools) do
		local usable = 0
		for _, slot in ipairs(pool.slots) do if Usable(slot) then usable = usable + 1 end end
		parts[#parts + 1] = string.format("%s %d/%d slots%s", unit, usable, #pool.slots,
			pool.refused and (" refused: " .. pool.refused) or "")
	end
	table.sort(parts)
	if real.fatal then parts[#parts + 1] = "fatal: " .. real.fatal end
	return #parts > 0 and table.concat(parts, "; ") or "no pools"
end

-- ---------------------------------------------------------------------------
-- The backend in use
-- ---------------------------------------------------------------------------

P.backend = real
function P.SetBackend(b) P.backend = b or real end
function P.Real() return real end
