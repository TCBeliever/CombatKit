-- The Stats module: lines on the HUD, live in combat although the numbers are
-- "secret" there, and its settings page.

local T = dofile(HERE .. "/stubs.lua")
local check, eq, W, fire, flush = T.check, T.eq, T.W, T.fire, T.flush
T.captureChat()

local CK = T.boot()
fire("PLAYER_ENTERING_WORLD")
check(T.loaded.CombatKit_Stats == nil, "off by default: never loaded")

CK.SetModuleEnabled("Stats", true); flush()
local ST = CK.modules.Stats
check(T.loaded.CombatKit_Stats ~= nil and ST and ST.enabled, "switched on: loaded and running")

local hud = CK.HUD.GetFrame()
local function rows() return hud.sections.stats.rows end
local function text(i) return rows()[i].value:GetText() end
local function label(i) return rows()[i].label:GetText() end

-- ---------------------------------------------------------------- readable values
check(hud.sections.loadout:IsShown() and hud.sections.stats:IsShown(), "Loadout and Stats share the HUD")
check(hud.rules[1]:IsShown(), "with a line between them")
check(label(1):find(CK.L["STAT_crit"], 1, true), "first row: crit")
eq(text(1), "30.0%", "crit is the highest of spell, melee and ranged")
eq(text(2), "18.0%", "haste")
eq(text(3), "41.5%", "mastery")
eq(text(4), "8.0%", "versatility is rating plus flat bonus")
check(not rows()[5] or not rows()[5].value:IsShown(), "four stats by default")

W.stats.haste = 25.55; fire("COMBAT_RATING_UPDATE")
eq(text(2), "25.6%", "an event refreshes it")

-- ---------------------------------------------------------------- order, which stats, precision
ST.db.shown.speed = true; ST.db.shown.ilvl = true
W.speed = 9.8; CK.HUD.Refresh()
eq(text(5), "140%", "movement speed as a percentage of run speed, no decimals")
eq(text(6), "702.6", "item level keeps one decimal, no percent sign")
-- no event says the speed changed: the module looks for itself
W.speed = 3.5; flush()
eq(text(5), "50%", "slowed: the HUD follows without any event")
W.speed = 0; W.runSpeed = 9.1; flush()
eq(text(5), "130%", "standing still: the speed you would run at, as on the character sheet")
W.swimming = true; flush()
eq(text(5), "67%", "in water: the swim speed")
W.swimming = false; W.gliding = 54.9; flush()   -- GetUnitSpeed says 0 while skyriding
eq(text(5), "784%", "skyriding: the glide speed")
W.gliding = nil; W.vehicleSpeed = 14; flush()
eq(text(5), "200%", "in a vehicle: the vehicle's speed")
W.vehicleSpeed = nil; W.runSpeed = nil; W.speed = 9.8; flush()
eq(text(5), "140%", "running again")
eq(ST.StatLabel("primary"), CK.L["STAT_primary_1"], "the primary stat goes by its own name")

-- durability: everything worn, taken together
ST.db.shown.durability = true
W.durability = { [1] = { 30, 100 }, [5] = { 100, 100 }, [16] = { 80, 100 } }
fire("UPDATE_INVENTORY_DURABILITY")
eq(text(7), "70%", "durability: the sum of what is left over the sum of what there was")
W.durability[5] = { 10, 100 }; fire("UPDATE_INVENTORY_DURABILITY")
check(text(7):find("40%", 1, true) and text(7):find(CK.Skin.Hex("warn"), 1, true), "amber from half down")
W.durability = { [1] = { 10, 100 } }; fire("UPDATE_INVENTORY_DURABILITY")
check(text(7):find(CK.Skin.Hex("bad"), 1, true), "red when nearly broken")
W.durability = nil; fire("UPDATE_INVENTORY_DURABILITY")
check(text(7):find("10%", 1, true), "nothing with durability on: the last known value stays")
ST.db.shown.durability = nil; CK.HUD.Refresh()
-- the order covers every stat, shown or not: item level sits below the hidden "primary"
ST.Move("ilvl", -1); ST.Move("ilvl", -1); CK.HUD.Refresh()
check(label(5):find(CK.L["STAT_ilvl"], 1, true), "moved above movement speed")
ST.Move("crit", -1); CK.HUD.Refresh()
check(label(1):find(CK.L["STAT_crit"], 1, true), "the first cannot move further up")
ST.db.decimals = 0; CK.HUD.Refresh()
eq(text(1), "30%", "decimals are a setting")
ST.db.decimals = 1

