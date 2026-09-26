local CK = CombatKit
local L, Skin, O = CK.L, CK.Skin, CK.Options

-- The small features. One that has settings gets a page: its switch, and below
-- it the settings, which wait for the switch (the features' addon is only in
-- memory while at least one of them is on). Those that are nothing but a switch
-- share the last page, "Misc".

local X = O.FIELD_X + 20
local HAS_PAGE = { CombatAlert = true }
local MI        -- the module; nil while no feature is on
local current   -- the feature whose page is open

-- What the state of a feature adds to its check box, if anything.
local function StateText(feature, on)
	if CK.GetModuleState("Misc") == "missing" then
		return Skin.Text("bad", L["STATE_missing"])
	elseif MI and MI.GetFeatureState(feature) == "waiting" then
		return Skin.Text("warn", L["STATE_waiting"])   -- a secure feature, switched in combat
	elseif not on and CK.GetModuleState("Misc") == "stale" then
		return Skin.Text("warn", L["STATE_stale"])     -- the last feature went off: its code leaves with a reload
	end
	return ""
end

local function Changed()
	MI.ApplyAlert()
	if MI.IsAlertTesting() then MI.SetAlertTesting(true) end   -- repaint the sample
	O.Changed()
end

local function BuildAlert(p, a)
	local function Text(key, which, y)
		Skin.Field(a, key, 0, y)
		local e = Skin.EditBox(a, 240, function(text)
			MI.AlertSettings()[which .. "Text"] = (text ~= "" and text ~= MI.ALERT_TEXT[which]) and text or nil
			Changed()
		end)
		e:SetPoint("TOPLEFT", X, y)
		return e
	end
	p.enter = Text("Text on entering", "enter", 0)
	p.leave = Text("Text on leaving", "leave", -28)

	Skin.Field(a, "Font size", 0, -60)
	local size = Skin.Stepper(a, function(dir)
		local s = MI.AlertSettings()
		s.fontSize = math.max(8, math.min(48, s.fontSize + dir))
		Changed()
	end)
	size:SetPoint("TOPLEFT", X, -60)
	p.fontSize = size.value

	Skin.Field(a, "Effect", 0, -92)
	p.rise = CK.Bind(Skin.Checkbox(a, "", function(checked)
		MI.AlertSettings().rise = checked and true or false
		Changed()
	end), "Float up")
	p.rise:SetPoint("TOPLEFT", X, -93)

	-- while ticked the text stays on screen and can be dragged; closing the window ends it
	Skin.Field(a, "Position", 0, -124)
	p.test = CK.Bind(Skin.Checkbox(a, "", function(checked)
		MI.SetAlertTesting(checked)
		O.Refresh()
	end), "Unlock")
	p.test:SetPoint("TOPLEFT", X, -125)
	local reset = CK.Bind(Skin.Button(a, "", 90, 20, function() MI.ResetAlertPosition() end), "Reset position")
	reset:SetPoint("LEFT", p.test, "RIGHT", 16, 0)

	-- see it as it will appear: entering, the next click leaving, and so on
	local which = "enter"
	p.play = CK.Bind(Skin.Button(a, "", 90, 20, function()
		if MI.IsAlertTesting() then MI.SetAlertTesting(false) end   -- the sample for dragging is in the way
		MI.ShowAlert(which)
		which = (which == "enter") and "leave" or "enter"
		O.Refresh()
	end), "Test")
	p.play:SetPoint("TOPLEFT", X, -156)
end

