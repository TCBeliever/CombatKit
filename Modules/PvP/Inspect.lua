local ADDON, ns = ...
local U = ns.Util

-- ===========================================================================
-- Inspecting teammates: spec, talents (C_Traits on the inspect config) and
-- PvP talents. One request in flight at a time, a cache by GUID. A read that
-- came back incomplete is tried again; a complete one is kept for the round.
-- The player's own talents are read the same way from the active config
-- (solo mode).
-- ===========================================================================

local I = {}
ns.Inspect = I

I.PVP_SLOTS = 3
I.TIMEOUT = 4
I.THROTTLE = 2          -- between requests
I.REFRESH = 120         -- a complete read is good for this long
I.MAX_TRIES = 6

I.cache = {}            -- guid -> { spec=, talents=, pvp=, traitComplete=, pvpComplete=, complete=, at= }
I.tries = {}            -- guid -> attempts since the last complete read
I.inflight = nil        -- { unit=, guid=, at= }
I.lastRequest = -1e9
I.stats = { requests = 0, ready = 0, reads = 0 }

local function InspectConfigID()
	local c = Constants and Constants.TraitConsts and Constants.TraitConsts.INSPECT_TRAIT_CONFIG_ID
	return type(c) == "number" and c or -1
end

local function UserInspecting()
	return InspectFrame ~= nil and U.Plain(InspectFrame.IsShown, InspectFrame) == true
end

function I.SpecOf(unit)
	local get = (C_SpecializationInfo and C_SpecializationInfo.GetInspectSpecialization) or GetInspectSpecialization
	local id = U.Plain(get, unit)
	if type(id) == "number" and id > 0 then return id end
	return nil
end

-- talents of a trait config: spellID -> rank; answers the table and whether every node was read
local function ReadTalents(configID)
	local api = C_Traits
	local out, complete = {}, true
	if type(api) ~= "table" or type(configID) ~= "number" then return out, false end
	if configID == InspectConfigID() and api.HasValidInspectData and U.Plain(api.HasValidInspectData) ~= true then
		return out, false
	end
	local ci = U.Plain(api.GetConfigInfo, configID)
	local treeIDs = U.Field(ci, "treeIDs")
	if type(treeIDs) ~= "table" or #treeIDs == 0 then return out, false end
	for _, treeID in ipairs(treeIDs) do
		local nodeIDs = U.Plain(api.GetTreeNodes, treeID)
		if type(nodeIDs) ~= "table" then
			complete = false
		else
			for _, nodeID in ipairs(nodeIDs) do
				local ni = U.Plain(api.GetNodeInfo, configID, nodeID)
				if type(ni) ~= "table" then
					complete = false
				else
					local active = U.Field(ni, "activeEntry")
					local rank = U.Field(active, "rank") or U.Field(ni, "activeRank") or U.Field(ni, "currentRank")
					if type(rank) ~= "number" then
						complete = false
					elseif rank > 0 then
						local entryID = U.Field(active, "entryID")
						local ei = entryID and U.Plain(api.GetEntryInfo, configID, entryID)
						local definitionID = U.Field(ei, "definitionID")
						local di = definitionID and U.Plain(api.GetDefinitionInfo, definitionID)
						local spellID = U.Field(di, "spellID")
						if type(spellID) == "number" then
							out[spellID] = rank
						elseif type(U.Field(ei, "subTreeID")) ~= "number" then
							complete = false   -- a hero tree choice has no spell; anything else should
						end
					end
				end
			end
		end
	end
	return out, complete
end

-- PvP talents of an inspected unit: talent IDs and their spell IDs, both as keys
local function ReadPvp(unit)
	local api = C_SpecializationInfo
	local out, valid = {}, 0
	if not (api and api.GetInspectSelectedPvpTalent) then return out, false end
	for i = 1, I.PVP_SLOTS do
		local talentID = U.Plain(api.GetInspectSelectedPvpTalent, unit, i)
		if type(talentID) == "number" and talentID >= 0 then valid = valid + 1 end
		if type(talentID) == "number" and talentID > 0 then
			out[talentID] = true
			local info = U.Plain(api.GetPvpTalentInfo, talentID)
			local spellID = U.Field(info, "spellID")
			if type(spellID) == "number" then out[spellID] = true else valid = valid - 1 end
		end
	end
	return out, valid == I.PVP_SLOTS
end

-- the player's own PvP talents
local function ReadOwnPvp()
	local api = C_SpecializationInfo
	local out = {}
	if not (api and api.GetAllSelectedPvpTalentIDs) then return out, false end
	local ids = U.Plain(api.GetAllSelectedPvpTalentIDs)
	if type(ids) ~= "table" then return out, false end
	for _, talentID in ipairs(ids) do
		if type(talentID) == "number" then
			out[talentID] = true
			local spellID = U.Field(U.Plain(api.GetPvpTalentInfo, talentID), "spellID")
			if type(spellID) == "number" then out[spellID] = true end
		end
	end
	return out, true
