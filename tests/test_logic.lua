-- Logic tests for the Loadout module: the whole kit is loaded the way the game
-- does (core from its .toc, the module on demand), against WoW API stubs.
-- ROOT, HERE and LOCALE are set by the runner.

local T = dofile(HERE .. "/stubs.lua")
local check, eq, W, fire, flush = T.check, T.eq, T.W, T.fire, T.flush
T.captureChat()

local HAVOC, VENG, DEVOUR = 577, 581, 1480
local function at(inst, itype, diff) W.inInstance, W.instanceType, W.difficultyID = inst, itype, diff or 0 end
local function wear(id) for k, s in pairs(W.sets) do s[2] = (k == id) end end
local function logged(entry) for _, l in ipairs(W.log) do if l == entry then return true end end return false end
local function count(entry) local n = 0 for _, l in ipairs(W.log) do if l == entry then n = n + 1 end end return n end

-- start in the open world as Havoc, on the raid loadout, wearing PvP gear
at(false, "none"); W.specIndex = 1; W.activeConfig[HAVOC] = 102; wear(2)
local CK = T.boot()
local ns = CK.modules.Loadout
check(ns ~= nil and ns.enabled, "the Loadout module is loaded and running after login")
local C = ns.char

-- ---------------------------------------------------------------- defaults
check(C.split.pve == false and C.split.pvp == false, "groups start unsplit")
check(C.groups.pve and C.groups.pvp, "both groups exist")
for _, s in ipairs(ns.SCENARIOS) do
	check(C.scenarios[s.key] and C.scenarios[s.key].custom == false, s.key .. " starts without its own settings")
end
eq(C.warmodePvP, false, "war mode option starts off")

-- ---------------------------------------------------------------- detection: six scenarios
at(false, "none"); eq(ns.DetectScenario(), "world", "world")
W.warMode = true; eq(ns.DetectScenario(), "world", "war mode is still the world scenario"); W.warMode = false
at(true, "arena"); eq(ns.DetectScenario(), "arena", "arena")
at(true, "pvp"); eq(ns.DetectScenario(), "bg", "battleground")
at(true, "raid", 16); eq(ns.DetectScenario(), "raid", "raid")
at(true, "party", 2); eq(ns.DetectScenario(), "dungeon", "heroic dungeon")
at(true, "party", 23); eq(ns.DetectScenario(), "dungeon", "mythic dungeon")
at(true, "party", 8); eq(ns.DetectScenario(), "dungeon", "keystone run is dungeon")
at(true, "scenario", 208); eq(ns.DetectScenario(), "delve", "delve")
at(true, "scenario", 12); eq(ns.DetectScenario(), "world", "story scenario plays as world")

eq(ns.ScenarioFromQueue("RATEDSHUFFLE", 3), "arena", "queue: shuffle")
eq(ns.ScenarioFromQueue("RATEDSOLORBG", 0), "bg", "queue: blitz")
eq(ns.ScenarioFromQueue("ARENASKIRMISH", 2), "arena", "queue: skirmish")
eq(ns.ScenarioFromQueue("BATTLEGROUND", 0), "bg", "queue: bg")
eq(ns.ScenarioFromQueue("SOMETHINGNEW", 0), "bg", "queue: unknown type falls to bg")
eq(ns.ScenarioFromQueue(nil, nil), nil, "queue: no info")

-- ---------------------------------------------------------------- resolution (requests 1, 2)
local pveHavoc = { configID = 101, configName = "M+ AoE", setID = 1, setName = "PvE" }
local pveVeng  = { configID = 201, configName = "Tank", setID = 3, setName = "Tank" }
local pvpHavoc = { setID = 2, setName = "PvP" }
C.groups.pve.specs[HAVOC], C.groups.pve.specs[VENG] = pveHavoc, pveVeng
C.groups.pvp.specs[HAVOC] = pvpHavoc

for _, key in ipairs({ "world", "delve", "dungeon", "raid" }) do
	local cell, source = ns.ResolveTarget(key, HAVOC)
	check(cell == pveHavoc and source == "pve", key .. " uses the PvE cell")
