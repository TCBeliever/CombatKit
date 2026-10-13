local ADDON, ns = ...
local CK = CombatKit
local L = CK.L

CK.NewModule("PartyCD", ns)

-- ===========================================================================
-- The module: when to look (an arena, from entering to leaving), who to look
-- at (party1, party2, and the player as the reference), when a round starts,
-- and the glue between the backend, the tracker and the rows.
-- ===========================================================================

local Tracker = ns.Tracker
local UNITS = { "player", "party1", "party2" }
local backend
local inArena = false
local engaged = false   -- the gates are open: a teammate arriving now is unknown, before that ready
local running = false

-- ---------------------------------------------------------------------------
-- Saved data (CombatKitPartyCDDB, account-wide)
-- ---------------------------------------------------------------------------

ns.defaults = {
	showSelf    = false,     -- the player's own row (debug: it is the self-test's reference)
	externals   = true,
	disabled    = {},        -- [spellID] = true: not watched
	iconSize    = 28,
	spacing     = 2,
	maxPerRow   = 8,
	attach      = true,      -- hang the rows on the party frames when they can be found
	side        = "RIGHT",   -- "RIGHT" | "LEFT" | "TOP" | "BOTTOM": which side of the frame
	offset      = 4,         -- distance from the frame
	offsetAlong = 0,         -- shift along the frame's edge
	grow        = "right",   -- "right" | "down": a loose row's direction
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
end

-- ---------------------------------------------------------------------------
-- The scene
-- ---------------------------------------------------------------------------

-- a log of what the backend reported and what the tracker made of it, kept
-- in the saved variables for a match's post-mortem (/ckpartycd log)
local LOG_LINES = 400
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

local function plain(v) return type(canaccessvalue) ~= "function" or canaccessvalue(v) end

-- who is here: the player, then party1 and party2 while they exist
local function Roster()
	local list = {}
	for _, unit in ipairs(UNITS) do
		if (unit ~= "player" or ns.db.showSelf) and UnitExists(unit) then
			local _, class = UnitClass(unit)
			local guid = UnitGUID(unit)
			if type(class) == "string" and plain(class) and ns.SPELLS[class] then
				list[#list + 1] = { unit = unit, guid = plain(guid) and guid or unit, class = class }
			end
		end
	end
	return list
end

-- which spells are watched: the externals switch and the spells switched off,
-- with a signature that changes with them
function ns.Selection()
	local ids = {}
	for id in pairs(ns.db.disabled) do ids[#ids + 1] = id end
	table.sort(ids)
	return { externals = ns.db.externals, disabled = ns.db.disabled,
		sig = tostring(ns.db.externals) .. "|" .. table.concat(ids, ",") }
end

local function ApplyRoster()
	local list = Roster()
	local sel = ns.Selection()
	Tracker.SetRoster(list, sel, not engaged)
	local watched = {}
	local names = {}
	for _, r in ipairs(list) do
		watched[r.unit] = true
		backend.SetWatch(r.unit, ns.SpellsFor(r.class, sel), true)
		names[#names + 1] = r.unit .. "=" .. r.class
	end
	for _, unit in ipairs(UNITS) do
		if not watched[unit] then backend.SetWatch(unit, {}) end
	end
	Log("roster %s", table.concat(names, " "))
	local problems = backend.Problems and backend.Problems()
	if problems and #problems > 0 then Log("backend: %s", table.concat(problems, "; ")) end
	ns.UI.Dirty()
end
ns.ApplyRoster = ApplyRoster

local function InArena()
	local inInstance, kind = IsInInstance()
	return inInstance and kind == "arena"
end

-- Entering an arena, everything is ready: the gates reset every cooldown,
-- and nothing can be used before them. The round start says so again.
local function Scene()
	local arena = InArena()
	if arena and not inArena then
		inArena = true
		engaged = false
		Tracker.Clear()
		Log("enter arena")
		backend.Start(callbacks)
		ApplyRoster()
		Tracker.RoundStart()
	elseif not arena and inArena then
		inArena = false
		engaged = false
		Log("leave arena")
		backend.Stop()
		Tracker.Clear()
	elseif arena then
		ApplyRoster()
	end
	ns.UI.Dirty()
end
ns.Scene = Scene

local ENGAGED = (Enum and Enum.PvPMatchState and Enum.PvPMatchState.Engaged) or 3

local function MatchState()
	if not inArena then return end
	local ok, state = pcall(C_PvP.GetActiveMatchState)
	Log("match state %s", tostring(state))
	if ok and state == ENGAGED then
		engaged = true
		Tracker.RoundStart()
		ns.UI.Dirty()
	elseif ok then
		engaged = false   -- waiting, starting up, between rounds, complete
	end
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
	elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
		if a == "player" and type(c) == "number" then Tracker.OnPlayerCast(c) end
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
	if inArena then Tracker.SelfTestCheck(at) end
	if sinceFull >= 1 or not ns.UI.IsLocked() or ns.UI.IsTesting() then
		sinceFull = 0
		ns.UI.Refresh(at)
	else
		ns.UI.RefreshIfDirty(at)
	end
end

local EVENTS = { "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA", "GROUP_ROSTER_UPDATE", "PLAYER_REGEN_ENABLED",
	"PVP_MATCH_STATE_CHANGED", "PVP_MATCH_ACTIVE" }

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
		CK.Msg("Party CD: %s, %s", inArena and "in arena" or "not in arena", Tracker.failed and "detection failed" or "detection fine")
		for _, line in ipairs(Tracker.Debug()) do print("  " .. line) end
		local problems = backend and backend.Problems and backend.Problems() or {}
		for _, line in ipairs(problems) do print("  backend: " .. line) end
	end
end

-- ---------------------------------------------------------------------------
-- Module on / off
-- ---------------------------------------------------------------------------

-- the tests swap the detection for a fake one that reports what they say
function ns.UseBackend(b)
	if backend and inArena then backend.Stop() end
	backend = b
	if inArena then
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
	if inArena then
		inArena = false
		backend.Stop()
	end
	Tracker.Clear()
	ns.UI.SetLocked(true)
	ns.UI.SetTest(false)
	ns.UI.Hide()
end

function ns.IsRunning() return running end
function ns.InArena() return inArena end

-- settings changed: redraw, and watch or stop watching the player and the externals
function ns.Apply()
	if inArena then ApplyRoster() end
	ns.UI.Refresh()
end

function ns.IsLocked() return ns.UI.IsLocked() end
function ns.SetLocked(state) ns.UI.SetLocked(state) end
function ns.IsTesting() return ns.UI.IsTesting() end
function ns.SetTest(on) ns.UI.SetTest(on) end
function ns.ResetPositions() ns.UI.ResetPositions() end
