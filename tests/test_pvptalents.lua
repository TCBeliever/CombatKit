-- PvP talents in a PvP setup: three slots per cell, applied after the talent
-- loadout, counted on the HUD, and the settings page row between talents and gear.

local T = dofile(HERE .. "/stubs.lua")
local check, eq, W, fire, flush = T.check, T.eq, T.W, T.fire, T.flush
T.captureChat()

local HAVOC, VENG = 577, 581
local GLIMPSE, COVER, RAIN, REVERSE, DETAIN, SIGIL = 1001, 1002, 1003, 1004, 1005, 1006
local ALL = { GLIMPSE, COVER, RAIN, REVERSE, DETAIN, SIGIL }
W.pvpTalentInfo = {}
for i, name in ipairs({ "Glimpse", "Cover of Darkness", "Rain from Above", "Reverse Magic", "Detainment", "Sigil Mastery" }) do
	W.pvpTalentInfo[ALL[i]] = { name = name, icon = 2000 + i }
end
local function slots(a, b, c)
	W.pvpSlots = { { selected = a, list = ALL }, { selected = b, list = ALL }, { selected = c, list = ALL } }
end
slots(GLIMPSE, COVER, RAIN)

W.specIndex = 1; W.activeConfig[HAVOC] = 101
for k, s in pairs(W.sets) do s[2] = (k == 1) end
CombatKitLoadoutDB = { settings = { auto = true } }
local CK = T.boot()
fire("PLAYER_ENTERING_WORLD")
local LO = CK.modules.Loadout
local C, L = LO.char, CK.L
local function pass(seconds) W.now = W.now + seconds; flush() end
local function hudLine(label)
	for _, r in ipairs(CK.HUD.GetFrame().sections.loadout.rows) do
		local text = r.label:IsShown() and r.label:GetText() or ""
		if text:find(label, 1, true) then return r.value:GetText() or "" end
	end
end


