local ADDON, ns = ...
local L = ns.L
local Skin = ns.Skin

-- ===========================================================================
-- This module's lines on the HUD: what the scenario wants for the current spec
--
--   [icon]   Havoc             Ready          [icon]   Havoc    Click to switch
--   Talents  M+ AoE                           Talents  M+ AoE
--   Gear     PvE                              Gear     PvP
--                                             →        PvE
--
-- Green matches. What differs takes two lines: what is on now, dimmed, and
-- under it, after an arrow, what will be applied, amber. Red no longer exists,
-- grey is not set up. When the scenario wants another spec, the first line
-- names it ("→ Vengeance"). A left click switches.
-- ===========================================================================

-- Returns text, colour name
local function StateText(st, early)
	if early then return L["Queue: %s"]:format(ns.ScenarioShortName(early)), "warn" end
	if ns.IsApplying() then
		return (ns.GetApplyWait() == "moving") and L["Stand still"] or L["Applying"], "warn"
	end
	if st.state == "mismatch" then
		if InCombatLockdown() and ns.IsAutoPending() then return L["After combat"], "warn" end
		if st.targetSpecID then
			local target = ns.GetSpecByID(st.targetSpecID)
			return "→ " .. (target and target.name or "?"), "warn"
		end
		return L["Click to switch"], "warn"
	end
	if st.state == "ready" then return L["Ready"], "ok" end
	return L["Not set up"], "dim"
end

-- The line(s) for talents or gear: one when it matches (or nothing is set up),
-- two when it differs: what is on now, then what will be applied.
local function AddLines(rows, label, has, ok, missing, target, current)
	if not has then
		rows[#rows + 1] = { label = label, value = Skin.Text("dim", "-") }
		return
	end
	local want = missing and Skin.Text("bad", (target or "?") .. " (" .. L["missing"] .. ")") or Skin.Text("warn", target or "?")
	if ok then
		rows[#rows + 1] = { label = label, value = Skin.Text("ok", target or "?") }
	else
		rows[#rows + 1] = { label = label, value = Skin.Text("dim", current or "-") }
		rows[#rows + 1] = { label = "→", value = want }
	end
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
		local rows = { { icon = spec and spec.icon or 134400, value = name, right = Skin.Text(colour, text) } }
		AddLines(rows, L["Talents"], st.hasTalents, st.talentsOK, st.talentsMissing, cell.configName,
			st.hasTalents and not st.talentsOK and ns.GetActiveConfigName(st.specID) or nil)
		AddLines(rows, L["Gear"], st.hasGear, st.gearOK, st.gearMissing, cell.setName,
			st.hasGear and not st.gearOK and ns.GetEquippedSetName() or nil)
		return rows, alert
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
