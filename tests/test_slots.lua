-- Talent spells back in their action slot (Slots.lua), the user's case of
-- 2026-11-17: Preservation with a PvE loadout that has Emerald Communion and a
-- PvP one that has not, both on shared action bars, switched by scenario.

local T = dofile(HERE .. "/stubs.lua")
local check, eq, W, fire, flush = T.check, T.eq, T.W, T.fire, T.flush

local DEV, PRES = 1467, 1468
local PVE, PVP = 56674545, 56310211
local EC, OTHER = 370960, 361469   -- Emerald Communion; a spell both loadouts have
W.specs = { { DEV, "Devastation", "DAMAGER" }, { PRES, "Preservation", "HEALER" } }
W.configs = { [DEV] = { 57945081 }, [PRES] = { PVE, PVP } }
W.configNames = { [57945081] = "dev", [PVE] = "pve", [PVP] = "pvp" }
W.sets = {}
W.activeConfig = { [DEV] = 57945081, [PRES] = PVE }
W.specIndex = 2
W.known = { [EC] = true, [OTHER] = true }
W.actions = { [1] = OTHER, [2] = "macro", [5] = EC, [7] = 355913 }
W.cvars = { AutoPushSpellToActionBar = "1" }

CombatKitLoadoutDB = {
	settings = { auto = true },
	chars = { ["Tester - Realm"] = {
		class = "EVOKER",
		groups = {
			pve = { specs = { [PRES] = { configID = PVE, configName = "pve" } } },
			pvp = { specs = { [PRES] = { configID = PVP, configName = "pvp" } } },
		},
	} },
}

