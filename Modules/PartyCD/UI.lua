local ADDON, ns = ...
local CK = CombatKit
local L = CK.L

-- ===========================================================================
-- The rows: one per teammate (and one for the player), icons in the order of
-- the spell list, hung on the teammate's party frame when one can be found,
-- at a position of their own otherwise. Every icon reads the tracker's state
-- and draws it:
--
--   ready     bright
--   active    bright, a breathing halo (the aura is up): green for a
--             defensive, yellow for an immunity or a big external, red for
--             a burst, violet for a crowd control on an opponent
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
	local f = CreateFrame("Frame", "CombatKitPartyCD_" .. unit, UIParent)
	f.unit = unit
	f.icons = {}
	f:SetSize(32, 32)
	f:SetFrameStrata("MEDIUM")
	f:SetMovable(true)
	f:SetClampedToScreen(true)
	f:EnableMouse(false)
	f:RegisterForDrag("LeftButton")
	-- while it is dragged the redraws leave its position alone; dropped, the
	-- point the icons grow from is saved, so a longer or shorter row later
	-- grows away from where it was put
	f:SetScript("OnDragStart", function(self)
		if locked or self.anchor then return end
		self.moving = true
		self:StartMoving()
	end)
	f:SetScript("OnDragStop", function(self)
		if not self.moving then return end
		self:StopMovingOrSizing()
		self.moving = false
		UI.SaveRow(self)
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

-- the halo's colour by what the ability is: green for a defensive, yellow
-- for an immunity or a big external, red for a burst, violet for a crowd control
local GLOW = {
	defensive = { 0.25, 0.95, 0.35 },
	major     = { 1.00, 0.85, 0.20 },
	burst     = { 1.00, 0.25, 0.25 },
	cc        = { 0.70, 0.45, 1.00 },
}

local function Colour(icon, def)
	local c = GLOW[def.glow] or GLOW.defensive
	if icon.glowKind == def.glow then return end
	icon.glowKind = def.glow
	for _, t in ipairs(icon.border) do t:SetColorTexture(c[1], c[2], c[3], 0.9) end
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
	-- the active glow: a frame around the icon with four strips in the accent
	-- colour, breathing while the buff is up
	icon.halo = CreateFrame("Frame", nil, icon)
	icon.halo:SetPoint("TOPLEFT", -3, 3)
	icon.halo:SetPoint("BOTTOMRIGHT", 3, -3)
	icon.halo:Hide()
	icon.border = {}
	for k = 1, 4 do
		icon.border[k] = icon.halo:CreateTexture(nil, "OVERLAY")
	end
	icon.border[1]:SetPoint("TOPLEFT")
	icon.border[1]:SetPoint("TOPRIGHT")
	icon.border[1]:SetHeight(3)
	icon.border[2]:SetPoint("BOTTOMLEFT")
	icon.border[2]:SetPoint("BOTTOMRIGHT")
	icon.border[2]:SetHeight(3)
	icon.border[3]:SetPoint("TOPLEFT")
	icon.border[3]:SetPoint("BOTTOMLEFT")
	icon.border[3]:SetWidth(3)
	icon.border[4]:SetPoint("TOPRIGHT")
	icon.border[4]:SetPoint("BOTTOMRIGHT")
	icon.border[4]:SetWidth(3)
	icon.pulse = icon.halo:CreateAnimationGroup()
	icon.pulse:SetLooping("BOUNCE")
	local fade = icon.pulse:CreateAnimation("Alpha")
	fade:SetFromAlpha(1)
	fade:SetToAlpha(0.25)
	fade:SetDuration(0.5)
	fade:SetSmoothing("IN_OUT")
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
	if on then
		if not icon.halo:IsShown() then
			icon.halo:Show()
			icon.pulse:Play()
		end
	elseif icon.halo:IsShown() then
		icon.pulse:Stop()
		icon.halo:Hide()
	end
end

-- The side of the frame a row hangs on, and how its lines line up. A row
-- by the frame's left or right runs away from the frame (to the right of a
-- right-hand row, to the left of a left-hand one) and its lines go down from
-- the frame's top, up from its bottom, or sit centred on its middle: grow
-- "down", "up" or "center". A row above or below runs along the frame's edge
-- and its lines stack away from the frame; they start at the frame's left
-- end, its right end, or are centred: grow "right", "left" or "center". A
-- loose row (no frame, or not attached) is laid out the same way, from the
-- point it was dragged to.
local GROWS_FOR = {
	RIGHT  = { down = true, up = true, center = true },
	LEFT   = { down = true, up = true, center = true },
	TOP    = { right = true, left = true, center = true },
	BOTTOM = { right = true, left = true, center = true },
}

