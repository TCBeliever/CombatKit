local CK = CombatKit
local L, Skin, O = CK.L, CK.Skin, CK.Options

-- Settings pages of the Reminder module, by what they are about: the
-- consumables (yours and the group's), your class (each of its reminders on
-- its own, and your own spell IDs), where they show, and how.

local X = O.FIELD_X + 20
local LINE = 26
local COL_W = 300    -- a column of the class list
local CONSUMABLES = {   -- two lines
	{ { "flask", "Flask" }, { "food", "Food" }, { "rune", "Augment rune" } },
	{ { "oil", "Weapon oil" }, { "healthstone", "Healthstone" } },
}
local SHARED = { { "feast", "Feast" }, { "cauldron", "Flask cauldron" } }
local CLASS_ROWS = 16   -- check boxes for the class list, two columns; one for several specs stands under each
local HEADS = 5         -- section heads over the class list: every spec, then each spec with reminders of its own
local CUSTOM_ROWS = 10  -- custom reminders, two columns, as many as a class can have
local RM   -- the module, set whenever the section is used

local function Changed()
	RM.Refresh()
	O.Changed()
end

-- A check box for a true/false setting of the module
local function Switch(p, key, labelKey)
	return CK.Bind(Skin.Checkbox(p, "", function(checked)
		RM.db[key] = checked
		RM.ApplyDisplay()   -- the samples too, while they are up
		Changed()
	end), labelKey)
end

-- ---------------------------------------------------------------------------
-- Consumables: yours, and what the group puts down
-- ---------------------------------------------------------------------------

local function BuildConsumables(p)
	local y = 0
	Skin.Field(p, "Yours", 0, y)
	p.consumables = {}
	for line, boxes in ipairs(CONSUMABLES) do
		local previous
		for _, c in ipairs(boxes) do
			local key = c[1]
			local box = CK.Bind(Skin.Checkbox(p, "", function(checked)
				RM.db.consumables[key] = checked
				Changed()
			end), c[2])
			if previous then
				box:SetPoint("LEFT", previous, "RIGHT", 16, 0)
			else
				box:SetPoint("TOPLEFT", X, y - 1 - (line - 1) * LINE)
			end
			previous = box
			p.consumables[key] = box
		end
	end
	p.timing = CK.Bind(Skin.Label(p, "", nil, "dim"), "CONSUMABLE_TIMING")
	p.timing:SetPoint("TOPLEFT", X, y - 4 - 2 * LINE)
	p.timing:SetWidth(O.RIGHT_W - X)
	p.timing:SetJustifyH("LEFT")

	y = y - 3 * LINE - 26
	Skin.Field(p, "The group's", 0, y)
	p.shared = {}
	local previous
	for _, s in ipairs(SHARED) do
		local kind = s[1]
		local box = CK.Bind(Skin.Checkbox(p, "", function(checked)
			RM.SetShared(kind, checked)
			O.Changed()
		end), s[2])
		if previous then box:SetPoint("LEFT", previous, "RIGHT", 16, 0) else box:SetPoint("TOPLEFT", X, y - 1) end
		previous = box
		p.shared[kind] = box
	end
	p.sharedNote = CK.Bind(Skin.Label(p, "", nil, "dim"), "SHARED_TIP")
	p.sharedNote:SetPoint("TOPLEFT", X, y - 1 - LINE)
	p.sharedNote:SetWidth(O.RIGHT_W - X)
	p.sharedNote:SetJustifyH("LEFT")
end

local function RefreshConsumables(p)
	local db = RM.db
	for key, box in pairs(p.consumables) do box:SetChecked(db.consumables[key]) end
	for kind, box in pairs(p.shared) do box:SetChecked(db.shared[kind]) end
end

-- ---------------------------------------------------------------------------
-- Your class: each reminder on its own; then your own spell IDs
-- ---------------------------------------------------------------------------

local WHEN = { { "missing", "When missing" }, { "present", "When present" } }
local WHO  = { { "me", "On you" }, { "group", "On the group" } }

