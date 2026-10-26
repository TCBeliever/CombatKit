local ADDON, ns = ...
local CK = CombatKit
local L = CK.L

CK.NewModule("PartyCD", ns)

-- ===========================================================================
-- The module: when to look (an arena, from entering to leaving), who to look
-- at (party1, party2, and the player as the reference), when a round starts,
-- and the glue between the backend, the tracker and the rows. Outside an
-- arena only the player's own row is looked at, and only while it is asked
-- for (showSelf, a debug setting).
-- ===========================================================================

local Tracker = ns.Tracker
local Inspect = ns.Inspect
local UNITS = ns.TEAM
local ENEMIES = { "arena1", "arena2", "arena3" }
local backend
local inArena = false
local engaged = false   -- the gates are open: a teammate arriving now is unknown, before that ready
local selfWatch = false -- outside an arena, the player's own row is watched (showSelf)
local running = false

-- ---------------------------------------------------------------------------
-- Saved data (CombatKitPartyCDDB, account-wide)
-- ---------------------------------------------------------------------------

ns.defaults = {
	showSelf    = false,     -- the player's own row (debug: it is the self-test's reference)
	trinket     = true,      -- the PvP trinket first in every row, from the game's own cooldown data
	glowStyle   = "ants",    -- the highlight while an aura is up: "ants" | "thin" | "proc" (UI.lua)
	picked      = {},        -- [spellID] = true | false: ticked on or off on the spells page;
	                         -- no entry: the default (on for a cooldown of a minute or more, Spells.lua)
	iconSize    = 28,
	spacing     = 2,
	maxPerRow   = 8,
	perRow      = "max",     -- how a row breaks into lines: "max" (at most maxPerRow to a line) |
	                         -- "even" (`lines` lines, the icons spread evenly over them; UI.lua)
	lines       = 2,
	attach      = true,      -- hang the rows on the party frames when they can be found
	side        = "RIGHT",   -- "RIGHT" | "LEFT" | "TOP" | "BOTTOM": which side of the frame
	offset      = 4,         -- distance from the frame
	offsetAlong = 0,         -- shift along the frame's edge
	grow        = "down",    -- how the lines line up: "down" | "up" | "center" by the frame's side,
	                         -- "right" | "left" | "center" above or below it (UI.lua)
	rows = {
		player = { point = "CENTER", relPoint = "CENTER", x = -260, y = -60 },
		party1 = { point = "CENTER", relPoint = "CENTER", x = -260, y = -100 },
		party2 = { point = "CENTER", relPoint = "CENTER", x = -260, y = -140 },
	},
}

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
	if type(CombatKitPartyCDDB) ~= "table" then CombatKitPartyCDDB = {} end
	ns.db = FillDefaults(CombatKitPartyCDDB, ns.defaults)
	-- earlier builds kept only the spells switched off, as `disabled`
	if type(ns.db.disabled) == "table" then
		for id in pairs(ns.db.disabled) do
			if ns.db.picked[id] == nil then ns.db.picked[id] = false end
		end
		ns.db.disabled = nil
	end
	-- earlier builds had a switch for the externals: switched off, it becomes
	-- every external unticked on the spells page
	if ns.db.externals == false then
		for _, list in pairs(ns.SPELLS) do
			for _, def in ipairs(list) do
				if def.external and ns.db.picked[def.id] == nil then ns.db.picked[def.id] = false end
			end
		end
	end
	ns.db.externals = nil
	ns.Profiles.Init(ns.db)
end

-- ---------------------------------------------------------------------------
-- The scene
-- ---------------------------------------------------------------------------

