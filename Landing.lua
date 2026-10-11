local ADDON, ns = ...
local L, Skin = ns.L, ns.Skin

-- ===========================================================================
-- The landing: a small window at login, the first time the kit runs and
-- again whenever a module the player was never asked about appears (an
-- update that brought one). One row per module, ticked as it would be on,
-- Apply switches them, Later asks again next login. /ck landing shows it
-- for every module, to look at it.
-- ===========================================================================

local Landing = {}
ns.Landing = Landing

local W = 440
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
	Skin.Backdrop(f, "bg", 1)
	tinsert(UISpecialFrames, "CombatKitLanding")   -- Esc closes it: Later

	local bar = Skin.Panel(f, "panel")
	bar:SetPoint("TOPLEFT")
	bar:SetPoint("TOPRIGHT")
	bar:SetHeight(28)
	f.title = Skin.Label(bar, Skin.Text("accent", "Combat") .. "Kit", "GameFontHighlight")
	f.title:SetPoint("LEFT", 10, 0)

	f.intro = Skin.Label(f, "", nil, "dim")
	f.intro:SetPoint("TOPLEFT", 14, -40)
	f.intro:SetWidth(W - 28)
	f.intro:SetJustifyH("LEFT")

	f.rows = {}
	f.apply = ns.Bind(Skin.Button(f, "", 90, 22, function() Landing.Apply() end), "Apply")
	f.later = ns.Bind(Skin.Button(f, "", 90, 22, function() Landing.Later() end), "Later")
	f.apply:SetPoint("BOTTOMRIGHT", -14, 12)
	f.later:SetPoint("RIGHT", f.apply, "LEFT", -8, 0)
	f:Hide()
	frame = f
	return f
end

local function Row(i)
	local f = frame
	local row = f.rows[i]
	if row then return row end
	row = {}
	row.check = Skin.Checkbox(f, "", function() end)
	row.desc = Skin.Label(f, "", nil, "dim")
	row.desc:SetWidth(W - 28 - 20)
	row.desc:SetJustifyH("LEFT")
	f.rows[i] = row
	return row
end

-- The modules on offer, in the window; `defs` from CombatKit.MODULES.
function Landing.Show(defs, why)
	local f = frame or Create()
	f.defs = defs
	f.intro:SetText(L[why == "first" and "LANDING_FIRST" or "LANDING_NEW"])
	local introH = f.intro:GetStringHeight()
	if type(introH) ~= "number" or introH < 14 then introH = 40 end
	local above
	for i, def in ipairs(defs) do
		local row = Row(i)
		local nameKey = "MODLIST_" .. def.name
		if not (ns.locales.enUS[nameKey] or ns.locales.zhTW[nameKey]) then nameKey = "MOD_" .. def.name end
		ns.Bind(row.check, nameKey)
		row.check:SetChecked(ns.IsModuleEnabled(def.name) or (def.default == true and ns.db.settings.asked[def.name] == nil))
		row.check:ClearAllPoints()
		if above then
			row.check:SetPoint("TOPLEFT", above, "BOTTOMLEFT", -20, -10)
		else
			row.check:SetPoint("TOPLEFT", f.intro, "BOTTOMLEFT", 0, -16)   -- under the text, however many lines it takes
		end
		row.desc:SetText(L["MODDESC_" .. def.name])
		row.desc:ClearAllPoints()
		row.desc:SetPoint("TOPLEFT", row.check, "BOTTOMLEFT", 20, -2)
		row.check:Show()
		row.desc:Show()
		row.module = def.name
		above = row.desc
	end
	for i = #defs + 1, #f.rows do
		f.rows[i].check:Hide()
		f.rows[i].desc:Hide()
	end
	f:SetHeight(40 + introH + 16 + #defs * 44 + 50)
	f:Show()
end

function Landing.IsShown() return frame ~= nil and frame:IsShown() end
function Landing.GetFrame() return frame end

-- The choices taken: each module as ticked, and none of them asked about again.
function Landing.Apply()
	if not frame then return end
	for i, def in ipairs(frame.defs or {}) do
		local on = frame.rows[i].check:GetChecked()
		if not def.features and on ~= ns.IsModuleEnabled(def.name) then ns.SetModuleEnabled(def.name, on) end
		ns.db.settings.asked[def.name] = true
	end
	frame:Hide()
end

-- Not now: the same question comes back next login.
function Landing.Later()
	if frame then frame:Hide() end
end

-- The modules the player was never asked about (switched as a whole; the small
-- features are switched on their own pages), and whether this is the first time.
function ns.PendingModules()
	local out, anyAsked = {}, false
	for name in pairs(ns.db.settings.asked) do anyAsked = true end
	for _, def in ipairs(ns.MODULES) do
		if not def.features and not ns.db.settings.asked[def.name] then out[#out + 1] = def end
	end
	return out, anyAsked and "new" or "first"
end
