local CK = CombatKit
local L, Skin, O = CK.L, CK.Skin, CK.Options

-- Settings of the Party CD module, three pages: the display, which spells
-- are watched (per class, in groups), and debug.

local X = O.FIELD_X + 20
local AR   -- the module, set whenever the section is used
local pages

local GROWS = { { "right", "Grow: right" }, { "down", "Grow: down" } }
local SIDES = { { "RIGHT", "Side: right" }, { "LEFT", "Side: left" }, { "TOP", "Side: above" }, { "BOTTOM", "Side: below" } }
local CLASSES = { "DEATHKNIGHT", "DEMONHUNTER", "DRUID", "EVOKER", "HUNTER", "MAGE", "MONK", "PALADIN", "PRIEST",
	"ROGUE", "SHAMAN", "WARLOCK", "WARRIOR" }
-- the groups a class's spells fall into, in page order; a kind without a key is not shown
local GROUPS = { { "self", "Defensives" }, { "external", "Externals (buffs put on an ally)" } }

local function Items(list)
	return function()
		local items = {}
		for _, g in ipairs(list) do items[#items + 1] = { label = L[g[2]], value = g[1] } end
		return items
	end
end

local function ClassName(class)
	return (LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[class]) or class
end

local function Changed()
	AR.Apply()
	O.Changed()
end

-- ---------------------------------------------------------------- the display
local function BuildMain(p)
	Skin.Field(p, "Show", 0, 0)
	p.externals = CK.Bind(Skin.Checkbox(p, "", function(checked)
		AR.db.externals = checked
		Changed()
	end), "Externals (buffs put on an ally)")
	p.externals:SetPoint("TOPLEFT", X, -1)
	p.trinket = CK.Bind(Skin.Checkbox(p, "", function(checked)
		AR.db.trinket = checked
		Changed()
	end), "The PvP trinket")
	p.trinket:SetPoint("TOPLEFT", X, -23)

	-- by the party frames: which side, how far, shifted along the edge
	Skin.Field(p, "Attach", 0, -54)
	p.attach = CK.Bind(Skin.Checkbox(p, "", function(checked)
		AR.db.attach = checked
		Changed()
	end), "Attach to party frames")
	p.attach:SetPoint("TOPLEFT", X, -55)
	Skin.Field(p, "Side", 0, -86)
	p.side = Skin.Dropdown(p, 180, Items(SIDES), function(_, item)
		AR.db.side = item.value
		Changed()
	end)
	p.side:SetPoint("TOPLEFT", X, -86)

	local function Slider(key, x, y, opts)
		local s = Skin.Slider(p, key, opts)
		s:SetPoint("TOPLEFT", x, y)
		return s
	end
	p.offset = Slider("Offset", 0, -120, { min = -40, max = 80, step = 1,
		onChange = function(v) AR.db.offset = v; Changed() end })
	p.offsetAlong = Slider("Offset along the frame", 200, -120, { min = -80, max = 80, step = 1,
		onChange = function(v) AR.db.offsetAlong = v; Changed() end })
	p.iconSize = Slider("Icon size", 0, -186, { min = 16, max = 48,
		onChange = function(v) AR.db.iconSize = v; Changed() end })
	p.spacing = Slider("Spacing", 200, -186, { min = 0, max = 12,
		onChange = function(v) AR.db.spacing = v; Changed() end })
	p.maxPerRow = Slider("Max icons per row", 0, -252, { min = 1, max = 12,
		onChange = function(v) AR.db.maxPerRow = v; Changed() end })

	-- a row without a frame to hang on: its direction, and dragging it while unlocked
	Skin.Field(p, "Grow", 0, -320)
	p.grow = Skin.Dropdown(p, 180, Items(GROWS), function(_, item)
		AR.db.grow = item.value
		Changed()
	end)
	p.grow:SetPoint("TOPLEFT", X, -320)
	Skin.Field(p, "Position", 0, -352)
	p.unlock = CK.Bind(Skin.Checkbox(p, "", function(checked)
		AR.SetLocked(not checked)
		O.Refresh()
	end), "Unlock")
	p.unlock:SetPoint("TOPLEFT", X, -353)
	local reset = CK.Bind(Skin.Button(p, "", 90, 20, function() AR.ResetPositions() end), "Reset position")
	reset:SetPoint("LEFT", p.unlock, "RIGHT", 16, 0)

	-- sample rows on screen right here, to see the look by the party frames or at the loose positions
	Skin.Field(p, "Test", 0, -384)
	p.test = CK.Bind(Skin.Checkbox(p, "", function(checked)
		AR.SetTest(checked)
		O.Refresh()
	end), "Show sample rows")
	p.test:SetPoint("TOPLEFT", X, -385)
end

local function RefreshMain(p)
	local db = AR.db
	p.externals:SetChecked(db.externals)
	p.trinket:SetChecked(db.trinket)
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

-- ---------------------------------------------------------------- the spells, per class
local function ClassItems()
	local items = {}
	for _, class in ipairs(CLASSES) do items[#items + 1] = { label = ClassName(class), value = class } end
	return items
end

-- one class's list: group headers, then a checkbox with the spell's icon and name per spell
local function ClassList(p, class)
	if p.lists[class] then return p.lists[class] end
	local list = CreateFrame("Frame", nil, p)
	list:SetPoint("TOPLEFT", 0, -34)
	list:SetPoint("BOTTOMRIGHT")
	list.checks = {}
	local y = 0
	for _, group in ipairs(GROUPS) do
		local kind, labelKey = group[1], group[2]
		local defs = {}
		for _, def in ipairs(AR.SPELLS[class] or {}) do
			if def.kind == kind then defs[#defs + 1] = def end
		end
		if #defs > 0 then
			Skin.Field(list, labelKey, 0, y)
			y = y - 24
			for _, def in ipairs(defs) do
				local c = Skin.Checkbox(list, C_Spell.GetSpellName(def.id) or tostring(def.id), function(checked)
					AR.db.disabled[def.id] = (not checked) and true or nil
					Changed()
				end)
				c:SetPoint("TOPLEFT", X + 22, y)
				c.icon = list:CreateTexture(nil, "ARTWORK")
				c.icon:SetSize(16, 16)
				c.icon:SetPoint("RIGHT", c, "LEFT", -4, 0)
				c.icon:SetTexture(C_Spell.GetSpellTexture(def.id))
				c.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
				c.def = def
				list.checks[#list.checks + 1] = c
				y = y - 22
			end
			y = y - 8
		end
	end
	list:Hide()
	p.lists[class] = list
	return list
end

local function BuildSpells(p)
	p.lists = {}
	local _, class = UnitClass("player")
	p.class = AR.SPELLS[class] and class or CLASSES[1]
	Skin.Field(p, "Class", 0, 0)
	p.picker = Skin.Dropdown(p, 180, ClassItems, function(_, item)
		p.class = item.value
		O.Refresh()
	end)
	p.picker:SetPoint("TOPLEFT", X, 0)
end

local function RefreshSpells(p)
	p.picker:SetValueText(ClassName(p.class))
	for class, list in pairs(p.lists) do list:SetShown(class == p.class) end
	local list = ClassList(p, p.class)
	list:Show()
	for _, c in ipairs(list.checks) do c:SetChecked(not AR.db.disabled[c.def.id]) end
end

-- ---------------------------------------------------------------- debug
local function BuildDebug(p)
	p.showSelf = CK.Bind(Skin.Checkbox(p, "", function(checked)
		AR.db.showSelf = checked
		Changed()
	end), "Show your own row")
	p.showSelf:SetPoint("TOPLEFT", X, -1)
	local status = CK.Bind(Skin.Button(p, "", 90, 20, function() SlashCmdList.CKPARTYCD("") end), "Status")
	status:SetPoint("TOPLEFT", X, -32)
	local log = CK.Bind(Skin.Button(p, "", 90, 20, function() SlashCmdList.CKPARTYCD("log") end), "Log")
	log:SetPoint("LEFT", status, "RIGHT", 8, 0)
	local clear = CK.Bind(Skin.Button(p, "", 90, 20, function() SlashCmdList.CKPARTYCD("clear") end), "Clear log")
	clear:SetPoint("LEFT", log, "RIGHT", 8, 0)
end

local function RefreshDebug(p)
	p.showSelf:SetChecked(AR.db.showSelf)
end

O.AddSection({
	key = "PartyCD",
	module = "PartyCD",
	order = 35,
	tab = function() return L["MOD_PartyCD"] end,
	GetNodes = function()
		return {
			{ key = "main", label = L["MOD_PartyCD"] },
			{ key = "spells", label = L["Spells"] },
			{ key = "debug", label = L["PAGE_debug"] },
		}
	end,
	GetHeader = function(node)
		if node == "spells" then return L["Spells"], L["PARTYCD_SPELLS_DESC"] end
		if node == "debug" then return L["PAGE_debug"], L["PARTYCD_DEBUG_DESC"] end
		return L["MOD_PartyCD"], L["MODDESC_PartyCD"]
	end,
	Build = function(body)
		AR = CK.modules.PartyCD
		pages = {}
		for _, key in ipairs({ "main", "spells", "debug" }) do
			local page = CreateFrame("Frame", nil, body)
			page:SetAllPoints()
			pages[key] = page
		end
		body.pages = pages
		BuildMain(pages.main)
		BuildSpells(pages.spells)
		BuildDebug(pages.debug)
	end,
	Refresh = function(node, body)
		AR = CK.modules.PartyCD
		local which = body.pages[node] and node or "main"
		for key, page in pairs(body.pages) do page:SetShown(key == which) end
		if which == "spells" then RefreshSpells(body.pages.spells)
		elseif which == "debug" then RefreshDebug(body.pages.debug)
		else RefreshMain(body.pages.main) end
	end,
	OnWindowHide = function()
		local module = CK.modules.PartyCD
		if module and not module.IsLocked() then module.SetLocked(true) end
		if module and module.IsTesting() then module.SetTest(false) end
	end,
})