-- a log of what the backend reported and what the tracker made of it, kept
-- in the saved variables for a match's post-mortem (/ckpartycd log)
local LOG_LINES = 300
local function Log(fmt, ...)
	if not ns.db then return end
	ns.db.log = ns.db.log or {}
	local log = ns.db.log
	log[#log + 1] = string.format("%.2f %s", GetTime(), string.format(fmt, ...))
	if #log > LOG_LINES then table.remove(log, 1) end
end
ns.Log = Log

local callbacks = {
	Shown = function(unit, id, at, initial)
		Log("shown %s %d%s", unit, id, initial and " (already up)" or "")
		Tracker.Shown(unit, id, at, initial)
	end,
	Hidden = function(unit, id, at)
		Log("hidden %s %d", unit, id)
		Tracker.Hidden(unit, id, at)
	end,
	Expired = function(unit, id, at)
		Log("expired %s %d", unit, id)
		Tracker.Expired(unit, id, at)
	end,
}

local plain = ns.plain

-- a unit's race as the game names it in files (UnitRace's second value:
-- "Dwarf", "Tauren"; one "Pandaren" for all three), or nil
local function RaceOf(unit)
	local ok, _, race = pcall(UnitRace, unit)
	if ok and type(race) == "string" and plain(race) and race ~= "" then return race end
end
ns.RaceOf = RaceOf

-- inspect's answer: the teammate's own cooldowns and charges, and what they do not have
local function Inspected(unit, results, complete)
	for id, r in pairs(results) do
		if r.cd then Tracker.SetCooldown(unit, id, r.cd, r.charges) end   -- nil: only the spec was known
		Tracker.SetAvailable(unit, id, not r.missing)
	end
	for _, line in ipairs(Inspect.Debug()) do
		if line:find("^inspect " .. unit .. ":") then Log("%s%s", line, complete and "" or " (retrying)") end
	end
end

-- every teammate's talents asked for, the ones already answered included
local function InspectAll()
	for _, t in ipairs(Tracker.Teammates()) do Inspect.Want(t.unit, t.guid, t.class) end
end

