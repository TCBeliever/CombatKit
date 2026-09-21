local ADDON, ns = ...
local CK = CombatKit
local L = CK.L

CK.NewModule("Range", ns)

-- ===========================================================================
-- Range detection
--
-- WoW has no "distance to unit" API. Instead we ask "is item X in range of
-- this unit?" for a ladder of items with known ranges, shortest first; the
-- first hit is the displayed number (so "30" means: farther than the 25yd
-- item, within the 30yd item). In combat this API is blocked for friendly
-- units, so there we fall back to the player's own spell book: every
-- non-passive spell with a max range below the class default is tested
-- with IsSpellInRange and the shortest one that hits is displayed.
-- ===========================================================================

local FRIEND_ITEMS = {
	{ 37727,  5 },   -- Ruby Acorn
	{ 63427,  6 },   -- Worgsaw
	{ 34368,  8 },   -- Attuned Crystal Cores
	{ 32321,  10 },  -- Sparrowhawk Net
	{ 1251,   15 },  -- Linen Bandage
	{ 21519,  20 },  -- Mistletoe
	{ 31463,  25 },  -- Zezzak's Shard
	{ 1180,   30 },  -- Scroll of Stamina
	{ 18904,  35 },  -- Zorbin's Ultra-Shrinker
	{ 34471,  40 },  -- Vial of the Sunwell
	{ 32698,  45 },  -- Wrangling Rope
	{ 116139, 50 },  -- Haunting Memento
	{ 32825,  60 },  -- Soul Cannon
	{ 41265,  70 },  -- Eyesore Blaster
	{ 35278,  80 },  -- Reinforced Net
}

local HARM_ITEMS = {
	{ 37727,  5 },   -- Ruby Acorn
	{ 63427,  6 },   -- Worgsaw
	{ 34368,  8 },   -- Attuned Crystal Cores
	{ 32321,  10 },  -- Sparrowhawk Net
	{ 33069,  15 },  -- Sturdy Rope
	{ 10645,  20 },  -- Gnomish Death Ray
	{ 24268,  25 },  -- Netherweave Net
	{ 835,    30 },  -- Large Rope Net
	{ 24269,  35 },  -- Heavy Netherweave Net
	{ 28767,  40 },  -- The Decapitator
	{ 23836,  45 },  -- Goblin Rocket Launcher
	{ 116139, 50 },  -- Haunting Memento
	{ 32825,  60 },  -- Soul Cannon
	{ 41265,  70 },  -- Eyesore Blaster
	{ 35278,  80 },  -- Reinforced Net
	{ 33119,  100 }, -- Malister's Frost Wand
}

ns.UNITS = { "target", "focus", "mouseover" }

local spellCache   = {}   -- { {spellID, maxRange}, ... }
local defaultRange = 40

local function IsHelpful(unit)
	if UnitIsUnit("player", unit) then return false end
	if UnitCanAttack("player", unit) then return false end
	return true
end

local function CheckItemRange(unit)
	if UnitIsUnit("player", unit) then return 0 end
	local list = IsHelpful(unit) and FRIEND_ITEMS or HARM_ITEMS
	for _, v in ipairs(list) do
		if C_Item.GetItemInfo(v[1]) and C_Item.IsItemInRange(v[1], unit) then
			return v[2]
		end
	end
	return 0
end

local function CheckSpellRange(unit)
	local best = 100
	for _, v in ipairs(spellCache) do
		if v[2] < best and C_Spell.IsSpellInRange(v[1], unit) then
			best = v[2]
		end
	end
	return best < 100 and best or 0
end

function ns.GetRangeColor(range)
	if not range or range <= 5 then return 0.9, 0.9, 0.9 end
	if range > 40 then return 1, 0, 0 end
	if range > 30 then return 1.0, 0.82, 0 end
	if range > 20 then return 0.035, 0.865, 0.0 end
	return 0.055, 0.875, 0.825
end

