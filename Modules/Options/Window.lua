local CK = CombatKit
local L, Skin = CK.L, CK.Skin

-- ===========================================================================
-- The settings window: a shell that sections plug into.
--
-- A section is one tab at the top, and the pages behind it. With more than one
-- page the tab has a tree on the left to pick from:
--   { key=, order=, tab = function() -> the tab's label,
--     module= (its pages need that module running; while it is off the tab is
--              dimmed and offers to switch it on), right= (tab sits at the right),
--     dimmed = function() -> bool, for a section that is never "off" as a whole,
--     GetNodes = function() -> { { key=, label=, indent=, tag=, here= }, ... },
--     GetHeader = function(node) -> title, description,
--     Build = function(body)            -- once, the first time it is opened
--     Refresh = function(node, body)    -- every time something changed
--     DefaultNode = function() -> node to open on, OnSelect = function(node),
--     OnWindowHide = function() }
-- Module pages live in Pages/; the last section is the kit's own: Modules,
-- General and HUD, behind the tab at the right.
-- ===========================================================================

local O = {}
CK.Options = O

-- layout units; the whole window is scaled by settings.windowScale (1.5 by default)
local W, H        = 640, 464
local TITLE_H     = 28
local TAB_H       = 24
local TOP         = TITLE_H + TAB_H - 2   -- title bar and tab strip share a border line each
local TAB_PAD     = 14
local LEFT_W      = 176
local RIGHT_X     = LEFT_W + 14
local RIGHT_W     = W - RIGHT_X - 14
local TREE_ROW    = 22
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

-- node: optional; without one the tab opens where it was left, else on its default page
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
-- Top: the tabs
-- ---------------------------------------------------------------------------

local function CreateTab(parent, def)
	local b = CreateFrame("Button", nil, parent)
	b:SetHeight(TAB_H - 2)   -- between the strip's two border lines
	b.section = def.key
	b.sel = Skin.Fill(b, "BACKGROUND", "selected")
	b.sel:SetAllPoints()
	b.bar = Skin.Fill(b, "BORDER", "accent")
	b.bar:SetPoint("TOPLEFT")
	b.bar:SetPoint("TOPRIGHT")
	b.bar:SetHeight(2)
	b.hover = Skin.Fill(b, "BACKGROUND", "hover", 0.5)
	b.hover:SetAllPoints()
	b.hover:Hide()
	b.text = Skin.Label(b, "", "GameFontHighlight")
	b.text:SetPoint("CENTER")
	b:SetScript("OnEnter", function(self) self.hover:Show() end)
	b:SetScript("OnLeave", function(self) self.hover:Hide() end)
	b:SetScript("OnClick", function(self) O.Select(self.section) end)
	return b
end

local function RefreshTabs()
	local x = 1
	for _, def in ipairs(sections) do
		local b = main.tabs[def.key]
		if not b then
			b = CreateTab(main.tabBar, def)
			main.tabs[def.key] = b
		end
		local isSelected = selected.section == def.key
		local dimmed = not IsOn(def) or (def.dimmed ~= nil and def.dimmed())
		b.text:SetText(def.tab())
		b.text:SetTextColor(Skin.Color(dimmed and "dim" or "text"))
		b.sel:SetShown(isSelected)
		b.bar:SetShown(isSelected)
		b.dimmed = dimmed
		b:SetWidth(b.text:GetStringWidth() + TAB_PAD * 2)
		b:ClearAllPoints()
		if def.right then
			b:SetPoint("TOPRIGHT", -1, -1)
		else
			b:SetPoint("TOPLEFT", x, -1)
			x = x + b:GetWidth()
		end
	end
end

-- ---------------------------------------------------------------------------
-- Left: the pages of the selected tab
-- ---------------------------------------------------------------------------

local function CreateTreeRow(parent)
	local b = CreateFrame("Button", nil, parent)
	b:SetHeight(TREE_ROW)
	b.sel = Skin.Fill(b, "BACKGROUND", "selected")
	b.sel:SetAllPoints()
	b.bar = Skin.Fill(b, "BORDER", "accent")
	b.bar:SetPoint("TOPLEFT")
	b.bar:SetPoint("BOTTOMLEFT")
	b.bar:SetWidth(2)
	b.hover = Skin.Fill(b, "BACKGROUND", "hover", 0.5)
	b.hover:SetAllPoints()
	b.hover:Hide()
	b.tag = Skin.Label(b, "", nil, "accent")
	b.tag:SetPoint("RIGHT", -8, 0)
	b.text = Skin.Label(b, "", "GameFontHighlight")
	b.text:SetJustifyH("LEFT")
	b.text:SetWordWrap(false)
	b:SetScript("OnEnter", function(self) self.hover:Show() end)
	b:SetScript("OnLeave", function(self) self.hover:Hide() end)
	b:SetScript("OnClick", function(self) O.Select(self.section, self.node) end)
	return b
end