-- who is here: the player, then party1 and party2 while they exist, with
-- their class and race (no inspect needed for either); outside an arena the
-- player alone
local function Roster()
	local list = {}
	for _, unit in ipairs(UNITS) do
		local wanted = (unit == "player" and ns.db.showSelf) or (unit ~= "player" and inArena)
		if wanted and UnitExists(unit) then
			local _, class = UnitClass(unit)
			local guid = UnitGUID(unit)
			if type(class) == "string" and plain(class) and ns.SPELLS[class] then
				list[#list + 1] = { unit = unit, guid = plain(guid) and guid or unit, class = class, race = RaceOf(unit) }
			end
		end
	end
	return list
end

-- which spells are watched: the spells ticked on or off, with a signature that
-- changes with them
function ns.Selection()
	local ids = {}
	for id, on in pairs(ns.db.picked) do ids[#ids + 1] = id .. (on and "+" or "-") end
	table.sort(ids)
	return { picked = ns.db.picked, sig = table.concat(ids, ",") }
end

local function ApplyRoster()
	local list = Roster()
	local sel = ns.Selection()
	-- before the gates nothing can have been used; outside an arena the own row
	-- starts as at the gates, so it tests the estimates as an arena would
	Tracker.SetRoster(list, sel, not (inArena and engaged))
	local watched = {}
	local names = {}
	for _, r in ipairs(list) do
		watched[r.unit] = true
		local t = Tracker.Get(r.unit)
		if t and not t.inspectAsked then   -- a new teammate (or a new GUID in the seat)
			t.inspectAsked = true
			Inspect.Want(r.unit, r.guid, r.class)
		end
		backend.SetWatch(r.unit, ns.FriendlyDefs(ns.SpellsFor(r.class, sel, r.race)), true)
		names[#names + 1] = r.unit .. "=" .. r.class .. (r.race and ("/" .. r.race) or "")
		-- the trinket: ask the server for the unit's crowd control cooldown data
		if ns.db.trinket and C_PvP and C_PvP.RequestCrowdControlSpell then pcall(C_PvP.RequestCrowdControlSpell, r.unit) end
	end
	for _, unit in ipairs(UNITS) do
		if not watched[unit] then
			backend.SetWatch(unit, {})
			Inspect.Forget(unit)
		end
	end
	-- the opponents: the debuffs of every crowd control the team has, its
	-- races' included (the player's own as well, so that a use of theirs is
	-- never a teammate's)
	local cc, seen = {}, {}
	local team = {}
	for _, r in ipairs(list) do team[#team + 1] = r end
	local _, own = UnitClass("player")
	if type(own) == "string" and plain(own) then team[#team + 1] = { class = own, race = RaceOf("player") } end
	for _, r in ipairs(team) do
		for _, def in ipairs(ns.EnemyDefs(ns.SpellsFor(r.class, sel, r.race))) do
			if not seen[def.id] then seen[def.id] = true; cc[#cc + 1] = def end
		end
	end
	if inArena then
		for _, unit in ipairs(ENEMIES) do backend.SetWatch(unit, cc, true) end
	end
	Log("roster %s", table.concat(names, " "))
	local problems = backend.Problems and backend.Problems()
	if problems and #problems > 0 then Log("backend: %s", table.concat(problems, "; ")) end
	ns.UI.Dirty()
end
ns.ApplyRoster = ApplyRoster

local InArena = ns.InArenaZone

-- Outside an arena, the player's own row while it is asked for: the backend
-- and the player's own talents for the player alone, from switching it on
-- to switching it off or entering an arena. Its cooldowns are the tracker's
-- estimates, as in an arena (that is what it is there to test); switched on,
-- every ability starts ready, as at the gates, and switching it off and on
-- again starts it afresh.
local function SelfWatch()
	local want = running and ns.db.showSelf and not inArena
	if want and not selfWatch then
		selfWatch = true
		Tracker.Clear()
		Log("watch own row")
		backend.Start(callbacks)
		Inspect.Start(Inspected)
		ApplyRoster()
	elseif not want and selfWatch then
		selfWatch = false
		Log("stop own row")
		backend.Stop()
		Inspect.Stop()
		Tracker.Clear()
	elseif want then
		ApplyRoster()
	end
end

-- Entering an arena, everything is ready: the gates reset every cooldown,
-- and nothing can be used before them. The round start says so again.
local function Scene()
	local arena = InArena()
	if arena and not inArena then
		inArena = true
		engaged = false
		selfWatch = false   -- the arena's own watching takes the player's row over
		Tracker.Clear()
		Log("enter arena")
		backend.Start(callbacks)
		Inspect.Start(Inspected)
		ApplyRoster()
		Tracker.RoundStart()
	elseif not arena and inArena then
		inArena = false
		engaged = false
		Log("leave arena")
		backend.Stop()
		Inspect.Stop()
		Tracker.Clear()
		SelfWatch()
	elseif arena then
		ApplyRoster()
	else
		SelfWatch()
	end
	ns.UI.Dirty()
end
ns.Scene = Scene

local ENGAGED = ns.ENGAGED

local function MatchState()
	if not inArena then return end
	local ok, state = pcall(C_PvP.GetActiveMatchState)
	Log("match state %s", tostring(state))
	if ok and state == ENGAGED then
		engaged = true
		Tracker.RoundStart()
		InspectAll()   -- talents may have changed in the waiting room
		ns.UI.Dirty()
	elseif ok then
		engaged = false   -- waiting, starting up, between rounds, complete
	end
end

-- ---------------------------------------------------------------------------
-- A teammate who cannot act
-- ---------------------------------------------------------------------------

-- Under a stun, a fear or a disorient a teammate casts nothing, so an external
-- or a crowd control seen then is someone else's (Tracker.lua). The game's
-- loss-of-control entries say it: on a teammate every field is secret but the
-- priority and the display type, and the priority tells the kind (measured in
-- AuraLab on 12.1: stun, fear and disorient 5, silence and disarm 3, an
-- interrupt 2, a root 1). Only 5 counts: a rooted or silenced teammate may
-- still have cast it.
local FULL_CONTROL = 5

local function Priority(data) return data.priority end   -- pcall'd: one function, no closure per entry

local function UnderControl(unit)
	local api = C_LossOfControl
	if not (api and api.GetActiveLossOfControlDataCountByUnit and api.GetActiveLossOfControlDataByUnit) then return false end
	local ok, count = pcall(api.GetActiveLossOfControlDataCountByUnit, unit)
	if not ok or type(count) ~= "number" or not plain(count) then return false end
	for i = 1, count do
		local okD, data = pcall(api.GetActiveLossOfControlDataByUnit, unit, i)
		if okD and type(data) == "table" then
			local okP, priority = pcall(Priority, data)
			if okP and type(priority) == "number" and plain(priority) and priority >= FULL_CONTROL then return true end
		end
	end
	return false
end

local function CheckControl(at)
	for _, unit in ipairs(UNITS) do Tracker.SetControlled(unit, UnderControl(unit), at) end
end

-- ---------------------------------------------------------------------------
-- Events and the update loop
-- ---------------------------------------------------------------------------

local driver = CreateFrame("Frame")
local acc = 0

driver:SetScript("OnEvent", function(_, event, a, b, c)
	if event == "PLAYER_ENTERING_WORLD" or event == "ZONE_CHANGED_NEW_AREA" then
		Scene()
	elseif event == "GROUP_ROSTER_UPDATE" or event == "PLAYER_REGEN_ENABLED" then
		if inArena then ApplyRoster() end
	elseif event == "PVP_MATCH_STATE_CHANGED" or event == "PVP_MATCH_ACTIVE" then
		MatchState()
	elseif event == "ARENA_COOLDOWNS_UPDATE" or event == "ARENA_CROWD_CONTROL_SPELL_UPDATE" then
		ns.UI.Dirty()   -- a trinket cooldown or the trinket itself changed: the rows draw it again
	elseif event == "INSPECT_READY" then
		if inArena then Inspect.Ready(a) end
	elseif event == "LOSS_OF_CONTROL_ADDED" or event == "LOSS_OF_CONTROL_UPDATE" then
		if inArena then CheckControl(GetTime()) end
	elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
		if a == "player" and type(c) == "number" then Tracker.OnPlayerCast(c) end
	elseif event == "PLAYER_SPECIALIZATION_CHANGED" or event == "TRAIT_CONFIG_UPDATED" or event == "PLAYER_PVP_TALENT_UPDATE" then
		-- the player's own talents changed: read again (no request, Inspect.lua)
		local me = Tracker.Get("player")
		if me and (event ~= "PLAYER_SPECIALIZATION_CHANGED" or a == nil or a == "player") then
			Inspect.Want("player", me.guid, me.class)
		end
	end
end)

-- the rows redraw when the tracker says something changed, and once a second
-- anyway: a cooldown that ran out changes a state without a word
local sinceFull = 0
local function OnUpdate(_, elapsed)
	acc = acc + elapsed
	sinceFull = sinceFull + elapsed
	if acc < 0.2 then return end
	acc = 0
	local at = GetTime()
	if inArena or selfWatch then
		Tracker.SelfTestCheck(at)
		Inspect.Tick(at)
	end
	if inArena then
		CheckControl(at)   -- the end of a control comes without an event of its own (its start does, exactly)
	end
	if sinceFull >= 1 or not ns.UI.IsLocked() or ns.UI.IsTesting() then
		sinceFull = 0
		ns.UI.Refresh(at)
	else
		ns.UI.RefreshIfDirty(at)
	end
end

local EVENTS = { "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA", "GROUP_ROSTER_UPDATE", "PLAYER_REGEN_ENABLED",
	"PVP_MATCH_STATE_CHANGED", "PVP_MATCH_ACTIVE", "ARENA_COOLDOWNS_UPDATE", "ARENA_CROWD_CONTROL_SPELL_UPDATE", "INSPECT_READY",
	"LOSS_OF_CONTROL_ADDED", "LOSS_OF_CONTROL_UPDATE", "PLAYER_SPECIALIZATION_CHANGED", "TRAIT_CONFIG_UPDATED",
	"PLAYER_PVP_TALENT_UPDATE" }

Tracker.AddListener(function(what, a, b)
	if what == "detection" then
		CK.Msg(a and L["Party CD: detection is back."] or L["Party CD: detection failed, the rows are dimmed."])
		Log("detection %s", a and "back" or "failed")
	elseif what == "use" then
		local state, readyAt, left = Tracker.State(b)
		Log("use %s %d cd=%.1f uses=%d %s%s%s", a.unit, b.def.id, b.cd, #b.uses, state,
			readyAt and string.format(" ready at %.1f", readyAt) or "", b.ambiguous and " ?" or "")
	elseif what == "round" then
		Log("round start")
	end
	ns.UI.Dirty()
end)

-- /ckpartycd status | log | clear: what the tracker holds, what was logged
SLASH_CKPARTYCD1 = "/ckpartycd"
SlashCmdList.CKPARTYCD = function(msg)
	msg = strtrim(msg or ""):lower()
	if msg == "log" then
		local log = ns.db and ns.db.log or {}
		for i = math.max(1, #log - 40), #log do print("  " .. log[i]) end
		CK.Msg("Party CD: %d log lines, the last %d shown", #log, math.min(#log, 41))
	elseif msg == "clear" then
		if ns.db then ns.db.log = {} end
		CK.Msg("Party CD: log cleared")
	else
		CK.Msg("Party CD: %s, %s", inArena and "in arena" or (selfWatch and "not in arena, own row watched" or "not in arena"),
			Tracker.failed and "detection failed" or "detection fine")
		for _, line in ipairs(Tracker.Debug()) do print("  " .. line) end
		for _, line in ipairs(Inspect.Debug()) do print("  " .. line) end
		local problems = backend and backend.Problems and backend.Problems() or {}
		for _, line in ipairs(problems) do print("  backend: " .. line) end
	end
end

-- ---------------------------------------------------------------------------
-- Module on / off
-- ---------------------------------------------------------------------------

-- the tests swap the detection for a fake one that reports what they say
function ns.UseBackend(b)
	if backend and (inArena or selfWatch) then backend.Stop() end
	backend = b
	if inArena or selfWatch then
		backend.Start(callbacks)
		ApplyRoster()
	end
end

function ns.GetBackend() return backend end

function ns.OnEnable()
	if not ns.db then InitDB() end
	backend = backend or ns.Backend
	running = true
	for _, e in ipairs(EVENTS) do pcall(driver.RegisterEvent, driver, e) end
	pcall(driver.RegisterUnitEvent, driver, "UNIT_SPELLCAST_SUCCEEDED", "player")
	driver:SetScript("OnUpdate", OnUpdate)
	ns.UI.Build()
	ns.UI.SetLocked(true)
	Scene()
end

function ns.OnDisable()
	running = false
	driver:UnregisterAllEvents()
	driver:SetScript("OnUpdate", nil)
	if inArena or selfWatch then
		inArena, selfWatch = false, false
		backend.Stop()
		Inspect.Stop()
	end
	Tracker.Clear()
	ns.UI.SetLocked(true)
	ns.UI.SetTest(false)
	ns.UI.Hide()
end

function ns.IsRunning() return running end
function ns.InArena() return inArena end
function ns.WatchingSelf() return selfWatch end

-- settings changed: redraw, and watch or stop watching the player and the ticked spells
function ns.Apply()
	if inArena then ApplyRoster() else SelfWatch() end
	ns.UI.Refresh()
end

function ns.IsLocked() return ns.UI.IsLocked() end
function ns.SetLocked(state) ns.UI.SetLocked(state) end
function ns.IsTesting() return ns.UI.IsTesting() end
function ns.SetTest(on) ns.UI.SetTest(on) end
function ns.ResetPositions() ns.UI.ResetPositions() end
