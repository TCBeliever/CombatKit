local ADDON, ns = ...
local U = ns.Util

-- ===========================================================================
-- The tracker: which teammate has which cooldown running.
--
-- Roster -> entries: one per (teammate, ability). Every scan asks the probe,
-- for each entry, whether its buff shows on the caster (kind "self"), on any
-- friendly unit (kind "ally": an external) or its debuff on any enemy (kind
-- "enemy": a crowd control). The buff appearing starts the estimate: ready
-- again at now + cd, the cooldown Cooldowns.lua resolved from the teammate's
-- talents.
--
-- What can go wrong, and what is done about it:
--   a flaky read     two consecutive "no" before a new "yes" counts again
--   the same use     an external or debuff seen again within its duration
--                    (+2 s) is the same use, unless it is a second charge on
--                    another target (targeted abilities)
--   whose was it     the teammate whose class has it; when two could have,
--                    the player's own casts, who was crowd controlled, and
--                    "it cannot be on the caster" narrow it; still two: both
--                    icons share one estimate and show "?"
--   a stale scan     a scan that straddled a roster or secrecy change is
--                    discarded
--   a late start     an entry made mid-round (reload, late join) is unknown,
--                    shown as "?", until its buff is first seen
--
-- Solo mode (/ckpvp solo): the player stands in for a teammate, so the whole
-- chain can be tried alone, outside arena; enemies are then the target.
-- ===========================================================================

local T = {}
ns.Tracker = T

T.GAP = 0.15                                  -- between scans
T.OWN_CAST_WINDOW = 3                         -- an external I cast myself, seen this soon after, is mine
T.DELAYED_WINDOW = 60                         -- a trap or totem can wait this long before it lands
T.NEGATIVES_TO_REARM = 2
T.BAD_CONTROLS_TO_PAUSE = 5
T.ROLE_ORDER = { defensive = 1, cc = 2, offensive = 3 }

T.solo = false
T.UNITS = { "party1", "party2" }               -- the teammates, 2v2 and 3v3
T.FRIENDS = { "player", "party1", "party2" }   -- where an external can land
T.ENEMIES = { "arena1", "arena2", "arena3" }   -- where a crowd control lands
T.WATCHED = { "player", "party1", "party2", "arena1", "arena2", "arena3" }

T.entries = {}     -- unit -> { entry, ... }
T.roster = {}      -- unit -> { guid=, class=, spec=, info= (Inspect entry) }
T.enemies = {}     -- unit -> { guid= }
T.shared = {}      -- ability id -> the shared state of an external or crowd control
T.stats = { scans = 0, positives = 0, invalid = 0, discarded = 0 }
T.ownCasts = {}    -- spellID -> when the player cast it
T.castCoverageSince = nil   -- since when the player's own casts are known
T.custom = {}      -- ability id -> cooldown set by hand
T.nextScan = 0
T.paused = nil     -- a reason, once the probe stopped working mid-match
T.live = false     -- a round is on
T.badControls = 0

local clock = U.clock

-- Solo: the player is the one tracked unit, the target the one enemy.
function T.SetSolo(on)
	T.solo = on and true or false
	if T.solo then
		T.UNITS, T.FRIENDS, T.ENEMIES = { "player" }, { "player" }, { "target" }
		T.WATCHED = { "player", "target" }
	else
		T.UNITS, T.FRIENDS = { "party1", "party2" }, { "player", "party1", "party2" }
		T.ENEMIES = { "arena1", "arena2", "arena3" }
		T.WATCHED = { "player", "party1", "party2", "arena1", "arena2", "arena3" }
	end
end

-- ---------------------------------------------------------------------------
-- Entries
-- ---------------------------------------------------------------------------

local function NewEntry(unit, ability)
	return {
		unit = unit, ability = ability, key = ability.id, kind = ability.kind,
		queue = {},          -- ready times, one per charge in use
		active = false,      -- the buff is up
		last = nil,          -- what the probe said last (true/false/nil)
		armed = true,        -- a positive starts an estimate (false while the buff stays up)
		negatives = 0,       -- consecutive "no"
		uncertain = false,   -- credited to this teammate, but another could have cast it
		unknown = T.live,    -- made mid-round: on cooldown or not, nobody knows yet
	}
end

local function Resolve(e, r)
	local resolved = ns.Cooldowns.Resolve(e.ability, r.info, T.custom)
	e.cd, e.charges, e.basis, e.assumes = resolved.cd, resolved.charges, resolved.basis, resolved.assumes
