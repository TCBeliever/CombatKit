local ADDON, ns = ...
local CK = CombatKit

-- ===========================================================================
-- Apply log: what the game said around each request of an apply, kept in the
-- saved variables (CombatKitLoadoutDB.applyLog, /ckloadout log) to find out
-- how it refuses a change (a talent's ability still recharging, a key
-- running) and what an addon can read before and after.
--
-- One record per apply: the target, then for every request what could be read
-- before it (can talents change at all, each node the loadout changes with
-- the outgoing talent's cooldown, charges and aura, the abilities still
-- recovering), what the request returned, the apply's own debug lines, and
-- the events, red error texts and system messages until a few seconds after
-- the apply ended, and how it ended.
--
-- A debugging aid: on in a copy run straight from the source (deploy.bat),
-- off in the release, where the packager comments out the @debug@ block
-- below. /ckloadout debug on | off overrides that (ns.db.debugLog).
-- ===========================================================================

local MAX_APPLIES = 30
local MAX_LINES   = 200   -- per apply
local MAX_NODES   = 40    -- changed nodes listed per request
local MAX_SPELLS  = 15    -- recovering abilities listed per request
local AFTER       = 4     -- seconds the events are still listened to once the apply ended
local GCD         = 1.6   -- a cooldown this short is the global one
local DEBUG_BUILD = false
--@debug@
DEBUG_BUILD = true
--@end-debug@

local SI = C_SpecializationInfo

local EVENTS = {
	"UI_ERROR_MESSAGE", "UI_INFO_MESSAGE", "CHAT_MSG_SYSTEM",
	"CONFIG_COMMIT_FAILED", "TRAIT_CONFIG_UPDATED", "TRAIT_CONFIG_LIST_UPDATED", "ACTIVE_COMBAT_CONFIG_CHANGED",
	"PLAYER_TALENT_UPDATE", "PLAYER_PVP_TALENT_UPDATE",
	"PLAYER_SPECIALIZATION_CHANGED", "ACTIVE_PLAYER_SPECIALIZATION_CHANGED",
	"EQUIPMENT_SWAP_FINISHED", "PLAYER_REGEN_DISABLED",
}
local UNIT_EVENTS = {
	"UNIT_SPELLCAST_SENT", "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_SUCCEEDED",
	"UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_FAILED_QUIET", "UNIT_SPELLCAST_INTERRUPTED",
}

local current          -- the record being written
local t0, closeAt      -- GetTime() it began; when it stops listening (set once the apply ended)
local frame, listening = nil, false

function ns.ApplyLogging()
	if not ns.db then return false end
	if ns.db.debugLog ~= nil then return ns.db.debugLog end
	return DEBUG_BUILD
end

function ns.ApplyLogOpen() return current ~= nil end

-- ---------------------------------------------------------------------------
-- Values as text. A secret value (12.x) is named, never compared or added.
-- ---------------------------------------------------------------------------

local function Secret(v) return issecretvalue and issecretvalue(v) or false end

local function Str(v)
	if Secret(v) then return "<secret>" end
	if type(v) == "string" then return '"' .. v .. '"' end
	if type(v) == "number" and v ~= math.floor(v) then return string.format("%.2f", v) end
	if type(v) == "table" then
		local n = 0
		for _ in pairs(v) do n = n + 1 end
		return "table(" .. n .. ")"
	end
	return tostring(v)
end

local function Num(v)
	if Secret(v) or type(v) ~= "number" then return nil end
	return v
end

