local ADDON, ns = ...
local U = ns.Util

-- ===========================================================================
-- /ckpvp scan: what the client itself says about the abilities and talents
-- in the table, written to the saved variables (CombatKitPvPDB.scan) so the
-- numbers can be checked offline against the game's own data.
--
-- For every ability, its buffs, every talent the table names, and a list of
-- talents worth looking at: the spell's name, description (the talent's
-- numbers are in there) and base cooldown. For the player's own class: every
-- node of the talent tree and every PvP talent, whether chosen or not. Spell
-- data loads lazily, so the scan asks for it and reads a batch per tick.
-- ===========================================================================

local S = {}
ns.Scan = S

S.BATCH = 25
S.STEP = 0.2

-- talents other trackers credit with changing these cooldowns: looked up, never trusted blindly
S.CANDIDATES = { 47476, 102543, 102560, 114154, 196704, 199259, 200733, 202107, 202424, 203965, 204074, 204268,
	205673, 205727, 210476, 216853, 228049, 231548, 233412, 234299, 235219, 235941, 238100, 248443, 256165, 260404,
	264874, 266921, 288733, 342249, 343247, 344359, 345829, 354825, 373035, 374383, 375406, 376204, 377637, 378425,
	381647, 381785, 382424, 382552, 383338, 384072, 384444, 384820, 384909, 386659, 386686, 387807, 388813, 389539,
	389682, 389783, 390135, 390378, 391174, 391271, 394013, 397103, 410320, 410358, 412713, 414659, 424742, 429072,
	431067, 434136, 437122, 441415, 450631, 457574, 459450, 462440, 468743, 1217092, 1218603, 1241511, 1244025,
	1244110, 1246481, 1254194, 1255166, 1256295, 1256353, 1258485, 1265517, 1266307, 1270255, 1277933 }

local running

