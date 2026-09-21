local ADDON, ns = ...
local L = ns.L
local Skin = ns.Skin

-- ===========================================================================
-- This module's lines on the HUD: what the scenario wants for the current spec
--
--   [icon]   Havoc             Ready
--   Talents  M+ AoE
--   Gear     PvE
--
-- Green matches, amber differs, red no longer exists, grey is not set up.
-- A left click applies.
-- ===========================================================================

-- Returns text, colour name
local function StateText(st, early)
	if early then return L["Queue: %s"]:format(ns.ScenarioName(early)), "warn" end
	if ns.IsApplying() then
		return (ns.GetApplyWait() == "moving") and L["Stand still"] or L["Applying"], "warn"
	end
	if st.state == "mismatch" then
		if InCombatLockdown() and ns.IsAutoPending() then return L["After combat"], "warn" end
		return L["Click to apply"], "warn"
	end
	if st.state == "ready" then return L["Ready"], "ok" end
	return L["Not set up"], "dim"
end

-- Returns the coloured value for the talents or gear line
local function ValueText(has, ok, missing, name)
	if not has then return Skin.Text("dim", "-") end
	if missing then return Skin.Text("bad", (name or "?") .. " (" .. L["missing"] .. ")") end
	return Skin.Text(ok and "ok" or "warn", name or "?")
end

local function SourceName(source)
	if source == "pve" or source == "pvp" then return ns.GroupName(source) end
	return source and ns.ScenarioName(source) or "-"
end

local function Current()
	local early = ns.GetEarlyScenario()
	local key = early or ns.GetCurrentScenario()
	return early, key, key and ns.GetStatus(key)
end

ns.hudSection = {
	key = "loadout",
	order = 10,

	GetRows = function(force)
		if not ns.char then return nil end
		local early, key, st = Current()
		if not st then return nil end
		local alert = early ~= nil or st.state == "mismatch"
		if not force and ns.db.settings.hud == "mismatch" and not alert and not ns.IsApplying() then
			return nil
		end

		local spec = st.specID and ns.GetSpecByID(st.specID)
		local name = spec and spec.name or "-"
		if ns.IsFaking() then name = name .. " " .. Skin.Text("dim", "(" .. L["faked"] .. ")") end
		local text, colour = StateText(st, early)
		local cell = st.cell or {}
		return {
			{ icon = spec and spec.icon or 134400, value = name, right = Skin.Text(colour, text) },
			{ label = L["Talents"], value = ValueText(st.hasTalents, st.talentsOK, st.talentsMissing, cell.configName) },
			{ label = L["Gear"], value = ValueText(st.hasGear, st.gearOK, st.gearMissing, cell.setName) },
		}, alert
	end,

	OnClick = function() ns.ApplyNow() end,

	OnTooltip = function(tooltip)
		local early, key, st = Current()
		if not st then return end
		local r, g, b = Skin.Color("dim")
		local function Row(label, value) tooltip:AddDoubleLine(label, value, r, g, b, 1, 1, 1) end
		Row(L["Scenario"], ns.ScenarioName(key))
		Row(L["Settings from"], SourceName(st.source))
		if st.autoSpec then
			local spec = ns.GetSpecByID(st.autoSpec)
			Row(L["Spec on entering"], spec and spec.name or "?")
		end
		Row(L["Status"], (StateText(st, early)))
		tooltip:AddLine(L["LOADOUT_HINT"], r, g, b)
	end,
}