-- every return of fn(...) as text; "n/a" when the client has no such function
local function Returns(fn, ...)
	if type(fn) ~= "function" then return "n/a" end
	local r = { n = 0 }
	local function pack(...) r.n = select("#", ...); for i = 1, r.n do r[i] = select(i, ...) end end
	pack(pcall(fn, ...))
	if not r[1] then return "error: " .. tostring(r[2]) end
	local out = {}
	for i = 2, r.n do out[#out + 1] = Str(r[i]) end
	return #out > 0 and table.concat(out, ", ") or "(nothing)"
end

local function Get(fn, ...)
	if type(fn) ~= "function" then return nil end
	local ok, v = pcall(fn, ...)
	if ok then return v end
end

local function SpellName(spellID)
	if Secret(spellID) or not spellID then return "?" end
	local name = Get(C_Spell and C_Spell.GetSpellName, spellID)
	return name and not Secret(name) and name or "?"
end

-- ---------------------------------------------------------------------------
-- The record
-- ---------------------------------------------------------------------------

local function Line(fmt, ...)
	if not current then return end
	local lines = current.lines
	if #lines >= MAX_LINES then
		if #lines == MAX_LINES then lines[#lines + 1] = "... (more lines dropped)" end
		return
	end
	lines[#lines + 1] = string.format("%6.2f %s", GetTime() - t0, string.format(fmt, ...))
end

-- the apply's own debug lines (ns.Debug) while a record is open
function ns.LogLine(fmt, ...)
	if current then Line(fmt, ...) end
end

local function Listen(on)
	if on == listening then return end
	listening = on
	if on then
		for _, e in ipairs(EVENTS) do pcall(frame.RegisterEvent, frame, e) end
		for _, e in ipairs(UNIT_EVENTS) do pcall(frame.RegisterUnitEvent, frame, e, "player") end
	else
		frame:UnregisterAllEvents()
	end
end

-- The record is closed once its listening time is over. A timer looks, and so
-- does the first event after it, whichever comes first.
local function CloseIfDue()
	if current and not (closeAt and GetTime() >= closeAt) then return false end
	current, t0, closeAt = nil, nil, nil
	Listen(false)
	return true
end

local function CloseLater()
	local record = current
	local function look()
		if current ~= record then return end
		if not CloseIfDue() then C_Timer.After(math.max(0.1, closeAt - GetTime()), look) end
	end
	C_Timer.After(AFTER, look)
end

-- ---------------------------------------------------------------------------
-- What can be read before a request
-- ---------------------------------------------------------------------------

-- cooldown, charges and own aura of an ability, and whether any of them is running
local function SpellState(spellID)
	if not spellID or Secret(spellID) then return "?", false end
	local now, parts, busy = GetTime(), {}, false
	local ok, cd = pcall(C_Spell.GetSpellCooldown, spellID)
	if ok and type(cd) == "table" then
		local start, dur = Num(cd.startTime), Num(cd.duration)
		if Secret(cd.startTime) or Secret(cd.duration) then
			parts[#parts + 1] = "cooldown <secret>"; busy = true
		elseif start and dur and dur > 0 then
			parts[#parts + 1] = string.format("cooldown %.1f of %.1f left", start + dur - now, dur)
			if dur > GCD then busy = true end
		end
		if Secret(cd.isEnabled) then parts[#parts + 1] = "enabled <secret>"
		elseif cd.isEnabled == false then parts[#parts + 1] = "cooldown on hold"; busy = true end
	end
	ok, cd = pcall(C_Spell.GetSpellCharges, spellID)
	if ok and type(cd) == "table" then
		local cur, max, start, dur = cd.currentCharges, cd.maxCharges, cd.cooldownStartTime, cd.cooldownDuration
		if Secret(cur) or Secret(max) or Secret(start) or Secret(dur) then
			parts[#parts + 1] = "charges <secret>"; busy = true
		elseif Num(cur) and Num(max) then
			local text = string.format("charges %d/%d", cur, max)
			if cur < max then
				busy = true
				if Num(start) and Num(dur) and dur > 0 then
					text = text .. string.format(", next in %.1f of %.1f", start + dur - now, dur)
				end
			end
			parts[#parts + 1] = text
		end
	end
	if C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID then
		local okAura, aura = pcall(C_UnitAuras.GetPlayerAuraBySpellID, spellID)
		if okAura and aura ~= nil then
			busy = true
			if Secret(aura) or type(aura) ~= "table" then
				parts[#parts + 1] = "aura " .. Str(aura)
			else
				local expires = Num(aura.expirationTime)
				parts[#parts + 1] = (expires and expires > 0) and string.format("aura %.1f left", expires - now)
					or ("aura on" .. (Secret(aura.expirationTime) and " <secret>" or ""))
			end
		end
	end
	local text = string.format("%d %s", spellID, SpellName(spellID))
	if #parts > 0 then text = text .. " [" .. table.concat(parts, "; ") .. "]" end
	return text, busy
end

-- every ability in the spell book (and what overrides it) whose cooldown,
-- charges or aura is running
local function Recovering()
	local out, seen = {}, {}
	if not (C_SpellBook and C_SpellBook.GetNumSpellBookSkillLines) then return out end
	pcall(function()
		local bank = Enum.SpellBookSpellBank.Player
		for tab = 1, C_SpellBook.GetNumSpellBookSkillLines() do
			local line = C_SpellBook.GetSpellBookSkillLineInfo(tab)
			if line and not line.offSpecID then
				for i = line.itemIndexOffset + 1, line.itemIndexOffset + line.numSpellBookItems do
					local _, _, spellID = C_SpellBook.GetSpellBookItemType(i, bank)
					if spellID and not Secret(spellID) and not C_SpellBook.IsSpellBookItemPassive(i, bank) then
						for _, id in ipairs({ spellID, Get(C_Spell.GetOverrideSpell, spellID) }) do
							if not Secret(id) and not seen[id] then
								seen[id] = true
								local text, busy = SpellState(id)
								if busy and #out < MAX_SPELLS then out[#out + 1] = text end
							end
						end
					end
				end
			end
		end
	end)
	return out
end

local function Situation()
	local _, instanceType, difficultyID = GetInstanceInfo()
	local okCast, castName, _, _, _, _, _, _, _, castSpell = pcall(UnitCastingInfo, "player")
	Line("  situation: combat %s, resting %s, moving %s, dead %s, mounted %s, casting %s %s, instance %s/%s, key %s, match %s",
		Str(InCombatLockdown()), Returns(IsResting), Str(Get(GetUnitSpeed, "player")), Returns(UnitIsDeadOrGhost, "player"),
		Returns(IsMounted), okCast and Str(castName) or "?", okCast and Str(castSpell) or "",
		Str(instanceType), Str(difficultyID),
		Returns(C_ChallengeMode and C_ChallengeMode.IsChallengeModeActive),
		Returns(C_PvP and C_PvP.GetActiveMatchState))
	Line("  talent UI %s; spec UI %s; PvP talent UI %s",
		Returns(SI and SI.CanPlayerUseTalentUI), Returns(SI and SI.CanPlayerUseTalentSpecUI),
		Returns(SI and SI.CanPlayerUsePVPTalentUI))
end

local function ActiveConfig()
	return Get(C_ClassTalents and C_ClassTalents.GetActiveConfigID)
end

local function CanChange()
	local active = ActiveConfig()
	return string.format("CanChangeTalents %s; CanEditConfig(%s) %s; staged changes %s",
		Returns(C_ClassTalents and C_ClassTalents.CanChangeTalents), Str(active),
		Returns(C_Traits and C_Traits.CanEditConfig, active), Returns(C_Traits and C_Traits.ConfigHasStagedChanges, active))
end

-- what a config has on a node: { spell=, overrides=, subTree=, entry=, rank=, key= } or nil, and the node info
local function Pick(configID, nodeID)
	local ok, n = pcall(C_Traits.GetNodeInfo, configID, nodeID)
	if not ok or type(n) ~= "table" then return nil, nil end
	if n.subTreeID and n.subTreeActive == false then return nil, n end   -- a hero tree not chosen
	local e, rank = n.activeEntry, n.ranksPurchased
	if type(e) ~= "table" or not e.entryID then return nil, n end
	rank = math.max(Num(rank) or 0, Num(e.rank) or 0)
	if rank <= 0 then return nil, n end
	local pick = { entry = e.entryID, rank = rank }
	local okEntry, entry = pcall(C_Traits.GetEntryInfo, configID, e.entryID)
	if okEntry and type(entry) == "table" then
		pick.subTree = entry.subTreeID
		if entry.definitionID then
			local okDef, def = pcall(C_Traits.GetDefinitionInfo, entry.definitionID)
			if okDef and type(def) == "table" then pick.spell, pick.overrides = def.spellID, def.overriddenSpellID end
		end
	end
	-- entry IDs are compared by what they give: the spell, else the hero tree, else the entry
	pick.key = (pick.spell and ("s" .. pick.spell) or pick.subTree and ("t" .. pick.subTree) or ("e" .. pick.entry)) .. "r" .. rank
	return pick, n
end

local function Describe(pick, withState)
	if not pick then return "none" end
	if not pick.spell then
		return pick.subTree and ("hero tree " .. pick.subTree) or ("entry " .. pick.entry)
	end
	local text = withState and SpellState(pick.spell) or string.format("%d %s", pick.spell, SpellName(pick.spell))
	text = text .. " r" .. pick.rank
	if pick.overrides and pick.overrides ~= 0 then
		text = text .. " (replaces " .. (withState and SpellState(pick.overrides) or tostring(pick.overrides)) .. ")"
	end
	return text
end

local function TalentChecks(setup, first)
	local active = ActiveConfig()
	local okInfo, info = pcall(C_Traits.GetConfigInfo, setup.configID)
	Line("  talents: active config %s, target %s %s", Str(active), Str(setup.configID),
		okInfo and type(info) == "table" and Str(info.name) or "?")
	Line("  %s", CanChange())
	if not first then return end
	Line("  import active: %s", Returns(C_Traits and C_Traits.GenerateImportString, active))
	Line("  import target: %s", Returns(C_Traits and C_Traits.GenerateImportString, setup.configID))
	local okConfig, config = pcall(C_Traits.GetConfigInfo, active)
	local treeID = okConfig and type(config) == "table" and type(config.treeIDs) == "table" and config.treeIDs[1]
	local okNodes, nodes = pcall(C_Traits.GetTreeNodes, treeID)
	if not treeID or not okNodes or type(nodes) ~= "table" then
		Line("  nodes: unreadable (tree %s)", Str(treeID))
		return
	end
	local changed, targetRead = 0, false
	for _, nodeID in ipairs(nodes) do
		local from, n = Pick(active, nodeID)
		local to, tn = Pick(setup.configID, nodeID)
		if tn then targetRead = true end
		if (from and from.key) ~= (to and to.key) then
			changed = changed + 1
			if changed <= MAX_NODES then
				local flags = ""
				if n then
					flags = string.format(" {refund %s, purchase %s, available %s}",
						Str(n.canRefundRank), Str(n.canPurchaseRank), Str(n.isAvailable))
				end
				Line("  node %s: %s -> %s%s", Str(nodeID), Describe(from, true), Describe(to, false), flags)
			end
		end
	end
	Line("  %d nodes, %d differ%s", #nodes, changed, targetRead and "" or "; the target's nodes were unreadable")
end

local function PvpTalent(talentID)
	if not talentID then return "none" end
	local ok, info = pcall(SI.GetPvpTalentInfo, talentID)
	if not ok or type(info) ~= "table" then return Str(talentID) .. " (no info)" end
	local text = Str(talentID) .. " " .. Str(info.name)
	if info.spellID then text = text .. " spell " .. SpellState(info.spellID) end
	local flags = {}
	for _, k in ipairs({ "selected", "available", "unlocked", "known", "grantedByAura", "dependenciesUnmet", "dependenciesUnmetReason" }) do
		if info[k] ~= nil then flags[#flags + 1] = k .. " " .. Str(info[k]) end
	end
	if #flags > 0 then text = text .. " {" .. table.concat(flags, ", ") .. "}" end
	return text
end

local function PvpChecks(setup)
	for _, change in ipairs(ns.PvpPlan(setup.pvp)) do
		local ok, slot = pcall(SI.GetPvpTalentSlotInfo, change.slot)
		local outgoing = ok and type(slot) == "table" and slot.selectedTalentID or nil
		Line("  PvP slot %d: %s -> %s", change.slot, PvpTalent(outgoing), PvpTalent(change.id))
	end
end

-- ---------------------------------------------------------------------------
-- Calls from the apply (Loadouts.lua)
-- ---------------------------------------------------------------------------

function ns.LogApplyStart(setup, description)
	if current and not current.outcome then current.outcome = "replaced by a new apply" end
	current, t0, closeAt = nil, nil, nil
	if not ns.ApplyLogging() then return Listen(false) end
	ns.db.applyLog = ns.db.applyLog or {}
	local log = ns.db.applyLog
	local _, build = GetBuildInfo()
	local spec = ns.GetSpecByID(ns.GetCurrentSpecID())
	current = {
		at = date("%Y-%m-%d %H:%M:%S"), build = build, char = UnitName("player"),
		spec = spec and spec.name, target = description, lines = {},
	}
	t0 = GetTime()
	log[#log + 1] = current
	while #log > MAX_APPLIES do table.remove(log, 1) end
	if not frame then
		frame = CreateFrame("Frame")
		frame:SetScript("OnEvent", function(_, event, ...) ns.LogEvent(event, ...) end)
	end
	Listen(true)
	Line("apply: %s%s", description, setup.force and " (forced)" or "")
end

-- name: "spec" | "talents" | "gear" | "pvp"; try counts from 1
function ns.LogAsk(name, try, setup)
	if not current then return end
	Line("ask %s, try %d", name, try)
	Situation()
	if name == "talents" then
		TalentChecks(setup, try == 1)
	elseif name == "pvp" then
		PvpChecks(setup)
	elseif name == "spec" then
		Line("  spec: %s -> %s", Str(ns.GetCurrentSpecID()), Str(setup.specID))
	end
	if name ~= "gear" then
		local list = Recovering()
		Line("  recovering: %s", #list > 0 and table.concat(list, " | ") or "nothing")
	end
end

-- what a request returned: pcall's ok, then the function's returns
function ns.LogReturns(label, ...)
	if not current then return end
	local out = {}
	for i = 1, select("#", ...) do out[#out + 1] = Str((select(i, ...))) end
	Line("  %s -> %s", label, table.concat(out, ", "))
end

function ns.LogApplyEnd(outcome)
	if not current or closeAt then return end
	current.outcome = outcome or "ended without a message"
	Line("end: %s", current.outcome)
	closeAt = GetTime() + AFTER
	CloseLater()
end

function ns.LogEvent(event, ...)
	if CloseIfDue() then return end
	if event == "UI_ERROR_MESSAGE" or event == "UI_INFO_MESSAGE" then
		local messageType, message = ...
		Line("%s %s %s %s", event, Str(messageType), Returns(GetGameMessageInfo, messageType), Str(message))
		if event == "UI_ERROR_MESSAGE" then Line("  now: %s", CanChange()) end
	elseif event:find("^UNIT_SPELLCAST_") then
		local spellID = select(event == "UNIT_SPELLCAST_SENT" and 4 or 3, ...)
		Line("%s %s %s", event, Str(spellID), SpellName(spellID))
	elseif event == "CONFIG_COMMIT_FAILED" then
		Line("%s %s", event, Str((...)))
		Line("  now: %s", CanChange())
	else
		local out = {}
		for i = 1, select("#", ...) do out[#out + 1] = Str((select(i, ...))) end
		Line("%s %s", event, table.concat(out, ", "))
	end
end

-- ---------------------------------------------------------------------------
-- /ckloadout log | clear | debug [on | off]
-- ---------------------------------------------------------------------------

local SHOWN, SHOWN_LINES = 5, 15
local KEY_LINE = { "UI_ERROR_MESSAGE", "CHAT_MSG_SYSTEM", "CONFIG_COMMIT_FAILED", "LoadConfig", "RollbackConfig",
	"LearnPvpTalent", "held up", "end:" }

SLASH_CKLOADOUT1 = "/ckloadout"
SlashCmdList.CKLOADOUT = function(msg)
	msg = strtrim(msg or ""):lower()
	local log = ns.db and ns.db.applyLog or {}
	if msg == "log" then
		for i = math.max(1, #log - SHOWN + 1), #log do
			local e = log[i]
			print(string.format("  %s %s: %s -> %s", e.at or "?", e.spec or "?", e.target or "?", e.outcome or "(still open)"))
		end
		-- the last apply's key lines: what was asked, what the game answered, how it ended
		local last, shown = log[#log], 0
		for _, l in ipairs(last and last.lines or {}) do
			for _, key in ipairs(KEY_LINE) do
				if l:find(key, 1, true) and shown < SHOWN_LINES then
					print("    " .. l)
					shown = shown + 1
					break
				end
			end
		end
		CK.Msg("Loadout: %d applies logged, the last %d shown; /reload writes them to the saved variables%s",
			#log, math.min(#log, SHOWN), ns.ApplyLogging() and "" or "; logging is off (/ckloadout debug on)")
	elseif msg == "clear" then
		if ns.db then ns.db.applyLog = {} end
		CK.Msg("Loadout: apply log cleared")
	elseif msg == "debug" or msg == "debug on" or msg == "debug off" then
		if ns.db then
			if msg == "debug" then ns.db.debugLog = not ns.ApplyLogging()
			else ns.db.debugLog = msg == "debug on" end
		end
		CK.Msg("Loadout: apply log %s", ns.ApplyLogging() and "on" or "off")
	else
		CK.Msg("Loadout: /ckloadout log | clear | debug [on | off]")
	end
end