local function RefreshTree()
	local def = byKey[selected.section]
	local nodes = (def and IsOn(def)) and def.GetNodes() or {}
	-- a single page needs no list: the page moves to the left edge
	local showTree = #nodes > 1
	main.tree:SetShown(showTree)
	main.detail:ClearAllPoints()
	main.detail:SetPoint("TOPLEFT", showTree and RIGHT_X or 14, -TOP - 12)

	local y, used = -6, 0
	if showTree then
		for _, node in ipairs(nodes) do
			used = used + 1
			local b = main.treeRows[used]
			if not b then
				b = CreateTreeRow(main.tree)
				main.treeRows[used] = b
			end
			b.section, b.node = def.key, node.key
			b:ClearAllPoints()
			b:SetPoint("TOPLEFT", 1, y)
			b:SetPoint("TOPRIGHT", -1, y)
			b.text:ClearAllPoints()
			b.text:SetPoint("LEFT", node.indent or 10, 0)
			b.text:SetPoint("RIGHT", b.tag, "LEFT", -4, 0)
			b.text:SetText(node.label)
			b.text:SetTextColor(Skin.Color(node.here and "ok" or "text"))
			b.tag:SetText(node.tag or "")
			local isSelected = selected.node == node.key
			b.sel:SetShown(isSelected)
			b.bar:SetShown(isSelected)
			b:Show()
			y = y - TREE_ROW
		end
	end
	for i = used + 1, #main.treeRows do main.treeRows[i]:Hide() end
end

-- ---------------------------------------------------------------------------
-- Right: the selected page
-- ---------------------------------------------------------------------------

-- The tab of a module that is off: what it is, and a check box to switch it on.
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

local function RefreshDetail()
	local def = byKey[selected.section]
	if not def then
		def = sections[1]
		selected = { section = def.key }
	end
	if not IsOn(def) then
		selected.node = nil
		return ShowOff(def)
	end
	main.off:Hide()
	-- the page is gone (a group folded its scenarios away, a module was just switched on)
	if not HasNode(def, selected.node) then
		selected.node = FirstNode(def)
		lastNode[def.key] = selected.node
		if def.OnSelect then def.OnSelect(selected.node) end
	end

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
	else
		body:SetPoint("TOPLEFT", 0, BODY_Y_BARE)
	end
	body:SetPoint("BOTTOMRIGHT")
	def.Refresh(selected.node, body)
end

function O.Refresh()
	if not main or not main:IsShown() then return end
	Skin.HideOptionList()
	RefreshDetail()   -- first: it may move the selection off a page that is gone
	RefreshTabs()
	RefreshTree()
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

-- The tab to open on: what was asked for, else the first module that is on.
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

	local tabBar = Skin.Panel(f, "bg")
	tabBar:SetPoint("TOPLEFT", 0, -TITLE_H + 1)
	tabBar:SetPoint("TOPRIGHT", 0, -TITLE_H + 1)
	tabBar:SetHeight(TAB_H)
	f.tabBar = tabBar
	f.tabs = {}   -- by section key

	local tree = Skin.Panel(f, "panel")
	tree:SetPoint("TOPLEFT", 0, -TOP)
	tree:SetPoint("BOTTOMLEFT")
	tree:SetWidth(LEFT_W)
	f.tree = tree
	f.treeRows = {}

	local d = CreateFrame("Frame", nil, f)
	d:SetPoint("TOPLEFT", RIGHT_X, -TOP - 12)
	d:SetSize(RIGHT_W, H - TOP - 24)
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
		wipe(lastNode)   -- a fresh look: every tab opens on its default page again
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
-- like Extras are switched on their own pages, in that module's tab.
local function BuildModules(page)
	page.rows = {}
	local above   -- the description above: a row follows it, however many lines it takes
	for _, def in ipairs(CK.MODULES) do
		if not def.features then
			local row = {}
			row.check = CK.Bind(Skin.Checkbox(page, "", function(checked) CK.SetModuleEnabled(def.name, checked) end),
				"MOD_" .. def.name)
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

local function BuildGeneral(page)
	local X = O.FIELD_X
	Skin.Field(page, "Language", 0, 0)
	page.language = Skin.Dropdown(page, 220, LanguageItems, function(_, item) CK.SetLanguage(item.value) end)
	page.language:SetPoint("TOPLEFT", X, 0)

	Skin.Field(page, "Window scale", 0, -32)
	local windowStepper = Skin.Stepper(page, function(dir)
		O.SetWindowScale(CK.db.settings.windowScale + dir * 0.1)
	end)
	windowStepper:SetPoint("TOPLEFT", X, -32)
	page.windowScale = windowStepper.value
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

	Row("Scale", -32)
	local hudStepper = Skin.Stepper(page, function(dir)
		CK.HUD.SetScale(CK.db.hud.scale + dir * CK.HUD.SCALE_STEP)
	end)
	hudStepper:SetPoint("TOPLEFT", X, -32)
	page.hudScale = hudStepper.value

	-- down to 0%: no background at all, only the texts (and the border, if it is on)
	Row("Background opacity", -64)
	local alphaStepper = Skin.Stepper(page, function(dir)
		CK.HUD.SetBackgroundAlpha(CK.db.hud.bgAlpha + dir * CK.HUD.ALPHA_STEP)
	end)
	alphaStepper:SetPoint("TOPLEFT", X, -64)
	page.bgAlpha = alphaStepper.value

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
	page.hudScale:SetText(string.format("%d%%", math.floor(CK.db.hud.scale * 100 + 0.5)))
	page.bgAlpha:SetText(string.format("%d%%", math.floor(CK.db.hud.bgAlpha * 100 + 0.5)))
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
	page.windowScale:SetText(string.format("%d%%", math.floor(CK.db.settings.windowScale * 100 + 0.5)))
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
