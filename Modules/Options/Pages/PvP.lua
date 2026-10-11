local CK = CombatKit
local L, Skin, O = CK.L, CK.Skin, CK.Options

-- Settings page of the PvP module (beta): what state the tracker is in, how
-- the icons look and where the rows go.

local X = O.FIELD_X + 20
local PV   -- the module, set whenever the section is used

local SIDES = { { "RIGHT", "Side: right" }, { "LEFT", "Side: left" } }
local function SideItems()
	local items = {}
	for _, s in ipairs(SIDES) do items[#items + 1] = { label = L[s[2]], value = s[1] } end
	return items
end

local function Changed()
	PV.Refresh()
	O.Changed()
end

local function Clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end

local function Build(p)
	p.note = CK.Bind(Skin.Label(p, "", nil, "dim"), "PVP_BETA_NOTE")
	p.note:SetPoint("TOPLEFT", 0, 0)
	p.note:SetWidth(O.PageWidth())
	p.note:SetJustifyH("LEFT")

	local y = -84
	Skin.Field(p, "Status", 0, y)
	p.state = Skin.Label(p, "")
	p.state:SetPoint("TOPLEFT", X, y)
	p.stats = Skin.Label(p, "", nil, "dim")
	p.stats:SetPoint("TOPLEFT", X, y - 16)

	local function Step(key, y2, onStep)
		Skin.Field(p, key, 0, y2)
		local s = Skin.Stepper(p, function(dir) onStep(dir); Changed() end)
		s:SetPoint("TOPLEFT", X, y2)
		return s
	end
	y = -124
	p.iconSize = Step("Icon size", y, function(dir)
		PV.db.iconSize = Clamp(PV.db.iconSize + dir * 2, 12, 64)
	end).value
	p.spacing = Step("Spacing", y - 28, function(dir)
		PV.db.spacing = Clamp(PV.db.spacing + dir, 0, 20)
	end).value
	local RIGHT = X + 130
	Skin.Field(p, "Font size", RIGHT, y)
	local fontSize = Skin.Stepper(p, function(dir)
		PV.db.fontSize = Clamp(PV.db.fontSize + dir, 8, 32)
		Changed()
	end)
	fontSize:SetPoint("TOPLEFT", RIGHT + 90, y)
	p.fontSize = fontSize.value
	Skin.Field(p, "Max per row", RIGHT, y - 28)
	local perRow = Skin.Stepper(p, function(dir)
		PV.db.maxPerRow = Clamp(PV.db.maxPerRow + dir, 1, 12)
		Changed()
	end)
	perRow:SetPoint("TOPLEFT", RIGHT + 90, y - 28)
	p.maxPerRow = perRow.value

	Skin.Field(p, "Side", 0, y - 56)
	p.side = Skin.Dropdown(p, 180, SideItems, function(_, item)
		PV.db.side = item.value
		Changed()
	end)
	p.side:SetPoint("TOPLEFT", X, y - 56)

	local offsetX = Step("Offset", y - 84, function(dir)
		PV.db.offset = Clamp(PV.db.offset + dir, -100, 100)
	end)
	p.offsetX = offsetX.value
	local offsetY = Skin.Stepper(p, function(dir)
		PV.db.offsetY = Clamp(PV.db.offsetY + dir, -100, 100)
		Changed()
	end)
	offsetY:SetPoint("LEFT", offsetX, "RIGHT", 16, 0)
	p.offsetY = offsetY.value

	Skin.Field(p, "Show", 0, y - 116)
	p.timer = CK.Bind(Skin.Checkbox(p, "", function(checked)
		PV.db.showTimer = checked
		Changed()
	end), "Remaining time")
	p.timer:SetPoint("TOPLEFT", X, y - 117)
	p.glow = CK.Bind(Skin.Checkbox(p, "", function(checked)
		PV.db.glow = checked
		Changed()
	end), "Highlight while the buff is up")
	p.glow:SetPoint("LEFT", p.timer, "RIGHT", 16, 0)
	p.offensive = CK.Bind(Skin.Checkbox(p, "", function(checked)
		PV.db.showOffensive = checked
		Changed()
	end), "Burst cooldowns")
	p.offensive:SetPoint("LEFT", p.glow, "RIGHT", 16, 0)
	p.cc = CK.Bind(Skin.Checkbox(p, "", function(checked)
		PV.db.showCC = checked
		Changed()
	end), "Crowd control")
	p.cc:SetPoint("TOPLEFT", X, y - 141)

	-- sample rows to look at outside arena; unlocked, a row without a party frame can be dragged
	Skin.Field(p, "Position", 0, y - 172)
	p.test = CK.Bind(Skin.Checkbox(p, "", function(checked)
		PV.Display.SetTesting(checked)
		O.Refresh()
	end), "Show sample rows")
	p.test:SetPoint("TOPLEFT", X, y - 173)
	p.solo = CK.Bind(Skin.Checkbox(p, "", function(checked)
		PV.SetSolo(checked)
		O.Refresh()
	end), "Solo mode")
	p.solo:SetPoint("TOPLEFT", X, y - 199)
	Skin.Tooltip(p.solo, "Solo mode", "SOLO_TIP")
	p.unlock = CK.Bind(Skin.Checkbox(p, "", function(checked)
		PV.Display.SetLocked(not checked)
		O.Refresh()
	end), "Unlock")
	p.unlock:SetPoint("LEFT", p.test, "RIGHT", 16, 0)
	local reset = CK.Bind(Skin.Button(p, "", 90, 20, function() PV.Display.ResetPositions() end), "Reset position")
	reset:SetPoint("LEFT", p.unlock, "RIGHT", 16, 0)
end

local function Refresh(p)
	local db = PV.db
	local state, reason = PV.State()
	local colour = (state == "unavailable" or state == "paused") and "bad" or (state == "scanning" and "ok" or "text")
	local text = Skin.Text(colour, L["PVP_STATE_" .. state])
	if reason then text = text .. " " .. Skin.Text("dim", reason) end
	p.state:SetText(text)
	local s = PV.Stats()
	p.stats:SetText(string.format(L["PVP_STATS"], s.scans, s.positives, s.invalid))
	p.iconSize:SetText(tostring(db.iconSize))
	p.spacing:SetText(tostring(db.spacing))
	p.fontSize:SetText(tostring(db.fontSize))
	p.maxPerRow:SetText(tostring(db.maxPerRow))
	for _, side in ipairs(SIDES) do
		if side[1] == db.side then p.side:SetValueText(L[side[2]]) end
	end
	p.offsetX:SetText("X " .. db.offset)
	p.offsetY:SetText("Y " .. db.offsetY)
	p.timer:SetChecked(db.showTimer)
	p.glow:SetChecked(db.glow)
	p.offensive:SetChecked(db.showOffensive ~= false)
	p.cc:SetChecked(db.showCC ~= false)
	p.solo:SetChecked(PV.IsSolo())
	p.test:SetChecked(PV.Display.IsTesting())
	p.unlock:SetChecked(not PV.Display.IsLocked())
end

O.AddSection({
	key = "PvP",
	module = "PvP",
	order = 35,
	tab = function() return L["MOD_PvP"] end,
	GetNodes = function() return { { key = "pvp", label = L["MOD_PvP"] } } end,
	GetHeader = function() return L["MOD_PvP"], L["MODDESC_PvP"] end,
	Build = function(p) PV = CK.modules.PvP; Build(p) end,
	Refresh = function(_, p) PV = CK.modules.PvP; Refresh(p) end,
	OnWindowHide = function()
		local module = CK.modules.PvP
		if not module then return end
		if module.Display.IsTesting() then module.Display.SetTesting(false) end
		if not module.Display.IsLocked() then module.Display.SetLocked(true) end
	end,
})
