local ADDON, ns = ...

-- ===========================================================================
-- The tracker: from "the buff of ability X was seen on unit U" to "teammate T
-- used X at time t, it is ready again at t + cd". It knows nothing about how
-- the sighting was made; a backend (Backend.lua, or a fake one in the tests)
-- reports three things through the callbacks below, and the tracker keeps
-- the estimates the display reads.
--
-- `unit` is where the aura is: a teammate for a buff, an opponent (arena1-3)
-- for a crowd control's debuff.
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
local controlled = {}    -- unit -> since when it is under a stun, a fear or a disorient
Tracker.failed = false

local SAME_USE_WINDOW = 1.0      -- one use seen on several units lands on them within this
local OWN_CAST_WINDOW = 0.5      -- a buff this soon after the player's cast is the player's
local SELF_TEST_WINDOW = 0.5     -- the player's own slot must light up within this
local SELF_TEST_STRIKES = 2      -- consecutive misses before detection is called broken
local CONTROL_GRACE = 0.3        -- controlled at least this long before a sighting: did not cast it

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
		charges = ns.BaseCharges(def),  -- one more once a teammate is seen using it that often
		estimate = true,    -- until inspect has had its say
		unknown = not known,
		ambiguous = false,  -- the last use may belong to someone else as well
		missing = false,    -- inspect says the teammate does not have it: not in the row
	}
end

