local ADDON, ns = ...
local CK = CombatKit

-- This addon's private table is the module: the core and the settings pages
-- reach it as CombatKit.modules.Loadout.
CK.NewModule("Loadout", ns)

ns.L    = CK.L
ns.Skin = CK.Skin
ns.Msg  = CK.Msg

-- Settings page "Debug messages in chat"; also a line of the apply log while an apply is logged
function ns.Debug(fmt, ...)
	local logging = ns.ApplyLogOpen and ns.ApplyLogOpen()
	if not ns.debug.verbose and not logging then return end
	local text = string.format(fmt, ...)
	if logging then ns.LogLine("%s", text) end
	if ns.debug.verbose then print("|cff66ccffCombat|rKit: |cff808080" .. text .. "|r") end
end

function ns.UpdateHUD() CK.HUD.Refresh() end
function ns.RefreshOptions() CK.RefreshOptions() end
