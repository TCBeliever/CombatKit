local ADDON, ns = ...

-- ===========================================================================
-- Detection, the only part that touches the game's aura machinery.
--
-- Another player's auras are secret in an arena: nothing about them can be
-- read, compared or computed. What the game does allow is drawing them. An
-- aura container (Blizzard_AuraContainer) bound to a unit takes slots, each
-- told which spell IDs it may draw; the game assigns the matching aura to the
-- slot's button and keeps a Duration object in step with it. Every value in
-- there is secret, and in an arena the button and its children cannot even be
-- touched; but a Cooldown frame of our own, outside the button, fed that
-- Duration with SetCooldownFromDurationObject(duration, true) hides while
-- the Duration is zero and shows while it is not, and only its cooldown
-- aspect is made secret, not whether it is shown. So its OnShow is "the buff
-- appeared", its OnHide "the buff is gone" and its OnCooldownDone "the buff
-- ran its full course", all plain, all one frame behind the game. That is
-- the whole mechanism; AuraLab (a separate development addon) measured it on
-- 12.1 in the open world, in combat and in arena matches. The technique of
-- detecting a secret aura through what the game draws of it was first used by
-- AsIntendedCDs; this is an independent design of it.
--
-- One slot per (unit, spell), kept for the session, filters changed only when
-- the roster changes; the probes are fed once per frame from the root's
-- OnUpdate. The root sits under WorldFrame so hiding the UI never stops the
-- containers from updating. An edge in the frame right after our own filter
-- change, or right after a roster change, is reported as `initial`: the buff
-- was already there as we began to look.
-- ===========================================================================

local Backend = {}
ns.Backend = Backend

local root
local containers = {}   -- unit -> { unit, frame, slots = { [spellID] = slot }, failed }
local callbacks
local frameNo = 0
local NONE = { [1] = true }        -- a filter that matches nothing
local SETTLE_FRAMES = 2            -- edges this soon after our own change are the state we found, not an event
local SETTLE_SECONDS = 0.1

local function Root()
	if root then return root end
	root = CreateFrame("Frame", "CombatKitArenaDetect", WorldFrame or UIParent)
	root:SetSize(1, 1)
	root:SetPoint("BOTTOMLEFT")
	root:SetAlpha(0)
	root:SetScript("OnUpdate", function()
		frameNo = frameNo + 1
		Backend.Feed()
	end)
	return root
end

function Backend.FrameNo() return frameNo end

local function Container(unit)
	local c = containers[unit]
	if c then return c end
	if C_AddOns and C_AddOns.IsAddOnLoaded and not C_AddOns.IsAddOnLoaded("Blizzard_AuraContainer") then
		pcall(C_AddOns.LoadAddOn, "Blizzard_AuraContainer")
	end
	local parent = Root()
	local ok, frame = pcall(CreateFrame, "AuraContainer", nil, parent, "CustomAuraContainerTemplate")
	if not ok or not frame then
		containers[unit] = { unit = unit, slots = {}, failed = tostring(frame) }
		return containers[unit]
	end
	frame:SetSize(8, 8)
	frame:SetPoint("BOTTOMLEFT")
	pcall(frame.SetUnit, frame, unit)
	pcall(frame.Show, frame)
	c = { unit = unit, frame = frame, slots = {} }
	containers[unit] = c
	return c
end

local function Filter(def)
	return { includeSpellIDs = { [def.aura] = true, [def.id] = true }, maxDuration = 600 }
end

local function Touch(slot)
	slot.changedFrame, slot.changedAt = frameNo, GetTime()
end

local function Edge(c, slot, what)
	if not callbacks or not slot.watching then return end
	local t = GetTime()
	local settling = frameNo <= (slot.changedFrame or 0) + SETTLE_FRAMES or t - (slot.changedAt or 0) < SETTLE_SECONDS
	if what == "shown" then
		callbacks.Shown(c.unit, slot.def.id, t, settling)
	elseif what == "hidden" then
		if not settling then callbacks.Hidden(c.unit, slot.def.id, t) end
	else
		callbacks.Expired(c.unit, slot.def.id, t)
	end
end

