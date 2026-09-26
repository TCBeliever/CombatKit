-- The apply state machine against a client that drops, refuses and delays
-- requests, replayed with the user's real saved settings (Evoker, 2026-09-20):
-- PvE split; delve: own settings, spec 1468; open world: own settings, spec 1467.

local T = dofile(HERE .. "/stubs.lua")
local check, eq, W, fire, flush = T.check, T.eq, T.W, T.fire, T.flush

local DEV, PRES, AUG = 1467, 1468, 1473
W.specs = { { DEV, "Devastation", "DAMAGER" }, { PRES, "Preservation", "HEALER" }, { AUG, "Augmentation", "DAMAGER" } }
W.configs = { [DEV] = { 57945081, 56310210 }, [PRES] = { 58128473, 56674545 }, [AUG] = {} }
W.configNames = { [57945081] = "cmder M+", [56310210] = "pvp", [58128473] = "delve", [56674545] = "pve" }
W.sets = { [0] = { "PVP", false }, [1] = { "Dev M+", true } }
W.activeConfig = { [DEV] = 57945081, [PRES] = 56674545 }
W.activeTraitConfig = 9001
W.loadResult = 2   -- LoadInProgress: talent changes are casts
W.specIndex = 1

CombatKitLoadoutDB = {
	version = 1,
	settings = { auto = true, early = true, hud = "always" },
	chars = { ["Tester - Realm"] = {
		class = "EVOKER",
		split = { pve = true, pvp = false },
		warmodePvP = false,
		groups = {
			pve = { specs = {} },
			pvp = { specs = {
				[DEV]  = { configID = 56310210, configName = "pvp", setID = 0, setName = "PVP" },
				[PRES] = { configID = 56674545, configName = "pve", setID = 0, setName = "PVP" },
			} },
		},
		scenarios = {
			world = { custom = true, autoSpec = DEV,  specs = { [DEV]  = { configID = 57945081, configName = "cmder M+", setID = 1, setName = "Dev M+" } } },
			delve = { custom = true, autoSpec = PRES, specs = { [PRES] = { configID = 58128473, configName = "delve",    setID = 1, setName = "Dev M+" } } },
			dungeon = { custom = false, specs = {} }, raid = { custom = false, specs = {} },
			arena = { custom = false, specs = {} }, bg = { custom = false, specs = {} },
		},
	} },
}

T.captureChat()

