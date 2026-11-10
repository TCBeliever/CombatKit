local CK = CombatKit
local L, Skin, O = CK.L, CK.Skin, CK.Options

-- Settings page of the Range module.

local X = O.FIELD_X + 20
local SLIDER_W = 300   -- a slider a line, this wide
local RG   -- the module, set whenever the section is used

local OUTLINES = { { "", "Outline: none" }, { "OUTLINE", "Outline: thin" }, { "THICKOUTLINE", "Outline: thick" } }
local function OutlineItems()
	local items = {}
	for _, o in ipairs(OUTLINES) do items[#items + 1] = { label = L[o[2]], value = o[1] } end
	return items
end

local function Changed()
	RG.Apply()
	O.Changed()
end

local function Build(p)
	-- a line each from the left edge, as OneClickFish lays them out (the units a set of check boxes); a slider a line, the
	-- mouseover's offsets under its switch, lined up with its label
	local y = 0
	local function Slider(key, x, opts)
		opts.width = SLIDER_W - x
		local s = Skin.Slider(p, key, opts)
		s:SetPoint("TOPLEFT", x, y)
		y = y - Skin.SLIDER_H - 10
		return s
	end
	-- first, since placing the boxes is what a new user does first: unlocked, the boxes show a sample
	-- number and can be dragged; closing the window locks them again
	Skin.Field(p, "Position", 0, y)
	p.unlock = CK.Bind(Skin.Switch(p, "", function(checked)
		RG.SetLocked(not checked)
		O.Refresh()
	end), "Unlock")
	p.unlock:SetPoint("TOPLEFT", X, y - 1)
	local reset = CK.Bind(Skin.Button(p, "", 90, 20, function() RG.ResetPositions() end), "Reset position")
	reset:SetPoint("LEFT", p.unlock, "RIGHT", 16, 0)
	y = y - 32 - 6

	p.units = {}
	for _, unit in ipairs(RG.UNITS) do
		local c = CK.Bind(Skin.Checkbox(p, "", function(checked)
			RG.db.units[unit].enabled = checked
			Changed()
		end), "RANGE_" .. unit)
		c:SetPoint("TOPLEFT", 0, y - 1)
		y = y - 26
		p.units[unit] = c
		if unit == "mouseover" then
			local x = Skin.CHECK_LABEL_X
			p.offsetX = Slider("Mouseover offset X", x, { min = -200, max = 200, step = 5,
				onChange = function(v) RG.db.units.mouseover.x = v; Changed() end })
			p.offsetY = Slider("Mouseover offset Y", x, { min = -200, max = 200, step = 5,
				onChange = function(v) RG.db.units.mouseover.y = v; Changed() end })
		end
	end

	p.hideMelee = CK.Bind(Skin.Switch(p, "", function(checked)
		RG.db.hideMelee = checked
		Changed()
	end), "Hide when 5 yards or closer")
	p.hideMelee:SetPoint("TOPLEFT", 0, y - 1)
	y = y - 26 - 10

	p.fontSize = Slider("Font size", 0, { min = 8, max = 40,
		onChange = function(v) RG.db.fontSize = v; Changed() end })
	p.updateRate = Slider("Update every", 0, { min = 0.05, max = 1, step = 0.05,
		format = function(v) return string.format("%.2f s", v) end,
		parse = function(t) return tonumber((t:gsub("s", ""):gsub("%s", ""))) end,
		onChange = function(v) RG.db.updateRate = v; Changed() end })
	y = y - 6

	Skin.Field(p, "Font outline", 0, y)
	p.outline = Skin.Dropdown(p, 180, OutlineItems, function(_, item)
		RG.db.fontOutline = item.value
		Changed()
	end)
	p.outline:SetPoint("TOPLEFT", X, y)

	-- the boxes switched on, with a sample number where they stand, without unlocking: a button by the page's title
	p.test = O.TitleButton(p, 70, function()
		RG.SetTesting(not RG.IsTesting())
		O.Refresh()
	end)
end

local function Refresh(p)
	local db = RG.db
	for unit, c in pairs(p.units) do c:SetChecked(db.units[unit].enabled) end
	p.hideMelee:SetChecked(db.hideMelee)
	p.fontSize:SetValue(db.fontSize)
	p.updateRate:SetValue(db.updateRate)
	p.offsetX:SetValue(db.units.mouseover.x)
	p.offsetY:SetValue(db.units.mouseover.y)
	for _, o in ipairs(OUTLINES) do
		if o[1] == (db.fontOutline or "") then p.outline:SetValueText(L[o[2]]) end
	end
	p.unlock:SetChecked(not RG.IsLocked())
	local testing = RG.IsTesting()
	p.test:SetLabel(L[testing and "Stop test" or "Test"])
	p.test:SetSelected(testing)
end

O.AddSection({
	key = "Range",
	module = "Range",
	order = 30,
	tab = function() return L["MOD_Range"] end,
	GetNodes = function() return { { key = "range", label = L["MOD_Range"] } } end,
	GetHeader = function() return L["MOD_Range"], L["MODDESC_Range"] end,
	Build = function(p) RG = CK.modules.Range; Build(p) end,
	Refresh = function(_, p) RG = CK.modules.Range; Refresh(p) end,
	OnWindowHide = function()
		local module = CK.modules.Range
		if module and not module.IsLocked() then module.SetLocked(true) end
		if module and module.IsTesting() then module.SetTesting(false) end
	end,
})
