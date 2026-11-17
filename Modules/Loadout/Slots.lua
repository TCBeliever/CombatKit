local ADDON, ns = ...

-- ===========================================================================
-- Talent spells back in their action slot
--
-- A talent change that takes a spell away makes the game clear the action
-- slot holding it (shared action bars). When the spell is learned again the
-- game pushes it into the first empty slot, or leaves it off the bars. Either
-- way it loses its place on every loadout switch (Emerald Communion between a
-- Preservation PvE and PvP loadout, reported 2026-11-17).
--
-- The bars are read after each burst of changes. A spell that left its slot
-- around a talent change, and is no longer known, is remembered with that
-- slot, per character and spec. Once it is known again it goes back there if
-- the slot is still empty: out of the slot the game pushed it into, or from
-- the spell book. Found anywhere else on the bars, it was put there on
-- purpose (or came back with a loadout's own bars) and is left alone.
--
-- Slot contents are the game's, kept on the server, so this works whatever
-- draws the bars. Nothing happens in combat (talents cannot change there
-- anyway) or while something is on the cursor.
--
-- While this is on, the game's own push of newly learned spells
-- (AutoPushSpellToActionBar, a per-character setting) is off, so nothing lands
-- in a stray slot first. Its value is kept in char.autoPushWas and put back
-- when this is switched off (the player's call, 2026-11-17).
-- ===========================================================================

local SLOTS  = 180   -- pages 1 to 15: the main bar's pages, the form bars, the extra bars
local PAGE   = 12    -- slots per page
local SETTLE = 1.0   -- seconds after the last change before the bars are read
local LEAD   = 2     -- a talent event this long before a burst's first change still counts for it
local RETRY  = 2     -- seconds between looks while something is on the cursor
local SWAP   = 12    -- more slots than this changing at once, and most of them, is a whole other set of bars
local CVAR   = "AutoPushSpellToActionBar"

local running = false
local snap            -- { spec=, config=, shared=, bars = { [slot] = value } }: the bars as last read
local burstAt         -- GetTime() of the first change since then
local talentAt        -- GetTime() of the last talent event
local pushed = {}     -- [spellID] = true: the game pushed it onto the bars since the last read
local queued, owed = false, false

local function Secret(v) return issecretvalue and issecretvalue(v) or false end

local function SpellName(spellID)
	local ok, name = pcall(C_Spell.GetSpellName, spellID)
	if ok and type(name) == "string" and not Secret(name) then return name end
	return tostring(spellID)
end

-- A learned spell or talent. The spell book is not asked: it can list a spell not learned yet.
local function Known(spellID)
	local book = C_SpellBook and C_SpellBook.IsSpellKnown
	for _, fn in ipairs({ book or false, IsPlayerSpell or false }) do
		if fn then
			local ok, known = pcall(fn, spellID)
			if ok and not Secret(known) and known == true then return true end
		end
	end
	return false
end

-- true | false, or nil when the game does not say
function ns.UsesSharedBars(configID)
	if not configID or not C_Traits then return nil end
	local ok, info = pcall(C_Traits.GetConfigInfo, configID)
	if not ok or type(info) ~= "table" or type(info.usesSharedActionBars) ~= "boolean" then return nil end
	return info.usesSharedActionBars
end

-- ---------------------------------------------------------------------------
-- Reading the bars. A slot reads as its spellID, true (anything else: a macro,
-- an item), nil (empty) or false (not to be judged: unreadable, or a vehicle
-- or override page, whose contents come and go).
-- ---------------------------------------------------------------------------

local function SkippedPages()
	local skip, AB = {}, C_ActionBar or {}
	for _, name in ipairs({ "GetVehicleBarIndex", "GetOverrideBarIndex", "GetTempShapeshiftBarIndex" }) do
		local ok, page = pcall(AB[name])
		if ok and type(page) == "number" and not Secret(page) then skip[page] = true end
	end
	return skip
end

local function ReadSlot(slot)
	local ok, kind, id = pcall(GetActionInfo, slot)
	if not ok or Secret(kind) or Secret(id) then return false end
	if kind == nil then return nil end
	if kind == "spell" and type(id) == "number" then return id end
	return true
end

-- Returns bars, whether every slot could be read, how many slots hold a spell
local function ReadBars()
	local bars, readable, spells = {}, true, 0
	local skip = SkippedPages()
	for slot = 1, SLOTS do
		if skip[math.ceil(slot / PAGE)] then
			bars[slot] = false
		else
			local v = ReadSlot(slot)
			if v == false then readable = false end
			if type(v) == "number" then spells = spells + 1 end
			bars[slot] = v
		end
	end
	return bars, readable, spells
end

-- The slot holding `spellID`, and whether more than one does
local function Find(bars, spellID)
	local where
	for slot = 1, SLOTS do
		if bars[slot] == spellID then
			if where then return where, true end
			where = slot
		end
	end
	return where, false
end

-- ---------------------------------------------------------------------------
-- Putting a spell back. The target slot is empty, so nothing is left on the
-- cursor; whatever is, is cleared.
-- ---------------------------------------------------------------------------

local function CursorBusy()
	return GetCursorInfo and GetCursorInfo() ~= nil
end

local function Place(spellID, slot)
	local pickup = (C_Spell and C_Spell.PickupSpell) or PickupSpell
	if not pickup or not PlaceAction then return end
	pcall(pickup, spellID)
	if CursorBusy() then pcall(PlaceAction, slot) end
	ClearCursor()
	ns.Debug("slots: %s back in slot %d", SpellName(spellID), slot)
end

local function Move(from, to, spellID)
	if not PickupAction or not PlaceAction then return end
	pcall(PickupAction, from)
	if CursorBusy() then
		pcall(PlaceAction, to)
		-- not taken: back where it was
		if CursorBusy() then pcall(PlaceAction, from) end
	end
	ClearCursor()
	ns.Debug("slots: %s moved from slot %d back to %d", SpellName(spellID), from, to)
end

-- The spells remembered for this spec that are known again. `before` is the
-- read before the burst; `sameBars` says the bar set did not change with it.
-- `bars` follows what is done, so two spells never go into one slot.
local function Restore(mem, bars, before, sameBars)
	for spellID, slot in pairs(mem) do
		if Known(spellID) then
			local where, several = Find(bars, spellID)
			if bars[slot] == nil then
				if not where then
					Place(spellID, slot)
					bars[slot] = spellID
				elseif not several and (pushed[spellID] or (sameBars and before[where] == nil)) then
					Move(where, slot, spellID)
					bars[slot], bars[where] = spellID, nil
				end
			end
			-- back, put back, taken elsewhere, or its slot taken: settled either way
			mem[spellID] = nil
		end
	end
end

-- ---------------------------------------------------------------------------
-- After a burst
-- ---------------------------------------------------------------------------

local function Memory(specID)
	local all = ns.char.slots
	all[specID] = all[specID] or {}
	return all[specID]
end

local QueueSettle

local function Settle()
	queued = false
	if not running or not ns.char then return end
	if InCombatLockdown() then owed = true; return end
	if CursorBusy() then
		-- the player is dragging something: looked at again once they let go
		C_Timer.After(RETRY, QueueSettle)
		return
	end
	local specID = ns.GetCurrentSpecID()
	if not specID then return end
	local bars, readable, spells = ReadBars()
	-- the bars cannot be read, or read empty (not loaded): judged at the next change
	if not readable or (spells == 0 and snap and snap.spells > 0) then return end

	local config = ns.GetActiveConfigID(specID)
	local shared = ns.UsesSharedBars(config)
	local on = ns.db.settings.slotRestore
	-- a first read, or one after a spec change (a spec has its own bars), only looks
	local same = snap ~= nil and snap.spec == specID
	if on and same then
		local mem = Memory(specID)
		local talents = (talentAt and burstAt and talentAt >= burstAt - LEAD) or ns.IsApplying()
		-- most of the bars changed at once: another set of bars came on (a spec, a
		-- loadout with its own bars), which brings its spells back by itself
		local changed = 0
		for slot = 1, SLOTS do
			if snap.bars[slot] ~= bars[slot] then changed = changed + 1 end
		end
		if changed > SWAP and changed * 2 > snap.spells then
			ns.Debug("slots: %d slots changed, another set of bars", changed)
			talents = false
		end
		if talents then
			for slot = 1, SLOTS do
				local was = snap.bars[slot]
				if type(was) == "number" and bars[slot] == nil and not Known(was) and not Find(bars, was) then
					mem[was] = slot
					ns.Debug("slots: %s left slot %d", SpellName(was), slot)
				end
			end
		end
		-- the same bars stay on with the same loadout, and when both share them
		local sameBars = snap.config == config or (snap.shared == true and shared == true)
		Restore(mem, bars, snap.bars, sameBars)
		bars, _, spells = ReadBars()
	end
	snap = { spec = specID, config = config, shared = shared, bars = bars, spells = spells }
	burstAt, pushed = nil, {}
end

QueueSettle = function()
	if queued or not running then return end
	queued = true
	C_Timer.After(SETTLE, Settle)
end

local function Burst()
	burstAt = burstAt or GetTime()
	QueueSettle()
end

-- ---------------------------------------------------------------------------
-- The game's auto-push: off while this is on, as it was otherwise
-- ---------------------------------------------------------------------------

local function GetAutoPush()
	local get = (C_CVar and C_CVar.GetCVar) or GetCVar
	if not get then return nil end
	local ok, value = pcall(get, CVAR)
	if ok and type(value) == "string" then return value end   -- nil: a client without it
end

local function SetAutoPush(value)
	local set = (C_CVar and C_CVar.SetCVar) or SetCVar
	if set then pcall(set, CVAR, value) end
end

function ns.SyncAutoPush()
	if not ns.char then return end
	if InCombatLockdown() then owed = true; return end
	local value = GetAutoPush()
	if value == nil then return end
	if running and ns.db.settings.slotRestore then
		if value ~= "0" then
			ns.char.autoPushWas = value
			SetAutoPush("0")
		end
	elseif ns.char.autoPushWas ~= nil then
		SetAutoPush(ns.char.autoPushWas)
		ns.char.autoPushWas = nil
	end
end

-- The option was switched: the bars are read afresh either way
function ns.OnSlotRestoreChanged()
	ns.SyncAutoPush()
	snap = nil
	QueueSettle()
end

-- The landing offers this module's options (CombatKit.MODULES): this one only
function ns.GetOption(key)
	if key == "slotRestore" then return ns.db.settings.slotRestore end
end

function ns.SetOption(key, on)
	if key ~= "slotRestore" or ns.db.settings.slotRestore == on then return end
	ns.db.settings.slotRestore = on
	ns.OnSlotRestoreChanged()
end

-- ---------------------------------------------------------------------------
-- Events
-- ---------------------------------------------------------------------------

local EVENTS = {
	"ACTIONBAR_SLOT_CHANGED", "SPELL_PUSHED_TO_ACTIONBAR", "SPELLS_CHANGED",
	"TRAIT_CONFIG_UPDATED", "PLAYER_TALENT_UPDATE", "ACTIVE_COMBAT_CONFIG_CHANGED", "PLAYER_PVP_TALENT_UPDATE",
	"PLAYER_SPECIALIZATION_CHANGED", "PLAYER_REGEN_ENABLED",
}

local handlers = {}

handlers.ACTIONBAR_SLOT_CHANGED = Burst

function handlers.SPELL_PUSHED_TO_ACTIONBAR(spellID)
	if type(spellID) == "number" and not Secret(spellID) then pushed[spellID] = true end
	Burst()
end

-- a spell learned without a slot changing (the game's push off): looked for in the memory
handlers.SPELLS_CHANGED = QueueSettle

local function Talents()
	talentAt = GetTime()
	Burst()
end
handlers.TRAIT_CONFIG_UPDATED         = Talents
handlers.PLAYER_TALENT_UPDATE         = Talents
handlers.ACTIVE_COMBAT_CONFIG_CHANGED = Talents
handlers.PLAYER_PVP_TALENT_UPDATE     = Talents

-- a spec has its own bars: the next read only looks
function handlers.PLAYER_SPECIALIZATION_CHANGED(unit)
	if unit ~= "player" then return end
	snap = nil
	QueueSettle()
end

function handlers.PLAYER_REGEN_ENABLED()
	if not owed then return end
	owed = false
	ns.SyncAutoPush()
	QueueSettle()
end

local driver = CreateFrame("Frame")
driver:SetScript("OnEvent", function(_, event, ...) handlers[event](...) end)

function ns.StartSlots()
	running = true
	for _, e in ipairs(EVENTS) do pcall(driver.RegisterEvent, driver, e) end
	snap, burstAt, talentAt, pushed, owed = nil, nil, nil, {}, false
	ns.SyncAutoPush()
	QueueSettle()
end

-- Switched off in combat, the game's push is put back once combat ends
function ns.StopSlots()
	running = false
	driver:UnregisterAllEvents()
	snap, burstAt, pushed, owed = nil, nil, {}, false
	ns.SyncAutoPush()
	if owed then driver:RegisterEvent("PLAYER_REGEN_ENABLED") end
end
