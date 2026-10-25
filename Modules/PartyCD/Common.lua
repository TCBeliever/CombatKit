local ADDON, ns = ...

-- ===========================================================================
-- The few small things every part of the module shares.
-- ===========================================================================

-- the team, in row order: the player (the reference row), then the teammates
ns.TEAM = { "player", "party1", "party2" }

-- whether addon code may read a value (in an arena most of a teammate's are secret)
function ns.plain(v) return type(canaccessvalue) ~= "function" or canaccessvalue(v) end

-- inside an arena instance (the match itself or its waiting room)
function ns.InArenaZone()
	local inInstance, kind = IsInInstance()
	return inInstance and kind == "arena"
end

-- the match state of a round in progress (C_PvP.GetActiveMatchState)
ns.ENGAGED = (Enum and Enum.PvPMatchState and Enum.PvPMatchState.Engaged) or 3