local function Side() return GROWS_FOR[ns.db.side] and ns.db.side or "RIGHT" end

-- the grow that goes with a side: the one asked for when it fits, else the first
function UI.GrowFor(side, grow)
	local fits = GROWS_FOR[side] or GROWS_FOR.RIGHT
	if fits[grow] then return grow end
	return (side == "TOP" or side == "BOTTOM") and "right" or "down"
end

-- the row's point, the frame's point, and which way the offset goes
local function Points(side, grow)
	if side == "TOP" or side == "BOTTOM" then
		local h = (grow == "left" and "RIGHT") or (grow == "center" and "") or "LEFT"
		if side == "TOP" then return "BOTTOM" .. h, "TOP" .. h, 0, 1 end
		return "TOP" .. h, "BOTTOM" .. h, 0, -1
	end
	local v = (grow == "up" and "BOTTOM") or (grow == "center" and "") or "TOP"
	if side == "LEFT" then return v .. "RIGHT", v .. "LEFT", -1, 0 end
	return v .. "LEFT", v .. "RIGHT", 1, 0
end

-- hang the row on its unit's frame, or put it at its own position; returns
-- the layout { side, grow } for the icons. A row being dragged keeps where it is.
local function Place(row)
	local db = ns.db
	local side = Side()
	local spec = { side = side, grow = UI.GrowFor(side, db.grow) }
	local frame = db.attach and FindFrame(row.unit) or nil
	row.anchor = frame
	if row.moving then return spec end
	row:ClearAllPoints()
	if frame then
		local point, rel, dx, dy = Points(spec.side, spec.grow)
		local x = dx ~= 0 and dx * db.offset or db.offsetAlong
		local y = dy ~= 0 and dy * db.offset or db.offsetAlong
		row:SetPoint(point, frame, rel, x, y)
		return spec
	end
	local r = db.rows[row.unit]
	row:SetPoint(r.point, UIParent, r.relPoint, r.x, r.y)
	return spec
end

-- a dropped row: where the point it is laid out from is, measured from the
-- screen's bottom left corner
function UI.SaveRow(row)
	local left, bottom, width, height = row:GetRect()
	if not left then return end
	local side = Side()
	local point = Points(side, UI.GrowFor(side, ns.db.grow))
	local x = point:find("LEFT") and left or (point:find("RIGHT") and left + width) or left + width / 2
	local y = point:find("TOP") and bottom + height or (point:find("BOTTOM") and bottom) or bottom + height / 2
	local r = ns.db.rows[row.unit]
	r.point, r.relPoint, r.x, r.y = point, "BOTTOMLEFT", math.floor(x + 0.5), math.floor(y + 0.5)
	row:ClearAllPoints()
	row:SetPoint(r.point, UIParent, r.relPoint, r.x, r.y)
end

-- the icons inside a row: lines of up to maxPerRow, laid out as Place says
local function Layout(row, n, spec)
	local db = ns.db
	local size, gap, per = db.iconSize, db.spacing, math.max(1, db.maxPerRow)
	local step = size + gap
	local along = spec.side == "TOP" or spec.side == "BOTTOM"
	local fromRight = spec.side == "LEFT" or (along and spec.grow == "left")
	local centred = along and spec.grow == "center"
	local upward = spec.side == "TOP" or (not along and spec.grow == "up")
	local v = upward and "BOTTOM" or "TOP"
	-- the countdown's font follows the icon: the game's number font is too wide for a small icon
	local font = size < 34 and "NumberFontNormalSmall" or "NumberFontNormal"
	for i = 1, n do
		local icon = Icon(row, i)
		icon:SetSize(size, size)
		if icon.font ~= font then
			icon.font = font
			pcall(icon.cd.SetCountdownFont, icon.cd, font)
		end
		icon:ClearAllPoints()
		local col, line = (i - 1) % per, math.floor((i - 1) / per)
		local y = upward and line * step or -line * step
		if centred then
			local inLine = math.min(per, n - line * per)   -- the last line may be shorter: centred too
			icon:SetPoint(v, row, v, (col - (inLine - 1) / 2) * step, y)
		elseif fromRight then
			icon:SetPoint(v .. "RIGHT", row, v .. "RIGHT", -col * step, y)
		else
			icon:SetPoint(v .. "LEFT", row, v .. "LEFT", col * step, y)
		end
		icon:Show()
	end
	for i = n + 1, #row.icons do row.icons[i]:Hide() end
	local cols, lines = math.min(math.max(n, 1), per), math.max(1, math.ceil(n / per))
	row:SetSize(cols * step - gap, lines * step - gap)
