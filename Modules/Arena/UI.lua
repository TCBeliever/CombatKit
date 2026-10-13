local ADDON, ns = ...
local CK = CombatKit
local L, Skin = CK.L, CK.Skin

-- ===========================================================================
-- The rows: one per teammate (and one for the player), icons in the order of
-- the spell list, hung on the teammate's party frame when one can be found,
-- at a position of their own otherwise. Every icon reads the tracker's state
-- and draws it:
--
--   ready     bright
--   active    bright, a border in the theme's accent (the buff is up)
--   cooling   dark, a cooldown swipe with the time left
--   unknown   dark, a "?" in the middle
--
-- a charge count in the corner when the ability has more than one, a small
-- "?" when the use may belong to another teammate as well, a dot while the
-- cooldown is the base value and not yet the teammate's own. When detection
-- is broken the rows dim as a whole. Unlocked, the rows show sample icons
-- and the loose ones can be dragged.
-- ===========================================================================

local UI = {}
ns.UI = UI

local rows = {}
local locked = true
local testing = false   -- sample rows on screen wherever you are, to see the look
local dirty = true
local UNITS = { "player", "party1", "party2" }

local function plain(v) return type(canaccessvalue) ~= "function" or canaccessvalue(v) end

-- ---------------------------------------------------------------------------
-- Finding the frame that shows a unit. A frame counts when it is visible and
-- names the unit, by its "unit" attribute or a plain `unit` field; a frame
-- that names the same player by another token (raid2 for party1, the player's
-- own frame) counts by GUID. Never UnitIsUnit: it answers with a secret in an
-- arena. Sorted or replaced party frames are asked first, the game's own last.
-- ---------------------------------------------------------------------------

local function UnitOf(frame)
	local ok, u = pcall(frame.GetAttribute, frame, "unit")
	if ok and type(u) == "string" and plain(u) then return u end
	local v = rawget(frame, "unit")
	if type(v) == "string" and plain(v) then return v end
end

local function Shows(frame, unit)
	if type(frame) ~= "table" then return false end
	if frame.IsForbidden then
		local okF, forbidden = pcall(frame.IsForbidden, frame)
		if okF and forbidden then return false end   -- a frame the client has taken away from addons
	end
	local okV, visible = pcall(frame.IsVisible, frame)
	if not okV or not visible then return false end
	local u = UnitOf(frame)
	if not u then return false end
	if u == unit then return true end
	local g1, g2 = UnitGUID(u), UnitGUID(unit)
	return type(g1) == "string" and plain(g1) and plain(g2) and g1 == g2
end

-- the first frame in a list (or a list of lists) that shows the unit
local function FirstShowing(list, unit, depth)
	if type(list) ~= "table" or (depth or 0) > 3 then return nil end
	for _, f in pairs(list) do
		if type(f) == "table" then
			if f.IsVisible then
				if Shows(f, unit) then return f end
			else
				local hit = FirstShowing(f, unit, (depth or 0) + 1)
				if hit then return hit end
			end
		end
	end
end

local PROVIDERS = {
	-- FrameSort: the party frames as it sorted them
	function(unit)
		local sorting = FrameSortApi and FrameSortApi.v3 and FrameSortApi.v3.Sorting
		if sorting and sorting.GetPartyFrames then
			local ok, frames = pcall(sorting.GetPartyFrames, sorting)
			if ok then return FirstShowing(frames, unit) end
		end
	end,
	-- DandersFrames
	function(unit)
		if DandersFrames_GetAllFrames then
			local ok, frames = pcall(DandersFrames_GetAllFrames)
			if ok then return FirstShowing(frames, unit) end
		end
	end,
	-- EllesmereUI
	function(unit)
		if EllesmereUI and EllesmereUI.GetUnitFrame then
			local ok, f = pcall(EllesmereUI.GetUnitFrame, unit)
			if ok and Shows(f, unit) then return f end
		end
	end,
	-- the game's own: compact party frames, the standard party frames, raid
	-- frames flat or kept in groups; the player frame for the player
	function(unit)
		if unit == "player" and Shows(PlayerFrame, unit) then return PlayerFrame end
		local party = (MAX_PARTY_MEMBERS or 4) + 1
		for i = 1, party do
			local f = _G["CompactPartyFrameMember" .. i]
			if Shows(f, unit) then return f end
			f = PartyFrame and PartyFrame["MemberFrame" .. i]
			if Shows(f, unit) then return f end
		end
		for i = 1, party do
			local f = _G["CompactRaidFrame" .. i]
			if Shows(f, unit) then return f end
			f = _G["CompactRaidGroup1Member" .. i]
			if Shows(f, unit) then return f end
		end
	end,
}