-- ---------------------------------------------------------------- combat: secret values
W.secretStats = true
local ok, err = pcall(fire, "COMBAT_RATING_UPDATE")
check(ok, "secret values raise no error: " .. tostring(err))
eq(text(2), "99.9%", "a stat from one API stays live: the game formats the secret")
eq(text(1), "99.9%", "crit falls back to the source that was highest before")
check(text(6):find("140%", 1, true) and text(6):find(CK.Skin.Hex("dim"), 1, true), "what needs arithmetic is shown from memory, dimmed")
check(hud:IsShown(), "and the HUD still lays itself out, without measuring secret text")
W.secretStats = false; flush()
eq(text(6), "140%", "readable again: the speed comes back on its own, no longer dimmed")
fire("PLAYER_REGEN_ENABLED")
eq(text(2), "25.6%", "readable again after combat")

-- ---------------------------------------------------------------- settings page
SlashCmdList.COMBATKIT("")
local main = CK.Options.GetFrame()
local function treeRow(section, node)
	for _, r in ipairs(main.treeRows) do
		if r:IsShown() and r.section == section and r.node == node then return r end
	end
end
check(not main.tabs.Stats.dimmed, "the module has its tab")
main.tabs.Stats:Click()
eq(treeRow("Stats", "stats"), nil, "a single page: no tree")
local page = main.bodies.Stats
eq(main.detail.title:GetText(), CK.L["MOD_Stats"], "page title")
eq(#page.rows, #ST.STATS, "one row per stat")
eq(page.rows[1].key, "crit", "in the saved order")
check(page.rows[1].check:GetChecked() and not page.rows[#ST.STATS].check:GetChecked(), "check boxes say what is shown")

-- the list: each stat with its English name next to it (once, when the interface is English)
local crit = page.rows[1].check.label:GetText()
if CK.L["STAT_crit"] == "Crit" then
	eq(crit, "Crit", "English interface: the name, once")
else
	check(crit:find(CK.L["STAT_crit"], 1, true) and crit:find("Crit", 1, true), "other languages: the name and its English")
end
local listX = page.rows[1].up.__point[2]
check(listX > page.english.__point[2] + page.english:GetWidth(), "the list is the right column, clear of the fields on the left")
local listRight = listX + 18 + 2 + 18 + 10 + page.rows[1].check:GetWidth()
check(listRight > CK.Options.RIGHT_W and listRight < CK.Options.PageWidth(), "in the room the tree leaves free on a single page, a margin from its edge")

-- English names on the HUD, whatever language the window is in
check(not page.english:GetChecked(), "English names: off by default")
check(label(1):find(CK.L["STAT_crit"], 1, true), "the HUD names crit in the language of the interface")
page.english:Click()
eq(ST.db.english, true, "ticked")
check(label(1):find("Crit", 1, true), "the HUD says Crit")
check(page.rows[1].check.label:GetText():find(CK.L["STAT_crit"], 1, true), "the list on the page stays in the language of the interface")
page.english:Click()
check(ST.db.english == nil and label(1):find(CK.L["STAT_crit"], 1, true), "and back")

page.rows[1].check:Click()
eq(ST.db.shown.crit, nil, "unticked: not shown")
check(label(1):find(CK.L["STAT_haste"], 1, true), "the HUD follows at once")
page.rows[1].check:Click()
page.rows[1].down:Click()
eq(ST.db.order[2], "crit", "arrow down moves it")
eq(page.rows[2].key, "crit", "the page follows")
page.rows[2].up:Click()
eq(ST.db.order[1], "crit", "arrow up moves it back")

-- ---------------------------------------------------------------- switching it off
CK.SetModuleEnabled("Stats", false)
check(not hud.sections.stats:IsShown(), "off: its lines leave the HUD")
check(main.tabs.Stats.dimmed and main.off:IsShown(), "and its tab offers to switch it on again")
W.stats.haste = 1; fire("COMBAT_RATING_UPDATE")
eq(CK.GetModuleState("Stats"), "stale", "loaded code stays until a reload")
CK.SetModuleEnabled("Stats", true); flush()
eq(text(2), "1.0%", "on again: current values")

T.releaseChat()
return T.report("stats [" .. (LOCALE or "enUS") .. "]")