local function ScanSpells()
	local _, class = UnitClass("player")
	defaultRange = (class == "EVOKER") and 25 or 40
	wipe(spellCache)

	for tab = 1, C_SpellBook.GetNumSpellBookSkillLines() do
		local line = C_SpellBook.GetSpellBookSkillLineInfo(tab)
		-- offSpecID ~= nil means "spells of an inactive spec": listed but not castable
		if line and not line.offSpecID then
			for i = line.itemIndexOffset + 1, line.itemIndexOffset + line.numSpellBookItems do
				local bank = Enum.SpellBookSpellBank.Player
				if not C_SpellBook.GetSpellBookItemName(i, bank) then break end
				local _, _, spellID = C_SpellBook.GetSpellBookItemType(i, bank)
				if spellID and not C_SpellBook.IsSpellBookItemPassive(i, bank) then
					local override = C_Spell.GetOverrideSpell(spellID)
					local info = C_Spell.GetSpellInfo(override or spellID)
					if info and info.maxRange and info.maxRange > 0 and info.maxRange < defaultRange then
						spellCache[#spellCache + 1] = { info.spellID, info.maxRange }
					end
				end
			end
		end
	end
end

-- Ask the client to cache every ladder item so the first ticks don't skip rungs.
local function PreloadItems()
	for _, list in ipairs({ FRIEND_ITEMS, HARM_ITEMS }) do
		for _, v in ipairs(list) do
			C_Item.RequestLoadItemDataByID(v[1])
		end
	end
end

-- Returns the range number to display for `unit`, or 0 for "nothing".
function ns.GetUnitRange(unit)
	if not UnitExists(unit) then return 0 end
	if not InCombatLockdown() or not IsHelpful(unit) then
		return CheckItemRange(unit)
	end
	return CheckSpellRange(unit)
end

-- ---------------------------------------------------------------------------
-- Saved data (CombatKitRangeDB, account-wide)
-- ---------------------------------------------------------------------------

ns.defaults = {
	fontSize    = 16,
	fontOutline = "THICKOUTLINE",   -- "" | "OUTLINE" | "THICKOUTLINE"
	updateRate  = 0.25,
	hideMelee   = false,
	units = {
		target    = { enabled = true, point = "CENTER", relPoint = "CENTER", x = 0,   y = -118 },
		focus     = { enabled = true, point = "CENTER", relPoint = "CENTER", x = 385, y = -220 },
		mouseover = { enabled = true, x = 50, y = 0 },
	},
}

-- Fill missing keys in `dst` from `defaults` (never overwrites existing values).
local function FillDefaults(dst, defaults)
	for k, v in pairs(defaults) do
		if type(v) == "table" then
			if type(dst[k]) ~= "table" then dst[k] = {} end
			FillDefaults(dst[k], v)
		elseif dst[k] == nil then
			dst[k] = v
		end
	end
	return dst
end

local function InitDB()
	if type(CombatKitRangeDB) ~= "table" then CombatKitRangeDB = {} end
	ns.db = FillDefaults(CombatKitRangeDB, ns.defaults)
end

-- ---------------------------------------------------------------------------
-- Display frames
-- ---------------------------------------------------------------------------

local displays = {}
ns.displays = displays
local locked = true
local running = false
local SAMPLE_TEXT = "35"

function ns.IsLocked() return locked end

local function CreateDisplay(unit)
	local f = CreateFrame("Frame", "CombatKitRange_" .. unit, UIParent)
	f.unit = unit
	f:SetSize(64, 32)
	f:SetFrameStrata("MEDIUM")
	f:SetFrameLevel(9000)
	f:SetMovable(true)
	f:SetClampedToScreen(true)
	f:EnableMouse(false)

	f.text = f:CreateFontString(nil, "OVERLAY")
	f.text:SetPoint("CENTER")

	-- Only visible while unlocked
	f.bg = f:CreateTexture(nil, "BACKGROUND")
	f.bg:SetAllPoints()
	f.bg:SetColorTexture(0.2, 0.6, 1.0, 0.35)
	f.bg:Hide()

	f.label = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	f.label:SetPoint("BOTTOM", f, "TOP", 0, 2)
	f.label:Hide()

	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", function(self)
		if not locked then self:StartMoving() end
	end)
	f:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		local point, _, relPoint, x, y = self:GetPoint()
		local u = ns.db.units[self.unit]
		u.point, u.relPoint, u.x, u.y = point, relPoint, math.floor(x + 0.5), math.floor(y + 0.5)
	end)

	displays[unit] = f
	return f
end

