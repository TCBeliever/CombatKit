local ADDON, ns = ...
local CK = CombatKit
local L = CK.L

CK.NewModule("Misc", ns)

-- ===========================================================================
-- Small things, each switched on its own (the core keeps the flags, see
-- CombatKit.IsFeatureEnabled). This addon is loaded while at least one is on.
--
-- A feature registers { Start=, Stop=, secure= }. `secure` means it touches
-- protected frames, which is only allowed out of combat: switching such a
-- feature in combat waits for combat to end.
-- ===========================================================================

ns.features = {}
local waiting = {}   -- feature name -> wanted state, for secure features during combat

function ns.AddFeature(name, feature)
	ns.features[name] = feature
end

local function Apply(name, on)
	local feature = ns.features[name]
	if not feature then return end
	if feature.secure and InCombatLockdown() then
		if (feature.running or false) ~= on then
			waiting[name] = on
			CK.Msg(L[on and "MISC_WAIT_START" or "MISC_WAIT_STOP"], L["FEAT_" .. name])
		end
		return
	end
	waiting[name] = nil
	if on and not feature.running then
		feature.running = true
		feature.Start()
	elseif not on and feature.running then
		feature.running = false
		feature.Stop()
	end
end

-- "on" | "off" | "waiting" (secure feature, combat)
function ns.GetFeatureState(name)
	if waiting[name] ~= nil then return "waiting" end
	local feature = ns.features[name]
	return feature and feature.running and "on" or "off"
end

function ns.SetFeature(name, on)
	Apply(name, on)
end

local driver = CreateFrame("Frame")
driver:SetScript("OnEvent", function()
	for name, on in pairs(waiting) do Apply(name, on) end
	CK.RefreshOptions()
end)

function ns.OnEnable()
	if type(CombatKitMiscDB) ~= "table" then CombatKitMiscDB = {} end
	ns.db = CombatKitMiscDB
	driver:RegisterEvent("PLAYER_REGEN_ENABLED")
	for name in pairs(ns.features) do
		if CK.IsFeatureEnabled("Misc", name) then Apply(name, true) end
	end
end

function ns.OnDisable()
	for name in pairs(ns.features) do Apply(name, false) end
	-- a secure feature still waiting for combat to end keeps the event until then
	if next(waiting) == nil then driver:UnregisterAllEvents() end
end
