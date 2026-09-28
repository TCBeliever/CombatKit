local ADDON, ns = ...
local L = ns.L
local CK = CombatKit

-- ---------------------------------------------------------------------------
-- Saved data (CombatKitLoadoutDB)
--
--   CombatKitLoadoutDB = {
--     version  = 1,
--     settings = { auto=, early=, hud = "always" | "mismatch", gearCheck= },   -- account-wide
--     chars    = {
--       ["Name - Realm"] = {
--         class      = "DEMONHUNTER",
--         split      = { pve = false, pvp = false },   -- group split into its scenarios
--         warmodePvP = false,                           -- open world with War Mode uses PvP
--         groups     = { pve = { specs = {} }, pvp = { specs = {} } },
--         scenarios  = { dungeon = { custom = false, specs = {}, autoSpec = nil }, ... },
--       },
--     },
--   }
--   specs[specID] = { configID=, configName=, setID=, setName= }
--
-- Per character because talent loadouts and equipment sets are.
-- ---------------------------------------------------------------------------

ns.defaults = {
	auto  = false,      -- switch talents and gear on entering a scenario / changing spec
	early = true,       -- show the upcoming scenario on a queue pop
	hud   = "always",   -- this module's HUD lines: "always" | "mismatch"
	gearCheck = true,   -- a text on screen when the gear does not fit the scenario
}

local function InitDB()
	if type(CombatKitLoadoutDB) ~= "table" then CombatKitLoadoutDB = {} end
	local db = CombatKitLoadoutDB
	db.version  = db.version or 1
	db.settings = db.settings or {}
	db.chars    = db.chars or {}
	for k, v in pairs(ns.defaults) do
		if db.settings[k] == nil then db.settings[k] = v end
	end
	ns.db = db
end

local function InitChar()
	local key = UnitName("player") .. " - " .. GetRealmName()
	local char = ns.db.chars[key] or {}
	ns.db.chars[key] = char
	char.class = select(2, UnitClass("player"))
	char.split = char.split or {}
	char.groups = char.groups or {}
	for _, group in ipairs(ns.GROUPS) do
		if char.split[group] == nil then char.split[group] = false end
		char.groups[group] = char.groups[group] or {}
		char.groups[group].specs = char.groups[group].specs or {}
	end
	if char.warmodePvP == nil then char.warmodePvP = false end
	char.scenarios = char.scenarios or {}
	for _, s in ipairs(ns.SCENARIOS) do
		local e = char.scenarios[s.key] or {}
		char.scenarios[s.key] = e
		if e.custom == nil then e.custom = false end
		e.specs = e.specs or {}
	end
	ns.char = char
end

-- ---------------------------------------------------------------------------
-- The check
--
-- Talents and gear are applied once per trigger: entering a scenario (logging
-- in counts) and changing spec. What the player changes by hand afterwards is
-- left alone; the HUD shows the difference and a click applies again.
-- ---------------------------------------------------------------------------

local LFG_EARLY_TIMEOUT = 60
local RETRY_WINDOW      = 10

local running = false              -- between OnEnable and OnDisable
local currentKey, currentWarmode   -- what the last check ran for
local enteredAt                    -- GetTime() when currentKey was entered
local wantAuto = false             -- an automatic apply is owed
local wantSpec = false             -- ...including the scenario's spec (only on entering)
local earlyBG, earlyLFG            -- scenario of a queue pop that is waiting for an answer
local checkQueued = false

function ns.GetCurrentScenario()
	return ns.char and ns.DetectScenario() or nil
end

function ns.GetEarlyScenario()
	return ns.debug.early or earlyBG or earlyLFG
end

function ns.IsAutoPending() return wantAuto end

-- A spec switch never takes the player out of the role a group gave them: a
-- healer who steps out of the dungeon must not come back as damage. Without an
-- assigned role (solo, friends, an NPC companion) nothing stands in the way.
local function RoleBlocks(targetSpecID)
	local assigned = ns.GetAssignedRole()
	local spec = ns.GetSpecByID(targetSpecID)
	if not assigned or not spec or not spec.role or spec.role == assigned then return false end
	ns.Msg(L["Not switching to %s: your role in this group is %s."], spec.name, L["ROLE_" .. assigned])
	return true
