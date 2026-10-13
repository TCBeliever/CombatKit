local ADDON, ns = ...
local CK = CombatKit
local L = CK.L

CK.NewModule("Arena", ns)

-- ===========================================================================
-- The module: when to look (an arena, from entering to leaving), who to look
-- at (party1, party2, and the player as the reference), when a round starts,
-- and the glue between the backend, the tracker and the rows.
-- ===========================================================================

local Tracker = ns.Tracker
local UNITS = { "player", "party1", "party2" }
local backend
local inArena = false
local running = false

-- ---------------------------------------------------------------------------
-- Saved data (CombatKitArenaDB, account-wide)
-- ---------------------------------------------------------------------------

ns.defaults = {
	showSelf    = true,
	externals   = true,
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
	if type(CombatKitArenaDB) ~= "table" then CombatKitArenaDB = {} end
	ns.db = FillDefaults(CombatKitArenaDB, ns.defaults)
end

-- ---------------------------------------------------------------------------
-- The scene
-- ---------------------------------------------------------------------------

local callbacks = {
	Shown = function(...) Tracker.Shown(...) end,
	Hidden = function(...) Tracker.Hidden(...) end,
	Expired = function(...) Tracker.Expired(...) end,
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

local function ApplyRoster()
	local list = Roster()
	Tracker.SetRoster(list, ns.db.externals)
	local watched = {}
	for _, r in ipairs(list) do
		watched[r.unit] = true
		backend.SetWatch(r.unit, ns.SpellsFor(r.class, ns.db.externals), true)
	end
	for _, unit in ipairs(UNITS) do
		if not watched[unit] then backend.SetWatch(unit, {}) end
	end
	ns.UI.Dirty()
end
ns.ApplyRoster = ApplyRoster

local function InArena()
	local inInstance, kind = IsInInstance()
	return inInstance and kind == "arena"
end

local function Scene()
	local arena = InArena()
	if arena and not inArena then
		inArena = true
		Tracker.Clear()
		backend.Start(callbacks)
		ApplyRoster()
	elseif not arena and inArena then
		inArena = false
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
	if ok and state == ENGAGED then
		Tracker.RoundStart()
		ns.UI.Dirty()
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

local function OnUpdate(_, elapsed)
	acc = acc + elapsed
	if acc < 0.2 then return end
	acc = 0
	local at = GetTime()
	if inArena then Tracker.SelfTestCheck(at) end
	if inArena or not ns.UI.IsLocked() then ns.UI.Refresh(at) else ns.UI.RefreshIfDirty(at) end
end

local EVENTS = { "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA", "GROUP_ROSTER_UPDATE", "PLAYER_REGEN_ENABLED",
	"PVP_MATCH_STATE_CHANGED", "PVP_MATCH_ACTIVE" }

Tracker.AddListener(function(what, ok)
	if what == "detection" then
		CK.Msg(ok and L["Arena: detection is back."] or L["Arena: detection failed, the rows are dimmed."])
	end
	ns.UI.Dirty()
end)

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
function ns.ResetPositions() ns.UI.ResetPositions() end
