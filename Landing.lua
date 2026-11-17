local ADDON, ns = ...
local L, Skin = ns.L, ns.Skin

-- ===========================================================================
-- The landing: a small window at login, the first time the kit runs and
-- again whenever a module the player was never asked about appears (an
-- update that brought one). One row per module, ticked as it would be on,
-- Apply switches them, Later asks again next login. /ck landing shows it
-- for every module, to look at it.
--
-- A module's options (CombatKit.MODULES `options`, off by default) have a row
-- of their own under it, usable while the module is ticked. A new option is
-- asked about once, on its own landing, wherever its module is on.
-- ===========================================================================

local Landing = {}
ns.Landing = Landing

local W = 480
local BODY_FONT = "GameFontHighlight"
-- the whole window is scaled so its body text reads at this size, and everything else with it
-- (the user's ask, 2026-11-04: text at 20, the rest to scale)
local BODY_SIZE = 20
local BG_ALPHA = 0.75   -- the window's ground lets a little of the world through
local frame

local function Create()
	local f = CreateFrame("Frame", "CombatKitLanding", UIParent, "BackdropTemplate")
	f:SetWidth(W)
	f:SetPoint("CENTER", 0, 80)
	f:SetFrameStrata("DIALOG")
	f:SetToplevel(true)
	f:SetClampedToScreen(true)
	f:SetMovable(true)
	f:EnableMouse(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", f.StopMovingOrSizing)
	Skin.Backdrop(f, "bg", BG_ALPHA)
	tinsert(UISpecialFrames, "CombatKitLanding")   -- Esc closes it: Later

	local bar = Skin.Panel(f, "panel")
	bar:SetPoint("TOPLEFT")
	bar:SetPoint("TOPRIGHT")
	bar:SetHeight(28)
	f.title = Skin.Label(bar, Skin.Text("accent", "Combat") .. "Kit", "GameFontHighlightLarge")
	f.title:SetPoint("LEFT", 10, 0)

	f.intro = Skin.Label(f, "", BODY_FONT, "dim")
	f.intro:SetPoint("TOPLEFT", 14, -40)
	f.intro:SetWidth(W - 28)
	f.intro:SetJustifyH("LEFT")

	f.rows = {}
	f.optionRows = {}
	f.apply = ns.Bind(Skin.Button(f, "", 90, 22, function() Landing.Apply() end), "Apply")
	f.later = ns.Bind(Skin.Button(f, "", 90, 22, function() Landing.Later() end), "Later")
	f.apply:SetPoint("BOTTOMRIGHT", -14, 12)
	f.later:SetPoint("RIGHT", f.apply, "LEFT", -8, 0)
	-- for a newcomer who wants to look around: the choices as they stand, then the settings window
	f.settings = ns.Bind(Skin.Button(f, "", 100, 22, function() Landing.OpenSettings() end), "Go to settings")
	f.settings:SetPoint("BOTTOMLEFT", 14, 12)
	f:Hide()
	frame = f
	return f
end

local function NewRow(onChange)
	local row = {}
	row.check = Skin.Switch(frame, "", onChange)
	row.check.label:SetFontObject(BODY_FONT)
	row.desc = Skin.Label(frame, "", BODY_FONT, "dim")
	row.desc:SetJustifyH("LEFT")
	return row
end

-- an option can be ticked while its module is
local function UpdateOptions()
	for i = 1, frame.optionCount or 0 do
		local row = frame.optionRows[i]
		row.check:SetDisabled(not row.parent.check:GetChecked())
	end
end

-- a switch for each module: on or off, one setting each
local function Row(i)
	frame.rows[i] = frame.rows[i] or NewRow(UpdateOptions)
	return frame.rows[i]
end

local function OptionRow(n)
	frame.optionRows[n] = frame.optionRows[n] or NewRow(function() end)
	return frame.optionRows[n]
end

-- An option as the module has it now; off while the module is not running
local function OptionValue(def, key)
	local module = ns.modules[def.name]
	if not (module and module.enabled and module.GetOption) then return false end
	return module.GetOption(key) and true or false
end

-- Places a row: its switch under `above` (nil: under the intro), `indent` to
-- the right of where the rows start, its text under the switch's label.
-- Returns the row's height.
local function Place(row, above, aboveIndent, indent, labelKey, descKey)
	local f = frame
	ns.Bind(row.check, labelKey)
	row.check:ClearAllPoints()
	local labelX = row.check:BaseLabelX()
	if above then
		-- `above` is the previous row's text, which starts at its label
		row.check:SetPoint("TOPLEFT", above, "BOTTOMLEFT", indent - aboveIndent - labelX, -10)
	else
		row.check:SetPoint("TOPLEFT", f.intro, "BOTTOMLEFT", indent, -16)   -- under the text, however many lines it takes
	end
	row.desc:SetText(L[descKey])
	row.desc:ClearAllPoints()
	row.desc:SetPoint("TOPLEFT", row.check, "BOTTOMLEFT", labelX, -2)
	row.desc:SetWidth(W - 28 - labelX - indent)
	row.check:Show()
	row.desc:Show()
	-- a description may wrap: the row is as tall as its text
	local descH = row.desc:GetStringHeight()
	if type(descH) ~= "number" or descH < 14 then descH = 16 end
	return 18 + 2 + descH + 10
end

-- how much the window is scaled: its body text at BODY_SIZE, whatever size the client gives the font
local function Scale()
	local font = _G[BODY_FONT]
	local base = font and font.GetFont and select(2, font:GetFont())
	if type(base) ~= "number" or base <= 0 then return 1 end
	return BODY_SIZE / base
end

-- The modules on offer, in the window; `defs` from CombatKit.MODULES.
function Landing.Show(defs, why)
	local f = frame or Create()
	f:SetScale(Scale())
	f.defs = defs
	f.intro:SetText(L[why == "first" and "LANDING_FIRST" or why == "options" and "LANDING_OPTIONS" or "LANDING_NEW"])
	local introH = f.intro:GetStringHeight()
	if type(introH) ~= "number" or introH < 14 then introH = 40 end
	local above, aboveIndent, rowsH, n = nil, 0, 0, 0
	for i, def in ipairs(defs) do
		local row = Row(i)
		local nameKey = "MODLIST_" .. def.name
		if not (ns.locales.enUS[nameKey] or ns.locales.zhTW[nameKey]) then nameKey = "MOD_" .. def.name end
		row.check:SetChecked(ns.IsModuleEnabled(def.name) or (def.default == true and ns.db.settings.asked[def.name] == nil))
		rowsH = rowsH + Place(row, above, aboveIndent, 0, nameKey, "MODDESC_" .. def.name)
		row.module = def.name
		above, aboveIndent = row.desc, 0
		-- its options, under its label
		local optionIndent = row.check:BaseLabelX()
		for _, key in ipairs(def.options or {}) do
			n = n + 1
			local opt = OptionRow(n)
			opt.parent, opt.def, opt.key = row, def, key
			opt.check:SetChecked(OptionValue(def, key))
			rowsH = rowsH + Place(opt, above, aboveIndent, optionIndent, "LANDOPT_" .. key, "LANDOPTDESC_" .. key)
			above, aboveIndent = opt.desc, optionIndent
		end
	end
	for i = #defs + 1, #f.rows do
		f.rows[i].check:Hide()
		f.rows[i].desc:Hide()
	end
	for i = n + 1, #f.optionRows do
		f.optionRows[i].check:Hide()
		f.optionRows[i].desc:Hide()
	end
	f.optionCount = n
	UpdateOptions()
	f:SetHeight(40 + introH + 16 + rowsH + 50)
	f:Show()
end

function Landing.IsShown() return frame ~= nil and frame:IsShown() end
function Landing.GetFrame() return frame end

-- The choices taken: each module as ticked, then the options of those that
-- run. Nothing shown is asked about again.
function Landing.Apply()
	if not frame then return end
	for i, def in ipairs(frame.defs or {}) do
		local on = frame.rows[i].check:GetChecked()
		if not def.features and on ~= ns.IsModuleEnabled(def.name) then ns.SetModuleEnabled(def.name, on) end
		ns.db.settings.asked[def.name] = true
	end
	for i = 1, frame.optionCount or 0 do
		local opt = frame.optionRows[i]
		local module = ns.modules[opt.def.name]
		if module and module.enabled and module.SetOption then
			module.SetOption(opt.key, opt.check:GetChecked() and true or false)
		end
		ns.db.settings.asked[opt.def.name .. "." .. opt.key] = true
	end
	frame:Hide()
end

-- The choices taken, then the settings window
function Landing.OpenSettings()
	Landing.Apply()
	ns.OpenOptions()
end

-- Not now: the same question comes back next login.
function Landing.Later()
	if frame then frame:Hide() end
end

-- The modules the player was never asked about (switched as a whole; the small
-- features are switched on their own pages), and those that are on with an
-- option never asked about. Returns them, and why: "first" (nothing was ever
-- asked), "new" (a new module among them) or "options" (new options only).
function ns.PendingModules()
	local asked = ns.db.settings.asked
	local out, anyAsked, newModule = {}, false, false
	for _ in pairs(asked) do anyAsked = true end
	for _, def in ipairs(ns.MODULES) do
		if not def.features then
			if not asked[def.name] then
				out[#out + 1], newModule = def, true
			elseif ns.IsModuleEnabled(def.name) then
				for _, key in ipairs(def.options or {}) do
					if not asked[def.name .. "." .. key] then
						out[#out + 1] = def
						break
					end
				end
			end
		end
	end
	return out, not anyAsked and "first" or newModule and "new" or "options"
end
