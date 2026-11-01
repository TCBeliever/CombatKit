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

-- The name of the talent loadout the spec has selected, or nil (none, or unsaved changes)
function ns.GetActiveConfigName(specID)
	local id = ns.GetActiveConfigID(specID)
	if not id then return nil end
	local ok, info = pcall(C_Traits.GetConfigInfo, id)
	return ok and type(info) == "table" and info.name or nil
end

-- The name of the equipment set that is fully equipped, or nil
function ns.GetEquippedSetName()
	if not C_EquipmentSet or not C_EquipmentSet.GetEquipmentSetIDs then return nil end
	for _, id in ipairs(C_EquipmentSet.GetEquipmentSetIDs() or {}) do
		local name, _, _, isEquipped = C_EquipmentSet.GetEquipmentSetInfo(id)
		if name and isEquipped then return name end
	end
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

-- ---------------------------------------------------------------------------
-- PvP talents: three slots, of the spec the player is in (the game answers for
-- no other). It keeps one set per spec, not per talent loadout, so a loadout
-- switch leaves them as they are. A cell keeps them as pvp = { [slot] = talentID };
-- an empty slot is left alone. Talent IDs do not change, so no repair by name.
-- ---------------------------------------------------------------------------

ns.PVP_SLOTS = 3

-- { [slot] = { enabled=, selected=, list = { talentID, ... }, available = { [talentID] = true } } }
function ns.GetPvpSlots()
	local out = {}
	if not SI or not SI.GetPvpTalentSlotInfo then return out end
	for i = 1, ns.PVP_SLOTS do
		local ok, info = pcall(SI.GetPvpTalentSlotInfo, i)
		if ok and type(info) == "table" then
			local list, available = info.availableTalentIDs or {}, {}
			for _, id in ipairs(list) do available[id] = true end
			out[i] = { enabled = info.enabled and true or false, selected = info.selectedTalentID, list = list, available = available }
		end
	end
	return out
end

-- name, icon of a PvP talent, or nil
function ns.GetPvpTalentInfo(talentID)
	if not talentID or not SI or not SI.GetPvpTalentInfo then return nil end
	local ok, info = pcall(SI.GetPvpTalentInfo, talentID)
	if ok and type(info) == "table" then return info.name, info.icon end
end

