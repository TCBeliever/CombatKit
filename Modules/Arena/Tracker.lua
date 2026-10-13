local ADDON, ns = ...

-- ===========================================================================
-- The tracker: from "the buff of ability X was seen on unit U" to "teammate T
-- used X at time t, it is ready again at t + cd". It knows nothing about how
-- the sighting was made; a backend (Backend.lua, or a fake one in the tests)
-- reports three things through the callbacks below, and the tracker keeps
-- the estimates the display reads.
--
--   Shown(unit, spellID, now, initial)   the buff is drawn for unit; `initial`
--                                        when it was already there as we began
--                                        to look (so its start is unknown)
--   Hidden(unit, spellID, now)           the buff is gone
--   Expired(unit, spellID, now)          the buff ran its full course (the
--                                        game's own timer); comes right before
--                                        Hidden
--
-- The player's own casts come in by OnPlayerCast: they settle who cast an
-- external, and they are the self-test (the player's own slot must light up
-- after the player's own cast, or detection is broken).
--
-- Data is kept per teammate (by GUID) and per spell: the uses seen, when the
-- buff is up, the cooldown estimate. States for the display:
--
--   ready    nothing outstanding (or a charge left)
--   active   the buff is up right now
--   cooling  every charge is spent; ready at readyAt
--   unknown  not seen since we began to look at this teammate (joined mid
--            round, reload): the ability may be ready or not
-- ===========================================================================

local Tracker = {}
ns.Tracker = Tracker

local teammates = {}     -- unit token -> teammate
local order = { "player", "party1", "party2" }
local recentCasts = {}   -- spellID -> time of the player's last cast
local listeners = {}
local durations = {}     -- spellID -> shortest full buff duration seen (for refresh inference)
local selfTest = { pending = {}, failures = 0 }
Tracker.failed = false

local SAME_USE_WINDOW = 1.0      -- area buffs land on several allies within this
local OWN_CAST_WINDOW = 0.5      -- a buff this soon after the player's cast is the player's
local SELF_TEST_WINDOW = 0.5     -- the player's own slot must light up within this
local SELF_TEST_STRIKES = 2      -- consecutive misses before detection is called broken

local function now() return GetTime() end

function Tracker.AddListener(fn) listeners[#listeners + 1] = fn end
local function Notify(what, ...) for _, fn in ipairs(listeners) do fn(what, ...) end end

-- ---------------------------------------------------------------------------
-- Teammates and their entries
-- ---------------------------------------------------------------------------

local function NewEntry(def, known)
	return {
		def = def,
		uses = {},          -- start times of the uses still recharging, oldest first
		activeSince = nil,  -- when the buff was last seen appearing (nil when down)
		activeHolder = nil, -- which unit holds the buff
		cd = ns.BaseCooldown(def),
		estimate = true,    -- until inspect has had its say
		unknown = not known,
		ambiguous = false,  -- the last use may belong to someone else as well
	}
end

-- the entries a teammate carries: the class's list, with or without externals;
-- entries that already exist are kept with their estimates
local function Fit(t, withExternals)
	local spells, order = {}, {}
	for _, def in ipairs(ns.SpellsFor(t.class, withExternals)) do
		spells[def.id] = t.spells[def.id] or NewEntry(def, t.known)
		order[#order + 1] = def.id
	end
	t.spells, t.order, t.externals = spells, order, withExternals
end

local function NewTeammate(unit, guid, class, withExternals)
	local t = { unit = unit, guid = guid, class = class, spells = {}, order = {}, known = false }
	Fit(t, withExternals)
	return t
end

-- The roster: { { unit = "party1", guid = "...", class = "DRUID" }, ... }. A
-- unit whose GUID changed is a new teammate and starts unknown; one that
-- stayed keeps its estimates.
function Tracker.SetRoster(list, withExternals)
	local seen = {}
	for _, r in ipairs(list) do
		seen[r.unit] = true
		local t = teammates[r.unit]
		if not t or t.guid ~= r.guid or t.class ~= r.class then
			teammates[r.unit] = NewTeammate(r.unit, r.guid, r.class, withExternals)
		elseif t.externals ~= withExternals then
			Fit(t, withExternals)
		end
	end
	for unit in pairs(teammates) do
		if not seen[unit] then teammates[unit] = nil end
	end
	Notify("roster")
end

-- A new round: every ability is ready and known.
function Tracker.RoundStart()
	for _, t in pairs(teammates) do
		t.known = true
		for _, e in pairs(t.spells) do
			e.uses, e.activeSince, e.activeHolder, e.unknown, e.ambiguous = {}, nil, nil, false, false
		end
	end
	Notify("round")
end

function Tracker.Clear()
	teammates = {}
	recentCasts = {}
	selfTest.pending, selfTest.failures = {}, 0
	Tracker.failed = false
	Notify("clear")
end

function Tracker.Teammates()
	local out = {}
	for _, unit in ipairs(order) do
		if teammates[unit] then out[#out + 1] = teammates[unit] end
	end
	return out
end

function Tracker.Get(unit) return teammates[unit] end

-- ---------------------------------------------------------------------------
-- Uses and the state they leave
-- ---------------------------------------------------------------------------

-- when each outstanding use is ready again: charges recharge one after another
local function ReadyTimes(e)
	local times, t = {}, nil
	for i, start in ipairs(e.uses) do
		t = math.max(start, t or 0) + e.cd
		times[i] = t
	end
	return times
end

-- drop the uses that have recharged
local function Settle(e, at)
	local times = ReadyTimes(e)
	local kept = {}
	for i, start in ipairs(e.uses) do
		if times[i] > at then kept[#kept + 1] = start end
	end
	e.uses = kept
end

local function AddUse(e, at)
	Settle(e, at)
	local last = e.uses[#e.uses]
	if last and at - last < SAME_USE_WINDOW then return false end   -- the same use seen again (an area buff)
	-- a single charge used again before the estimate said it could: the estimate was too long
	if e.def.charges == 1 and last and at - last < e.cd then
		e.cd = at - last
		e.uses = {}
	end
	e.uses[#e.uses + 1] = at
	e.unknown = false
	return true
end

-- state, when it is ready (cooling only), charges left, and the flags
function Tracker.State(e, at)
	at = at or now()
	Settle(e, at)
	local times = ReadyTimes(e)
	local left = e.def.charges - #e.uses
	local state, readyAt, nextAt = "ready", nil, nil
	if left <= 0 then
		state, readyAt = "cooling", times[1]
	elseif #e.uses > 0 then
		nextAt = times[1]   -- a charge is recharging while another is left
	end
	if e.activeSince then state = "active" end
	if e.unknown and not e.activeSince then state = "unknown" end
	return state, readyAt, left, nextAt
end

-- ---------------------------------------------------------------------------
-- What the backend reports
-- ---------------------------------------------------------------------------

local function Entry(unit, spellID)
	local t = teammates[unit]
	return t and t.spells[spellID], t
end

-- who could have put this external on `holder`
local function Candidates(def, holder, at)
	local out = {}
	local recent = recentCasts[def.id]
	if recent and at - recent <= OWN_CAST_WINDOW and teammates.player and teammates.player.spells[def.id] then
		return { teammates.player }, true
	end
	for _, unit in ipairs(order) do
		local t = teammates[unit]
		if t and t.spells[def.id] and unit ~= "player" then
			local okDead, dead = pcall(UnitIsDeadOrGhost, unit)
			if okDead and dead == true then
				-- a dead teammate cast nothing
			elseif def.notOnSelf and unit == holder then
				-- cannot be cast on oneself: the holder is not the caster
			else
				out[#out + 1] = t
			end
		end
	end
	if #out == 0 and teammates[holder] and teammates[holder].spells[def.id] and not def.notOnSelf then
		out[1] = teammates[holder]   -- nobody else could have: the holder did it to themselves
	end
	return out, false
end

local function Use(t, e, at, holder, ambiguous)
	if not AddUse(e, at) then return end
	e.ambiguous = ambiguous or false
	Notify("use", t, e)
end

function Tracker.Shown(unit, spellID, at, initial)
	at = at or now()
	local def = ns.SPELL_BY_ID[spellID]
	if not def then return end
	if def.kind == "self" then
		local e, t = Entry(unit, spellID)
		if not e then return end
		if initial then
			e.activeSince, e.activeHolder = at, unit   -- up as we began to look: a use of unknown start
			Notify("active", t, e)
			return
		end
		e.activeSince, e.activeHolder = at, unit
		Use(t, e, at, unit, false)
		Tracker.SelfTestPass(unit, spellID)
		Notify("active", t, e)
		return
	end
	-- an external: credit everyone who could have cast it
	local list, own = Candidates(def, unit, at)
	for _, t in ipairs(list) do
		local e = t.spells[spellID]
		if e then
			e.activeSince, e.activeHolder = at, unit
			if not initial then Use(t, e, at, unit, #list > 1) end
			if own then Tracker.SelfTestPass("player", spellID) end
			Notify("active", t, e)
		end
	end
end

function Tracker.Hidden(unit, spellID, at)
	at = at or now()
	for _, t in pairs(teammates) do
		local e = t.spells[spellID]
		if e and e.activeHolder == unit then
			e.activeSince, e.activeHolder = nil, nil
			Notify("inactive", t, e)
		end
	end
end

-- the buff ran its full course: its length is learned, and a length longer
-- than the shortest seen means it was refreshed, i.e. used again, in between
function Tracker.Expired(unit, spellID, at)
	at = at or now()
	for _, t in pairs(teammates) do
		local e = t.spells[spellID]
		if e and e.activeHolder == unit and e.activeSince then
			local length = at - e.activeSince
			local known = durations[spellID]
			if not known or length < known - 0.25 then
				durations[spellID] = length
			elseif length > known + 0.5 and e.def.charges > 1 then
				Use(t, e, at - known, unit, e.ambiguous)   -- the refresh, dated by the full length
			end
		end
	end
end

function Tracker.KnownDuration(spellID) return durations[spellID] end

-- ---------------------------------------------------------------------------
-- The player's own casts: attribution, and the self-test
-- ---------------------------------------------------------------------------

function Tracker.OnPlayerCast(spellID, at)
	at = at or now()
	local def = ns.SPELL_BY_ID[spellID]
	if not def then return end
	recentCasts[spellID] = at
	local me = teammates.player
	if me and me.spells[spellID] and def.kind == "self" then
		selfTest.pending[spellID] = at
	end
end

function Tracker.SelfTestPass(unit, spellID)
	if unit ~= "player" or not selfTest.pending[spellID] then return end
	selfTest.pending[spellID] = nil
	selfTest.failures = 0
	if Tracker.failed then
		Tracker.failed = false
		Notify("detection", true)
	end
end

-- called regularly: a cast whose buff never showed is a strike
function Tracker.SelfTestCheck(at)
	at = at or now()
	for spellID, t in pairs(selfTest.pending) do
		if at - t > SELF_TEST_WINDOW then
			selfTest.pending[spellID] = nil
			selfTest.failures = selfTest.failures + 1
			if selfTest.failures >= SELF_TEST_STRIKES and not Tracker.failed then
				Tracker.failed = true
				Notify("detection", false)
			end
		end
	end
end

-- inspect's answer for a teammate: a cooldown that is no longer an estimate
function Tracker.SetCooldown(unit, spellID, seconds)
	local e = Entry(unit, spellID)
	if not e then return end
	e.cd, e.estimate = seconds, false
	Notify("use", teammates[unit], e)
end

-- for the tests and the status line
function Tracker.Debug()
	local out = {}
	for _, t in ipairs(Tracker.Teammates()) do
		for _, id in ipairs(t.order) do
			local e = t.spells[id]
			local state, readyAt, left = Tracker.State(e)
			out[#out + 1] = string.format("%s %d %s%s%s", t.unit, id, state,
				readyAt and string.format(" until %.1f", readyAt) or "", e.def.charges > 1 and (" x" .. left) or "")
		end
	end
	return out
end