end

local function RunAuto(key)
	if not wantAuto then return end
	if not ns.db.settings.auto then
		wantAuto, wantSpec = false, false
		return
	end
	-- keeps being owed: a pending pop, combat, a running key or match, an apply in progress
	if ns.GetEarlyScenario() or InCombatLockdown() or ns.IsLocked() or ns.IsApplying() then return end

	local specID = ns.GetCurrentSpecID()
	if not specID then return end
	wantAuto = false

	local _, _, autoSpec = ns.ResolveTarget(key, specID)
	local targetSpec
	if wantSpec and autoSpec and autoSpec ~= specID and not RoleBlocks(autoSpec) then targetSpec = autoSpec end
	wantSpec = false

	local state = ns.GetStatus(key).state
	ns.Debug("auto: %s is %s%s", key, state, targetSpec and ", spec switch" or "")
	if not targetSpec and state ~= "mismatch" then return end
	local setup = ns.BuildSetup(key, targetSpec)
	if setup then ns.ApplySetup(setup) end
end

-- trigger: "spec" (the spec changed) | "retry" (second pass after a loading screen) | nil
function ns.Check(trigger)
	if not running or not ns.char then return end
	local key = ns.DetectScenario()
	local warmode = key == "world" and ns.IsWarMode()
	if key ~= currentKey or warmode ~= currentWarmode then
		ns.Debug("entered %s%s", key, warmode and " (war mode)" or "")
		currentKey, currentWarmode = key, warmode
		wantAuto, wantSpec = true, true
		enteredAt = GetTime()
	end
	if trigger == "spec" then
		wantAuto = true
	elseif trigger == "retry" and enteredAt and GetTime() - enteredAt <= RETRY_WINDOW then
		-- only a scenario that was just entered is owed a second pass; a loading
		-- screen inside the same scenario must not undo what was changed by hand
		wantAuto = true
	end
	RunAuto(key)
	ns.UpdateGearWarning(key)
	ns.UpdateHUD()
end

-- Events come in bursts (an equipment swap is one event per slot).
function ns.QueueCheck(delay)
	if checkQueued then return end
	checkQueued = true
	C_Timer.After(delay or 0.3, function()
		checkQueued = false
		ns.Check()
	end)
end

-- The player interrupted a cast of ours: nothing is owed any more, and the
-- second pass after a loading screen must not ask again either. The next
-- entry or spec change starts afresh.
function ns.OnApplyInterrupted()
	wantAuto, wantSpec, enteredAt = false, false, nil
end

-- Debug page: run the check as if the scenario had just been entered.
function ns.EnterAgain()
	currentKey = nil
	ns.Check()
end

-- The HUD was clicked: apply what it shows, now, the spec it names included.
function ns.ApplyNow()
	if not running or not ns.char then return end
	local key = ns.GetEarlyScenario() or ns.DetectScenario()
	local st = ns.GetStatus(key)
	if st.state ~= "mismatch" then return end
	local setup = ns.BuildSetup(key, st.targetSpecID)
	if setup then ns.ApplySetup(setup) end
	ns.UpdateHUD()
end

-- ---------------------------------------------------------------------------
-- Events
-- ---------------------------------------------------------------------------

local EVENTS = {
	"PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA", "WAR_MODE_STATUS_UPDATE",
	"PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED",
	"PLAYER_SPECIALIZATION_CHANGED",
	"TRAIT_CONFIG_UPDATED", "TRAIT_CONFIG_LIST_UPDATED", "ACTIVE_COMBAT_CONFIG_CHANGED", "CONFIG_COMMIT_FAILED",
	"UNIT_SPELLCAST_INTERRUPTED",
	"EQUIPMENT_SETS_CHANGED", "EQUIPMENT_SWAP_FINISHED", "PLAYER_EQUIPMENT_CHANGED",
	"UPDATE_BATTLEFIELD_STATUS",
	"LFG_PROPOSAL_SHOW", "LFG_PROPOSAL_FAILED", "LFG_PROPOSAL_DONE",
	"CHALLENGE_MODE_START", "CHALLENGE_MODE_COMPLETED", "CHALLENGE_MODE_RESET",
	"PVP_MATCH_ACTIVE", "PVP_MATCH_COMPLETE",
}

