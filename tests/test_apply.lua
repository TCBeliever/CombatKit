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

-- ---------------------------------------------------------------- a loadout the game holds up (2026-11-01)
-- Tempered Soul gives Soul Immolation a second charge, and the game will not take
-- it out while Soul Immolation recharges. It says so in LoadConfig's answer only,
-- and leaves the refused loadout staged in the tree.
local HELD = "You can't change talents while Tempered Soul is on cooldown."
local SOUL_IMMOLATION, TEMPERED_SOUL, LONG_CD, SHORT_CD = 1241937, 1246555, 357208, 333
local function told(text) local n = 0 for _, l in ipairs(T.chat) do if l:find(text, 1, true) then n = n + 1 end end return n end
local function hud(text) return ns.hudSection.GetRows(true)[1].right:find(text, 1, true) ~= nil end
-- the line under the state: "" label, its text
local function hudDetail()
	local row = ns.hudSection.GetRows(true)[2]
	return row and row.label == "" and row.value or nil
end
W.spells = { { SOUL_IMMOLATION, 8 }, { LONG_CD, 25 }, { SHORT_CD, 30 } }   -- the spell book
-- Tempered Soul is a talent on now, and its text names Soul Immolation (the stubs call every spell "spell<ID>")
W.traits = { [W.activeTraitConfig] = { nodes = { { entries = { { spell = TEMPERED_SOUL } }, taken = 1 } } } }
W.descriptions = { [TEMPERED_SOUL] = "The cooldown of spell1241937 is reduced by 30 sec and it gains 1 additional charge." }
local NAMED = "You can't change talents while spell1246555 is on cooldown."
W.charges = { [SOUL_IMMOLATION] = { 1, 2, W.now - 1, 30 } }   -- 29 s until the charge is back
W.cooldowns = { [SHORT_CD] = { W.now - 20, 30 } }             -- an ability that has nothing to do with it, back in 10 s
W.loadResult, W.loadError = 0, NAMED
W.log = {}; T.chat = {}
ns.ApplySetup({ configID = 56674545 })
eq(count("talents:"), 1, "held up: asked once")
eq(count("rollback"), 1, "the refused loadout is taken back out of the tree")
check(not W.staged, "nothing stays staged")
eq(told(NAMED), 1, "the game's reason is said")
eq(ns.GetApplyWait(), "held", "the apply waits")
check(hud(ns.L["Waiting for cooldown"]) and not hud("("), "the HUD's state: waiting for a cooldown")
check((hudDetail() or ""):find("spell1241937 (0:29)", 1, true) ~= nil,
	"and under it the ability the talent's text names, with its time")
pass(5); pass(5)
eq(count("talents:"), 1, "the unrelated ability coming back first brings no request")
check((hudDetail() or ""):find("spell1241937 (0:19)", 1, true) ~= nil, "the HUD counts down")
W.casting = true; pass(1)
eq(ns.GetApplyWait(), "held", "a cast of the player's own changes nothing while waiting")
W.casting = false
local redrawn, UpdateHUD = 0, ns.UpdateHUD
ns.UpdateHUD = function() redrawn = redrawn + 1; UpdateHUD() end
pass(1); pass(1)
ns.UpdateHUD = UpdateHUD
check(redrawn >= 2, "the HUD is redrawn as the seconds go")
for _ = 1, 3 do pass(5) end
eq(count("talents:"), 1, "not asked again while Soul Immolation recharges")
check(ns.IsApplying(), "still pending, past the usual timeout")
eq(told(NAMED), 1, "and said once")
W.charges, W.cooldowns = nil, nil; W.loadResult, W.loadError = 2, nil
pass(5)
eq(count("talents:"), 2, "asked again once the charge is back")
W.casting = true; pass(1); talentsLand(); pass(1)
check(not ns.IsApplying(), "and the loadout went in")
eq(W.activeConfig[PRES], 56674545, "recorded")

-- combat in the middle of the wait does not time it out
W.charges = { [SOUL_IMMOLATION] = { 1, 2, W.now - 1, 30 } }
W.loadResult, W.loadError = 0, HELD
W.log = {}
ns.ApplySetup({ configID = 58128473 })
check(hud(ns.L["Waiting for cooldown (%s)"]:format("0:29")) and not hudDetail(),
	"a refusal that names nothing it knows: the first ability back, unnamed, on one line")
