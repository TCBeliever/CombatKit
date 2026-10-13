local CK = CombatKit
local L, Skin, O = CK.L, CK.Skin, CK.Options

-- Settings page of the Arena module.

local X = O.FIELD_X + 20
local AR   -- the module, set whenever the section is used

local GROWS = { { "right", "Grow: right" }, { "down", "Grow: down" } }
local function GrowItems()
	local items = {}
	for _, g in ipairs(GROWS) do items[#items + 1] = { label = L[g[2]], value = g[1] } end
	return items
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

	local function Slider(key, x, y, opts)
		local s = Skin.Slider(p, key, opts)
		s:SetPoint("TOPLEFT", x, y)
		return s
	end
	p.iconSize = Slider("Icon size", 0, -58, { min = 16, max = 48,
		onChange = function(v) AR.db.iconSize = v; Changed() end })
	p.spacing = Slider("Spacing", 200, -58, { min = 0, max = 12,
		onChange = function(v) AR.db.spacing = v; Changed() end })

	Skin.Field(p, "Grow", 0, -126)
	p.grow = Skin.Dropdown(p, 180, GrowItems, function(_, item)
		AR.db.grow = item.value
		Changed()
	end)
	p.grow:SetPoint("TOPLEFT", X, -126)

	-- unlocked, the rows show sample icons and can be dragged; closing the window locks them again
	Skin.Field(p, "Position", 0, -158)
	p.unlock = CK.Bind(Skin.Checkbox(p, "", function(checked)
		AR.SetLocked(not checked)
		O.Refresh()
	end), "Unlock")
	p.unlock:SetPoint("TOPLEFT", X, -159)
	local reset = CK.Bind(Skin.Button(p, "", 90, 20, function() AR.ResetPositions() end), "Reset position")
	reset:SetPoint("LEFT", p.unlock, "RIGHT", 16, 0)
end

local function Refresh(p)
	local db = AR.db
	p.showSelf:SetChecked(db.showSelf)
	p.externals:SetChecked(db.externals)
	p.iconSize:SetValue(db.iconSize)
	p.spacing:SetValue(db.spacing)
	for _, g in ipairs(GROWS) do
		if g[1] == db.grow then p.grow:SetValueText(L[g[2]]) end
	end
	p.unlock:SetChecked(not AR.IsLocked())
end

O.AddSection({
	key = "Arena",
	module = "Arena",
	order = 35,
	tab = function() return L["MOD_Arena"] end,
	GetNodes = function() return { { key = "arena", label = L["MOD_Arena"] } } end,
	GetHeader = function() return L["MOD_Arena"], L["MODDESC_Arena"] end,
	Build = function(p) AR = CK.modules.Arena; Build(p) end,
	Refresh = function(_, p) AR = CK.modules.Arena; Refresh(p) end,
	OnWindowHide = function()
		local module = CK.modules.Arena
		if module and not module.IsLocked() then module.SetLocked(true) end
	end,
})
