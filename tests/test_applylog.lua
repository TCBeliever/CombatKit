-- The apply log: what the game said around each request of an apply, kept in
-- the saved variables. The case it was written for: a Demon Hunter whose new
-- loadout drops Soul Immolation (1241937, one charge, 60 s) while it recharges.

local T = dofile(HERE .. "/stubs.lua")
local check, eq, W, fire, flush = T.check, T.eq, T.W, T.fire, T.flush

local SOUL_IMMOLATION, IMMOLATION_AURA = 1241937, 258920
W.activeTraitConfig = 9001
W.loadResult = 2   -- LoadInProgress
-- the talents on now (9001) and in the loadout "M+ AoE" (101): node 1 drops Soul
-- Immolation, node 2 is a choice that flips, node 3 stays
W.traits = {
	[9001] = { nodes = {
		{ entries = { { spell = SOUL_IMMOLATION, replaces = IMMOLATION_AURA } }, taken = 1 },
		{ entries = { { spell = 111 }, { spell = 222 } }, taken = 1 },
		{ entries = { { spell = 333 } }, taken = 1 },
	} },
	[101] = { nodes = {
		{ entries = { { spell = SOUL_IMMOLATION, replaces = IMMOLATION_AURA } } },
		{ entries = { { spell = 111 }, { spell = 222 } }, taken = 2 },
		{ entries = { { spell = 333 } }, taken = 1 },
	} },
}
W.spells = { { IMMOLATION_AURA, 8 }, { SOUL_IMMOLATION, 8 }, { 333, 30 } }   -- the spell book
W.gameMessages = { [1234] = "ERR_TEST_TOKEN" }

CombatKitLoadoutDB = { version = 1, settings = { auto = false }, chars = {} }
T.captureChat()

local CK = T.boot()
local ns = CK.modules.Loadout
fire("PLAYER_ENTERING_WORLD")