pass(5); W.combat = true; pass(5); W.combat = false; fire("PLAYER_REGEN_ENABLED")
pass(5); pass(5); pass(5)
check(ns.IsApplying(), "a fight during the wait: still waiting")
eq(count("talents:"), 1, "and nothing asked")
W.charges = nil; W.loadResult, W.loadError = 2, nil
pass(5)
eq(count("talents:"), 2, "asked once the charge is back")
W.casting = true; pass(1); talentsLand(); pass(1)
check(not ns.IsApplying(), "and it went in")

-- a request right after a refused one is refused too, without a reason and with
-- a red error text (a second click 0.2 s later): the next apply waits a moment
W.charges = { [SOUL_IMMOLATION] = { 1, 2, W.now - 1, 30 } }
W.loadResult, W.loadError = 0, HELD
W.log = {}
ns.ApplySetup({ configID = 56674545 })
eq(count("talents:"), 1, "held up")
ns.ApplySetup({ configID = 56674545 })   -- clicked again at once
eq(count("talents:"), 1, "a new apply does not ask right after the refusal")
pass(1)
eq(count("talents:"), 1, "nor a second later")
pass(1)
eq(count("talents:"), 2, "it asks once the gap is over")
W.charges = nil

-- refused without a reason: put down to timing once, then tries as before
W.loadError = nil
W.log = {}; T.chat = {}
pass(2)
ns.ApplySetup({ configID = 56674545 })
for _ = 1, 8 do pass(2) end
eq(count("talents:"), 5, "one free retry, then the four tries")
check(not ns.IsApplying() and said(ns.L["Could not load the talent loadout: %s"]:format(ns.L["unknown reason"])), "then it gives up")
eq(told(HELD), 0, "no held-up message without a reason")

-- talents that cannot change at all right now: the game says so before any request
W.talentsBlocked = "You can't change talents right now."
W.log = {}; T.chat = {}
ns.ApplySetup({ configID = 56674545 })
for _ = 1, 8 do pass(2) end
eq(count("talents:"), 0, "no loadout request while the game says talents cannot change")
check(not ns.IsApplying() and said(W.talentsBlocked), "it gives up with the game's reason")
W.talentsBlocked = nil

-- held up with nothing recovering: asked every 5 s, for three minutes at most
W.loadError = HELD
W.log = {}; T.chat = {}
ns.ApplySetup({ configID = 56674545 })
check(hud(ns.L["Waiting for cooldown"]) and not hud("("), "nothing recovering: no name, no time")
for _ = 1, 40 do pass(5) end
check(not ns.IsApplying(), "given up after three minutes")
check(said(ns.L["Could not load the talent loadout: %s"]:format(HELD)), "with the game's reason")
eq(count("talents:"), 37, "asked every 5 s meanwhile")
-- a long cooldown is waited for in one go
W.cooldowns = { [LONG_CD] = { W.now - 30, 180 } }   -- 150 s to go
W.log = {}
ns.ApplySetup({ configID = 56674545 })   -- right after the last refusal: asked 5 s later
for _ = 1, 30 do pass(5) end
eq(count("talents:"), 1, "asked once, then nothing for 145 s")
pass(5)
eq(count("talents:"), 2, "and again when that ability is back")
W.cooldowns = nil; W.loadResult, W.loadError = 2, nil
pass(5); W.casting = true; pass(1); talentsLand(); pass(1)
check(not ns.IsApplying(), "and it went in")

-- a held-up loadout belongs to where it was asked for
W.charges = { [SOUL_IMMOLATION] = { 1, 2, W.now - 1, 30 } }
W.loadResult, W.loadError = 0, HELD
W.log = {}
ns.ApplyNow(); flush()   -- the delve's loadout
eq(W.log[1], "talents:58128473", "the delve's loadout, held up")
check(ns.IsApplying(), "waiting")
pretend("world")
eq(count("spec:"), 1, "entering the open world drops it: its own apply goes ahead at once")
W.casting = true; pass(3); specLands(1); pass(1)
check(not ns.IsApplying(), "and finishes")
pass(60)
eq(count("talents:"), 1, "the delve's loadout is not asked for again")
-- the same when the player changes spec by hand
W.log = {}
ns.ApplySetup({ configID = 56310210 })   -- Devastation's pvp loadout, held up
eq(count("talents:"), 1, "held up")
W.specIndex = 2; pass(1)
check(not ns.IsApplying(), "a spec changed by hand drops it")
pass(60)
eq(count("talents:"), 1, "and it is not asked for again")
W.charges = nil; W.loadResult, W.loadError = 2, nil

