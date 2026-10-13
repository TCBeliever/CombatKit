-- ===========================================================================
-- CombatKit Lab: experiments, run in game, on what an addon can observe about
-- an aura it is not allowed to read (another player's, in arena since 12.1).
-- Everything printed is also kept in CombatKitLabDB, written on /reload, so a
-- session can be read from the saved variables afterwards.
--
-- The question that decides the PvP module's design: when the game draws an
-- aura into a slot the addon asked for, which signals reach the addon as plain
-- events (OnShow, OnHide, a size change, a status bar value) the moment the
-- aura appears, without the addon polling and without reading a secret value?
--
-- /cklab                       this list
-- /cklab state                 secrecy regime, combat, instance, match state, who is around
-- /cklab api                   which APIs exist; every method of an aura container, slot button, duration object
-- /cklab watch <unit> <id...>  draw the unit's aura(s) in one slot and log every signal (add "harm" for a debuff)
-- /cklab filter <id...>        change the slot's spell filter while watching
-- /cklab direct <unit> <id>    what the direct aura reads answer for that unit (plain, secret, nil)
-- /cklab loc <unit>            which fields of the unit's loss-of-control data are readable
-- /cklab report                counts of every signal seen so far, saved as one run
-- /cklab show | hide           make the slot visible on screen (top centre) or not
-- /cklab quiet | loud          stop or resume printing every signal as it happens
-- /cklab stop                  end the watch
-- ===========================================================================

local ADDON = ...
CombatKitLabDB = CombatKitLabDB or {}

local Lab = {}
local run   -- the watch in progress

local function clock() return (GetTimePreciseSec or GetTime)() end

local function plain(v)
	return type(canaccessvalue) ~= "function" or canaccessvalue(v) == true
end

-- a value as text, never touching a secret one
local function show(v)
	if type(issecretvalue) == "function" and issecretvalue(v) then return "<secret>" end
	if not plain(v) then return "<inaccessible>" end
	if v == nil then return "nil" end
	local t = type(v)
	if t == "string" or t == "number" or t == "boolean" then return tostring(v) end
	return t
end

local function say(fmt, ...)
	print("|cffffcc66cklab|r " .. (select("#", ...) > 0 and string.format(fmt, ...) or tostring(fmt)))
end

-- function names an object offers: its own fields and its widget methods
local function methodsOf(obj)
	local names, seen = {}, {}
	local function take(t)
		if type(t) ~= "table" then return end
		for k, v in pairs(t) do
			if type(k) == "string" and type(v) == "function" and not seen[k] then
				seen[k] = true
				names[#names + 1] = k
			end
		end
	end
	if type(obj) == "table" then take(obj) end
	local ok, mt = pcall(getmetatable, obj)
	if ok and type(mt) == "table" then take(mt.__index) end
	table.sort(names)
	return names
end

-- ---------------------------------------------------------------------------
-- The timeline of a watch
-- ---------------------------------------------------------------------------

local function mark(tag, detail)
	if not run then return end
	local now = clock()
	local line = string.format("%8.3f %-22s %s", now - run.started, tag, detail or "")
	run.lines[#run.lines + 1] = line
	if run.verbose then print("  " .. line) end
	return now
end

local function signal(name, detail)
	if not run then return end
	run.signals[name] = (run.signals[name] or 0) + 1
	local now = mark(name, detail)
	-- how long after the aura really appeared (known for the player) the signal came
	if name:find("OnShow") or name:find("OnValueChanged") then
		if run.lastTruthUp and now - run.lastTruthUp < 3 then
			mark("latency", string.format("%s came %.3f s after the direct read said up", name, now - run.lastTruthUp))
		end
		run.lastSignalUp = run.lastSignalUp or now
	end
end

-- ---------------------------------------------------------------------------
-- Frames
-- ---------------------------------------------------------------------------

function Lab.Root()
	if Lab.root then return Lab.root end
	local f = CreateFrame("Frame", "CombatKitLabRoot", UIParent)
	f:SetSize(64, 64)
	f:SetPoint("TOP", UIParent, "TOP", 0, -120)
	f:EnableMouse(false)
	f:Show()
	Lab.root = f
	return f
end

function Lab.NewContainer(unit)
	if C_AddOns and not C_AddOns.IsAddOnLoaded("Blizzard_AuraContainer") then
		pcall(C_AddOns.LoadAddOn, "Blizzard_AuraContainer")
	end
	local ok, c = pcall(CreateFrame, "AuraContainer", nil, Lab.Root(), "CustomAuraContainerTemplate")
	if not ok or not c then
		say("CreateFrame AuraContainer failed: %s", tostring(c))
		return nil
	end
	c:SetSize(40, 40)
	c:SetPoint("CENTER")
	local okU, err = pcall(c.SetUnit, c, unit)
	if not okU then say("SetUnit(%s) failed: %s", unit, tostring(err)) end
	pcall(c.Show, c)
	return c
end

local function hook(frame, label, script)
	local ok, err = pcall(frame.HookScript, frame, script, function(_, a, b)
		local extra = ""
		if script == "OnValueChanged" then extra = "value " .. show(a)
		elseif script == "OnMinMaxChanged" then extra = "min " .. show(a) .. " max " .. show(b)
		elseif script == "OnAttributeChanged" then extra = tostring(a) .. " = " .. show(b)
		elseif script == "OnSizeChanged" then extra = string.format("%s x %s", show(a), show(b)) end
		signal(label .. "." .. script, extra)
	end)
	if not ok then mark("hook", label .. "." .. script .. " not hookable: " .. tostring(err)) end
end

-- the game hands the slot's button here (when, exactly, is one of the answers)
function Lab.InitButton(slot, button)
	slot.button = button
	mark("init", "initializeFrame called; button type " .. tostring(button:GetObjectType()))
	for _, s in ipairs({ "OnShow", "OnHide", "OnSizeChanged", "OnAttributeChanged" }) do hook(button, "button", s) end

	-- a status bar bound as the slot's duration bar: the game drives its value
	local bar = CreateFrame("StatusBar", nil, button)
	bar:SetSize(1, 1)
	bar:SetPoint("BOTTOMLEFT")
	bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
	slot.bar = bar
	local ok, err = pcall(button.SetDurationBar, button, bar)
	mark("bar", ok and "SetDurationBar accepted" or ("SetDurationBar failed: " .. tostring(err)))
	for _, s in ipairs({ "OnShow", "OnHide", "OnValueChanged", "OnMinMaxChanged" }) do hook(bar, "bar", s) end

	-- the Duration object behind that bar, and what it offers
	local okD, d = pcall(bar.GetTimerDuration, bar)
	if okD and d ~= nil and plain(d) then
		slot.duration = d
		local names = methodsOf(d)
		run.durationMethods = names
		mark("duration", "GetTimerDuration gave a " .. type(d) .. "; methods: " .. table.concat(names, " "))
	else
		mark("duration", "GetTimerDuration: " .. (okD and show(d) or ("failed: " .. tostring(d))))
	end

	-- a Cooldown bound once to that Duration, parented away from the button so
	-- its show and hide reflect the Duration alone: does it follow the aura by itself?
	if slot.duration ~= nil then
		local cd = CreateFrame("Cooldown", nil, Lab.Root(), "CooldownFrameTemplate")
		cd:SetSize(40, 40)
		cd:SetPoint("CENTER")
		cd:SetDrawEdge(false)
		cd:SetHideCountdownNumbers(false)
		for _, s in ipairs({ "OnShow", "OnHide", "OnCooldownDone" }) do hook(cd, "cooldown", s) end
		local okC, errC = pcall(cd.SetCooldownFromDurationObject, cd, slot.duration, true)
		mark("cooldown", okC and "bound to the Duration once, never fed again" or ("SetCooldownFromDurationObject failed: " .. tostring(errC)))
		slot.cd = cd
	end

	run.buttonMethods = methodsOf(button)
	mark("button", #run.buttonMethods .. " methods: " .. table.concat(run.buttonMethods, " "))
end

-- ---------------------------------------------------------------------------
-- Reads polled every 0.2 s: which are plain, and which change with the aura
-- ---------------------------------------------------------------------------

local READS = {
	{ "button:IsShown", function(s) return s.button:IsShown() end },
	{ "button:IsVisible", function(s) return s.button:IsVisible() end },
	{ "button:GetAlpha", function(s) return s.button:GetAlpha() end },
	{ "bar:IsShown", function(s) return s.bar:IsShown() end },
	{ "bar:GetValue", function(s) return s.bar:GetValue() end },
	{ "bar:GetMinMaxValues.max", function(s) return select(2, s.bar:GetMinMaxValues()) end },
	{ "cooldown:IsShown", function(s) return s.cd and s.cd:IsShown() end },
	{ "cooldown:GetCooldownDuration", function(s) return s.cd and s.cd:GetCooldownDuration() end },
	{ "cooldown:GetCooldownTimes.start", function(s) return s.cd and (s.cd:GetCooldownTimes()) end },
}
-- Duration object methods worth trying by name, if the object has them
local DURATION_READS = { "GetRemainingDuration", "GetTotalDuration", "GetDuration", "GetStartTime", "GetEndTime",
	"GetElapsed", "IsZero", "IsActive", "HasDuration", "GetPercent", "GetProgress" }

function Lab.Regime()
	local secret
	if C_Secrets and C_Secrets.ShouldAurasBeSecret then
		local ok, v = pcall(C_Secrets.ShouldAurasBeSecret)
		secret = ok and v or "error"
	end
	return string.format("auras secret=%s combat=%s", show(secret), tostring(InCombatLockdown()))
end

function Lab.Poll()
	if not run or not run.slot or not run.slot.button then return end
	local s = run.slot
	for _, r in ipairs(READS) do
		local ok, v = pcall(r[2], s)
		local text = ok and show(v) or ("error: " .. tostring(v):sub(1, 60))
		if run.reads[r[1]] ~= text then
			run.reads[r[1]] = text
			mark("read", r[1] .. " -> " .. text)
		end
	end
	if s.duration ~= nil then
		for _, name in ipairs(DURATION_READS) do
			local fn = s.duration[name]
			if type(fn) == "function" then
				local ok, v = pcall(fn, s.duration)
				local text = ok and show(v) or ("error: " .. tostring(v):sub(1, 60))
				local key = "duration:" .. name
				if run.reads[key] ~= text then
					run.reads[key] = text
					mark("read", key .. " -> " .. text)
				end
			end
		end
	end
	local regime = Lab.Regime()
	if run.regime ~= regime then
		run.regime = regime
		mark("regime", regime)
	end
end

-- the direct read of the same aura: plain for the player, maybe for a party
-- member outside arena; the yardstick the slot's signals are measured against
function Lab.Truth(unit)
	if not run then return end
	for _, id in ipairs(run.ids) do
		local ok, data
		if unit == "player" and C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID then
			ok, data = pcall(C_UnitAuras.GetPlayerAuraBySpellID, id)
		elseif C_UnitAuras and C_UnitAuras.GetAuraDataBySpellID then
			ok, data = pcall(C_UnitAuras.GetAuraDataBySpellID, unit, id, run.filter)
		end
		local state
		if not ok then state = "error" elseif not plain(data) then state = "secret"
		elseif data == nil then state = "down" else state = "up" end
		if run.truth[id] ~= state then
			run.truth[id] = state
			local now = mark("direct read", id .. " " .. state)
			if state == "up" then
				run.lastTruthUp = now
				if run.lastSignalUp and now - run.lastSignalUp < 3 then
					mark("latency", string.format("the direct read said up %.3f s after the first signal", now - run.lastSignalUp))
				end
			else
				run.lastSignalUp = nil
			end
		end
	end
end

-- ---------------------------------------------------------------------------
-- Commands
-- ---------------------------------------------------------------------------

function Lab.Watch(unit, ids, filter)
	Lab.Stop(true)
	run = { unit = unit, ids = ids, filter = filter, started = clock(), lines = {}, signals = {}, reads = {}, truth = {},
		verbose = true, at = date("%Y-%m-%d %H:%M:%S") }
	CombatKitLabDB.current = run
	local c = Lab.NewContainer(unit)
	if not c then run = nil return end
	run.container = c
	for _, s in ipairs({ "OnShow", "OnHide", "OnSizeChanged" }) do hook(c, "container", s) end
	run.containerMethods = methodsOf(c)
	local set = {}
	for _, id in ipairs(ids) do set[id] = true end
	local slot = { key = "lab" }
	run.slot = slot
	mark("regime", Lab.Regime())
	local ok, err = pcall(c.AddAuraSlot, c, "lab", filter, {
		candidateFilters = { includeSpellIDs = set },
		initializeFrame = function(button) Lab.InitButton(slot, button) end,
	})
	mark("slot", ok and ("AddAuraSlot accepted for " .. unit .. " " .. filter .. " ids " .. table.concat(ids, ","))
		or ("AddAuraSlot failed: " .. tostring(err)))
	local ev = CreateFrame("Frame")
	run.events = ev
	pcall(ev.RegisterUnitEvent, ev, "UNIT_AURA", unit)
	ev:RegisterEvent("PLAYER_REGEN_DISABLED")
	ev:RegisterEvent("PLAYER_REGEN_ENABLED")
	ev:SetScript("OnEvent", function(_, event, u)
		if event == "UNIT_AURA" then
			signal("event.UNIT_AURA", u)
			Lab.Truth(u)
		else
			mark("event", event)
		end
	end)
	run.ticker = C_Timer.NewTicker(0.2, Lab.Poll)
	Lab.Truth(unit)
	say("watching %s for %s (%s). Cast it, let it fade, cast again. /cklab report when done.", unit, table.concat(ids, ","), filter)
end

function Lab.Filter(ids)
	if not run or not run.container then say("nothing is being watched") return end
	local set = {}
	for _, id in ipairs(ids) do set[id] = true end
	local ok, err = pcall(run.container.SetAuraSlotCandidateFilters, run.container, "lab", { includeSpellIDs = set })
	run.ids = ids
	run.truth = {}
	mark("filter", ok and ("changed to " .. table.concat(ids, ",")) or ("SetAuraSlotCandidateFilters failed: " .. tostring(err)))
	Lab.Truth(run.unit)
end

function Lab.Report()
	if not run then say("nothing is being watched") return end
	say("run on %s, %s, %.0f s", run.unit, table.concat(run.ids, ","), clock() - run.started)
	local names = {}
	for name in pairs(run.signals) do names[#names + 1] = name end
	table.sort(names)
	say("signals:")
	for _, name in ipairs(names) do print(string.format("  %-28s %d", name, run.signals[name])) end
	say("reads, last value:")
	local keys = {}
	for k in pairs(run.reads) do keys[#keys + 1] = k end
	table.sort(keys)
	for _, k in ipairs(keys) do print(string.format("  %-34s %s", k, run.reads[k])) end
	say("%d timeline lines kept; saved on /reload", #run.lines)
	CombatKitLabDB.runs = CombatKitLabDB.runs or {}
	CombatKitLabDB.runs[#CombatKitLabDB.runs + 1] = {
		at = run.at, unit = run.unit, ids = run.ids, filter = run.filter, signals = run.signals, reads = run.reads,
		lines = run.lines, buttonMethods = run.buttonMethods, containerMethods = run.containerMethods,
		durationMethods = run.durationMethods,
	}
end

function Lab.Stop(silent)
	if not run then return end
	if run.ticker then run.ticker:Cancel() end
	if run.events then run.events:UnregisterAllEvents() end
	if run.container then
		pcall(run.container.SetAuraSlotCandidateFilters, run.container, "lab", { includeSpellIDs = {} })
		pcall(run.container.Hide, run.container)
	end
	if run.slot and run.slot.cd then run.slot.cd:Hide() end
	-- only plain data stays in the saved variables
	CombatKitLabDB.current = { at = run.at, unit = run.unit, ids = run.ids, lines = run.lines, signals = run.signals, reads = run.reads }
	if not silent then say("stopped; the timeline stays in CombatKitLabDB.current until the next watch") end
	run = nil
end

function Lab.State()
	say(Lab.Regime())
	local inInstance, kind = IsInInstance()
	local state
	if C_PvP and C_PvP.GetActiveMatchState then
		local ok, v = pcall(C_PvP.GetActiveMatchState)
		state = ok and v or "error"
	end
	say("instance %s %s, match state %s", tostring(inInstance), tostring(kind), show(state))
	for _, unit in ipairs({ "player", "party1", "party2", "arena1", "arena2", "arena3", "target" }) do
		if UnitExists(unit) then
			local _, class = UnitClass(unit)
			say("  %-7s %s %s", unit, show(class), show(UnitName(unit)))
		end
	end
end

function Lab.Api()
	local function has(name, v) print(string.format("  %-46s %s", name, v and "yes" or "no")) end
	say("functions:")
	has("canaccessvalue / issecretvalue / canaccesstable", type(canaccessvalue) == "function" and type(issecretvalue) == "function" and type(canaccesstable) == "function")
	has("C_Secrets.ShouldAurasBeSecret", C_Secrets and C_Secrets.ShouldAurasBeSecret)
	has("C_DurationUtil.CreateDuration", C_DurationUtil and C_DurationUtil.CreateDuration)
	has("C_UnitAuras.GetAuraDataBySpellID", C_UnitAuras and C_UnitAuras.GetAuraDataBySpellID)
	has("C_UnitAuras.GetPlayerAuraBySpellID", C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID)
	has("C_UnitAuras.GetAuraSlots", C_UnitAuras and C_UnitAuras.GetAuraSlots)
	has("C_LossOfControl.GetActiveLossOfControlDataByUnit", C_LossOfControl and C_LossOfControl.GetActiveLossOfControlDataByUnit)
	has("C_PvP.GetActiveMatchState", C_PvP and C_PvP.GetActiveMatchState)
	has("Blizzard_AuraContainer loaded", C_AddOns.IsAddOnLoaded("Blizzard_AuraContainer"))
	local c = Lab.NewContainer("player")
	local containerMethods
	if c then
		containerMethods = methodsOf(c)
		say("aura container, %d methods:", #containerMethods)
		print("  " .. table.concat(containerMethods, " "))
		c:Hide()
	end
	local found = {}
	for k, v in pairs(_G) do
		if type(k) == "string" and (k:find("AuraContainer") or k:find("AuraSlot") or k:find("AuraButton") or k:find("Duration")) then
			found[#found + 1] = k .. ":" .. type(v)
		end
	end
	table.sort(found)
	say("globals that look related (%d):", #found)
	print("  " .. table.concat(found, " "))
	local durationMethods
	if C_DurationUtil and C_DurationUtil.CreateDuration then
		local ok, d = pcall(C_DurationUtil.CreateDuration)
		if ok and d ~= nil then
			durationMethods = methodsOf(d)
			say("a fresh Duration object (%s), %d methods:", type(d), #durationMethods)
			print("  " .. table.concat(durationMethods, " "))
		end
	end
	CombatKitLabDB.api = { at = date("%Y-%m-%d %H:%M:%S"), container = containerMethods, globals = found, duration = durationMethods }
end

function Lab.Direct(unit, id)
	local function try(label, fn, ...)
		local ok, v = pcall(fn, ...)
		if not ok then say("  %-40s error: %s", label, tostring(v):sub(1, 80)) return end
		local text = show(v)
		if type(v) == "table" and plain(v) then
			local fields = {}
			for _, f in ipairs({ "name", "spellId", "duration", "expirationTime", "applications", "sourceUnit", "auraInstanceID" }) do
				fields[#fields + 1] = f .. "=" .. show(v[f])
			end
			text = "table: " .. table.concat(fields, " ")
		end
		say("  %-40s %s", label, text)
	end
	say("direct reads of %d on %s (%s):", id, unit, Lab.Regime())
	if C_UnitAuras then
		if C_UnitAuras.GetAuraDataBySpellID then
			try("GetAuraDataBySpellID HELPFUL", C_UnitAuras.GetAuraDataBySpellID, unit, id, "HELPFUL")
			try("GetAuraDataBySpellID HARMFUL", C_UnitAuras.GetAuraDataBySpellID, unit, id, "HARMFUL")
		end
		if C_UnitAuras.GetPlayerAuraBySpellID and unit == "player" then try("GetPlayerAuraBySpellID", C_UnitAuras.GetPlayerAuraBySpellID, id) end
		if C_UnitAuras.GetAuraSlots then try("GetAuraSlots HELPFUL (continuation)", C_UnitAuras.GetAuraSlots, unit, "HELPFUL") end
		if C_UnitAuras.GetBuffDataByIndex then try("GetBuffDataByIndex 1", C_UnitAuras.GetBuffDataByIndex, unit, 1) end
	end
	if AuraUtil and AuraUtil.FindAuraByName and C_Spell and C_Spell.GetSpellName then
		local name = C_Spell.GetSpellName(id)
		if name then try("AuraUtil.FindAuraByName", AuraUtil.FindAuraByName, name, unit) end
	end
end

function Lab.Loc(unit)
	local api = C_LossOfControl
	if not (api and api.GetActiveLossOfControlDataCountByUnit) then say("no loss-of-control API") return end
	local ok, count = pcall(api.GetActiveLossOfControlDataCountByUnit, unit)
	say("loss of control on %s: count %s", unit, ok and show(count) or ("error " .. tostring(count)))
	if not ok or not plain(count) or type(count) ~= "number" then return end
	for i = 1, count do
		local okD, d = pcall(api.GetActiveLossOfControlDataByUnit, unit, i)
		if not okD or type(d) ~= "table" then
			say("  %d: %s", i, okD and show(d) or ("error " .. tostring(d)))
		else
			local parts = {}
			for _, f in ipairs({ "locType", "spellID", "displayType", "priority", "startTime", "timeRemaining", "duration", "lockoutSchool", "displayText", "iconTexture" }) do
				parts[#parts + 1] = f .. "=" .. show(d[f])
			end
			say("  %d: %s", i, table.concat(parts, " "))
		end
	end
	if unit ~= "player" then say("(for comparison, /cklab loc player shows the same fields for yourself)") end
end

local HELP = {
	"/cklab state | api | watch <unit> <id...> [harm] | filter <id...> | direct <unit> <id> | loc <unit>",
	"/cklab report | show | hide | quiet | loud | stop",
	"first: /cklab watch player <a buff you can cast on yourself>, cast it, wait, cast again, /cklab report",
	"then the same on party1 in a group outside arena, then on party1 in arena, then an enemy debuff on arena1 with harm",
}

SLASH_COMBATKITLAB1 = "/cklab"
SlashCmdList.COMBATKITLAB = function(msg)
	msg = strtrim(msg or "")
	local args = {}
	for word in msg:gmatch("%S+") do args[#args + 1] = word end
	local cmd = (args[1] or ""):lower()
	if cmd == "state" then Lab.State()
	elseif cmd == "api" then Lab.Api()
	elseif cmd == "watch" then
		local unit, ids, harm = args[2], {}, false
		for i = 3, #args do
			if args[i]:lower() == "harm" then harm = true else ids[#ids + 1] = tonumber(args[i]) end
		end
		if not unit or #ids == 0 then say("usage: /cklab watch <unit> <spellID...> [harm]") return end
		Lab.Watch(unit, ids, harm and "HARMFUL|INCLUDE_NAME_PLATE_ONLY" or "HELPFUL")
	elseif cmd == "filter" then
		local ids = {}
		for i = 2, #args do ids[#ids + 1] = tonumber(args[i]) end
		Lab.Filter(ids)
	elseif cmd == "direct" then
		if not args[2] or not tonumber(args[3]) then say("usage: /cklab direct <unit> <spellID>") return end
		Lab.Direct(args[2], tonumber(args[3]))
	elseif cmd == "loc" then Lab.Loc(args[2] or "player")
	elseif cmd == "report" then Lab.Report()
	elseif cmd == "show" then Lab.Root():SetAlpha(1)
	elseif cmd == "hide" then Lab.Root():SetAlpha(0)
	elseif cmd == "quiet" then if run then run.verbose = false end
	elseif cmd == "loud" then if run then run.verbose = true end
	elseif cmd == "stop" then Lab.Stop()
	else
		for _, line in ipairs(HELP) do say(line) end
	end
end
