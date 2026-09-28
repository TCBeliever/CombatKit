local CK = CombatKit
local L, Skin, O = CK.L, CK.Skin, CK.Options

-- ===========================================================================
-- Settings pages of the Loadout module: PvE / PvP (each optionally split into
-- its scenarios), Options, Debug. The module itself is CombatKit.modules.Loadout;
-- these pages only exist while it is on.
-- ===========================================================================

local SPEC_ICON = 40
local SPEC_SLOT = 84
local FIELD_X   = O.FIELD_X
local FIELD_W   = 300
local RIGHT_W   = O.RIGHT_W

local LO                -- the module, set whenever the section is used
local selected = {}     -- { kind = "group" | "scenario" | "page", key= }
local selectedSpec      -- specID whose talents and gear are being edited
local pages             -- body.pages, once built

local function ParseNode(node)
	local kind, key = (node or ""):match("^(%a+):(.+)$")
	if kind then return kind, key end
	return "page", node
end

-- ---------------------------------------------------------------------------
-- Data helpers
-- ---------------------------------------------------------------------------

local function GroupOf(key) return LO.SCENARIO_BY_KEY[key].group end

-- The cells the page shows, and whether they may be edited here: a scenario
-- that uses its group's settings shows the group's cells, read-only.
local function ShownSpecs()
	local char = LO.char
	if selected.kind == "group" then return char.groups[selected.key].specs, true end
	local entry = char.scenarios[selected.key]
	if entry.custom then return entry.specs, true end
	return char.groups[GroupOf(selected.key)].specs, false
end

local function Changed()
	O.Changed()
	LO.Check()   -- refreshes the HUD; editing settings never applies anything by itself
end

local function SetCell(idField, nameField, id, name)
	local specs = ShownSpecs()
	local cell = specs[selectedSpec] or {}
	cell[idField], cell[nameField] = id, id and name or nil
	if cell.configID == nil and cell.setID == nil then cell = nil end
	specs[selectedSpec] = cell
	Changed()
end

local function CopyCells(from, to)
	for specID, cell in pairs(from) do
		to[specID] = { configID = cell.configID, configName = cell.configName, setID = cell.setID, setName = cell.setName }
	end
end