local function FindFrame(unit)
	for _, find in ipairs(PROVIDERS) do
		local f = find(unit)
		if f then return f end
	end
end

-- ---------------------------------------------------------------------------
-- Rows and icons
-- ---------------------------------------------------------------------------

local function Row(unit)
	if rows[unit] then return rows[unit] end
	local f = CreateFrame("Frame", "CombatKitArena_" .. unit, UIParent)
	f.unit = unit
	f.icons = {}
	f:SetSize(32, 32)
	f:SetFrameStrata("MEDIUM")
	f:SetMovable(true)
	f:SetClampedToScreen(true)
	f:EnableMouse(false)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", function(self) if not locked and not self.anchor then self:StartMoving() end end)
	f:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		local point, _, relPoint, x, y = self:GetPoint()
		local r = ns.db.rows[self.unit]
		r.point, r.relPoint, r.x, r.y = point, relPoint, math.floor(x + 0.5), math.floor(y + 0.5)
	end)
	f.bg = f:CreateTexture(nil, "BACKGROUND")
	f.bg:SetAllPoints()
	f.bg:SetColorTexture(0.2, 0.6, 1.0, 0.35)
	f.bg:Hide()
	f.label = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	f.label:SetPoint("BOTTOM", f, "TOP", 0, 2)
	f.label:Hide()
	f.warn = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	f.warn:SetPoint("LEFT", f, "RIGHT", 4, 0)
	f.warn:SetText("!")
	f.warn:Hide()
	f:Hide()
	rows[unit] = f
	return f
end

local function Accent(tex)
	if Skin.Paint then
		Skin.Paint(tex, function(t) t:SetColorTexture(Skin.Color("accent")) end)
	else
		tex:SetColorTexture(Skin.Color("accent"))
	end
end

local function Icon(row, i)
	local icon = row.icons[i]
	if icon then return icon end
	icon = CreateFrame("Frame", nil, row)
	icon.tex = icon:CreateTexture(nil, "ARTWORK")
	icon.tex:SetAllPoints()
	icon.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	icon.cd = CreateFrame("Cooldown", nil, icon, "CooldownFrameTemplate")
	icon.cd:SetAllPoints()
	icon.cd:SetDrawEdge(false)
	icon.cd:SetHideCountdownNumbers(false)
	-- the active border: four strips just outside the icon
	icon.border = {}
	for k = 1, 4 do
		local t = icon:CreateTexture(nil, "OVERLAY")
		Accent(t)
		t:Hide()
		icon.border[k] = t
	end
	icon.border[1]:SetPoint("BOTTOMLEFT", icon, "TOPLEFT", -2, 0)
	icon.border[1]:SetPoint("BOTTOMRIGHT", icon, "TOPRIGHT", 2, 0)
	icon.border[1]:SetHeight(2)
	icon.border[2]:SetPoint("TOPLEFT", icon, "BOTTOMLEFT", -2, 0)
	icon.border[2]:SetPoint("TOPRIGHT", icon, "BOTTOMRIGHT", 2, 0)
	icon.border[2]:SetHeight(2)
	icon.border[3]:SetPoint("TOPRIGHT", icon, "TOPLEFT", 0, 0)
	icon.border[3]:SetPoint("BOTTOMRIGHT", icon, "BOTTOMLEFT", 0, 0)
	icon.border[3]:SetWidth(2)
	icon.border[4]:SetPoint("TOPLEFT", icon, "TOPRIGHT", 0, 0)
	icon.border[4]:SetPoint("BOTTOMLEFT", icon, "BOTTOMRIGHT", 0, 0)
	icon.border[4]:SetWidth(2)
	icon.count = icon:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
	icon.count:SetPoint("BOTTOMRIGHT", -1, 1)
	icon.mark = icon:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	icon.mark:SetPoint("CENTER")
	icon.mark:SetText("?")
	icon.mark:Hide()
	icon.amb = icon:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	icon.amb:SetPoint("TOPLEFT", 1, -1)
	icon.amb:SetText("?")
	icon.amb:Hide()
	icon.dot = icon:CreateTexture(nil, "OVERLAY")
	icon.dot:SetSize(4, 4)
	icon.dot:SetPoint("TOPRIGHT", -2, -2)
	icon.dot:SetColorTexture(1, 1, 1, 0.9)
	icon.dot:Hide()
	row.icons[i] = icon
	return icon