end

-- Who, among the friends, could cast this? (class and, when known, spec)
local function Casters(ability)
	local out = {}
	for _, unit in ipairs(T.FRIENDS) do
		local r = T.roster[unit]
		if r and r.class == ability.class and (not ability.specs or not r.spec or ability.specs[r.spec]) then
			out[#out + 1] = unit
		end
	end
	return out
end

local function Sorted(list)
	for i, e in ipairs(list) do e.order = i end
	table.sort(list, function(a, b)
		local ra, rb = T.ROLE_ORDER[a.ability.role] or 9, T.ROLE_ORDER[b.ability.role] or 9
		if ra ~= rb then return ra < rb end
		return a.order < b.order
	end)
	return list
end

-- Entries from the roster. Timers of entries that survive are kept.
function T.Rebuild()
	local keep = {}
	for _, unit in ipairs(T.UNITS) do
		local r = T.roster[unit]
		local list = {}
		if r and r.class then
			local old = {}
			for _, e in ipairs(T.entries[unit] or {}) do
				if e.guid == r.guid then old[e.key] = e end
			end
			for _, ability in ipairs(ns.Spells.For(r.class, r.spec)) do
				local e = old[ability.id] or NewEntry(unit, ability)
				e.guid, e.ability = r.guid, ability
				Resolve(e, r)
				list[#list + 1] = e
			end
			Sorted(list)
		end
		keep[unit] = list
	end
	T.entries = keep
	-- the entries of a shared ability (external, crowd control) take its state
	for id, state in pairs(T.shared) do
		local still = false
		for _, unit in ipairs(T.UNITS) do
			for _, e in ipairs(T.entries[unit]) do
				if e.key == id and e.kind ~= "self" then
					still = true
					if state.candidates[unit] then e.queue, e.started = state.queue, state.started end
				end
			end
		end
		if not still then T.shared[id] = nil end
	end
	T.RefreshUncertainty()
	ns.Display.Dirty()
end

-- "?" on the entries of a shared ability that two teammates could have cast
function T.RefreshUncertainty()
	for _, unit in ipairs(T.UNITS) do
		for _, e in ipairs(T.entries[unit]) do
			if e.kind ~= "self" then
				local state = T.shared[e.key]
				e.uncertain = state ~= nil and state.ambiguous == true and state.candidates[unit] == true
			end
		end
	end
end

-- roster: unit -> { guid=, class=, spec=, info= }; enemies: unit -> { guid= }
function T.SetRoster(roster, enemies)
	if not roster.player then
		local _, class = UnitClass("player")
		roster.player = { guid = U.Plain(UnitGUID, "player") or "player", class = class, spec = ns.PlayerSpec and ns.PlayerSpec() }
	end
	T.roster = roster
	T.enemies = enemies or {}
	T.Rebuild()
end

function T.SetCustom(custom)
	T.custom = custom or {}
	for _, unit in ipairs(T.UNITS) do
		for _, e in ipairs(T.entries[unit] or {}) do
			if T.roster[e.unit] then Resolve(e, T.roster[e.unit]) end
		end
	end
	ns.Display.Dirty()
end

-- A new round: every cooldown is ready again, and known to be.
function T.ResetTimers()
	for _, list in pairs(T.entries) do
		for _, e in ipairs(list) do
			e.queue, e.active, e.last, e.armed, e.negatives, e.unknown, e.started = {}, false, nil, true, 0, false, nil
		end
	end
	T.shared = {}
	T.ownCasts = {}
	T.castCoverageSince = clock()
	T.RefreshUncertainty()
	ns.Display.Dirty()
end

function T.Clear()
	T.entries, T.roster, T.enemies, T.shared = {}, {}, {}, {}
	T.ownCasts = {}
	T.castCoverageSince = nil
	T.paused = nil
	T.badControls = 0
	T.stats = { scans = 0, positives = 0, invalid = 0, discarded = 0 }
	ns.Probe.backend.Reset()
	ns.Display.Dirty()
end

-- the units an ability's buff or debuff can be on
function T.Holders(ability)
	if ability.kind == "self" then return nil end
	if ability.kind == "enemy" then return T.ENEMIES end
	return T.FRIENDS
end

local function Present(unit)
	return T.roster[unit] ~= nil or T.enemies[unit] ~= nil
end

-- how many requests a scan holds per unit (for the probe to size its pools)
function T.Needed()
	local needed, seen = {}, {}
	for _, unit in ipairs(T.UNITS) do
		for _, e in ipairs(T.entries[unit] or {}) do
			if e.kind == "self" then
				needed[unit] = (needed[unit] or 0) + 1
			elseif not seen[e.key] then
				seen[e.key] = true
				for _, holder in ipairs(T.Holders(e.ability)) do needed[holder] = (needed[holder] or 0) + 1 end
			end
		end
	end
	return needed
end

-- ---------------------------------------------------------------------------
-- Charges and estimates
-- ---------------------------------------------------------------------------

-- available charges, and seconds until the next one comes back (0 = ready)
function T.Charges(e, now)
	local q = e.queue
	while q[1] and q[1] <= now do table.remove(q, 1) end
	local max = e.charges or 1
	local nextIn = q[1] and (q[1] - now) or 0
	return math.max(0, max - #q), nextIn
end

local function StartEstimate(e, now)
	local available = T.Charges(e, now)
	if available == 0 then
		-- a use with nothing left to use: the estimate was too long (a talent?); start over
		e.queue = {}
		U.Log("timer", e.unit, e.key, "used before the estimate ended: estimate dropped")
	end
	local tail = e.queue[#e.queue] or now
	e.queue[#e.queue + 1] = math.max(tail, now) + e.cd
	e.started = now
	e.unknown = false
	T.stats.positives = T.stats.positives + 1
	U.Log("timer", e.unit, e.key, string.format("%ds (%s)", e.cd, e.basis))
end

-- The player cast this himself: the buff that follows is not a teammate's.
function T.OnPlayerCast(spellID)
	if type(spellID) == "number" then T.ownCasts[spellID] = clock() end
end

-- ---------------------------------------------------------------------------
-- Self abilities
-- ---------------------------------------------------------------------------

-- what one scan said about a "self" entry: present (true), absent (false), unknown (nil)
local function ObserveSelf(e, present, now)
	if present ~= nil and present ~= e.active then U.Log("buff", e.unit, e.key, present and "up" or "down") end
	e.last = present
	if present == nil then return end
	if not present then
		e.active = false
		e.negatives = e.negatives + 1
		if e.negatives >= T.NEGATIVES_TO_REARM then e.armed = true end
		return
	end
	e.negatives = 0
	e.active = true
	if not e.armed then return end
	e.armed = false
	StartEstimate(e, now)
end

-- ---------------------------------------------------------------------------
-- Externals and crowd control: whose was it?
-- ---------------------------------------------------------------------------

-- Answers owner (a unit), reason; or nil, reason, candidates (two or more)
function T.Owner(ability, at, holders)
	local candidates = Casters(ability)
	if #candidates == 0 then return nil, "no eligible caster" end
	local how = "the only one who has it"
	local window = (ability.delayed and T.DELAYED_WINDOW or T.OWN_CAST_WINDOW) + (ability.dur or 0)
	-- the player: his own casts are known
	local hasPlayer = false
	for _, unit in ipairs(candidates) do if unit == "player" then hasPlayer = true end end
	if hasPlayer and #candidates > 1 then
		local own = T.ownCasts[ability.id]
		if own and at - own <= window then
			return "player", "my own cast"
		elseif T.castCoverageSince and T.castCoverageSince < at - window then
			local rest = {}
			for _, unit in ipairs(candidates) do if unit ~= "player" then rest[#rest + 1] = unit end end
			candidates, how = rest, "not mine: my casts are known"
		end
	end
	-- a teammate who was crowd controlled or silenced could not have cast
	if #candidates > 1 then
		local kept, dropped = {}, {}
		for _, unit in ipairs(candidates) do
			local why = unit ~= "player" and ns.Control.CannotHaveCast(unit, at) or nil
			if why then dropped[#dropped + 1] = unit .. " " .. why else kept[#kept + 1] = unit end
		end
		if #kept > 0 and #dropped > 0 then candidates, how = kept, "ruled out: " .. table.concat(dropped, ", ") end
	end
	-- an external that cannot be self-cast: not whoever carries it
	if #candidates > 1 and ability.excludeCaster and holders then
		local rest = {}
		for _, unit in ipairs(candidates) do if not holders[unit] then rest[#rest + 1] = unit end end
		if #rest >= 1 then candidates, how = rest, "the buff is on the other one" end
	end
	if #candidates == 1 then return candidates[1], how end
	return nil, "two could have cast it", candidates
end

local function SharedState(id)
	local state = T.shared[id]
	if not state then
		state = { queue = {}, armed = true, negatives = 0, candidates = {}, ambiguous = false,
			recipientNegatives = {}, usedRecipients = {} }
		T.shared[id] = state
	end
	return state
end

-- the entries of a shared ability on these units take the shared estimate
local function Share(id, units, state)
	state.candidates = {}
	for _, unit in ipairs(units) do state.candidates[unit] = true end
	for _, unit in ipairs(T.UNITS) do
		for _, e in ipairs(T.entries[unit]) do
			if e.key == id and e.kind ~= "self" then
				if state.candidates[unit] then
					e.queue, e.started = state.queue, state.started
				elseif e.queue == state.queue then
					e.queue, e.started = {}, nil   -- no longer a candidate: its own, empty
				end
			end
		end
	end
	T.RefreshUncertainty()
end

-- one scan's answers for a shared ability: holders[unit] = true where it shows;
-- known = at least one holder answered
local function ObserveShared(ability, holders, known, anyPositive, now)
	local id = ability.id
	local state = SharedState(id)
	-- the entries of every possible caster carry the buff state for the glow
	for _, unit in ipairs(T.UNITS) do
		for _, e in ipairs(T.entries[unit]) do
			if e.key == id and e.kind ~= "self" then
				e.last = known and anyPositive or nil
				if known then e.active = anyPositive end
			end
		end
	end
	if not known then return end
	if anyPositive ~= (state.up or false) then
		local on = {}
		for unit in pairs(holders) do on[#on + 1] = unit end
		table.sort(on)
		U.Log("buff", nil, id, anyPositive and ("up on " .. table.concat(on, ",")) or "down")
		state.up = anyPositive
	end
	-- who got it this scan, for targeted charges
	local newRecipient = false
	for _, unit in ipairs(T.Holders(ability)) do
		if holders[unit] then
			if (state.recipientNegatives[unit] or 0) >= T.NEGATIVES_TO_REARM and not state.usedRecipients[unit] then
				newRecipient = true
			end
			state.recipientNegatives[unit] = 0
		else
			state.recipientNegatives[unit] = (state.recipientNegatives[unit] or 0) + 1
		end
	end
	if not anyPositive then
		state.negatives = state.negatives + 1
		if state.negatives >= T.NEGATIVES_TO_REARM then state.armed = true end
		return
	end
	state.negatives = 0

	local owner, how, candidates = T.Owner(ability, now, holders)
	if owner == "player" and not T.solo then return end   -- mine: no teammate's cooldown
	local units = owner and { owner } or candidates
	if not units then return end
	-- the estimate is on the owner's entry (or, ambiguous, on every candidate's)
	local target
	for _, unit in ipairs(units) do
		for _, e in ipairs(T.entries[unit] or {}) do
			if e.key == id then target = target or e end
		end
	end
	if not target then return end

	local window = math.max(3, (ability.dur or 0) + 2)
	local sameUse = state.started ~= nil and (now - state.started) < window
	local targeted = ability.targeted and (target.charges or 1) > 1 and newRecipient and state.started ~= nil
	if not state.armed and not targeted then return end
	if sameUse and not targeted then return end
	state.armed = false
	local wasAmbiguous = state.ambiguous
	state.ambiguous = owner == nil
	Share(id, units, state)
	if not sameUse then state.usedRecipients = {} end
	for unit in pairs(holders) do state.usedRecipients[unit] = true end
	if wasAmbiguous and owner then U.Log("shared", owner, id, "settled: " .. how) end
	StartEstimate(target, now)
	state.queue, state.started = target.queue, target.started
	for _, unit in ipairs(units) do
		for _, e in ipairs(T.entries[unit] or {}) do
			if e.key == id then e.queue, e.started, e.unknown = state.queue, state.started, false end
		end
	end
	if not owner then U.Log("shared", nil, id, "one of " .. table.concat(units, "/") .. " used it: estimate on both") end
end

-- ---------------------------------------------------------------------------
-- Scans
-- ---------------------------------------------------------------------------

local function Signature()
	local parts = { "regime=" .. U.Regime() }
	for _, unit in ipairs(T.WATCHED) do
		local r = T.roster[unit] or T.enemies[unit]
		parts[#parts + 1] = unit .. "=" .. (r and (tostring(r.guid) .. ":" .. tostring(r.spec)) or "-")
	end
	return table.concat(parts, "|")
end

-- the parts of two signatures that differ, for the log
local function SignatureDiff(a, b)
	local was = {}
	for part in a:gmatch("[^|]+") do was[part:match("^[^=]+")] = part end
	local out = {}
	for part in b:gmatch("[^|]+") do
		local key = part:match("^[^=]+")
		if was[key] ~= part then out[#out + 1] = tostring(was[key]) .. " -> " .. part end
	end
	return table.concat(out, "; ")
end

-- the requests of one scan: self entries on their unit, shared ones on every holder
local function Requests()
	local requests, owners = {}, {}
	local function add(e, holder)
		requests[#requests + 1] = { unit = holder, ids = e.ability.auras }
		owners[#requests] = { entry = e, holder = holder }
	end
	local seen = {}
	for _, unit in ipairs(T.UNITS) do
		for _, e in ipairs(T.entries[unit] or {}) do
			if e.kind == "self" then
				add(e, unit)
			elseif not seen[e.key] then
				seen[e.key] = true
				for _, holder in ipairs(T.Holders(e.ability)) do
					if Present(holder) then add(e, holder) end
				end
			end
		end
	end
	return requests, owners
end

function T.Pause(reason)
	if T.paused then return end
	T.paused = reason
	U.Log("pause", nil, nil, reason)
	ns.Probe.backend.Reset()
	ns.OnTrackerPaused(reason)
end

local function Resolve(owners, signature, results, valid, why)
	local now = clock()
	if results == nil then
		T.stats.invalid = T.stats.invalid + 1
		if why == "refused" and ns.Probe.backend.Refused() then T.Pause("refused") end
		return
	end
	local current = Signature()
	if signature ~= current then
		T.stats.discarded = T.stats.discarded + 1
		U.Log("scan", nil, nil, "discarded: " .. SignatureDiff(signature, current))
		return
	end
	T.stats.scans = T.stats.scans + 1
	if not valid then
		T.stats.invalid = T.stats.invalid + 1
		T.badControls = T.badControls + 1
		if T.badControls >= T.BAD_CONTROLS_TO_PAUSE then T.Pause("controls") end
		return
	end
	T.badControls = 0
	local groups = {}   -- ability id -> { ability=, holders=, known=, any= }
	for i, o in ipairs(owners) do
		local v = results[i]
		if o.entry.kind == "self" then
			ObserveSelf(o.entry, v, now)
		else
			local g = groups[o.entry.key]
			if not g then g = { ability = o.entry.ability, holders = {}, known = false, any = false }; groups[o.entry.key] = g end
			if v == true then g.holders[o.holder] = true; g.any = true; g.known = true
			elseif v == false then g.known = true end
		end
	end
	for _, g in pairs(groups) do ObserveShared(g.ability, g.holders, g.known, g.any, now) end
	ns.Display.Dirty()
end

-- Called every tick while an arena round is on.
function T.Tick(now)
	local backend = ns.Probe.backend
	backend.Tick(now)
	if T.paused or backend.Busy() or now < T.nextScan then return end
	local requests, owners = Requests()
	if #requests == 0 then
		T.nextScan = now + 1
		return
	end
	local signature = Signature()
	T.nextScan = now + T.GAP + 2   -- in case the scan never answers; the callback brings it forward
	local ok = backend.Scan(requests, function(results, valid, why)
		T.nextScan = clock() + T.GAP
		Resolve(owners, signature, results, valid, why)
	end)
	if not ok then T.nextScan = now + 1 end
end

function T.Entries(unit) return T.entries[unit] or {} end

-- for /ckpvp entries
function T.Describe(unit, now)
	local lines = {}
	for _, e in ipairs(T.Entries(unit)) do
		local available, nextIn = T.Charges(e, now)
		local state = e.unknown and "unknown" or (nextIn > 0 and string.format("%ds left", math.floor(nextIn + 0.5)) or "ready")
		if (e.charges or 1) > 1 then state = state .. string.format(" (%d/%d)", available, e.charges) end
		lines[#lines + 1] = string.format("  %d %-26s %-5s %-9s cd=%-4d %-8s %s%s%s | %s", e.key, e.ability.name, e.kind,
			e.ability.role, e.cd or 0, e.basis, state, e.active and ", up" or "", e.uncertain and ", ?" or "",
			ns.Cooldowns.Explain({ basis = e.basis, assumes = e.assumes or {} }))
	end
	return lines
end