local handlers = {}

function handlers.PLAYER_ENTERING_WORLD()
	earlyLFG = nil
	ns.QueueCheck(1)
	-- instance info, talent and equipment set data can lag behind the loading
	-- screen; whatever the first pass could not do yet is owed again
	C_Timer.After(4, function() ns.Check("retry") end)
end

function handlers.PLAYER_REGEN_DISABLED()
	ns.OnGearWarningCombat()
	ns.UpdateHUD()
end

function handlers.PLAYER_REGEN_ENABLED()
	ns.ContinueApply()
	ns.QueueCheck(0.3)
end

function handlers.PLAYER_SPECIALIZATION_CHANGED(unit)
	if unit ~= "player" then return end
	C_Timer.After(0.5, function()
		ns.ContinueApply()
		ns.Check("spec")   -- the new spec gets its own talents and gear
	end)
	ns.RefreshOptions()
end

function handlers.TRAIT_CONFIG_UPDATED(configID)
	ns.OnTalentsCommitted(configID)
	ns.QueueCheck()
end

function handlers.CONFIG_COMMIT_FAILED()
	ns.OnTalentsFailed()
	ns.QueueCheck()
end

function handlers.UNIT_SPELLCAST_INTERRUPTED(unit)
	if unit ~= "player" then return end
	ns.OnCastInterrupted()
	ns.QueueCheck()
end

function handlers.EQUIPMENT_SWAP_FINISHED()
	ns.ContinueApply()
	ns.QueueCheck()
end

function handlers.PLAYER_EQUIPMENT_CHANGED()
	ns.QueueCheck(0.5)
end

function handlers.UPDATE_BATTLEFIELD_STATUS()
	local key = ns.db.settings.early and ns.ScanBattlefieldPops() or nil
	if key ~= earlyBG then
		earlyBG = key
		ns.QueueCheck(0.1)
	end
end

function handlers.LFG_PROPOSAL_SHOW()
	earlyLFG = ns.db.settings.early and ns.ScenarioFromLFGProposal() or nil
	if not earlyLFG then return end
	local mine = earlyLFG
	-- the loading screen normally clears it; never let it outlive the proposal by much
	C_Timer.After(LFG_EARLY_TIMEOUT, function()
		if earlyLFG == mine then
			earlyLFG = nil
			ns.QueueCheck()
		end
	end)
	ns.QueueCheck(0.1)
end

function handlers.LFG_PROPOSAL_FAILED()
	earlyLFG = nil
	ns.QueueCheck()
end
handlers.LFG_PROPOSAL_DONE = handlers.LFG_PROPOSAL_FAILED

local function Refresh()
	ns.QueueCheck()
	ns.RefreshOptions()
end
handlers.TRAIT_CONFIG_LIST_UPDATED    = Refresh
handlers.ACTIVE_COMBAT_CONFIG_CHANGED = Refresh
handlers.EQUIPMENT_SETS_CHANGED       = Refresh

local driver = CreateFrame("Frame")
driver:SetScript("OnEvent", function(_, event, ...)
	if handlers[event] then
		handlers[event](...)
	else
		ns.QueueCheck(1)   -- zone, war mode, keystone and match state
	end
end)

-- ---------------------------------------------------------------------------
-- Module on / off
-- ---------------------------------------------------------------------------

function ns.OnEnable()
	if not ns.db then InitDB() end
	InitChar()
	running = true
	-- an event this client does not know raises an error on registration
	for _, e in ipairs(EVENTS) do pcall(driver.RegisterEvent, driver, e) end
	CK.HUD.AddSection(ns.hudSection)
	-- switched on mid-session there is no loading screen to start from; at
	-- login this merges with the one PLAYER_ENTERING_WORLD asks for
	currentKey = nil
	ns.QueueCheck(1)
end

function ns.OnDisable()
	running = false
	driver:UnregisterAllEvents()
	ns.CancelApply()
	wantAuto, wantSpec, earlyBG, earlyLFG = false, false, nil, nil
	ns.UpdateGearWarning(nil)
	wipe(ns.debug)
	CK.HUD.RemoveSection("loadout")
end
