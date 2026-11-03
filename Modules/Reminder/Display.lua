local ADDON, ns = ...
local CK = CombatKit
local L, Skin = CK.L, CK.Skin

-- ===========================================================================
-- How the reminders show: a row of icons, centred on a point the player
-- drags, and if asked the same as rows on the HUD. Each icon shows the
-- spell's or the item's icon, its name above it and, inside at the bottom,
-- the time left when it is running out (a feast counts down) or how many in
-- the group lack a buff; and, if asked, the game's proc glow running round it.
-- A click on one casts its spell or uses its item, and a sound can say that
-- one appeared.
--
-- A reminder is { key=, icon=, label=, text=, warn= (the name in red:
-- something to undo), expires= (GetTime() at which a countdown ends),
-- action = { kind = "spell" | "item", id=, slot= (an item used on a weapon) } }.
-- ===========================================================================

local LABEL_GAP = 3    -- between an icon and its name
local WARN      = { 1, 0.3, 0.3 }
local NAME      = { 1, 0.82, 0 }
local SOUND_GAP = 5    -- seconds: one sound for reminders that come together

-- the game's own sounds to pick from (those the client has); "" = none
ns.SOUNDS = { "RAID_WARNING", "READY_CHECK", "ALARM_CLOCK_WARNING_3", "TELL_MESSAGE" }

local frame
local icons = {}
local current = {}       -- what the module last asked to show
local heard = {}         -- the keys of the reminders that were up at the last real look
local lastSound = -SOUND_GAP
local locked, testing = true, false

local sampleKind = "consumables"   -- which samples the test shows: the settings page open

function ns.IsLocked() return locked end
function ns.IsTesting() return testing end

-- between two icons: room for a name of four or five characters above each
local function Gap(size) return math.max(6, math.floor(size * 0.2)) end

-- ---------------------------------------------------------------------------
-- The glow: the game's own proc border (the band that runs round an action
-- button), run by an animation of our own; nothing of the action bars' glow
-- code is called. A client without that atlas gets the classic marching ants
-- (a file cut into cells), and one without either no glow.
-- ---------------------------------------------------------------------------

local PROC = { atlas = "UI-HUD-ActionBar-Proc-Loop-Flipbook", rows = 6, columns = 5, frames = 30, duration = 1, scale = 1.4 }
local ANTS = { file = "Interface\\SpellActivationOverlay\\IconAlertAnts", size = 256, cell = 48, columns = 5, frames = 22,
	duration = 0.5, scale = 1.2 }

local function HasAtlas(name)
	if not (C_Texture and C_Texture.GetAtlasInfo) then return true end
	local ok, info = pcall(C_Texture.GetAtlasInfo, name)
	return ok and info ~= nil
end

local function AntsFrame(tex, i)
	local unit = ANTS.cell / ANTS.size
	local col, line = i % ANTS.columns, math.floor(i / ANTS.columns)
	tex:SetTexCoord(col * unit, (col + 1) * unit, line * unit, (line + 1) * unit)
end

-- the glow on an icon, made once: { tex=, anim=, scale= }, or false
local function Glow(b)
	if b.glow ~= nil then return b.glow end
	local tex = b:CreateTexture(nil, "OVERLAY", nil, 7)
	tex:SetPoint("CENTER")
	tex:SetBlendMode("ADD")
	tex:Hide()
	local anim = tex:CreateAnimationGroup()
	anim:SetLooping("REPEAT")
	local style
	if HasAtlas(PROC.atlas) and tex:SetAtlas(PROC.atlas) ~= false then
		style = PROC
		local flip = anim:CreateAnimation("FlipBook")
		flip:SetFlipBookRows(PROC.rows)
		flip:SetFlipBookColumns(PROC.columns)
		flip:SetFlipBookFrames(PROC.frames)
		flip:SetDuration(PROC.duration)
	elseif tex:SetTexture(ANTS.file) ~= false and tex:GetTexture() ~= nil then
		style = ANTS
		AntsFrame(tex, 0)
		local step = anim:CreateAnimation("Animation")
		step:SetDuration(ANTS.duration)
		step:SetScript("OnUpdate", function(self)
			AntsFrame(tex, math.min(ANTS.frames - 1, math.floor((self:GetProgress() or 0) * ANTS.frames)))
		end)
	else
		b.glow = false
		return false
	end
	b.glow = { tex = tex, anim = anim, scale = style.scale }
	return b.glow
end