local function pass(seconds) W.now = W.now + seconds; flush() end
local function last() local log = ns.db.applyLog or {} return log[#log] end
local function has(record, text)
	for _, l in ipairs(record and record.lines or {}) do if l:find(text, 1, true) then return true end end
	return false
end
local function listeners(event)
	local n = 0
	for _, f in ipairs(T.all) do if f.__events[event] then n = n + 1 end end
	return n
end

check(ns.ApplyLogging(), "run from the source: the apply log is on")
eq(listeners("UI_ERROR_MESSAGE"), 0, "nothing listens before an apply")

-- ---------------------------------------------------------------- the refused loadout
W.now = 100
W.charges = { [SOUL_IMMOLATION] = { 0, 1, 81, 60 } }   -- recharging, 41 s to go
ns.ApplySetup({ configID = 101 })
local r = last()
check(r ~= nil and r.target:find("M+ AoE", 1, true) ~= nil, "a record names the target")
check(r.at ~= nil and r.spec == "Havoc", "with the time and the spec")
check(has(r, "ask talents, try 1"), "the request")
check(has(r, "CanChangeTalents true, true"), "what the game says about changing talents at all")
check(has(r, 'import active: "import9001"') and has(r, 'import target: "import101"'), "both loadouts as import strings")
check(has(r, "node 1: 1241937 spell1241937 [charges 0/1, next in 41.0 of 60.0] r1 (replaces 258920 spell258920) -> none"),
	"the outgoing talent with its charges and the ability it replaces")
check(has(r, "node 2: 111 spell111 r1 -> 222 spell222 r1"), "a choice node that flips")
check(not has(r, "node 3:"), "a node that stays is not listed")
check(has(r, "3 nodes, 2 differ"), "the count")
check(has(r, "recovering: 1241937 spell1241937 [charges 0/1"), "the spell book's recovering abilities")
check(not has(r, "recovering: 258920") and not has(r, "333 spell333 ["), "and only those")
check(has(r, "LoadConfig(101, true) -> true, 2"), "what LoadConfig returned")
check(has(r, "apply: talents, try 1: asked"), "the apply's own debug line, chat messages off")
eq(listeners("UI_ERROR_MESSAGE"), 1, "listening while the apply runs")

fire("UI_ERROR_MESSAGE", 1234, "Can't do that while Soul Immolation recharges")
check(has(r, 'UI_ERROR_MESSAGE 1234 "ERR_TEST_TOKEN" "Can\'t do that while Soul Immolation recharges"'),
	"a red error text, with the name of its global string")
check(has(r, "now: CanChangeTalents"), "and what the game says right after")
fire("UNIT_SPELLCAST_FAILED", "player", "Cast-1", 384255)
check(has(r, "UNIT_SPELLCAST_FAILED 384255 spell384255"), "a cast event of the player")
fire("CONFIG_COMMIT_FAILED", 9001)
check(has(r, "CONFIG_COMMIT_FAILED 9001"), "the failed commit")
check(r.outcome ~= nil and r.outcome:find(ns.L["Talent change"], 1, true) ~= nil, "the outcome is the message the player saw")
check(has(r, "end: "), "and closes the record's request part")
fire("CHAT_MSG_SYSTEM", "late text")
check(has(r, 'CHAT_MSG_SYSTEM "late text"'), "what follows within a few seconds is still logged")
check(ns.ApplyLogOpen(), "still listening")
pass(5)
check(not ns.ApplyLogOpen(), "then the record closes")
eq(listeners("UI_ERROR_MESSAGE"), 0, "and nothing listens any more")
T.raw("UI_ERROR_MESSAGE", 1, "after")
check(not has(r, '"after"'), "a later error is not logged")
check(r.t0 == nil and r.closeAt == nil, "no timing values in the saved record")

-- ---------------------------------------------------------------- secret values
W.charges = { [SOUL_IMMOLATION] = { T.SECRET, T.SECRET, T.SECRET, T.SECRET } }
W.playerAuras = { [SOUL_IMMOLATION] = { expirationTime = W.now + 10 } }
ns.ApplySetup({ configID = 101 })
r = last()
check(has(r, "charges <secret>"), "a secret value is named, not read")
check(has(r, "aura 10.0 left"), "the ability's own aura on the player")
W.casting = false; fire("TRAIT_CONFIG_UPDATED", W.activeTraitConfig)
eq(r.outcome, "ended without a message", "a loadout that went in")
pass(5)
W.charges, W.playerAuras = nil, nil

-- ---------------------------------------------------------------- PvP talents
W.pvpSlots = { { selected = 5001, list = { 5001, 5002 } }, { list = {} }, { list = {} } }
W.pvpTalentInfo = {
	[5001] = { name = "Old", spellID = 7001, selected = true, available = true },
	[5002] = { name = "New", spellID = 7002, available = true },
}
W.cooldowns = { [7001] = { W.now - 5, 30 } }
ns.ApplySetup({ pvp = { 5002 } })
r = last()
check(has(r, 'PvP slot 1: 5001 "Old" spell 7001 spell7001 [cooldown 25.0 of 30.0 left] {selected true, available true} -> 5002 "New"'),
	"the outgoing PvP talent with its ability's cooldown")
check(has(r, "LearnPvpTalent(5002, 1) -> true"), "what LearnPvpTalent returned")
pass(1)
eq(r.outcome, "ended without a message", "the PvP talent went in")
pass(5)
W.cooldowns = nil

-- ---------------------------------------------------------------- bounds
W.activeConfig[577] = 102   -- the other loadout again, so each apply stays pending
for _ = 1, 35 do ns.ApplySetup({ configID = 101 }) end
eq(#ns.db.applyLog, 30, "30 applies kept")
eq(ns.db.applyLog[29].outcome, "replaced by a new apply", "an apply cut short by the next one says so")
ns.CancelApply()
r = last()
check(r.outcome:find("switched off", 1, true) ~= nil, "a cancelled apply says so")
for i = 1, 250 do fire("CHAT_MSG_SYSTEM", "line " .. i) end
eq(#r.lines, 201, "200 lines per apply, and a mark")
check(r.lines[201]:find("dropped", 1, true) ~= nil, "the mark says lines were dropped")
pass(5)

-- ---------------------------------------------------------------- /ckloadout
T.chat = {}
SlashCmdList.CKLOADOUT("log")
check(T.said("30 applies logged"), "/ckloadout log counts the records")
SlashCmdList.CKLOADOUT("clear")
eq(#ns.db.applyLog, 0, "cleared")
SlashCmdList.CKLOADOUT("debug off")
check(T.said("apply log off") and ns.db.debugLog == false, "/ckloadout debug off")
ns.ApplySetup({ configID = 101 })
eq(#ns.db.applyLog, 0, "logging off: nothing logged")
eq(listeners("UI_ERROR_MESSAGE"), 0, "and nothing listens")
ns.CancelApply()
SlashCmdList.CKLOADOUT("log")
check(T.said("logging is off"), "/ckloadout log says logging is off")
SlashCmdList.CKLOADOUT("debug")
check(T.said("apply log on") and ns.ApplyLogging(), "/ckloadout debug toggles it back on")
ns.db.debugLog = nil
do
	-- what the packager does to a @debug@ block (BigWigs packager): comment it out
	local f = assert(io.open(ROOT .. "/Modules/Loadout/ApplyLog.lua", "r"))
	local src = f:read("*a")
	f:close()
	local block = "\n--@debug@\nDEBUG_BUILD = true\n--@end-debug@\n"
	check(src:find(block, 1, true) ~= nil, "DEBUG_BUILD is set inside a @debug@ block")
	local packed = src:gsub("%-%-@debug@", "--[===[@debug@"):gsub("%-%-@end%-debug@", "--@end-debug@]===]")
	check(packed:find("--[===[@debug@\nDEBUG_BUILD = true\n--@end-debug@]===]", 1, true) ~= nil,
		"packaged: the block is a comment, so the release does not log")
	check(loadstring(packed) ~= nil, "packaged: still valid Lua")
end

T.releaseChat()
return T.report("applylog [" .. (LOCALE or "enUS") .. "]")