T.captureChat()
local ns
local function pass(seconds) W.now = W.now + seconds; flush() end
local function count(prefix) local n = 0 for _, l in ipairs(W.log) do if l:sub(1, #prefix) == prefix then n = n + 1 end end return n end
local function logged(line) for _, l in ipairs(W.log) do if l == line then return true end end return false end

-- the game taking a talent away: the spell is no longer known, and every slot holding it is cleared
local function lose(spellID)
	W.known[spellID] = nil
	for slot = 1, 180 do
		if W.actions[slot] == spellID then W.actions[slot] = nil; T.raw("ACTIONBAR_SLOT_CHANGED", slot) end
	end
	T.raw("PLAYER_TALENT_UPDATE")
end
-- and giving it back: pushed into `pushTo` when given (the game's auto-push), else nowhere
local function learn(spellID, pushTo)
	W.known[spellID] = true
	if pushTo then
		W.actions[pushTo] = spellID
		T.raw("ACTIONBAR_SLOT_CHANGED", pushTo)
		T.raw("SPELL_PUSHED_TO_ACTIONBAR", spellID, pushTo, 1)
	end
	T.raw("PLAYER_TALENT_UPDATE")
	T.raw("SPELLS_CHANGED")
end
-- a talent change by hand in the talent window: what leaves and what comes, then a moment
local function change(f) W.now = W.now + 5; f(); pass(1) end

local CK = T.boot()
ns = CK.modules.Loadout
fire("PLAYER_ENTERING_WORLD")
pass(5)

-- ---------------------------------------------------------------- the game's auto-push
eq(ns.db.settings.slotRestore, true, "on by default")
eq(W.cvars.AutoPushSpellToActionBar, "0", "the game's auto-push is off while it is on")
eq(ns.char.autoPushWas, "1", "and what it was is kept")
ns.db.settings.slotRestore = false; ns.OnSlotRestoreChanged()
eq(W.cvars.AutoPushSpellToActionBar, "1", "switched off: back as it was")
eq(ns.char.autoPushWas, nil, "and nothing is kept any more")
ns.db.settings.slotRestore = true; ns.OnSlotRestoreChanged()
eq(W.cvars.AutoPushSpellToActionBar, "0", "on again: off again")
pass(1)

-- ---------------------------------------------------------------- the reported case, by hand
W.log = {}
change(function() lose(EC) end)
eq(W.actions[5], nil, "the game clears its slot")
eq(ns.char.slots[PRES][EC], 5, "the slot is remembered for this spec")
change(function() learn(EC) end)
eq(W.actions[5], EC, "learned again with the push off: back in its slot")
check(logged("pickupspell:" .. EC) and logged("place:5"), "from the spell book")
eq(ns.char.slots[PRES][EC], nil, "and no longer remembered")
eq(W.cursor, nil, "nothing left on the cursor")
eq(W.actions[1], OTHER, "the rest of the bars untouched")

-- pushed by the game into the first empty slot: moved back
W.log = {}
change(function() lose(EC) end)
change(function() learn(EC, 3) end)
eq(W.actions[5], EC, "pushed elsewhere: moved back")
eq(W.actions[3], nil, "out of the slot it was pushed into")
check(logged("pickup:3") and logged("place:5"), "picked up from there")

-- the same without the game saying it pushed: the loadout did not change, so it can only be the push
change(function() lose(EC) end)
change(function()
	W.known[EC] = true
	W.actions[4] = EC
	T.raw("ACTIONBAR_SLOT_CHANGED", 4)
	T.raw("PLAYER_TALENT_UPDATE")
end)
eq(W.actions[5], EC, "a new slot right after the talent came back: moved back too")
eq(W.actions[4], nil, "and out of it")

-- the slot taken meanwhile: the spell is not put anywhere, and forgotten
change(function() lose(EC) end)
W.actions[5] = "macro"; fire("ACTIONBAR_SLOT_CHANGED", 5); pass(1)
W.log = {}
change(function() learn(EC) end)
eq(W.actions[5], "macro", "a taken slot is left alone")
eq(count("pickupspell:"), 0, "and nothing is picked up")
eq(ns.char.slots[PRES][EC], nil, "settled")
W.actions[5] = EC; fire("ACTIONBAR_SLOT_CHANGED", 5); pass(1)

-- taken off by hand while known: not the game's doing, never put back
W.actions[5] = nil; fire("ACTIONBAR_SLOT_CHANGED", 5)
T.raw("PLAYER_TALENT_UPDATE"); pass(1)
eq(ns.char.slots[PRES][EC], nil, "a spell removed by hand is not remembered")
W.actions[5] = EC; fire("ACTIONBAR_SLOT_CHANGED", 5); pass(1)

-- cleared with no talent change around it: not remembered either
W.now = W.now + 30
W.known[EC] = nil; W.actions[5] = nil; fire("ACTIONBAR_SLOT_CHANGED", 5); pass(1)
eq(ns.char.slots[PRES][EC], nil, "no talent change, nothing remembered")
W.known[EC] = true; W.actions[5] = EC; fire("ACTIONBAR_SLOT_CHANGED", 5); pass(1)

-- something on the cursor: waits for it to go
change(function() lose(EC) end)
W.cursor = 999
change(function() learn(EC) end)
eq(W.actions[5], nil, "not while the player holds something")
eq(W.cursor, 999, "and what they hold is theirs")
W.cursor = nil; pass(3)
eq(W.actions[5], EC, "put back once the cursor is free")

-- combat: waits for it to end
change(function() lose(EC) end)
W.combat = true
change(function() learn(EC) end)
eq(W.actions[5], nil, "nothing in combat")
W.combat = false; fire("PLAYER_REGEN_ENABLED"); pass(1)
eq(W.actions[5], EC, "put back when combat ends")

-- secret answers: nothing is judged
W.actionsSecret = true
change(function() lose(EC) end)
eq(ns.char.slots[PRES][EC], nil, "bars that cannot be read are not judged")
W.actionsSecret = false; pass(1)
change(function() learn(EC) end)
W.actions[5] = EC; fire("ACTIONBAR_SLOT_CHANGED", 5); pass(1)

-- ---------------------------------------------------------------- CombatKit's own switch, both ways
local load = C_ClassTalents.LoadConfig
C_ClassTalents.LoadConfig = function(id, ...)
	local result, err = load(id, ...)
	if id == PVP then lose(EC) elseif id == PVE then learn(EC) end
	return result, err
end
W.loadResult = 3   -- Ready
local function pretend(key) W.now = W.now + 10; ns.debug.scenario = key; ns.Check(); pass(1) end

W.log = {}
pretend("arena")
eq(W.activeConfig[PRES], PVP, "arena: the PvP loadout")
eq(W.actions[5], nil, "Emerald Communion leaves its slot")
eq(ns.char.slots[PRES][EC], 5, "remembered")
pretend("world")
eq(W.activeConfig[PRES], PVE, "open world: the PvE loadout")
eq(W.actions[5], EC, "Emerald Communion is back in its slot")
pretend("arena"); pretend("world")
eq(W.actions[5], EC, "and again, every time")
eq(count("talents:"), 4, "four loadout switches")

-- ---------------------------------------------------------------- bars that are not shared
-- a loadout with its own bars brings its spells back itself; a spell found in another slot then is left there
W.ownBars = { [PVE] = true, [PVP] = true }
change(function() lose(EC) end)
change(function()
	W.activeConfig[PRES] = PVP
	W.known[EC] = true
	W.actions[6] = EC
	T.raw("ACTIONBAR_SLOT_CHANGED", 6)
	T.raw("PLAYER_TALENT_UPDATE")
end)
eq(W.actions[6], EC, "another loadout's own bars: left where they have it")
eq(W.actions[5], nil, "not moved")
W.ownBars = nil; W.activeConfig[PRES] = PVE
W.actions[6] = nil; W.actions[5] = EC; fire("ACTIONBAR_SLOT_CHANGED", 5); pass(1)

-- a whole other set of bars at once, the loadout still reading the same: a loadout's own
-- bars coming on. Spells that leave then are not remembered, even into empty slots.
local kept = W.actions
local mine, theirs = {}, {}
for slot = 1, 20 do mine[slot] = 400000 + slot; W.known[400000 + slot] = true end
for slot = 1, 10 do theirs[slot] = 500000 + slot end
W.actions = mine
for slot = 1, 20 do T.raw("ACTIONBAR_SLOT_CHANGED", slot) end
pass(1)
change(function()
	for slot = 1, 20 do W.known[400000 + slot] = nil end
	for slot = 1, 10 do W.known[500000 + slot] = true end
	W.actions = theirs
	for slot = 1, 20 do T.raw("ACTIONBAR_SLOT_CHANGED", slot) end
	T.raw("PLAYER_TALENT_UPDATE")
end)
eq(next(ns.char.slots[PRES]), nil, "a whole other set of bars: nothing remembered")
W.actions = kept
for slot = 1, 20 do T.raw("ACTIONBAR_SLOT_CHANGED", slot) end
pass(1)

-- ---------------------------------------------------------------- a spec change
-- every slot changes and the other spec's spells are not known: nothing is remembered
ns.debug.scenario = nil
W.now = W.now + 30
local presBars = W.actions
W.actions = { [1] = 362969, [2] = 357208 }
for slot = 1, 12 do T.raw("ACTIONBAR_SLOT_CHANGED", slot) end
W.known = { [362969] = true, [357208] = true }
W.specIndex = 1
T.raw("PLAYER_TALENT_UPDATE")
fire("PLAYER_SPECIALIZATION_CHANGED", "player"); pass(1)
eq(next(ns.char.slots[DEV] or {}), nil, "Devastation remembers nothing")
eq(ns.char.slots[PRES][EC], nil, "neither does Preservation")
W.actions, W.specIndex = presBars, 2
W.known = { [EC] = true, [OTHER] = true }
fire("PLAYER_SPECIALIZATION_CHANGED", "player"); pass(1)

-- ---------------------------------------------------------------- switched off
ns.db.settings.slotRestore = false; ns.OnSlotRestoreChanged(); pass(1)
change(function() lose(EC) end)
eq(ns.char.slots[PRES][EC], nil, "off: nothing is remembered")
change(function() learn(EC) end)
eq(W.actions[5], nil, "and nothing is put back")
ns.db.settings.slotRestore = true; ns.OnSlotRestoreChanged(); pass(1)
W.actions[5] = EC; fire("ACTIONBAR_SLOT_CHANGED", 5); pass(1)

-- the module switched off puts the game's auto-push back
eq(W.cvars.AutoPushSpellToActionBar, "0", "on: the push is off")
CK.SetModuleEnabled("Loadout", false); flush()
eq(W.cvars.AutoPushSpellToActionBar, "1", "module off: the push is back")
CK.SetModuleEnabled("Loadout", true); flush()
eq(W.cvars.AutoPushSpellToActionBar, "0", "module on: off again")

-- a push the player had off already stays off, and stays theirs
CK.SetModuleEnabled("Loadout", false); flush()
W.cvars.AutoPushSpellToActionBar = "0"
CK.SetModuleEnabled("Loadout", true); flush()
eq(ns.char.autoPushWas, nil, "already off: nothing to put back later")
CK.SetModuleEnabled("Loadout", false); flush()
eq(W.cvars.AutoPushSpellToActionBar, "0", "and it stays off")

-- a client without the setting: nothing is written
W.cvars = {}; W.log = {}
CK.SetModuleEnabled("Loadout", true); flush()
eq(count("cvar:"), 0, "no such setting: nothing written")

T.releaseChat()
return T.report(("slots [%s]"):format(LOCALE))