local function SetGlow(b, on, size, warn)
	local g = Glow(b)
	if not g then return end
	if on then
		g.tex:SetSize(size * g.scale, size * g.scale)
		g.tex:SetVertexColor(unpack(warn and { 1, 0.35, 0.35 } or { 1, 1, 1 }))
		g.tex:Show()
		if not g.anim:IsPlaying() then g.anim:Play() end
	else
		g.anim:Stop()
		g.tex:Hide()
	end
end

local function Countdown(seconds)
	seconds = math.max(0, math.ceil(seconds))
	return string.format("%d:%02d", math.floor(seconds / 60), seconds % 60)
end

-- Where the row stands: where it was dragged, else the default near the top edge
local function Anchor()
	local db, d = ns.db, ns.defaults
	return db.point or d.point, UIParent, db.relPoint or d.relPoint, db.x or d.x, db.y or d.y
end

local function SavePosition(self)
	self:StopMovingOrSizing()
	local db = ns.db
	-- kept as an offset of the centre, so the row stays centred there as it grows and shrinks
	local cx, cy = self:GetCenter()
	local ux, uy = UIParent:GetCenter()
	if cx and ux then
		db.point, db.relPoint, db.x, db.y = "CENTER", "CENTER", math.floor(cx - ux + 0.5), math.floor(cy - uy + 0.5)
	else
		local point, _, relPoint, x, y = self:GetPoint()
		db.point, db.relPoint, db.x, db.y = point, relPoint, math.floor(x + 0.5), math.floor(y + 0.5)
	end
	self:ClearAllPoints()
	self:SetPoint(Anchor())
end

-- ---------------------------------------------------------------------------
-- Click to use. Secure buttons over the icons: the only way a click may cast
-- or use something. They cannot be shown, hidden, moved or changed in combat,
-- so they are only touched out of combat, and a state driver hides them all
-- the moment combat starts. They are not anchored to the icons (an insecure
-- frame a secure one hangs on cannot move in combat either): they sit on a
-- secure frame of their own, placed where the row is.
-- ---------------------------------------------------------------------------

local clicks
local buttons = {}

local function ShowTip(self)
	local a = self.action
	if not a then return end
	GameTooltip:SetOwner(self, "ANCHOR_TOP")
	if a.kind == "spell" then GameTooltip:SetSpellByID(a.id) else GameTooltip:SetItemByID(a.id) end
	GameTooltip:Show()
end

local function ClickButton(i)
	if not clicks then
		clicks = CreateFrame("Frame", "CombatKitReminderClicks", UIParent, "SecureHandlerStateTemplate")
		clicks:SetFrameStrata("MEDIUM")
		clicks:SetFrameLevel(20)
		RegisterStateDriver(clicks, "visibility", "[combat] hide; show")
	end
	local b = buttons[i]
	if b then return b end
	b = CreateFrame("Button", nil, clicks, "SecureActionButtonTemplate")
	-- down or up, whichever the game's "cast on key down" setting makes it act on; a
	-- right button goes through, so holding it over an icon still turns the camera
	b:RegisterForClicks("LeftButtonUp", "LeftButtonDown")
	if b.SetPassThroughButtons then pcall(b.SetPassThroughButtons, b, "RightButton") end
	b:SetScript("OnEnter", ShowTip)
	b:SetScript("OnLeave", GameTooltip_Hide)
	buttons[i] = b
	return b
end

local function Point(b, a)
	if a.kind == "spell" then
		b:SetAttribute("type", "spell")
		b:SetAttribute("spell", a.id)
		b:SetAttribute("item", nil)
	else
		b:SetAttribute("type", "item")
		b:SetAttribute("item", "item:" .. a.id)
		b:SetAttribute("spell", nil)
	end
	b:SetAttribute("target-slot", a.slot)
	b.action = a
end

-- No buttons up: out of combat only (the state driver sees to combat)
function ns.ClearClicks()
	if InCombatLockdown() then return end
	for _, b in ipairs(buttons) do b:Hide() end
end

local function PlaceClicks(list, width, size)
	if InCombatLockdown() then return end
	local db = ns.db
	local live = db.click and db.icons and locked and not testing
	if not live then return ns.ClearClicks() end
	local used = 0
	for i, r in ipairs(list) do
		if r.action then
			local b = ClickButton(i)
			used = math.max(used, i)
			b:ClearAllPoints()
			b:SetSize(size, size)
			b:SetPoint("LEFT", clicks, "LEFT", (i - 1) * (size + Gap(size)), 0)
			Point(b, r.action)
			b:Show()
		elseif buttons[i] then
			buttons[i]:Hide()
		end
	end
	for i = #list + 1, #buttons do buttons[i]:Hide() end
	if clicks then
		clicks:ClearAllPoints()
		clicks:SetPoint(Anchor())
		clicks:SetSize(width, size)
	end