local function ApplyLockState()
	for _, unit in ipairs(ns.UNITS) do
		local f = displays[unit]
		local movable = (not locked) and unit ~= "mouseover"
		f:EnableMouse(movable)
		f.bg:SetShown(not locked)
		f.label:SetText(L["RANGE_" .. unit])
		f.label:SetShown(not locked)
		if not locked then
			f.text:SetText(SAMPLE_TEXT)
			f.text:SetTextColor(ns.GetRangeColor(35))
			f:Show()
		else
			f.text:SetText("")
			f:SetShown(running and ns.db.units[unit].enabled)
		end
	end
end

-- Font, positions and lock state, from the saved settings.
function ns.Apply()
	if not displays.target then return end
	for _, unit in ipairs(ns.UNITS) do
		local f, u = displays[unit], ns.db.units[unit]
		-- flags argument is mandatory since 10.0; "" = no outline
		f.text:SetFont(STANDARD_TEXT_FONT, ns.db.fontSize, ns.db.fontOutline or "")
		if unit ~= "mouseover" then
			f:ClearAllPoints()
			f:SetPoint(u.point, UIParent, u.relPoint, u.x, u.y)
		end
	end
	ApplyLockState()
end

-- Unlocked: every box shows a sample number and can be dragged.
function ns.SetLocked(state)
	locked = state and true or false
	if displays.target then ApplyLockState() end
end

function ns.ResetPositions()
	for _, unit in ipairs(ns.UNITS) do
		local d, u = ns.defaults.units[unit], ns.db.units[unit]
		u.point, u.relPoint, u.x, u.y = d.point, d.relPoint, d.x, d.y
	end
	ns.Apply()
end

-- ---------------------------------------------------------------------------
-- Update loop
-- ---------------------------------------------------------------------------

local function UpdateUnit(unit)
	local f = displays[unit]
	if not f or not locked then return end
	local u = ns.db.units[unit]
	if not u.enabled then
		f.text:SetText("")
		return
	end
	local range = ns.GetUnitRange(unit)
	if range == 0 or (ns.db.hideMelee and range <= 5) then
		f.text:SetText("")
	else
		f.text:SetText(math.floor(range + 0.5))
		f.text:SetTextColor(ns.GetRangeColor(range))
	end
end
ns.UpdateUnit = UpdateUnit

local function FollowCursor()
	local f = displays.mouseover
	if not f then return end
	local u = ns.db.units.mouseover
	if locked and (not u.enabled or not UnitExists("mouseover")) then return end
	local scale = UIParent:GetEffectiveScale()
	local x, y = GetCursorPosition()
	f:ClearAllPoints()
	f:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x / scale + u.x, y / scale + u.y)
end

local driver = CreateFrame("Frame")
local elapsedAcc = 0
local function OnUpdate(_, elapsed)
	FollowCursor()
	elapsedAcc = elapsedAcc + elapsed
	if elapsedAcc >= ns.db.updateRate then
		elapsedAcc = 0
		for _, unit in ipairs(ns.UNITS) do UpdateUnit(unit) end
	end
end

driver:SetScript("OnEvent", function(_, event)
	if event == "PLAYER_TARGET_CHANGED" then
		UpdateUnit("target")
	elseif event == "PLAYER_FOCUS_CHANGED" then
		UpdateUnit("focus")
	else
		ScanSpells()
	end
end)

local EVENTS = {
	"PLAYER_TARGET_CHANGED", "PLAYER_FOCUS_CHANGED", "PLAYER_ENTERING_WORLD",
	"TRAIT_CONFIG_UPDATED", "TRAIT_CONFIG_LIST_UPDATED", "ACTIVE_TALENT_GROUP_CHANGED",
	"PLAYER_REGEN_ENABLED", "SPELLS_CHANGED",
}

-- ---------------------------------------------------------------------------
-- Module on / off
-- ---------------------------------------------------------------------------

function ns.OnEnable()
	if not ns.db then InitDB() end
	running = true
	if not displays.target then
		for _, unit in ipairs(ns.UNITS) do CreateDisplay(unit) end
	end
	for _, e in ipairs(EVENTS) do pcall(driver.RegisterEvent, driver, e) end
	driver:SetScript("OnUpdate", OnUpdate)
	PreloadItems()
	ScanSpells()
	ns.Apply()
end

function ns.OnDisable()
	running = false
	locked = true
	driver:UnregisterAllEvents()
	driver:SetScript("OnUpdate", nil)
	for _, f in pairs(displays) do f:Hide() end
end

function ns.IsRunning() return running end