end

local function SetActive(icon, on)
	for _, t in ipairs(icon.border) do t:SetShown(on) end
end

-- where a row hangs by the frame, per side: the row's point, the frame's
-- point, which way the offset goes, and which way the icons grow
local SIDES = {
	RIGHT  = { point = "TOPLEFT",    rel = "TOPRIGHT",   dx = 1,  dy = 0,  grow = "right" },
	LEFT   = { point = "TOPRIGHT",   rel = "TOPLEFT",    dx = -1, dy = 0,  grow = "left" },
	TOP    = { point = "BOTTOMLEFT", rel = "TOPLEFT",    dx = 0,  dy = 1,  grow = "right" },
	BOTTOM = { point = "TOPLEFT",    rel = "BOTTOMLEFT", dx = 0,  dy = -1, grow = "right" },
}

-- hang the row on its unit's frame, or put it at its own position; returns
-- the direction the icons grow
local function Place(row)
	local db = ns.db
	local frame = db.attach and FindFrame(row.unit) or nil
	row.anchor = frame
	row:ClearAllPoints()
	if frame then
		local s = SIDES[db.side] or SIDES.RIGHT
		local x = s.dx ~= 0 and s.dx * db.offset or db.offsetAlong
		local y = s.dy ~= 0 and s.dy * db.offset or db.offsetAlong
		row:SetPoint(s.point, frame, s.rel, x, y)
		return s.grow
	end
	local r = db.rows[row.unit]
	row:SetPoint(r.point, UIParent, r.relPoint, r.x, r.y)
	return db.grow
end

local function Layout(row, n, grow)
	local db = ns.db
	local size, gap, per = db.iconSize, db.spacing, math.max(1, db.maxPerRow)
	local step = size + gap
	for i = 1, n do
		local icon = Icon(row, i)
		icon:SetSize(size, size)
		icon:ClearAllPoints()
		local col, line = (i - 1) % per, math.floor((i - 1) / per)
		if grow == "down" then
			icon:SetPoint("TOPLEFT", row, "TOPLEFT", line * step, -col * step)
		elseif grow == "left" then
			icon:SetPoint("TOPRIGHT", row, "TOPRIGHT", -col * step, -line * step)
		else
			icon:SetPoint("TOPLEFT", row, "TOPLEFT", col * step, -line * step)
		end
		icon:Show()
	end
	for i = n + 1, #row.icons do row.icons[i]:Hide() end
	local cols, lines = math.min(math.max(n, 1), per), math.max(1, math.ceil(n / per))
	if grow == "down" then cols, lines = lines, cols end
	row:SetSize(cols * step - gap, lines * step - gap)
end

-- one icon from one entry
local function Draw(icon, e, at)
	local state, readyAt, left, nextAt = ns.Tracker.State(e, at)
	icon.tex:SetTexture(C_Spell.GetSpellTexture(e.def.id))
	icon.tex:SetDesaturated(state == "cooling" or state == "unknown")
	icon.tex:SetAlpha(state == "unknown" and 0.6 or 1)
	SetActive(icon, state == "active")
	icon.mark:SetShown(state == "unknown")
	icon.amb:SetShown(e.ambiguous and state ~= "ready" and state ~= "unknown")
	if state == "cooling" then
		icon.cd:SetCooldown(readyAt - e.cd, e.cd)
	elseif nextAt then
		icon.cd:SetCooldown(nextAt - e.cd, e.cd)   -- a charge recharging while another is left
	else
		icon.cd:Clear()
	end
	icon.dot:SetShown(e.estimate and (state == "cooling" or nextAt ~= nil))
	if e.def.charges > 1 and state ~= "unknown" then
		icon.count:SetText(left)
		icon.count:Show()
	else
		icon.count:Hide()
	end
end

