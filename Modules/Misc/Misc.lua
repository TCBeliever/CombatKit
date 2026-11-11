local ADDON, ns = ...
local CK = CombatKit

CK.NewModule("Misc", ns)

-- ===========================================================================
-- Small things, each switched on its own (the core keeps the flags, see
-- CombatKit.IsFeatureEnabled). This addon is loaded while at least one is on.
--
-- A feature registers { Start=, Stop= }. None touches protected frames, so
-- each one switches at once, in combat too.
-- ===========================================================================

ns.features = {}

function ns.AddFeature(name, feature)
	ns.features[name] = feature
end

local function Apply(name, on)
	local feature = ns.features[name]
	if not feature then return end
	if on and not feature.running then
		feature.running = true
		feature.Start()
	elseif not on and feature.running then
		feature.running = false
		feature.Stop()
	end
end

-- "on" | "off"
function ns.GetFeatureState(name)
	local feature = ns.features[name]
	return feature and feature.running and "on" or "off"
end

function ns.SetFeature(name, on)
	Apply(name, on)
end

function ns.OnEnable()
	if type(CombatKitMiscDB) ~= "table" then CombatKitMiscDB = {} end
	ns.db = CombatKitMiscDB
	for name in pairs(ns.features) do
		if CK.IsFeatureEnabled("Misc", name) then Apply(name, true) end
	end
end

function ns.OnDisable()
	for name in pairs(ns.features) do Apply(name, false) end
end
