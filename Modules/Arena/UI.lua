local ADDON, ns = ...
local CK = CombatKit
local L = CK.L

-- ===========================================================================
-- The rows: one per teammate (and one for the player), icons in the order of
-- the spell list. Every icon reads the tracker's state and draws it:
--
--   ready     bright
--   active    bright, a glow around it (the buff is up)
--   cooling   dark, a cooldown swipe with the time left
--   unknown   dark, a "?" in the middle
--
-- a charge count in the corner when the ability has more than one, a small
-- "?" when the use may belong to another teammate as well, a dot while the
-- cooldown is the base value and not yet the teammate's own. When detection
-- is broken the rows dim as a whole. Rows are positioned by hand for now;
-- unlocked, they show sample icons and can be dragged.
-- ===========================================================================

local UI = {}
ns.UI = UI

local rows = {}
local locked = true
local dirty = true
local UNITS = { "player", "party1", "party2" }

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
	f:SetScript("OnDragStart", function(self) if not locked then self:StartMoving() end end)
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
	icon.glow = icon:CreateTexture(nil, "OVERLAY")
	icon.glow:SetPoint("TOPLEFT", -3, 3)
	icon.glow:SetPoint("BOTTOMRIGHT", 3, -3)
	icon.glow:SetColorTexture(1, 0.85, 0.3, 0.45)
	icon.glow:Hide()
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

local function Layout(row, n)
	local db = ns.db
	local size, gap = db.iconSize, db.spacing
	for i = 1, n do
		local icon = Icon(row, i)
		icon:SetSize(size, size)
		icon:ClearAllPoints()
		if db.grow == "down" then
			icon:SetPoint("TOPLEFT", row, "TOPLEFT", 0, -(i - 1) * (size + gap))
		else
			icon:SetPoint("TOPLEFT", row, "TOPLEFT", (i - 1) * (size + gap), 0)
		end
		icon:Show()
	end
	for i = n + 1, #row.icons do row.icons[i]:Hide() end
	if db.grow == "down" then
		row:SetSize(size, math.max(1, n) * (size + gap) - gap)
	else
		row:SetSize(math.max(1, n) * (size + gap) - gap, size)
	end
end

-- one icon from one entry
local function Draw(icon, e, at)
	local state, readyAt, left, nextAt = ns.Tracker.State(e, at)
	icon.tex:SetTexture(C_Spell.GetSpellTexture(e.def.id))
	icon.tex:SetDesaturated(state == "cooling" or state == "unknown")
	icon.tex:SetAlpha(state == "unknown" and 0.6 or 1)
	icon.glow:SetShown(state == "active")
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

-- a row of sample icons: the player's own class, every ability ready
local function DrawSample(row)
	local _, class = UnitClass("player")
	local defs = ns.SpellsFor(class, ns.db.externals)
	Layout(row, #defs)
	for i, def in ipairs(defs) do
		local icon = row.icons[i]
		icon.tex:SetTexture(C_Spell.GetSpellTexture(def.id))
		icon.tex:SetDesaturated(false)
		icon.tex:SetAlpha(1)
		icon.glow:Hide()
		icon.mark:Hide()
		icon.amb:Hide()
		icon.dot:Hide()
		icon.cd:Clear()
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
		local r = ns.db.rows[unit]
		row:ClearAllPoints()
		row:SetPoint(r.point, UIParent, r.relPoint, r.x, r.y)
		if not locked then
			DrawSample(row)
			row:SetAlpha(1)
			row:Show()
		else
			local t = ns.Tracker.Get(unit)
			if t and (unit ~= "player" or ns.db.showSelf) and #t.order > 0 then
				Layout(row, #t.order)
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

-- unlocked: every row shows sample icons, a label, and can be dragged
function UI.SetLocked(state)
	locked = state and true or false
	for _, unit in ipairs(UNITS) do
		local row = Row(unit)
		row:EnableMouse(not locked)
		row.bg:SetShown(not locked)
		row.label:SetText(L["ARENA_" .. unit])
		row.label:SetShown(not locked)
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

function UI.Rows() return rows end
