-- The Reminder module for a rogue: poisons, two of each kind with Dragon-Tempered
-- Blades; a click casts one that is not on yet, those of last time first.

local T = dofile(HERE .. "/stubs.lua")
local check, eq, W, fire = T.check, T.eq, T.W, T.fire
T.captureChat()

local DEADLY, INSTANT, WOUND, CRIPPLING, ATROPHIC, BLADES = 2823, 315584, 8679, 3408, 381637, 381801
W.units.player = { class = "ROGUE" }
W.specs = { { 259, "Assassination" }, { 260, "Outlaw" }, { 261, "Subtlety" } }
W.known = { [DEADLY] = true, [INSTANT] = true, [CRIPPLING] = true, [ATROPHIC] = true, [BLADES] = true }
W.playerAuras = {}
W.inInstance, W.instanceType, W.difficultyID = true, "party", 2
local CK = T.boot()
CK.SetModuleEnabled("Reminder", true)
local RM = CK.modules.Reminder
local L = CK.L
RM.db.consumables = { flask = false, food = false, rune = false, oil = true, healthstone = false }
fire("PLAYER_ENTERING_WORLD")
local function find(label)
	local frame, icons, buttons = RM.GetDisplay()
	if not frame or not frame:IsShown() then return nil end
	for i, b in ipairs(icons) do
		if b:IsShown() and b.label:GetText() == label then
			return { text = b.text:GetText(), icon = b.icon:GetTexture(), button = buttons[i] }
		end
	end
end

local function cast(label) local r = find(label); return r and r.button and r.button:GetAttribute("spell") end
local LETHAL, NONLETHAL = L["Lethal poison"], L["Non-lethal poison"]

eq(cast(LETHAL), DEADLY, "no poison on: a click casts Deadly Poison")
eq(find(LETHAL).icon, "icon" .. DEADLY, "and shows it")
W.playerAuras[DEADLY] = { expirationTime = W.now + 3600 }
fire("UNIT_AURA", "player")
eq(cast(LETHAL), INSTANT, "Deadly on, two wanted: the click casts the other one, not Deadly again")
W.playerAuras[INSTANT] = { expirationTime = W.now + 3600 }
fire("UNIT_AURA", "player")
check(not find(LETHAL), "both on: fine")
eq(table.concat(RM.db.used["259/pve"].lethal, ","), DEADLY .. "," .. INSTANT, "the two are remembered for Assassination")

-- another pair next time: the remembered ones are offered first
W.known[WOUND] = true
W.playerAuras[DEADLY] = nil
W.playerAuras[WOUND] = { expirationTime = W.now + 3600 }
fire("UNIT_AURA", "player")
eq(table.concat(RM.db.used["259/pve"].lethal, ","), INSTANT .. "," .. WOUND, "Instant and Wound now")
W.playerAuras[INSTANT], W.playerAuras[WOUND] = nil, nil
fire("UNIT_AURA", "player")
eq(cast(LETHAL), INSTANT, "all off: the click casts Instant first, as last time, not Deadly")

eq(cast(NONLETHAL), ATROPHIC, "a non-lethal one too: the guides' Atrophic first")
local items = RM.ClassItems()
eq(items[2].guide, "spell" .. ATROPHIC .. " + spell" .. CRIPPLING, "the class page names the guides' two (Numbing is not known)")
eq(items[1].guides[260], "spell" .. INSTANT, "and each spec's: Outlaw's lethal poison is Instant")
eq(items[2].guides[261], "spell" .. ATROPHIC, "Subtlety's non-lethal: one, the talent node's Atrophic")

-- the page: the poisons under each spec, with that spec's pick; another spec's greyed
SlashCmdList.COMBATKIT("")
local main = CK.Options.GetFrame()
main.tabs.Reminder:Click()
for _, row in ipairs(main.treeRows) do
	if row:IsShown() and row.section == "Reminder" and row.node == "class" then row:Click() end
end
local page = main.bodies.Reminder.pages.class
check(page.heads[1]:IsShown() and page.heads[1].text:GetText() == "Assassination", "no 'all specs' head: every poison is per spec")
check(page.heads[3]:IsShown() and not page.heads[4]:IsShown(), "Assassination, Outlaw, Subtlety")
eq(page.items[3].key, "lethal", "Outlaw's lethal poison")
check(page.items[3].label:GetText():find("spell" .. INSTANT, 1, true), "with Outlaw's pick")
main:Hide()

-- an arena: nothing remembered for PvP, the guides' PvP poisons
W.instanceType = "arena"
W.playerAuras = {}
fire("PLAYER_ENTERING_WORLD")
eq(cast(LETHAL), WOUND, "an arena: Wound first")
eq(cast(NONLETHAL), CRIPPLING, "and Crippling")

T.releaseChat()
return T.report("reminder rogue [" .. (LOCALE or "enUS") .. "]")
