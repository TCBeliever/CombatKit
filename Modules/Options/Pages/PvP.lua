local CK = CombatKit
local L, Skin, O = CK.L, CK.Skin, CK.Options

-- Settings of the PvP module (beta), two pages: the icons (how they look, where
-- the rows go, below a divider the debug corner), and Monitoring (what is
-- tracked: the trinket, the roles, and every ability of a class as a switch).

local X = O.FIELD_X + 20
local PV   -- the module, set whenever the section is used

local SIDES = { { "RIGHT", "Side: right" }, { "LEFT", "Side: left" }, { "TOP", "Side: top" }, { "BOTTOM", "Side: bottom" } }
local function SideItems()
	local items = {}
	for _, s in ipairs(SIDES) do items[#items + 1] = { label = L[s[2]], value = s[1] } end
	return items
end

local CLASSES = { "DEATHKNIGHT", "DEMONHUNTER", "DRUID", "EVOKER", "HUNTER", "MAGE", "MONK", "PALADIN", "PRIEST",
	"ROGUE", "SHAMAN", "WARLOCK", "WARRIOR" }
local function ClassName(token)
	local names = LOCALIZED_CLASS_NAMES_MALE
	return (type(names) == "table" and names[token]) or token
end
local function ClassItems()
	local items = {}
	for _, token in ipairs(CLASSES) do items[#items + 1] = { label = ClassName(token), value = token } end
	return items
end

local function Changed()
	PV.Refresh()
	O.Changed()
end

-- what is tracked changed: the entries again, then the window
local function Retrack()
	PV.RebuildEntries()
	O.Changed()
end

-- ---------------------------------------------------------------------------
-- The icons
-- ---------------------------------------------------------------------------

local function BuildIcons(p)
	local function Slider(key, x, y, opts)
		opts.width = 140
		local s = Skin.Slider(p, key, opts)
		s:SetPoint("TOPLEFT", x, y)
		return s
	end
	local function Check(key, y, onChange)
		local c = CK.Bind(Skin.Checkbox(p, "", onChange), key)
		c:SetPoint("TOPLEFT", X, y - 1)
		return c
	end
	local COL = 152

	local y = 0
	p.iconSize = Slider("Icon size", 0, y, { min = 12, max = 64, step = 2, onChange = function(v) PV.db.iconSize = v; Changed() end })
	p.fontSize = Slider("Countdown size", COL, y, { min = 8, max = 32, onChange = function(v) PV.db.fontSize = v; Changed() end })
	p.spacing = Slider("Spacing", COL * 2, y, { min = 0, max = 20, onChange = function(v) PV.db.spacing = v; Changed() end })
	p.maxPerRow = Slider("Max icons per row", COL * 3, y, { min = 1, max = 12, onChange = function(v) PV.db.maxPerRow = v; Changed() end })

	-- where the rows go
	y = -(Skin.SLIDER_H + 8)
	p.offsetX = Slider("Horizontal offset", 0, y, { min = -100, max = 100, onChange = function(v) PV.db.offset = v; Changed() end })
	p.offsetY = Slider("Vertical offset", COL, y, { min = -100, max = 100, onChange = function(v) PV.db.offsetY = v; Changed() end })
	-- the side, laid out like the sliders beside it: its name above, the control under
	Skin.Field(p, "Side", COL * 2, y + 4)
	p.side = Skin.Dropdown(p, 150, SideItems, function(_, item)
		PV.db.side = item.value
		Changed()
	end)
	p.side:SetPoint("TOPLEFT", COL * 2, y - 17)
	-- off: the rows stay where they were dragged to (Unlock), whatever frames there are
	p.attach = CK.Bind(Skin.Checkbox(p, "", function(checked)
		PV.db.attach = checked
		Changed()
	end), "Attach to party frames")
	p.attach:SetPoint("TOPLEFT", COL * 2, y - 42)

	-- what the icons show
	y = -(Skin.SLIDER_H * 2 + 24)
	Skin.Field(p, "Display", 0, y)
	p.timer = Check("Countdown", y, function(checked) PV.db.showTimer = checked; Changed() end)
	p.glow = CK.Bind(Skin.Checkbox(p, "", function(checked) PV.db.glow = checked; Changed() end), "Glow while active")
	p.glow:SetPoint("TOPLEFT", X + 200, y - 1)

	-- sample rows to look at outside arena; unlocked, a row off its frame can be dragged
	y = -(Skin.SLIDER_H * 2 + 56)
	Skin.Field(p, "Layout", 0, y)
	p.test = Check("Test icons", y, function(checked)
		PV.Display.SetTesting(checked)
		O.Refresh()
	end)
	p.unlock = CK.Bind(Skin.Checkbox(p, "", function(checked)
		PV.Display.SetLocked(not checked)
		O.Refresh()
	end), "Unlock")
	p.unlock:SetPoint("LEFT", p.test, "RIGHT", 16, 0)
	local reset = CK.Bind(Skin.Button(p, "", 90, 20, function() PV.Display.ResetPositions() end), "Reset position")
	reset:SetPoint("LEFT", p.unlock, "RIGHT", 16, 0)

	-- the debug corner, under a line with its name on it
	y = -(Skin.SLIDER_H * 2 + 102)
	local line = Skin.Fill(p, "ARTWORK", "border")
	line:SetPoint("TOPLEFT", 0, y)
	line:SetPoint("TOPRIGHT", 0, y)
	line:SetHeight(1)
	p.debugTitle = Skin.Label(p, "debug", nil, "dim")
	p.debugTitle:SetPoint("TOP", p, "TOP", 0, y + 7)
	p.debugTitle:SetDrawLayer("OVERLAY", 7)
	local cover = Skin.Fill(p, "OVERLAY", "bg")
	cover:SetPoint("TOPLEFT", p.debugTitle, "TOPLEFT", -6, 0)
	cover:SetPoint("BOTTOMRIGHT", p.debugTitle, "BOTTOMRIGHT", 6, 0)

	y = y - 24
	Skin.Field(p, "Status", 0, y)
	p.state = Skin.Label(p, "")
	p.state:SetPoint("TOPLEFT", X, y)
	p.stats = Skin.Label(p, "", nil, "dim")
	p.stats:SetPoint("TOPLEFT", X, y - 16)
	p.solo = Check("Solo mode", y - 44, function(checked)
		PV.SetSolo(checked)
		O.Refresh()
	end)
	Skin.Tooltip(p.solo, "Solo mode", "SOLO_TIP")
end

local function RefreshIcons(p)
	local db = PV.db
	local state, reason = PV.State()
	local colour = (state == "unavailable" or state == "paused") and "bad" or (state == "scanning" and "ok" or "text")
	local text = Skin.Text(colour, L["PVP_STATE_" .. state])
	if reason then text = text .. " " .. Skin.Text("dim", reason) end
	p.state:SetText(text)
	local s = PV.Stats()
	p.stats:SetText(string.format(L["PVP_STATS"], s.scans, s.positives, s.invalid))
	p.iconSize:SetValue(db.iconSize)
	p.spacing:SetValue(db.spacing)
	p.fontSize:SetValue(db.fontSize)
	p.maxPerRow:SetValue(db.maxPerRow)
	for _, side in ipairs(SIDES) do
		if side[1] == db.side then p.side:SetValueText(L[side[2]]) end
	end
	p.attach:SetChecked(db.attach ~= false)
	p.offsetX:SetValue(db.offset)
	p.offsetY:SetValue(db.offsetY)
	p.timer:SetChecked(db.showTimer)
	p.glow:SetChecked(db.glow)
	p.test:SetChecked(PV.Display.IsTesting())
	p.unlock:SetChecked(not PV.Display.IsLocked())
	p.solo:SetChecked(PV.IsSolo())
end

-- ---------------------------------------------------------------------------
-- Monitoring: what is tracked
-- ---------------------------------------------------------------------------

local ROW_H = 22

local function AbilityLabel(a)
	local name = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(a.id)
	if type(name) ~= "string" or not canaccessvalue(name) or name == "" then name = a.name end
	local role = a.role == "cc" and L["Crowd control"] or (a.role == "offensive" and L["Offensive cooldowns"] or L["Defensive"])
	return name .. "  " .. Skin.Text("dim", string.format("%s · %ds", role, a.cd))
end

local function BuildWatch(p)
	local function Check(key, x, y, onChange)
		local c = CK.Bind(Skin.Checkbox(p, "", onChange), key)
		c:SetPoint("TOPLEFT", x, y - 1)
		return c
	end
	Skin.Field(p, "Track", 0, 0)
	p.trinket = Check("PvP trinket", X, 0, function(checked) PV.db.showTrinket = checked; Retrack() end)
	p.offensive = Check("Offensive cooldowns", X + 150, 0, function(checked) PV.db.showOffensive = checked; Retrack() end)
	p.cc = Check("Crowd control", X + 330, 0, function(checked) PV.db.showCC = checked; Retrack() end)

	-- one class at a time: its abilities, each a switch
	Skin.Field(p, "Class", 0, -34)
	p.class = CLASSES[1]
	local _, own = UnitClass("player")
	if type(own) == "string" then p.class = own end
	p.classDrop = Skin.Dropdown(p, 180, ClassItems, function(_, item)
		p.class = item.value
		O.Refresh()
	end)
	p.classDrop:SetPoint("TOPLEFT", X, -34)
	Skin.Field(p, "Abilities", 0, -66)
	p.abilities = {}
end

local function RefreshWatch(p)
	local db = PV.db
	p.trinket:SetChecked(db.showTrinket ~= false)
	p.offensive:SetChecked(db.showOffensive ~= false)
	p.cc:SetChecked(db.showCC ~= false)
	p.classDrop:SetValueText(ClassName(p.class))
	local list = PV.Spells.BY_CLASS[p.class] or {}
	local half = math.ceil(#list / 2)
	for i, a in ipairs(list) do
		local c = p.abilities[i]
		if not c then
			c = Skin.Checkbox(p, "", function(checked)
				if checked then db.disabled[c.id] = nil else db.disabled[c.id] = true end
				Retrack()
			end)
			p.abilities[i] = c
		end
		c.id = a.id
		c:SetLabel(AbilityLabel(a))
		c:SetChecked(not db.disabled[a.id])
		c:ClearAllPoints()
		local col, line = (i > half) and 1 or 0, (i > half) and (i - half - 1) or (i - 1)
		c:SetPoint("TOPLEFT", X + col * 300, -66 - line * ROW_H)
		c:Show()
	end
	for i = #list + 1, #p.abilities do p.abilities[i]:Hide() end
end

-- ---------------------------------------------------------------------------
-- The section
-- ---------------------------------------------------------------------------

O.AddSection({
	key = "PvP",
	module = "PvP",
	order = 35,
	tab = function() return L["MOD_PvP"] end,
	GetNodes = function()
		return { { key = "pvp", label = L["MOD_PvP"] }, { key = "watch", label = L["Monitoring"] } }
	end,
	GetHeader = function(node)
		if node == "watch" then return L["Monitoring"], nil end
		return "arena party CD " .. Skin.Text("accent", "beta"), L["MODDESC_PvP"]
	end,
	Build = function(body)
		PV = CK.modules.PvP
		body.pages = {}
		for _, key in ipairs({ "pvp", "watch" }) do
			local page = CreateFrame("Frame", nil, body)
			page:SetAllPoints()
			body.pages[key] = page
		end
		BuildIcons(body.pages.pvp)
		BuildWatch(body.pages.watch)
		-- the controls by name on the body too, whichever page holds them (the tests look there)
		for _, key in ipairs({ "iconSize", "fontSize", "spacing", "maxPerRow", "offsetX", "offsetY", "side", "attach",
			"timer", "glow", "test", "unlock", "state", "stats", "solo" }) do body[key] = body.pages.pvp[key] end
		for _, key in ipairs({ "trinket", "offensive", "cc", "classDrop" }) do body[key] = body.pages.watch[key] end
		body.classPick = function(token) body.pages.watch.class = token; O.Refresh() end
	end,
	Refresh = function(node, body)
		PV = CK.modules.PvP
		for key, page in pairs(body.pages) do page:SetShown(key == node) end
		if node == "watch" then RefreshWatch(body.pages.watch) else RefreshIcons(body.pages.pvp) end
		-- the lists read by the tests stay current whichever page is up
		if node ~= "watch" then RefreshWatch(body.pages.watch) end
	end,
	OnWindowHide = function()
		local module = CK.modules.PvP
		if not module then return end
		if module.Display.IsTesting() then module.Display.SetTesting(false) end
		if not module.Display.IsLocked() then module.Display.SetLocked(true) end
	end,
})
