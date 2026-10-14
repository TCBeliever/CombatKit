local ADDON, ns = ...

-- ===========================================================================
-- Inspect: a teammate's talents, so that the cooldown of a watched ability is
-- theirs and not the class's base. The inspected talent tree is walked with
-- C_Traits; what each selected talent, PvP talent and specialization passive
-- does to a watched ability comes from TalentData.lua, generated from the
-- game's data files (tools/talentdata.py): seconds or a share off the
-- cooldown, by rank, or a charge. A watched ability that the tree offers and
-- the teammate did not take is dropped from the row, and so is one no spell
-- list gives their specialization (`specs` in Spells.lua). When the game is
-- a newer build than the data, a selected talent the data does not know is
-- read from its text (the game's own tooltip) as a stopgap.
--
-- A request is never sent while the player has the inspect window open: it
-- would replace whoever they are looking at.
--
-- Asked for once per teammate when they arrive and again at every round
-- start; one request in flight at a time, retried at a fixed interval while
-- the teammate is out of inspect range or the texts are not loaded yet, and
-- given up after a while. The player's own talents need no request.
-- ===========================================================================

local Inspect = {}
ns.Inspect = Inspect

local RETRY = 5          -- seconds between attempts
local MAX_TRIES = 10     -- then give up until the next round
local TIMEOUT = 3        -- an answer later than this is not waited for
local PVP_SLOTS = 3

local INSPECT_CONFIG = (Constants and Constants.TraitConsts and Constants.TraitConsts.INSPECT_TRAIT_CONFIG_ID) or -1
local ORDER = { "player", "party1", "party2" }

local pending = {}       -- [unit] = { unit, guid, class, tries, nextAt, sentAt }
local inflight           -- the pending record whose request is out
local onResult           -- fn(unit, specID, results, complete)
local lastResult = {}    -- [unit] = a line for the status command

local function plain(v) return type(canaccessvalue) ~= "function" or canaccessvalue(v) end

-- the player is looking at someone in the inspect window
local function UserInspecting()
	if not InspectFrame then return false end
	local ok, shown = pcall(InspectFrame.IsShown, InspectFrame)
	return ok and shown == true
end

-- a specialization ID, or nil
local function Spec(id)
	if type(id) == "number" and plain(id) and id > 0 then return id end
end

local function InspectedSpec(unit)
	local get = (C_SpecializationInfo and C_SpecializationInfo.GetInspectSpecialization) or GetInspectSpecialization
	if not get then return nil end
	local ok, id = pcall(get, unit)
	return ok and Spec(id) or nil
end

local function PlayerSpec()
	local api = C_SpecializationInfo
	if not (api and api.GetSpecialization and api.GetSpecializationInfo) then return nil end
	local okI, index = pcall(api.GetSpecialization)
	if not okI or type(index) ~= "number" then return nil end
	local ok, id = pcall(api.GetSpecializationInfo, index)
	return ok and Spec(id) or nil
end
Inspect.PlayerSpec = PlayerSpec

-- ---------------------------------------------------------------------------
-- Reading a talent's text
-- ---------------------------------------------------------------------------

-- Sentences that change a cooldown as a one-off ("each time", "whenever")
-- are not a static modifier and are left alone.
local DYNAMIC = { "each ", "every ", "whenever", "when ", " per ", "每", "當", "当" }

-- how a cooldown is written as shortened by seconds / by a share, lengthened,
-- and how an extra charge is written; in the client's languages the module
-- has (English, Traditional and Simplified Chinese)
local LESS_SEC = {
	"[Rr]educ%a+ the cooldowns? of .- by (%d+%.?%d*) ?sec",
	"[Rr]educ%a+ .- cooldowns? by (%d+%.?%d*) ?sec",
	"cooldowns? .- reduced by (%d+%.?%d*) ?sec",
	"cooldowns? .- decreased by (%d+%.?%d*) ?sec",
	"冷卻時間縮短%s*(%d+%.?%d*)%s*秒", "冷卻時間減少%s*(%d+%.?%d*)%s*秒",
	"冷却时间缩短%s*(%d+%.?%d*)%s*秒", "冷却时间减少%s*(%d+%.?%d*)%s*秒",
}
local LESS_MIN = {
	"[Rr]educ%a+ the cooldowns? of .- by (%d+%.?%d*) ?min",
	"cooldowns? .- reduced by (%d+%.?%d*) ?min",
	"冷卻時間縮短%s*(%d+%.?%d*)%s*分", "冷却时间缩短%s*(%d+%.?%d*)%s*分",
}
local LESS_PCT = {
	"[Rr]educ%a+ the cooldowns? of .- by (%d+%.?%d*)%%",
	"[Rr]educ%a+ .- cooldowns? by (%d+%.?%d*)%%",
	"cooldowns? .- reduced by (%d+%.?%d*)%%",
	"cooldowns? .- decreased by (%d+%.?%d*)%%",
	"冷卻時間縮短%s*(%d+%.?%d*)%s*%%", "冷卻時間減少%s*(%d+%.?%d*)%s*%%",
	"冷却时间缩短%s*(%d+%.?%d*)%s*%%", "冷却时间减少%s*(%d+%.?%d*)%s*%%",
}
local MORE_SEC = {
	"[Ii]ncreas%a+ the cooldowns? of .- by (%d+%.?%d*) ?sec",
	"cooldowns? .- increased by (%d+%.?%d*) ?sec",
	"冷卻時間延長%s*(%d+%.?%d*)%s*秒", "冷卻時間增加%s*(%d+%.?%d*)%s*秒",
	"冷却时间延长%s*(%d+%.?%d*)%s*秒", "冷却时间增加%s*(%d+%.?%d*)%s*秒",
}
local CHARGES_N = { "(%d+) additional charges?", "額外.-(%d+)%s*次?充能", "额外.-(%d+)%s*次?充能" }
local CHARGE_ONE = { "additional charge", "額外.-充能", "额外.-充能" }   -- patterns

local function First(patterns, s)
	for _, p in ipairs(patterns) do
		local v = s:match(p)
		if v then return tonumber(v) end
	end
end

local function Matches(patterns, s)
	for _, p in ipairs(patterns) do
		if s:find(p) then return true end
	end
	return false
end

local function Any(list, s)
	for _, w in ipairs(list) do
		if s:find(w, 1, true) then return true end
	end
	return false
end

-- the text cut into sentences, decimals kept whole
local function Sentences(text)
	local out = {}
	text = text:gsub("(%d)%.(%d)", "%1\1%2"):gsub("。", ".")   -- a byte class would cut inside a Chinese character
	for s in text:gmatch("[^%.]+") do
		s = s:gsub("\1", ".")
		out[#out + 1] = s
	end
	return out
end

-- What a talent's text says about the watched abilities: for every
-- sentence that names one, the seconds taken off (or added), the share
-- taken off and the charges added. `byName` maps a watched ability's name
-- to its definition. Returns a list of { def = def, sec = n, pct = n,
-- charges = n }, one per ability named in a sentence that says something.
function Inspect.Parse(text, byName)
	local out = {}
	if type(text) ~= "string" or text == "" then return out end
	for _, s in ipairs(Sentences(text)) do
		local named = {}
		for name, def in pairs(byName) do
			if s:find(name, 1, true) then named[#named + 1] = def end
		end
		if #named > 0 and not Any(DYNAMIC, s:lower()) then
			local sec, pct, charges = 0, 0, 0
			local less = First(LESS_SEC, s)
			local lessMin = First(LESS_MIN, s)
			local more = First(MORE_SEC, s)
			if less then sec = sec - less end
			if lessMin then sec = sec - lessMin * 60 end
			if more then sec = sec + more end
			pct = First(LESS_PCT, s) or 0
			local n = First(CHARGES_N, s)
			if n then charges = n elseif Matches(CHARGE_ONE, s) then charges = 1 end
			if sec ~= 0 or pct ~= 0 or charges ~= 0 then
				for _, def in ipairs(named) do
					out[#out + 1] = { def = def, sec = sec, pct = pct, charges = charges }
				end
			end
		end
	end
	return out
end

-- ---------------------------------------------------------------------------
-- Walking a talent configuration
-- ---------------------------------------------------------------------------

local function Lines(data)
	if type(data) ~= "table" or type(data.lines) ~= "table" then return nil end
	local parts = {}
	for _, line in ipairs(data.lines) do
		if type(line) == "table" and type(line.leftText) == "string" and plain(line.leftText) then
			parts[#parts + 1] = line.leftText
		end
	end
	if #parts == 0 then return nil end
	return table.concat(parts, ". ")
end

-- the text of a selected talent: its tooltip at that rank when the client
-- gives one, else the spell's description; nil when not loaded yet
local function TalentText(entryID, rank, spellID, override, state)
	if type(override) == "string" and override ~= "" then return override end
	if entryID and C_TooltipInfo and C_TooltipInfo.GetTraitEntry then
		local ok, data = pcall(C_TooltipInfo.GetTraitEntry, entryID, rank)
		local text = ok and Lines(data)
		if text then return text end
	end
	if not spellID then return nil end
	local ok, desc = pcall(C_Spell.GetSpellDescription, spellID)
	if ok and type(desc) == "string" and desc ~= "" then return desc end
	if C_Spell.RequestLoadSpellData then pcall(C_Spell.RequestLoadSpellData, spellID) end
	state.complete = false
	return nil
end

local function DefinitionSpell(configID, entryID)
	local ok, entry = pcall(C_Traits.GetEntryInfo, configID, entryID)
	if not ok or type(entry) ~= "table" or not entry.definitionID then return nil end
	local okD, defn = pcall(C_Traits.GetDefinitionInfo, entry.definitionID)
	if not okD or type(defn) ~= "table" then return nil end
	return defn.spellID, defn.overrideDescription, entry.definitionID
end

-- the game's build, as the data file writes it
local function LiveBuild()
	if not GetBuildInfo then return nil end
	local ok, version, build = pcall(GetBuildInfo)
	if ok and type(version) == "string" and build ~= nil then return version .. "." .. tostring(build) end
end

-- the texts are read for talents the data does not know when the game has
-- moved past the data's build
function Inspect.TextFallback()
	local data = ns.TalentData
	if not data or not data.mods then return true end
	local live = LiveBuild()
	return live ~= nil and live ~= data.build
end

-- One configuration (the inspected one, or the player's active one), the
-- selected PvP talents and the specialization, read for a class's watched
-- abilities. Returns results = { [spellID] = { cd = seconds, charges = n,
-- missing = bool } } for every watched ability of the class, and whether
-- everything needed was there (a text not loaded yet says no).
function Inspect.Analyse(configID, class, pvpTalentIDs, spec)
	local defs = ns.SPELLS[class]
	if not defs then return nil, true end
	local data = ns.TalentData or {}
	local mods = data.mods or {}
	local useText = Inspect.TextFallback()
	local byName, acc = {}, {}
	for _, def in ipairs(defs) do
		if useText then
			local ok, name = pcall(C_Spell.GetSpellName, def.id)
			if ok and type(name) == "string" and name ~= "" and plain(name) then byName[name] = def end
		end
		acc[def.id] = { sec = 0, pct = 1, charges = 0, offered = false, taken = false }
	end
	-- a tree node may give the ability as another spell (`casts`: a talent's or
	-- a specialization's version on the same button): it counts as the ability
	local castOf = {}
	for _, def in ipairs(defs) do
		for _, cast in ipairs(def.casts or {}) do castOf[cast] = acc[def.id] end
	end
	local function Of(sid) return sid and (acc[sid] or castOf[sid]) end
	local state = { complete = true }

	-- what the data says a selected spell does, at the rank of the definition taken
	local function AtRank(values, rank)
		if type(values) ~= "table" then return values end
		return values[math.min(math.max(rank or 1, 1), #values)]
	end
	local function ApplyData(source, definitionID, rank)
		local m = source and mods[source]
		if not m then return false end
		for sid, r in pairs(m) do
			local a = acc[sid]
			if a then
				local ranks = r.ranks and definitionID and r.ranks[definitionID]
				local sec = ranks and ranks.sec and AtRank(ranks.sec, rank) or r.sec
				local pct = ranks and ranks.pct and AtRank(ranks.pct, rank) or r.pct
				local charges = ranks and ranks.charges and AtRank(ranks.charges, rank) or r.charges
				if sec then a.sec = a.sec + sec end
				if pct then a.pct = a.pct * (1 + pct / 100) end   -- negative: shorter
				if charges then a.charges = a.charges + charges end
			end
		end
		return true
	end
	-- what a talent's text says (the stopgap on a newer build)
	local function ApplyText(text)
		for _, m in ipairs(Inspect.Parse(text, byName)) do
			local a = acc[m.def.id]
			a.sec = a.sec + m.sec
			a.pct = a.pct * (1 - m.pct / 100)
			a.charges = a.charges + m.charges
		end
	end

	local okC, cfg = pcall(C_Traits.GetConfigInfo, configID)
	if not okC or type(cfg) ~= "table" or type(cfg.treeIDs) ~= "table" then return nil, false end
	for _, treeID in ipairs(cfg.treeIDs) do
		local okN, nodes = pcall(C_Traits.GetTreeNodes, treeID)
		for _, nodeID in ipairs(okN and nodes or {}) do
			local okI, info = pcall(C_Traits.GetNodeInfo, configID, nodeID)
			if okI and type(info) == "table" then
				local active = info.activeEntry
				local rank = (type(active) == "table" and active.rank) or 0
				if info.subTreeID and info.subTreeActive == false then rank = 0 end   -- a hero tree not chosen
				for _, entryID in ipairs(info.entryIDs or {}) do
					local sid = DefinitionSpell(configID, entryID)
					if Of(sid) then Of(sid).offered = true end
				end
				if rank > 0 and active.entryID then
					local sid, override, definitionID = DefinitionSpell(configID, active.entryID)
					if Of(sid) then Of(sid).taken = true end
					if not ApplyData(sid, definitionID, rank) and useText then
						local text = TalentText(active.entryID, rank, sid, override, state)
						if text then ApplyText(text) end
					end
				end
			end
		end
	end
	for _, talentID in ipairs(pvpTalentIDs or {}) do
		local ok, info = pcall(C_SpecializationInfo.GetPvpTalentInfo, talentID)
		local sid = ok and type(info) == "table" and info.spellID
		if sid then
			if Of(sid) then Of(sid).taken = true end
			if not ApplyData(sid) and useText then
				local text = TalentText(nil, nil, sid, nil, state)
				if text then ApplyText(text) end
			end
		end
	end
	-- the specialization's passives
	for _, source in ipairs((spec and data.spec and data.spec[spec]) or {}) do ApplyData(source) end

	-- a PvP talent taken that takes another ability's button (`replaces`):
	-- that ability is gone (Ancient of Lore for Tree of Life)
	for _, def in ipairs(defs) do
		if def.replaces and acc[def.id].taken and acc[def.replaces] then acc[def.replaces].replaced = true end
	end
	local results = {}
	for _, def in ipairs(defs) do
		local a = acc[def.id]
		local base = ns.BaseCooldown(def)
		local cd = math.max(1, math.floor(((base + a.sec) * a.pct) * 2 + 0.5) / 2)
		results[def.id] = { cd = cd, charges = ns.BaseCharges(def) + a.charges, missing = (a.offered and not a.taken) or a.replaced or false }
	end
	return results, state.complete
end

-- ---------------------------------------------------------------------------
-- The queue
-- ---------------------------------------------------------------------------

function Inspect.Start(cb)
	onResult = cb
	pending, inflight, lastResult = {}, nil, {}
end

function Inspect.Stop()
	pending, inflight = {}, nil
end

-- this teammate's talents are wanted (again)
function Inspect.Want(unit, guid, class)
	if pending[unit] and inflight == pending[unit] then return end
	pending[unit] = { unit = unit, guid = guid, class = class, tries = 0, nextAt = 0 }
end

function Inspect.Forget(unit)
	if inflight == pending[unit] then inflight = nil end
	pending[unit] = nil
end

function Inspect.Pending(unit) return pending[unit] ~= nil end

local function PlayerPvpTalents()
	if C_SpecializationInfo and C_SpecializationInfo.GetAllSelectedPvpTalentIDs then
		local ok, ids = pcall(C_SpecializationInfo.GetAllSelectedPvpTalentIDs)
		if ok and type(ids) == "table" then return ids end
	end
	return {}
end

local function InspectedPvpTalents(unit)
	local ids = {}
	if C_SpecializationInfo and C_SpecializationInfo.GetInspectSelectedPvpTalent then
		for i = 1, PVP_SLOTS do
			local ok, id = pcall(C_SpecializationInfo.GetInspectSelectedPvpTalent, unit, i)
			if ok and type(id) == "number" and plain(id) then ids[#ids + 1] = id end
		end
	end
	return ids
end

local function Describe(results, complete)
	local parts = {}
	for id, r in pairs(results or {}) do
		local def = ns.SPELL_BY_ID[id]
		if r.missing then
			parts[#parts + 1] = id .. " missing"
		elseif def and (r.cd ~= ns.BaseCooldown(def) or r.charges ~= ns.BaseCharges(def)) then
			parts[#parts + 1] = string.format("%d cd=%g%s", id, r.cd, r.charges > 1 and (" x" .. r.charges) or "")
		end
	end
	table.sort(parts)
	return (#parts > 0 and table.concat(parts, ", ") or "no changes") .. (complete and "" or " (texts pending)")
		.. (Inspect.TextFallback() and " [data for another build: texts read as well]" or "")
end

-- abilities the spec does not have are missing, whatever the tree said
local function ApplySpec(results, class, spec)
	if not spec then return results end
	results = results or {}
	for _, def in ipairs(ns.SPELLS[class] or {}) do
		if def.specs and not def.specs[spec] then
			local r = results[def.id] or {}
			r.missing = true
			results[def.id] = r
		end
	end
	return results
end

local function Finish(p, configID, pvpIDs, forPlayer, at, spec)
	local results, complete = Inspect.Analyse(configID, p.class, pvpIDs, spec)
	results = ApplySpec(results, p.class, spec)
	if spec then p.spec = spec end
	if results then
		lastResult[p.unit] = string.format("%s: spec %s, %s", p.unit, tostring(spec), Describe(results, complete))
		if onResult then onResult(p.unit, results, complete) end
	else
		complete = false
	end
	if complete then
		pending[p.unit] = nil
	else
		p.nextAt = at + RETRY   -- the texts arrive, the next attempt reads them
	end
	if inflight == p then inflight = nil end
end

-- INSPECT_READY: the answer, for the unit whose GUID this is (any addon's request serves)
function Inspect.Ready(guid, at)
	at = at or GetTime()
	for _, unit in ipairs(ORDER) do
		local p = pending[unit]
		if p and unit ~= "player" then
			local okG, g = pcall(UnitGUID, unit)
			local mine = (okG and plain(g) and g == guid) or (inflight == p and not (okG and plain(g)))
			if mine then
				Finish(p, INSPECT_CONFIG, InspectedPvpTalents(unit), false, at, InspectedSpec(unit))
				if ClearInspectPlayer and not UserInspecting() then pcall(ClearInspectPlayer) end
				return true
			end
		end
	end
	return false
end

-- called regularly: the player's own talents straight away, one teammate request at a time
function Inspect.Tick(at)
	at = at or GetTime()
	local me = pending.player
	if me and me.nextAt <= at then
		me.tries = me.tries + 1
		local configID = C_ClassTalents and C_ClassTalents.GetActiveConfigID and select(2, pcall(C_ClassTalents.GetActiveConfigID))
		if type(configID) == "number" then
			Finish(me, configID, PlayerPvpTalents(), true, at, PlayerSpec())
		else
			me.nextAt = at + RETRY
		end
		if me.tries >= MAX_TRIES then pending.player = nil end
	end
	if UserInspecting() then return end   -- a request now would replace whoever they are looking at
	if inflight then
		if at - (inflight.sentAt or at) > TIMEOUT then
			inflight.nextAt = at + RETRY
			inflight = nil
		end
		return
	end
	for _, unit in ipairs(ORDER) do
		local p = pending[unit]
		if p and unit ~= "player" and p.nextAt <= at then
			p.tries = p.tries + 1
			p.nextAt = at + RETRY
			if p.tries > MAX_TRIES then
				lastResult[unit] = unit .. ": gave up"
				pending[unit] = nil
			else
				local okE, exists = pcall(UnitExists, unit)
				local okC, can = pcall(CanInspect, unit)
				if okE and exists and okC and can == true and NotifyInspect then
					if pcall(NotifyInspect, unit) then
						inflight, p.sentAt = p, at
						return
					end
				end
			end
		end
	end
end

-- for the status command
function Inspect.Debug()
	local out = {}
	for _, unit in ipairs(ORDER) do
		if lastResult[unit] then out[#out + 1] = "inspect " .. lastResult[unit] end
		if pending[unit] then out[#out + 1] = string.format("inspect %s: pending, %d tries", unit, pending[unit].tries) end
	end
	return out
end
