local ADDON, ns = ...
local CK = CombatKit

-- This addon's private table is the module: the core and the settings pages
-- reach it as CombatKit.modules.Loadout.
CK.NewModule("Loadout", ns)

ns.L    = CK.L
ns.Skin = CK.Skin
ns.Msg  = CK.Msg

-- Settings page "Debug messages in chat"
function ns.Debug(fmt, ...)
	if ns.debug.verbose then print("|cff66ccffCombat|rKit: |cff808080" .. string.format(fmt, ...) .. "|r") end
end

function ns.UpdateHUD() CK.HUD.Refresh() end
function ns.RefreshOptions() CK.RefreshOptions() end
