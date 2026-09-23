local ADDON, ns = ...
local L = ns.L

-- ===========================================================================
-- Reading the character: specs, talent loadouts, equipment sets
-- ===========================================================================

local SI = C_SpecializationInfo

local function SpecIndex()
	local fn = (SI and SI.GetSpecialization) or GetSpecialization
	return fn and fn() or nil
end

local function SpecInfo(index)
	local fn = (SI and SI.GetSpecializationInfo) or GetSpecializationInfo
	if not fn or not index then return nil end
	return fn(index)   -- id, name, description, icon, role
end

local function NumSpecs()
	local _, _, classID = UnitClass("player")
	if SI and SI.GetNumSpecializationsForClassID and classID then
		local n = SI.GetNumSpecializationsForClassID(classID)
		if n and n > 0 then return n end
	end
	if GetNumSpecializations then return GetNumSpecializations() end
	return 4
end

-- { { index=, id=, name=, icon=, role= }, ... } for the player's class
-- An index past the class's specs can still answer with an empty record, so
-- a spec only counts when it has a real id and a name.
function ns.GetSpecs()
	local out = {}
	for i = 1, NumSpecs() do
		local id, name, _, icon, role = SpecInfo(i)
		if id and id > 0 and name and name ~= "" then
			out[#out + 1] = { index = i, id = id, name = name, icon = icon, role = role }
		end
	end
	return out
end

function ns.GetSpecByID(specID)
	for _, s in ipairs(ns.GetSpecs()) do
		if s.id == specID then return s end
	end
end

function ns.GetCurrentSpecID()
	local id = SpecInfo(SpecIndex())
	return id
end

-- { { id=, name= }, ... } saved talent loadouts of one spec
function ns.GetTalentConfigs(specID)
	local out = {}
	if not specID or not C_ClassTalents or not C_ClassTalents.GetConfigIDsBySpecID then return out end
	local ok, ids = pcall(C_ClassTalents.GetConfigIDsBySpecID, specID)
	if not ok or type(ids) ~= "table" then return out end
	for _, id in ipairs(ids) do
		local okInfo, info = pcall(C_Traits.GetConfigInfo, id)
		if okInfo and info and info.name then
			out[#out + 1] = { id = id, name = info.name }
		end
	end
	return out
end

function ns.GetActiveConfigID(specID)
	if not specID or not C_ClassTalents or not C_ClassTalents.GetLastSelectedSavedConfigID then return nil end
	local ok, id = pcall(C_ClassTalents.GetLastSelectedSavedConfigID, specID)
	return ok and id or nil
end

-- { { id=, name=, icon= }, ... } sorted by name
function ns.GetEquipmentSets()
	local out = {}
	if not C_EquipmentSet or not C_EquipmentSet.GetEquipmentSetIDs then return out end
	for _, id in ipairs(C_EquipmentSet.GetEquipmentSetIDs() or {}) do
		local name, icon = C_EquipmentSet.GetEquipmentSetInfo(id)
		if name then out[#out + 1] = { id = id, name = name, icon = icon } end
	end
	table.sort(out, function(a, b) return a.name:lower() < b.name:lower() end)
	return out
end

-- Returns isEquipped, exists
function ns.IsSetEquipped(setID)
	if not setID then return true, false end
	local name, _, _, isEquipped = C_EquipmentSet.GetEquipmentSetInfo(setID)
	if not name then return false, false end
	return isEquipped and true or false, true
end

-- Saved ids go stale: a loadout that was deleted and imported again gets a new
-- id, and so does a recreated equipment set. The name was saved next to the
-- id for exactly this; re-link by name when the id no longer resolves.
-- A cell is { configID, configName, setID, setName } for one spec.
function ns.RepairCell(cell, specID)
	if cell.setID and not C_EquipmentSet.GetEquipmentSetInfo(cell.setID) and cell.setName then
		local id = C_EquipmentSet.GetEquipmentSetID(cell.setName)
		if id then cell.setID = id end
	end
	if cell.configID and specID and cell.configName then
		local found, byName
		for _, c in ipairs(ns.GetTalentConfigs(specID)) do
			if c.id == cell.configID then found = c end
			if c.name == cell.configName then byName = c end
		end
		if found then
			cell.configName = found.name   -- follow renames
		elseif byName then
			cell.configID = byName.id
		end
	end
	if cell.setID then
		local name = C_EquipmentSet.GetEquipmentSetInfo(cell.setID)
		if name then cell.setName = name end
	end
end

-- ===========================================================================
-- What should be worn here
--
-- Every spec has one cell per group (PvE, PvP). A group that is split lets a
-- scenario carry its own cells; a scenario without its own uses the group's.
-- With the option on, open world with War Mode counts as PvP.
-- ===========================================================================

local function ConfigExists(configID)
	local ok, info = pcall(C_Traits.GetConfigInfo, configID)
	return ok and info ~= nil
end

-- Returns cell (or nil), sourceKey ("pve" | "pvp" | scenario key), autoSpecID (or nil)
function ns.ResolveTarget(key, specID)
	local char = ns.char
	local scenario = ns.SCENARIO_BY_KEY[key]
	if not scenario then return nil end
	if key == "world" and char.warmodePvP and ns.IsWarMode() then
		return char.groups.pvp.specs[specID], "pvp", nil
	end
	local group = scenario.group
	if char.split[group] then
		local entry = char.scenarios[key]
		local autoSpec = scenario.autoSpec and entry.autoSpec or nil
		if entry.custom then return entry.specs[specID], key, autoSpec end
		return char.groups[group].specs[specID], group, autoSpec
	end
	return char.groups[group].specs[specID], group, nil
end

-- How the character compares to the target for `key`, for the current spec.
-- state: "none" (nothing configured) | "ready" | "mismatch"
function ns.GetStatus(key)
	local specID = ns.GetCurrentSpecID()
	local st = { key = key, specID = specID, state = "none", talentsOK = true, gearOK = true }
	if not specID then return st end   -- no spec yet (low level)

	local cell, source, autoSpec = ns.ResolveTarget(key, specID)
	st.cell, st.source, st.autoSpec = cell, source, autoSpec
	if not cell then return st end
	ns.RepairCell(cell, specID)

	if cell.configID then
		st.hasTalents = true
		st.talentsOK = ns.GetActiveConfigID(specID) == cell.configID
		st.talentsMissing = not ConfigExists(cell.configID)
	end
	if cell.setID then
		st.hasGear = true
		local equipped, exists = ns.IsSetEquipped(cell.setID)
		st.gearOK, st.gearMissing = equipped, not exists
	end
	if st.hasTalents or st.hasGear then
		st.state = (st.talentsOK and st.gearOK) and "ready" or "mismatch"
	end
	return st
end

-- The setup that closes the gap for `key`; targetSpecID only when the spec
-- itself has to change. "Missing" also covers data that has not loaded yet
-- right after login, so such a part is left out rather than attempted.
function ns.BuildSetup(key, targetSpecID)
	local specID = targetSpecID or ns.GetCurrentSpecID()
	if not specID then return nil end
	local cell = ns.ResolveTarget(key, specID)
	local setup = { specID = targetSpecID }
	if cell then
		ns.RepairCell(cell, specID)
		if cell.configID and ConfigExists(cell.configID) then
			setup.configID = cell.configID
		end
		if cell.setID and select(2, ns.IsSetEquipped(cell.setID)) then
			setup.setID = cell.setID
		end
	end
	if not setup.specID and not setup.configID and not setup.setID then return nil end
	return setup
end

-- The setup that takes the character to `specID` with `cell`'s talents and
-- gear, or nil when it is already there. For the settings page: what the page
-- shows, applied on request, whatever scenario the character is in.
function ns.BuildSetupFor(specID, cell)
	if not specID then return nil end
	local setup = { specID = specID ~= ns.GetCurrentSpecID() and specID or nil }
	if cell then
		ns.RepairCell(cell, specID)
		if cell.configID and ConfigExists(cell.configID)
			and (setup.specID or ns.GetActiveConfigID(specID) ~= cell.configID) then
			setup.configID = cell.configID
		end
		if cell.setID then
			local equipped, exists = ns.IsSetEquipped(cell.setID)
			if exists and (setup.specID or not equipped) then setup.setID = cell.setID end
		end
	end
	if not setup.specID and not setup.configID and not setup.setID then return nil end
	return setup
end

-- ===========================================================================
-- Applying a setup: spec, then gear and talents
--
-- Every step is a request the client may drop without a word: it is still in
-- the previous cast, it is mid-transition, the player moved. So nothing is
-- assumed. A ticker looks at the real state, waits while the player is casting
-- (spec and talent changes are casts), asks again when a request had no effect,
-- and gives up with a message after a few tries. Events only make it faster.
-- ===========================================================================

local TICK          = 0.75   -- seconds between looks while an apply is pending
local GRACE         = 1.0    -- a request gets this long to show an effect (a cast starting counts)
local MAX_TRIES     = 4      -- per step
local APPLY_TIMEOUT = 15     -- without any new request

local pending   -- { setup=, expires=, steps = { spec={}, talents={}, gear={} }, commitSpecID=, commitConfigID= }
local ticking = false

local function IsCasting()
	for _, fn in ipairs({ UnitCastingInfo, UnitChannelInfo }) do
		if fn then
			local ok, name = pcall(fn, "player")
			if ok and ((issecretvalue and issecretvalue(name)) or name ~= nil) then return true end
		end
	end
	return false
end

-- A spec change is cast standing still; asking while running only burns tries.
local function IsMoving()
	if not GetUnitSpeed then return false end
	local ok, speed = pcall(GetUnitSpeed, "player")
	if not ok or speed == nil or (issecretvalue and issecretvalue(speed)) then return false end
	return speed > 0
end

-- Returns true when the client accepted the request (which is no promise)
function ns.EquipSet(setID)
	if not setID or InCombatLockdown() then return false end
	local ok, equipped = pcall(C_EquipmentSet.UseEquipmentSet, setID)
	return ok and equipped ~= false
end

local function SwitchSpec(specID)
	local spec = ns.GetSpecByID(specID)
	if not spec then return false end
	local fn = (SI and SI.SetSpecialization) or SetSpecialization
	if not fn then return false end
	local ok, accepted = pcall(fn, spec.index)
	return ok and accepted ~= false
end

-- The talent UI only shows a loadout as selected when told so explicitly.
local function RememberConfig(specID, configID)
	if C_ClassTalents.UpdateLastSelectedSavedConfigID then
		pcall(C_ClassTalents.UpdateLastSelectedSavedConfigID, specID, configID)
	end
end

-- Returns accepted, reason
local function LoadTalents(specID, configID)
	local ok, result, changeError = pcall(C_ClassTalents.LoadConfig, configID, true)
	local R = Enum.LoadConfigResult
	if not ok or result == nil or result == R.Error then
		return false, (type(changeError) == "string" and changeError ~= "") and changeError or L["unknown reason"]
	end
	if result == R.LoadInProgress then
		pending.commitSpecID, pending.commitConfigID = specID, configID   -- finished by TRAIT_CONFIG_UPDATED
	else
		RememberConfig(specID, configID)
	end
	return true
end

-- Names for a setup, for the dry run and the debug log
local function DescribeSetup(setup)
	local spec = setup.specID and ns.GetSpecByID(setup.specID)
	local config = setup.configID and select(2, pcall(C_Traits.GetConfigInfo, setup.configID))
	local set = setup.setID and C_EquipmentSet.GetEquipmentSetInfo(setup.setID)
	return spec and spec.name or "-", type(config) == "table" and config.name or "-", set or "-"
end

-- What the apply is held up by, logged once per change and shown on the HUD
local function Waiting(reason)
	if pending.waiting ~= reason then
		pending.waiting = reason
		if reason then ns.Debug("apply: waiting (%s)", reason) end
		ns.UpdateHUD()
	end
end

local function Finish(message, ...)
	pending = nil
	if message then ns.Msg(message, ...) end
	-- an automatic apply that came due meanwhile is settled now instead of
	-- landing on a later manual change
	ns.QueueCheck(0.1)
end

-- One step: ask (again) when allowed. Returns false when the step is out of tries.
local function Ask(name, request)
	local step = pending.steps[name]
	local now = GetTime()
	if step.askedAt and now - step.askedAt < GRACE then return true end   -- give the last request a moment
	if (step.tries or 0) >= MAX_TRIES then return false end
	step.tries = (step.tries or 0) + 1
	step.askedAt = now
	pending.expires = now + APPLY_TIMEOUT
	local accepted, reason = request()
	step.reason = reason
	ns.Debug("apply: %s, try %d: %s", name, step.tries, accepted and "asked" or ("refused" .. (reason and (" (" .. reason .. ")") or "")))
	return true
end

function ns.ContinueApply()
	if not pending then return end
	if InCombatLockdown() then
		pending.expires = GetTime() + APPLY_TIMEOUT   -- the clock only runs while something can be done
		return
	end
	local setup = pending.setup
	local specID = ns.GetCurrentSpecID()
	local needSpec = setup.specID and setup.specID ~= specID

	if GetTime() > pending.expires then
		ns.Debug("apply: timed out")
		-- only the spec step can wait that long without asking (the player kept moving)
		return Finish(needSpec and L["Could not switch specialization."] or nil)
	end
	-- the previous request, or the player's own cast: wait it out
	if IsCasting() then return Waiting("casting") end

	if needSpec then
		-- asked as soon as the player stands still
		if IsMoving() then return Waiting("moving") end
		if not Ask("spec", function() return SwitchSpec(setup.specID) end) then
			return Finish(L["Could not switch specialization."])
		end
		return   -- talents and gear belong to the new spec
	end

	Waiting(nil)
	local done = true
	if setup.setID and not ns.IsSetEquipped(setup.setID) then
		done = false
		if not Ask("gear", function() return ns.EquipSet(setup.setID) end) then
			local _, _, setName = DescribeSetup(setup)
			return Finish(L["Could not equip %s."], setName)
		end
	end
	if setup.configID and ns.GetActiveConfigID(specID) ~= setup.configID then
		done = false
		if not Ask("talents", function() return LoadTalents(specID, setup.configID) end) then
			return Finish(L["Could not load the talent loadout: %s"], pending.steps.talents.reason or L["unknown reason"])
		end
	end
	if done then
		ns.Debug("apply: done")
		Finish()
	end
end

local function Tick()
	ticking = false
	if not pending then return end
	ns.ContinueApply()
	if pending and not ticking then
		ticking = true
		C_Timer.After(TICK, Tick)
	end
end

function ns.ApplySetup(setup)
	if ns.debug.dryRun then
		ns.Msg(L["DRYRUN_MSG"], DescribeSetup(setup))
		return
	end
	ns.Debug("apply: spec %s, talents %s, gear %s", DescribeSetup(setup))
	pending = { setup = setup, expires = GetTime() + APPLY_TIMEOUT, steps = { spec = {}, talents = {}, gear = {} } }
	if InCombatLockdown() then ns.Msg(L["In combat. It will be applied when combat ends."]) end
	ns.ContinueApply()
	if pending and not ticking then
		ticking = true
		C_Timer.After(TICK, Tick)
	end
end

-- TRAIT_CONFIG_UPDATED(configID). The event fires for every trait tree
-- (professions, skyriding, ...), so only the active talent config counts as
-- "the commit we started went through".
function ns.OnTalentsCommitted(configID)
	if pending and pending.commitConfigID then
		local active = C_ClassTalents.GetActiveConfigID and C_ClassTalents.GetActiveConfigID()
		if configID == nil or active == nil or configID == active then
			RememberConfig(pending.commitSpecID, pending.commitConfigID)
			pending.commitSpecID, pending.commitConfigID = nil, nil
		end
	end
	ns.ContinueApply()
end

-- CONFIG_COMMIT_FAILED: the cast was interrupted; the ticker asks again
function ns.OnTalentsFailed()
	if pending and pending.commitConfigID then
		ns.Debug("apply: talent commit failed")
		pending.commitSpecID, pending.commitConfigID = nil, nil
		pending.steps.talents.reason = L["the change was interrupted"]
	end
end

function ns.IsApplying()
	return pending ~= nil
end

-- the module was switched off: whatever was being applied is dropped
function ns.CancelApply()
	pending = nil
end

-- "moving" while a spec change waits for the player to stand still
function ns.GetApplyWait()
	return pending and pending.waiting or nil
end