end

-- one icon from one entry
local function Draw(icon, e, at)
	local state, readyAt, left, nextAt = ns.Tracker.State(e, at)
	icon.tex:SetTexture(C_Spell.GetSpellTexture(e.def.id))
	icon.tex:SetDesaturated(state == "cooling" or state == "unknown")
	icon.tex:SetAlpha(state == "unknown" and 0.6 or 1)
	Colour(icon, e.def)
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
	if e.charges > 1 and state ~= "unknown" then
		icon.count:SetText(left)
		icon.count:Show()
	else
		icon.count:Hide()
	end
end

-- The PvP trinket, first in a row: the game keeps a Duration for every
-- player's crowd control cooldown in an arena and hands it over, secret or
-- not; fed to the icon's Cooldown it draws itself. Nothing is read back.
-- Which spell it is (the medallion, or a racial that shares its cooldown)
-- the game says as well, once asked (RequestCrowdControlSpell); the
-- medallion's icon stands in until then.
local MEDALLION = 336126   -- Gladiator's Medallion

local function TrinketSpell(unit)
	if not (unit and C_PvP and C_PvP.GetArenaCrowdControlInfo) then return nil end
	local ok, id = pcall(C_PvP.GetArenaCrowdControlInfo, unit)
	if ok and type(id) == "number" and plain(id) and id > 0 then return id end
end

local function DrawTrinket(icon, unit)
	icon.tex:SetTexture(C_Spell.GetSpellTexture(TrinketSpell(unit) or MEDALLION))
	icon.tex:SetDesaturated(false)
	icon.tex:SetAlpha(1)
	SetActive(icon, false)
	icon.mark:Hide()
	icon.amb:Hide()
	icon.dot:Hide()
	icon.count:Hide()
	if unit and C_PvP and C_PvP.GetArenaCrowdControlDuration then
		local ok, duration = pcall(C_PvP.GetArenaCrowdControlDuration, unit)
		if ok and duration ~= nil then
			if pcall(icon.cd.SetCooldownFromDurationObject, icon.cd, duration, true) then return end
		end
	end
	icon.cd:Clear()
end

-- a row of sample icons: the player's own class, one of each look: the
-- first with its buff up, the second cooling with the estimate dot, the
-- third unknown, the rest ready; the trinket in front when it is on
local function DrawSample(row, spec, at)
	local _, class = UnitClass("player")
	local defs = ns.SpellsFor(class, ns.Selection())
	local lead = ns.db.trinket and 1 or 0
	Layout(row, #defs + lead, spec)
	if lead == 1 then DrawTrinket(row.icons[1], nil) end
	for i, def in ipairs(defs) do
		local icon = row.icons[i + lead]
		icon.tex:SetTexture(C_Spell.GetSpellTexture(def.id))
		icon.tex:SetDesaturated(i == 2 or i == 3)
		icon.tex:SetAlpha(i == 3 and 0.6 or 1)
		Colour(icon, def)
		SetActive(icon, i == 1)
		icon.mark:SetShown(i == 3)
		icon.amb:SetShown(i == 2 and def.kind == "external")
		icon.dot:SetShown(i == 2)
		if i == 2 then icon.cd:SetCooldown(at - 12, def.cd) else icon.cd:Clear() end
		local charges = ns.BaseCharges(def)
		if charges > 1 then icon.count:SetText(charges) icon.count:Show() else icon.count:Hide() end
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
			local spec = Place(row)
			DrawSample(row, spec, at)
			row.label:SetText(L["PARTYCD_" .. unit])
			row.bg:SetShown(not locked and row.anchor == nil)
			row.warn:Hide()
			row:SetAlpha(1)
			row:Show()
		else
			local t = ns.Tracker.Get(unit)
			if t and (unit ~= "player" or ns.db.showSelf) and #t.order > 0 then
				local spec = Place(row)
				local lead = ns.db.trinket and 1 or 0
				Layout(row, #t.order + lead, spec)
				if lead == 1 then DrawTrinket(row.icons[1], unit) end
				for i, id in ipairs(t.order) do Draw(row.icons[i + lead], t.spells[id], at) end
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