-- the row: the teammate's abilities in the class's order, the missing ones left out
local function Reorder(t)
	local order = {}
	for _, id in ipairs(t.all) do
		if not t.spells[id].missing then order[#order + 1] = id end
	end
	t.order = order
end

-- the entries a teammate carries: the class's list under the selection
-- (the spells ticked on or off); entries that already exist are
-- kept with their estimates
local function Fit(t, sel)
	local spells, all = {}, {}
	for _, def in ipairs(ns.SpellsFor(t.class, sel)) do
		spells[def.id] = t.spells[def.id] or NewEntry(def, t.known)
		all[#all + 1] = def.id
	end
	t.spells, t.all, t.sig = spells, all, sel.sig
	Reorder(t)
end

local function NewTeammate(unit, guid, class, sel, known)
	local t = { unit = unit, guid = guid, class = class, spells = {}, order = {}, known = known and true or false }
	Fit(t, sel)
	return t
end

-- The roster: { { unit = "party1", guid = "...", class = "DRUID" }, ... }. A
-- unit whose GUID changed is a new teammate; it starts known and ready when
-- the round has not begun (nothing can have been used before the gates),
-- unknown when it arrives mid round. One that stayed keeps its estimates.
-- `sel` is the selection (see Spells.lua) with a `sig` that changes with it.
function Tracker.SetRoster(list, sel, known)
	if type(sel) ~= "table" then sel = { sig = "" } end
	local seen = {}
	for _, r in ipairs(list) do
		seen[r.unit] = true
		local t = teammates[r.unit]
		if not t or t.guid ~= r.guid or t.class ~= r.class then
			teammates[r.unit] = NewTeammate(r.unit, r.guid, r.class, sel, known)
		elseif t.sig ~= sel.sig then
			Fit(t, sel)
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
	controlled = {}
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

-- a sighting within this long of the last use is that use seen again: an
-- use seen on several units (Allies, Enemies) lands on them for its `window`
local function SameUseWindow(def)
	if def.window then return def.window + 1 end
	return SAME_USE_WINDOW
end

-- may two close uses of this ability prove the estimate too long? Only when
-- the use is surely this teammate's and nothing but the cooldown can bring
-- the ability back: one charge, no talent for another, no reset, not one seen
-- effect walked into twice
local function CanCorrect(e, trusted)
	local d = e.def
	return trusted and ns.BaseCharges(d) == 1 and not d.extraCharge and not d.noLearn and not d.window
end

local function AddUse(e, at, trusted)
	Settle(e, at)
	local last = e.uses[#e.uses]
	if last and at - last < SameUseWindow(e.def) then return false end
	if last and at - last < e.cd and CanCorrect(e, trusted) then
		e.cd = at - last
		e.uses = {}
	end
	e.uses[#e.uses + 1] = at
	-- more uses outstanding than charges: the talent for another charge is there
	if e.def.extraCharge and #e.uses > e.charges then e.charges = ns.BaseCharges(e.def) + 1 end
	e.unknown = false
	return true
end

-- state, when it is ready (cooling only), charges left, and the flags
function Tracker.State(e, at)
	at = at or now()
	Settle(e, at)
	local times = ReadyTimes(e)
	local left = e.charges - #e.uses
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
-- the player's class has this ability (whether or not the player's own row is shown)
local function PlayerHas(def)
	local ok, _, class = pcall(UnitClass, "player")
	return ok and type(class) == "string" and ns.CLASSES_WITH[def.id] and ns.CLASSES_WITH[def.id][class] == true
end

-- who could have put this external on `holder` (a teammate), or this crowd
-- control on `holder` (an opponent). The player's own cast settles it first:
-- within OWN_CAST_WINDOW, or within the ability's `fuse` for one that can
-- land long after the cast (a trap, a totem); the player's own use is then
-- nobody else's, credited to the player's row when it is shown.
-- a teammate under a stun, a fear or a disorient (PartyCD.lua reads it from the
-- game's loss-of-control data), from when
function Tracker.SetControlled(unit, on, at)
	if on then controlled[unit] = controlled[unit] or at or now() else controlled[unit] = nil end
end

local function Controlled(unit, at)
	local since = controlled[unit]
	return since ~= nil and at - since >= CONTROL_GRACE
end
Tracker.Controlled = function(unit, at) return Controlled(unit, at or now()) end

local function Candidates(def, holder, at)
	local out, held = {}, {}
	local recent = recentCasts[def.id]
	if recent and at - recent <= (def.fuse or 0) + OWN_CAST_WINDOW and PlayerHas(def) then
		if teammates.player and teammates.player.spells[def.id] then return { teammates.player }, true end
		return {}, true
	end
	for _, unit in ipairs(order) do
		local t = teammates[unit]
		if t and t.spells[def.id] and not t.spells[def.id].missing and unit ~= "player" then
			local okDead, dead = pcall(UnitIsDeadOrGhost, unit)
			if okDead and dead == true then
				-- a dead teammate cast nothing
			elseif def.seen == "otherAlly" and unit == holder then
				-- cannot be cast on oneself: the holder is not the caster
			elseif Controlled(unit, at) and not ns.CastableUnderControl(def) then
				held[#held + 1] = t   -- stunned, feared or disoriented since before: not the caster
			else
				out[#out + 1] = t
			end
		end
	end
	if #out == 0 and teammates[holder] and teammates[holder].spells[def.id] and def.seen ~= "otherAlly" then
		local t = teammates[holder]
		out[1] = t   -- nobody else could have: the holder did it to themselves
		if t.spells[def.id].missing then t.spells[def.id].missing = false; Reorder(t); Notify("roster") end
	end
	-- everyone who could have was under control: the reading was wrong somewhere, so
	-- they stay the candidates rather than nobody
	if #out == 0 then out = held end
	return out, false
end

local function Use(t, e, at, holder, ambiguous)
	if not AddUse(e, at, not ambiguous) then return end
	e.ambiguous = ambiguous or false
	Notify("use", t, e)
end

function Tracker.Shown(unit, spellID, at, initial)
	at = at or now()
	local def = ns.SPELL_BY_ID[spellID]
	if not def then return end
	if def.seen == "caster" then
		local e, t = Entry(unit, spellID)
		if not e then return end
		if e.missing then e.missing = false; Reorder(t); Notify("roster") end
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
	-- an external or a crowd control: credit everyone who could have cast it
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
			elseif length > known + 0.5 and ns.BaseCharges(e.def) > 1 and not e.def.window then
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
	-- the spell cast may not be the one the list watches (a trap is cast as
	-- another spell than the trap that holds the target): `casts` in Spells.lua
	local def = ns.SPELL_BY_ID[spellID] or ns.SPELL_BY_CAST[spellID]
	if not def then return end
	recentCasts[def.id] = at
	local me = teammates.player
	if me and me.spells[def.id] and def.seen == "caster" then
		selfTest.pending[def.id] = at
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

-- inspect's answer for a teammate: a cooldown that is no longer an estimate,
-- and the charges their talents give
function Tracker.SetCooldown(unit, spellID, seconds, charges)
	local e = Entry(unit, spellID)
	if not e then return end
	e.cd, e.estimate = seconds, false
	if type(charges) == "number" and charges > e.charges then e.charges = charges end
	Notify("use", teammates[unit], e)
end

-- inspect's answer: the teammate has the ability or not (a buff seen later says yes again)
function Tracker.SetAvailable(unit, spellID, available)
	local e, t = Entry(unit, spellID)
	if not e or e.missing == (not available) then return end
	e.missing = not available
	Reorder(t)
	Notify("roster")
end

-- for the tests and the status line
function Tracker.Debug()
	local out = {}
	local at = now()
	for _, t in ipairs(Tracker.Teammates()) do
		for _, id in ipairs(t.order) do
			local e = t.spells[id]
			local state, readyAt, left = Tracker.State(e, at)
			out[#out + 1] = string.format("%s %d %s cd=%.0f%s uses=%d%s%s", t.unit, id, state, e.cd, e.estimate and "~" or "", #e.uses,
				readyAt and string.format(" ready in %.0f", readyAt - at) or "", e.charges > 1 and (" x" .. left) or "")
		end
	end
	return out
end
