local CK = CombatKit
local Skin = CK.Skin

-- ===========================================================================
-- The settings widgets, drawn with the core's palette: close button, edit box,
-- dropdown, stepper, slider. They are added to CombatKit.Skin so pages read
-- the same whether a helper lives in the core (button, check box) or here.
-- ===========================================================================

local Rest, Hoverable = Skin.Rest, Skin.Hoverable   -- the button and the check box live in the core's Skin

-- Two thin rotated bars: an X or a chevron, without a texture file.
local function Bars(parent, length, colour, a1, x1, a2, x2)
	local out = {}
	for i, spec in ipairs({ { a1, x1 }, { a2, x2 } }) do
		local t = Skin.Fill(parent, "ARTWORK", colour)
		t:SetSize(length, 1.5)
		t:SetPoint("CENTER", spec[2], 0)
		t:SetRotation(spec[1])
		out[i] = t
	end
	return out
end

function Skin.CloseButton(parent, onClick)
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(20, 20)
	b.bars = Bars(b, 12, "dim", math.pi / 4, 0, -math.pi / 4, 0)
	local function Tint(name)
		for _, t in ipairs(b.bars) do t:SetColorTexture(Skin.Color(name)) end
	end
	b:SetScript("OnEnter", function() Tint("text") end)
	b:SetScript("OnLeave", function() Tint("dim") end)
	b:SetScript("OnClick", onClick)
	return b
end

-- A "v" for dropdowns, anchored by the caller
function Skin.Chevron(parent)
	local holder = CreateFrame("Frame", nil, parent)
	holder:SetSize(10, 8)
	holder.bars = Bars(holder, 6, "dim", -math.pi / 4, -2, math.pi / 4, 2)
	return holder
end

-- A small square button with an arrow, up or down
function Skin.ArrowButton(parent, up, onClick)
	local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
	b:SetSize(18, 18)
	Skin.Backdrop(b, "element")
	Hoverable(b)
	local a = math.pi / 4
	b.bars = Bars(b, 6, "dim", up and a or -a, -2, up and -a or a, 2)
	b:SetScript("OnClick", onClick)
	return b
end

-- A one-line text box. onCommit(text) when the player is done with it.
function Skin.EditBox(parent, w, onCommit)
	local e = CreateFrame("EditBox", nil, parent, "BackdropTemplate")
	e:SetSize(w, 20)
	Skin.Backdrop(e, "element")
	e:SetFontObject("GameFontHighlightSmall")
	e:SetTextInsets(6, 6, 0, 0)
	e:SetAutoFocus(false)
	e:SetMaxLetters(40)
	e:SetScript("OnEnterPressed", e.ClearFocus)
	e:SetScript("OnEscapePressed", e.ClearFocus)
	e:SetScript("OnEditFocusGained", function(self) self:SetBackdropBorderColor(Skin.Color("accent")) end)
	e:SetScript("OnEditFocusLost", function(self)
		self:SetBackdropBorderColor(Skin.Color("border"))
		onCommit(strtrim(self:GetText() or ""))
	end)
	return e
end

-- Adds a tooltip without replacing the hover scripts a skinned widget has.
-- Takes locale keys (or functions returning one), read when shown, so it
-- follows a language switch and whatever the key depends on.
function Skin.Tooltip(widget, titleKey, bodyKey)
	local function Text(key)
		if type(key) == "function" then key = key() end
		return CK.L[key]
	end
	widget:HookScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:SetText(Text(titleKey), 1, 1, 1, 1, true)
		if bodyKey then GameTooltip:AddLine(Text(bodyKey), nil, nil, nil, true) end
		GameTooltip:Show()
	end)
	widget:HookScript("OnLeave", GameTooltip_Hide)
end

-- ---------------------------------------------------------------------------
-- Dropdown: a button that opens a small pick list
-- ---------------------------------------------------------------------------

local LIST_ROWS = 12   -- more than this and the list scrolls with the mouse wheel

