local ADDON, ns = ...
local CK = CombatKit
local L = CK.L

-- ===========================================================================
-- Pet health: a line while a hunter's or warlock's pet is low, in combat too
-- (the rest of the module waits for combat to end): the spell that heals the
-- pet as an icon, if asked, and the text to its right, sized as the combat
-- alert's text is, by a font size. It stands on its own, where the player
-- drags it while the reminders are unlocked.
--
-- The pet's health may be secret (an arena, a raid encounter, a key), so it is
-- never read. UnitHealthPercent hands it through a step curve as a colour
-- whose alpha is 1 below the threshold and 0 from it up, and the icon takes
-- that alpha as it is: the game decides what shows. For the same reason there
-- is no sound: nothing here knows when the icon appears.
-- ===========================================================================

-- the spell that heals the pet: its icon
local ICONS = { HUNTER = 136, WARLOCK = 755 }   -- Mend Pet, Health Funnel
local RED = { 1, 0.3, 0.3 }
local GAP = 6   -- between the icon and the text

local frame
local curve, curveAt   -- the curve, and the threshold it was made for
local running = false
local events = CreateFrame("Frame")

-- the curve for a threshold in percent: opaque from 0 up to it, clear from it on
local function Curve(below)
	if curve and curveAt == below then return curve end
	if not (C_CurveUtil and C_CurveUtil.CreateColorCurve and CreateColor) then return nil end
	local c = C_CurveUtil.CreateColorCurve()
	if Enum and Enum.LuaCurveType then c:SetType(Enum.LuaCurveType.Step) end
	c:AddPoint(0, CreateColor(1, 1, 1, 1))
	c:AddPoint(below / 100, CreateColor(1, 1, 1, 0))
	curve, curveAt = c, below
	return c
end

-- does this character have the warning at all: a class with a pet that heals it
function ns.HasPetHealth()
	local _, class = UnitClass("player")
	return ICONS[class] ~= nil
end

-- for the settings page: the warning's icon (the spell that heals the pet), and the pet section's
local HEADS = { HUNTER = 883, WARLOCK = 691 }   -- Call Pet 1, Summon Felhunter
function ns.PetHealthIcon()
	local _, class = UnitClass("player")
	return ns.SpellIcon(ICONS[class])
end
function ns.PetHeadIcon()
	local _, class = UnitClass("player")
	return ns.SpellIcon(HEADS[class])
end

local function SavePosition(self)
	self:StopMovingOrSizing()
	local db = ns.db.petHealth
	local cx, cy = self:GetCenter()
	local ux, uy = UIParent:GetCenter()
	if cx and ux then
		db.point, db.relPoint, db.x, db.y = "CENTER", "CENTER", math.floor(cx - ux + 0.5), math.floor(cy - uy + 0.5)
	end
	self:ClearAllPoints()
	self:SetPoint(db.point, UIParent, db.relPoint, db.x, db.y)
end

local function Create()
	frame = CreateFrame("Frame", "CombatKitPetHealth", UIParent)
	frame:SetFrameStrata("MEDIUM")
	frame:SetMovable(true)
	frame:SetClampedToScreen(true)
	frame:EnableMouse(false)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", function(self) if not ns.IsLocked() then self:StartMoving() end end)
	frame:SetScript("OnDragStop", SavePosition)
	frame.bg = frame:CreateTexture(nil, "BACKGROUND")
	frame.bg:SetPoint("TOPLEFT", -4, 4)
	frame.bg:SetPoint("BOTTOMRIGHT", 4, -4)
	frame.bg:SetColorTexture(0.2, 0.6, 1.0, 0.35)
	frame.bg:Hide()
	frame.icon = frame:CreateTexture(nil, "ARTWORK")
	frame.icon:SetPoint("LEFT")
	frame.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	frame.label = frame:CreateFontString(nil, "OVERLAY")
	frame.label:SetJustifyH("LEFT")
	frame:Hide()
end

