local ADDON, ns = ...

-- ===========================================================================
-- In combat, a right click on a unit no longer targets or interacts with it.
-- Holding the button still turns the camera, and holding both buttons still
-- runs forward.
--
-- The right button keeps the game's own binding ("turn or action"). Replacing
-- it with an override binding, as this feature first did, also takes away
-- running with both buttons: the game only runs while both of its own mouse
-- bindings are held. Instead, when the right button comes up over the world in
-- combat with a unit under the cursor, mouselook is stopped first, and the game
-- no longer takes the release for a click on that unit (the technique Right
-- Click Modifier uses).
--
-- No protected frame is touched, so it switches on and off in combat too.
-- "Unit" includes corpses, on purpose: a pull leaves them all over the floor.
-- Left click (the game's "interact on left click") and the interact key still
-- reach them. Ore, herbs, chests and doors are objects, not units, and are
-- never affected.
-- ===========================================================================

local on, hooked = false, false

local function OnMouseUp(_, button)
	if on and button == "RightButton" and InCombatLockdown() and UnitExists("mouseover") then
		MouselookStop()
	end
end

ns.AddFeature("RightClick", {
	Start = function()
		on = true
		-- a hook cannot be taken back: it stays, idle while the feature is off
		if not hooked then
			WorldFrame:HookScript("OnMouseUp", OnMouseUp)
			hooked = true
		end
	end,
	Stop = function()
		on = false
	end,
})