end

-- What is known of a unit, from the cache (nil when nothing was read yet).
function I.InfoFor(guid)
	return I.cache[guid]
end

local function Store(unit, guid, entry)
	local prev = I.cache[guid]
	-- a partial read never replaces a complete one of the same spec
	if prev and prev.spec == entry.spec then
		if prev.traitComplete and not entry.traitComplete then entry.talents, entry.traitComplete = prev.talents, true end
		if prev.pvpComplete and not entry.pvpComplete then entry.pvp, entry.pvpComplete = prev.pvp, true end
	end
	entry.complete = entry.spec ~= nil and entry.traitComplete and entry.pvpComplete
	if entry.spec or next(entry.talents) or next(entry.pvp) then
		I.cache[guid] = entry
		I.stats.reads = I.stats.reads + 1
		if entry.complete then I.tries[guid] = 0 end
		U.Log("inspect", unit, nil, string.format("spec %s, %s talents, pvp %s%s", tostring(entry.spec),
			entry.traitComplete and "all" or "some", entry.pvpComplete and "all" or "some",
			entry.complete and "" or " (incomplete)"))
		return entry
	end
	return nil
end

-- Read what the client holds for the inspected unit right now (after INSPECT_READY).
function I.Read(unit, guid)
	if U.Plain(UnitGUID, unit) ~= guid then return nil end
	local entry = { at = U.clock(), spec = I.SpecOf(unit) }
	entry.talents, entry.traitComplete = ReadTalents(InspectConfigID())
	entry.pvp, entry.pvpComplete = ReadPvp(unit)
	return Store(unit, guid, entry)
end

-- The player's own spec and talents, from the active config (solo mode).
function I.ReadSelf()
	local guid = U.Plain(UnitGUID, "player")
	if type(guid) ~= "string" then return nil end
	local entry = { at = U.clock(), spec = ns.PlayerSpec and ns.PlayerSpec() }
	local configID = C_ClassTalents and U.Plain(C_ClassTalents.GetActiveConfigID)
	entry.talents, entry.traitComplete = ReadTalents(configID)
	entry.pvp, entry.pvpComplete = ReadOwnPvp()
	return Store("player", guid, entry)
end

local function Due(guid, now)
	local c = I.cache[guid]
	if not c then return true end
	if not c.complete then return (I.tries[guid] or 0) < I.MAX_TRIES end
	return now - c.at >= I.REFRESH
end

-- One request at a time, for the teammates whose read is missing or incomplete.
-- roster: unit -> { guid= }
function I.Tick(now, roster, units)
	if I.inflight and now - I.inflight.at < I.TIMEOUT then return end
	I.inflight = nil
	if UserInspecting() or now - I.lastRequest < I.THROTTLE then return end
	for _, unit in ipairs(units) do
		local r = roster[unit]
		if r and unit ~= "player" and Due(r.guid, now) then
			if U.Plain(CanInspect, unit, true) == true then
				I.tries[r.guid] = (I.tries[r.guid] or 0) + 1
				I.inflight = { unit = unit, guid = r.guid, at = now }
				I.lastRequest = now
				I.stats.requests = I.stats.requests + 1
				pcall(NotifyInspect, unit)
				return
			end
		end
	end
end

-- INSPECT_READY: read whoever it was for. Answers the unit when it was a teammate.
function I.OnReady(guid, roster, units)
	if type(guid) ~= "string" or not canaccessvalue(guid) then return nil end
	I.stats.ready = I.stats.ready + 1
	local hit
	for _, unit in ipairs(units) do
		local r = roster[unit]
		if r and r.guid == guid and unit ~= "player" then
			I.Read(unit, guid)
			hit = unit
		end
	end
	if I.inflight and I.inflight.guid == guid then
		I.inflight = nil
		if ClearInspectPlayer and not UserInspecting() then pcall(ClearInspectPlayer) end
	end
	return hit
end

function I.Reset()
	I.cache, I.tries, I.inflight = {}, {}, nil
end

function I.Describe(unit, guid)
	local c = I.cache[guid]
	if not c then return unit .. ": nothing read" end
	local n = 0
	for _ in pairs(c.talents or {}) do n = n + 1 end
	return string.format("%s: spec %s, %d talents%s, pvp%s, %d tries", unit, tostring(c.spec), n,
		c.traitComplete and "" or " (incomplete)", c.pvpComplete and "" or " (incomplete)", I.tries[guid] or 0)
end
