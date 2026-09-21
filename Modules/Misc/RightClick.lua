local ADDON, ns = ...

-- ===========================================================================
-- In combat, right-clicking a unit under the cursor turns the camera instead
-- of targeting it.
--
-- A secure state driver watches "[combat,@mouseover,exists]". While that holds,
-- the right mouse button is bound to a button that starts and stops mouselook,
-- which is what a right click on empty ground does anyway. Outside combat, or
-- with nothing under the cursor, the binding is gone and right click is normal.
--
-- Only the right button is touched. "Unit" includes corpses, on purpose: a pull
-- leaves them all over the floor. Left click (the game's "interact on left
-- click") and the interact key still reach them. Ore, herbs, chests and doors
-- are objects, not units, and are never affected.
-- ===========================================================================

local BUTTON = "CombatKitMouselookButton"
local button, state

local function Create()
	button = CreateFrame("Button", BUTTON)
	button:RegisterForClicks("AnyDown", "AnyUp")
	button:SetScript("OnClick", function(_, _, down)
		if down then MouselookStart() else MouselookStop() end
	end)

	-- without this the driver does not notice the mouseover changing
	SecureStateDriverManager:RegisterEvent("UPDATE_MOUSEOVER_UNIT")

	state = CreateFrame("Frame", "CombatKitRightClickState", nil, "SecureHandlerStateTemplate")
	state:SetAttribute("_onstate-mov", [[
		if newstate == 1 then
			self:SetBindingClick(1, "BUTTON2", "]] .. BUTTON .. [[")
		else
			self:ClearBindings()
		end
	]])
end

ns.AddFeature("RightClick", {
	secure = true,   -- protected frames: started and stopped out of combat only
	Start = function()
		if not state then Create() end
		RegisterStateDriver(state, "mov", "[combat,@mouseover,exists]1;0")
	end,
	Stop = function()
		UnregisterStateDriver(state, "mov")
		ClearOverrideBindings(state)
	end,
})
