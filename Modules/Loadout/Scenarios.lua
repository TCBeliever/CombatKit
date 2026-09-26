local ADDON, ns = ...

-- ===========================================================================
-- Scenarios
--
-- Two groups, PvE and PvP, are all a new user has to fill in. Each group can
-- be split into its scenarios; a scenario then either keeps using the group's
-- settings or gets its own. Content that plays the same shares a scenario:
-- Mythic+ with dungeons, Solo Shuffle with arena, Blitz with battlegrounds.
-- ===========================================================================

ns.GROUPS = { "pve", "pvp" }

-- Debug page: pretend values, this session only. nil / false = the real thing.
--   scenario, early (scenario keys), warmode, role ("TANK"|"HEALER"|"DAMAGER"), locked, dryRun, verbose
ns.debug = {}

function ns.IsFaking()
	local d = ns.debug
	return (d.scenario or d.early or d.warmode or d.role or d.locked) and true or false
end

ns.SCENARIOS = {
	{ key = "world",   group = "pve", autoSpec = true },   -- solo content: may switch spec on entering
	{ key = "delve",   group = "pve", autoSpec = true },
	{ key = "dungeon", group = "pve" },
	{ key = "raid",    group = "pve" },
	{ key = "arena",   group = "pvp" },
	{ key = "bg",      group = "pvp" },
}

ns.SCENARIO_BY_KEY = {}
for _, s in ipairs(ns.SCENARIOS) do ns.SCENARIO_BY_KEY[s.key] = s end

function ns.ScenarioName(key) return ns.L["SCN_" .. key] end
-- for the HUD, where "Battlegrounds / rated" is too long; the full name unless a short one exists
function ns.ScenarioShortName(key)
	local short = ns.L["SCN_SHORT_" .. key]
	if short == "SCN_SHORT_" .. key then return ns.ScenarioName(key) end
	return short
end
function ns.GroupName(group) return ns.L["GROUP_" .. group] end

local DIFFICULTY_DELVE = 208

-- 12.x can hand addons "secret" values inside instances; a secret boolean
-- cannot be tested. Anything we cannot read counts as false.
local function Flag(fn, ...)
	if type(fn) ~= "function" then return false end
	local ok, v = pcall(fn, ...)
	if not ok or v == nil then return false end
	if issecretvalue and issecretvalue(v) then return false end
	return v and true or false
end
ns.Flag = Flag

function ns.IsWarMode()
	if ns.debug.warmode then return true end
	return C_PvP and Flag(C_PvP.IsWarModeDesired) or false
end

-- The role the group gave the player ("TANK" | "HEALER" | "DAMAGER"), or nil:
-- solo, a group without roles (friends, an NPC companion), or unreadable.
function ns.GetAssignedRole()
	if ns.debug.role then return ns.debug.role end
	if not IsInGroup() or not UnitGroupRolesAssigned then return nil end
	local ok, role = pcall(UnitGroupRolesAssigned, "player")
	if not ok or role == nil or (issecretvalue and issecretvalue(role)) then return nil end
	if role == "NONE" or role == "" then return nil end
	return role
end

-- Returns the scenario key for where the player is right now.
function ns.DetectScenario()
	if ns.debug.scenario then return ns.debug.scenario end
	local inInstance, instanceType = IsInInstance()
	if not inInstance then return "world" end

	-- 12.1 world boss lairs are instanced and share the delve API family
	if C_DelvesUI and Flag(C_DelvesUI.IsInLair) then return "raid" end

	if instanceType == "arena" then return "arena" end
	if instanceType == "pvp" then return "bg" end
	if instanceType == "raid" then return "raid" end
	if instanceType == "party" then return "dungeon" end
	if instanceType == "scenario" then
		local _, _, difficultyID = GetInstanceInfo()
		if difficultyID == DIFFICULTY_DELVE then return "delve" end
		if C_DelvesUI and Flag(C_DelvesUI.HasActiveDelve) then return "delve" end
		if C_PartyInfo and Flag(C_PartyInfo.IsDelveInProgress) then return "delve" end
	end
	return "world"   -- story scenarios and the like play as open world
end

-- Once the key is running or the match has started nothing can be changed
-- any more; switching waits until it is over.
function ns.IsLocked()
	if ns.debug.locked then return true end
	if C_ChallengeMode and Flag(C_ChallengeMode.IsChallengeModeActive) then return true end
	if C_PvP and C_PvP.GetActiveMatchState and Enum and Enum.PvPMatchState then
		local ok, state = pcall(C_PvP.GetActiveMatchState)
		if ok and state ~= nil and not (issecretvalue and issecretvalue(state)) then
			return state == Enum.PvPMatchState.Engaged
		end
	end
	return false
end

-- ---------------------------------------------------------------------------
-- Queue pops: the scenario you are about to enter
-- ---------------------------------------------------------------------------

-- GetBattlefieldStatus queueType is a string such as "ARENA", "ARENASKIRMISH",
-- "BATTLEGROUND", "RATEDSHUFFLE", "RATEDSOLORBG". Matched loosely so an
-- unknown or renamed type still lands somewhere sensible.
function ns.ScenarioFromQueue(queueType, teamSize)
	local t = type(queueType) == "string" and queueType:upper() or ""
	if t:find("SOLORBG") or t:find("BLITZ") or t:find("BATTLEGROUND") or t:find("RBG") then return "bg" end
	if t:find("SHUFFLE") or t:find("ARENA") then return "arena" end
	if type(teamSize) == "number" and teamSize > 0 and teamSize <= 3 then return "arena" end
	if t ~= "" then return "bg" end
	return nil
end

function ns.ScanBattlefieldPops()
	if not GetMaxBattlefieldID or not GetBattlefieldStatus then return nil end
	for i = 1, GetMaxBattlefieldID() do
		local status, _, teamSize, _, _, queueType = GetBattlefieldStatus(i)
		if status == "confirm" then
			return ns.ScenarioFromQueue(queueType, teamSize)
		end
	end
	return nil
end

-- LFG proposal subtypes: 1 dungeon, 2 heroic, 3 raid finder, 5 flex raid
local LFG_SUBTYPE = { [1] = "dungeon", [2] = "dungeon", [3] = "raid", [5] = "raid" }

function ns.ScenarioFromLFGProposal()
	if not GetLFGProposal then return nil end
	local exists, _, _, subtypeID = GetLFGProposal()
	if not exists then return nil end
	return LFG_SUBTYPE[subtypeID]
end
