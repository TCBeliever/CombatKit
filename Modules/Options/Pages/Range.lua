local CK = CombatKit
local L, Skin, O = CK.L, CK.Skin, CK.Options

-- Settings page of the Range module.

local X = O.FIELD_X + 20
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
	Skin.Field(p, "Show", 0, 0)
	p.units = {}
	local previous
	for _, unit in ipairs(RG.UNITS) do
		local c = CK.Bind(Skin.Checkbox(p, "", function(checked)
			RG.db.units[unit].enabled = checked
			Changed()
		end), "RANGE_" .. unit)
		if previous then c:SetPoint("LEFT", previous, "RIGHT", 16, 0) else c:SetPoint("TOPLEFT", X, -1) end
		previous = c
		p.units[unit] = c
	end

	p.hideMelee = CK.Bind(Skin.Checkbox(p, "", function(checked)
		RG.db.hideMelee = checked
		Changed()
	end), "Hide when 5 yards or closer")
	p.hideMelee:SetPoint("TOPLEFT", X, -27)

	local function Slider(key, x, y, opts)
		local s = Skin.Slider(p, key, opts)
		s:SetPoint("TOPLEFT", x, y)
		return s
	end
	p.fontSize = Slider("Font size", 0, -58, { min = 8, max = 40,
		onChange = function(v) RG.db.fontSize = v; Changed() end })
	p.updateRate = Slider("Update every", 200, -58, { min = 0.05, max = 1, step = 0.05,
		format = function(v) return string.format("%.2f s", v) end,
		parse = function(t) return tonumber((t:gsub("s", ""):gsub("%s", ""))) end,
		onChange = function(v) RG.db.updateRate = v; Changed() end })
	p.offsetX = Slider("Mouseover offset X", 0, -124, { min = -200, max = 200, step = 5,
		onChange = function(v) RG.db.units.mouseover.x = v; Changed() end })
	p.offsetY = Slider("Mouseover offset Y", 200, -124, { min = -200, max = 200, step = 5,
		onChange = function(v) RG.db.units.mouseover.y = v; Changed() end })

	Skin.Field(p, "Font outline", 0, -192)
	p.outline = Skin.Dropdown(p, 180, OutlineItems, function(_, item)
		RG.db.fontOutline = item.value
		Changed()
	end)
	p.outline:SetPoint("TOPLEFT", X, -192)

	-- unlocked, the boxes show a sample number and can be dragged; closing the window locks them again
	Skin.Field(p, "Position", 0, -224)
	p.unlock = CK.Bind(Skin.Checkbox(p, "", function(checked)
		RG.SetLocked(not checked)
		O.Refresh()
	end), "Unlock")
	p.unlock:SetPoint("TOPLEFT", X, -225)
	local reset = CK.Bind(Skin.Button(p, "", 90, 20, function() RG.ResetPositions() end), "Reset position")
	reset:SetPoint("LEFT", p.unlock, "RIGHT", 16, 0)
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
	end,
})