local function Build(p)
	p.enable = CK.Bind(Skin.Checkbox(p, "", function(checked)
		CK.SetFeatureEnabled("Misc", current, checked)   -- refreshes the window
	end), "Enable")
	p.enable:SetPoint("TOPLEFT", 0, 0)
	p.state = Skin.Label(p, "")
	p.state:SetPoint("LEFT", p.enable, "RIGHT", 10, 0)

	p.alert = CreateFrame("Frame", nil, p)
	p.alert:SetPoint("TOPLEFT", 0, -34)
	p.alert:SetPoint("BOTTOMRIGHT")
	BuildAlert(p, p.alert)

	-- "Misc": a switch and a line of explanation per feature, one under the other
	p.misc = CreateFrame("Frame", nil, p)
	p.misc:SetAllPoints()
	p.simple = {}
	local above
	for _, feature in ipairs(CK.MODULE_BY_NAME.Misc.features) do
		if not HAS_PAGE[feature] then
			local row = { feature = feature }
			row.check = CK.Bind(Skin.Checkbox(p.misc, "", function(checked)
				CK.SetFeatureEnabled("Misc", feature, checked)   -- refreshes the window
			end), "FEAT_" .. feature)
			if above then
				row.check:SetPoint("TOPLEFT", above, "BOTTOMLEFT", -20, -12)
			else
				row.check:SetPoint("TOPLEFT", 0, 0)
			end
			row.state = Skin.Label(p.misc, "")
			row.state:SetPoint("LEFT", row.check, "RIGHT", 10, 0)
			row.desc = CK.Bind(Skin.Label(p.misc, "", nil, "dim"), "FEATDESC_" .. feature)
			row.desc:SetPoint("TOPLEFT", row.check, "BOTTOMLEFT", 20, -3)
			row.desc:SetWidth(O.RIGHT_W - 20)
			row.desc:SetJustifyH("LEFT")
			p.simple[#p.simple + 1] = row
			p.simple[feature] = row
			above = row.desc
		end
	end
end

local function Refresh(node, p)
	MI = CK.modules.Misc
	local misc = node == "misc"
	p.misc:SetShown(misc)
	p.enable:SetShown(not misc)
	p.state:SetShown(not misc)
	if misc then
		current = nil
		p.alert:Hide()
		for _, row in ipairs(p.simple) do
			local on = CK.IsFeatureEnabled("Misc", row.feature)
			row.check:SetChecked(on)
			row.state:SetText(StateText(row.feature, on))
		end
		return
	end

	current = node
	local on = CK.IsFeatureEnabled("Misc", node)
	p.enable:SetChecked(on)
	p.state:SetText(StateText(node, on))

	local showAlert = node == "CombatAlert" and on and MI ~= nil and MI.enabled
	p.alert:SetShown(showAlert and true or false)
	if not showAlert then return end
	p.enter:SetText(MI.AlertText("enter"))
	p.leave:SetText(MI.AlertText("leave"))
	p.fontSize:SetText(tostring(MI.AlertSettings().fontSize))
	p.rise:SetChecked(MI.AlertSettings().rise)
	p.test:SetChecked(MI.IsAlertTesting())
end

O.AddSection({
	key = "Misc",
	order = 40,
	tab = function() return L["MOD_Misc"] end,
	dimmed = function() return not CK.IsModuleEnabled("Misc") end,
	GetNodes = function()
		local nodes, anySimpleOn = {}, false
		for _, feature in ipairs(CK.MODULE_BY_NAME.Misc.features) do
			local on = CK.IsFeatureEnabled("Misc", feature)
			if HAS_PAGE[feature] then
				nodes[#nodes + 1] = { key = feature, label = L["FEAT_" .. feature], here = on }
			elseif on then
				anySimpleOn = true
			end
		end
		nodes[#nodes + 1] = { key = "misc", label = L["Misc"], here = anySimpleOn }
		return nodes
	end,
	GetHeader = function(node)
		if node == "misc" then return L["Misc"], nil end
		return L["FEAT_" .. node], L["FEATDESC_" .. node]
	end,
	Build = Build,
	Refresh = Refresh,
	OnWindowHide = function()
		local module = CK.modules.Misc
		if module and module.IsAlertTesting() then module.SetAlertTesting(false) end
	end,
})
