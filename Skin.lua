local ADDON, ns = ...

-- ===========================================================================
-- Look: flat panels, 1px borders, one palette at a time. No Blizzard frame
-- templates and no texture or font files; everything is drawn with the white
-- 8x8 texture. Fonts stay the game's own so every locale keeps its glyphs.
--
-- Only what frames on screen need lives here, plus the button and the check
-- box; the other settings widgets are added to this table by CombatKit_Options.
-- ===========================================================================

local Skin = {}
ns.Skin = Skin

local WHITE = "Interface\\Buttons\\WHITE8x8"

-- The themes to pick from, in the order the settings list them; the first is
-- the default. To add one, add its table here and its name to the options'
-- locales (THEME_<key>). ok, warn and bad mean the same in every theme, so an
-- accent keeps clear of green, amber and red.
Skin.THEMES = {
	{ key = "tide", colors = {
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
	} },
	{ key = "dusk", colors = {
		bg       = { 0.040, 0.030, 0.060 },
		panel    = { 0.085, 0.060, 0.135 },
		element  = { 0.140, 0.100, 0.230 },
		hover    = { 0.190, 0.140, 0.300 },
		selected = { 0.180, 0.130, 0.290 },
		border   = { 0.390, 0.280, 0.560 },
		accent   = { 0.700, 0.540, 0.920 },
		text     = { 1.00, 1.00, 1.00 },
		dim      = { 0.70, 0.65, 0.78 },
		ok       = { 0.34, 0.88, 0.48 },
		warn     = { 0.91, 0.66, 0.25 },
		bad      = { 0.95, 0.35, 0.35 },
	} },
}

-- The palette in force, filled by Skin.SetTheme. The table stays the same, so
-- a reference taken once keeps reading the current theme.
local C = {}
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

-- ---------------------------------------------------------------------------
-- Painting. Every widget coloured from the palette says how, so a theme switch
-- can paint it again. A colour that follows a state (a lit button, a dimmed
-- tab) and every inline Skin.Text are set again by the refresh after a switch.
-- ---------------------------------------------------------------------------

local painted = setmetatable({}, { __mode = "k" })   -- widget -> how it is coloured

-- apply(widget) colours it from the palette: run now and on every theme switch.
function Skin.Paint(widget, apply)
	painted[widget] = apply
	apply(widget)
	return widget
end

-- key: one of Skin.THEMES; anything else reads as the first. Skin.theme is the
-- key in force afterwards.
function Skin.SetTheme(key)
	local theme = Skin.THEMES[1]
	for _, t in ipairs(Skin.THEMES) do
		if t.key == key then theme = t end
	end
	Skin.theme = theme.key
	for name, c in pairs(theme.colors) do C[name] = { c[1], c[2], c[3] } end
	for widget, apply in pairs(painted) do apply(widget) end
end

-- frame must have been created with "BackdropTemplate"
function Skin.Backdrop(frame, bg, alpha, border)
	frame:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
	Skin.Paint(frame, function(f)
		local r, g, b = Skin.Color(bg or "bg")
		f:SetBackdropColor(r, g, b, alpha or 1)
		f:SetBackdropBorderColor(Skin.Color(border or "border"))
	end)
end

function Skin.Panel(parent, bg, alpha, border)
	local f = CreateFrame("Frame", nil, parent, "BackdropTemplate")
	Skin.Backdrop(f, bg, alpha, border)
	return f
end

-- A solid colour texture
function Skin.Fill(parent, layer, name, alpha)
	local t = parent:CreateTexture(nil, layer or "BACKGROUND")
	return Skin.Paint(t, function(tex)
		local r, g, b = Skin.Color(name)
		tex:SetColorTexture(r, g, b, alpha or 1)
	end)
end

function Skin.Label(parent, text, template, colour)
	local fs = parent:CreateFontString(nil, "OVERLAY", template or "GameFontHighlightSmall")
	Skin.Paint(fs, function(f) f:SetTextColor(Skin.Color(colour or "text")) end)
	fs:SetText(text or "")
	return fs
end

-- ---------------------------------------------------------------------------
-- Two widgets the core itself needs (the landing): the button and the check box.
-- The rest of the settings widgets are in CombatKit_Options.
-- ---------------------------------------------------------------------------

-- At rest: plain, or picked out when the widget is the chosen one of a group.
local function Rest(self)
	self:SetBackdropColor(Skin.Color(self.selected and "selected" or "element"))
	self:SetBackdropBorderColor(Skin.Color(self.selected and "accent" or "border"))
end

local function Hoverable(widget)
	widget:HookScript("OnEnter", function(self)
		if self.disabled then return end
		self:SetBackdropColor(Skin.Color("hover"))
		self:SetBackdropBorderColor(Skin.Color("accent"))
	end)
	widget:HookScript("OnLeave", Rest)
end
Skin.Hoverable = Hoverable
Skin.Rest = Rest

-- w is a minimum: a label longer than that (other language) widens the button.
-- SetLabel instead of SetText keeps that true when the language changes.
function Skin.Button(parent, text, w, h, onClick)
	local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
	b:SetSize(w, h or 20)
	Skin.Backdrop(b, "element")
	Skin.Paint(b, Rest)   -- a lit button stays lit through a theme switch
	local fs = Skin.Label(b, "")
	fs:SetPoint("CENTER")
	b:SetFontString(fs)
	function b:SetLabel(label)
		self:SetText(label or "")
		self:SetWidth(math.max(w, fs:GetStringWidth() + 18))
	end
	b:SetLabel(text)
	-- one of several buttons that stand for a choice: the chosen one stays lit
	function b:SetSelected(on)
		self.selected = on and true or false
		Rest(self)
	end
	function b:SetDisabled(disabled)
		self.disabled = disabled and true or false
		self:SetAlpha(self.disabled and 0.55 or 1)
	end
	Hoverable(b)
	b:SetScript("OnClick", function(self, ...)
		if not self.disabled then onClick(self, ...) end
	end)
	return b
end

-- A plain Button that behaves like a check box. onChange(checked)
function Skin.Checkbox(parent, text, onChange)
	local c = CreateFrame("Button", nil, parent)
	c:SetHeight(18)
	c.box = Skin.Fill(c, "BACKGROUND", "border")
	c.box:SetSize(14, 14)
	c.box:SetPoint("LEFT")
	c.fill = Skin.Fill(c, "BORDER", "element")
	c.fill:SetSize(12, 12)
	c.fill:SetPoint("CENTER", c.box)
	c.mark = Skin.Fill(c, "ARTWORK", "accent")
	c.mark:SetSize(8, 8)
	c.mark:SetPoint("CENTER", c.box)
	c.mark:Hide()
	c.label = Skin.Label(c, "")
	c.label:SetPoint("LEFT", c.box, "RIGHT", 6, 0)

	-- the click area follows the label, whatever the language
	function c:SetLabel(label)
		self.label:SetText(label or "")
		self:SetWidth(14 + 6 + self.label:GetStringWidth())
	end
	c:SetLabel(text)

	function c:SetChecked(v)
		self.checked = v and true or false
		self.mark:SetShown(self.checked)
	end
	function c:GetChecked() return self.checked or false end

	c:SetScript("OnEnter", function(self) self.box:SetColorTexture(Skin.Color("accent")) end)
	c:SetScript("OnLeave", function(self) self.box:SetColorTexture(Skin.Color("border")) end)
	c:SetScript("OnClick", function(self)
		self:SetChecked(not self.checked)
		onChange(self.checked)
	end)
	return c
end

Skin.SetTheme(Skin.THEMES[1].key)   -- until the saved one is read