-- an ability with charges holds the loadout up until every charge is back (at 0/2
-- the game still refused at 1/2), and a talent's own ability counts even when the
-- spell book shows another spell in its place
local IMMOLATION_AURA = 258920
W.spells = { { IMMOLATION_AURA, 8 } }
W.traits[W.activeTraitConfig].nodes[2] = { entries = { { spell = SOUL_IMMOLATION } }, taken = 1 }
W.loadResult, W.loadError = 0, NAMED
W.log = {}
pass(2)
W.charges = { [SOUL_IMMOLATION] = { 0, 2, W.now - 1, 30 } }   -- 29 s to the first charge, 59 s to the second
ns.ApplySetup({ configID = 58128473 })
eq(count("talents:"), 1, "both charges spent: held up")
check((hudDetail() or ""):find("spell1241937 (0:59)", 1, true) ~= nil,
	"counted to the last charge, the ability found among the talents")
pass(30)
eq(count("talents:"), 1, "not asked when the first charge is back")
W.loadResult, W.loadError = 2, nil
pass(30)
eq(count("talents:"), 2, "asked when the second one is")
W.casting = true; pass(1); talentsLand(); pass(1)
check(not ns.IsApplying(), "and it went in")
W.charges = nil

-- a commit of ours whose cast the player interrupts leaves the loadout staged too
W.log = {}
ns.ApplySetup({ configID = 56674545 })
eq(count("talents:"), 1, "asked")
W.casting = true; pass(1)
W.casting = false; W.staged = true
fire("UNIT_SPELLCAST_INTERRUPTED", "player")
fire("CONFIG_COMMIT_FAILED", W.activeTraitConfig)
eq(count("rollback"), 1, "the interrupted loadout is taken back out of the tree")
check(not W.staged, "nothing stays staged")
-- one the player started in the talent window is theirs
W.log = {}; W.staged = true
pass(20)
fire("CONFIG_COMMIT_FAILED", W.activeTraitConfig)
eq(count("rollback"), 0, "a failed commit of the player's own is left alone")
W.staged = false

-- right after a cast the game names the first talent the loadout takes out whose
-- ability is on the global cooldown (Darkness), not what really holds it up
local DARKNESS = 196718
local ON_GCD = "You can't change talents while spell196718 is on cooldown."
W.traits[W.activeTraitConfig].nodes[3] = { entries = { { spell = DARKNESS } }, taken = 1 }
W.spells = { { IMMOLATION_AURA, 8 }, { DARKNESS, 10 } }
W.cooldowns = { [DARKNESS] = { W.now - 0.3, 1.2 } }             -- the global cooldown, 0.9 s left
W.charges = { [SOUL_IMMOLATION] = { 0, 2, W.now - 1, 30 } }
W.loadResult, W.loadError = 0, ON_GCD
W.log = {}; T.chat = {}
ns.ApplySetup({ configID = 56674545 })
eq(count("talents:"), 1, "refused, naming Darkness")
eq(told(ON_GCD), 0, "nothing said for the global cooldown")
check(ns.GetApplyWait() ~= "held", "nor shown as a wait")
W.cooldowns = nil; W.loadError = NAMED
pass(1)
eq(count("talents:"), 1, "not asked before a refusal's gap is over")
pass(1)
eq(count("talents:"), 2, "asked again once the global cooldown is over")
eq(told(NAMED), 1, "now the game names what holds it up, and that is said")
check((hudDetail() or ""):find("spell1241937 (0:57)", 1, true) ~= nil, "and shown, to the last charge")

-- a click on the HUD while waiting asks nothing: it would only be refused again
W.log = {}; T.chat = {}
ns.ApplyNow(); flush(); ns.ApplyNow(); flush()
eq(#W.log, 0, "clicks during the wait ask nothing")
eq(told(NAMED), 0, "and say nothing again")
check(ns.IsHeldUp(), "the wait goes on")
ns.CancelApply()
W.charges = nil; W.loadResult, W.loadError = 2, nil

T.releaseChat()
return T.report("apply [" .. (LOCALE or "enUS") .. "]")