-- ---------------------------------------------------------------- what it takes
local plan, have, want, missing = LO.PvpPlan({ GLIMPSE, COVER, RAIN })
check(#plan == 0 and have == 3 and want == 3 and missing == 0, "all three on: nothing to do")
plan, have = LO.PvpPlan({ COVER, RAIN, GLIMPSE })
check(#plan == 0 and have == 3, "the slot a talent sits in does not matter")
plan, have, want = LO.PvpPlan({ GLIMPSE, REVERSE, nil })
check(#plan == 1 and plan[1].id == REVERSE and plan[1].slot == 2 and have == 1 and want == 2, "one not on goes to its own slot")
plan = LO.PvpPlan({ REVERSE, GLIMPSE, nil })
check(#plan == 1 and plan[1].slot == 2, "its own slot holds a wanted talent: the first free slot instead")
plan = LO.PvpPlan({ REVERSE, DETAIN, SIGIL })
check(#plan == 3 and plan[1].slot == 1 and plan[2].slot == 2 and plan[3].slot == 3, "three new ones, each to its own slot")
W.pvpSlots[3].locked = true
plan, _, _, missing = LO.PvpPlan({ REVERSE, DETAIN, SIGIL })
check(#plan == 2 and missing == 1, "a locked slot: the third has nowhere to go")
W.pvpSlots[3].locked = nil
plan, _, _, missing = LO.PvpPlan({ 9999 })
check(#plan == 0 and missing == 1, "a talent this spec does not have: missing")
check(not LO.HasPvp({}) and not LO.HasPvp(nil) and LO.HasPvp({ nil, nil, RAIN }), "an empty slot is no PvP talent")

-- ---------------------------------------------------------------- arena: the loadout, then the PvP talents
C.groups.pvp.specs[HAVOC] = { configID = 102, configName = "Raid ST", pvp = { REVERSE, DETAIN, RAIN } }
W.log = {}
W.inInstance, W.instanceType = true, "arena"
fire("ZONE_CHANGED_NEW_AREA")
eq(W.log[1], "talents:102", "arena: the PvP loadout first")
eq(W.log[2], "pvp:" .. REVERSE .. "@1", "then the PvP talents that are not on")
eq(W.log[3], "pvp:" .. DETAIN .. "@2", "each to its own slot")
eq(#W.log, 3, "Rain from Above was on already")
fire("PLAYER_PVP_TALENT_UPDATE")
check(not LO.IsApplying(), "done")
eq(LO.GetStatus("arena").state, "ready", "ready")
local line = hudLine(L["PvP talents"])
check(line and line:find("3/3", 1, true), "the HUD counts them: 3/3")

-- changed by hand: shown, never changed back by itself
W.log = {}
W.pvpSlots[1].selected = GLIMPSE
fire("PLAYER_PVP_TALENT_UPDATE")
eq(LO.GetStatus("arena").state, "mismatch", "a PvP talent changed by hand: not ready")
line = hudLine(L["PvP talents"])
check(line and line:find("2/3", 1, true), "the HUD says 2/3")
eq(#W.log, 0, "and nothing is changed back")
LO.ApplyNow(); flush()
eq(W.log[1], "pvp:" .. REVERSE .. "@1", "a click on the HUD puts it back")
fire("PLAYER_PVP_TALENT_UPDATE")
eq(LO.GetStatus("arena").state, "ready", "ready again")

-- one the spec does not have: missing, and the apply does not loop on it
C.groups.pvp.specs[HAVOC].pvp = { REVERSE, DETAIN, 9999 }
local st = LO.GetStatus("arena")
check(st.state == "mismatch" and st.pvpMissing, "a talent that cannot be placed: missing")
line = hudLine(L["PvP talents"]) or ""
W.log = {}
LO.ApplyNow(); flush()
check(not LO.IsApplying() and #W.log == 0, "nothing can be placed: the apply ends at once")
check((hudLine(L["PvP talents"]) or ""):find(L["missing"], 1, true), "the HUD says it is missing")
C.groups.pvp.specs[HAVOC].pvp = { REVERSE, DETAIN, SIGIL }

-- a client that ignores the request: asked a few times, then it says so
W.pvpRefused = true
W.log = {}
LO.ApplyNow(); flush()
for _ = 1, 6 do pass(1.1) end
check(not LO.IsApplying(), "gives up")
eq(#W.log, 4, "after four tries")
check(T.said(L["Could not set the PvP talents: %s"]:format(L["unknown reason"])), "and says so")
W.pvpRefused = nil

-- dry run names them
LO.debug.dryRun = true
LO.ApplyNow(); flush()
check(T.said("Sigil Mastery"), "the dry run names the PvP talents")
LO.debug.dryRun = nil
LO.ApplyNow(); flush()
fire("PLAYER_PVP_TALENT_UPDATE")
eq(LO.GetStatus("arena").state, "ready", "applied for real")

-- ---------------------------------------------------------------- settings page
SlashCmdList.COMBATKIT("")
local O = CK.Options
local main = O.GetFrame()
local function treeRow(section, node)
	for _, r in ipairs(main.treeRows) do
		if r:IsShown() and r.section == section and r.node == node then return r end
	end
end
local function pick(dropdown, value)
	dropdown:Click()
	local list = T.frames.CombatKitOptionList
	if not (list and list:IsShown()) then return false end
	for _, b in ipairs(list.buttons) do
		if b:IsShown() and b.item.value == value then b:Click(); return true end
	end
	list:Hide()
	return false
end
local function offered(dropdown, value)
	dropdown:Click()
	local list = T.frames.CombatKitOptionList
	local found = false
	for _, b in ipairs(list.buttons) do
		if b:IsShown() and b.item.value == value then found = true end
	end
	list:Hide()
	return found
end
local p = main.bodies.Loadout.pages.loadout
local function specButton(specID)
	for _, b in ipairs(p.specButtons) do if b:IsShown() and b.specID == specID then return b end end
end

W.log = {}
treeRow("Loadout", "group:pve"):Click()
check(not p.pvpLabel:IsShown() and not p.pvpSlots[1]:IsShown() and not p.pvpCapture:IsShown(), "PvE: no PvP talent row")
local gearY = p.gear.__point[3]
treeRow("Loadout", "group:pvp"):Click()
specButton(HAVOC):Click()
check(p.pvpLabel:IsShown() and p.pvpSlots[3]:IsShown() and p.pvpCapture:IsShown(), "PvP: three slots and the button")
check(not p.pvpSlots[1].disabled and not p.pvpSlots[1].icon:IsDesaturated() and not p.pvpCapture.disabled, "the current spec: in colour, editable")
eq(treeRow("Loadout", "group:pvp").text:GetText(), "PvP", "the tab is named PvP")
local slotH = select(2, CK.Skin.TalentSlotSize(26))
local pvpH = slotH + 32   -- the icons, then "Use current" under them
eq(p.gear.__point[3], gearY - 28 - pvpH, "the gear set moves down under 'Multiple setups' and the PvP talents")
check(p.warmode:IsShown() and p.warmode.__point[3] == gearY - 28 - pvpH - 68, "and so does the War Mode option")
local slotY = p.pvpSlots[1].__point[3]
check(p.pvpLabel.__point[1] == "LEFT" and p.pvpLabel.__point[5] == slotY - slotH / 2, "the PvP label on the icons' middle line")
check(p.pvpCapture.__point[2] == p.pvpSlots[1].__point[2] and p.pvpCapture.__point[3] == slotY - slotH - 4, "'Use current' on its own line, under the icons")
eq(p.pvpSlots[1].icon:GetTexture(), 2004, "the slots show the cell's talents as icons")
eq(p.pvpSlots[1].border.__atlas, "talents-node-pvp-filled", "in the game's own octagonal frame")
check(p.pvpSlots[1].mask and p.pvpSlots[1].mask.__atlas == "talents-node-choice-mask", "the icon cut to the game's octagon")

check(not offered(p.pvpSlots[3], REVERSE) and not offered(p.pvpSlots[3], DETAIN), "a talent picked in another slot is not offered")
check(offered(p.pvpSlots[3], COVER) and offered(p.pvpSlots[3], SIGIL), "the rest are, its own included")
check(pick(p.pvpSlots[3], COVER), "slot 3: Cover of Darkness")
eq(C.groups.pvp.specs[HAVOC].pvp[3], COVER, "saved")
check(pick(p.pvpSlots[1], nil), "slot 1: not set")
eq(C.groups.pvp.specs[HAVOC].pvp[1], nil, "cleared")
check(p.pvpSlots[1].icon.__atlas == "pvptalents-talentborder-empty" and p.pvpSlots[1].border.__atlas == "talents-node-pvp-green",
	"an empty slot looks like the game's empty slot")

slots(GLIMPSE, COVER, RAIN)
p.pvpCapture:Click()
local pvp = C.groups.pvp.specs[HAVOC].pvp
check(pvp[1] == GLIMPSE and pvp[2] == COVER and pvp[3] == RAIN, "'Use current': the three that are on, slot by slot")
W.pvpSlots[3].selected = nil
p.pvpCapture:Click()
pvp = C.groups.pvp.specs[HAVOC].pvp
check(pvp[2] == COVER and pvp[3] == nil, "an empty slot stays empty")
eq(#W.log, 0, "editing never applies anything")

specButton(VENG):Click()
check(p.pvpSlots[1].disabled and p.pvpSlots[1].icon:IsDesaturated() and p.pvpCapture:IsShown() and p.pvpCapture.disabled,
	"another spec: the game lists only the current spec's talents, so its slots and the button are grey")
eq(p.pvpSlots[1].border.__atlas, "talents-node-pvp-inspect-empty", "in the frame the game uses for talents you cannot change")
specButton(HAVOC):Click()
check(not p.pvpSlots[1].disabled and not p.pvpSlots[1].icon:IsDesaturated(), "the current spec: in colour again")

-- a cell may hold PvP talents alone
local keep = C.groups.pvp.specs[HAVOC]
C.groups.pvp.specs[HAVOC] = nil; O.Refresh()
check(pick(p.pvpSlots[2], RAIN), "PvP talents alone")
check(C.groups.pvp.specs[HAVOC] and C.groups.pvp.specs[HAVOC].pvp[2] == RAIN and specButton(HAVOC).dot:IsShown(), "make a cell")
check(pick(p.pvpSlots[2], nil), "cleared again")
eq(C.groups.pvp.specs[HAVOC], nil, "an empty cell is removed")
C.groups.pvp.specs[HAVOC] = keep; O.Refresh()

-- split: arena reads the group's, read-only, and its own starts as a copy
p.split:Click()
treeRow("Loadout", "scenario:arena"):Click()
check(p.pvpSlots[2]:IsShown() and p.pvpSlots[2].disabled, "arena using the PvP settings: shown, read-only")
eq(p.pvpSlots[2].icon:GetTexture(), 2002, "the group's talents")
p.follow:Click()
local own = C.scenarios.arena.specs[HAVOC]
check(own and own.pvp and own.pvp ~= keep.pvp and own.pvp[2] == COVER, "its own settings start as a copy, PvP talents included")
check(pick(p.pvpSlots[2], SIGIL), "and change on their own")
eq(keep.pvp[2], COVER, "the group's are untouched")
p.follow:Click()
treeRow("Loadout", "group:pvp"):Click()
p.split:Click()

-- "Multiple setups": up to three setups, the one picked is shown and used
treeRow("Loadout", "group:pve"):Click()
check(not p.multi:IsShown(), "PvE: no multiple setups")
treeRow("Loadout", "group:pvp"):Click()
check(p.multi:IsShown() and not p.multi:GetChecked() and not p.setButtons[1]:IsShown(), "PvP: the option, off, no setup buttons")
p.multi:Click()
local cell = C.groups.pvp.specs[HAVOC]
check(cell.multi and p.setButtons[3]:IsShown() and p.setButtons[1].selected, "on: three buttons, the first in use")
eq(p.talents.text:GetText(), "Raid ST", "the first setup is the one there was")
p.setButtons[2]:Click()
check(cell.active == 2 and p.setButtons[2].selected and not p.setButtons[1].selected, "the second picked")
eq(p.talents.text:GetText(), L["Not set"], "it starts empty")
eq(LO.GetStatus("arena").state, "none", "an empty setup in use: nothing set up")
check(pick(p.talents, 101), "the second setup: its own loadout")
check(pick(p.pvpSlots[1], SIGIL), "and its own PvP talents")
check(cell.alt[2].configID == 101 and cell.alt[2].pvp[1] == SIGIL and cell.configID == 102, "kept apart from the first")
st = LO.GetStatus("arena")
check(st.cell == cell.alt[2] and st.setIndex == 2, "the arena uses the second")
W.log = {}
LO.ApplyNow(); flush()
eq(W.log[1], "talents:101", "and the HUD click applies it")
eq(W.log[2], "pvp:" .. SIGIL .. "@1", "PvP talents included")
fire("PLAYER_PVP_TALENT_UPDATE")
p.setButtons[1]:Click()
check(LO.GetStatus("arena").cell == cell and p.talents.text:GetText() == "Raid ST", "back on the first")
p.setButtons[3]:Click()
check(pick(p.talents, 101) and pick(p.talents, nil), "the third: a loadout, cleared again")
eq(cell.alt[3], nil, "an empty setup is not kept")
p.multi:Click()
check(not cell.multi and cell.active == nil and not p.setButtons[1]:IsShown(), "off: no buttons")
check(cell.alt[2] and cell.alt[2].configID == 101, "the other setups are kept")
eq(LO.GetStatus("arena").cell, cell, "and the first is used")
p.multi:Click()
check(cell.multi and p.setButtons[1].selected, "on again: from the first")

p.split:Click()
treeRow("Loadout", "scenario:arena"):Click()
check(p.multi:GetChecked() and p.multi.disabled and p.setButtons[2].disabled, "arena on the PvP settings: shown, read-only")
C.scenarios.arena.specs = {}   -- the copy made above is gone: the next one is made afresh
p.follow:Click()
local mine = C.scenarios.arena.specs[HAVOC]
check(mine.multi and mine.alt and mine.alt[2] ~= cell.alt[2] and mine.alt[2].configID == 101, "its own settings copy every setup")
p.follow:Click()
treeRow("Loadout", "group:pvp"):Click()
p.split:Click()
p.multi:Click()

-- which spec a page opens on: the one it switches to, else the one the character is in
local function lit(specID) return not specButton(specID).icon:IsDesaturated() end
specButton(VENG):Click()
check(lit(VENG) and not lit(HAVOC), "a spec picked by hand")
treeRow("Loadout", "group:pve"):Click()
check(lit(HAVOC) and not lit(VENG), "another page: back on the spec the character is in")
specButton(VENG):Click()
main:Hide(); SlashCmdList.COMBATKIT("")
check(main:IsShown() and lit(HAVOC) and not lit(VENG), "the window reopened: the same")
treeRow("Loadout", "group:pve"):Click()
p.split:Click()
C.scenarios.world.autoSpec = VENG
treeRow("Loadout", "scenario:world"):Click()
check(lit(VENG) and not lit(HAVOC), "a page that switches spec opens on that spec")
treeRow("Loadout", "scenario:dungeon"):Click()
check(lit(HAVOC), "the next page: the character's spec again")
C.scenarios.world.autoSpec = nil
treeRow("Loadout", "group:pve"):Click()
p.split:Click()
treeRow("Loadout", "group:pvp"):Click()

-- "Apply" with another spec: the spec, its loadout, then its PvP talents
C.groups.pvp.specs[VENG] = { configID = 201, configName = "Tank", pvp = { DETAIN } }
specButton(VENG):Click()
W.activeConfig[VENG] = nil
W.log = {}
p.switch:Click(); flush()
eq(W.log[1], "spec:2", "the spec first")
eq(#W.log, 1, "nothing else before it is on")
slots(GLIMPSE, COVER, RAIN)   -- Vengeance's slots, once it is the spec
W.specIndex = 2; fire("PLAYER_SPECIALIZATION_CHANGED", "player")
eq(W.log[2], "talents:201", "then its talents")
eq(W.log[3], "pvp:" .. DETAIN .. "@1", "then its PvP talents")
fire("PLAYER_PVP_TALENT_UPDATE")
check(not LO.IsApplying(), "done")

-- a client without the game's slot art: the square stands in
W.missingAtlases = { ["talents-node-choice-mask"] = true }
local square = CK.Skin.TalentSlot(UIParent, 26, function() return {} end, function() end)
check(square.empty ~= nil and square.border == nil, "without the octagon art: a plain square slot")
square:SetIcon(2001); square:SetDisabled(true)
check(square.icon:IsDesaturated() and not square.empty:IsShown(), "which shows and greys an icon the same way")
W.missingAtlases = nil

T.releaseChat()
return T.report("pvp   [" .. (LOCALE or "enUS") .. "]")
