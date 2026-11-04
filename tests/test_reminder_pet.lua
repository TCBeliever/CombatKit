-- The Reminder module's pets: the demon you summoned last, the chooser that Alt opens over
-- an icon, the tooltips, the settings page's name, and the pet's health.

local T = dofile(HERE .. "/stubs.lua")
local check, eq, W, fire = T.check, T.eq, T.W, T.fire
T.captureChat()

local FELGUARD, FELHUNTER, VOIDWALKER, IMP = 30146, 691, 697, 688

-- the pet's health through a colour curve, as the game does it: W.petHealth is 0 to 1, or T.SECRET
-- for a health the game keeps to itself (then the alpha is secret too)
Enum.LuaCurveType = { Linear = 0, Step = 1 }
function CreateColor(r, g, b, a) return { r = r, g = g, b = b, a = a } end
C_CurveUtil = { CreateColorCurve = function()
	local c = { points = {} }
	function c:SetType(t) self.type = t end
	function c:AddPoint(x, y) self.points[#self.points + 1] = { x = x, y = y } end
	return c
end }
function UnitHealthPercent(unit, _, curve)
	local pct = W.petHealth
	if pct == T.SECRET then return { GetRGBA = function() return 1, 1, 1, T.SECRET end } end
	local y = curve.points[1].y
	for _, p in ipairs(curve.points) do if pct >= p.x then y = p.y end end
	return { GetRGBA = function() return y.r, y.g, y.b, y.a end }
end

-- what the tooltip was given
local tip = {}
function GameTooltip:SetSpellByID(id) tip = { "spell" .. id } end
function GameTooltip:SetText(text) tip = { text } end
function GameTooltip:AddLine(text) tip[#tip + 1] = text end
local function has(text)
	for _, line in ipairs(tip) do if line == text then return true end end
	return false
end
local owner
function GameTooltip:SetOwner(o) owner, tip = o, {} end
function GameTooltip:IsOwned(o) return owner == o end
function GameTooltip:Hide() owner, tip = nil, {} end
function GameTooltip_Hide() GameTooltip:Hide() end

-- the Imp by the game's own name, to see the icon named for the demon, short of the spell
local spellName = C_Spell.GetSpellName
C_Spell.GetSpellName = function(id) if id == IMP then return "Summon Imp" end return spellName(id) end

W.units.player = { class = "WARLOCK" }
W.specs = { { 265, "Affliction" }, { 266, "Demonology" }, { 267, "Destruction" } }
W.specIndex = 1
W.known = { [FELHUNTER] = true, [VOIDWALKER] = true, [IMP] = true }
local CK = T.boot()
CK.SetModuleEnabled("Reminder", true)
local RM = CK.modules.Reminder
local L = CK.L
RM.db.consumables = { flask = false, food = false, rune = false, oil = false, healthstone = false }
for _, key in ipairs({ "soulstone", "createstone", "sacrifice" }) do RM.db.off[key] = true end
fire("PLAYER_ENTERING_WORLD")

local function demon()
	local frame, icons, buttons = RM.GetDisplay()
	if not frame or not frame:IsShown() then return nil end
	for i, b in ipairs(icons) do
		local r = buttons[i] and buttons[i].reminder
		if b:IsShown() and r and r.key == "demon" then return b, buttons[i] end
	end
end

-- ---------------------------------------------------------------- the demon you summoned last
local icon, button = demon()
check(icon, "no demon out: the demon reminder")
eq(icon and icon.label:GetText(), "spell" .. FELHUNTER, "named for the demon it summons")
eq(button and button:GetAttribute("spell"), FELHUNTER, "nothing summoned yet: the first demon known")
fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", IMP)
T.flush()
icon, button = demon()
eq(button and button:GetAttribute("spell"), IMP, "the Imp summoned: a click summons the Imp from now on")
eq(icon and icon.icon:GetTexture(), "icon" .. IMP, "and the icon is the Imp's")
eq(icon and icon.label:GetText(), "Imp", "named Imp, short of Summon Imp")
eq(RM.db.used["265/pve"].demon[1], IMP, "remembered for Affliction in PvE")
fire("UNIT_SPELLCAST_SUCCEEDED", "party1", "Cast-2", VOIDWALKER)
fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-3", T.SECRET)
T.flush()
eq(RM.db.used["265/pve"].demon[1], IMP, "someone else's cast, or a secret one, changes nothing")

-- on a mount the demon may be away until you get off (after a flight): no reminder till then
W.mounted = true
fire("PLAYER_MOUNT_DISPLAY_CHANGED")
T.flush()
check(not demon(), "mounted: no demon reminder")
W.mounted = false
fire("PLAYER_MOUNT_DISPLAY_CHANGED")
T.flush()
icon, button = demon()
check(icon, "off the mount and still no demon: back")

-- ---------------------------------------------------------------- the tooltip
button:GetScript("OnEnter")(button)
eq(tip[1], "spell" .. IMP, "the tooltip: the game's own for the spell")
check(has(L["TIP_CAST"]) and has(L["TIP_CHOOSE"]), "then what a click does, and that Alt picks another")
button:GetScript("OnLeave")(button)

-- ---------------------------------------------------------------- the chooser
local _, _, _, choices = RM.GetDisplay()
local function open()
	local list = {}
	for _, b in ipairs(choices) do if b:IsShown() then list[#list + 1] = b:GetAttribute("spell") end end
	table.sort(list)
	return table.concat(list, ",")
end
check(open() == "", "no modifier held: no chooser")
W.shift = true
button:GetScript("OnEnter")(button)
check(open() == "", "Shift: no chooser either")
check(tip[1] == "spell" .. IMP, "the icon's tooltip up")
W.shift = false
W.alt = true
fire("MODIFIER_STATE_CHANGED", "LALT", 1)
eq(open(), FELHUNTER .. "," .. VOIDWALKER, "Alt over the icon: the other demons known, not the one it casts")
check(#tip == 0, "and the icon's tooltip gone, off the row")
local felhunter
for _, b in ipairs(choices) do if b:IsShown() and b:GetAttribute("spell") == FELHUNTER then felhunter = b end end
felhunter:GetScript("OnEnter")(felhunter)
check(tip[1] == "spell" .. FELHUNTER and has(L["TIP_PICK"]), "a choice's tooltip: its spell, and that the icon casts it from now on")
felhunter:GetScript("PostClick")(felhunter, "LeftButton", true)
eq(open(), FELHUNTER .. "," .. VOIDWALKER, "still open while the button is down")
felhunter:GetScript("PostClick")(felhunter, "LeftButton", false)
eq(open(), "", "gone once the click is over")
fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-4", FELHUNTER)
T.flush()
icon, button = demon()
eq(button and button:GetAttribute("spell"), FELHUNTER, "the demon picked is the one the icon summons next")
button:GetScript("OnLeave")(button)
button:GetScript("OnEnter")(button)
eq(open(), IMP .. "," .. VOIDWALKER, "open again: the others than the Felhunter now")
check(#tip == 0, "and no tooltip over it")
W.alt = false
fire("PLAYER_REGEN_DISABLED")
eq(open(), "", "combat: the chooser goes with the icons")
fire("PLAYER_REGEN_ENABLED")
T.flush()
eq(open(), "", "and does not come back by itself")

-- ---------------------------------------------------------------- the settings page's name
local item
for _, it in ipairs(RM.ClassItems()) do if it.key == "demon" then item = it end end
eq(item and item.label, "spell" .. FELHUNTER, "on the icon: the demon's name")
eq(item and item.title, string.format(L["Summon demon (%s)"], "spell" .. FELHUNTER), "on the settings page: Summon demon (the one)")

-- the class page: the demon by the page's name, and the pet's block under every spec's reminders
SlashCmdList.COMBATKIT("")
local main = CK.Options.GetFrame()
main.tabs.Reminder:Click()
for _, row in ipairs(main.treeRows) do
	if row:IsShown() and row.section == "Reminder" and row.node == "class" then row:Click() end
end
local page = main.bodies.Reminder.pages.class
check(page:IsShown() and page.petBlock and page.petBlock:IsShown(), "the class page has the pet's block")
local named
for _, c in ipairs(page.items) do
	if c:IsShown() and c.key == "demon" then named = c.label:GetText() end
end
eq(named, string.format(L["Summon demon (%s)"], "spell" .. FELHUNTER), "the demon under the page's name")
check(page.petOn:GetChecked() and page.petIcon:GetChecked() and page.petBelow.current == 40 and page.petFont.current == 20,
	"the block shows the settings")
page.petIcon:Click()
check(not RM.db.petHealth.icon, "the icon switched off from the page")
page.petIcon:Click()
eq(page.heads[1].text:GetText(), L["Pet"], "the pet's section first")
eq(page.heads[2].text:GetText(), L["All specs"], "then every spec's")
check(not page.heads[3]:IsShown(), "and no spec of its own: Grimoire of Sacrifice is with the demon")
eq(page.items[1].key, "demon", "the demon first")
eq(page.items[2].key, "sacrifice", "then Grimoire of Sacrifice")
eq(page.items[2].guide:GetText(), string.format(L["SPECS_ONLY"], "Affliction" .. L["LIST_SEP"] .. "Destruction"),
	"for Affliction and Destruction, under its name")
eq(page.petOn.label:GetText(), L["Pet health low"], "the warning, named as on screen")
eq(page.petOn.icon:GetTexture(), "icon755", "with Health Funnel's icon")
page.petOn:Click()
check(not RM.db.petHealth.on and page.petDep:GetAlpha() == 0.55, "switched off from the page: its settings greyed")
page.petOn:Click()
check(RM.db.petHealth.on and page.petDep:GetAlpha() == 1, "and back")
main:Hide()

-- ---------------------------------------------------------------- Demonology: the Felguard first
W.known[FELGUARD] = true
W.specIndex = 2
fire("PLAYER_SPECIALIZATION_CHANGED", "player")
T.flush()
icon, button = demon()
eq(button and button:GetAttribute("spell"), FELGUARD, "Demonology in PvE with Summon Felguard: the Felguard")
fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-5", IMP)
T.flush()
icon, button = demon()
eq(button and button:GetAttribute("spell"), FELGUARD, "whichever demon was summoned last")
W.specIndex = 1
fire("PLAYER_SPECIALIZATION_CHANGED", "player")
T.flush()

-- ---------------------------------------------------------------- the pet's health
W.units.pet = { guid = "Pet-0-3299-0-12-417-0000ABCDEF" }   -- a Felhunter
W.petHealth = 0.8
fire("UNIT_PET", "player")
T.flush()
local hp = RM.GetPetHealth()
check(hp and not hp:IsShown(), "a pet at 80%: no warning")
W.petHealth = 0.3
fire("UNIT_HEALTH", "pet")
check(hp:IsShown() and hp:GetAlpha() == 1, "below 40%: the warning, opaque")
eq(hp.label:GetText(), L["Pet health low"], "named")
eq(hp.icon:GetTexture(), "icon755", "with Health Funnel's icon")
eq(select(2, hp.label:GetFont()), 20, "the text as large as the font size")
check(hp.icon:IsShown(), "the icon on its left")
RM.db.petHealth.icon = false
RM.db.petHealth.fontSize = 30
RM.PetHealthApply()
check(hp:IsShown() and not hp.icon:IsShown() and select(2, hp.label:GetFont()) == 30, "the text alone, larger")
RM.db.petHealth.icon, RM.db.petHealth.fontSize = true, 20
RM.PetHealthApply()
W.petHealth = 0.4
fire("UNIT_HEALTH", "pet")
check(not hp:IsShown(), "at the threshold: gone")
W.petHealth = T.SECRET
fire("UNIT_HEALTH", "pet")
check(hp:IsShown() and hp:GetAlpha() == T.SECRET, "a secret health: up, with the game's own alpha")
fire("PLAYER_REGEN_DISABLED")
W.petHealth = 0.2
fire("UNIT_HEALTH", "pet")
check(hp:IsShown() and hp:GetAlpha() == 1, "in combat too")
fire("PLAYER_REGEN_ENABLED")
RM.db.petHealth.below = 10
RM.PetHealthApply()
check(not hp:IsShown(), "a lower threshold: 20% is fine")
RM.db.petHealth.below = 40
RM.db.petHealth.on = false
RM.PetHealthApply()
check(not hp:IsShown(), "switched off: nothing")
RM.db.petHealth.on = true
W.units.pet.dead = true
fire("UNIT_HEALTH", "pet")
check(not hp:IsShown(), "a dead pet: the pet reminder's business")
W.units.pet = nil
RM.SetLocked(false)
check(hp:IsShown() and hp:GetAlpha() == 1, "unlocked: a sample to drag, pet or no pet")
RM.SetLocked(true)
check(not hp:IsShown(), "locked again: gone")
W.known[108503] = true   -- Grimoire of Sacrifice: no demon wanted
W.units.pet = { guid = "Pet-0-3299-0-12-417-0000ABCDEF" }
W.petHealth = 0.1
fire("SPELLS_CHANGED")
check(not hp:IsShown(), "with Grimoire of Sacrifice: no warning")

T.releaseChat()
return T.report("reminder pet [" .. (LOCALE or "enUS") .. "]")
