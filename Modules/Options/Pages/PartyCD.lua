local CK = CombatKit
local L, Skin, O = CK.L, CK.Skin, CK.Options

-- Settings of the Party CD module, three pages: the display, which spells
-- are watched (per class, in groups), and debug.

local X = O.FIELD_X + 20
local AR   -- the module, set whenever the section is used
local pages

-- how the lines line up, by the side: up, down or centred by the frame's
-- left or right, left, right or centred above or below it
local GROWS = { { "up", "Grow: up" }, { "down", "Grow: down" }, { "left", "Grow: left" }, { "right", "Grow: right" },
	{ "center", "Grow: center" } }
local GROWS_BY_SIDE = {
	RIGHT = { "down", "up", "center" }, LEFT = { "down", "up", "center" },
	TOP = { "right", "left", "center" }, BOTTOM = { "right", "left", "center" },
}
local GROW_LABEL = {}
for _, g in ipairs(GROWS) do GROW_LABEL[g[1]] = g[2] end

local function GrowItems()
	local items = {}
	for _, key in ipairs(GROWS_BY_SIDE[AR.db.side] or GROWS_BY_SIDE.RIGHT) do
		items[#items + 1] = { label = L[GROW_LABEL[key]], value = key }
	end
	return items
end
local SIDES = { { "RIGHT", "Side: right" }, { "LEFT", "Side: left" }, { "TOP", "Side: above" }, { "BOTTOM", "Side: below" } }
local CLASSES = { "DEATHKNIGHT", "DEMONHUNTER", "DRUID", "EVOKER", "HUNTER", "MAGE", "MONK", "PALADIN", "PRIEST",
	"ROGUE", "SHAMAN", "WARLOCK", "WARRIOR" }

local function Items(list)
	return function()
		local items = {}
		for _, g in ipairs(list) do items[#items + 1] = { label = L[g[2]], value = g[1] } end
		return items
	end
end

local RACIAL = "RACIAL"   -- the picker's last entry: every racial ability

local function ClassName(class)
	if class == RACIAL then return L["Racial"] end
	return (LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[class]) or class
end

-- the abilities the page lists for the picker's choice
local function ListFor(class)
	if class == RACIAL then return AR.RACIAL_LIST end
	return AR.SPELLS[class] or {}
end

local function Changed()
	AR.Apply()
	O.Changed()
end

local MEDALLION = 336126   -- Gladiator's Medallion: the PvP trinket's icon

-- a spell's icon between a check box and its name; the click area takes the
-- icon in, whatever the label (a language change sets it again)
local function WithIcon(c)
	c.icon = c:CreateTexture(nil, "ARTWORK")
	c.icon:SetSize(16, 16)
	c.icon:SetPoint("LEFT", c.box, "RIGHT", 6, 0)
	c.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	c.label:ClearAllPoints()
	c.label:SetPoint("LEFT", c.icon, "RIGHT", 6, 0)
	local SetLabel = c.SetLabel
	function c:SetLabel(label)
		SetLabel(self, label)
		self:SetWidth(self:GetWidth() + 22)
	end
	c:SetLabel(c.label:GetText())
	return c
end

-- ---------------------------------------------------------------- the display
local function BuildMain(p)
	Skin.Field(p, "Show", 0, 0)
	p.trinket = CK.Bind(WithIcon(Skin.Checkbox(p, "", function(checked)
		AR.db.trinket = checked
		Changed()
	end)), "The PvP trinket")
	p.trinket.icon:SetTexture(C_Spell.GetSpellTexture(MEDALLION) or 134400)
	p.trinket:SetPoint("TOPLEFT", X, -1)

	-- by the party frames: which side, how far, shifted along the edge
	Skin.Field(p, "Attach", 0, -26)
	p.attach = CK.Bind(Skin.Checkbox(p, "", function(checked)
		AR.db.attach = checked
		Changed()
	end), "Attach to party frames")
	p.attach:SetPoint("TOPLEFT", X, -27)
	-- the side and how the lines line up go together: the second follows the first
	Skin.Field(p, "Side", 0, -50)
	p.side = Skin.Dropdown(p, 100, Items(SIDES), function(_, item)
		AR.db.side = item.value
		AR.db.grow = AR.UI.GrowFor(item.value, AR.db.grow)
		Changed()
		O.Refresh()
	end)
	p.side:SetPoint("TOPLEFT", X, -50)
	p.growLabel = Skin.Field(p, "Grow", X + 116, -50)
	p.grow = Skin.Dropdown(p, 100, GrowItems, function(_, item)
		AR.db.grow = item.value
		Changed()
	end)
	p.grow:SetPoint("TOPLEFT", p.growLabel, "TOPRIGHT", 10, 4)

	-- the numbers, three to a line
	local COL, SW = 150, 130
	local function Slider(key, x, y, opts)
		opts.width = SW
		local s = Skin.Slider(p, key, opts)
		s:SetPoint("TOPLEFT", x, y)
		return s
	end
	local row1 = -78
	local row2 = row1 - Skin.SLIDER_H - 6
	p.offset = Slider("Offset", 0, row1, { min = -40, max = 80, step = 1,
		onChange = function(v) AR.db.offset = v; Changed() end })
	p.offsetAlong = Slider("Offset along the frame", COL, row1, { min = -80, max = 80, step = 1,
		onChange = function(v) AR.db.offsetAlong = v; Changed() end })
	p.iconSize = Slider("Icon size", COL * 2, row1, { min = 16, max = 48,
		onChange = function(v) AR.db.iconSize = v; Changed() end })
	p.spacing = Slider("Spacing", 0, row2, { min = 0, max = 12,
		onChange = function(v) AR.db.spacing = v; Changed() end })
	p.maxPerRow = Slider("Max icons per row", COL, row2, { min = 1, max = 12,
		onChange = function(v) AR.db.maxPerRow = v; Changed() end })

	-- a row without a frame to hang on: dragging it while unlocked
	local y = row2 - Skin.SLIDER_H - 6
	Skin.Field(p, "Position", 0, y)
	p.unlock = CK.Bind(Skin.Checkbox(p, "", function(checked)
		AR.SetLocked(not checked)
		O.Refresh()
	end), "Unlock")
	p.unlock:SetPoint("TOPLEFT", X, y - 1)
	local reset = CK.Bind(Skin.Button(p, "", 90, 20, function() AR.ResetPositions() end), "Reset position")
	reset:SetPoint("LEFT", p.unlock, "RIGHT", 16, 0)

	-- sample rows on screen right here, to see the look by the party frames or at the loose positions
	y = y - 24
	Skin.Field(p, "Test", 0, y)
	p.test = CK.Bind(Skin.Checkbox(p, "", function(checked)
		AR.SetTest(checked)
		O.Refresh()
	end), "Show sample rows")
	p.test:SetPoint("TOPLEFT", X, y - 1)
end

local function RefreshMain(p)
	local db = AR.db
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
	local grow = AR.UI.GrowFor(db.side, db.grow)
	for _, g in ipairs(GROWS) do
		if g[1] == grow then p.grow:SetValueText(L[g[2]]) end
	end
	p.unlock:SetChecked(not AR.IsLocked())
	p.test:SetChecked(AR.IsTesting())
end

-- ---------------------------------------------------------------- the spells, per class
-- A class picked at the top; under it the class's
-- abilities by category. A category's own box ticks or unticks everything
-- under it, for the class shown; every ability has its box, its icon between
-- the box and the name. The categories sit in two columns, in their order
-- down the first and on into the second (the order of the icons in a row),
-- broken where the taller column is shortest, so a class with many abilities
-- still fits the window.
local ROW_H = 20
local GAP = 6         -- under a category
local COL_MIN = 290   -- the second column starts at half the page, never closer than this
local CATEGORIES = { { "defense", "Defensive" }, { "burst", "Offensive cooldowns" }, { "control", "Crowd control" },
	{ "other", "Other" } }

-- how many of the categories go in the first column, given each one's height
-- (0 for one the class does not have): the break that makes the taller column
-- shortest, the first column taking the extra one on a tie. The last one
-- (other) always ends the second column, bottom right.
local function FirstColumn(heights)
	local total = 0
	for _, h in ipairs(heights) do total = total + h end
	local best, bestTall, left = 0, total, 0
	for k = 1, #heights - 1 do
		left = left + heights[k]
		local tall = math.max(left, total - left)
		if tall <= bestTall then best, bestTall = k, tall end
	end
	return best
end

-- a tick: kept only when it differs from the default, so a later change of
-- the default reaches every ability the user left alone
local function Pick(def, checked)
	if checked == AR.DefaultOn(def) then
		AR.db.picked[def.id] = nil
	else
		AR.db.picked[def.id] = checked
	end
end

local RACIAL_ICON = "Interface\\Icons\\INV_Misc_GroupNeedMore"   -- a generic one for every race
local WHITE = { 1, 1, 1 }

-- a class's colour as { r, g, b }; white for the racial entry
local function ClassColor(class)
	local c = class ~= RACIAL and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
	return c and { c.r, c.g, c.b } or WHITE
end

-- every class with its icon and colour, then the racial abilities
local function ClassItems()
	local items = {}
	for _, class in ipairs(CLASSES) do
		items[#items + 1] = { label = ClassName(class), value = class, atlas = "classicon-" .. class:lower(), color = ClassColor(class) }
	end
	items[#items + 1] = { label = ClassName(RACIAL), value = RACIAL, icon = RACIAL_ICON, color = WHITE }
	return items
end

-- the race's name, from the game, for a racial ability
local function RaceName(def)
	if not (def.raceID and C_CreatureInfo and C_CreatureInfo.GetRaceInfo) then return def.race end
	local ok, info = pcall(C_CreatureInfo.GetRaceInfo, def.raceID)
	return ok and type(info) == "table" and info.raceName or def.race
end

local function SpellName(def)
	local ok, name = pcall(C_Spell.GetSpellName, def.id)
	if not (ok and type(name) == "string" and name ~= "") then name = tostring(def.id) end
	if def.race then name = name .. " (" .. RaceName(def) .. ")" end
	return name
end

-- a check box with the spell's icon between the box and the name
local function AbilityRow(parent, onChange)
	return WithIcon(Skin.Checkbox(parent, "", onChange))
end

local function BuildSpells(p)
	local _, class = UnitClass("player")
	p.class = AR.SPELLS[class] and class or CLASSES[1]
	Skin.Field(p, "Class / race", 0, 0)
	p.picker = Skin.Dropdown(p, 180, ClassItems, function(_, item)
		p.class = item.value
		O.Refresh()
	end)
	p.picker:SetPoint("TOPLEFT", X, 0)
	p.picker.maxRows = #CLASSES + 1   -- the whole list at once, no scrolling

	p.headers = {}
	for _, cat in ipairs(CATEGORIES) do
		local role = cat[1]
		local h = CK.Bind(Skin.Checkbox(p, "", function(checked)
			for _, def in ipairs(ListFor(p.class)) do
				if def.tag == role then Pick(def, checked) end
			end
			Changed()
			O.Refresh()
		end), cat[2])
		h.role = role
		p.headers[role] = h
	end
	p.abilities = {}
end

local function RefreshSpells(p)
	local db = AR.db
	p.picker:SetValueText(ClassName(p.class))
	p.picker.text:SetTextColor(unpack(ClassColor(p.class)))
	local list = ListFor(p.class)
	local tops, used = { -34, -34 }, 0
	local colX = math.max(COL_MIN, math.floor((p:GetWidth() or 0) / 2))
	local heights = {}
	for i, cat in ipairs(CATEGORIES) do
		local n = 0
		for _, def in ipairs(list) do if def.tag == cat[1] then n = n + 1 end end
		heights[i] = n > 0 and (n + 1) * ROW_H + GAP or 0
	end
	local first = FirstColumn(heights)
	for i, cat in ipairs(CATEGORIES) do
		local role = cat[1]
		local header = p.headers[role]
		local any, all = false, true
		for _, def in ipairs(list) do
			if def.tag == role then
				any = true
				if not AR.Picked(def, db.picked) then all = false end
			end
		end
		header:SetShown(any)
		if any then
			local col = i <= first and 1 or 2
			local x, y = (col - 1) * colX, tops[col]
			header:ClearAllPoints()
			header:SetPoint("TOPLEFT", x, y)
			header:SetChecked(all)
			y = y - ROW_H
			for _, def in ipairs(list) do
				if def.tag == role then
					used = used + 1
					local c = p.abilities[used]
					if not c then
						c = AbilityRow(p, function(checked)
							Pick(c.def, checked)
							Changed()
							O.Refresh()
						end)
						p.abilities[used] = c
					end
					c.def = def
					c.icon:SetTexture(C_Spell.GetSpellTexture(def.id) or 134400)
					c:SetLabel(SpellName(def))
					c:SetChecked(AR.Picked(def, db.picked))
					c:ClearAllPoints()
					c:SetPoint("TOPLEFT", x + 24, y)
					c:Show()
					y = y - ROW_H
				end
			end
			tops[col] = y - GAP
		end
	end
	for i = used + 1, #p.abilities do p.abilities[i]:Hide() end
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
	tab = function() return L["TAB_PartyCD"] end,   -- short in the tab list; the page says beta
	GetNodes = function()
		return {
			{ key = "main", label = L["MOD_PartyCD"] },
			{ key = "spells", label = L["Spells"] },
			{ key = "debug", label = L["PAGE_debug"] },
		}
	end,
	GetHeader = function(node)
		if node == "spells" then return nil, nil end   -- the tab says it; the page starts at the top
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
