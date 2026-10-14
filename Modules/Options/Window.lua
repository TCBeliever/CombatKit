local CK = CombatKit
local L, Skin = CK.L, CK.Skin

-- ===========================================================================
-- The settings window: a shell that sections plug into.
--
-- A section is one entry in the list at the left, and the pages behind it.
-- With more than one page, the pages are tabs in a strip across the top of
-- the right side:
--   { key=, order=, tab = function() -> the entry's label,
--     module= (its pages need that module running; while it is off the entry is
--              dimmed and offers to switch it on), right= (entry sits at the bottom),
--     dimmed = function() -> bool, for a section that is never "off" as a whole,
--     GetNodes = function() -> { { key=, label=, tag=, here=, parent=, subLabel= }, ... },
--       a node with `parent` (another node's key) is a page under that one: it is
--       shown in a second strip, under the first, while its parent or a sibling is
--       open; the parent itself leads that strip, as `subLabel` when it has one,
--     GetHeader = function(node) -> title, description,
--     Build = function(body)            -- once, the first time it is opened
--     Refresh = function(node, body)    -- every time something changed
--     DefaultNode = function() -> node to open on, OnSelect = function(node),
--     OnWindowHide = function() }
-- Module pages live in Pages/; the last section is the kit's own: Modules,
-- General and HUD, behind the entry at the bottom of the list.
-- ===========================================================================

local O = {}
CK.Options = O

-- layout units; the whole window is scaled by settings.windowScale (1.5 by default)
local W, H        = 758, 464   -- the right side is as wide as the whole window used to be
local TITLE_H     = 28
local TOP         = TITLE_H - 1   -- the title bar's bottom border line
local SIDE_W      = 118           -- the list of sections at the left
local SIDE_ROW    = 26
local TAB_H       = 24            -- the strip of a section's pages
local TAB_PAD     = 12
local RIGHT_X     = SIDE_W + 14
local RIGHT_W     = W - RIGHT_X - 14
local DESC_GAP    = 20    -- between the description, however many lines it takes, and the page
local BODY_Y_BARE = -32   -- below a title that has no description
local WINDOW_SCALE_MIN, WINDOW_SCALE_MAX = 0.8, 2.0

O.RIGHT_W = RIGHT_W
O.FIELD_X = 110

local main
local sections, byKey = {}, {}
local selected = {}   -- { section=, node= }
local lastNode = {}   -- section -> the page it was left on, while the window stays open
local openOn          -- "Section/node" asked for before the window was shown

function O.AddSection(def)
	sections[#sections + 1] = def
	byKey[def.key] = def
	table.sort(sections, function(a, b) return (a.order or 0) < (b.order or 0) end)
end

-- Can the section show its pages? (Its module is on and in memory.)
local function IsOn(def)
	return def.module == nil or (CK.IsModuleEnabled(def.module) and CK.modules[def.module] ~= nil)
end

local function HasNode(def, node)
	if node == nil then return false end
	for _, n in ipairs(def.GetNodes()) do
		if n.key == node then return true end
	end
	return false
end

local function FirstNode(def)
	local node = def.DefaultNode and def.DefaultNode()
	if HasNode(def, node) then return node end
	local first = def.GetNodes()[1]
	return first and first.key
end

-- node: optional; without one the section opens where it was left, else on its default page
function O.Select(sectionKey, node)
	local def = byKey[sectionKey]
	if not def then return end
	if IsOn(def) then
		node = node or lastNode[sectionKey]
		if not HasNode(def, node) then node = FirstNode(def) end
		lastNode[sectionKey] = node
		if def.OnSelect then def.OnSelect(node) end
	else
		node = nil
	end
	selected = { section = sectionKey, node = node }
	O.Refresh()
end

function O.GetSelection() return selected.section, selected.node end

-- What every page calls after it changed something.
function O.Changed()
	O.Refresh()
	CK.HUD.Refresh()
end

-- ---------------------------------------------------------------------------
-- Left: the sections
-- ---------------------------------------------------------------------------

local function CreateTab(parent, def)
	local b = CreateFrame("Button", nil, parent)
	b:SetHeight(SIDE_ROW)
	b.section = def.key
	b.sel = Skin.Fill(b, "BACKGROUND", "selected")
	b.sel:SetAllPoints()
	b.bar = Skin.Fill(b, "BORDER", "accent")
	b.bar:SetPoint("TOPLEFT")
	b.bar:SetPoint("BOTTOMLEFT")
	b.bar:SetWidth(2)
	b.hover = Skin.Fill(b, "BACKGROUND", "hover", 0.5)
	b.hover:SetAllPoints()
	b.hover:Hide()
	b.text = Skin.Label(b, "", "GameFontHighlight")
	b.text:SetPoint("LEFT", 12, 0)
	b.text:SetPoint("RIGHT", -6, 0)
	b.text:SetJustifyH("LEFT")
	b.text:SetWordWrap(false)
	b:SetScript("OnEnter", function(self) self.hover:Show() end)
	b:SetScript("OnLeave", function(self) self.hover:Hide() end)
	b:SetScript("OnClick", function(self) O.Select(self.section) end)
	return b
end

-- the sections from the top; those marked `right` from the bottom
local function RefreshTabs()
	local y, bottom = -6, 6
	for _, def in ipairs(sections) do
		local b = main.tabs[def.key]
		if not b then
			b = CreateTab(main.side, def)
			main.tabs[def.key] = b
		end
		local isSelected = selected.section == def.key
		local dimmed = not IsOn(def) or (def.dimmed ~= nil and def.dimmed())
		b.text:SetText(def.tab())
		b.text:SetTextColor(Skin.Color(dimmed and "dim" or "text"))
		b.sel:SetShown(isSelected)
		b.bar:SetShown(isSelected)
		b.dimmed = dimmed
		b:ClearAllPoints()
		if def.right then
			b:SetPoint("BOTTOMLEFT", 1, bottom)
			b:SetPoint("BOTTOMRIGHT", -1, bottom)
			bottom = bottom + SIDE_ROW
		else
			b:SetPoint("TOPLEFT", 1, y)
			b:SetPoint("TOPRIGHT", -1, y)
			y = y - SIDE_ROW
		end
	end
end

-- ---------------------------------------------------------------------------
-- Top right: the pages of the selected section, as tabs
-- ---------------------------------------------------------------------------

local function CreateTreeRow(parent)
	local b = CreateFrame("Button", nil, parent)
	b:SetHeight(TAB_H)
	b.sel = Skin.Fill(b, "BACKGROUND", "selected")
	b.sel:SetAllPoints()
	b.bar = Skin.Fill(b, "BORDER", "accent")
	b.bar:SetPoint("BOTTOMLEFT")
	b.bar:SetPoint("BOTTOMRIGHT")
	b.bar:SetHeight(2)
	b.hover = Skin.Fill(b, "BACKGROUND", "hover", 0.5)
	b.hover:SetAllPoints()
	b.hover:Hide()
	b.text = Skin.Label(b, "", "GameFontHighlight")
	b.text:SetPoint("LEFT", TAB_PAD, 0)
	b.text:SetWordWrap(false)
	b.tag = Skin.Label(b, "", nil, "accent")
	b.tag:SetPoint("LEFT", b.text, "RIGHT", 4, 0)
	b:SetScript("OnEnter", function(self) self.hover:Show() end)
	b:SetScript("OnLeave", function(self) self.hover:Hide() end)
	b:SetScript("OnClick", function(self) O.Select(self.section, self.node) end)
	return b
end

-- The pages of the selected section; one page needs no strip
local function TreeNodes()
	local def = byKey[selected.section]
	return (def and IsOn(def)) and def.GetNodes() or {}
end

-- How wide the page is: the right side, whatever the strip above it holds.
function O.PageWidth()
	return RIGHT_W
end

-- The strip of page tabs, flowing left to right and wrapping to another line
-- when a section has more pages than fit. Pages under another (parent) make a
-- second strip, under the first, while that family is open. The detail below
-- moves down as far as the strips reach.
local function RefreshTree()
	local def, nodes = byKey[selected.section], TreeNodes()
	local showTree = #nodes > 1
	main.tree:SetShown(showTree)

	local top, children = {}, {}
	for _, node in ipairs(nodes) do
		if node.parent then
			children[node.parent] = children[node.parent] or {}
			table.insert(children[node.parent], node)
		else
			top[#top + 1] = node
		end
	end
	-- the family that is open: the top node selected, or the parent of the one selected
	local family
	for _, node in ipairs(top) do
		if node.key == selected.node then family = node end
		for _, child in ipairs(children[node.key] or {}) do
			if child.key == selected.node then family = node end
		end
	end

	local x, line, used = 0, 0, 0
	local function place(node, label, isSelected)
		used = used + 1
		local b = main.treeRows[used]
		if not b then
			b = CreateTreeRow(main.tree)
			main.treeRows[used] = b
		end
		b.section, b.node = def.key, node.key
		b.text:SetText(label)
		b.text:SetTextColor(Skin.Color(node.here and "ok" or "text"))
		b.tag:SetText(node.tag or "")
		local w = TAB_PAD + b.text:GetStringWidth() + TAB_PAD
		if node.tag and node.tag ~= "" then w = w + b.tag:GetStringWidth() + 4 end
		w = math.ceil(w)
		if x > 0 and x + w > RIGHT_W then
			x, line = 0, line + 1
		end
		b:ClearAllPoints()
		b:SetPoint("TOPLEFT", x, -line * TAB_H)
		b:SetWidth(w)
		x = x + w
		b.sel:SetShown(isSelected)
		b.bar:SetShown(isSelected)
		b:Show()
	end
	if showTree then
		for _, node in ipairs(top) do
			place(node, node.label, node == family or node.key == selected.node)
		end
		if family and children[family.key] then
			x, line = 0, line + 1
			place(family, family.subLabel or family.label, family.key == selected.node)
			for _, child in ipairs(children[family.key]) do
				place(child, child.label, child.key == selected.node)
			end
		end
	end
	for i = used + 1, #main.treeRows do main.treeRows[i]:Hide() end

	local stripH = showTree and (line + 1) * TAB_H or 0
	main.tree:SetHeight(math.max(stripH, 1))
	main.detail:ClearAllPoints()
	main.detail:SetPoint("TOPLEFT", RIGHT_X, -TOP - 12 - (showTree and stripH + 8 or 0))
	main.detail:SetPoint("BOTTOMRIGHT", -14, 12)
end

-- ---------------------------------------------------------------------------
-- Right: the selected page
-- ---------------------------------------------------------------------------

-- The entry of a module that is off: what it is, and a check box to switch it on.
local function ShowOff(def)
	local d = main.detail
	d.title:SetText(def.tab())
	d.desc:SetText(L["MODDESC_" .. def.module])
	for _, body in pairs(main.bodies) do body:Hide() end
	local off = main.off
	off.module = def.module
	off.check:SetChecked(false)
	local state = CK.GetModuleState(def.module)
	local text = ""
	if state == "missing" then
		text = Skin.Text("bad", L["STATE_missing"])
	elseif state == "stale" then
		text = Skin.Text("warn", L["STATE_stale"])
	end
	off.state:SetText(text)
	off:Show()
end

-- The selection made good: a section that is gone falls back to the first, a
-- page that is gone (a group folded its scenarios away, a module was just
-- switched on) to the section's first
local function FixSelection()
	local def = byKey[selected.section]
	if not def then
		def = sections[1]
		selected = { section = def.key }
	end
	if not IsOn(def) then
		selected.node = nil
	elseif not HasNode(def, selected.node) then
		selected.node = FirstNode(def)
		lastNode[def.key] = selected.node
		if def.OnSelect then def.OnSelect(selected.node) end
	end
end

local function RefreshDetail()
	local def = byKey[selected.section]
	if not IsOn(def) then return ShowOff(def) end
	main.off:Hide()

	local d = main.detail
	local title, desc = def.GetHeader(selected.node)
	d.title:SetText(title or "")
	d.desc:SetText(desc or "")

	local body = main.bodies[def.key]
	if not body then
		body = CreateFrame("Frame", nil, d)
		main.bodies[def.key] = body
		def.Build(body)
	end
	for key, other in pairs(main.bodies) do other:SetShown(key == def.key) end
	body:ClearAllPoints()
	if desc and desc ~= "" then
		body:SetPoint("TOPLEFT", d.desc, "BOTTOMLEFT", 0, -DESC_GAP)   -- the text wraps: its height is its own
	elseif not title or title == "" then
		body:SetPoint("TOPLEFT", 0, 0)   -- no header at all: the page starts at the top
	else
		body:SetPoint("TOPLEFT", 0, BODY_Y_BARE)
	end
	body:SetPoint("BOTTOMRIGHT")
	def.Refresh(selected.node, body)
end

function O.Refresh()
	if not main or not main:IsShown() then return end
	Skin.HideOptionList()
	FixSelection()
	RefreshTree()     -- the strip first: the detail sits under it
	RefreshDetail()
	RefreshTabs()
end

function O.IsShown()
	return main ~= nil and main:IsShown()
end

function O.SetWindowScale(scale)
	scale = math.max(WINDOW_SCALE_MIN, math.min(WINDOW_SCALE_MAX, scale))
	scale = math.floor(scale * 10 + 0.5) / 10
	CK.db.settings.windowScale = scale
	if main then main:SetScale(scale) end
	O.Refresh()
end

-- ---------------------------------------------------------------------------
-- Window
-- ---------------------------------------------------------------------------

-- The section to open on: what was asked for, else the first module that is on.
local function InitialSelection()
	if openOn then
		local sectionKey, node = openOn:match("^([^/]+)/(.+)$")
		openOn = nil
		if sectionKey and byKey[sectionKey] then return sectionKey, node end
	end
	for _, def in ipairs(sections) do
		if def.module and IsOn(def) then return def.key end
	end
	return "kit", "modules"
end

local function CreateMain()
	local f = CreateFrame("Frame", "CombatKitFrame", UIParent, "BackdropTemplate")
	f:SetSize(W, H)
	f:SetScale(CK.db.settings.windowScale)
	f:SetPoint("CENTER")
	f:SetFrameStrata("HIGH")
	f:SetToplevel(true)
	f:SetClampedToScreen(true)
	f:SetMovable(true)
	f:EnableMouse(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", f.StopMovingOrSizing)
	Skin.Backdrop(f, "bg", 1)   -- opaque: the game must not bleed through
	tinsert(UISpecialFrames, "CombatKitFrame")   -- Esc closes it

	local bar = Skin.Panel(f, "panel")
	bar:SetPoint("TOPLEFT")
	bar:SetPoint("TOPRIGHT")
	bar:SetHeight(TITLE_H)
	local version = C_AddOns.GetAddOnMetadata("CombatKit", "Version") or ""
	f.title = Skin.Label(bar, Skin.Text("accent", "Combat") .. "Kit " .. Skin.Text("dim", "v" .. version), "GameFontHighlight")
	f.title:SetPoint("LEFT", 10, 0)
	f.close = Skin.CloseButton(bar, function() f:Hide() end)
	f.close:SetPoint("RIGHT", -4, 0)

	-- the sections, down the left
	local side = Skin.Panel(f, "panel")
	side:SetPoint("TOPLEFT", 0, -TOP)
	side:SetPoint("BOTTOMLEFT")
	side:SetWidth(SIDE_W)
	f.side = side
	f.tabs = {}   -- by section key

	-- the pages of the section, across the top of the right side
	local tree = CreateFrame("Frame", nil, f)
	tree:SetPoint("TOPLEFT", RIGHT_X, -TOP - 6)
	tree:SetPoint("TOPRIGHT", -14, -TOP - 6)
	tree:SetHeight(TAB_H)
	f.tree = tree
	f.treeRows = {}

	local d = CreateFrame("Frame", nil, f)
	d:SetPoint("TOPLEFT", RIGHT_X, -TOP - 12)
	d:SetPoint("BOTTOMRIGHT", -14, 12)
	f.detail = d
	d.title = Skin.Label(d, "", "GameFontHighlightLarge")
	d.title:SetPoint("TOPLEFT", 0, 0)
	d.desc = Skin.Label(d, "", nil, "dim")
	d.desc:SetPoint("TOPLEFT", 0, -22)
	d.desc:SetWidth(RIGHT_W)
	d.desc:SetJustifyH("LEFT")
	f.bodies = {}   -- one frame per section, built the first time it is opened

	-- shown instead of a section's pages while its module is off
	local off = CreateFrame("Frame", nil, d)
	off:SetPoint("TOPLEFT", d.desc, "BOTTOMLEFT", 0, -DESC_GAP)
	off:SetPoint("BOTTOMRIGHT")
	off.check = CK.Bind(Skin.Checkbox(off, "", function(checked)
		CK.SetModuleEnabled(off.module, checked)   -- refreshes the window: its pages take over
	end), "Enable")
	off.check:SetPoint("TOPLEFT", 0, 0)
	off.state = Skin.Label(off, "")
	off.state:SetPoint("LEFT", off.check, "RIGHT", 10, 0)
	off:Hide()
	f.off = off

	f:SetScript("OnShow", function()
		wipe(lastNode)   -- a fresh look: every section opens on its default page again
		local sectionKey, node = InitialSelection()
		O.Select(sectionKey, node)
		CK.HUD.Refresh()   -- always visible while the window is open
	end)
	f:SetScript("OnHide", function()
		Skin.HideOptionList()
		-- whatever a page unlocked for dragging is locked again
		for _, def in ipairs(sections) do
			if def.OnWindowHide then def.OnWindowHide() end
		end
		CK.HUD.Refresh()
	end)
	f:Hide()
	main = f
	return f
end

-- node: optional "Section/node" to open straight on a page
function O.Open(node)
	if not main then CreateMain() end
	if main:IsShown() then
		local sectionKey, key = (node or ""):match("^([^/]+)/(.+)$")
		if sectionKey and byKey[sectionKey] then O.Select(sectionKey, key) end
		return
	end
	openOn = node
	main:Show()
end

function O.Toggle()
	if main and main:IsShown() then main:Hide() else O.Open() end
end

-- for the tests
function O.GetFrame() return main end

-- ---------------------------------------------------------------------------
-- The kit's own pages: Modules, General, HUD
-- ---------------------------------------------------------------------------

-- One row per module that is switched as a whole. The small features of a module
-- like Extras are switched on their own pages, in that module's section.
local function BuildModules(page)
	page.rows = {}
	local above   -- the description above: a row follows it, however many lines it takes
	for _, def in ipairs(CK.MODULES) do
		if not def.features then
			local row = {}
			local listKey = "MODLIST_" .. def.name
			if not (CK.locales.enUS[listKey] or CK.locales.zhTW[listKey]) then listKey = "MOD_" .. def.name end
			row.check = CK.Bind(Skin.Checkbox(page, "", function(checked) CK.SetModuleEnabled(def.name, checked) end), listKey)
			if above then
				row.check:SetPoint("TOPLEFT", above, "BOTTOMLEFT", -20, -12)
			else
				row.check:SetPoint("TOPLEFT", 0, 0)
			end
			row.state = Skin.Label(page, "")
			row.state:SetPoint("LEFT", row.check, "RIGHT", 10, 0)
			row.desc = CK.Bind(Skin.Label(page, "", nil, "dim"), "MODDESC_" .. def.name)
			row.desc:SetPoint("TOPLEFT", row.check, "BOTTOMLEFT", 20, -3)
			row.desc:SetWidth(RIGHT_W - 20)
			row.desc:SetJustifyH("LEFT")
			row.module = def.name
			page.rows[#page.rows + 1] = row
			page[def.name] = row
			above = row.desc
		end
	end

	page.note = CK.Bind(Skin.Label(page, "", nil, "dim"), "RELOAD_NOTE")
	page.note:SetPoint("TOPLEFT", above, "BOTTOMLEFT", -20, -20)
	page.note:SetWidth(RIGHT_W - 110)
	page.note:SetJustifyH("LEFT")
	page.reload = CK.Bind(Skin.Button(page, "", 90, 20, function() ReloadUI() end), "Reload UI")
	page.reload:SetPoint("TOPLEFT", page.note, "TOPRIGHT", 16, 3)
end

local function RefreshModules(page)
	-- anything switched off whose code is still in memory, the feature modules included
	local anyStale = false
	for _, def in ipairs(CK.MODULES) do
		if CK.GetModuleState(def.name) == "stale" then anyStale = true end
	end
	for _, row in ipairs(page.rows) do
		local on = CK.IsModuleEnabled(row.module)
		local state = CK.GetModuleState(row.module)
		row.check:SetChecked(on)
		-- only what the check box does not already say
		local text = ""
		if state == "missing" then
			text = Skin.Text("bad", L["STATE_missing"])
		elseif state == "stale" and not on then
			text = Skin.Text("warn", L["STATE_stale"])
		end
		row.state:SetText(text)
	end
	page.note:SetShown(anyStale)
	page.reload:SetShown(anyStale)
end

local function LanguageLabel(entry) return entry.label or L[entry.key] end
local function LanguageItems()
	local items = {}
	for _, entry in ipairs(CK.LANGUAGES) do
		items[#items + 1] = { label = LanguageLabel(entry), value = entry.code }
	end
	return items
end

-- Fonts to pick from. CombatKit ships none: it offers the game's own (which ones
-- exist, and which can write the client's language, depends on the client) and,
-- when some other addon brought LibSharedMedia along, everything registered there
-- (the library already leaves out fonts that cannot write the client's language).
local GAME_FONTS = {
	koKR = { { "기본 글꼴", [[Fonts\2002.TTF]] }, { "굵은 글꼴", [[Fonts\2002B.TTF]] }, { "데미지 글꼴", [[Fonts\K_Damage.TTF]] },
		{ "퀘스트 글꼴", [[Fonts\K_Pagetext.TTF]] } },
	zhCN = { { "默认", [[Fonts\ARKai_T.ttf]] }, { "聊天", [[Fonts\ARHei.ttf]] }, { "伤害数字", [[Fonts\ARKai_C.ttf]] } },
	zhTW = { { "預設", [[Fonts\bLEI00D.ttf]] }, { "聊天", [[Fonts\bHEI01B.ttf]] }, { "提示訊息", [[Fonts\bHEI00M.ttf]] },
		{ "傷害數字", [[Fonts\bKAI00M.ttf]] } },
	ruRU = { { "Friz Quadrata TT", [[Fonts\FRIZQT___CYR.TTF]] }, { "Arial Narrow", [[Fonts\ARIALN.TTF]] },
		{ "Morpheus", [[Fonts\MORPHEUS_CYR.TTF]] }, { "Skurri", [[Fonts\SKURRI_CYR.TTF]] } },
	western = { { "Friz Quadrata TT", [[Fonts\FRIZQT__.TTF]] }, { "Arial Narrow", [[Fonts\ARIALN.TTF]] },
		{ "Morpheus", [[Fonts\MORPHEUS_CYR.TTF]] }, { "Skurri", [[Fonts\SKURRI_CYR.TTF]] } },
}

local function FontItems()
	local items = { { label = L["Game default"] } }
	local media = LibStub and LibStub("LibSharedMedia-3.0", true)
	if media then
		for _, name in ipairs(media:List("font")) do
			items[#items + 1] = { label = name, value = media:Fetch("font", name) }
		end
	else
		for _, font in ipairs(GAME_FONTS[GetLocale()] or GAME_FONTS.western) do
			items[#items + 1] = { label = font[1], value = font[2] }
		end
	end
	return items
end

-- the themes, each with its accent as a swatch
local function ThemeItems()
	local items = {}
	for _, theme in ipairs(Skin.THEMES) do
		items[#items + 1] = { label = L["THEME_" .. theme.key], value = theme.key, swatch = theme.colors.accent }
	end
	return items
end

local function BuildGeneral(page)
	local X = O.FIELD_X
	Skin.Field(page, "Language", 0, 0)
	page.language = Skin.Dropdown(page, 220, LanguageItems, function(_, item) CK.SetLanguage(item.value) end)
	page.language:SetPoint("TOPLEFT", X, 0)

	-- the colours of this window and of the HUD; both take them at once
	Skin.Field(page, "Theme", 0, -32)
	page.theme = Skin.Dropdown(page, 220, ThemeItems, function(_, item) CK.SetTheme(item.value) end)
	page.theme:SetPoint("TOPLEFT", X, -32)

	page.windowScale = Skin.Slider(page, "Window scale", { min = WINDOW_SCALE_MIN, max = WINDOW_SCALE_MAX, step = 0.1,
		format = Skin.Percent, parse = Skin.ParsePercent, onChange = function(v) O.SetWindowScale(v) end })
	page.windowScale:SetPoint("TOPLEFT", 0, -64)
end

-- The HUD stays on screen while this window is open, so every change shows at once.
local function BuildHud(page)
	local X = O.FIELD_X
	local function Row(key, y) Skin.Field(page, key, 0, y) end
	local function Check(labelKey, y, onChange)
		local c = CK.Bind(Skin.Checkbox(page, "", onChange), labelKey)
		c:SetPoint("TOPLEFT", X, y - 1)
		return c
	end

	page.hudShow = Check("Show the HUD", 0, function(checked)
		CK.db.hud.show = checked and "always" or "never"
		O.Changed()
	end)

	page.hudScale = Skin.Slider(page, "Scale", { min = CK.HUD.SCALE_MIN or 0.5, max = CK.HUD.SCALE_MAX or 2, step = CK.HUD.SCALE_STEP,
		format = Skin.Percent, parse = Skin.ParsePercent, onChange = function(v) CK.HUD.SetScale(v) end })
	page.hudScale:SetPoint("TOPLEFT", 0, -28)
	-- down to 0%: no background at all, only the texts (and the border, if it is on)
	page.bgAlpha = Skin.Slider(page, "Background opacity", { min = 0, max = 1, step = CK.HUD.ALPHA_STEP,
		format = Skin.Percent, parse = Skin.ParsePercent, onChange = function(v) CK.HUD.SetBackgroundAlpha(v) end })
	page.bgAlpha:SetPoint("TOPLEFT", 200, -28)

	page.border = Check("Show the border", -96, function(checked) CK.HUD.SetBorder(checked) end)

	Row("Font", -128)
	page.font = Skin.Dropdown(page, 220, FontItems, function(_, item) CK.HUD.SetFont(item.value, item.label) end)
	page.font:SetPoint("TOPLEFT", X, -128)

	-- the corner the box keeps while rows come and go
	Row("Anchor", -160)
	page.anchor = Skin.Dropdown(page, 220, function()
		local items = {}
		for _, a in ipairs(CK.HUD.ANCHORS) do items[#items + 1] = { label = L["ANCHOR_" .. a], value = a } end
		return items
	end, function(_, item) CK.HUD.SetAnchor(item.value) end)
	page.anchor:SetPoint("TOPLEFT", X, -160)
	Skin.Tooltip(page.anchor, "Anchor", "ANCHOR_TIP")

	Row("Position", -192)
	page.locked = Check("Lock", -192, function(checked) CK.db.hud.locked = checked end)
	Skin.Tooltip(page.locked, "Lock", "HUD_HINT")
	local reset = CK.Bind(Skin.Button(page, "", 90, 20, function() CK.HUD.ResetPosition() end), "Reset position")
	reset:SetPoint("LEFT", page.locked, "RIGHT", 16, 0)
end

local function RefreshHud(page)
	page.hudShow:SetChecked(CK.db.hud.show ~= "never")
	page.hudScale:SetValue(CK.db.hud.scale)
	page.bgAlpha:SetValue(CK.db.hud.bgAlpha)
	page.border:SetChecked(CK.db.hud.border)
	page.font:SetValueText(CK.db.hud.font and CK.db.hud.fontName or L["Game default"])
	page.anchor:SetValueText(L["ANCHOR_" .. CK.db.hud.anchor])
	page.locked:SetChecked(CK.db.hud.locked)
end

local function RefreshGeneral(page)
	local code = CK.db.settings.locale
	for _, entry in ipairs(CK.LANGUAGES) do
		if entry.code == code then page.language:SetValueText(LanguageLabel(entry)) end
	end
	page.theme:SetValueText(L["THEME_" .. Skin.theme])
	page.windowScale:SetValue(CK.db.settings.windowScale)
end

O.AddSection({
	key = "kit",
	order = 1000,
	right = true,
	tab = function() return L["Settings"] end,
	GetNodes = function()
		return { { key = "modules", label = L["Modules"] }, { key = "general", label = L["General"] },
			{ key = "hud", label = "HUD" } }
	end,
	GetHeader = function(node)
		if node == "modules" then return L["Modules"], L["MODULES_DESC"] end
		if node == "hud" then return "HUD", nil end
		return L["General"], nil
	end,
	Build = function(body)
		body.pages = {}
		for _, key in ipairs({ "modules", "general", "hud" }) do
			local page = CreateFrame("Frame", nil, body)
			page:SetAllPoints()
			body.pages[key] = page
		end
		BuildModules(body.pages.modules)
		BuildGeneral(body.pages.general)
		BuildHud(body.pages.hud)
	end,
	Refresh = function(node, body)
		for key, page in pairs(body.pages) do page:SetShown(key == node) end
		if node == "modules" then
			RefreshModules(body.pages.modules)
		elseif node == "hud" then
			RefreshHud(body.pages.hud)
		else
			RefreshGeneral(body.pages.general)
		end
	end,
})
