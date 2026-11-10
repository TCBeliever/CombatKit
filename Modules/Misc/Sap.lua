local ADDON, ns = ...

-- ===========================================================================
-- Sap icon: for a rogue in an arena or a battleground, the Sap icon above the
-- nameplate of every enemy player out of combat, the one condition Sap asks of
-- a player. A player is always a kind of target Sap takes, so the creature type
-- is not looked at (the game keeps an enemy player's hidden there anyway).
-- The AI opponents of a training battleground count as players; pets and other
-- NPCs get nothing.
--
-- Nothing runs anywhere else: outside an arena or a battleground no unit event
-- is even registered. The icon hangs on the nameplate's own frame, not on the
-- unit frame inside it, so it shows whichever addon draws the nameplates.
-- Nameplates come and go with the camera and are reused, so are the icons.
--
-- Its size and its offset from the top of the nameplate (X, Y) are the player's.
-- To set them anywhere, a preview puts the icon on every nameplate on screen.
-- ===========================================================================

local SAP = 6770
local DEFAULTS = { size = 24, x = 0, y = 2 }

local icons = {}      -- nameplate frame -> its icon (a small frame with the texture)
local plates = {}     -- unit token -> nameplate frame, while that unit has one
local started = false -- the feature runs (a rogue switched it on)
local active = false  -- listening: in an arena or a battleground, or previewing
local preview = false -- the icon on every nameplate, to set its size and place

local UNIT_EVENTS = { "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED", "UNIT_FLAGS", "UNIT_FACTION" }

local function Settings()
	ns.db.SapIcon = ns.db.SapIcon or {}
	local s = ns.db.SapIcon
	for k, v in pairs(DEFAULTS) do
		if s[k] == nil then s[k] = v end
	end
	return s
end
ns.SapSettings = Settings
ns.SAP_DEFAULTS = DEFAULTS

local function Readable(v) return not (issecretvalue and issecretvalue(v)) end

-- A player, or an NPC standing in for one (the AI opponents of a training
-- battleground, which UnitIsPlayer does not count).
local function PlayerLike(unit)
	local player = UnitIsPlayer(unit)
	if player or not UnitIsNPCAsPlayer then return player end
	return UnitIsNPCAsPlayer(unit)
end

-- A value the client keeps secret counts against: no icon rather than a wrong one.
local function Sappable(unit)
	local player, enemy = PlayerLike(unit), UnitCanAttack("player", unit)
	local dead, combat = UnitIsDeadOrGhost(unit), UnitAffectingCombat(unit)
	if not (Readable(player) and Readable(enemy) and Readable(dead) and Readable(combat)) then return false end
	return player and enemy and not dead and not combat
end

local function Place(icon)
	local s = Settings()
	icon:SetSize(s.size, s.size)
	icon:ClearAllPoints()
	icon:SetPoint("BOTTOM", icon.plate, "TOP", s.x, s.y)
end

local function Icon(plate)
	local icon = icons[plate]
	if not icon then
		-- a frame of its own above the nameplate's unit frame: pulled down onto the
		-- health bar (Y below zero), it is drawn over the bar, not under it
		icon = CreateFrame("Frame", nil, plate)
		icon.plate = plate
		icon:SetFrameLevel(plate:GetFrameLevel() + 20)
		icon.texture = icon:CreateTexture(nil, "ARTWORK")
		icon.texture:SetAllPoints()
		icon.texture:SetTexture(C_Spell.GetSpellTexture(SAP))
		icon.texture:SetTexCoord(0.08, 0.92, 0.08, 0.92)   -- without the icon's own border
		Place(icon)
		icons[plate] = icon
	end
	return icon
end

-- Size and offset, from the saved settings, on every icon made so far.
function ns.ApplySapIcon()
	for _, icon in pairs(icons) do Place(icon) end
end

local function Update(unit)
	local plate = plates[unit]
	if not plate then return end
	if preview or Sappable(unit) then
		Icon(plate):Show()
	elseif icons[plate] then
		icons[plate]:Hide()
	end
end

local function Added(unit)
	-- nil for a forbidden nameplate (a friendly one inside an instance)
	local plate = C_NamePlate.GetNamePlateForUnit(unit)
	if not plate then return end
	plates[unit] = plate
	Update(unit)
end

local function Removed(unit)
	local plate = plates[unit]
	if not plate then return end
	plates[unit] = nil
	if icons[plate] then icons[plate]:Hide() end
end

local function InPvP()
	local _, kind = IsInInstance()
	return kind == "arena" or kind == "pvp"
end

local driver = CreateFrame("Frame")

local function SetActive(on)
	if on == active then return end
	active = on
	if on then
		for _, event in ipairs(UNIT_EVENTS) do driver:RegisterEvent(event) end
		-- the nameplates already up (switched on inside a match, or a preview)
		for _, plate in ipairs(C_NamePlate.GetNamePlates()) do
			if plate.namePlateUnitToken then Added(plate.namePlateUnitToken) end
		end
	else
		for _, event in ipairs(UNIT_EVENTS) do driver:UnregisterEvent(event) end
		for unit in pairs(plates) do Removed(unit) end
	end
end

-- Listen where it is wanted, and look at every nameplate again (a preview came or went).
local function Refresh()
	SetActive(started and (preview or InPvP()))
	for unit in pairs(plates) do Update(unit) end
end

driver:SetScript("OnEvent", function(_, event, unit)
	if event == "PLAYER_ENTERING_WORLD" then
		Refresh()
	elseif event == "NAME_PLATE_UNIT_ADDED" then
		Added(unit)
	elseif event == "NAME_PLATE_UNIT_REMOVED" then
		Removed(unit)
	else   -- UNIT_FLAGS (in or out of combat), UNIT_FACTION: only for units with a nameplate
		Update(unit)
	end
end)

function ns.SetSapPreview(on)
	preview = on and started or false
	Refresh()
end
function ns.IsSapPreview() return preview end

-- for the tests: the icon a nameplate frame has, if any
function ns.SapIconOf(plate) return icons[plate] end

ns.AddFeature("SapIcon", {
	-- a rogue's only: the core neither offers nor counts it for another class
	Start = function()
		started = true
		driver:RegisterEvent("PLAYER_ENTERING_WORLD")
		Refresh()
	end,
	Stop = function()
		started, preview = false, false
		driver:UnregisterEvent("PLAYER_ENTERING_WORLD")
		SetActive(false)
	end,
})