end
for _, key in ipairs({ "arena", "bg" }) do
	local cell, source = ns.ResolveTarget(key, HAVOC)
	check(cell == pvpHavoc and source == "pvp", key .. " uses the PvP cell")
end
eq(ns.ResolveTarget("dungeon", VENG), pveVeng, "each spec has its own cell")
eq(ns.ResolveTarget("dungeon", DEVOUR), nil, "a spec without a cell has no target")

-- split: a scenario may carry its own cells
local dungeonHavoc = { configID = 101, configName = "M+ AoE", setID = 3, setName = "Tank" }
C.scenarios.dungeon.custom = true
C.scenarios.dungeon.specs[HAVOC] = dungeonHavoc
eq(ns.ResolveTarget("dungeon", HAVOC), pveHavoc, "own settings are ignored while the group is not split")
C.split.pve = true
local cell, source = ns.ResolveTarget("dungeon", HAVOC)
check(cell == dungeonHavoc and source == "dungeon", "split + own settings: the scenario's cell")
eq(ns.ResolveTarget("raid", HAVOC), pveHavoc, "a scenario without its own settings keeps the group's")
eq(ns.ResolveTarget("dungeon", VENG), nil, "own settings do not fall back per spec")

-- spec on entering: only for world and delve, only while split
C.scenarios.delve.autoSpec = VENG
C.scenarios.dungeon.autoSpec = VENG
eq(select(3, ns.ResolveTarget("delve", HAVOC)), VENG, "delve carries its spec")
eq(select(3, ns.ResolveTarget("dungeon", HAVOC)), nil, "dungeons never switch spec")
C.split.pve = false
eq(select(3, ns.ResolveTarget("delve", HAVOC)), nil, "no spec switch while PvE is not split")
C.scenarios.dungeon.custom = false
C.scenarios.dungeon.autoSpec = nil

-- war mode
W.warMode = true
eq(select(2, ns.ResolveTarget("world", HAVOC)), "pve", "war mode alone changes nothing")
C.warmodePvP = true
cell, source = ns.ResolveTarget("world", HAVOC)
check(cell == pvpHavoc and source == "pvp", "war mode world uses PvP when asked to")
eq(select(2, ns.ResolveTarget("delve", HAVOC)), "pve", "only the open world is affected")
W.warMode = false
eq(select(2, ns.ResolveTarget("world", HAVOC)), "pve", "war mode off: PvE again")
C.warmodePvP = false

-- ---------------------------------------------------------------- status
at(false, "none"); W.specIndex = 1; W.activeConfig[HAVOC] = 102; wear(2)
local st = ns.GetStatus("world")
check(st.state == "mismatch" and not st.talentsOK and not st.gearOK, "wrong talents and gear")
W.activeConfig[HAVOC] = 101; wear(1)
eq(ns.GetStatus("world").state, "ready", "ready when both match")
W.specIndex = 3
eq(ns.GetStatus("world").state, "none", "nothing set up for this spec")
W.specIndex = 1
W.setsHidden = true
st = ns.GetStatus("world")
check(st.gearMissing and st.state == "mismatch", "a set that does not resolve is reported missing")
W.setsHidden = false

-- ---------------------------------------------------------------- engine: apply once on entering
W.activeConfig[HAVOC] = 102; wear(2); W.log = {}
at(true, "raid", 16)
fire("PLAYER_ENTERING_WORLD")
check(logged("talents:101") and logged("equip:1"), "entering a scenario applies talents and gear")
eq(ns.GetStatus("raid").state, "ready", "and then it is ready")