-- the game hands the slot's button over from inside AddAuraSlot; nothing is
-- ever hooked on the button (its visibility is set with a secret value, and a
-- handler there makes the game refuse), only our own frames get handlers
function Backend.InitSlot(c, slot, button)
	pcall(button.SetAllPoints, button, c.frame)
	local bar = CreateFrame("StatusBar", nil, button)
	bar:SetSize(1, 1)
	bar:SetPoint("BOTTOMLEFT")
	local okBar = pcall(button.SetDurationBar, button, bar, {})
	local okD, handle = pcall(bar.GetTimerDuration, bar)
	if okBar and okD and handle ~= nil then slot.handle = handle end

	local parent = Root()
	local probe = CreateFrame("Cooldown", nil, parent, "CooldownFrameTemplate")
	probe:SetSize(1, 1)
	probe:SetPoint("BOTTOMLEFT")
	pcall(probe.SetHideCountdownNumbers, probe, true)
	pcall(probe.SetDrawEdge, probe, false)
	pcall(probe.SetDrawSwipe, probe, false)
	pcall(probe.SetDrawBling, probe, false)
	for script, what in pairs({ OnShow = "shown", OnHide = "hidden", OnCooldownDone = "expired" }) do
		local ok = pcall(probe.HookScript, probe, script, function() Edge(c, slot, what) end)
		if not ok then slot.failed = "cannot hook " .. script end
	end
	slot.probe = probe
end

local function Slot(c, def)
	local slot = c.slots[def.id]
	if slot then return slot end
	slot = { def = def }
	c.slots[def.id] = slot
	if not c.frame then slot.failed = c.failed return slot end
	local ok, err = pcall(c.frame.AddAuraSlot, c.frame, tostring(def.id), "HELPFUL", {
		candidateFilters = Filter(def),
		initializeFrame = function(button) Backend.InitSlot(c, slot, button) end,
	})
	if not ok then
		slot.failed = tostring(err)
		if not tostring(err):find("already exists", 1, true) then c.slots[def.id] = nil end   -- try again later
	end
	if not slot.handle and not slot.failed then slot.failed = "no duration handle" end
	return slot
end

local function SetFilter(c, slot, filters)
	if not c.frame then return false end
	return pcall(c.frame.SetAuraSlotCandidateFilters, c.frame, tostring(slot.def.id), filters)
end

-- Draw these spells for this unit, and nothing else. `roster` says the unit
-- may have changed hands, so whatever is up now is the state we found.
function Backend.SetWatch(unit, defs, roster)
	local c = Container(unit)
	local want = {}
	for _, def in ipairs(defs) do want[def.id] = def end
	for id, slot in pairs(c.slots) do
		if not want[id] and slot.watching then
			slot.watching = false
			Touch(slot)
			SetFilter(c, slot, { includeSpellIDs = NONE, maxDuration = 600 })
		end
	end
	for id, def in pairs(want) do
		local slot = c.slots[id]
		local fresh = slot == nil
		slot = Slot(c, def)
		if not slot.failed then
			if not slot.watching then
				slot.watching = true
				Touch(slot)
				if not fresh then SetFilter(c, slot, Filter(def)) end
			elseif roster then
				Touch(slot)
			end
		end
	end
	return c.frame ~= nil
end

function Backend.Feed()
	for _, c in pairs(containers) do
		for _, slot in pairs(c.slots) do
			if slot.watching and slot.handle and slot.probe and not slot.failed then
				local ok = pcall(slot.probe.SetCooldownFromDurationObject, slot.probe, slot.handle, true)
				if not ok then slot.failed = "feed refused" end
			end
		end
	end
end

function Backend.Start(cb)
	callbacks = cb
	Root():Show()
end

function Backend.Stop()
	callbacks = nil
	for unit in pairs(containers) do Backend.SetWatch(unit, {}) end
end

-- what is wrong, if anything: for the status line
function Backend.Problems()
	local out = {}
	for unit, c in pairs(containers) do
		if c.failed then out[#out + 1] = unit .. ": " .. c.failed end
		for id, slot in pairs(c.slots) do
			if slot.failed and slot.watching then out[#out + 1] = string.format("%s %d: %s", unit, id, slot.failed) end
		end
	end
	table.sort(out)
	return out
end
