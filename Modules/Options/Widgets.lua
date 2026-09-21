local CK = CombatKit
local Skin = CK.Skin

-- ===========================================================================
-- The settings widgets, drawn with the core's palette: button, check box,
-- close button, dropdown, stepper. They are added to CombatKit.Skin so pages
-- read the same whether a helper lives in the core or here.
-- ===========================================================================

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

-- w is a minimum: a label longer than that (other language) widens the button.
-- SetLabel instead of SetText keeps that true when the language changes.
function Skin.Button(parent, text, w, h, onClick)
	local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
	b:SetSize(w, h or 20)
	Skin.Backdrop(b, "element")
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
	Hoverable(b)
	b:SetScript("OnClick", onClick)
	return b
end

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
		w = math.max(w, f.measure:GetStringWidth() + 16 + (item.icon and 22 or 0))
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
			if item.icon then
				b.icon:SetTexture(item.icon)
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

-- getItems(dropdown) -> { { label=, value=, icon= }, ... }; onPick(dropdown, item)
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

-- A dim label in front of a control, bound to its locale key
function Skin.Field(parent, key, x, y)
	local label = CK.Bind(Skin.Label(parent, "", nil, "dim"), key)
	label:SetPoint("TOPLEFT", x or 0, y - 4)
	return label
end