end

-- ---------------------------------------------------------------------------
-- The row
-- ---------------------------------------------------------------------------

local function Tick(self, elapsed)
	self.elapsed = (self.elapsed or 0) + elapsed
	if self.elapsed < 1 then return end
	self.elapsed = 0
	local now, over = GetTime(), false
	for i, r in ipairs(current) do
		if r.expires then
			if now >= r.expires then over = true elseif icons[i] then icons[i].text:SetText(Countdown(r.expires - now)) end
		end
	end
	if ns.db.hud then CK.HUD.Refresh() end
	if over then ns.Queue(0) end
end

local function Create()
	frame = CreateFrame("Frame", "CombatKitReminder", UIParent)
	frame:SetSize(40, 40)
	frame:SetFrameStrata("MEDIUM")
	frame:SetMovable(true)
	frame:SetClampedToScreen(true)
	frame:EnableMouse(false)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", function(self) if not locked then self:StartMoving() end end)
	frame:SetScript("OnDragStop", SavePosition)
	-- only while unlocked
	frame.bg = frame:CreateTexture(nil, "BACKGROUND")
	frame.bg:SetPoint("TOPLEFT", -4, 4)
	frame.bg:SetPoint("BOTTOMRIGHT", 4, -4)
	frame.bg:SetColorTexture(0.2, 0.6, 1.0, 0.35)
	frame.bg:Hide()
	frame:Hide()
end

local function Icon(i)
	local b = icons[i]
	if b then return b end
	b = CreateFrame("Frame", nil, frame)
	b.icon = b:CreateTexture(nil, "ARTWORK")
	b.icon:SetAllPoints()
	b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	b.label = b:CreateFontString(nil, "OVERLAY")
	b.label:SetPoint("BOTTOM", b, "TOP", 0, LABEL_GAP)
	b.label:SetJustifyH("CENTER")
	b.label:SetJustifyV("BOTTOM")
	b.text = b:CreateFontString(nil, "OVERLAY")
	b.text:SetPoint("BOTTOM", b, "BOTTOM", 0, 2)
	icons[i] = b
	return b
end