-- the font, the icon and the text side by side, and the place, from the settings: the font
-- before anything is written on it. The icon is half as tall again as the text.
local function Layout()
	local db = ns.db.petHealth
	frame.label:SetFont(STANDARD_TEXT_FONT, db.fontSize, "OUTLINE")
	frame.label:SetText(L["Pet health low"])
	local size = math.floor(db.fontSize * 1.5 + 0.5)
	frame.icon:SetSize(size, size)
	frame.icon:SetTexture(ns.PetHealthIcon() or 134400)
	frame.icon:SetShown(db.icon)
	frame.label:ClearAllPoints()
	if db.icon then
		frame.label:SetPoint("LEFT", frame.icon, "RIGHT", GAP, 0)
	else
		frame.label:SetPoint("LEFT")
	end
	local textW = frame.label:GetStringWidth() or 0
	frame:SetSize((db.icon and size + GAP or 0) + textW, math.max(db.icon and size or 0, db.fontSize))
	frame:ClearAllPoints()
	frame:SetPoint(db.point, UIParent, db.relPoint, db.x, db.y)
end

-- a sample to drag or look at: the reminders unlocked, or the test on
local function Sample()
	return not ns.IsLocked() or ns.IsTesting()
end

-- The pet is low: the curve's alpha, as the game hands it (possibly secret). Where the frame
-- will not take a secret alpha, the icon and its name take it as a colour instead.
local function Paint(alpha)
	frame:SetAlpha(1)
	frame.icon:SetVertexColor(1, 1, 1, 1)
	frame.label:SetTextColor(RED[1], RED[2], RED[3], 1)
	if alpha == nil then return end
	if not pcall(frame.SetAlpha, frame, alpha) then
		frame:SetAlpha(1)
		pcall(frame.icon.SetVertexColor, frame.icon, 1, 1, 1, alpha)
		pcall(frame.label.SetTextColor, frame.label, RED[1], RED[2], RED[3], alpha)
	end
end

local function Update()
	local db = ns.db and ns.db.petHealth
	if not db then return end
	local _, class = UnitClass("player")
	local wanted = running and db.on and ICONS[class]
	if not wanted then
		if frame then frame:Hide() end
		return
	end
	if not frame then
		Create()
		Layout()
	end
	local sample = Sample()
	frame:EnableMouse(not ns.IsLocked())
	frame.bg:SetShown(not ns.IsLocked())
	if sample then
		Paint(nil)
		frame:Show()
		return
	end
	local expected = ns.PetExpected()
	local c = expected and ns.HasPet() and UnitHealthPercent and Curve(db.below)
	if not c then
		frame:Hide()
		return
	end
	local ok, color = pcall(UnitHealthPercent, "pet", true, c)
	if not ok or not color or not color.GetRGBA then
		frame:Hide()
		return
	end
	local _, _, _, alpha = color:GetRGBA()
	if not ns.Secret(alpha) and (alpha or 0) <= 0 then
		frame:Hide()   -- readable and clear: nothing to show
		return
	end
	Paint(alpha)
	frame:Show()
end

-- Size, place and name, from the settings; then what shows
function ns.PetHealthApply()
	if frame then Layout() end
	Update()
end

events:SetScript("OnEvent", function() Update() end)

-- with the module: the pet's health and the things that decide whether it is watched
function ns.PetHealthStart(on)
	running = on and true or false
	events:UnregisterAllEvents()
	if running and ns.HasPetHealth() then
		pcall(events.RegisterUnitEvent, events, "UNIT_HEALTH", "pet")
		pcall(events.RegisterUnitEvent, events, "UNIT_MAXHEALTH", "pet")
		pcall(events.RegisterUnitEvent, events, "UNIT_PET", "player")
		for _, e in ipairs({ "PLAYER_ENTERING_WORLD", "SPELLS_CHANGED", "PLAYER_SPECIALIZATION_CHANGED", "TRAIT_CONFIG_UPDATED" }) do
			pcall(events.RegisterEvent, events, e)
		end
	end
	ns.PetHealthApply()
end

-- for the tests
function ns.GetPetHealth() return frame end