local function Add(list, seen, id, kind)
	if type(id) == "number" and not seen[id] then
		seen[id] = kind
		list[#list + 1] = id
	end
end

-- the player's own class: every talent node and PvP talent
local function OwnTree(list, seen, out)
	local api = C_Traits
	local configID = C_ClassTalents and U.Plain(C_ClassTalents.GetActiveConfigID)
	if not (api and type(configID) == "number") then return end
	local treeIDs = U.Field(U.Plain(api.GetConfigInfo, configID), "treeIDs")
	for _, treeID in ipairs(type(treeIDs) == "table" and treeIDs or {}) do
		for _, nodeID in ipairs(U.Plain(api.GetTreeNodes, treeID) or {}) do
			local ni = U.Plain(api.GetNodeInfo, configID, nodeID)
			local entryIDs = U.Field(ni, "entryIDs")
			local active = U.Field(U.Field(ni, "activeEntry"), "entryID")
			for _, entryID in ipairs(type(entryIDs) == "table" and entryIDs or {}) do
				local ei = U.Plain(api.GetEntryInfo, configID, entryID)
				local definitionID = U.Field(ei, "definitionID")
				local di = definitionID and U.Plain(api.GetDefinitionInfo, definitionID)
				local spellID = U.Field(di, "spellID")
				if type(spellID) == "number" then
					Add(list, seen, spellID, "tree")
					out[#out + 1] = string.format("%d|%d|%d|%s|%s|%s", nodeID, entryID, spellID,
						tostring(U.Field(ei, "maxRanks")), tostring(U.Field(ei, "subTreeID")), entryID == active and "chosen" or "")
				end
			end
		end
	end
	-- PvP talents: the ones each slot offers (which leave out the chosen ones) plus the chosen ones, once each
	local spec = C_SpecializationInfo
	if spec and spec.GetPvpTalentSlotInfo then
		local talentIDs, listed = {}, {}
		local function want(talentID)
			if type(talentID) == "number" and not listed[talentID] then
				listed[talentID] = true
				talentIDs[#talentIDs + 1] = talentID
			end
		end
		for slot = 1, 3 do
			local info = U.Plain(spec.GetPvpTalentSlotInfo, slot)
			local available = U.Field(info, "availableTalentIDs")
			for _, talentID in ipairs(type(available) == "table" and available or {}) do want(talentID) end
			want(U.Field(info, "selectedTalentID"))
		end
		if spec.GetAllSelectedPvpTalentIDs then
			for _, talentID in ipairs(U.Plain(spec.GetAllSelectedPvpTalentIDs) or {}) do want(talentID) end
		end
		table.sort(talentIDs)
		for _, talentID in ipairs(talentIDs) do
			local spellID = U.Field(U.Plain(spec.GetPvpTalentInfo, talentID), "spellID")
			if type(spellID) == "number" then
				Add(list, seen, spellID, "pvp")
				out[#out + 1] = string.format("pvp|%d|%d|%s", talentID, spellID,
					U.Plain(IsPlayerSpell, spellID) and "chosen" or "")
			end
		end
	end
end

local function Collect()
	local list, seen, tree = {}, {}, {}
	for _, class in ipairs({ "DEATHKNIGHT", "DEMONHUNTER", "DRUID", "EVOKER", "HUNTER", "MAGE", "MONK", "PALADIN",
		"PRIEST", "ROGUE", "SHAMAN", "WARLOCK", "WARRIOR" }) do
		for _, a in ipairs(ns.Spells.BY_CLASS[class] or {}) do
			Add(list, seen, a.id, "ability")
			for _, aura in ipairs(a.auras) do Add(list, seen, aura, "aura") end
			for _, m in ipairs(a.mods or {}) do Add(list, seen, m.talent, "mod") end
		end
	end
	for _, id in ipairs(S.CANDIDATES) do Add(list, seen, id, "candidate") end
	OwnTree(list, seen, tree)
	return list, seen, tree
end

local function ReadOne(id, kind)
	local name = C_Spell and C_Spell.GetSpellName and U.Plain(C_Spell.GetSpellName, id)
	local desc = C_Spell and C_Spell.GetSpellDescription and U.Plain(C_Spell.GetSpellDescription, id)
	local base = type(GetSpellBaseCooldown) == "function" and U.Plain(GetSpellBaseCooldown, id)
	local charges = C_Spell and C_Spell.GetSpellCharges and U.Plain(C_Spell.GetSpellCharges, id)
	local max = U.Field(charges, "maxCharges")
	local known = type(IsPlayerSpell) == "function" and U.Plain(IsPlayerSpell, id)
	desc = type(desc) == "string" and desc:gsub("[\r\n]+", " / ") or ""
	-- the tooltip's cooldown or recharge line: the recharge of a charge spell is only there
	local tip = ""
	if C_TooltipInfo and C_TooltipInfo.GetSpellByID then
		local data = U.Plain(C_TooltipInfo.GetSpellByID, id)
		local lines = U.Field(data, "lines")
		for i = 1, type(lines) == "table" and #lines or 0 do
			local line = lines[i]
			for _, text in ipairs({ U.Field(line, "leftText"), U.Field(line, "rightText") }) do
				if type(text) == "string" and (text:find("冷卻") or text:find("充能") or text:find("ooldown") or text:find("echarge")) then
					tip = tip .. (tip ~= "" and " / " or "") .. text
				end
			end
		end
	end
	return string.format("%d|%s|%s|%s|%s|%s|%s|%s", id, kind, tostring(name), tostring(base), tostring(max),
		known and "known" or "", tip, desc)
end

local function Finish()
	local r = running
	running = nil
	ns.db.scan = {
		at = date("%Y-%m-%d %H:%M:%S"), class = select(2, UnitClass("player")), spec = ns.PlayerSpec and ns.PlayerSpec(),
		version = C_AddOns.GetAddOnMetadata("CombatKit", "Version"), count = #r.items, items = r.items, tree = r.tree,
	}
	ns.Say(string.format(ns.L["PVP_SCAN_DONE"], #r.items, #r.tree))
end

local function Step()
	local r = running
	if not r then return end
	-- ask for the next batch first; the batch asked for last time is read now
	local first = r.next
	for i = first, math.min(#r.list, first + S.BATCH - 1) do
		if C_Spell and C_Spell.RequestLoadSpellData then pcall(C_Spell.RequestLoadSpellData, r.list[i]) end
	end
	if r.pending then
		for i = r.pending, math.min(#r.list, r.pending + S.BATCH - 1) do
			r.items[#r.items + 1] = ReadOne(r.list[i], r.seen[r.list[i]])
		end
	end
	r.pending = first <= #r.list and first or nil
	r.next = first + S.BATCH
	if not r.pending then return Finish() end
	C_Timer.After(S.STEP, Step)
end

function S.Start()
	if running then return false end
	local list, seen, tree = Collect()
	running = { list = list, seen = seen, tree = tree, items = {}, next = 1, pending = nil }
	ns.Say(string.format(ns.L["PVP_SCAN_START"], #list))
	Step()
	return true
end

function S.Running() return running ~= nil end