-- What the unlocked or tested row shows, to see the size and place: the
-- consumables page's kind of reminder, the class page's (your class's own
-- and your spell IDs, as they would look), or on the other pages both.
local function ConsumableSamples(list)
	list[#list + 1] = { icon = ns.ItemIcon(ns.FLASK.items[1]), label = L["Flask"] }
	list[#list + 1] = { icon = ns.FOOD_ICON, label = L["Food"], text = "4m" }
	list[#list + 1] = { icon = ns.ItemIcon(ns.OIL.items[1]), label = L["Weapon oil"] }
	list[#list + 1] = { icon = ns.ItemIcon(ns.FEAST.items[2]), label = L["Feast"], text = Countdown(161) }
end

local function ClassSamples(list)
	local items = ns.ClassItems and ns.ClassItems() or {}
	local now = {}
	for _, item in ipairs(items) do
		if item.on and item.now then now[#now + 1] = item end
	end
	if #now == 0 then now = items end   -- nothing for this spec right now: the whole list, to see it anyway
	for _, item in ipairs(now) do
		list[#list + 1] = { icon = item.icon, label = item.label, warn = item.warn }
	end
	for _, c in ipairs(ns.CustomList and ns.CustomList() or {}) do
		list[#list + 1] = { icon = ns.SpellIcon(c.id), label = ns.SpellName(c.id), warn = c.when == "present" }
	end
end

local function Samples()
	local list = {}
	if sampleKind ~= "class" then ConsumableSamples(list) end
	if sampleKind ~= "consumables" then ClassSamples(list) end
	if #list == 0 then ConsumableSamples(list) end   -- a class with nothing of its own
	return list
end

local function Layout(list)
	local size = ns.db.size
	local gap = Gap(size)
	local n = #list
	local width = math.max(size, n * size + (n - 1) * gap)
	frame:SetSize(width, size)
	local nameSize, textSize = math.max(9, math.floor(size * 0.26)), math.max(9, math.floor(size * 0.3))
	local counting = false
	for i, r in ipairs(list) do
		local b = Icon(i)
		b:SetSize(size, size)
		b:ClearAllPoints()
		b:SetPoint("LEFT", frame, "LEFT", (i - 1) * (size + gap), 0)
		b.icon:SetTexture(r.icon or 134400)   -- the question mark, should an icon not be in yet
		b.label:SetFont(STANDARD_TEXT_FONT, nameSize, "OUTLINE")
		b.label:SetWidth(size + gap)
		b.label:SetWordWrap(true)
		b.label:SetMaxLines(2)
		b.label:SetText(r.label or "")
		b.label:SetTextColor(unpack(r.warn and WARN or NAME))
		b.text:SetFont(STANDARD_TEXT_FONT, textSize, "OUTLINE")
		b.text:SetText(r.expires and Countdown(r.expires - GetTime()) or r.text or "")
		SetGlow(b, ns.db.glow, size, r.warn)
		b:Show()
		counting = counting or r.expires ~= nil
	end
	for i = n + 1, #icons do icons[i]:Hide() end
	frame:SetScript("OnUpdate", counting and Tick or nil)
	return width, size
end

local function Paint()
	if not frame then return end
	local sample = not locked or testing
	local list = sample and Samples() or (ns.db.icons and current or {})
	frame:EnableMouse(not locked)
	frame.bg:SetShown(not locked)
	if #list == 0 then
		frame:SetScript("OnUpdate", nil)
		frame:Hide()
		ns.ClearClicks()
		return
	end
	local width, size = Layout(list)
	frame:Show()
	PlaceClicks(list, width, size)
end

-- A sound when a reminder appears that was not up at the last real look
local function Sound(list)
	local now, new = {}, false
	for _, r in ipairs(list) do
		if r.key then
			now[r.key] = true
			if not heard[r.key] then new = true end
		end
	end
	heard = now
	local kit = ns.db.sound ~= "" and SOUNDKIT and SOUNDKIT[ns.db.sound]
	if new and kit and PlaySound and GetTime() - lastSound >= SOUND_GAP then
		lastSound = GetTime()
		PlaySound(kit, "Master")
	end
end

-- The reminders to show now; an empty list hides them. `hidden`: they are
-- only out of sight for now (combat, a loading screen), not dealt with.
local onHud = false   -- the HUD shows rows of ours

function ns.ShowReminders(list, hidden)
	current = list
	if not hidden then Sound(list) end
	local hud = ns.db.hud and #list > 0
	if hud or onHud then CK.HUD.Refresh() end
	onHud = hud
	if not frame then
		if #list == 0 and locked and not testing then return end
		Create()
		ns.ApplyDisplay()
		return
	end
	Paint()
end

-- Size and position, from the saved settings
function ns.ApplyDisplay()
	if not frame then return end
	local db = ns.db
	frame:ClearAllPoints()
	frame:SetPoint(Anchor())
	Paint()
end

-- Unlocked: sample icons that can be dragged
function ns.SetLocked(state)
	locked = state and true or false
	if not frame and (locked and not testing) then return end
	if not frame then Create() end
	ns.ApplyDisplay()
end

-- The samples to show: those of the settings page open ("consumables", "class", or anything else for both)
function ns.SetSampleKind(kind)
	if kind == sampleKind then return end
	sampleKind = kind
	if frame and (testing or not locked) then ns.ApplyDisplay() end
end

-- A test: the sample icons where the row stands, without unlocking
function ns.SetTesting(on)
	testing = on and true or false
	if not frame and (locked and not testing) then return end
	if not frame then Create() end
	ns.ApplyDisplay()
end

function ns.ResetPosition()
	local db, d = ns.db, ns.defaults
	db.point, db.relPoint, db.x, db.y = d.point, d.relPoint, d.x, d.y
	ns.ApplyDisplay()
end

-- One of ns.SOUNDS, to hear it before picking it
function ns.PlaySample(key)
	local kit = SOUNDKIT and SOUNDKIT[key]
	if kit and PlaySound then PlaySound(kit, "Master") end
end

-- ---------------------------------------------------------------------------
-- The HUD: a row per reminder, the box's border amber while there are any
-- ---------------------------------------------------------------------------

ns.hudSection = {
	key = "reminder",
	order = 15,
	GetRows = function()
		if not ns.db.hud or #current == 0 then return nil end
		local rows = {}
		for _, r in ipairs(current) do
			local right = r.expires and Countdown(r.expires - GetTime()) or r.text
			rows[#rows + 1] = { icon = r.icon, value = r.warn and Skin.Text("bad", r.label or "") or (r.label or ""), right = right }
		end
		return rows, true
	end,
	OnClick = function() CK.OpenOptions("Reminder/main") end,
	OnTooltip = function(tooltip) tooltip:AddLine(L["REMINDER_HUD_TIP"], 1, 1, 1, true) end,
}

-- what is up right now (AuraLab records it next to what the game hands out)
function ns.Shown() return current end

-- for the tests
function ns.GetDisplay() return frame, icons, buttons end
