local ADDON, ns = ...
local CK = CombatKit
local L = CK.L
local U = ns.Util

CK.NewModule("PvP", ns)

-- ===========================================================================
-- The module: arena only. Watches the roster, inspects teammates for their
-- spec and talents, starts the tracker when a round is on and stops it when
-- it is over. /ckpvp shows what it is doing; /ckpvp solo tries the whole
-- thing on the player alone, anywhere.
--
-- Beta. What it shows are estimates read off the buffs teammates get; see
-- Tracker.lua for what can go wrong, Probe.lua for how a secret buff becomes
-- a yes or a no, and why the module gives up rather than guess.
-- ===========================================================================

ns.TICK = 0.1

-- ---------------------------------------------------------------------------
-- Saved data (CombatKitPvPDB, account-wide)
-- ---------------------------------------------------------------------------

ns.defaults = {
	iconSize  = 28,
	spacing   = 2,
	maxPerRow = 8,
	fontSize  = 12,
	attach    = true,       -- next to the party frames; off: where the rows were dragged to
	side      = "RIGHT",    -- which side of the party frame the row sits on
	offset    = 6,
	offsetY   = 0,
	showTimer = true,
	glow      = true,
	showTrinket = true,     -- the PvP trinket, first in the row (C_PvP knows its cooldown)
	disabled  = {},         -- ability id -> true: not tracked (Monitoring page)
	cooldowns = {},         -- ability id -> seconds set by hand (/ckpvp cd)
	solo = false,           -- /ckpvp solo: kept across reloads, so a test session needs no typing
	rows = {   -- where a row goes when no party frame is found for its unit
		party1 = { point = "CENTER", relPoint = "CENTER", x = -300, y = 60 },
		party2 = { point = "CENTER", relPoint = "CENTER", x = -300, y = 20 },
		player = { point = "CENTER", relPoint = "CENTER", x = -300, y = 100 },
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
	if type(CombatKitPvPDB) ~= "table" then CombatKitPvPDB = {} end
	ns.db = FillDefaults(CombatKitPvPDB, ns.defaults)
end

-- ---------------------------------------------------------------------------
-- State
-- ---------------------------------------------------------------------------

local running = false        -- the module is on
local unavailable = nil      -- reason key, once the self test failed
local unavailableDetail      -- what the client said, for "refused"
local inArena = false        -- an arena, or solo mode
local solo = false
local matchState = nil
local live = false           -- a round is on: scanning
local tickAcc, slowAcc, snapshotAcc = 0, 0, 0

local STATE = { Inactive = 0, Waiting = 1, StartUp = 2, Engaged = 3, PostRound = 4, Complete = 5 }

function ns.IsRunning() return running end
function ns.IsLive() return live end
-- the icons are on screen from the moment the arena is entered, every cooldown ready,
-- until the module has a reason to show nothing
local function Showing() return inArena and not unavailable and not ns.Tracker.paused end
function ns.IsShowing() return Showing() end
function ns.IsSolo() return solo end

local function Refused()
	local b = ns.Probe.backend
	return b.Refused and b.Refused() or nil
end

function ns.ReasonText(reason, detail)
	local text = L["PVP_REASON_" .. reason]
	if reason == "refused" then text = string.format(text, tostring(detail or "?")) end
	return text
end

-- "unavailable" | "paused" | "scanning" | "ready" | "idle", and the reason for the first two
function ns.State()
	if unavailable then return "unavailable", ns.ReasonText(unavailable, unavailableDetail) end
	if ns.Tracker.paused then return "paused", ns.ReasonText(ns.Tracker.paused, Refused()) end
	if live then return "scanning" end
	if inArena then return "ready" end
	return "idle"
end

function ns.Stats() return ns.Tracker.stats end

-- Is this ability tracked at all? The Monitoring page's role switches and per-ability list.
function ns.Allowed(ability)
	return ns.db.disabled[ability.id] ~= true
end

-- the settings about what is tracked changed: entries again, the same timers kept
function ns.RebuildEntries()
	ns.Tracker.Rebuild()
	if inArena then
		ns.Probe.backend.Prepare(ns.Tracker.WATCHED, ns.Tracker.Needed())
		ns.Display.PrepareGlow()
	end
	ns.Refresh()
end

local function IsArena()
	local ok, _, kind = pcall(IsInInstance)
	return ok and canaccessvalue(kind) == true and kind == "arena"
end

local function MatchState()
	if solo and not IsArena() then return STATE.Engaged end
	if not (C_PvP and C_PvP.GetActiveMatchState) then return nil end
	return U.Plain(C_PvP.GetActiveMatchState)
end

function ns.PlayerSpec()
	local api = C_SpecializationInfo
	local index = U.Plain(api and api.GetSpecialization or GetSpecialization)
	if type(index) ~= "number" then return nil end
	local id = U.Plain(api and api.GetSpecializationInfo or GetSpecializationInfo, index)
	return type(id) == "number" and id > 0 and id or nil
end

-- ---------------------------------------------------------------------------
-- Roster
-- ---------------------------------------------------------------------------

-- A teammate that is a bot (a match against NPCs): nothing to inspect, no cooldowns
-- worth showing. A bot answers UnitIsPlayer or carries a player GUID with extra parts.
local function IsNpc(unit, guid)
	if type(UnitIsPlayer) == "function" and U.Plain(UnitIsPlayer, unit) == false then return true end
	if type(guid) == "string" and guid:match("^Player%-") then
		local _, dashes = guid:gsub("%-", "")
		if dashes > 2 then return true end
	end
	return false
end
ns.IsNpc = IsNpc

local npcNoted = {}
local function ReadRoster()
	local roster, enemies, signature = {}, {}, {}
	for _, unit in ipairs(ns.Tracker.UNITS) do
		local friendly = unit == "player" or U.Plain(UnitCanAssist, "player", unit) ~= false
		if U.Plain(UnitExists, unit) == true and friendly then
			local ok, _, class = pcall(UnitClass, unit)
			local guid = U.Plain(UnitGUID, unit)
			if ok and canaccessvalue(class) and type(class) == "string" and type(guid) == "string" and IsNpc(unit, guid) then
				if not npcNoted[guid] then
					npcNoted[guid] = true
					U.Log("roster", unit, nil, "a bot: not tracked")
				end
			elseif ok and canaccessvalue(class) and type(class) == "string" and type(guid) == "string" then
				local info = ns.Inspect.InfoFor(guid)
				local role = U.Plain(UnitGroupRolesAssigned, unit)
				roster[unit] = { guid = guid, class = class, spec = info and info.spec or nil, info = info, role = role }
				signature[#signature + 1] = unit .. "=" .. guid .. ":" .. tostring(info and info.spec) .. ":"
					.. tostring(info and info.at) .. ":" .. tostring(role)
			end
		end
	end
	for _, unit in ipairs(ns.Tracker.ENEMIES) do
		if U.Plain(UnitExists, unit) == true and U.Plain(UnitCanAttack, "player", unit) == true then
			local guid = U.Plain(UnitGUID, unit)
			enemies[unit] = { guid = type(guid) == "string" and guid or "?" }
			signature[#signature + 1] = unit .. "=" .. enemies[unit].guid
		end
	end
	return roster, enemies, table.concat(signature, "|")
end

local lastSignature
local function SyncRoster(force)
	local roster, enemies, signature = ReadRoster()
	if force or signature ~= lastSignature then
		lastSignature = signature
		if C_PvP and C_PvP.RequestCrowdControlSpell then
			for unit in pairs(roster) do pcall(C_PvP.RequestCrowdControlSpell, unit) end
		end
		ns.Tracker.SetRoster(roster, enemies)
		ns.Probe.backend.Prepare(ns.Tracker.WATCHED, ns.Tracker.Needed())
		ns.Display.PrepareGlow()
		return true
	end
	return false
end

-- ---------------------------------------------------------------------------
-- Arena lifecycle
-- ---------------------------------------------------------------------------

-- true: the probe works here. false: it never will (said so). nil: not now (combat).
local function SelfTest()
	if unavailable then return false end
	if ns.selfTested then return true end
	local backend = ns.Probe.backend
	if not backend.SelfTest then
		ns.selfTested = true
		return true
	end
	local ok, reason, detail = backend.SelfTest()
	if ok == nil then return nil end
	if not ok then
		unavailable, unavailableDetail = reason, detail
		U.Log("unavailable", nil, nil, ns.ReasonText(reason, detail))
		CK.Msg(L["PVP_UNAVAILABLE"], ns.ReasonText(reason, detail))
		ns.Display.HideAll()
		CK.RefreshOptions()
		ns.Snapshot("unavailable")
		return false
	end
	ns.selfTested = true
	return true
end

function ns.OnTrackerPaused(reason)
	live, ns.Tracker.live = false, false   -- at once, not at the next lifecycle tick: nothing is painted meanwhile
	CK.Msg(L["PVP_PAUSED"], ns.ReasonText(reason, Refused()))
	ns.Display.HideAll()
	CK.RefreshOptions()
	ns.Snapshot("paused")
end

local function Prepare()
	if SelfTest() then
		ns.Probe.backend.Prepare(ns.Tracker.WATCHED, ns.Tracker.Needed())
		ns.Display.PrepareGlow()
	end
end

local function EnterArena()
	inArena = true
	matchState = nil
	live = false
	ns.Tracker.live = false
	ns.Tracker.Clear()
	ns.Inspect.Reset()
	ns.Control.Reset()
	ns.Display.ClearGlow()
	if ns.Probe.backend.ResetCircuits then ns.Probe.backend.ResetCircuits() end
	lastSignature = nil
	U.Log("arena", nil, nil, solo and "solo" or "entered")
	if solo then ns.Inspect.ReadSelf() end
	Prepare()
	SyncRoster(true)
end

local function LeaveArena()
	inArena = false
	live = false
	matchState = nil
	ns.Tracker.live = false
	ns.Tracker.Clear()
	ns.Display.HideAll()
	ns.Display.ClearGlow()
end

-- Match state: scanning only while a round is engaged; a new round resets the timers.
local function Lifecycle()
	local active = IsArena() or solo
	if active ~= inArena then
		if active then EnterArena() else LeaveArena() end
	end
	if not inArena then return end
	local state = MatchState()
	if state ~= matchState then
		U.Log("match", nil, nil, tostring(matchState) .. " -> " .. tostring(state))
		if state == STATE.Engaged then
			ns.Tracker.ResetTimers()
			SyncRoster(true)
			Prepare()
		end
		matchState = state
	end
	live = state == STATE.Engaged and not unavailable and not ns.Tracker.paused
	ns.Tracker.live = live
end

-- Solo: the player stands in for a teammate, the target for an enemy, here and now.
function ns.SetSolo(on)
	on = on and true or false
	if on == solo then return end
	if inArena then LeaveArena() end
	solo = on
	ns.db.solo = on
	ns.Tracker.SetSolo(on)
	lastSignature = nil
	Lifecycle()
	CK.Msg("%s", L[on and "PVP_SOLO_ON" or "PVP_SOLO_OFF"])
	CK.RefreshOptions()
end

-- ---------------------------------------------------------------------------
-- Driver
-- ---------------------------------------------------------------------------

local driver = CreateFrame("Frame")

local EVENTS = { "PLAYER_ENTERING_WORLD", "GROUP_ROSTER_UPDATE", "INSPECT_READY", "PVP_MATCH_STATE_CHANGED",
	"PVP_MATCH_ACTIVE", "PVP_MATCH_COMPLETE", "PVP_MATCH_INACTIVE", "PLAYER_REGEN_ENABLED", "ZONE_CHANGED_NEW_AREA",
	"LOSS_OF_CONTROL_ADDED", "LOSS_OF_CONTROL_UPDATE", "PLAYER_TARGET_CHANGED", "TRAIT_CONFIG_UPDATED",
	"PLAYER_SPECIALIZATION_CHANGED", "PLAYER_LOGOUT", "PLAYER_REGEN_DISABLED",
	"ARENA_COOLDOWNS_UPDATE", "ARENA_CROWD_CONTROL_SPELL_UPDATE" }

driver:SetScript("OnEvent", function(_, event, arg1, _, arg3)
	if event == "PLAYER_LOGOUT" then
		ns.Snapshot("logout")
		return
	end
	if event == "UNIT_SPELLCAST_SUCCEEDED" then
		if canaccessvalue(arg1) and arg1 == "player" and canaccessvalue(arg3) then ns.Tracker.OnPlayerCast(arg3) end
		return
	end
	if event == "LOSS_OF_CONTROL_ADDED" or event == "LOSS_OF_CONTROL_UPDATE" then
		ns.Control.Learn()
		return
	end
	if event == "INSPECT_READY" then
		if inArena and ns.Inspect.OnReady(arg1, ns.Tracker.roster, ns.Tracker.UNITS) then SyncRoster() end
		return
	end
	if event == "TRAIT_CONFIG_UPDATED" or event == "PLAYER_SPECIALIZATION_CHANGED" then
		if solo and inArena then
			ns.Inspect.ReadSelf()
			SyncRoster()
		end
		return
	end
	if event == "PLAYER_TARGET_CHANGED" then
		if solo and inArena then
			U.Log("target", nil, nil, U.Plain(UnitExists, "target") and (U.Plain(UnitCanAttack, "player", "target") and "enemy" or "friendly") or "none")
			SyncRoster()
		end
		return
	end
	if event == "PLAYER_REGEN_DISABLED" then
		if inArena then U.Log("combat", nil, nil, "start") end
		return
	end
	if event == "ARENA_COOLDOWNS_UPDATE" or event == "ARENA_CROWD_CONTROL_SPELL_UPDATE" then
		ns.Display.Dirty()   -- a teammate's trinket: the game tells, the icon follows at the next paint
		return
	end
	if event == "PLAYER_REGEN_ENABLED" and inArena then U.Log("combat", nil, nil, "end") end
	Lifecycle()
	if event == "GROUP_ROSTER_UPDATE" or event == "PLAYER_ENTERING_WORLD" then
		if inArena then
			SyncRoster()
			ns.Display.Dirty()
		end
	end
	if event == "PLAYER_REGEN_ENABLED" and inArena then
		Prepare()   -- pools, slots and glow lanes that combat held back
	end
end)

local function OnUpdate(_, elapsed)
	tickAcc = tickAcc + elapsed
	slowAcc = slowAcc + elapsed
	if slowAcc >= 1 then
		slowAcc = 0
		snapshotAcc = snapshotAcc + 1
		if snapshotAcc >= ns.SNAPSHOT_EVERY then
			snapshotAcc = 0
			ns.Snapshot()
		end
		Lifecycle()
		if inArena then
			SyncRoster()
			ns.Inspect.Tick(GetTime(), ns.Tracker.roster, ns.Tracker.UNITS)
			if ns.Display.LanesPending() and not InCombatLockdown() then ns.Display.PrepareGlow() end
			ns.Display.Dirty()   -- frames may have appeared
		end
	end
	if tickAcc < ns.TICK then return end
	tickAcc = 0
	if live then
		local now = GetTime()
		pcall(ns.Control.Tick, now, ns.Tracker.roster)
		local ok, err = pcall(ns.Tracker.Tick, now)
		if not ok then
			ns.lastError = tostring(err)
			U.Log("error", nil, nil, tostring(err))
			ns.Tracker.Pause("refused")
			ns.Snapshot("error")
		end
	end
	if inArena or ns.Display.IsTesting() then ns.Display.Update(GetTime(), Showing()) end
end

-- the display, from the settings
function ns.Refresh()
	if inArena or ns.Display.IsTesting() then
		ns.Display.Dirty()
		ns.Display.Update(GetTime(), Showing())
	else
		ns.Display.HideAll()
	end
end

-- ---------------------------------------------------------------------------
-- /ckpvp
-- ---------------------------------------------------------------------------

local function Say(text) CK.Msg("%s", text) end
ns.Say, ns.L = Say, L

function ns.StatusLines()
	local state, reason = ns.State()
	local s = ns.Tracker.stats
	local where = solo and "solo" or (inArena and "arena" or "not in arena")
	local lines = {
		string.format("PvP %s | %s%s | match state %s", where, L["PVP_STATE_" .. state], reason and (": " .. reason) or "",
			tostring(matchState)),
		string.format(L["PVP_STATS"], s.scans, s.positives, s.invalid) .. string.format(", %d discarded", s.discarded),
		"probe: " .. (ns.Probe.backend.Status and ns.Probe.backend.Status() or "fake"),
		"glow: " .. ns.Display.GlowStatus() .. " | FrameSort: " .. (ns.Display.FrameSortHooked() and "hooked" or "not loaded"),
		string.format("inspect: %d requests, %d ready, %d reads", ns.Inspect.stats.requests, ns.Inspect.stats.ready,
			ns.Inspect.stats.reads),
	}
	for _, unit in ipairs(ns.Tracker.UNITS) do
		local r = ns.Tracker.roster[unit]
		if r then
			lines[#lines + 1] = string.format("  %s %s spec=%s entries=%d | %s | %s", unit, r.class, tostring(r.spec),
				#ns.Tracker.Entries(unit), ns.Inspect.Describe(unit, r.guid), ns.Control.Describe(unit))
		end
	end
	local enemies = {}
	for _, unit in ipairs(ns.Tracker.ENEMIES) do
		if ns.Tracker.enemies[unit] then enemies[#enemies + 1] = unit end
	end
	lines[#lines + 1] = "  enemies: " .. (#enemies > 0 and table.concat(enemies, ", ") or "none")
	return lines
end

-- What /ckpvp status, entries and log would print, kept in the saved variables so
-- it can be read from the file after a reload, without typing anything in game.
ns.SNAPSHOT_EVERY = 5
function ns.Snapshot(why)
	if not ns.db then return end
	local now = GetTime()
	if inArena then
		local rows = ns.Display.Describe()
		if #rows > 0 then ns.rowsLastArena = rows end
	end
	local entries = {}
	for _, unit in ipairs(ns.Tracker.UNITS) do
		local r = ns.Tracker.roster[unit]
		entries[#entries + 1] = string.format("%s %s spec=%s", unit, r and r.class or "-", tostring(r and r.spec))
		for _, line in ipairs(ns.Tracker.Describe(unit, now)) do entries[#entries + 1] = line end
	end
	-- the talents read, with their names: how a talent the module does not know yet is found
	local talents = {}
	local name = C_Spell and C_Spell.GetSpellName
	for _, unit in ipairs(ns.Tracker.UNITS) do
		local r = ns.Tracker.roster[unit]
		local info = r and r.info
		if info then
			local ids = {}
			for id in pairs(info.talents or {}) do ids[#ids + 1] = id end
			table.sort(ids)
			for _, id in ipairs(ids) do
				talents[#talents + 1] = string.format("%s %d r%d %s", unit, id, info.talents[id], name and tostring(U.Plain(name, id)) or "")
			end
			for id in pairs(info.pvp or {}) do
				talents[#talents + 1] = string.format("%s pvp %d %s", unit, id, name and tostring(U.Plain(name, id)) or "")
			end
		end
	end
	ns.db.debug = {
		at = date("%Y-%m-%d %H:%M:%S"), why = why or "tick", version = C_AddOns.GetAddOnMetadata("CombatKit", "Version"),
		status = ns.StatusLines(), entries = entries, log = U.LogLines(U.LOG_CAP), lastError = ns.lastError,
		talents = talents, rows = ns.Display.Describe(), rowsLastArena = ns.rowsLastArena,
	}
end

function ns.Slash(msg)
	msg = strtrim(msg or "")
	local cmd, rest = msg:match("^(%S*)%s*(.*)$")
	cmd = (cmd or ""):lower()
	if cmd == "" or cmd == "status" then
		for _, line in ipairs(ns.StatusLines()) do Say(line) end
	elseif cmd == "log" then
		local lines = U.LogLines(tonumber(rest) or 20)
		local held, total = U.LogCount()
		Say(string.format("log: last %d of %d (%d held)", #lines, total, held))
		for _, line in ipairs(lines) do print(line) end
	elseif cmd == "entries" then
		local now = GetTime()
		if not inArena then Say(L["PVP_ENTRIES_IDLE"]) end
		for _, unit in ipairs(ns.Tracker.UNITS) do
			local r = ns.Tracker.roster[unit]
			Say(string.format("%s %s spec=%s", unit, r and r.class or "-", tostring(r and r.spec)))
			for _, line in ipairs(ns.Tracker.Describe(unit, now)) do print(line) end
		end
	elseif cmd == "cd" then
		local id, seconds = rest:match("^(%d+)%s*(%S*)$")
		id = tonumber(id)
		local ability = id and ns.Spells.BY_ID[id]
		if not ability then
			Say(L["PVP_CD_USAGE"])
			return
		end
		if seconds == "" or seconds == "reset" then
			ns.db.cooldowns[id] = nil
			Say(string.format(L["PVP_CD_RESET"], ability.name, ability.cd))
		else
			local n = tonumber(seconds)
			if not n or n < 1 or n > 900 then Say(L["PVP_CD_USAGE"]) return end
			ns.db.cooldowns[id] = math.floor(n)
			Say(string.format(L["PVP_CD_SET"], ability.name, math.floor(n)))
		end
		ns.Tracker.SetCustom(ns.db.cooldowns)
	elseif cmd == "scan" then
		ns.Scan.Start()
	elseif cmd == "solo" then
		ns.SetSolo(not solo)
	elseif cmd == "test" then
		ns.Display.SetTesting(not ns.Display.IsTesting())
	else
		Say("/ckpvp status | log [n] | entries | cd <spellID> <seconds|reset> | solo | scan | test")
	end
	ns.Snapshot("slash " .. cmd)
end

-- ---------------------------------------------------------------------------
-- Module on / off
-- ---------------------------------------------------------------------------

function ns.OnEnable()
	if not ns.db then InitDB() end
	running = true
	ns.Tracker.SetCustom(ns.db.cooldowns)
	for _, e in ipairs(EVENTS) do pcall(driver.RegisterEvent, driver, e) end
	pcall(driver.RegisterUnitEvent, driver, "UNIT_SPELLCAST_SUCCEEDED", "player")
	driver:SetScript("OnUpdate", OnUpdate)
	ns.Display.HookFrameSort()
	SLASH_COMBATKITPVP1 = "/ckpvp"
	SlashCmdList.COMBATKITPVP = ns.Slash
	-- the self test needs frames, which combat forbids; out of combat it runs now
	if not InCombatLockdown() then SelfTest() end
	if ns.db.solo and not solo then
		solo = true
		ns.Tracker.SetSolo(true)
		CK.Msg("%s", L["PVP_SOLO_STILL"])
	end
	Lifecycle()
end

function ns.OnDisable()
	ns.Snapshot("disable")
	running = false
	driver:UnregisterAllEvents()
	driver:SetScript("OnUpdate", nil)
	ns.Display.SetLocked(true)
	if ns.Display.IsTesting() then ns.Display.SetTesting(false) end
	if solo then ns.SetSolo(false) end
	ns.db.solo = false
	LeaveArena()
	-- switched on again, the self test runs again: a reason to try is a reason to retry
	unavailable, unavailableDetail, ns.selfTested = nil, nil, nil
end

-- for the tests
ns._Lifecycle = Lifecycle
ns._SyncRoster = SyncRoster
ns._Tick = function(elapsed) OnUpdate(nil, elapsed) end