local function Items(list)
	return function()
		local items = {}
		for _, e in ipairs(list) do items[#items + 1] = { label = L[e[2]], value = e[1] } end
		return items
	end
end

local function Named(list, value)
	for _, e in ipairs(list) do
		if e[1] == value then return L[e[2]] end
	end
end

local function Cell(i, top)
	local column, row = (i - 1) % 2, math.floor((i - 1) / 2)
	return column * COL_W, top - row * 24
end

-- A section head: the class's or a spec's icon, and its name
local function Head(p)
	local h = CreateFrame("Frame", nil, p)
	h:SetSize(2 * COL_W, 20)
	h.icon = h:CreateTexture(nil, "ARTWORK")
	h.icon:SetSize(18, 18)
	h.icon:SetPoint("LEFT", 0, 0)
	h.text = Skin.Label(h, "")
	h.text:SetPoint("LEFT", h.icon, "RIGHT", 6, 0)
	return h
end

local function BuildClass(p)
	-- the class list by spec: laid out by Refresh, the class's own entries in their own order
	p.heads, p.items = {}, {}
	for i = 1, HEADS do p.heads[i] = Head(p) end
	for i = 1, CLASS_ROWS do
		local c
		c = Skin.Checkbox(p, "", function(checked)
			if c.key then RM.SetClassItem(c.key, checked) end
			O.Changed()
		end)
		-- on hover, why it is greyed out, and where its recommendation comes from
		c:HookScript("OnEnter", function(self)
			if not self.tip then return end
			GameTooltip:SetOwner(self, "ANCHOR_TOP")
			GameTooltip:SetText(self.tipTitle or "", 1, 1, 1, 1, true)
			GameTooltip:AddLine(self.tip, nil, nil, nil, true)
			GameTooltip:Show()
		end)
		c:HookScript("OnLeave", GameTooltip_Hide)
		p.items[i] = c
	end
	p.none = CK.Bind(Skin.Label(p, "", nil, "dim"), "CLASS_NONE")
	p.none:SetPoint("TOPLEFT", 0, -2)

	-- custom: a line to add one, then the list; Refresh puts the block below the class list
	local b = CreateFrame("Frame", nil, p)
	b:SetSize(O.RIGHT_W, 20)
	p.customBlock = b
	local y = 0
	p.draftWhen, p.draftWho = "missing", "me"
	Skin.Field(b, "Spell ID", 0, y)
	p.id = Skin.EditBox(b, 90, function() end)
	p.id:SetPoint("TOPLEFT", X, y)
	p.when = Skin.Dropdown(b, 120, Items(WHEN), function(_, item)
		p.draftWhen = item.value
		O.Refresh()
	end)
	p.when:SetPoint("LEFT", p.id, "RIGHT", 10, 0)
	p.who = Skin.Dropdown(b, 120, Items(WHO), function(_, item)
		p.draftWho = item.value
		O.Refresh()
	end)
	p.who:SetPoint("LEFT", p.when, "RIGHT", 10, 0)
	p.add = CK.Bind(Skin.Button(b, "", 60, 20, function()
		local why = RM.AddCustom(p.id:GetText(), p.draftWhen, p.draftWho)
		p.why = why
		if not why then p.id:SetText("") end
		O.Changed()
	end), "Add")
	p.add:SetPoint("LEFT", p.who, "RIGHT", 10, 0)
	Skin.Tooltip(p.add, "Add", "CUSTOM_TIP")
	p.status = Skin.Label(b, "", nil, "dim")
	p.status:SetPoint("TOPLEFT", X, y - 26)

	p.rows = {}
	for i = 1, CUSTOM_ROWS do
		local row = CreateFrame("Frame", nil, b)
		row:SetSize(COL_W - 10, 22)
		row:SetPoint("TOPLEFT", Cell(i, y - 50))
		row.icon = row:CreateTexture(nil, "ARTWORK")
		row.icon:SetSize(18, 18)
		row.icon:SetPoint("LEFT", 0, 0)
		row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		row.remove = CK.Bind(Skin.Button(row, "", 50, 20, function()
			if row.entry then RM.RemoveCustom(row.entry) end
			O.Changed()
		end), "Remove")
		row.remove:SetPoint("RIGHT", 0, 0)
		row.text = Skin.Label(row, "")
		row.text:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
		row.text:SetPoint("RIGHT", row.remove, "LEFT", -6, 0)
		row.text:SetJustifyH("LEFT")
		row.text:SetWordWrap(false)
		p.rows[i] = row
	end
end

-- The class list in sections: what every spec has (an item for every spec, or for none in
-- particular), then each spec with reminders of its own; one for several specs stands under each
local function Sections(items)
	local specs = RM.ClassSpecs()
	local _, class = UnitClass("player")
	local sections = { { name = L["All specs"], atlas = class and ("classicon-" .. class:lower()), items = {} } }
	local mine = RM.SpecID()
	for _, s in ipairs(specs) do
		sections[#sections + 1] = { name = s.name, icon = s.icon, current = s.id == mine, items = {} }
	end
	for _, item in ipairs(items) do
		local of, picks = {}, 0
		for i, s in ipairs(specs) do
			if item.spec and item.spec[s.id] then of[#of + 1] = i + 1 end
			if item.guides and item.guides[s.id] then picks = picks + 1 end
		end
		if picks > 0 then
			-- each spec its own recommendation (poisons, runes): under each spec, greyed where it is not yours
			for i, s in ipairs(specs) do
				if item.guides[s.id] then
					-- yours as it stands now (no pick while it does not apply); another spec's from the guides
					local yours = s.id == mine
					local copy = setmetatable({ guide = yours and item.guide or not yours and item.guides[s.id] or nil,
						now = item.now and yours }, { __index = item })
					table.insert(sections[i + 1].items, copy)
				end
			end
		elseif #of == 0 or #of == #specs then
			table.insert(sections[1].items, item)
		else
			for _, i in ipairs(of) do table.insert(sections[i].items, item) end
		end
	end
	return sections
end

local function RefreshClass(p)
	local items = RM.ClassItems()
	local y, heads, n = 0, 0, 0
	for _, s in ipairs(Sections(items)) do
		if #s.items > 0 and heads < HEADS then
			heads = heads + 1
			local head = p.heads[heads]
			head:ClearAllPoints()
			head:SetPoint("TOPLEFT", 0, y)
			head:Show()
			if s.atlas then
				head.icon:SetAtlas(s.atlas)
			else
				head.icon:SetTexture(s.icon)
				head.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
			end
			-- another spec than yours: its name dim, like its reminders
			head.text:SetText(s.current == false and Skin.Text("dim", s.name) or s.name)
			y = y - 24
			for i, item in ipairs(s.items) do
				local c = p.items[n + 1]
				if c then
					n = n + 1
					local column, row = (i - 1) % 2, math.floor((i - 1) / 2)
					c:ClearAllPoints()
					c:SetPoint("TOPLEFT", 24 + column * COL_W, y - row * 24)
					c:Show()
					c.key = item.key
					-- not for your spec or talents right now: greyed, still to be set; the guides' pick after it
					local label = item.now and (item.label or "?") or Skin.Text("dim", item.label or "?")
					if item.guide then label = label .. Skin.Text("dim", "  " .. string.format(L["GUIDE_PICK"], item.guide)) end
					c:SetLabel(label)
					c:SetChecked(item.on)
					c.tipTitle = item.label
					c.tip = item.guide and L["GUIDE_TIP"] or not item.now and L["NOT_NOW_TIP"] or nil
				end
			end
			y = y - math.ceil(#s.items / 2) * 24 - 8
		end
	end
	for i = heads + 1, HEADS do p.heads[i]:Hide() end
	for i = n + 1, CLASS_ROWS do
		p.items[i].key, p.items[i].tip = nil, nil
		p.items[i]:Hide()
	end
	p.none:SetShown(#items == 0)
	p.customBlock:ClearAllPoints()
	p.customBlock:SetPoint("TOPLEFT", 0, math.min(y, -24) - 14)

	p.when:SetValueText(Named(WHEN, p.draftWhen))
	p.who:SetValueText(Named(WHO, p.draftWho))
	local list = RM.CustomList()
	if p.why then
		p.status:SetText(Skin.Text("warn", L[p.why]))
	else
		p.status:SetText(string.format(L["CUSTOM_COUNT"], #list, RM.CUSTOM_MAX))
	end
	p.why = nil   -- said once
	for i, row in ipairs(p.rows) do
		local c = list[i]
		row.entry = c
		row:SetShown(c ~= nil)
		if c then
			row.icon:SetTexture(C_Spell.GetSpellTexture(c.id))
			row.text:SetText((C_Spell.GetSpellName(c.id) or "?") .. Skin.Text("dim", string.format("  %d  %s%s%s", c.id,
				Named(WHEN, c.when), L["LIST_SEP"], Named(WHO, c.who))))
		end
	end
end

-- ---------------------------------------------------------------------------
-- Where: a line per scenario, a column each for yours and the group's
-- ---------------------------------------------------------------------------

local ORDER = { "dungeon", "raid", "delve", "world", "arena", "bg" }
-- a column for each kind, named as its page is
local COLUMNS = { { "consumablesWhere", "Consumables" }, { "classWhere", "Your class" }, { "sharedWhere", "Feasts and cauldrons" } }
local COL_X = { 200, 330, 460 }

local function BuildWhere(p)
	p.boxes = {}
	for c, col in ipairs(COLUMNS) do
		local head = CK.Bind(Skin.Label(p, "", nil, "dim"), col[2])
		head:SetPoint("TOPLEFT", COL_X[c], 0)
	end
	p.names = {}
	for i, key in ipairs(ORDER) do
		local y = -24 - (i - 1) * LINE
		p.names[key] = Skin.Label(p, "")
		p.names[key]:SetPoint("TOPLEFT", 0, y - 2)
		for c, col in ipairs(COLUMNS) do
			local set = col[1]
			-- an unticked box is saved as false: a missing key would read as the default again
			local box = Skin.Checkbox(p, "", function(checked)
				RM.db[set][key] = checked
				Changed()
			end)
			box:SetPoint("TOPLEFT", COL_X[c], y)
			p.boxes[set .. key] = box
		end
	end
	-- under the arena and battleground rows: what PvP leaves out
	p.pvp = CK.Bind(Skin.Label(p, "", nil, "dim"), "WHERE_PVP")
	p.pvp:SetPoint("TOPLEFT", 0, -24 - #ORDER * LINE - 6)
	p.pvp:SetWidth(O.RIGHT_W - X)
	p.pvp:SetJustifyH("LEFT")
end

local function RefreshWhere(p)
	for _, key in ipairs(ORDER) do
		p.names[key]:SetText(L["SCN_" .. key])
		for _, col in ipairs(COLUMNS) do p.boxes[col[1] .. key]:SetChecked(RM.db[col[1]][key]) end
	end
end

-- ---------------------------------------------------------------------------
-- How they show
-- ---------------------------------------------------------------------------

local function SoundItems()
	local items = { { label = L["None"], value = "" } }
	for _, key in ipairs(RM.SOUNDS) do
		if SOUNDKIT and SOUNDKIT[key] then items[#items + 1] = { label = L["SOUND_" .. key], value = key } end
	end
	return items
end

local function BuildDisplay(p)
	p.size = Skin.Slider(p, "Icon size", { min = 24, max = 96, step = 2,
		onChange = function(v) RM.db.size = v; RM.ApplyDisplay(); O.Changed() end })
	p.size:SetPoint("TOPLEFT", 0, 0)
	p.expiring = Skin.Slider(p, "Running out within", { min = 0, max = 15,
		format = function(v) return v == 0 and L["Off"] or string.format(L["%d min"], v) end,
		parse = function(t) return tonumber((t or ""):match("%d+")) or 0 end,
		onChange = function(v) RM.db.expiring = v; Changed() end })
	p.expiring:SetPoint("TOPLEFT", 200, 0)

	-- unlocked, sample icons show and can be dragged; closing the window locks them again
	local y = -(Skin.SLIDER_H + 14)
	Skin.Field(p, "Position", 0, y)
	p.unlock = CK.Bind(Skin.Checkbox(p, "", function(checked)
		RM.SetLocked(not checked)
		O.Refresh()
	end), "Unlock")
	p.unlock:SetPoint("TOPLEFT", X, y - 1)
	local reset = CK.Bind(Skin.Button(p, "", 90, 20, function() RM.ResetPosition() end), "Reset position")
	reset:SetPoint("LEFT", p.unlock, "RIGHT", 16, 0)

	y = y - 32
	Skin.Field(p, "Show", 0, y)
	p.icons = Switch(p, "icons", "Icons on screen")
	p.icons:SetPoint("TOPLEFT", X, y - 1)
	p.hud = Switch(p, "hud", "Rows on the HUD")
	p.hud:SetPoint("LEFT", p.icons, "RIGHT", 16, 0)
	p.click = Switch(p, "click", "Click to use")
	p.click:SetPoint("TOPLEFT", X, y - 1 - LINE)
	Skin.Tooltip(p.click, "Click to use", "CLICK_TIP")
	p.glow = Switch(p, "glow", "Glow")
	p.glow:SetPoint("LEFT", p.click, "RIGHT", 16, 0)

	y = y - 2 * LINE - 6
	Skin.Field(p, "Sound", 0, y)
	p.sound = Skin.Dropdown(p, 200, SoundItems, function(_, item)
		RM.db.sound = item.value
		if item.value ~= "" then RM.PlaySample(item.value) end
		O.Changed()
	end)
	p.sound:SetPoint("TOPLEFT", X, y)
	Skin.Tooltip(p.sound, "Sound", "SOUND_TIP")
end

local function RefreshDisplay(p)
	local db = RM.db
	p.size:SetValue(db.size)
	p.expiring:SetValue(db.expiring)
	p.unlock:SetChecked(not RM.IsLocked())
	p.icons:SetChecked(db.icons)
	p.hud:SetChecked(db.hud)
	p.click:SetChecked(db.click)
	p.glow:SetChecked(db.glow)
	p.sound:SetValueText(db.sound ~= "" and L["SOUND_" .. db.sound] or L["None"])
end

local PAGES = {
	{ key = "consumables", label = "Consumables", Build = BuildConsumables, Refresh = RefreshConsumables },
	{ key = "class", label = "Your class", desc = "CLASS_DESC", Build = BuildClass, Refresh = RefreshClass },
	{ key = "where", label = "Where", desc = "WHERE_DESC", Build = BuildWhere, Refresh = RefreshWhere },
	{ key = "display", label = "Display", Build = BuildDisplay, Refresh = RefreshDisplay },
}

O.AddSection({
	key = "Reminder",
	module = "Reminder",
	order = 37,
	tab = function() return L["MOD_Reminder"] end,
	GetNodes = function()
		local nodes = {}
		for _, page in ipairs(PAGES) do nodes[#nodes + 1] = { key = page.key, label = L[page.label] } end
		return nodes
	end,
	GetHeader = function(node)
		for _, page in ipairs(PAGES) do
			if page.key == node and page.key ~= "consumables" then return L[page.label], page.desc and L[page.desc] end
		end
		return L["MOD_Reminder"], L["MODDESC_Reminder"]
	end,
	Build = function(body)
		RM = CK.modules.Reminder
		body.pages = {}
		for _, page in ipairs(PAGES) do
			local frame = CreateFrame("Frame", nil, body)
			frame:SetAllPoints()
			body.pages[page.key] = frame
			page.Build(frame)
		end
		-- sample icons where the row stands, without unlocking: a button by the title, on every page
		body.test = Skin.Button(body, "", 70, 20, function()
			RM.SetTesting(not RM.IsTesting())
			O.Refresh()
		end)
		body.test:SetPoint("LEFT", O.GetFrame().detail.title, "RIGHT", 12, 0)
	end,
	Refresh = function(node, body)
		RM = CK.modules.Reminder
		local which = body.pages[node] and node or "consumables"
		for key, frame in pairs(body.pages) do frame:SetShown(key == which) end
		RM.SetSampleKind(which)   -- the test shows this page's kind of reminder
		for _, page in ipairs(PAGES) do
			if page.key == which then page.Refresh(body.pages[which]) end
		end
		local testing = RM.IsTesting()
		body.test:SetLabel(L[testing and "Stop test" or "Test"])
		body.test:SetSelected(testing)
	end,
	OnWindowHide = function()
		local module = CK.modules.Reminder
		if module and not module.IsLocked() then module.SetLocked(true) end
		if module and module.IsTesting() then module.SetTesting(false) end
	end,
})
