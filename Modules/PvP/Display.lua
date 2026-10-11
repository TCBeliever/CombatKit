local ADDON, ns = ...
local CK = CombatKit
local U = ns.Util

-- ===========================================================================
-- The icons: one row per teammate (wrapping at "max per row"), next to his
-- party frame.
--
-- The frame is looked for in DandersFrames first (its frames carry `unit`),
-- then in the game's own compact party frames. Without one the row stands on
-- its own at a saved position and can be dragged while the settings have
-- "Unlock" ticked. A test mode shows sample rows outside arena.
--
-- The glow while a buff is up is drawn by the game: an AuraContainer slot over
-- the icon, filtered to the ability's buffs on the unit that carries them,
-- shows a border the moment the buff is there, without the scan's delay. Where
-- that cannot be set up, the tracker's own reading lights a plain border.
-- ===========================================================================

local D = {}
ns.Display = D

local rows = {}        -- unit -> row frame
local dirty = true
local testing = false
local unlocked = false
local lanes = {}       -- key "unit:id:holder" -> { host=, container=, icon= }
local laneFailed = false
local lanesPending = false

local SAMPLE = {
	party1 = { class = "PRIEST", spec = 256 },
	party2 = { class = "WARRIOR", spec = 71 },
}

function D.Dirty() dirty = true end
function D.IsTesting() return testing end
function D.IsLocked() return not unlocked end

-- ---------------------------------------------------------------------------
-- Where a teammate's frame is
-- ---------------------------------------------------------------------------

local function UnitOf(frame)
	local ok, unit = pcall(function()
		if frame.IsForbidden and frame:IsForbidden() then return nil end
		local u = frame.GetAttribute and frame:GetAttribute("unit")
		if type(u) ~= "string" or not canaccessvalue(u) then u = frame.unit end
		if type(u) == "string" and canaccessvalue(u) then return u end
	end)
	return ok and unit or nil
end

local function Visible(frame)
	local ok, v = pcall(frame.IsVisible, frame)
	return ok and v == true
end

-- the frame showing `unit`, and which addon draws it
function D.FindFrame(unit)
	local function match(frame)
		if not frame or not Visible(frame) then return false end
		local u = UnitOf(frame)
		return u == unit or (u ~= nil and UnitIsUnit(u, unit))
	end
	if type(DandersFrames_GetAllFrames) == "function" then
		local ok, frames = pcall(DandersFrames_GetAllFrames)
		if ok and type(frames) == "table" then
			for _, f in pairs(frames) do
				if match(f) then return f, "DandersFrames" end
			end
		end
	end
	-- FrameSort knows the frames it sorted, per provider
	local sorting = FrameSortApi and FrameSortApi.v3 and FrameSortApi.v3.Sorting
	if sorting and sorting.GetPartyFrames then
		local ok, byProvider = pcall(sorting.GetPartyFrames, sorting)
		if ok and type(byProvider) == "table" then
			for _, frames in pairs(byProvider) do
				if type(frames) == "table" then
					for _, f in ipairs(frames) do
						if match(f) then return f, "FrameSort" end
					end
				end
			end
		end
	end
	for i = 1, 5 do
		local f = _G["CompactPartyFrameMember" .. i]
		if match(f) then return f, "Blizzard" end
		if PartyFrame and match(PartyFrame["MemberFrame" .. i]) then return PartyFrame["MemberFrame" .. i], "Blizzard" end
	end
	if unit == "player" and match(PlayerFrame) then return PlayerFrame, "Blizzard" end
	return nil
end

-- ---------------------------------------------------------------------------
-- Native glow lanes
-- ---------------------------------------------------------------------------

local GLOW_TEXTURE = "Interface\\Buttons\\UI-ActionButton-Border"
local OUTLINE = "OUTLINE"

local function MakeLane(holder, ids)
	local host = CreateFrame("Frame", nil, UIParent)
	host:SetSize(40, 40)
	host:SetFrameStrata("MEDIUM")
	host:SetFrameLevel(60)
	host:EnableMouse(false)
	host:Hide()
	local container = CreateFrame("AuraContainer", nil, host, ns.Probe.TEMPLATE)
	container:SetAllPoints(host)
	container:EnableMouse(false)
	local included = {}
	for _, id in ipairs(ids) do included[id] = true end
	local lane = { host = host, container = container }
	container:AddAuraSlot("glow", "HELPFUL", {
		candidateFilters = { includeSpellIDs = included },
		initializeFrame = function(button)
			button:SetAllPoints(container)
			button:EnableMouse(false)
			local t = button:CreateTexture(nil, "OVERLAY")
			t:SetAllPoints(button)
			t:SetTexture(GLOW_TEXTURE)
			t:SetBlendMode("ADD")
			t:SetVertexColor(1, 0.72, 0.12, 1)
			lane.initialized = true
		end,
	})
	container:SetUnit(holder)
	container:Show()
	return lane