local ns
local function pass(seconds) W.now = W.now + seconds; flush() end
local function count(prefix) local n = 0 for _, l in ipairs(W.log) do if l:sub(1, #prefix) == prefix then n = n + 1 end end return n end
local function said(text) for _, l in ipairs(T.chat) do if l:find(text, 1, true) then return true end end return false end
local function pretend(key) ns.debug.scenario = key; ns.Check(); flush() end
-- the client finishing what was asked
local function specLands(index) W.casting = false; W.specIndex = index; fire("PLAYER_SPECIALIZATION_CHANGED", "player") end
local function talentsLand() W.casting = false; fire("TRAIT_CONFIG_UPDATED", W.activeTraitConfig) end

local CK = T.boot()
ns = CK.modules.Loadout
fire("PLAYER_ENTERING_WORLD")
eq(ns.GetStatus("world").state, "ready", "the city starts ready: Devastation, cmder M+, Dev M+")
check(not ns.IsApplying(), "nothing to apply at login")

-- ---------------------------------------------------------------- the reported round trip
W.log = {}
pretend("delve")
eq(W.log[1], "spec:2", "delve: asks for Preservation")
W.casting = true; pass(3)
eq(#W.log, 1, "and waits while the spec change is cast")
specLands(2)
eq(W.log[2], "talents:58128473", "then the delve loadout")
W.casting = true; pass(2)

-- an unrelated trait tree updating must not count as our commit
fire("TRAIT_CONFIG_UPDATED", 777)
eq(W.activeConfig[PRES], 56674545, "a profession tree update is not our commit")
check(ns.IsApplying(), "still applying")

-- the user flips back to open world while the talent change is still being cast:
-- this is where 0.2.0 asked too early, was dropped by the client and never asked again
W.log = {}
pretend("world")
eq(#W.log, 0, "nothing is asked during the cast")
talentsLand()
eq(W.activeConfig[PRES], 58128473, "the delve commit is recorded")
eq(W.log[1], "spec:1", "open world: asks for Devastation as soon as the cast is over")
W.casting = true; pass(3)
specLands(1)
check(not ns.IsApplying(), "open world needs nothing more: its loadout and set are already on")
eq(ns.GetStatus("world").state, "ready", "and the round trip ends ready")
eq(count("spec:"), 1, "asked exactly once")

-- and again, the other way, to be sure it is repeatable
W.log = {}
pretend("delve"); W.casting = true; pass(3); specLands(2)
check(not ns.IsApplying(), "delve again: the loadout is remembered, nothing to load")
eq(count("spec:"), 1, "one spec request")
pretend("world"); W.casting = true; pass(3); specLands(1)
eq(count("spec:"), 2, "and one back")

-- ---------------------------------------------------------------- a request the client accepts and then ignores
W.log = {}; T.chat = {}
pretend("delve")
eq(count("spec:"), 1, "asked")
pass(0.5); eq(count("spec:"), 1, "not again within the grace period")
pass(1); eq(count("spec:"), 2, "asked again when nothing happened")
pass(2); pass(2)
eq(count("spec:"), 4, "up to four times")
pass(2)
eq(count("spec:"), 4, "then no more")
check(not ns.IsApplying(), "it gives up")
check(said(ns.L["Could not switch specialization."]), "and says so")

-- a later entry starts fresh
W.log = {}
pretend("world")
eq(#W.log, 0, "open world is already right: nothing to do")
pretend("delve")
eq(count("spec:"), 1, "delve asks again from scratch")
W.casting = true; pass(3); specLands(2)

-- ---------------------------------------------------------------- a request the client refuses outright
W.log = {}; T.chat = {}
W.specRefused = true
pretend("world")
pass(2); pass(2); pass(2); pass(2)
eq(count("spec:"), 4, "a refused request is retried like a dropped one")
check(not ns.IsApplying() and said(ns.L["Could not switch specialization."]), "and given up the same way")
W.specRefused = false

-- ---------------------------------------------------------------- a talent cast the player interrupts is not asked again
W.specIndex = 2; W.activeConfig[PRES] = 56674545
W.log = {}; T.chat = {}
pretend("raid"); pretend("delve")   -- re-enter delve as Preservation with the wrong loadout
eq(count("talents:"), 1, "loadout asked")
W.casting = true; pass(1)
W.casting = false; fire("CONFIG_COMMIT_FAILED")
pass(2); pass(2); pass(2)
eq(count("talents:"), 1, "the interruption ends it: not asked again")
check(not ns.IsApplying(), "nothing pending")
check(said(ns.L["Talent change"]) and said("HUD"), "one message, pointing at the HUD")
eq(ns.GetStatus("delve").state, "mismatch", "the HUD keeps showing what is missing")
fire("PLAYER_ENTERING_WORLD"); pass(1); pass(4); pass(1)
eq(count("talents:"), 1, "the second pass after a loading screen does not ask either")
ns.ApplyNow(); flush()
eq(count("talents:"), 2, "clicking the HUD asks once more")
W.casting = true; pass(1); talentsLand(); pass(1)
check(not ns.IsApplying(), "and finished")
eq(ns.GetStatus("delve").state, "ready", "ready")

-- the same for a spec cast: seen under way, then gone with the spec unchanged
W.specIndex = 1; W.log = {}; T.chat = {}
pretend("raid"); pretend("delve")   -- delve wants Preservation
eq(count("spec:"), 1, "spec asked")
W.casting = true; pass(1)
W.casting = false; pass(1); pass(1); pass(1)
eq(count("spec:"), 1, "gone without landing: not asked again")
check(not ns.IsApplying() and said(ns.L["Spec change"]), "ended with a message")
pass(2); pass(2)
eq(count("spec:"), 1, "and stays ended")
-- a dropped request (never a cast) is still retried
W.log = {}
pretend("raid"); pretend("delve")
eq(count("spec:"), 1, "spec asked")
pass(2)
eq(count("spec:"), 2, "no cast showed up: asked again")
W.casting = true; pass(1); specLands(2)
W.casting = true; pass(1); talentsLand(); pass(1)
check(not ns.IsApplying(), "and finished")

-- ---------------------------------------------------------------- running after a loading screen
W.log = {}; T.chat = {}
W.specIndex = 1; pretend("world"); flush()
W.moving = true
pretend("delve")
pass(1); pass(1); pass(1); pass(1); pass(1)
eq(count("spec:"), 0, "no spec request is wasted while the player is moving")
check(ns.IsApplying(), "it waits")
W.moving = false; pass(1)
eq(count("spec:"), 1, "asked once the player stands still")
W.casting = true; pass(3); specLands(2)
W.casting = true; pass(1); talentsLand(); pass(1)
check(not ns.IsApplying(), "and carried through")
-- but not forever
W.specIndex = 1; pretend("world"); flush(); W.log = {}; T.chat = {}
W.moving = true
pretend("delve")
for _ = 1, 20 do pass(1) end
check(not ns.IsApplying(), "a player who never stops is not followed around")
check(said(ns.L["Could not switch specialization."]), "and is told")
eq(count("spec:"), 0, "still nothing was asked")
W.moving = false
W.specIndex = 2; W.activeConfig[PRES] = 58128473

-- ---------------------------------------------------------------- in a group (the second report)
-- open world -> delve did nothing while grouped: 0.2.0 refused every spec switch in any group
W.specIndex = 1; W.activeConfig[DEV] = 57945081; pretend("world"); flush()
W.log = {}; T.chat = {}; W.inGroup = true
pretend("delve")
eq(count("spec:"), 1, "grouped with no assigned role (an NPC companion, friends): the delve spec is switched to")
W.casting = true; pass(3); specLands(2)
W.casting = true; pass(1); talentsLand(); pass(1)
eq(ns.GetStatus("delve").state, "ready", "and the delve ends ready")

-- a healer stepping out of a dungeon is not turned into damage
W.role = "HEALER"; W.log = {}; T.chat = {}
pretend("world")
eq(count("spec:"), 0, "assigned healer: open world does not switch to Devastation")
check(said("Devastation"), "and says why")
W.role = nil; W.inGroup = false
W.specIndex = 2; W.activeConfig[PRES] = 58128473

-- ---------------------------------------------------------------- combat stops the clock, it does not time out
W.log = {}
W.activeConfig[PRES] = 56674545
pretend("raid"); W.combat = true; pretend("delve")
ns.ApplyNow(); flush()
pass(60)
check(ns.IsApplying(), "a click in combat stays pending however long the fight")
eq(count("talents:"), 0, "and asks nothing meanwhile")
W.combat = false; fire("PLAYER_REGEN_ENABLED")
eq(count("talents:"), 1, "asked when combat ends")
W.casting = true; pass(1); talentsLand(); pass(1)

T.releaseChat()
return T.report("apply [" .. (LOCALE or "enUS") .. "]")