-- what is changed by hand afterwards is left alone
wear(2); W.log = {}
fire("PLAYER_EQUIPMENT_CHANGED")
fire("EQUIPMENT_SWAP_FINISHED")
eq(#W.log, 0, "a manual gear change is not undone")
W.activeConfig[HAVOC] = 102
fire("TRAIT_CONFIG_UPDATED")
eq(#W.log, 0, "a manual talent change is not undone")
eq(ns.GetStatus("raid").state, "mismatch", "the HUD can show the difference")

-- a loading screen inside the same scenario is not an entry
W.now = 100
fire("PLAYER_ENTERING_WORLD")
eq(#W.log, 0, "a loading screen in the same scenario changes nothing")

-- a click on the HUD applies again
ns.ApplyNow(); flush()
check(logged("talents:101") and logged("equip:1"), "ApplyNow applies")

-- entering PvP
W.log = {}
at(true, "arena")
fire("PLAYER_ENTERING_WORLD")
check(logged("equip:2") and not logged("talents:101"), "arena: the PvP set, no talents configured")

-- changing spec applies that spec's cell
W.log = {}
at(true, "party", 8); fire("PLAYER_ENTERING_WORLD")
W.log = {}
W.specIndex = 2; W.activeConfig[VENG] = 999
fire("PLAYER_SPECIALIZATION_CHANGED", "player")
check(logged("talents:201") and logged("equip:3"), "a spec change applies the new spec's talents and gear")
W.log = {}
fire("PLAYER_SPECIALIZATION_CHANGED", "party1")
eq(#W.log, 0, "someone else's spec change is ignored")
W.specIndex = 1

-- combat: owed, paid when combat ends
at(false, "none"); W.activeConfig[HAVOC] = 101; wear(1); fire("PLAYER_ENTERING_WORLD")
W.log = {}; W.combat = true
at(true, "arena"); fire("PLAYER_ENTERING_WORLD")
eq(#W.log, 0, "nothing in combat")
check(ns.IsAutoPending(), "but it stays owed")
W.combat = false; fire("PLAYER_REGEN_ENABLED")
check(logged("equip:2"), "applied when combat ends")

-- a running key (reload mid-run): owed until it is over
at(false, "none"); fire("PLAYER_ENTERING_WORLD")
W.log = {}; W.challengeActive = true; wear(2)
at(true, "party", 8); fire("PLAYER_ENTERING_WORLD")
eq(#W.log, 0, "nothing while the key runs")
W.challengeActive = false; fire("CHALLENGE_MODE_COMPLETED")
check(logged("equip:1"), "applied once the key is over")

-- automatic switching off
ns.db.settings.auto = false
W.log = {}
at(true, "arena"); fire("PLAYER_ENTERING_WORLD")
eq(#W.log, 0, "auto off: entering switches nothing")
check(not ns.IsAutoPending(), "and nothing stays owed")
ns.ApplyNow(); flush()
check(logged("equip:2"), "auto off: a click still applies")
ns.db.settings.auto = true

-- data that has not loaded on the first pass is picked up by the second
at(false, "none"); fire("PLAYER_ENTERING_WORLD")
W.log = {}; wear(2); W.setsHidden = true
at(true, "raid", 16)
T.raw("PLAYER_ENTERING_WORLD"); flush(2)
check(not logged("equip:1"), "first pass: the set is not there yet")
W.setsHidden = false
flush()
check(logged("equip:1"), "second pass equips it")

-- ---------------------------------------------------------------- spec on entering (request 3)
C.split.pve = true
C.scenarios.delve.autoSpec = VENG
at(false, "none"); W.specIndex = 1; fire("PLAYER_ENTERING_WORLD")
W.log = {}; W.activeConfig[VENG] = 999; wear(1)
at(true, "scenario", 208); fire("PLAYER_ENTERING_WORLD")
eq(W.log[1], "spec:2", "entering a delve switches spec first")
eq(#W.log, 1, "and waits for it")
W.specIndex = 2; fire("PLAYER_SPECIALIZATION_CHANGED", "player")
check(logged("talents:201") and logged("equip:3"), "then the new spec's talents and gear")
-- switching back by hand is respected
W.log = {}
W.specIndex = 1; W.activeConfig[HAVOC] = 101; wear(1)
fire("PLAYER_SPECIALIZATION_CHANGED", "player")
check(not logged("spec:2"), "a manual spec change is not undone")
-- a group alone does not stand in the way (friends, an NPC companion: no assigned role)
-- settle(): the stub client never finishes a spec change, so let the request run out
local function settle() W.now = W.now + 100; flush(); T.chat = {} end
W.specs[2][3] = "TANK"   -- Vengeance
settle()
at(false, "none"); fire("PLAYER_ENTERING_WORLD")
W.log = {}; W.inGroup = true
at(true, "scenario", 208); fire("PLAYER_ENTERING_WORLD")
check(logged("spec:2"), "grouped without an assigned role: the spec still switches")
settle()
-- an assigned role does, when the target spec would leave it
at(false, "none"); W.specIndex = 1; fire("PLAYER_ENTERING_WORLD")
settle()
W.log = {}; W.role = "DAMAGER"
at(true, "scenario", 208); fire("PLAYER_ENTERING_WORLD")
check(not logged("spec:2"), "assigned damage: not switched to a tank spec")
local told = false
for _, line in ipairs(T.chat) do if line:find("Vengeance", 1, true) then told = true end end
check(told, "and the reason is said in chat")
settle()
-- the same role is fine
at(false, "none"); fire("PLAYER_ENTERING_WORLD")
settle()
W.log = {}; W.role = "TANK"
at(true, "scenario", 208); fire("PLAYER_ENTERING_WORLD")
check(logged("spec:2"), "assigned tank: switching to the tank spec is allowed")
settle()
W.inGroup = false; W.role = nil; W.specs[2][3] = nil
C.scenarios.delve.autoSpec = nil
C.split.pve = false

-- ---------------------------------------------------------------- queue pop
at(false, "none"); W.specIndex = 1; W.activeConfig[HAVOC] = 101; wear(1)
fire("PLAYER_ENTERING_WORLD")
W.log = {}
W.battlefield[1] = { "confirm", 3, "ARENA" }
fire("UPDATE_BATTLEFIELD_STATUS")
eq(ns.GetEarlyScenario(), "arena", "the pop names the scenario")
eq(#W.log, 0, "nothing is switched on a pop")
ns.ApplyNow(); flush()
check(logged("equip:2"), "a click during the pop applies the upcoming scenario")
-- a spec change during the pop waits for the answer
W.log = {}; W.specIndex = 2
fire("PLAYER_SPECIALIZATION_CHANGED", "player")
eq(#W.log, 0, "automatic switching pauses while a pop is pending")
W.battlefield[1] = nil
fire("UPDATE_BATTLEFIELD_STATUS")
eq(ns.GetEarlyScenario(), nil, "declined")
check(logged("equip:3"), "the paused switch runs once the pop is gone")
W.specIndex = 1

ns.db.settings.early = false
W.battlefield[1] = { "confirm", 3, "ARENA" }; fire("UPDATE_BATTLEFIELD_STATUS")
eq(ns.GetEarlyScenario(), nil, "pops can be ignored")
W.battlefield[1] = nil; fire("UPDATE_BATTLEFIELD_STATUS")
ns.db.settings.early = true

W.lfg = 2; fire("LFG_PROPOSAL_SHOW")
eq(ns.GetEarlyScenario(), "dungeon", "LFG proposal names the scenario")
T.runLongTimers()
eq(ns.GetEarlyScenario(), nil, "a stale proposal times out")
fire("LFG_PROPOSAL_SHOW"); W.lfg = nil; fire("LFG_PROPOSAL_FAILED")
eq(ns.GetEarlyScenario(), nil, "a failed proposal clears it")

-- ---------------------------------------------------------------- repair by name
W.configs[HAVOC] = { 101, 150 }; W.configNames[150] = "Raid ST"; W.configNames[102] = nil
local stale = { configID = 102, configName = "Raid ST", setID = 9, setName = "Tank" }
ns.RepairCell(stale, HAVOC)
eq(stale.configID, 150, "talent loadout re-linked by name")
eq(stale.setID, 3, "equipment set re-linked by name")

-- ---------------------------------------------------------------- locale keys the module itself needs
for _, g in ipairs(ns.GROUPS) do
	check(ns.L["GROUP_" .. g] ~= "GROUP_" .. g, "GROUP_" .. g)
end
for _, sc in ipairs(ns.SCENARIOS) do
	check(ns.L["SCN_" .. sc.key] ~= "SCN_" .. sc.key, "SCN_" .. sc.key)
end
for _, role in ipairs({ "TANK", "HEALER", "DAMAGER" }) do
	check(ns.L["ROLE_" .. role] ~= "ROLE_" .. role, "ROLE_" .. role)
end
check(CK.HUD.GetFrame() ~= nil, "checks keep the HUD up to date")

T.releaseChat()
return T.report("logic [" .. (LOCALE or "enUS") .. "]")