end

-- the holders an entry's buff or debuff can be on
local function Holders(e)
	if e.kind == "self" then return { e.unit } end
	return ns.Tracker.Holders(e.ability)
end

local function Present(unit)
	return ns.Tracker.roster[unit] ~= nil or ns.Tracker.enemies[unit] ~= nil
end

-- Out of combat: a lane per (entry, holder) the icons need; the rest hidden.
function D.PrepareGlow()
	if laneFailed or not ns.db.glow then return end
	if InCombatLockdown() then lanesPending = true return end
	lanesPending = false
	local wanted = {}
	for _, unit in ipairs(ns.Tracker.UNITS) do
		for _, e in ipairs(ns.Tracker.Entries(unit)) do
			for _, holder in ipairs(Holders(e)) do
				if Present(holder) then
					local key = unit .. ":" .. e.key .. ":" .. holder
					wanted[key] = true
					if not lanes[key] then
						local ok, lane = pcall(MakeLane, holder, e.ability.auras)
						if not ok then
							laneFailed = true
							U.Log("glow", holder, e.key, "lane failed: " .. tostring(lane))
							return
						end
						lanes[key] = lane
					end
				end
			end
		end
	end
	for key, lane in pairs(lanes) do
		if not wanted[key] then lane.host:Hide(); lane.icon = nil end
	end
end

-- the lanes of an icon follow it; answers whether the game draws its glow
local function BindGlow(icon, e, size)
	if laneFailed or testing then return false end
	local bound = false
	for _, holder in ipairs(Holders(e)) do
		local lane = lanes[e.unit .. ":" .. e.key .. ":" .. holder]
		if lane and lane.initialized then
			if lane.icon ~= icon then
				lane.host:ClearAllPoints()
				lane.host:SetPoint("CENTER", icon, "CENTER", 0, 0)
				lane.icon = icon
			end
			lane.host:SetSize(size * 1.5, size * 1.5)
			lane.host:SetShown(ns.db.glow)
			bound = true
		end
	end
	return bound
end

function D.HideGlow()
	for _, lane in pairs(lanes) do lane.host:Hide() end
end

function D.ClearGlow()
	for _, lane in pairs(lanes) do lane.host:Hide(); lane.icon = nil end
end

function D.GlowStatus()
	if laneFailed then return "native glow failed; plain border in use" end
	local n = 0
	for _ in pairs(lanes) do n = n + 1 end
	return string.format("%d glow lanes%s", n, lanesPending and " (more after combat)" or "")
end

-- ---------------------------------------------------------------------------
-- Rows and icons
-- ---------------------------------------------------------------------------

local function NewIcon(row)
	local b = CreateFrame("Frame", nil, row)
	b.icon = b:CreateTexture(nil, "ARTWORK")
	b.icon:SetAllPoints()
	b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	b.border = b:CreateTexture(nil, "BACKGROUND")
	b.border:SetPoint("TOPLEFT", -1, 1)
	b.border:SetPoint("BOTTOMRIGHT", 1, -1)
	b.border:SetColorTexture(0, 0, 0, 1)
	b.cd = CreateFrame("Cooldown", nil, b, "CooldownFrameTemplate")
	b.cd:SetAllPoints()
	b.cd:SetDrawEdge(false)
	b.cd:SetReverse(false)
	b.cd:SetHideCountdownNumbers(true)
	b.glow = b:CreateTexture(nil, "OVERLAY")
	b.glow:SetPoint("TOPLEFT", -2, 2)
	b.glow:SetPoint("BOTTOMRIGHT", 2, -2)
	b.glow:SetColorTexture(0.34, 0.88, 0.48, 0.6)
	b.glow:Hide()
	local text = CreateFrame("Frame", nil, b)   -- above the cooldown swipe
	text:SetAllPoints()
	text:SetFrameLevel(b.cd:GetFrameLevel() + 2)
	-- a font string needs a font before any text; Paint sets the size, this sets a font
	b.time = text:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	b.time:SetPoint("CENTER")
	b.mark = text:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	b.mark:SetPoint("TOPRIGHT", 1, 1)
	b.mark:SetText("?")
	b.mark:Hide()
	b.charges = text:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	b.charges:SetPoint("BOTTOMRIGHT", 1, -1)
	b.charges:Hide()
	return b