local optionList
local function ShowOptionList(anchor, items, onPick)
	if not optionList then
		local f = CreateFrame("Frame", "CombatKitOptionList", UIParent, "BackdropTemplate")
		f:SetFrameStrata("TOOLTIP")
		Skin.Backdrop(f, "bg", 1, "accent")
		f:EnableMouse(true)
		f.buttons = {}
		f.measure = Skin.Label(f, "")
		f.measure:Hide()
		-- a thumb at the right edge while there is more than fits
		f.thumb = Skin.Fill(f, "ARTWORK", "accent", 0.7)
		f.thumb:SetWidth(2)
		f:EnableMouseWheel(true)
		f:SetScript("OnMouseWheel", function(self, delta)
			local last = math.max(0, #self.items - LIST_ROWS)
			self.offset = math.max(0, math.min(last, self.offset - delta))
			self.Render()
		end)
		-- click anywhere else closes it
		f:SetScript("OnUpdate", function(self)
			if IsMouseButtonDown("LeftButton") and not self:IsMouseOver() and not self.anchor:IsMouseOver() then
				self:Hide()
			end
		end)
		optionList = f
	end
	local f = optionList
	if f:IsShown() and f.anchor == anchor then f:Hide(); return end
	f.anchor = anchor
	-- it hangs off UIParent but has to match the (scaled) window it belongs to
	f:SetScale(anchor:GetEffectiveScale() / UIParent:GetEffectiveScale())
	f.items, f.offset = items, 0
	local w = anchor:GetWidth() - 8
	for _, item in ipairs(items) do
		f.measure:SetText(item.label)
		w = math.max(w, f.measure:GetStringWidth() + 16 + ((item.icon or item.swatch) and 22 or 0))
	end
	local rows = math.min(#items, LIST_ROWS)
	for i = 1, rows do
		local b = f.buttons[i]
		if not b then
			b = CreateFrame("Button", nil, f)
			b:SetHeight(20)
			b.hover = Skin.Fill(b, "BACKGROUND", "hover")
			b.hover:SetAllPoints()
			b.hover:Hide()
			b.icon = b:CreateTexture(nil, "ARTWORK")
			b.icon:SetSize(16, 16)
			b.icon:SetPoint("LEFT", 6, 0)
			b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
			b.text = Skin.Label(b, "")
			b:SetScript("OnEnter", function(self) self.hover:Show() end)
			b:SetScript("OnLeave", function(self) self.hover:Hide() end)
			b:SetScript("OnClick", function(self)
				f:Hide()
				f.onPick(self.item)
			end)
			f.buttons[i] = b
		end
		b:ClearAllPoints()
		b:SetPoint("TOPLEFT", 4, -4 - (i - 1) * 20)
		b:SetWidth(w)
		b:Show()
	end
	for i = rows + 1, #f.buttons do f.buttons[i]:Hide() end

	-- the rows show items[offset + 1 ...]
	function f.Render()
		for i = 1, rows do
			local b, item = f.buttons[i], f.items[f.offset + i]
			b.item = item
			b.text:SetText(item.label)
			b.text:ClearAllPoints()
			if item.icon or item.swatch then
				if item.swatch then
					b.icon:SetColorTexture(item.swatch[1], item.swatch[2], item.swatch[3])
				else
					b.icon:SetTexture(item.icon)
				end
				b.icon:Show()
				b.text:SetPoint("LEFT", b.icon, "RIGHT", 6, 0)
			else
				b.icon:Hide()
				b.text:SetPoint("LEFT", 8, 0)
			end
		end
		local more = #f.items > rows
		f.thumb:SetShown(more)
		if more then
			local track = rows * 20
			f.thumb:SetHeight(track * rows / #f.items)
			f.thumb:ClearAllPoints()
			f.thumb:SetPoint("TOPRIGHT", -1, -4 - track * f.offset / #f.items)
		end
	end
	f.Render()
	f.onPick = onPick
	f:SetSize(w + 8, rows * 20 + 8)
	f:ClearAllPoints()
	f:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2)
	f:Show()
end

function Skin.HideOptionList() if optionList then optionList:Hide() end end

-- getItems(dropdown) -> { { label=, value=, icon= }, ... }; onPick(dropdown, item).
-- An item may carry swatch = { r, g, b }, a plain colour, instead of an icon.
function Skin.Dropdown(parent, w, getItems, onPick)
	local d = CreateFrame("Button", nil, parent, "BackdropTemplate")
	d:SetSize(w, 20)
	Skin.Backdrop(d, "element")
	Hoverable(d)

	d.chevron = Skin.Chevron(d)
	d.chevron:SetPoint("RIGHT", -6, 0)

	d.text = Skin.Label(d, "")
	d.text:SetPoint("LEFT", 7, 0)
	d.text:SetPoint("RIGHT", -20, 0)
	d.text:SetJustifyH("LEFT")
	d.text:SetWordWrap(false)

	d:SetScript("OnClick", function(self)
		if self.disabled then return end
		ShowOptionList(self, getItems(self), function(item) onPick(self, item) end)
	end)
	d:SetScript("OnHide", Skin.HideOptionList)

	function d:SetValueText(text, dim)
		self.text:SetText(text)
		self.text:SetTextColor(Skin.Color((dim or self.disabled) and "dim" or "text"))
	end
	function d:SetDisabled(disabled)
		self.disabled = disabled and true or false
		self:SetAlpha(self.disabled and 0.55 or 1)
	end
	return d
end

-- "- 100% +" as one block the caller places; .value is the label in the middle
function Skin.Stepper(parent, onStep)
	local holder = CreateFrame("Frame", nil, parent)
	holder:SetSize(20 + 2 + 52 + 2 + 20, 20)
	local minus = Skin.Button(holder, "-", 20, 20, function() onStep(-1) end)
	minus:SetWidth(20)   -- a button grows with its label; these two must not, the block has a fixed width
	minus:SetPoint("LEFT")
	holder.value = Skin.Label(holder, "100%")
	holder.value:SetPoint("LEFT", minus, "RIGHT", 2, 0)
	holder.value:SetWidth(52)
	holder.value:SetJustifyH("CENTER")
	holder.value:SetWordWrap(false)
	local plus = Skin.Button(holder, "+", 20, 20, function() onStep(1) end)
	plus:SetWidth(20)
	plus:SetPoint("LEFT", holder.value, "RIGHT", 2, 0)
	return holder
end

-- A number to set: its name above, a slider with the ends marked, and under it a
-- box the number can be typed into. opts: min, max, step (1), width (170),
-- format(v) -> text, parse(text) -> number | nil, onChange(v). The block is
-- Skin.SLIDER_H tall; .value is the box (its text is what the number reads as).
Skin.SLIDER_H = 58
function Skin.Percent(v) return string.format("%d%%", math.floor(v * 100 + 0.5)) end
function Skin.ParsePercent(text)
	local n = tonumber((text or ""):gsub("%%", ""):gsub("%s", ""))
	if not n then return nil end
	return n / 100
end
function Skin.Slider(parent, key, opts)
	local w = opts.width or 170
	local step = opts.step or 1
	local format = opts.format or function(v) return tostring(v) end
	local parse = opts.parse or tonumber
	local f = CreateFrame("Frame", nil, parent)
	f:SetSize(w, Skin.SLIDER_H)
	f.label = CK.Bind(Skin.Label(f, "", nil, "dim"), key)
	f.label:SetPoint("TOP", 0, 0)

	local s = CreateFrame("Slider", nil, f)
	s:SetOrientation("HORIZONTAL")
	s:SetSize(w - 8, 12)
	s:SetPoint("TOP", 0, -17)
	s:SetMinMaxValues(opts.min, opts.max)
	s:SetValueStep(step)
	s:SetObeyStepOnDrag(true)
	local track = Skin.Fill(s, "BACKGROUND", "element")
	track:SetPoint("LEFT")
	track:SetPoint("RIGHT")
	track:SetHeight(4)
	s:SetThumbTexture("Interface\\Buttons\\WHITE8x8")
	local thumb = s:GetThumbTexture()
	if thumb then
		thumb:SetSize(8, 14)
		Skin.Paint(thumb, function(t) t:SetVertexColor(Skin.Color("accent")) end)
	end
	f.slider = s
	f.lo = Skin.Label(f, format(opts.min), nil, "dim")
	f.lo:SetPoint("BOTTOMLEFT", 0, 2)
	f.hi = Skin.Label(f, format(opts.max), nil, "dim")
	f.hi:SetPoint("BOTTOMRIGHT", 0, 2)

	local function snap(v)
		v = math.max(opts.min, math.min(opts.max, v))
		v = math.floor(v / step + 0.5) * step
		return math.floor(v * 1000 + 0.5) / 1000   -- the step may be a fraction
	end
	f.value = Skin.EditBox(f, 64, function(text)
		local n = parse(text)
		if n == nil then
			f.value:SetText(format(f.current))
			return
		end
		n = snap(n)
		f:SetValue(n)
		opts.onChange(n)
	end)
	f.value:SetJustifyH("CENTER")
	f.value:SetPoint("BOTTOM", 0, 0)

	-- what the number reads as, for whoever asks the block itself
	function f:GetText() return self.value:GetText() end

	-- the number from outside: the slider and the box follow, nothing fires
	function f:SetValue(v)
		self.current = v
		self.setting = true
		s:SetValue(v)
		self.setting = false
		self.value:SetText(format(v))
	end
	s:SetScript("OnValueChanged", function(_, v)
		if f.setting then return end
		v = snap(v)
		if v == f.current then return end
		f.current = v
		f.value:SetText(format(v))
		opts.onChange(v)
	end)
	return f
end

-- A dim label in front of a control, bound to its locale key
function Skin.Field(parent, key, x, y)
	local label = CK.Bind(Skin.Label(parent, "", nil, "dim"), key)
	label:SetPoint("TOPLEFT", x or 0, y - 4)
	return label
end
