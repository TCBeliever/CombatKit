local ADDON, ns = ...

-- ===========================================================================
-- Look: flat panels, 1px borders, one palette. No Blizzard frame templates and
-- no texture or font files; everything is drawn with the white 8x8 texture.
-- Fonts stay the game's own so every locale keeps its glyphs.
--
-- Only what frames on screen need lives here. Buttons, check boxes and the
-- other settings widgets are added to this table by CombatKit_Options.
-- ===========================================================================

local Skin = {}
ns.Skin = Skin

local WHITE = "Interface\\Buttons\\WHITE8x8"

-- "Tide". To restyle the addon, change this table and nothing else.
local C = {
	bg       = { 0.025, 0.040, 0.055 },
	panel    = { 0.040, 0.100, 0.130 },
	element  = { 0.060, 0.180, 0.230 },
	hover    = { 0.080, 0.240, 0.300 },
	selected = { 0.070, 0.230, 0.290 },
	border   = { 0.160, 0.450, 0.560 },
	accent   = { 0.300, 0.720, 0.880 },
	text     = { 1.00, 1.00, 1.00 },
	dim      = { 0.62, 0.71, 0.76 },
	ok       = { 0.34, 0.88, 0.48 },
	warn     = { 0.91, 0.66, 0.25 },
	bad      = { 0.95, 0.35, 0.35 },
}
Skin.colors = C

function Skin.Color(name)
	local c = C[name]
	return c[1], c[2], c[3]
end

-- "|cffrrggbb" for inline colouring
function Skin.Hex(name)
	local c = C[name]
	return string.format("|cff%02x%02x%02x",
		math.floor(c[1] * 255 + 0.5), math.floor(c[2] * 255 + 0.5), math.floor(c[3] * 255 + 0.5))
end

function Skin.Text(name, text)
	return Skin.Hex(name) .. text .. "|r"
end

-- frame must have been created with "BackdropTemplate"
function Skin.Backdrop(frame, bg, alpha, border)
	frame:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
	local r, g, b = Skin.Color(bg or "bg")
	frame:SetBackdropColor(r, g, b, alpha or 1)
	frame:SetBackdropBorderColor(Skin.Color(border or "border"))
end

function Skin.Panel(parent, bg, alpha, border)
	local f = CreateFrame("Frame", nil, parent, "BackdropTemplate")
	Skin.Backdrop(f, bg, alpha, border)
	return f
end

-- A solid colour texture
function Skin.Fill(parent, layer, name, alpha)
	local t = parent:CreateTexture(nil, layer or "BACKGROUND")
	local r, g, b = Skin.Color(name)
	t:SetColorTexture(r, g, b, alpha or 1)
	return t
end

function Skin.Label(parent, text, template, colour)
	local fs = parent:CreateFontString(nil, "OVERLAY", template or "GameFontHighlightSmall")
	fs:SetTextColor(Skin.Color(colour or "text"))
	fs:SetText(text or "")
	return fs
end