end

local function NewRow(unit)
	local f = CreateFrame("Frame", "CombatKitPvP_" .. unit, UIParent)
	f.unit = unit
	f.icons = {}
	f:SetSize(28, 28)
	f:SetFrameStrata("MEDIUM")
	f:SetFrameLevel(50)
	f:SetMovable(true)
	f:SetClampedToScreen(true)
	f:EnableMouse(false)
	f.bg = f:CreateTexture(nil, "BACKGROUND")
	f.bg:SetAllPoints()
	f.bg:SetColorTexture(0.2, 0.6, 1.0, 0.35)
	f.bg:Hide()
	f.label = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	f.label:SetPoint("BOTTOM", f, "TOP", 0, 2)
	f.label:Hide()
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", function(self) if unlocked then self:StartMoving() end end)
	f:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		local point, _, relPoint, x, y = self:GetPoint()
		local p = ns.db.rows[self.unit]
		p.point, p.relPoint, p.x, p.y = point, relPoint, math.floor(x + 0.5), math.floor(y + 0.5)
	end)
	rows[unit] = f
	return f
end

-- Next to its frame when there is one, else where it was dragged to.
local function Place(row)
	local db = ns.db
	local frame = (not testing) and D.FindFrame(row.unit) or nil
	row.anchored = frame ~= nil
	row:ClearAllPoints()
	if frame then
		if db.side == "LEFT" then
			row:SetPoint("TOPRIGHT", frame, "TOPLEFT", -db.offset, db.offsetY)
		else
			row:SetPoint("TOPLEFT", frame, "TOPRIGHT", db.offset, db.offsetY)
		end
	else
		local p = db.rows[row.unit]
		row:SetPoint(p.point, UIParent, p.relPoint, p.x, p.y)
	end
end

local function Layout(row, count)
	local db = ns.db
	local size, gap, perRow = db.iconSize, db.spacing, math.max(1, db.maxPerRow or 8)
	local cols = math.min(count, perRow)
	local lines = math.max(1, math.ceil(count / perRow))
	local w = cols > 0 and (cols * size + (cols - 1) * gap) or size
	row:SetSize(w, lines * size + (lines - 1) * gap)
	local leftward = db.side == "LEFT" and row.anchored
	for i, b in ipairs(row.icons) do
		b:SetSize(size, size)
		b:ClearAllPoints()
		local col, line = (i - 1) % perRow, math.floor((i - 1) / perRow)
		local x, y = col * (size + gap), -line * (size + gap)
		if leftward then
			b:SetPoint("TOPRIGHT", row, "TOPRIGHT", -x, y)   -- grows away from the frame
		else
			b:SetPoint("TOPLEFT", row, "TOPLEFT", x, y)
		end
		b:SetShown(i <= count)
	end
end

local function Countdown(seconds)
	if seconds >= 60 then return string.format("%d:%02d", math.floor(seconds / 60), math.floor(seconds % 60)) end
	return tostring(math.ceil(seconds))
end