local function TalentItems()
	local items = { { label = L["Not set"], value = nil } }
	for _, c in ipairs(LO.GetTalentConfigs(selectedSpec)) do
		items[#items + 1] = { label = c.name, value = c.id }
	end
	return items
end

local function GearItems()
	local items = { { label = L["Not set"], value = nil } }
	for _, s in ipairs(LO.GetEquipmentSets()) do
		items[#items + 1] = { label = s.name, value = s.id, icon = s.icon }
	end
	return items
end

-- Off + the given scenario keys
local function ScenarioItems(keys)
	local items = { { label = L["Off"], value = nil } }
	for _, key in ipairs(keys) do
		items[#items + 1] = { label = LO.ScenarioName(key), value = key }
	end
	return items
end

local ROLES = { "TANK", "HEALER", "DAMAGER" }
local function RoleItems()
	local items = { { label = L["Off"], value = nil } }
	for _, role in ipairs(ROLES) do
		items[#items + 1] = { label = L["ROLE_" .. role], value = role }
	end
	return items
end

local QUEUE_SCENARIOS = { "arena", "bg", "dungeon", "raid" }

-- "Open world, Delves, ..." for a group
local function GroupSummary(group)
	local names = {}
	for _, s in ipairs(LO.SCENARIOS) do
		if s.group == group then names[#names + 1] = LO.ScenarioName(s.key) end
	end
	return table.concat(names, L["LIST_SEP"])
end

-- Where the player is, as a node
local function CurrentNode()
	local key = LO.GetCurrentScenario()
	if not key then return nil end
	if key == "world" and LO.char.warmodePvP and LO.IsWarMode() then return "group", "pvp" end
	local group = GroupOf(key)
	if LO.char.split[group] then return "scenario", key end
	return "group", group
end

-- A scenario that switches spec opens on that spec: it is the one set up there.
local function FocusSpec()
	if selected.kind ~= "scenario" or not LO.SCENARIO_BY_KEY[selected.key].autoSpec then return end
	local autoSpec = LO.char.scenarios[selected.key].autoSpec
	if autoSpec then selectedSpec = autoSpec end
end

-- ---------------------------------------------------------------------------
-- A group or a scenario: pick a spec, then its talents and gear
-- ---------------------------------------------------------------------------

local function CreateSpecButton(parent)
	local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
	b:SetSize(SPEC_ICON + 4, SPEC_ICON + 4)
	Skin.Backdrop(b, "bg", 1, "border")
	b.icon = b:CreateTexture(nil, "ARTWORK")
	b.icon:SetPoint("TOPLEFT", 2, -2)
	b.icon:SetPoint("BOTTOMRIGHT", -2, 2)
	b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	-- corner mark: this spec has something set here
	b.dot = Skin.Fill(b, "OVERLAY", "accent")
	b.dot:SetSize(8, 8)
	b.dot:SetPoint("TOPRIGHT", -3, -3)
	-- "auto": the spec this scenario switches to
	b.tagBg = Skin.Fill(b, "OVERLAY", "accent")
	b.tagBg:SetPoint("BOTTOMLEFT", 1, 1)
	b.tag = Skin.Label(b, "", nil, "bg")
	b.tag:SetDrawLayer("OVERLAY", 7)
	b.tag:SetPoint("CENTER", b.tagBg)
	b.name = Skin.Label(b, "")
	b.name:SetPoint("TOP", b, "BOTTOM", 0, -4)
	b.name:SetWidth(SPEC_SLOT - 4)
	b.name:SetJustifyH("CENTER")
	b.name:SetWordWrap(false)
	b:SetScript("OnClick", function(self)
		selectedSpec = self.specID
		-- with "switch spec automatically" on, the picked spec is the one switched to
		if selected.kind == "scenario" and LO.SCENARIO_BY_KEY[selected.key].autoSpec then
			local entry = LO.char.scenarios[selected.key]
			if entry.autoSpec then
				entry.autoSpec = self.specID
				return Changed()
			end
		end
		O.Refresh()
	end)
	return b
end

local function BuildLoadout(p)
	-- a group page: list its scenarios separately in the tree
	p.split = CK.Bind(Skin.Checkbox(p, "", function(checked)
		LO.char.split[selected.key] = checked
		Changed()
	end), "Split into scenarios")
	p.split:SetPoint("TOPLEFT", 0, 0)
	Skin.Tooltip(p.split, "Split into scenarios", function() return "SPLIT_TIP_" .. selected.key end)

	-- checked: the scenario uses its group's settings. The label names the
	-- group, so it is set on refresh.
	p.follow = Skin.Checkbox(p, "", function(checked)
		local entry = LO.char.scenarios[selected.key]
		entry.custom = not checked
		-- first time on its own: start from what it was using until now
		if entry.custom and next(entry.specs) == nil then
			CopyCells(LO.char.groups[GroupOf(selected.key)].specs, entry.specs)
		end
		Changed()
	end)
	p.follow:SetPoint("TOPLEFT", 0, 0)

	-- open world and delves: switch to the picked spec on entering
	p.auto = CK.Bind(Skin.Checkbox(p, "", function(checked)
		LO.char.scenarios[selected.key].autoSpec = checked and selectedSpec or nil
		Changed()
	end), "Switch spec automatically")
	Skin.Tooltip(p.auto, "Switch spec automatically", "AUTOSPEC_TIP")
	p.autoHint = Skin.Label(p, "", nil, "dim")
	p.autoHint:SetPoint("LEFT", p.auto, "RIGHT", 10, 0)

	-- the spec picker and its two fields move as one block under whatever rows are shown
	local editor = CreateFrame("Frame", nil, p)
	editor:SetSize(RIGHT_W, 200)
	p.editor = editor
	p.specButtons = {}   -- created on first refresh

	local fieldY = -(SPEC_ICON + 4) - 4 - 14 - 14
	Skin.Field(editor, "Talent loadout", 0, fieldY)
	p.talents = Skin.Dropdown(editor, FIELD_W, TalentItems, function(_, item)
		SetCell("configID", "configName", item.value, item.label)
	end)
	p.talents:SetPoint("TOPLEFT", FIELD_X, fieldY)

	Skin.Field(editor, "Equipment set", 0, fieldY - 28)
	p.gear = Skin.Dropdown(editor, FIELD_W, GearItems, function(_, item)
		SetCell("setID", "setName", item.value, item.label)
	end)
	p.gear:SetPoint("TOPLEFT", FIELD_X, fieldY - 28)

	-- what the page shows, applied right now: the spec picked above, its talents and
	-- gear, whatever is on already (so a loadout can be re-applied)
	p.switch = CK.Bind(Skin.Button(editor, "", 110, 22, function()
		local specs = ShownSpecs()
		local setup = LO.BuildSetupFor(selectedSpec, specs[selectedSpec])
		if setup then LO.ApplySetup(setup) end
		O.Refresh()
	end), "Switch now")
	p.switch:SetPoint("TOPLEFT", FIELD_X, fieldY - 28 - 32)
	Skin.Tooltip(p.switch, "Switch now", "SWITCH_NOW_TIP")

	p.warmode = CK.Bind(Skin.Checkbox(editor, "", function(checked)
		LO.char.warmodePvP = checked
		Changed()
	end), "Open world with War Mode uses PvP")
	p.warmode:SetPoint("TOPLEFT", 0, fieldY - 28 - 32 - 36)
end

local function RefreshLoadout(p)
	local char = LO.char
	local isScenario = selected.kind == "scenario"
	local scenario = isScenario and LO.SCENARIO_BY_KEY[selected.key]
	local entry = isScenario and char.scenarios[selected.key]
	local canAutoSpec = isScenario and scenario.autoSpec or false
	local autoSpec = canAutoSpec and entry.autoSpec or nil

	local specs, editable = ShownSpecs()
	local currentSpec = LO.GetCurrentSpecID()
	local list = LO.GetSpecs()

	-- with "switch spec automatically" on, the picked spec IS the target
	if autoSpec then selectedSpec = autoSpec end
	local known = false
	for _, spec in ipairs(list) do if spec.id == selectedSpec then known = true end end
	if not known then selectedSpec = currentSpec or (list[1] and list[1].id) end

	-- the rows above the spec picker: only the ones this page has
	local y = 0
	local isGroup = selected.kind == "group"
	p.split:SetShown(isGroup)
	if isGroup then
		p.split:SetChecked(char.split[selected.key])
		y = y - 26
	end
	p.follow:SetShown(isScenario)
	if isScenario then
		p.follow:SetLabel(L["Use the %s settings"]:format(LO.GroupName(scenario.group)))
		p.follow:SetChecked(not entry.custom)
		y = y - 26
	end
	p.auto:SetShown(canAutoSpec)
	p.autoHint:SetShown(autoSpec ~= nil)
	if canAutoSpec then
		p.auto:ClearAllPoints()
		p.auto:SetPoint("TOPLEFT", 0, y)
		p.auto:SetChecked(autoSpec ~= nil)
		if autoSpec then
			local target = LO.GetSpecByID(autoSpec)
			p.autoHint:SetText(L["On entering: %s"]:format(target and target.name or "?"))
		end
		y = y - 26
	end
	p.editor:ClearAllPoints()
	p.editor:SetPoint("TOPLEFT", 0, y - 4)

	for i = 1, math.max(#list, #p.specButtons) do
		local spec = list[i]
		local b = p.specButtons[i]
		if spec then
			if not b then
				b = CreateSpecButton(p.editor)
				b:SetPoint("TOPLEFT", (i - 1) * SPEC_SLOT + (SPEC_SLOT - SPEC_ICON - 4) / 2, 0)
				p.specButtons[i] = b
			end
			local isSelected = spec.id == selectedSpec
			local isTarget = spec.id == autoSpec
			b.specID = spec.id
			b.icon:SetTexture(spec.icon)
			b.icon:SetAlpha(isSelected and 1 or 0.45)
			b.icon:SetDesaturated(not isSelected)
			b:SetBackdropBorderColor(Skin.Color(isSelected and "accent" or "border"))
			b.dot:SetShown(specs[spec.id] ~= nil)
			b.tagBg:SetShown(isTarget)
			b.tag:SetShown(isTarget)
			if isTarget then
				b.tag:SetText(L["auto"])
				b.tagBg:SetSize(b.tag:GetStringWidth() + 6, 12)
			end
			b.name:SetText(spec.name)
			b.name:SetTextColor(Skin.Color(spec.id == currentSpec and "ok" or isSelected and "text" or "dim"))
			b:Show()
		elseif b then
			b:Hide()
		end
	end

	local cell = selectedSpec and specs[selectedSpec]
	if cell then LO.RepairCell(cell, selectedSpec) end
	local usable = editable and selectedSpec ~= nil
	p.talents:SetDisabled(not usable)
	p.gear:SetDisabled(not usable)
	p.talents:SetValueText(cell and cell.configName or L["Not set"], not (cell and cell.configID))
	p.gear:SetValueText(cell and cell.setName or L["Not set"], not (cell and cell.setID))
	-- nothing to switch to at all (this spec, nothing set): the button waits
	p.switch:SetDisabled(selectedSpec == nil or LO.BuildSetupFor(selectedSpec, cell) == nil)

	local isPvP = isGroup and selected.key == "pvp"
	p.warmode:SetShown(isPvP)
	if isPvP then p.warmode:SetChecked(char.warmodePvP) end
end

-- ---------------------------------------------------------------------------
-- Options
-- ---------------------------------------------------------------------------

local function BuildOptions(p)
	local y = 0
	local function Toggle(labelKey, tipKey, get, set)
		local c = CK.Bind(Skin.Checkbox(p, "", function(checked) set(checked); Changed() end), labelKey)
		c:SetPoint("TOPLEFT", 0, y)
		if tipKey then Skin.Tooltip(c, labelKey, tipKey) end
		c.get = get
		y = y - 26
		return c
	end
	p.auto = Toggle("Switch talents and gear automatically", "AUTO_TIP",
		function() return LO.db.settings.auto end, function(v) LO.db.settings.auto = v end)
	p.gearCheck = Toggle("Smart gear check", "GEARCHECK_TIP",
		function() return LO.db.settings.gearCheck end, function(v) LO.db.settings.gearCheck = v end)
	p.early = Toggle("Show the next scenario on a queue pop", "EARLY_TIP",
		function() return LO.db.settings.early end, function(v) LO.db.settings.early = v end)
	p.mismatch = Toggle("On the HUD only when something differs", nil,
		function() return LO.db.settings.hud == "mismatch" end,
		function(v) LO.db.settings.hud = v and "mismatch" or "always" end)
	p.toggles = { p.auto, p.gearCheck, p.early, p.mismatch }
end

local function RefreshOptions(p)
	for _, c in ipairs(p.toggles) do c:SetChecked(c.get()) end
end

-- ---------------------------------------------------------------------------
-- Debug: simulate being somewhere else. Session only.
-- ---------------------------------------------------------------------------

local ADVANCED = { "early", "role", "warmode", "locked", "dryRun", "verbose" }   -- LO.debug fields behind "Advanced"
local advancedOpen = false   -- this session only

local function BuildDebug(page)
	local function Set(field, value)
		LO.debug[field] = value or nil
		Changed()
	end
	local X = FIELD_X + 30

	-- the one thing this page is for: a button per scenario, the simulated one lit.
	-- "Off" sits with the title; below it a line per group, its buttons equally wide.
	Skin.Field(page, "Simulate scenario", 0, 0)
	page.scenarioButtons = {}
	local function ScenarioButton(key, group)
		local b = Skin.Button(page, "", 60, 22, function() Set("scenario", key) end)
		b.scenario, b.group = key, group
		page.scenarioButtons[#page.scenarioButtons + 1] = b
		page.scenarioButtons[key or "off"] = b
	end
	ScenarioButton(nil)
	for _, s in ipairs(LO.SCENARIOS) do ScenarioButton(s.key, s.group) end
	page.groupLabels = {}
	for _, group in ipairs(LO.GROUPS) do
		page.groupLabels[group] = Skin.Label(page, "", nil, "dim")
	end

	page.advancedToggle = Skin.Button(page, "", 90, 22, function()
		advancedOpen = not advancedOpen
		O.Refresh()
	end)

	-- everything else
	local p = CreateFrame("Frame", nil, page)
	p:SetSize(O.RIGHT_W, 10)
	page.advanced = p

	Skin.Field(p, "Simulate queue pop", 0, 0)
	page.early = Skin.Dropdown(p, 220, function() return ScenarioItems(QUEUE_SCENARIOS) end, function(_, item)
		Set("early", item.value)
	end)
	page.early:SetPoint("TOPLEFT", X, 0)

	Skin.Field(p, "Simulate group role", 0, -28)
	page.role = Skin.Dropdown(p, 220, RoleItems, function(_, item) Set("role", item.value) end)
	page.role:SetPoint("TOPLEFT", X, -28)

	local y = -62
	local function Toggle(field, key, tipKey)
		local c = CK.Bind(Skin.Checkbox(p, "", function(checked) Set(field, checked) end), key)
		c:SetPoint("TOPLEFT", 0, y)
		if tipKey then Skin.Tooltip(c, key, tipKey) end
		y = y - 24
		return c
	end
	page.warmode = Toggle("warmode", "Simulate War Mode")
	page.locked  = Toggle("locked", "Simulate a running key or match")
	y = y - 8
	page.dryRun  = Toggle("dryRun", "Dry run", "DRYRUN_TIP")
	page.verbose = Toggle("verbose", "Debug messages in chat")

	page.enter = CK.Bind(Skin.Button(p, "", 110, 22, function() LO.EnterAgain() end), "Enter again")
	page.enter:SetPoint("TOPLEFT", 0, y - 10)
	Skin.Tooltip(page.enter, "Enter again", "ENTER_TIP")
	page.reset = CK.Bind(Skin.Button(p, "", 110, 22, function()
		wipe(LO.debug)
		Changed()
	end), "Reset all")
	page.reset:SetPoint("LEFT", page.enter, "RIGHT", 8, 0)
end

local function RefreshDebug(p)
	local dbg = LO.debug

	-- A button is as wide as its label needs in this language. Those of the scenarios
	-- share one width, so the lines read as a grid; a label too long for four of them
	-- on a line (it has few neighbours) keeps its own.
	local GROUP_X, GAP = 44, 6
	local cap = math.floor((O.RIGHT_W - GROUP_X - GAP * 3) / 4)
	local shared = 0
	for _, b in ipairs(p.scenarioButtons) do
		b:SetLabel(b.scenario and LO.ScenarioName(b.scenario) or L["Off"])
		b:SetSelected(dbg.scenario == b.scenario)
		if b.scenario and b:GetWidth() <= cap then shared = math.max(shared, b:GetWidth()) end
	end
	local off = p.scenarioButtons.off
	off:ClearAllPoints()
	off:SetPoint("TOPLEFT", FIELD_X + 30, 0)

	local y = -34
	for _, group in ipairs(LO.GROUPS) do
		local label = p.groupLabels[group]
		label:SetText(LO.GroupName(group))
		label:ClearAllPoints()
		label:SetPoint("TOPLEFT", 0, y - 5)
		local x = GROUP_X
		for _, b in ipairs(p.scenarioButtons) do
			if b.group == group then
				if b:GetWidth() <= cap then b:SetWidth(shared) end
				b:ClearAllPoints()
				b:SetPoint("TOPLEFT", x, y)
				x = x + b:GetWidth() + GAP
			end
		end
		y = y - 28
	end
	y = y - 12

	-- "Advanced" says how many of its settings are on, so none of them hides
	local active = 0
	for _, field in ipairs(ADVANCED) do
		if dbg[field] then active = active + 1 end
	end
	p.advancedToggle:SetLabel(active > 0 and (L["Advanced"] .. " (" .. active .. ")") or L["Advanced"])
	p.advancedToggle:SetSelected(advancedOpen)
	p.advancedToggle:ClearAllPoints()
	p.advancedToggle:SetPoint("TOPLEFT", 0, y)
	p.advanced:ClearAllPoints()
	p.advanced:SetPoint("TOPLEFT", 0, y - 34)
	p.advanced:SetShown(advancedOpen)

	p.early:SetValueText(dbg.early and LO.ScenarioName(dbg.early) or L["Off"], not dbg.early)
	p.role:SetValueText(dbg.role and L["ROLE_" .. dbg.role] or L["Off"], not dbg.role)
	p.warmode:SetChecked(dbg.warmode)
	p.locked:SetChecked(dbg.locked)
	p.dryRun:SetChecked(dbg.dryRun)
	p.verbose:SetChecked(dbg.verbose)
end

-- ---------------------------------------------------------------------------
-- The section
-- ---------------------------------------------------------------------------

O.AddSection({
	key = "Loadout",
	module = "Loadout",
	order = 10,
	tab = function() return L["MOD_Loadout"] end,

	GetNodes = function()
		LO = CK.modules.Loadout
		local nodes = {}
		local curKind, curKey = CurrentNode()
		for _, group in ipairs(LO.GROUPS) do
			nodes[#nodes + 1] = { key = "group:" .. group, label = LO.GroupName(group),
				here = (curKind == "group" and curKey == group) }
			if LO.char.split[group] then
				for _, s in ipairs(LO.SCENARIOS) do
					if s.group == group then
						nodes[#nodes + 1] = { key = "scenario:" .. s.key, label = LO.ScenarioName(s.key), indent = 22,
							tag = LO.char.scenarios[s.key].custom and L["own"] or nil,
							here = (curKind == "scenario" and curKey == s.key) }
					end
				end
			end
		end
		nodes[#nodes + 1] = { key = "options", label = L["Options"] }
		nodes[#nodes + 1] = { key = "debug", label = L["PAGE_debug"], tag = LO.IsFaking() and L["faked"] or nil }
		return nodes
	end,

	GetHeader = function(node)
		LO = CK.modules.Loadout
		local kind, key = ParseNode(node)
		if kind == "group" then return LO.GroupName(key), GroupSummary(key) end
		if kind == "scenario" then return LO.ScenarioName(key), L["SCN_DESC_" .. key] end
		if key == "debug" then return L["PAGE_debug"], L["PAGE_DESC_debug"] end
		return L["Options"], nil
	end,

	DefaultNode = function()
		LO = CK.modules.Loadout
		local kind, key = CurrentNode()
		return kind and (kind .. ":" .. key) or "group:pve"
	end,

	OnSelect = function(node)
		LO = CK.modules.Loadout
		local kind, key = ParseNode(node)
		-- a scenario whose group is no longer split has no page: fall back to the group
		if kind == "scenario" and not LO.char.split[GroupOf(key)] then kind, key = "group", GroupOf(key) end
		selected = { kind = kind, key = key }
		if not selectedSpec then selectedSpec = LO.GetCurrentSpecID() end
		FocusSpec()
	end,

	Build = function(body)
		LO = CK.modules.Loadout
		pages = {}
		for _, key in ipairs({ "loadout", "options", "debug" }) do
			local page = CreateFrame("Frame", nil, body)
			page:SetAllPoints()
			pages[key] = page
		end
		body.pages = pages
		BuildLoadout(pages.loadout)
		BuildOptions(pages.options)
		BuildDebug(pages.debug)
	end,

	Refresh = function(node, body)
		LO = CK.modules.Loadout
		local which = (selected.kind == "page") and selected.key or "loadout"
		for key, page in pairs(body.pages) do page:SetShown(key == which) end
		if which == "loadout" then
			RefreshLoadout(body.pages.loadout)
		elseif which == "options" then
			RefreshOptions(body.pages.options)
		else
			RefreshDebug(body.pages.debug)
		end
	end,
})