-- The talents a cell wants, in slot order: { { id=, slot= }, ... }
local function PvpWanted(pvp)
	local out, seen = {}, {}
	if type(pvp) ~= "table" then return out end
	for i = 1, ns.PVP_SLOTS do
		local id = pvp[i]
		if id and not seen[id] then
			seen[id] = true
			out[#out + 1] = { id = id, slot = i }
		end
	end
	return out
end

function ns.HasPvp(pvp) return #PvpWanted(pvp) > 0 end

-- What it takes to have `pvp` on. Which slot a talent sits in changes nothing
-- in the game, so one that is on in another slot counts as on. A talent that
-- is not on goes to its own slot when that slot holds nothing wanted, else to
-- the first such slot. Returns plan { { id=, slot= }, ... }, how many wanted
-- talents are on, how many there are, and how many cannot go anywhere (not
-- this spec's, the slots still locked, or the data not loaded yet).
function ns.PvpPlan(pvp)
	local slots = ns.GetPvpSlots()
	local want = PvpWanted(pvp)
	local isWanted, on = {}, {}
	for _, w in ipairs(want) do isWanted[w.id] = true end
	local free = {}
	for i = 1, ns.PVP_SLOTS do
		local s = slots[i]
		if s and s.enabled then
			if s.selected then on[s.selected] = true end
			if not (s.selected and isWanted[s.selected]) then free[i] = true end
		end
	end
	local plan, have, missing = {}, 0, 0
	for _, w in ipairs(want) do
		if on[w.id] then
			have = have + 1
		else
			local slot
			if free[w.slot] and slots[w.slot].available[w.id] then
				slot = w.slot
			else
				for i = 1, ns.PVP_SLOTS do
					if free[i] and slots[i].available[w.id] then slot = i; break end
				end
			end
			if slot then
				free[slot] = nil
				plan[#plan + 1] = { id = w.id, slot = slot }
			else
				missing = missing + 1
			end
		end
	end
	return plan, have, #want, missing
end

-- The talents' names, for the dry run and the debug log
local function PvpNames(pvp)
	local names = {}
	for _, w in ipairs(PvpWanted(pvp)) do names[#names + 1] = ns.GetPvpTalentInfo(w.id) or tostring(w.id) end
	return #names > 0 and table.concat(names, ", ") or "-"
end

-- Saved ids go stale: a loadout that was deleted and imported again gets a new
-- id, and so does a recreated equipment set. The name was saved next to the
-- id for exactly this; re-link by name when the id no longer resolves.
-- A cell is { configID, configName, setID, setName, pvp } for one spec.
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

-- "Multiple setups" (PvP pages): a cell can hold up to three setups. The first
-- is the cell itself, the others cell.alt[2] and cell.alt[3]; cell.active says
-- which one is used, the first unless another was picked.
ns.MAX_SETS = 3

function ns.ActiveIndex(cell)
	if not (cell and cell.multi) then return 1 end
	local n = cell.active or 1
	return (n >= 1 and n <= ns.MAX_SETS) and n or 1
end

function ns.GetSet(cell, n)
	if not cell then return nil end
	if n == 1 then return cell end
	return cell.alt and cell.alt[n] or nil
end

function ns.ActiveSet(cell) return ns.GetSet(cell, ns.ActiveIndex(cell)) end

-- the setup in use, and its number when the cell has several
local function InUse(cell, source, autoSpec)
	return ns.ActiveSet(cell), source, autoSpec, cell and cell.multi and ns.ActiveIndex(cell) or nil
end

-- Returns cell (the setup in use, or nil), sourceKey ("pve" | "pvp" | scenario key),
-- autoSpecID (or nil), the setup's number (nil unless the cell has several)
function ns.ResolveTarget(key, specID)
	local char = ns.char
	local scenario = ns.SCENARIO_BY_KEY[key]
	if not scenario then return nil end
	if key == "world" and char.warmodePvP and ns.IsWarMode() then
		return InUse(char.groups.pvp.specs[specID], "pvp", nil)
	end
	local group = scenario.group
	if char.split[group] then
		local entry = char.scenarios[key]
		local autoSpec = scenario.autoSpec and entry.autoSpec or nil
		if entry.custom then return InUse(entry.specs[specID], key, autoSpec) end
		return InUse(char.groups[group].specs[specID], group, autoSpec)
	end
	return InUse(char.groups[group].specs[specID], group, nil)
end

-- How the character compares to the target for `key`.
-- state: "none" (nothing configured) | "ready" | "mismatch"
-- A scenario that switches spec on entering has that spec as its target while
-- the character is in another one (targetSpecID), with the talents and gear
-- set for it; otherwise the target is the current spec's own.
function ns.GetStatus(key)
	local specID = ns.GetCurrentSpecID()
	local st = { key = key, specID = specID, state = "none", talentsOK = true, gearOK = true, pvpOK = true }
	if not specID then return st end   -- no spec yet (low level)

	local cell, source, autoSpec, setIndex = ns.ResolveTarget(key, specID)
	st.cell, st.source, st.autoSpec, st.setIndex = cell, source, autoSpec, setIndex
	local targetSpec = specID
	if autoSpec and autoSpec ~= specID then
		st.targetSpecID = autoSpec
		st.state = "mismatch"
		targetSpec = autoSpec
		cell, _, _, st.setIndex = ns.ResolveTarget(key, autoSpec)
		st.cell = cell
	end
	if not cell then return st end
	ns.RepairCell(cell, targetSpec)

	if cell.configID then
		st.hasTalents = true
		st.talentsOK = not st.targetSpecID and ns.GetActiveConfigID(specID) == cell.configID
		st.talentsMissing = not ConfigExists(cell.configID)
	end
	if cell.setID then
		st.hasGear = true
		local equipped, exists = ns.IsSetEquipped(cell.setID)
		st.gearOK, st.gearMissing = (equipped and not st.targetSpecID) and true or false, not exists
	end
	if ns.HasPvp(cell.pvp) then
		-- the slots answer for the spec the player is in: another spec's are not on yet
		st.hasPvp = true
		local _, have, want, missing = ns.PvpPlan(cell.pvp)
		if st.targetSpecID then have, missing = 0, 0 end
		st.pvpHave, st.pvpWant = have, want
		st.pvpOK, st.pvpMissing = have == want, missing > 0
	end
	if st.hasTalents or st.hasGear or st.hasPvp then
		st.state = (st.talentsOK and st.gearOK and st.pvpOK) and "ready" or "mismatch"
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
		-- what can be placed is worked out at the time, in the spec the setup ends in
		if ns.HasPvp(cell.pvp) then setup.pvp = cell.pvp end
	end
	if not setup.specID and not setup.configID and not setup.setID and not setup.pvp then return nil end
	return setup
end

-- The setup that takes the character to `specID` with `cell`'s talents and
-- gear: everything the cell has, whatever is on right now, so the player can
-- ask for it again (a loadout re-applied drops unsaved talent changes). Only
-- what does not exist is left out; nil when there is nothing at all.
-- For the settings page: what the page shows, applied on request, whatever
-- scenario the character is in. A forced setup asks every step once.
function ns.BuildSetupFor(specID, cell)
	if not specID then return nil end
	local setup = { specID = specID ~= ns.GetCurrentSpecID() and specID or nil, force = true }
	if cell then
		ns.RepairCell(cell, specID)
		if cell.configID and ConfigExists(cell.configID) then setup.configID = cell.configID end
		if cell.setID and select(2, ns.IsSetEquipped(cell.setID)) then setup.setID = cell.setID end
		if ns.HasPvp(cell.pvp) then setup.pvp = cell.pvp end
	end
	if not setup.specID and not setup.configID and not setup.setID and not setup.pvp then return nil end
	return setup
end

-- ===========================================================================
-- Applying a setup: spec, then gear and talents, then PvP talents
--
-- Every step is a request the client may drop without a word: it is still in
-- the previous cast, it is mid-transition, the player moved. So nothing is
-- assumed. A ticker looks at the real state, waits while the player is casting
-- (spec and talent changes are casts), asks again when a request had no effect,
-- and gives up with a message after a few tries. Events only make it faster.
--
-- A request that did start its cast was accepted. If that cast ends with
-- nothing to show for it, the player (or the game) interrupted it, and asking
-- again would only have them interrupt it again: the apply ends there, with
-- one message, and nothing stays owed. The HUD keeps showing what is missing.
--
-- A loadout the game refuses with a reason is held up, not wrong: a talent
-- that changes an ability's charges cannot be taken out while that ability
-- recharges (Tempered Soul and Soul Immolation, measured 2026-11-01). That
-- refusal is not a try. The apply says it once, waits until the next of the
-- player's abilities is back, and asks again, for up to a few minutes.
-- ===========================================================================

local TICK          = 0.75   -- seconds between looks while an apply is pending
local GRACE         = 1.0    -- a request gets this long to show an effect (a cast starting counts)
local MAX_TRIES     = 4      -- per step
local APPLY_TIMEOUT = 15     -- without any new request
local CAST_WINDOW   = 8      -- an interruption this long after a request still counts as ours
local CAST_GONE     = 0.5    -- a cast must be gone this long before it is called interrupted
local LOAD_GAP      = 1.5    -- after a refused loadout request: one 0.2 s later was refused without a reason
local HOLD_POLL     = 5      -- a held-up loadout is asked again this often when no ability's recovery says when
local HOLD_MARGIN   = 0.3    -- asked this long after the ability is back
local HOLD_LIMIT    = 180    -- seconds a loadout is waited for, from its first refusal
local GCD           = 1.6    -- a cooldown this short is the global one

local pending   -- { setup=, expires=, steps = { spec={}, talents={}, gear={}, pvp={} }, commitSpecID=, commitConfigID= }
local ticking = false
local refusedAt   -- GetTime() of the last refused loadout request, of any apply
local committingAt   -- GetTime() of the last loadout request the game took and is casting

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
	ns.LogReturns("UseEquipmentSet(" .. tostring(setID) .. ")", ok, equipped)
	return ok and equipped ~= false
end

local function SwitchSpec(specID)
	local spec = ns.GetSpecByID(specID)
	if not spec then return false end
	local fn = (SI and SI.SetSpecialization) or SetSpecialization
	if not fn then return false end
	local ok, accepted = pcall(fn, spec.index)
	ns.LogReturns("SetSpecialization(" .. spec.index .. ")", ok, accepted)
	return ok and accepted ~= false
end

-- The talent UI only shows a loadout as selected when told so explicitly.
local function RememberConfig(specID, configID)
	if C_ClassTalents.UpdateLastSelectedSavedConfigID then
		pcall(C_ClassTalents.UpdateLastSelectedSavedConfigID, specID, configID)
	end
end

local function Plain(v)
	return not (issecretvalue and issecretvalue(v)) and type(v) == "number"
end

-- The player's abilities that are recharging or cooling down (the global
-- cooldown aside): the spell book's, base spells and what overrides them, and
-- `extra` ({ [spellID] = anything }, the talents on now). { [spellID] = seconds
-- until it is fully back }: an ability with charges holds a loadout up until
-- every charge is back (Soul Immolation at 0/2 was still refused at 1/2,
-- measured 2026-11-01), so its time runs to the last one.
local function Recovering(extra)
	local out = {}
	if not C_Spell then return out end
	local now, seen = GetTime(), {}
	local function Left(start, duration)
		if Plain(start) and Plain(duration) and duration > GCD then
			local left = start + duration - now
			if left > 0 then return left end
		end
	end
	local function Look(spellID)
		if not Plain(spellID) or seen[spellID] then return end
		seen[spellID] = true
		local ok, charges = pcall(C_Spell.GetSpellCharges, spellID)
		if ok and type(charges) == "table" and Plain(charges.currentCharges) and Plain(charges.maxCharges) then
			-- with charges the cooldown only shows while none is left: the charges tell it all
			local cur, max = charges.currentCharges, charges.maxCharges
			local left = cur < max and Left(charges.cooldownStartTime, charges.cooldownDuration)
			if left then
				out[spellID] = left + (max - cur - 1) * charges.cooldownDuration
				return
			end
		end
		local okCd, cd = pcall(C_Spell.GetSpellCooldown, spellID)
		out[spellID] = okCd and type(cd) == "table" and Left(cd.startTime, cd.duration) or nil
	end
	for spellID in pairs(extra or {}) do Look(spellID) end
	if not (C_SpellBook and C_SpellBook.GetNumSpellBookSkillLines) then return out end
	pcall(function()
		local bank = Enum.SpellBookSpellBank.Player
		for tab = 1, C_SpellBook.GetNumSpellBookSkillLines() do
			local line = C_SpellBook.GetSpellBookSkillLineInfo(tab)
			if line and not line.offSpecID then
				for i = line.itemIndexOffset + 1, line.itemIndexOffset + line.numSpellBookItems do
					local _, _, spellID = C_SpellBook.GetSpellBookItemType(i, bank)
					if spellID and not C_SpellBook.IsSpellBookItemPassive(i, bank) then
						Look(spellID)
						Look(C_Spell.GetOverrideSpell and C_Spell.GetOverrideSpell(spellID))
					end
				end
			end
		end
	end)
	return out
end

local function Soonest(recovering)
	local soonest
	for _, left in pairs(recovering) do
		if not soonest or left < soonest then soonest = left end
	end
	return soonest
end

local function ActiveTraitConfig()
	return C_ClassTalents.GetActiveConfigID and C_ClassTalents.GetActiveConfigID() or nil
end

local function SpellName(spellID)
	local ok, name = pcall(C_Spell.GetSpellName, spellID)
	if ok and not (issecretvalue and issecretvalue(name)) and type(name) == "string" and name ~= "" then return name end
end

-- Of the spells `ids` ({ [spellID] = anything }), the one whose name `text`
-- contains; the longest name wins ("Darkness" is part of "Dark Matter").
local function Named(text, ids)
	local best, bestLen
	for id in pairs(ids) do
		local name = SpellName(id)
		if name and text:find(name, 1, true)
			and (not best or #name > bestLen or (#name == bestLen and id < best)) then
			best, bestLen = id, #name
		end
	end
	return best
end

-- The talents on now: { [spellID] = entryID }
local function TalentSpells()
	local out, active = {}, ActiveTraitConfig()
	local ok, info = pcall(C_Traits.GetConfigInfo, active)
	local treeID = ok and type(info) == "table" and type(info.treeIDs) == "table" and info.treeIDs[1]
	local okNodes, nodes = pcall(C_Traits.GetTreeNodes, treeID)
	if not treeID or not okNodes or type(nodes) ~= "table" then return out end
	for _, nodeID in ipairs(nodes) do
		local okNode, node = pcall(C_Traits.GetNodeInfo, active, nodeID)
		local e = okNode and type(node) == "table" and node.activeEntry
		if type(e) == "table" and e.entryID and (e.rank or 0) > 0 and not (node.subTreeID and node.subTreeActive == false) then
			local okEntry, entry = pcall(C_Traits.GetEntryInfo, active, e.entryID)
			local okDef, def = false, nil
			if okEntry and type(entry) == "table" and entry.definitionID then
				okDef, def = pcall(C_Traits.GetDefinitionInfo, entry.definitionID)
			end
			if okDef and type(def) == "table" and def.spellID then out[def.spellID] = e.entryID end
		end
	end
	return out
end

-- A talent's text: its spell's description, else its tooltip
local function TalentText(spellID, entryID)
	local ok, desc = pcall(C_Spell.GetSpellDescription, spellID)
	if ok and type(desc) == "string" and desc ~= "" then return desc end
	if not (C_TooltipInfo and C_TooltipInfo.GetTraitEntry) then return nil end
	local okTip, data = pcall(C_TooltipInfo.GetTraitEntry, entryID)
	if not okTip or type(data) ~= "table" or type(data.lines) ~= "table" then return nil end
	local parts = {}
	for _, line in ipairs(data.lines) do
		if type(line.leftText) == "string" then parts[#parts + 1] = line.leftText end
	end
	return table.concat(parts, "\n")
end

-- The recovering ability a refusal waits for, as far as its text tells: one it
-- names (a talent's own ability), else one named in the text of the talent it
-- names. "You can't change talents while Tempered Soul is on cooldown": Tempered
-- Soul is passive, its text reads "The cooldown of Soul Immolation is reduced".
-- Seconds left of a spell's cooldown however short, the global one included, or nil
local function CooldownLeft(spellID)
	local ok, cd = pcall(C_Spell.GetSpellCooldown, spellID)
	if not ok or type(cd) ~= "table" or not Plain(cd.startTime) or not Plain(cd.duration) or cd.duration <= 0 then
		return nil
	end
	local left = cd.startTime + cd.duration - GetTime()
	return left > 0 and left or nil
end

-- `talents` is TalentSpells(). Returns the ability, and the talent the
-- refusal names with the length of its text (for the log).
local function Blocker(reason, recovering, talents)
	local id = Named(reason, recovering)
	if id then return id end
	local talent = Named(reason, talents)
	local text = talent and TalentText(talent, talents[talent])
	return text and Named(text, recovering) or nil, talent, text and #text or 0
end

local function HasStagedChanges(configID)
	if not configID or not C_Traits.ConfigHasStagedChanges then return false end
	local ok, staged = pcall(C_Traits.ConfigHasStagedChanges, configID)
	return ok and staged == true
end

-- A refused loadout stays staged in the talent tree, as if picked by hand and
-- not applied, and the next request is judged with it. It is taken back out,
-- so the tree shows what is on. (Whatever the player had staged by hand was
-- already replaced by the request.)
local function RollBack()
	local active = ActiveTraitConfig()
	if not HasStagedChanges(active) or not C_Traits.RollbackConfig then return end
	local ok, rolled = pcall(C_Traits.RollbackConfig, active)
	ns.LogReturns("RollbackConfig(" .. tostring(active) .. ")", ok, rolled)
end

-- The game's reason talents cannot change at all right now, asked before a
-- request, or nil. With changes staged it judges those instead, so then it is
-- not asked.
local function CannotChange()
	if not C_ClassTalents.CanChangeTalents or HasStagedChanges(ActiveTraitConfig()) then return nil end
	local ok, canChange, _, changeError = pcall(C_ClassTalents.CanChangeTalents)
	if not ok or canChange ~= false then return nil end
	return (type(changeError) == "string" and changeError ~= "") and changeError or L["unknown reason"]
end

-- Returns accepted, reason, holdFor: when the game holds the change up, the
-- seconds until it is worth asking again. Such a refusal is not a try.
local function LoadTalents(specID, configID)
	local cannot = CannotChange()
	if cannot then return false, cannot end
	local ok, result, changeError, learned = pcall(C_ClassTalents.LoadConfig, configID, true)
	ns.LogReturns("LoadConfig(" .. tostring(configID) .. ", true)", ok, result, changeError, learned)
	local R = Enum.LoadConfigResult
	if not ok or result == nil or result == R.Error then
		refusedAt = GetTime()
		RollBack()
		local step = pending.steps.talents
		local reason = ok and type(changeError) == "string" and changeError ~= "" and changeError or nil
		if reason then
			-- the talents' own abilities count too, besides the spell book's
			local talents = TalentSpells()
			local recovering = Recovering(talents)
			local blocker, talent, textLength = Blocker(reason, recovering, talents)
			-- Right after a cast every talent ability is on the global cooldown, and the
			-- game names the first one the loadout takes out (Darkness, measured
			-- 2026-11-01). Asked again once that is over, when it names what really
			-- holds the loadout up; nothing is said or shown for it.
			local gcd = not blocker and talent and CooldownLeft(talent)
			if gcd and gcd <= GCD then
				ns.Debug("apply: %s is on the global cooldown", tostring(SpellName(talent)))
				step.held, step.heldSpec = nil, specID
				return false, reason, math.max(LOAD_GAP, gcd + HOLD_MARGIN)
			end
			if not step.told then
				step.told = true
				ns.Msg(L["Talent loadout postponed: %s It is tried again when the cooldown ends."], reason)
			end
			-- asked again when the ability it waits for is fully back, else when the first one is
			local wait = blocker and recovering[blocker] or Soonest(recovering)
			if blocker then
				ns.Debug("apply: waits for %s %d", tostring(SpellName(blocker)), blocker)
			else
				ns.Debug("apply: waits for an ability not named (talent %s, text of %d bytes)",
					talent and (tostring(SpellName(talent)) .. " " .. talent) or "none", textLength or 0)
			end
			step.heldSpec = specID
			step.held = { spell = blocker, endsAt = wait and GetTime() + wait }
			return false, reason, wait and math.max(LOAD_GAP, wait + HOLD_MARGIN) or HOLD_POLL
		end
		-- refused without a reason: too soon after another request, once per step
		step.held = nil
		if ok and not step.early then
			step.early, step.heldSpec = true, specID
			return false, L["unknown reason"], LOAD_GAP
		end
		return false, L["unknown reason"]
	end
	if result == R.LoadInProgress then
		pending.commitSpecID, pending.commitConfigID = specID, configID   -- finished by TRAIT_CONFIG_UPDATED
		committingAt = GetTime()
	else
		RememberConfig(specID, configID)
	end
	return true
end

-- PvP talents are learned at once, no cast. Returns accepted, reason
local function LearnPvp(plan)
	if not LearnPvpTalent then return false, L["unknown reason"] end
	for _, change in ipairs(plan) do
		local ok, err = pcall(LearnPvpTalent, change.id, change.slot)
		ns.LogReturns(string.format("LearnPvpTalent(%d, %d)", change.id, change.slot), ok, err)
		if not ok then return false, tostring(err) end
	end
	return true
end

-- Names for a setup, for the dry run and the debug log
local function DescribeSetup(setup)
	local spec = setup.specID and ns.GetSpecByID(setup.specID)
	local config = setup.configID and select(2, pcall(C_Traits.GetConfigInfo, setup.configID))
	local set = setup.setID and C_EquipmentSet.GetEquipmentSetInfo(setup.setID)
	return spec and spec.name or "-", type(config) == "table" and config.name or "-", set or "-", PvpNames(setup.pvp)
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
	ns.LogApplyEnd(message and string.format(message, ...) or nil)
	pending = nil
	if message then ns.Msg(message, ...) end
	-- an automatic apply that came due meanwhile is settled now instead of
	-- landing on a later manual change
	ns.QueueCheck(0.1)
end

-- The step whose cast is pending right now: spec first, then talents (gear has no cast).
local function CastingStep()
	local setup = pending.setup
	local specID = ns.GetCurrentSpecID()
	if setup.specID and setup.specID ~= specID then return pending.steps.spec, "spec" end
	if setup.configID and ns.GetActiveConfigID(specID) ~= setup.configID then return pending.steps.talents, "talents" end
end

local function Interrupted(name)
	ns.Debug("apply: %s cast interrupted", name)
	ns.OnApplyInterrupted()
	Finish(L["%s interrupted. Click the HUD to apply again."], L[name == "spec" and "Spec change" or "Talent change"])
end

-- The cast of `step` was seen and is gone while the step is not done. nil: no
-- cast was seen; false: gone, but a cast that just finished needs a moment to
-- show up in the state, so wait; true: gone for good, interrupted.
local function CastGone(step)
	if not step.castSeen then return nil end
	step.castGoneAt = step.castGoneAt or GetTime()
	return GetTime() - step.castGoneAt >= CAST_GONE
end

local function IsHeld(step)
	return step.heldUntil ~= nil and GetTime() < step.heldUntil
end

-- held up for a reason the game gave (not just for asking too soon)
local function IsHeldUp(step)
	return IsHeld(step) and step.held ~= nil
end

-- One step: ask (again) when allowed. Returns false when the step is out of
-- tries, or held up by the game for longer than it is worth waiting.
local function Ask(name, request)
	local step = pending.steps[name]
	local now = GetTime()
	if step.askedAt and now - step.askedAt < GRACE then return true end   -- give the last request a moment
	if IsHeld(step) then return true end
	if (step.tries or 0) >= MAX_TRIES then return false end
	step.tries = (step.tries or 0) + 1
	step.askedAt = now
	pending.expires = now + APPLY_TIMEOUT
	ns.LogAsk(name, step.tries, pending.setup)
	local accepted, reason, holdFor = request()
	step.reason = reason
	ns.Debug("apply: %s, try %d: %s%s", name, step.tries, accepted and "asked" or ("refused" .. (reason and (" (" .. reason .. ")") or "")),
		holdFor and string.format(", held up, again in %.1f s", holdFor) or "")
	step.heldUntil = nil
	if holdFor then
		-- not a try: what it takes is time, then asking again
		step.tries = step.tries - 1
		step.heldSince = step.heldSince or now
		if now + holdFor - step.heldSince > HOLD_LIMIT then return false end
		step.heldUntil = now + holdFor
		pending.expires = step.heldUntil + APPLY_TIMEOUT
	end
	return true
end

function ns.ContinueApply()
	if not pending then return end
	if InCombatLockdown() then
		-- the clock only runs while something can be done (a held-up loadout keeps its own wait)
		pending.expires = math.max(pending.expires, GetTime() + APPLY_TIMEOUT)
		return
	end
	local setup = pending.setup
	local specID = ns.GetCurrentSpecID()
	local needSpec = setup.specID and setup.specID ~= specID

	-- a held-up loadout belongs to the spec it was asked for in: the player changed spec
	if pending.steps.talents.heldSince and pending.steps.talents.heldSpec ~= specID then
		ns.Debug("apply: held-up loadout dropped, the spec changed")
		return Finish()
	end
	if GetTime() > pending.expires then
		ns.Debug("apply: timed out")
		-- only the spec step can wait that long without asking (the player kept moving)
		return Finish(needSpec and L["Could not switch specialization."] or nil)
	end
	-- the previous request, or the player's own cast: wait it out. A cast seen
	-- after a request of ours means the client took it. While the game holds a
	-- loadout up nothing is asked, so the player's casts do not matter.
	if IsCasting() and not IsHeld(pending.steps.talents) then
		local step = CastingStep()
		if step and step.askedAt then step.castSeen, step.castGoneAt = true, nil end
		return Waiting("casting")
	end

	if needSpec then
		local gone = CastGone(pending.steps.spec)
		if gone then return Interrupted("spec") elseif gone == false then return end
		-- asked as soon as the player stands still
		if IsMoving() then return Waiting("moving") end
		if not Ask("spec", function() return SwitchSpec(setup.specID) end) then
			return Finish(L["Could not switch specialization."])
		end
		return   -- talents and gear belong to the new spec
	end

	local talents = pending.steps.talents
	Waiting(IsHeldUp(talents) and "held" or nil)
	-- the HUD counts the wait down, a second at a time
	if IsHeldUp(talents) and talents.held.endsAt then
		local second = math.ceil(talents.held.endsAt - GetTime())
		if second ~= talents.held.second then
			talents.held.second = second
			ns.UpdateHUD()
		end
	end
	local done = true
	-- a forced setup asks each step once even when it looks done already
	local force = setup.force
	if setup.setID and (not ns.IsSetEquipped(setup.setID) or (force and not pending.steps.gear.tries)) then
		done = false
		if not Ask("gear", function() return ns.EquipSet(setup.setID) end) then
			local _, _, setName = DescribeSetup(setup)
			return Finish(L["Could not equip %s."], setName)
		end
	end
	local talentsDone = true
	if setup.configID and (ns.GetActiveConfigID(specID) ~= setup.configID
		or (force and (not talents.tries or talents.heldUntil))) then
		done, talentsDone = false, false
		local gone = CastGone(talents)
		if gone then return Interrupted("talents") elseif gone == false then return end
		-- a loadout asked for too soon after a refused one is refused too, without a reason
		if not IsHeld(talents) and refusedAt and GetTime() - refusedAt < LOAD_GAP then return end
		if not Ask("talents", function() return LoadTalents(specID, setup.configID) end) then
			return Finish(L["Could not load the talent loadout: %s"], talents.reason or L["unknown reason"])
		end
		if IsHeldUp(talents) then Waiting("held") end
	end
	-- PvP talents once the loadout is in, so the two changes never cross. What is
	-- on already is not asked again, forced or not: there is nothing to drop.
	if setup.pvp and talentsDone then
		local plan = ns.PvpPlan(setup.pvp)
		if #plan > 0 then
			done = false
			if not Ask("pvp", function() return LearnPvp(plan) end) then
				return Finish(L["Could not set the PvP talents: %s"], pending.steps.pvp.reason or L["unknown reason"])
			end
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
	local description = string.format("spec %s, talents %s, gear %s, PvP talents %s", DescribeSetup(setup))
	ns.Debug("apply: %s", description)
	pending = { setup = setup, expires = GetTime() + APPLY_TIMEOUT, steps = { spec = {}, talents = {}, gear = {}, pvp = {} } }
	ns.LogApplyStart(setup, description)
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
			committingAt = nil
		end
	end
	ns.ContinueApply()
end

-- CONFIG_COMMIT_FAILED: the commit we started did not go through (interrupted,
-- or refused after all). Asking the same thing again would not change that.
function ns.OnTalentsFailed()
	-- a commit of ours that did not go through (its cast interrupted: the player
	-- cast something) leaves the loadout staged, like a refusal. Only ours: one
	-- the player started in the talent window is theirs to undo.
	if committingAt and GetTime() - committingAt < CAST_WINDOW then
		committingAt = nil
		RollBack()
	end
	if pending and pending.commitConfigID then
		pending.commitSpecID, pending.commitConfigID = nil, nil
		Interrupted("talents")
	end
end

-- UNIT_SPELLCAST_INTERRUPTED for the player: ours, when a request of ours is out
-- and its cast was seen or is due.
function ns.OnCastInterrupted()
	if not pending then return end
	local step, name = CastingStep()
	if step and step.askedAt and (step.castSeen or GetTime() - step.askedAt < CAST_WINDOW) then
		Interrupted(name)
	end
end

function ns.IsApplying()
	return pending ~= nil
end

-- A held-up loadout belongs to the scenario it was asked for: on entering
-- another one it is dropped, so that scenario's own apply is not kept waiting.
function ns.DropHeldApply()
	if pending and pending.steps.talents.heldSince then
		ns.Debug("apply: held-up loadout dropped, another scenario")
		Finish()
	end
end

-- the module was switched off: whatever was being applied is dropped
function ns.CancelApply()
	if pending then ns.LogApplyEnd("cancelled: the module was switched off") end
	pending = nil
end

-- "moving" while a spec change waits for the player to stand still, "held"
-- while the game refuses the loadout for now
function ns.GetApplyWait()
	return pending and pending.waiting or nil
end

function ns.IsHeldUp()
	return pending ~= nil and IsHeldUp(pending.steps.talents)
end

-- While the game holds a loadout up: the ability it waits for (nil when the
-- refusal does not tell) and the seconds until that one is back (nil when
-- nothing is recovering and it is just asked again now and then)
function ns.GetHeldUp()
	local step = pending and pending.steps.talents
	if not step or not IsHeldUp(step) then return nil end
	return step.held.spell, step.held.endsAt and math.max(0, step.held.endsAt - GetTime()) or nil
end
