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

local function Clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end

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

	local function Step(key, y, onStep)
		Skin.Field(p, key, 0, y)
		local s = Skin.Stepper(p, function(dir) onStep(dir); Changed() end)
		s:SetPoint("TOPLEFT", X, y)
		return s
	end
	p.fontSize = Step("Font size", -58, function(dir)
		RG.db.fontSize = Clamp(RG.db.fontSize + dir, 8, 40)
	end).value
	p.updateRate = Step("Update every", -114, function(dir)
		RG.db.updateRate = Clamp(math.floor((RG.db.updateRate + dir * 0.05) * 100 + 0.5) / 100, 0.05, 1)
	end).value
	local offsetX = Step("Mouseover offset", -142, function(dir)
		RG.db.units.mouseover.x = Clamp(RG.db.units.mouseover.x + dir * 5, -200, 200)
	end)
	p.offsetX = offsetX.value
	local offsetY = Skin.Stepper(p, function(dir)
		RG.db.units.mouseover.y = Clamp(RG.db.units.mouseover.y + dir * 5, -200, 200)
		Changed()
	end)
	offsetY:SetPoint("LEFT", offsetX, "RIGHT", 16, 0)
	p.offsetY = offsetY.value

	Skin.Field(p, "Font outline", 0, -86)
	p.outline = Skin.Dropdown(p, 180, OutlineItems, function(_, item)
		RG.db.fontOutline = item.value
		Changed()
	end)
	p.outline:SetPoint("TOPLEFT", X, -86)

	-- unlocked, the boxes show a sample number and can be dragged; closing the window locks them again
	Skin.Field(p, "Position", 0, -176)
	p.unlock = CK.Bind(Skin.Checkbox(p, "", function(checked)
		RG.SetLocked(not checked)
		O.Refresh()
	end), "Unlock")
	p.unlock:SetPoint("TOPLEFT", X, -177)
	local reset = CK.Bind(Skin.Button(p, "", 90, 20, function() RG.ResetPositions() end), "Reset position")
	reset:SetPoint("LEFT", p.unlock, "RIGHT", 16, 0)
end

local function Refresh(p)
	local db = RG.db
	for unit, c in pairs(p.units) do c:SetChecked(db.units[unit].enabled) end
	p.hideMelee:SetChecked(db.hideMelee)
	p.fontSize:SetText(tostring(db.fontSize))
	p.updateRate:SetText(string.format("%.2f s", db.updateRate))
	p.offsetX:SetText("X " .. db.units.mouseover.x)
	p.offsetY:SetText("Y " .. db.units.mouseover.y)
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
	GetHeader = function() return L["MOD_Range"], nil end,
	Build = function(p) RG = CK.modules.Range; Build(p) end,
	Refresh = function(_, p) RG = CK.modules.Range; Refresh(p) end,
	OnWindowHide = function()
		local module = CK.modules.Range
		if module and not module.IsLocked() then module.SetLocked(true) end
	end,
})