local function Paint(b, e, now)
	local db = ns.db
	local a = e.ability
	b.icon:SetTexture(C_Spell.GetSpellTexture(a.id) or 134400)
	local fontSize = db.fontSize or 12
	if b.fontSize ~= fontSize then
		b.time:SetFont(STANDARD_TEXT_FONT, fontSize, OUTLINE)
		b.mark:SetFont(STANDARD_TEXT_FONT, math.max(8, math.floor(fontSize * 0.9)), OUTLINE)
		b.charges:SetFont(STANDARD_TEXT_FONT, math.max(8, math.floor(fontSize * 0.8)), OUTLINE)
		b.fontSize = fontSize
	end
	local available, nextIn = ns.Tracker.Charges(e, now)
	local cd = e.cd or a.cd
	if available == 0 and nextIn > 0 then
		local start = e.queue[1] - cd
		if b.cdStart ~= start then
			b.cd:SetCooldown(start, cd)
			b.cdStart = start
		end
		b.cd:Show()
		b.icon:SetDesaturated(true)
		b.icon:SetAlpha(0.6)
		b.time:SetText(db.showTimer and Countdown(nextIn) or "")
	else
		b.cd:Clear()
		b.cd:Hide()
		b.cdStart = nil
		b.icon:SetDesaturated(e.unknown == true)
		b.icon:SetAlpha(e.unknown and 0.5 or 1)
		b.time:SetText("")
	end
	if (e.charges or 1) > 1 then
		b.charges:SetText(tostring(available))
		b.charges:Show()
	else
		b.charges:Hide()
	end
	-- the game's glow when a lane is bound, the tracker's reading otherwise
	local native = db.glow and BindGlow(b, e, db.iconSize)
	b.glow:SetShown(db.glow and not native and e.active or false)
	b.mark:SetShown(e.unknown or (e.uncertain and nextIn > 0) or false)
end

-- ---------------------------------------------------------------------------
-- Update
-- ---------------------------------------------------------------------------

local function SampleEntries(unit)
	local s = SAMPLE[unit]
	local out = {}
	for i, ability in ipairs(ns.Spells.For(s.class, s.spec)) do
		local e = { ability = ability, kind = ability.kind, queue = {}, active = i == 1, uncertain = i == 2,
			charges = ability.charges or 1, cd = ability.cd }
		if i == 2 then e.queue[1] = GetTime() + ability.cd * 0.6 end
		if i == 3 then e.unknown = true end
		out[#out + 1] = e
	end
	return out
end

local function Entries(unit)
	local list = testing and SampleEntries(unit) or ns.Tracker.Entries(unit)
	if ns.db.showOffensive ~= false and ns.db.showCC ~= false then return list end
	local out = {}
	for _, e in ipairs(list) do
		local role = e.ability.role
		if (role ~= "offensive" or ns.db.showOffensive ~= false) and (role ~= "cc" or ns.db.showCC ~= false) then
			out[#out + 1] = e
		end
	end
	return out
end

-- FrameSort moved the frames: the rows follow at the next paint
local hooked = false
function D.HookFrameSort()
	if hooked then return end
	local sorting = FrameSortApi and FrameSortApi.v3 and FrameSortApi.v3.Sorting
	if sorting and sorting.RegisterPostSortCallback then
		local ok = pcall(sorting.RegisterPostSortCallback, sorting, function() D.Dirty() end)
		hooked = ok and true or false
	end
end
function D.FrameSortHooked() return hooked end

-- rows come and go with the roster; icons are repainted every call
function D.Update(now, live)
	now = now or GetTime()
	local units = testing and { "party1", "party2" } or ns.Tracker.UNITS
	for _, unit in ipairs(units) do
		local list = (live or testing) and Entries(unit) or {}
		local row = rows[unit]
		if #list == 0 then
			if row then row:Hide() end
		else
			row = row or NewRow(unit)
			for i = #row.icons + 1, #list do row.icons[i] = NewIcon(row) end
			if dirty or not row:IsShown() then Place(row) end
			Layout(row, #list)
			for i, e in ipairs(list) do Paint(row.icons[i], e, now) end
			local loose = unlocked and not row.anchored
			row.bg:SetShown(loose)
			row.label:SetShown(loose)
			row.label:SetText(unit)
			row:EnableMouse(loose)
			row:Show()
		end
	end
	if not live then D.HideGlow() end
	dirty = false
end

function D.HideAll()
	for _, row in pairs(rows) do row:Hide() end
	D.HideGlow()
end

-- Sample rows outside arena, to size and place them.
function D.SetTesting(on)
	testing = on and true or false
	dirty = true
	if testing then D.Update(GetTime(), false) else ns.Refresh() end
end

function D.SetLocked(locked)
	unlocked = not locked
	dirty = true
	D.Update(GetTime(), ns.IsLive())
end

function D.ResetPositions()
	for unit, p in pairs(ns.defaults.rows) do
		local r = ns.db.rows[unit]
		r.point, r.relPoint, r.x, r.y = p.point, p.relPoint, p.x, p.y
	end
	dirty = true
	D.Update(GetTime(), ns.IsLive())
end

function D.Rows() return rows end
function D.LanesPending() return lanesPending end