-- a row of sample icons: the player's own class, one of each look: the
-- first with its buff up, the second cooling with the estimate dot, the
-- third unknown, the rest ready
local function DrawSample(row, grow, at)
	local _, class = UnitClass("player")
	local defs = ns.SpellsFor(class, ns.db.externals)
	Layout(row, #defs, grow)
	for i, def in ipairs(defs) do
		local icon = row.icons[i]
		icon.tex:SetTexture(C_Spell.GetSpellTexture(def.id))
		icon.tex:SetDesaturated(i == 2 or i == 3)
		icon.tex:SetAlpha(i == 3 and 0.6 or 1)
		SetActive(icon, i == 1)
		icon.mark:SetShown(i == 3)
		icon.amb:SetShown(i == 2 and def.kind == "external")
		icon.dot:SetShown(i == 2)
		if i == 2 then icon.cd:SetCooldown(at - 12, def.cd) else icon.cd:Clear() end
		if def.charges > 1 then icon.count:SetText(def.charges) icon.count:Show() else icon.count:Hide() end
	end
end

function UI.Dirty() dirty = true end

-- redraw every row from the tracker (or the samples while unlocked)
function UI.Refresh(at)
	at = at or GetTime()
	dirty = false
	for _, unit in ipairs(UNITS) do
		local row = Row(unit)
		if not locked or testing then
			local grow = Place(row)
			DrawSample(row, grow, at)
			row.label:SetText(L["ARENA_" .. unit])
			row.bg:SetShown(not locked and row.anchor == nil)
			row.warn:Hide()
			row:SetAlpha(1)
			row:Show()
		else
			local t = ns.Tracker.Get(unit)
			if t and (unit ~= "player" or ns.db.showSelf) and #t.order > 0 then
				local grow = Place(row)
				Layout(row, #t.order, grow)
				for i, id in ipairs(t.order) do Draw(row.icons[i], t.spells[id], at) end
				row:SetAlpha(ns.Tracker.failed and 0.35 or 1)
				row.warn:SetShown(ns.Tracker.failed)
				row:Show()
			else
				row:Hide()
			end
		end
	end
end

function UI.RefreshIfDirty(at)
	if dirty then UI.Refresh(at) end
end

function UI.IsLocked() return locked end
function UI.IsTesting() return testing end

-- sample rows on screen, in the world as in an arena, until switched off
function UI.SetTest(on)
	testing = on and true or false
	UI.Refresh()
end

-- unlocked: every row shows sample icons and a label; a loose one can be dragged
function UI.SetLocked(state)
	locked = state and true or false
	for _, unit in ipairs(UNITS) do
		local row = Row(unit)
		row:EnableMouse(not locked)
		row.label:SetShown(not locked)
		if locked then row.bg:Hide() end
	end
	UI.Refresh()
end

function UI.ResetPositions()
	for _, unit in ipairs(UNITS) do
		local d, r = ns.defaults.rows[unit], ns.db.rows[unit]
		r.point, r.relPoint, r.x, r.y = d.point, d.relPoint, d.x, d.y
	end
	UI.Refresh()
end

function UI.Hide()
	for _, row in pairs(rows) do row:Hide() end
end

-- once: whatever moves, re-binds or sorts the party frames marks the rows
-- dirty, and the next tick places them again. The game's compact frames say
-- so through CompactUnitFrame_SetUnit and _UpdateVisible (nameplates share
-- that code, so those are turned away by their back-reference); FrameSort
-- and DandersFrames through their post-sort callbacks.
function UI.Build()
	if UI.built then return end
	UI.built = true
	local function Changed(frame)
		if type(frame) == "table" and rawget(frame, "namePlateFrame") ~= nil then return end
		UI.Dirty()
	end
	if hooksecurefunc then
		if CompactUnitFrame_SetUnit then pcall(hooksecurefunc, "CompactUnitFrame_SetUnit", Changed) end
		if CompactUnitFrame_UpdateVisible then pcall(hooksecurefunc, "CompactUnitFrame_UpdateVisible", Changed) end
	end
	local sorting = FrameSortApi and FrameSortApi.v3 and FrameSortApi.v3.Sorting
	if sorting and sorting.RegisterPostSortCallback then
		pcall(sorting.RegisterPostSortCallback, sorting, function() UI.Dirty() end)
	end
	if DandersFrames and DandersFrames.RegisterCallback then
		UI.owner = UI.owner or CreateFrame("Frame")
		pcall(DandersFrames.RegisterCallback, UI.owner, "OnFramesSorted", function() UI.Dirty() end)
	end
end

function UI.Rows() return rows end
