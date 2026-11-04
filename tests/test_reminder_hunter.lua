-- The Reminder module for a Beast Mastery hunter: the pet named by its slot ("Pet 2"), the
-- one called last, and the stable's pets by name in the chooser.

local T = dofile(HERE .. "/stubs.lua")
local check, eq, W, fire = T.check, T.eq, T.W, T.fire
T.captureChat()

local CALL1, CALL2, CALL3 = 883, 83242, 83243
C_StableInfo = { GetStablePetInfo = function(slot)
	local pets = { { icon = 1001, name = "Wolf" }, { icon = 1002, name = "Bear" }, { icon = 1003, name = "Owl" } }
	return pets[slot]
end }

W.units.player = { class = "HUNTER" }
W.specs = { { 253, "Beast Mastery" }, { 254, "Marksmanship" }, { 255, "Survival" } }
W.specIndex = 1
W.known = { [CALL1] = true, [CALL2] = true, [CALL3] = true }
local CK = T.boot()
CK.SetModuleEnabled("Reminder", true)
local RM = CK.modules.Reminder
local L = CK.L
RM.db.consumables = { flask = false, food = false, rune = false, oil = false, healthstone = false }
fire("PLAYER_ENTERING_WORLD")

local function pet()
	local frame, icons, buttons = RM.GetDisplay()
	if not frame or not frame:IsShown() then return nil end
	for i, b in ipairs(icons) do
		if b:IsShown() then return b, buttons[i] end
	end
end

local icon, button = pet()
eq(icon and icon.label:GetText(), string.format(L["Pet %d"], 1), "no pet: named by the slot, short of Call Pet 1")
eq(icon and icon.icon:GetTexture(), 1001, "with the pet's own icon from the stable")
eq(button and button:GetAttribute("spell"), CALL1, "a click calls it")
fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", CALL2)
T.flush()
icon, button = pet()
eq(icon and icon.label:GetText(), string.format(L["Pet %d"], 2), "the second pet called: the one from now on")
eq(button and button:GetAttribute("spell"), CALL2, "and the one a click calls")
local names = {}
for _, opt in ipairs(button.reminder.options) do names[#names + 1] = opt.name end
eq(table.concat(names, ","), "Wolf,Owl", "the chooser: the other pets by their names")
local item = RM.ClassItems()[1]
eq(item.title, string.format(L["Summon pet (%s)"], "Bear"), "on the settings page: Summon pet (its name)")

-- the class page: one group (the pet), so no heading over it
SlashCmdList.COMBATKIT("")
local main = CK.Options.GetFrame()
main.tabs.Reminder:Click()
for _, row in ipairs(main.treeRows) do
	if row:IsShown() and row.section == "Reminder" and row.node == "class" then row:Click() end
end
local page = main.bodies.Reminder.pages.class
check(not page.heads[1]:IsShown(), "one group on the page: no heading")
eq(page.items[1].key, "pet", "the pet")
check(page.petBlock and page.petBlock:IsShown(), "and the warning under it")
eq(page.petOn.icon:GetTexture(), "icon136", "with Mend Pet's icon")
main:Hide()
W.units.pet = { guid = "Pet-0-3299-0-12-1000-0000ABCDEF" }
fire("UNIT_PET", "player")
T.flush()
check(not pet(), "a pet out: fine")

T.releaseChat()
return T.report("reminder hunter [" .. (LOCALE or "enUS") .. "]")
