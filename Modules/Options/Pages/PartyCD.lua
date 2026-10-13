local CK = CombatKit
local L, Skin, O = CK.L, CK.Skin, CK.Options

-- Settings page of the Party CD module.

local X = O.FIELD_X + 20
local AR   -- the module, set whenever the section is used

local GROWS = { { "right", "Grow: right" }, { "down", "Grow: down" } }
local SIDES = { { "RIGHT", "Side: right" }, { "LEFT", "Side: left" }, { "TOP", "Side: above" }, { "BOTTOM", "Side: below" } }
local function Items(list)
	return function()
		local items = {}
		for _, g in ipairs(list) do items[#items + 1] = { label = L[g[2]], value = g[1] } end
		return items
	end
end

local function Changed()
	AR.Apply()
	O.Changed()
end

local function Build(p)
	Skin.Field(p, "Show", 0, 0)
	p.showSelf = CK.Bind(Skin.Checkbox(p, "", function(checked)
		AR.db.showSelf = checked
		Changed()
	end), "Show your own row")
	p.showSelf:SetPoint("TOPLEFT", X, -1)
	p.externals = CK.Bind(Skin.Checkbox(p, "", function(checked)
		AR.db.externals = checked
		Changed()
	end), "Externals (buffs put on an ally)")
	p.externals:SetPoint("TOPLEFT", X, -27)

	-- by the party frames: which side, how far, shifted along the edge
	Skin.Field(p, "Attach", 0, -58)
	p.attach = CK.Bind(Skin.Checkbox(p, "", function(checked)
		AR.db.attach = checked
		Changed()
	end), "Attach to party frames")
	p.attach:SetPoint("TOPLEFT", X, -59)
	Skin.Field(p, "Side", 0, -90)
	p.side = Skin.Dropdown(p, 180, Items(SIDES), function(_, item)
		AR.db.side = item.value
		Changed()
	end)
	p.side:SetPoint("TOPLEFT", X, -90)

	local function Slider(key, x, y, opts)
		local s = Skin.Slider(p, key, opts)
		s:SetPoint("TOPLEFT", x, y)
		return s
	end
	p.offset = Slider("Offset", 0, -124, { min = -40, max = 80, step = 1,
		onChange = function(v) AR.db.offset = v; Changed() end })
	p.offsetAlong = Slider("Offset along the frame", 200, -124, { min = -80, max = 80, step = 1,
		onChange = function(v) AR.db.offsetAlong = v; Changed() end })
	p.iconSize = Slider("Icon size", 0, -190, { min = 16, max = 48,
		onChange = function(v) AR.db.iconSize = v; Changed() end })
	p.spacing = Slider("Spacing", 200, -190, { min = 0, max = 12,
		onChange = function(v) AR.db.spacing = v; Changed() end })
	p.maxPerRow = Slider("Max icons per row", 0, -256, { min = 1, max = 12,
		onChange = function(v) AR.db.maxPerRow = v; Changed() end })

	-- a row without a frame to hang on: its direction, and dragging it while unlocked
	Skin.Field(p, "Grow", 0, -324)
	p.grow = Skin.Dropdown(p, 180, Items(GROWS), function(_, item)
		AR.db.grow = item.value
		Changed()
	end)
	p.grow:SetPoint("TOPLEFT", X, -324)
	Skin.Field(p, "Position", 0, -356)
	p.unlock = CK.Bind(Skin.Checkbox(p, "", function(checked)
		AR.SetLocked(not checked)
		O.Refresh()
	end), "Unlock")
	p.unlock:SetPoint("TOPLEFT", X, -357)
	local reset = CK.Bind(Skin.Button(p, "", 90, 20, function() AR.ResetPositions() end), "Reset position")
	reset:SetPoint("LEFT", p.unlock, "RIGHT", 16, 0)

	-- sample rows on screen right here, to see the look by the party frames or at the loose positions
	Skin.Field(p, "Test", 0, -388)
	p.test = CK.Bind(Skin.Checkbox(p, "", function(checked)
		AR.SetTest(checked)
		O.Refresh()
	end), "Show sample rows")
	p.test:SetPoint("TOPLEFT", X, -389)
end

local function Refresh(p)
	local db = AR.db
	p.showSelf:SetChecked(db.showSelf)
	p.externals:SetChecked(db.externals)
	p.attach:SetChecked(db.attach)
	p.offset:SetValue(db.offset)
	p.offsetAlong:SetValue(db.offsetAlong)
	p.iconSize:SetValue(db.iconSize)
	p.spacing:SetValue(db.spacing)
	p.maxPerRow:SetValue(db.maxPerRow)
	for _, s in ipairs(SIDES) do
		if s[1] == db.side then p.side:SetValueText(L[s[2]]) end
	end
	for _, g in ipairs(GROWS) do
		if g[1] == db.grow then p.grow:SetValueText(L[g[2]]) end
	end
	p.unlock:SetChecked(not AR.IsLocked())
	p.test:SetChecked(AR.IsTesting())
end

O.AddSection({
	key = "PartyCD",
	module = "PartyCD",
	order = 35,
	tab = function() return L["MOD_PartyCD"] end,
	GetNodes = function() return { { key = "arena", label = L["MOD_PartyCD"] } } end,
	GetHeader = function() return L["MOD_PartyCD"], L["MODDESC_PartyCD"] end,
	Build = function(p) AR = CK.modules.PartyCD; Build(p) end,
	Refresh = function(_, p) AR = CK.modules.PartyCD; Refresh(p) end,
	OnWindowHide = function()
		local module = CK.modules.PartyCD
		if module and not module.IsLocked() then module.SetLocked(true) end
		if module and module.IsTesting() then module.SetTest(false) end
	end,
})
