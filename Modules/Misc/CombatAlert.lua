local ADDON, ns = ...
local CK = CombatKit

-- ===========================================================================
-- A short text in the middle of the screen when combat starts and when it
-- ends: fade in, hold, fade out, and, if asked, floating up the while. A new
-- event while one is still showing starts over instead of queueing.
-- ===========================================================================

local FADE_IN, HOLD, FADE_OUT = 0.5, 0.5, 0.5
local RISE = 40   -- how far the text floats up over the whole show
local COLOUR = { enter = { 1, 0.1, 0.1 }, leave = { 0, 1, 0 } }

local DEFAULTS = { fontSize = 16, point = "CENTER", relPoint = "CENTER", x = 0, y = 120, rise = false }

local frame
local testing = false

local function Settings()
	ns.db.CombatAlert = ns.db.CombatAlert or {}
	local s = ns.db.CombatAlert
	for k, v in pairs(DEFAULTS) do
		if s[k] == nil then s[k] = v end
	end
	return s
end
ns.AlertSettings = Settings
ns.ALERT_DEFAULTS = DEFAULTS

-- English in every language, as MiniCombatNotifier has it; the player can type their own.
local TEXT = { enter = "<Entering Combat>", leave = "<Leaving Combat>" }
ns.ALERT_TEXT = TEXT

-- The text for "enter" / "leave": the player's own, else the one above.
function ns.AlertText(which)
	local own = Settings()[which .. "Text"]
	if own and own ~= "" then return own end
	return TEXT[which]
end

local function Create()
	frame = CreateFrame("Frame", "CombatKitCombatAlert", UIParent)
	frame:SetSize(400, 48)
	frame:SetFrameStrata("MEDIUM")
	frame:SetMovable(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", function(self) if testing then self:StartMoving() end end)
	frame:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		local point, _, relPoint, x, y = self:GetPoint()
		local s = Settings()
		s.point, s.relPoint, s.x, s.y = point, relPoint, math.floor(x + 0.5), math.floor(y + 0.5)
	end)

	-- only while placing it
	frame.bg = frame:CreateTexture(nil, "BACKGROUND")
	frame.bg:SetAllPoints()
	frame.bg:SetColorTexture(1, 1, 1, 0.08)
	frame.bg:Hide()

	frame.text = frame:CreateFontString(nil, "ARTWORK")
	frame.text:SetAllPoints()
	frame.text:SetJustifyH("CENTER")
	frame.text:SetJustifyV("MIDDLE")
	frame.text:SetAlpha(0)

	frame.fade = frame.text:CreateAnimationGroup()
	local function Alpha(order, from, to, duration)
		local a = frame.fade:CreateAnimation("Alpha")
		a:SetOrder(order)
		a:SetFromAlpha(from)
		a:SetToAlpha(to)
		a:SetDuration(duration)
		a:SetSmoothing("IN_OUT")
	end
	Alpha(1, 0, 1, FADE_IN)
	Alpha(2, 1, 1, HOLD)
	Alpha(3, 1, 0, FADE_OUT)
	frame.fade:SetScript("OnFinished", function() frame.text:SetAlpha(0) end)

	-- the option: a steady drift upwards for as long as the text shows. A group
	-- of its own, so the fade is the same with or without it.
	frame.rise = frame.text:CreateAnimationGroup()
	local t = frame.rise:CreateAnimation("Translation")
	t:SetOffset(0, RISE)
	t:SetDuration(FADE_IN + HOLD + FADE_OUT)
end

local function StopAll()
	for _, group in ipairs({ frame.fade, frame.rise }) do
		if group:IsPlaying() then group:Stop() end
	end
end

-- Font size and position, from the saved settings.
function ns.ApplyAlert()
	if not frame then return end
	local s = Settings()
	-- flags argument is mandatory since 10.0; STANDARD_TEXT_FONT follows the game's language
	frame.text:SetFont(STANDARD_TEXT_FONT, s.fontSize, "OUTLINE")
	frame:ClearAllPoints()
	frame:SetPoint(s.point, UIParent, s.relPoint, s.x, s.y)
end

local function Show(which)
	if testing then return end
	StopAll()
	frame.text:SetText(ns.AlertText(which))
	frame.text:SetTextColor(unpack(COLOUR[which]))
	frame.text:SetAlpha(0)
	frame.fade:Play()
	if Settings().rise then frame.rise:Play() end
end
ns.ShowAlert = Show

-- Placing it: the entering text stays on screen and the box can be dragged.
function ns.SetAlertTesting(on)
	if not frame then return end
	testing = on and true or false
	StopAll()
	frame:EnableMouse(testing)
	frame.bg:SetShown(testing)
	frame.text:SetText(testing and ns.AlertText("enter") or "")
	frame.text:SetTextColor(unpack(COLOUR.enter))
	frame.text:SetAlpha(testing and 1 or 0)
end
function ns.IsAlertTesting() return testing end

function ns.ResetAlertPosition()
	local s = Settings()
	s.point, s.relPoint, s.x, s.y = DEFAULTS.point, DEFAULTS.relPoint, DEFAULTS.x, DEFAULTS.y
	ns.ApplyAlert()
end

local driver = CreateFrame("Frame")
driver:SetScript("OnEvent", function(_, event)
	Show(event == "PLAYER_REGEN_DISABLED" and "enter" or "leave")
end)

ns.AddFeature("CombatAlert", {
	Start = function()
		if not frame then Create() end
		ns.ApplyAlert()
		frame:Show()
		driver:RegisterEvent("PLAYER_REGEN_DISABLED")
		driver:RegisterEvent("PLAYER_REGEN_ENABLED")
	end,
	Stop = function()
		driver:UnregisterAllEvents()
		ns.SetAlertTesting(false)
		frame:Hide()
	end,
})
