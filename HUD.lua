local ADDON, ns = ...
local L = ns.L
local Skin = ns.Skin

-- ===========================================================================
-- The HUD: one small box that modules fill.
--
--   [icon]   Havoc             Ready      <- a section (Loadout)
--   Talents  M+ AoE
--   Gear     PvE
--   ---------------------------------
--   Crit     23.4%                         <- another section (Stats)
--   Haste    18.0%
--
-- Two columns shared by every section: the label on the left, the value flush
-- with the right edge; a row with an icon keeps its text right next to the icon
-- instead, and may carry a second text at the right edge. A section is
--   { key=, order=, GetRows = function(force) -> rows, alert,
--     OnClick = function(), OnTooltip = function(tooltip) }
-- and a row is { icon=, label=, value=, right= } with texts already coloured.
-- A row may give { fmt=, num= } instead of value: the game formats the number,
-- which is the only way to show a "secret" one (12.x hands those out for the
-- player's own stats in combat). Text set that way cannot be measured either,
-- so such a row says how wide it is: width=.
-- GetRows returns nil when the section has nothing to show right now; `force`
-- is true while the settings window is open, so the box can be placed.
-- With no rows at all the HUD is hidden. Right click opens the settings, drag
-- moves, Ctrl + mouse wheel resizes; a left click belongs to the section.
-- ===========================================================================

local HUD = {}
ns.HUD = HUD

local PAD_X, PAD_Y = 8, 6
local ICON         = 14   -- one text line high
local ICON_GAP     = 4    -- between an icon and its text
local GAP          = 6
local LINE_H       = 15
local RULE_GAP     = 4    -- above and below the line between two sections
local MIN_W, MAX_W = 120, 260
local ROW_FONT     = "GameFontHighlightSmall"   -- what the rows use unless the player picked a font

HUD.ALPHA_STEP = 0.1

HUD.SCALE_MIN, HUD.SCALE_MAX, HUD.SCALE_STEP = 0.6, 1.8, 0.1

local frame
local sections = {}   -- definitions, sorted by order

-- ---------------------------------------------------------------------------
-- Position and size
-- ---------------------------------------------------------------------------

local function ApplyPosition()
	local s = ns.db.hud
	frame:ClearAllPoints()
	frame:SetPoint(s.point, UIParent, s.relPoint, s.x, s.y)
end

function HUD.SetScale(scale)
	scale = math.max(HUD.SCALE_MIN, math.min(HUD.SCALE_MAX, scale))
	scale = math.floor(scale * 10 + 0.5) / 10
	ns.db.hud.scale = scale
	if frame then frame:SetScale(scale) end
	ns.RefreshOptions()
end

function HUD.ResetPosition()
	local s, d = ns.db.hud, ns.defaults.hud
	s.point, s.relPoint, s.x, s.y = d.point, d.relPoint, d.x, d.y
	if frame then ApplyPosition() end
end

-- ---------------------------------------------------------------------------
-- Look: background, border, font
-- ---------------------------------------------------------------------------

-- The background can fade out completely; the border is a switch of its own.
local function ApplyBox(alert)
	local s = ns.db.hud
	local r, g, b = Skin.Color("bg")
	frame:SetBackdropColor(r, g, b, s.bgAlpha)
	-- the border says it too: accent when fine, amber when a section wants attention
	r, g, b = Skin.Color(alert and "warn" or "accent")
	frame:SetBackdropBorderColor(r, g, b, s.border and 1 or 0)
end

-- Only the typeface changes: size and flags stay those of the rows' own font.
local function ApplyFont(fs)
	local file = ns.db.hud.font
	local object = _G[ROW_FONT]
	if file and object and object.GetFont then
		local _, size, flags = object:GetFont()
		local ok, valid = pcall(fs.SetFont, fs, file, size or 12, flags or "")
		if ok and valid ~= false and fs:GetFont() then return end
		-- the file is gone (it came from an addon that no longer is): the game's font again
	end
	fs:SetFontObject(ROW_FONT)
	fs:SetTextColor(Skin.Color("text"))   -- a font object brings its own colour along
end

function HUD.SetBackgroundAlpha(alpha)
	alpha = math.max(0, math.min(1, alpha))
	ns.db.hud.bgAlpha = math.floor(alpha * 10 + 0.5) / 10
	HUD.Refresh()
	ns.RefreshOptions()
end

function HUD.SetBorder(on)
	ns.db.hud.border = on and true or false
	HUD.Refresh()
end

-- file: a font file, or nil for the game's own; name: what the settings show for it
function HUD.SetFont(file, name)
	ns.db.hud.font, ns.db.hud.fontName = file, file and name or nil
	if frame then
		for _, section in pairs(frame.sections) do
			for _, r in ipairs(section.rows) do
				ApplyFont(r.label); ApplyFont(r.value); ApplyFont(r.right)
			end
		end
	end
	HUD.Refresh()
	ns.RefreshOptions()
end

-- Dragging and resizing work from anywhere on the box, sections included.
local function MakeHandle(widget)
	widget:EnableMouseWheel(true)
	widget:RegisterForDrag("LeftButton")
	widget:SetScript("OnDragStart", function()
		if not ns.db.hud.locked then frame:StartMoving() end
	end)
	widget:SetScript("OnDragStop", function()
		frame:StopMovingOrSizing()
		local point, _, relPoint, x, y = frame:GetPoint()
		local s = ns.db.hud
		s.point, s.relPoint, s.x, s.y = point, relPoint, math.floor(x + 0.5), math.floor(y + 0.5)
	end)
	widget:SetScript("OnMouseWheel", function(_, delta)
		if IsControlKeyDown() then HUD.SetScale(ns.db.hud.scale + delta * HUD.SCALE_STEP) end
	end)
end

local function CreateHUD()
	local f = CreateFrame("Frame", "CombatKitHUD", UIParent, "BackdropTemplate")
	f:SetSize(MIN_W, PAD_Y * 2 + LINE_H)
	f:SetFrameStrata("MEDIUM")
	f:SetClampedToScreen(true)
	f:SetMovable(true)
	f:EnableMouse(true)
	Skin.Backdrop(f, "bg", ns.db.hud.bgAlpha, "accent")
	MakeHandle(f)
	f:SetScript("OnMouseUp", function(_, button)
		if button == "RightButton" then ns.ToggleOptions() end
	end)
	f.sections = {}   -- section frames, by key
	f.rules = {}
	f:SetScale(ns.db.hud.scale)
	frame = f
	ApplyPosition()
	return f
end

-- ---------------------------------------------------------------------------
-- Sections
-- ---------------------------------------------------------------------------

local function ShowTooltip(self)
	GameTooltip:SetOwner(frame, "ANCHOR_BOTTOM")
	GameTooltip:AddLine("|cff66ccffCombat|rKit")
	if self.def.OnTooltip then self.def.OnTooltip(GameTooltip) end
	GameTooltip:AddLine(" ")
	GameTooltip:AddLine(L["HUD_HINT"], Skin.Color("dim"))
	GameTooltip:Show()
end

local function SectionFrame(def)
	local s = frame.sections[def.key]
	if not s then
		s = CreateFrame("Button", nil, frame)
		s:RegisterForClicks("LeftButtonUp", "RightButtonUp")
		s:SetScript("OnClick", function(self, button)
			if button == "RightButton" then
				ns.ToggleOptions()
			elseif self.def.OnClick then
				self.def.OnClick()
			end
		end)
		s:SetScript("OnEnter", ShowTooltip)
		s:SetScript("OnLeave", GameTooltip_Hide)
		MakeHandle(s)
		s.rows = {}
		frame.sections[def.key] = s
	end
	s.def = def
	return s
end

local function RowWidgets(section, index)
	local r = section.rows[index]
	if not r then
		local function Text(justify)
			local fs = Skin.Label(section, "")
			if ns.db.hud.font then ApplyFont(fs) end
			fs:SetJustifyH(justify)
			fs:SetWordWrap(false)
			return fs
		end
		r = { label = Text("LEFT"), value = Text("LEFT"), right = Text("RIGHT") }
		r.icon = section:CreateTexture(nil, "ARTWORK")
		r.icon:SetSize(ICON, ICON)
		r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		local y = -(index - 1) * LINE_H
		r.icon:SetPoint("TOPLEFT", PAD_X, y)
		r.label:SetPoint("TOPLEFT", PAD_X, y - 1)
		r.right:SetPoint("TOPRIGHT", -PAD_X, y - 1)
		r.y = y - 1
		section.rows[index] = r
	end
	return r
end

local function IsSecret(v) return issecretvalue ~= nil and issecretvalue(v) end

-- The width of a text, or `fallback` when the game will not tell (secret text).
local function TextWidth(fs, fallback)
	local w = fs:GetStringWidth()
	if IsSecret(w) then return fallback or 44 end
	return w
end

local function SetValue(fs, row)
	if row.fmt then
		-- formatted by the game; if even that is refused, keep what was there
		if not pcall(fs.SetFormattedText, fs, row.fmt, row.num) then fs:SetText(row.value or "?") end
	else
		fs:SetText(row.value or "")
	end
end

local function SortSections()
	table.sort(sections, function(a, b) return (a.order or 0) < (b.order or 0) end)
end

function HUD.AddSection(def)
	for i, s in ipairs(sections) do
		if s.key == def.key then table.remove(sections, i); break end
	end
	sections[#sections + 1] = def
	SortSections()
	HUD.Refresh()
end

function HUD.RemoveSection(key)
	for i, s in ipairs(sections) do
		if s.key == key then table.remove(sections, i); break end
	end
	if frame and frame.sections[key] then frame.sections[key]:Hide() end
	HUD.Refresh()
end

function HUD.Refresh()
	if not ns.db then return end
	local force = ns.IsOptionsShown()   -- always visible while the settings are open

	local shown = {}
	if ns.db.hud.show ~= "never" or force then
		for _, def in ipairs(sections) do
			local rows, alert = def.GetRows(force)
			if rows and #rows > 0 then shown[#shown + 1] = { def = def, rows = rows, alert = alert } end
		end
	end
	if #shown == 0 then
		if frame then frame:Hide() end
		return
	end
	if not frame then CreateHUD() end

	-- texts first: the columns are as wide as the widest of them. A row with an
	-- icon stands apart: its text follows the icon, whatever the label column needs.
	local column, widest, iconRow, alert = 0, 0, 0, false
	local used = {}
	for _, entry in ipairs(shown) do
		local section = SectionFrame(entry.def)
		used[entry.def.key] = true
		alert = alert or entry.alert
		for i, row in ipairs(entry.rows) do
			local r = RowWidgets(section, i)
			r.icon:SetShown(row.icon ~= nil)
			if row.icon then r.icon:SetTexture(row.icon) end
			r.label:SetText(row.icon and "" or Skin.Text("dim", row.label or ""))
			SetValue(r.value, row)
			r.right:SetText(row.right or "")
			r.label:Show(); r.value:Show(); r.right:Show()
			local width = TextWidth(r.value, row.width)
			if row.right and row.right ~= "" then width = width + 12 + TextWidth(r.right) end
			if row.icon then
				iconRow = math.max(iconRow, ICON + ICON_GAP + width)
			else
				column = math.max(column, TextWidth(r.label))
				widest = math.max(widest, width)
			end
		end
		for i = #entry.rows + 1, #section.rows do
			local r = section.rows[i]
			r.icon:Hide(); r.label:Hide(); r.value:Hide(); r.right:Hide()
		end
	end
	for key, section in pairs(frame.sections) do
		if not used[key] then section:Hide() end
	end

	local valueX = PAD_X + column + GAP
	local width = math.max(MIN_W, math.min(MAX_W, math.max(valueX + widest, PAD_X + iconRow) + PAD_X))
	local y = -PAD_Y
	for i, entry in ipairs(shown) do
		if i > 1 then
			local rule = frame.rules[i - 1]
			if not rule then
				rule = Skin.Fill(frame, "ARTWORK", "border", 0.6)
				rule:SetHeight(1)
				frame.rules[i - 1] = rule
			end
			rule:ClearAllPoints()
			rule:SetPoint("TOPLEFT", PAD_X, y - RULE_GAP)
			rule:SetPoint("TOPRIGHT", -PAD_X, y - RULE_GAP)
			rule:Show()
			y = y - RULE_GAP * 2 - 1
		end
		local section = frame.sections[entry.def.key]
		local height = #entry.rows * LINE_H
		section:ClearAllPoints()
		section:SetPoint("TOPLEFT", 0, y)
		section:SetSize(width, height)
		for index, row in ipairs(entry.rows) do
			local r = section.rows[index]
			r.value:ClearAllPoints()
			if row.icon then
				r.value:SetJustifyH("LEFT")
				r.value:SetPoint("TOPLEFT", PAD_X + ICON + ICON_GAP, r.y)
			elseif not (row.right and row.right ~= "") then
				-- flush with the right edge, like a table; needs no width, so it also suits a
				-- text the game will not measure
				r.value:SetJustifyH("RIGHT")
				r.value:SetPoint("TOPRIGHT", -PAD_X, r.y)
			else
				r.value:SetJustifyH("LEFT")
				r.value:SetPoint("TOPLEFT", valueX, r.y)
			end
		end
		section:Show()
		y = y - height
	end
	for i = #shown, #frame.rules do frame.rules[i]:Hide() end

	ApplyBox(alert)
	frame:SetSize(width, -y + PAD_Y)
	frame:Show()
end

-- for the settings and the tests
function HUD.GetFrame() return frame end
