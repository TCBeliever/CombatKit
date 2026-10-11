local ADDON, ns = ...
local U = ns.Util

-- ===========================================================================
-- Who is crowd controlled: a teammate stunned or silenced when an external
-- appeared cannot have cast it, which settles who did when two could have.
--
-- C_LossOfControl gives a teammate's effects by unit, but their type can be
-- secret; the priority is readable. Which priority means what is learned from
-- the player's own loss-of-control readouts (type and priority both readable
-- there), seeded with the usual values.
-- ===========================================================================

local C = {}
ns.Control = C

C.UNITS = { "party1", "party2" }
C.MAX_GAP = 0.5   -- a sample older than this says nothing

C.CLASS_OF = {
	STUN = "hard", STUN_MECHANIC = "hard", FEAR = "hard", FEAR_MECHANIC = "hard", CONFUSE = "hard",
	CHARM = "hard", POSSESS = "hard", SLEEP = "hard", HORROR = "hard", BANISH = "hard",
	INCAPACITATE = "hard", DISORIENT = "hard", CYCLONE = "hard",
	SILENCE = "silence", PACIFYSILENCE = "silence",
	ROOT = "soft", DISARM = "soft", PACIFY = "soft", DAZE = "soft", SNARE = "soft",
	SCHOOL_INTERRUPT = "interrupt",
}
C.SEEDS = { STUN = 5, STUN_MECHANIC = 5, FEAR_MECHANIC = 5, CONFUSE = 5, ROOT = 1, SCHOOL_INTERRUPT = 2 }

C.priority = {}   -- locType -> priority
C.state = {}      -- unit -> { at=, hard=, silence=, ok= }

function C.Reset()
	C.priority = {}
	for t, p in pairs(C.SEEDS) do C.priority[t] = p end
	C.state = {}
end
C.Reset()

-- the player's own effects: type and priority are readable, so the map learns
function C.Learn()
	local api = C_LossOfControl
	if not (api and api.GetActiveLossOfControlDataCount) then return end
	local count = U.Plain(api.GetActiveLossOfControlDataCount)
	if type(count) ~= "number" then return end
	for i = 1, count do
		local d = U.Plain(api.GetActiveLossOfControlData, i)
		local t, p = U.Field(d, "locType"), U.Field(d, "priority")
		if type(t) == "string" and type(p) == "number" then C.priority[t] = p end
	end
end

local function ClassOfPriority(p)
	local class
	for t, prio in pairs(C.priority) do
		if prio == p then
			local c = C.CLASS_OF[t] or "unknown"
			if class and class ~= c then return "unknown" end
			class = c
		end
	end
	return class or "unknown"
end

-- what a teammate is under right now; nil when it cannot be read
local function Classes(unit)
	local api = C_LossOfControl
	if not (api and api.GetActiveLossOfControlDataCountByUnit) then return nil end
	local count = U.Plain(api.GetActiveLossOfControlDataCountByUnit, unit)
	if type(count) ~= "number" then return nil end
	local out = {}
	for i = 1, count do
		local d = U.Plain(api.GetActiveLossOfControlDataByUnit, unit, i)
		local p = U.Field(d, "priority")
		if type(p) ~= "number" then return nil end
		out[ClassOfPriority(p)] = true
	end
	return out
end

function C.Sample(unit, now)
	local st = C.state[unit] or {}
	C.state[unit] = st
	local classes = Classes(unit)
	st.at = now
	if not classes then
		st.ok, st.hard, st.silence = false, nil, nil
		return st
	end
	st.ok = true
	for _, c in ipairs({ "hard", "silence" }) do
		if classes[c] then st[c] = st[c] or now else st[c] = nil end
	end
	return st
end

function C.Tick(now, roster)
	for _, unit in ipairs(C.UNITS) do
		if roster[unit] then C.Sample(unit, now) else C.state[unit] = nil end
	end
end

-- Was the unit unable to cast at `at`? Answers why, or nil.
function C.CannotHaveCast(unit, at)
	local st = C.state[unit]
	if not st or not st.ok or type(st.at) ~= "number" or at - st.at > C.MAX_GAP then return nil end
	if st.hard and st.hard <= at then return "crowd controlled" end
	if st.silence and st.silence <= at then return "silenced" end
	return nil
end

function C.Describe(unit)
	local st = C.state[unit]
	if not st then return unit .. ": no sample" end
	if not st.ok then return unit .. ": readout unavailable" end
	local parts = {}
	if st.hard then parts[#parts + 1] = "crowd controlled" end
	if st.silence then parts[#parts + 1] = "silenced" end
	return unit .. ": " .. (#parts > 0 and table.concat(parts, ", ") or "free")
end
