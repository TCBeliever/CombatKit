-- The Arena module: the tracker's estimates driven by a fake backend (rounds,
-- teammates changing, externals and who cast them, charges and refreshes,
-- mid-round starts, the self-test), the rows, the settings page.

local T = dofile(HERE .. "/stubs.lua")
local check, eq, W, fire, flush = T.check, T.eq, T.W, T.fire, T.flush
T.captureChat()

CombatKitPartyCDDB = { showSelf = true,   -- the player's own row is a debug setting, off by default; this test wants it
	disabled = { [49039] = true },           -- an older build's switch: Lichborne off
	-- crowd control under a minute is off by default: the scenarios below use these
	picked = { [8122] = true, [179057] = true, [217832] = true } }  -- Psychic Scream, Chaos Nova, Imprison
local CK = T.boot()
check(T.loaded.CombatKit_PartyCD == nil, "off by default: never loaded")
CK.SetModuleEnabled("PartyCD", true)
local AR = CK.modules.PartyCD
check(AR and AR.enabled and AR.IsRunning(), "switched on: loaded and running")
local TR = AR.Tracker
check(AR.db.disabled == nil and AR.db.picked[49039] == false, "an older build's switched-off spell is kept as ticked off")

-- on by default: a cooldown of a minute or more; a shorter one waits to be ticked
local function def(id) return AR.SPELL_BY_ID[id] end
check(AR.DefaultOn(def(22812)) and AR.Picked(def(22812), {}), "Barkskin, 60 s: on by default (a minute counts)")
check(not AR.DefaultOn(def(99)) and not AR.Picked(def(99), {}), "Incapacitating Roar, 30 s: off by default")
check(AR.Picked(def(99), { [99] = true }) and not AR.Picked(def(22812), { [22812] = false }), "a tick either way wins")
-- how an ability is seen and what it is for are two things (Spells.lua)
check(def(198589).seen == "caster" and def(102342).seen == "ally" and def(6940).seen == "otherAlly"
	and def(196718).seen == "allies" and def(408).seen == "enemy" and def(78675).seen == "enemies"
	and def(187650).seen == "enemyLater", "the seven ways of being seen")
check(def(196718).window == 8 and def(187650).fuse == 60, "an area's window, a trap's fuse")
check(def(102342).external and def(6940).external and def(196718).external and not def(198589).external
	and not def(408).external, "externals: on someone else than the caster")
check(def(48707).seen == "ally" and not def(48707).external, "Anti-Magic Shell: may sit on an ally (Spellwarden), not hidden with the externals")
check(AR.SPELL_BY_CAST[199448] == def(6940), "Ultimate Sacrifice's Blessing of Sacrifice is still Blessing of Sacrifice")
check(def(408).onEnemy and def(78675).onEnemy and def(187650).onEnemy and not def(102342).onEnemy, "looked for on the opponents")
check(def(1122).tag == "burst" and AR.HasTag(def(1122), "control") and def(1122).noLearn,
	"Summon Infernal: burst first, control too, and a burst is never learned from")
check(def(49028).tag == "burst" and AR.HasTag(def(49028), "defense"), "Dancing Rune Weapon: burst and defense")
check(AR.UI.GlowOf(def(642)) == "big" and AR.UI.GlowOf(def(22812)) == "defense" and AR.UI.GlowOf(def(408)) == "control"
	and AR.UI.GlowOf(def(13750)) == "burst" and AR.UI.GlowOf(def(29166)) == "other", "the halo's colour follows the main tag, big first")
for _, list in pairs(AR.SPELLS) do
	local last = 0
	local order = { defense = 1, burst = 2, control = 3, other = 4 }
	for _, d in ipairs(list) do
		check(order[d.tag] ~= nil, d.id .. ": a known main tag")
		check(order[d.tag] >= last, d.id .. ": the class's list runs by main tag")
		last = order[d.tag] or last
	end
end
local druidAll = 0
for _, d in ipairs(AR.SPELLS.DRUID) do druidAll = druidAll + 1 end
check(#AR.SpellsFor("DRUID", true) < druidAll, "the short druid cooldowns are not watched until ticked")
for _, d in ipairs(AR.SpellsFor("DRUID", true)) do
	check(AR.BaseCooldown(d) >= 60, "watched by default: " .. d.id .. " has a cooldown of a minute or more")
end
-- Survival Instincts with two charges from the start, as the charge scenarios below
-- were written (the data gives one; a passive or a talent adds the second)
AR.TalentData.base[61336].charges = 2

-- a backend that reports what the test says
local fake = { watches = {}, started = false }
function fake.Start(cb) fake.cb = cb; fake.started = true end
function fake.Stop() fake.started = false end
function fake.SetWatch(unit, defs) fake.watches[unit] = defs end
AR.UseBackend(fake)

local function shown(unit, id, at, initial) W.now = at; fake.cb.Shown(unit, id, at, initial) end
local function hidden(unit, id, at) W.now = at; fake.cb.Hidden(unit, id, at) end
local function expired(unit, id, at) W.now = at; fake.cb.Expired(unit, id, at) end
local function state(unit, id, at)
	W.now = at or W.now
	local t = TR.Get(unit)
	local e = t and t.spells[id]
	if not e then return "none" end
	return TR.State(e, W.now)
end

-- ---------------------------------------------------------------- out in the world: nothing
check(not fake.started, "outside an arena the backend is not started")
check(next(AR.UI.Rows()) == nil or not AR.UI.Rows().player:IsShown(), "no row outside an arena")

-- ---------------------------------------------------------------- into an arena: a druid and a priest
W.inInstance, W.instanceType = true, "arena"
W.units.player = { friendly = true }
W.units.party1 = { friendly = true, class = "DRUID", guid = "Player-1-DRUID" }
W.units.party2 = { friendly = true, class = "PRIEST", guid = "Player-1-PRIEST" }
W.now = 0
fire("PLAYER_ENTERING_WORLD")
check(fake.started, "entering an arena starts the backend")
check(fake.watches.party1 and #fake.watches.party1 == #AR.FriendlyDefs(AR.SpellsFor("DRUID", true)), "every druid buff is watched on party1")
check(fake.watches.player and #fake.watches.player == #AR.FriendlyDefs(AR.SpellsFor("DEMONHUNTER", true)), "the player's own row is watched too")
check(fake.watches.arena1 and #fake.watches.arena1 > 0, "the opponents are watched for the team's crowd control")
eq(state("party1", 22812), "ready", "entering: everything is ready, the gates reset it anyway")
-- a teammate who turns up in the roster a few seconds later, still before the gates: ready too
W.units.party2 = nil
fire("GROUP_ROSTER_UPDATE")
check(TR.Get("party2") == nil, "party2 not there yet")
W.units.party2 = { friendly = true, class = "PRIEST", guid = "Player-1-PRIEST" }
fire("GROUP_ROSTER_UPDATE")
eq(state("party2", 33206), "ready", "arriving before the gates: ready, not unknown")

W.matchState = 3
fire("PVP_MATCH_STATE_CHANGED")
eq(state("party1", 22812), "ready", "the round starts: everything is ready")
eq(state("party2", 33206), "ready", "for everyone")
AR.UI.Refresh(0)
check(AR.UI.Rows().party1:IsShown() and AR.UI.Rows().party2:IsShown() and AR.UI.Rows().player:IsShown(), "three rows up")

-- ---------------------------------------------------------------- a self buff: Barkskin
shown("party1", 22812, 10)
eq(state("party1", 22812), "active", "the buff is drawn: active")
hidden("party1", 22812, 18)
local s, readyAt = state("party1", 22812, 18)
eq(s, "cooling", "the buff is gone: cooling")
eq(readyAt, 70, "ready again 60 s after it appeared, not after it ended")
eq(state("party1", 22812, 69.9), "cooling", "still cooling just before")
eq(state("party1", 22812, 70.1), "ready", "ready when the cooldown has run")

-- ---------------------------------------------------------------- charges: Survival Instincts, two of them
local s1, _, left = state("party1", 61336, 100)
eq(s1, "ready", "two charges, none used: ready")
eq(left, 2, "both charges left")
shown("party1", 61336, 100)
expired("party1", 61336, 106)
hidden("party1", 61336, 106)
s1, _, left = state("party1", 61336, 107)
eq(s1, "ready", "one charge used, one left: still ready")
eq(left, 1, "one left")
eq(TR.KnownDuration(61336), 6, "the buff's length is learned from its full course")
shown("party1", 61336, 120)
hidden("party1", 61336, 126)
s1, readyAt, left = state("party1", 61336, 127)
eq(s1, "cooling", "both charges used: cooling")
eq(left, 0, "none left")
eq(readyAt, 280, "the first charge is back 180 s after the first use")
s1, _, left = state("party1", 61336, 281)
eq(s1, "ready", "one charge back")
eq(left, 1, "and counted")
eq(state("party1", 61336, 461), "ready", "the second one recharges after the first: 280 + 180")
local _, _, left2 = state("party1", 61336, 461)
eq(left2, 2, "both back")

-- a refresh: the second use while the first buff is still up leaves no edge, but a longer buff
W.matchState = 3; fire("PVP_MATCH_STATE_CHANGED")   -- a new round, everything ready
shown("party1", 61336, 500)
expired("party1", 61336, 509)   -- 9 s, the learned length is 6: refreshed at 503
hidden("party1", 61336, 509)
s1, _, left = state("party1", 61336, 510)
eq(left, 0, "the refresh counted as the second use")
eq(s1, "cooling", "so both charges are spent")

-- ---------------------------------------------------------------- externals: Pain Suppression on the druid
W.matchState = 3; fire("PVP_MATCH_STATE_CHANGED")
shown("party1", 33206, 600)
eq(state("party2", 33206), "active", "the only priest gets the credit")
eq(state("party1", 33206), "none", "the druid has no such ability")
hidden("party1", 33206, 608)
eq(state("party2", 33206, 608), "cooling", "and the cooldown")
check(not TR.Get("party2").spells[33206].ambiguous, "unambiguous")

-- the player's own cast of an external it has is the player's, not a teammate's
W.units.player = { friendly = true, class = "PRIEST", guid = "Player-0-ME" }
fire("GROUP_ROSTER_UPDATE")
W.matchState = 3; fire("PVP_MATCH_STATE_CHANGED")
W.now = 700
fire("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-1", 33206)
shown("party1", 33206, 700.2)
eq(state("player", 33206), "active", "the player cast it a moment ago: the player's")
eq(state("party2", 33206, 700.2), "ready", "the other priest is left alone")
hidden("party1", 33206, 708)

-- no cast of ours: the player is never a candidate, the one priest teammate is
shown("party1", 33206, 900)
eq(state("party2", 33206, 900), "active", "the teammate's")
eq(state("player", 33206, 900), "ready", "not the player's: the player's casts are known")
hidden("party1", 33206, 908)

-- two priest teammates: both are credited and marked
W.units.player = { friendly = true, class = "DEMONHUNTER", guid = "Player-0-ME" }
W.units.party1 = { friendly = true, class = "PRIEST", guid = "Player-1-PRIEST-A" }
fire("GROUP_ROSTER_UPDATE")
W.matchState = 3; fire("PVP_MATCH_STATE_CHANGED")
shown("player", 33206, 950)
check(TR.Get("party1").spells[33206].ambiguous and TR.Get("party2").spells[33206].ambiguous, "two candidates: both marked")
eq(state("party1", 33206, 950), "active", "both active")
eq(state("party2", 33206, 950), "active", "both active, the other one")
hidden("player", 33206, 958)

-- a dead candidate did not cast it
W.units.party2.dead = true
W.matchState = 3; fire("PVP_MATCH_STATE_CHANGED")
shown("player", 33206, 1000)
eq(state("party1", 33206, 1000), "active", "the living priest")
eq(state("party2", 33206, 1000), "ready", "not the dead one")
check(not TR.Get("party1").spells[33206].ambiguous, "and no mark")
hidden("player", 33206, 1008)
W.units.party2.dead = nil

-- a candidate under a stun, a fear or a disorient did not cast it: the game's loss of
-- control, priority 5 (a root is 1 and stops no cast)
local loc = {}
C_LossOfControl = {
	GetActiveLossOfControlDataCountByUnit = function(unit) return loc[unit] and #loc[unit] or 0 end,
	GetActiveLossOfControlDataByUnit = function(unit, i) return loc[unit] and loc[unit][i] end,
}
local function control(unit, priority, at)
	loc[unit] = priority and { { priority = priority, displayType = 2 } } or nil
	W.now = at; fire(priority and "LOSS_OF_CONTROL_ADDED" or "LOSS_OF_CONTROL_UPDATE", unit, 1)
end
W.matchState = 3; fire("PVP_MATCH_STATE_CHANGED")
control("party2", 5, 1020)
shown("player", 33206, 1021)
eq(state("party1", 33206, 1021), "active", "the priest who could act")
eq(state("party2", 33206, 1021), "ready", "not the stunned one")
check(not TR.Get("party1").spells[33206].ambiguous, "and no mark")
hidden("player", 33206, 1029)
control("party2", nil, 1030)
check(not TR.Controlled("party2", 1030), "the stun is over")
W.matchState = 3; fire("PVP_MATCH_STATE_CHANGED")
control("party2", 1, 1040)
shown("player", 33206, 1041)
check(TR.Get("party1").spells[33206].ambiguous and TR.Get("party2").spells[33206].ambiguous, "rooted: still a candidate")
hidden("player", 33206, 1049)
control("party2", nil, 1050)
W.matchState = 3; fire("PVP_MATCH_STATE_CHANGED")
control("party2", 5, 1060)
shown("player", 33206, 1060.1)
check(TR.Get("party2").spells[33206].ambiguous, "stunned the same moment: may have cast it just before, still a candidate")
hidden("player", 33206, 1068)
W.matchState = 3; fire("PVP_MATCH_STATE_CHANGED")
control("party1", 5, 1070)
shown("player", 33206, 1071)
check(TR.Get("party1").spells[33206].ambiguous and TR.Get("party2").spells[33206].ambiguous,
	"both under control: the reading is off somewhere, both stay the candidates")
hidden("player", 33206, 1079)
control("party1", nil, 1080); control("party2", nil, 1080)
check(AR.CastableUnderControl(AR.SPELL_BY_ID[22812]) and not AR.CastableUnderControl(AR.SPELL_BY_ID[33206]),
	"Barkskin can be cast stunned, Pain Suppression cannot (the game's data)")
C_LossOfControl = nil

-- Blessing of Sacrifice cannot be on its caster: the holder is excluded
W.units.party1 = { friendly = true, class = "PALADIN", guid = "Player-1-PAL" }
W.units.party2 = { friendly = true, class = "PALADIN", guid = "Player-1-PAL2" }
fire("GROUP_ROSTER_UPDATE")
W.matchState = 3; fire("PVP_MATCH_STATE_CHANGED")
shown("party1", 6940, 1100)
eq(state("party2", 6940, 1100), "active", "the other paladin cast it")
eq(state("party1", 6940, 1100), "ready", "not the one wearing it")
hidden("party1", 6940, 1112)

-- an area buff lands on several allies within a frame: one use
shown("party1", 1022, 1200)
shown("party2", 1022, 1200.05)
check(TR.Get("party1").spells[1022].ambiguous, "two paladins could have cast Blessing of Protection")
local uses = #TR.Get("party1").spells[1022].uses
eq(uses, 1, "seen twice, one use")

-- ---------------------------------------------------------------- a teammate arrives mid round: unknown until seen
W.units.party1 = { friendly = true, class = "DRUID", guid = "Player-2-DRUID" }
fire("GROUP_ROSTER_UPDATE")
eq(state("party1", 22812, 1300), "unknown", "a new teammate: nothing known")
eq(state("party2", 642, 1300), "ready", "the one who stayed keeps his state")
shown("party1", 22812, 1310, true)
eq(state("party1", 22812, 1310), "active", "already up as we began to look: active")
hidden("party1", 22812, 1318)
eq(state("party1", 22812, 1318), "unknown", "but its start is unknown, so still unknown afterwards")
shown("party1", 22812, 1400)
hidden("party1", 22812, 1408)
eq(state("party1", 22812, 1408), "cooling", "the first use seen from the start: known from here")

-- a single charge used again sooner than the estimate: the estimate was too long
W.matchState = 3; fire("PVP_MATCH_STATE_CHANGED")
shown("party1", 22812, 1500); hidden("party1", 22812, 1508)
shown("party1", 22812, 1550); hidden("party1", 22812, 1558)
eq(TR.Get("party1").spells[22812].cd, 50, "two uses 50 s apart: the cooldown is at most 50")
local _, ra = state("party1", 22812, 1558)
eq(ra, 1600, "and the display follows")

-- what must not correct the estimate
W.units.player = { friendly = true, class = "DEMONHUNTER", guid = "Player-0-ME" }
W.units.party1 = { friendly = true, class = "DEMONHUNTER", guid = "Player-1-DH" }
W.units.party2 = { friendly = true, class = "MAGE", guid = "Player-1-MAGE" }
fire("GROUP_ROSTER_UPDATE")
W.matchState = 3; fire("PVP_MATCH_STATE_CHANGED")
-- an area buff: allies walk in and out of Darkness for 8 s; one use, no correction
shown("party2", 196718, 1700)
shown("player", 196718, 1703)
hidden("player", 196718, 1705)
shown("player", 196718, 1706)
eq(#TR.Get("party1").spells[196718].uses, 1, "allies walking in and out of an area buff: one use")
eq(TR.Get("party1").spells[196718].cd, 300, "and the estimate untouched")
shown("party2", 196718, 1720)
eq(#TR.Get("party1").spells[196718].uses, 2, "a sighting after the effect has run: another use")
eq(TR.Get("party1").spells[196718].cd, 300, "which still corrects nothing")
-- a talent may add a charge: two close uses are two charges, not a shorter cooldown
shown("party1", 198589, 1800); hidden("party1", 198589, 1810)
shown("party1", 198589, 1830); hidden("party1", 198589, 1840)
eq(TR.Get("party1").spells[198589].cd, 60, "Blur twice in 30 s: a second charge, the estimate stays")
eq(TR.Get("party1").spells[198589].charges, 2, "and the teammate is known to have two charges")
local bs, bReady, bLeft = state("party1", 198589, 1841)
check(bs == "cooling" and bLeft == 0 and bReady == 1860, "both spent: cooling until the first comes back")
bs, bReady, bLeft = state("party1", 198589, 1861)
check(bs == "ready" and bLeft == 1, "the first charge back: ready with one, the second still recharging")
-- a reset can bring an ability back: Ice Block twice says nothing about its cooldown
shown("party2", 45438, 1900); hidden("party2", 45438, 1910)
shown("party2", 45438, 1930); hidden("party2", 45438, 1940)
eq(TR.Get("party2").spells[45438].cd, 240, "Ice Block twice: the estimate stays")
-- two of a class: a use that may be either's corrects neither
W.units.party2 = { friendly = true, class = "DEMONHUNTER", guid = "Player-1-DH2" }
fire("GROUP_ROSTER_UPDATE")
W.matchState = 3; fire("PVP_MATCH_STATE_CHANGED")
shown("player", 196718, 2000)
shown("player", 196718, 2020)
check(TR.Get("party1").spells[196718].ambiguous and TR.Get("party2").spells[196718].ambiguous, "either demon hunter's Darkness")
eq(TR.Get("party1").spells[196718].cd, 300, "neither estimate is touched")
eq(TR.Get("party2").spells[196718].cd, 300, "neither estimate is touched, the other one")

-- ---------------------------------------------------------------- the self-test
W.units.player = { friendly = true, class = "DEMONHUNTER", guid = "Player-0-ME" }
W.units.party1 = { friendly = true, class = "DRUID", guid = "Player-3-DRUID" }
W.units.party2 = { friendly = true, class = "PRIEST", guid = "Player-3-PRIEST" }
fire("GROUP_ROSTER_UPDATE")
W.matchState = 3; fire("PVP_MATCH_STATE_CHANGED")
W.now = 2000
fire("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-2", 198589)
shown("player", 198589, 2000.02)
check(not TR.failed, "the player's own buff showed after the cast: fine")
hidden("player", 198589, 2010)
W.now = 2100; fire("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-3", 198589)
W.now = 2101; TR.SelfTestCheck(2101)
check(not TR.failed, "one miss is not yet a failure")
W.now = 2200; fire("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-4", 198589)
W.now = 2201; TR.SelfTestCheck(2201)
check(TR.failed, "two misses in a row: detection is broken")
check(T.said(CK.L["Party CD: detection failed, the rows are dimmed."]), "and the player is told")
AR.UI.Refresh(2201)
check(AR.UI.Rows().party1.warn:IsShown(), "the rows carry the warning")
W.now = 2300; fire("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-5", 198589)
shown("player", 198589, 2300.02)
check(not TR.failed, "a buff that shows again clears it")

-- ---------------------------------------------------------------- crowd control: debuffs on the opponents
local function uses(unit, id) return #TR.Get(unit).spells[id].uses end
shown("arena1", 5211, 2310)
eq(state("party1", 5211), "active", "Mighty Bash on arena1: the druid's, glowing while it holds")
eq(uses("party1", 5211), 1, "one use, the only one who has it")
check(not TR.Get("party1").spells[5211].ambiguous, "and nobody else could have")
hidden("arena1", 5211, 2314)
shown("arena1", 8122, 2320)
shown("arena2", 8122, 2320.02)
eq(uses("party2", 8122), 1, "Psychic Scream on two opponents at once: one use")
-- the player's own crowd control is the player's, even one that lands later
W.now = 2340; fire("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-6", 207684)
shown("arena1", 207684, 2342.5)
eq(uses("player", 207684), 1, "Sigil of Misery bursting 2.5 s after the cast: still the player's own")
-- a cast under another ID: the PvP talent's Imprison is still the player's own
W.now = 2345; fire("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-6b", 221527)
shown("arena3", 217832, 2345.1)
eq(uses("player", 217832), 1, "Imprison cast as 221527: recognised as the player's own")
hidden("arena3", 217832, 2346)
TR.RoundStart()
-- a demon hunter teammate: the player's own Imprison is not theirs
W.units.party2 = { friendly = true, class = "DEMONHUNTER", guid = "Player-4-DH" }
fire("GROUP_ROSTER_UPDATE")
W.now = 2350; fire("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-7", 217832)
shown("arena2", 217832, 2350.1)
eq(uses("party2", 217832), 0, "the player cast Imprison: no use for the teammate")
eq(uses("player", 217832), 1, "the player's own instead")
shown("arena3", 217832, 2380)
eq(uses("party2", 217832), 1, "an Imprison the player did not cast: the other demon hunter's")
AR.db.showSelf = false; AR.Apply()
W.now = 2400; fire("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-8", 179057)
shown("arena1", 179057, 2400.1)
eq(uses("party2", 179057), 0, "the player's own row hidden: their Chaos Nova is still not the teammate's")
AR.db.showSelf = true; AR.Apply()
W.units.party2 = { friendly = true, class = "PRIEST", guid = "Player-3-PRIEST" }
fire("GROUP_ROSTER_UPDATE")
W.matchState = 3; fire("PVP_MATCH_STATE_CHANGED")

-- ---------------------------------------------------------------- the rows
AR.UI.Refresh(2300.02)
local row = AR.UI.Rows().party1
eq(#TR.Get("party1").order, #AR.SpellsFor("DRUID", true), "one icon per druid ability")
check(row.icons[1] and row.icons[1]:IsShown(), "icons are shown")
-- the PvP trinket leads the row, from the game's own cooldown data
local n = #TR.Get("party1").order
check(row.icons[n + 1]:IsShown() and not row.icons[n + 2], "one more icon than abilities: the trinket")
eq(row.icons[1].tex.__texture, nil, "mock textures keep no file name")   -- the texture mock records nothing; the request does
check(W.log[#W.log]:find("trinket:", 1, true) ~= nil, "the trinket icon asked the game for party1's duration")
-- the icon is the spell the game says the teammate carries: the medallion, or a racial
local asked = {}
local realTexture = C_Spell.GetSpellTexture
C_Spell.GetSpellTexture = function(id) asked[#asked + 1] = id; return realTexture(id) end
AR.UI.Refresh(2300.03)
local function askedFor(id) for _, x in ipairs(asked) do if x == id then return true end end return false end
check(askedFor(336126), "nothing said yet: the medallion's icon")
W.trinketSpell = { party1 = 59752 }
asked = {}
fire("ARENA_CROWD_CONTROL_SPELL_UPDATE", "party1")
AR.UI.Refresh(2300.04)
check(askedFor(59752), "the server named a racial for party1: its icon (the player's row still shows the medallion)")
W.trinketSpell = nil
C_Spell.GetSpellTexture = realTexture
AR.db.trinket = false; AR.Apply()
check(not row.icons[n + 1]:IsShown(), "trinket off: only the abilities")
AR.db.trinket = true; AR.Apply()
AR.db.externals = false
AR.Apply()
eq(#TR.Get("party1").order, #AR.SpellsFor("DRUID", false), "externals off: only the self buffs")
AR.db.externals = true
AR.Apply()
AR.db.showSelf = false
AR.Apply()
check(TR.Get("player") == nil, "the player's row switched off")
AR.db.showSelf = true
AR.Apply()
check(TR.Get("player") ~= nil, "and back")

-- a loose row, unlocked, dragged: the redraws leave it alone, and the drop is saved
AR.UI.SetLocked(false)
local loose = AR.UI.Rows().party2
local before = loose.__point
loose:GetScript("OnDragStart")(loose)
check(loose.moving, "dragging")
AR.UI.Refresh(2300.05)
check(loose.__point == before, "a redraw while it is dragged does not put it back")
loose.__rect = { 300, 400, 120, 32 }
loose:GetScript("OnDragStop")(loose)
local saved = AR.db.rows.party2
check(not loose.moving and saved.point == "TOPLEFT" and saved.relPoint == "BOTTOMLEFT" and saved.x == 300 and saved.y == 432,
	"dropped: its top left corner saved, from the screen's bottom left")
AR.UI.Refresh(2300.06)
check(loose.__point[1] == "TOPLEFT" and loose.__point[4] == 300 and loose.__point[5] == 432, "and the next redraw keeps it there")
AR.db.grow = "up"
loose:GetScript("OnDragStart")(loose)
loose:GetScript("OnDragStop")(loose)
check(AR.db.rows.party2.point == "BOTTOMLEFT" and AR.db.rows.party2.y == 400, "growing up: its bottom left corner is what is saved")
AR.db.grow = "right"
AR.UI.ResetPositions()
AR.UI.SetLocked(true)

-- hung on the party frame that shows the unit
eq(row.__point[2], UIParent, "no party frame around: the row sits at its own position")
local member = CreateFrame("Button", "CompactPartyFrameMember1")
member:SetAttribute("unit", "party1")
AR.Apply()
check(row.__point[1] == "TOPLEFT" and row.__point[2] == member and row.__point[3] == "TOPRIGHT" and row.__point[4] == 4,
	"party1's row hangs on the right of its frame, 4 px away")
AR.db.side = "LEFT"; AR.Apply()
check(row.__point[1] == "TOPRIGHT" and row.__point[3] == "TOPLEFT" and row.__point[4] == -4, "on the left when asked")
local step = AR.db.iconSize + AR.db.spacing
check(row.icons[2].__point[1] == "TOPRIGHT" and row.icons[2].__point[4] == -step, "a left-hand row runs away from the frame: leftwards")
AR.db.side = "RIGHT"; AR.db.maxPerRow = 2; AR.Apply()
check(row.icons[2].__point[1] == "TOPLEFT" and row.icons[2].__point[4] == step, "a right-hand row runs rightwards")
check(row.icons[3].__point[1] == "TOPLEFT" and row.icons[3].__point[4] == 0 and row.icons[3].__point[5] == -step, "down: the next line under the first")
AR.db.grow = "up"; AR.Apply()
check(row.__point[1] == "BOTTOMLEFT" and row.__point[3] == "BOTTOMRIGHT", "up: lined up with the frame's bottom")
check(row.icons[3].__point[1] == "BOTTOMLEFT" and row.icons[3].__point[5] == step, "and the next line above the first")
AR.db.grow = "center"; AR.Apply()
check(row.__point[1] == "LEFT" and row.__point[3] == "RIGHT", "centred: on the frame's middle")
AR.db.side = "TOP"; AR.db.grow = "up"; AR.Apply()
check(row.__point[1] == "BOTTOMLEFT" and row.__point[3] == "TOPLEFT" and row.__point[5] == 4, "above: up is not a choice there, so from the left end")
check(row.icons[3].__point[1] == "BOTTOMLEFT" and row.icons[3].__point[5] == step, "and the lines stack away from the frame, upwards")
AR.db.grow = "left"; AR.Apply()
check(row.__point[1] == "BOTTOMRIGHT" and row.__point[3] == "TOPRIGHT", "left: from the frame's right end")
check(row.icons[2].__point[1] == "BOTTOMRIGHT" and row.icons[2].__point[4] == -step, "the icons going left")
AR.db.side = "BOTTOM"; AR.db.grow = "center"; AR.Apply()
check(row.__point[1] == "TOP" and row.__point[3] == "BOTTOM", "below, centred: under the frame's middle")
check(row.icons[1].__point[1] == "TOP" and math.abs(row.icons[1].__point[4] + step / 2) < 0.01, "every line centred on the row")
check(row.icons[3].__point[5] == -step, "the lines stack downwards, away from the frame")
eq(AR.UI.GrowFor("LEFT", "right"), "down", "a grow that does not fit the side: its first one")
eq(AR.UI.GrowFor("BOTTOM", "center"), "center", "one that fits: kept")
AR.db.side, AR.db.grow, AR.db.maxPerRow = "RIGHT", "down", 8
AR.db.side = "BOTTOM"; AR.db.offsetAlong = 6; AR.Apply()
check(row.__point[1] == "TOPLEFT" and row.__point[3] == "BOTTOMLEFT" and row.__point[4] == 6 and row.__point[5] == -4, "below: the offset goes down, the shift goes along")
AR.db.side = "RIGHT"; AR.db.offsetAlong = 0
AR.db.maxPerRow = 2; AR.Apply()
check(row.icons[3].__point[4] == 0 and row.icons[3].__point[5] == -(AR.db.iconSize + AR.db.spacing), "more icons than fit a row: the next line")
AR.db.maxPerRow = 8
member:Hide(); AR.Apply()
eq(row.__point[2], UIParent, "a frame that is hidden: back to the loose position")
member:Show()
member:SetAttribute("unit", "raid2")
W.units.raid2 = W.units.party1
AR.Apply()
eq(row.__point[2], member, "a frame naming the same player by another token counts, by GUID")
W.units.raid2 = nil
member:SetAttribute("unit", "party1")
AR.db.attach = false; AR.Apply()
eq(row.__point[2], UIParent, "attach off: loose")
AR.db.attach = true; AR.Apply()

-- unlocked: sample rows, a loose one draggable with a background
AR.SetLocked(false)
check(not AR.IsLocked() and AR.UI.Rows().player.bg:IsShown(), "unlocked: a loose row shows its background")
check(not AR.UI.Rows().party1.bg:IsShown(), "an attached one does not")
AR.SetLocked(true)

-- ---------------------------------------------------------------- settings page
SlashCmdList.COMBATKIT("")
local main = CK.Options.GetFrame()
check(main and main:IsShown(), "the settings window opens")
main.tabs.PartyCD:Click()
local body = main.bodies.PartyCD
local page = body.pages.main
check(page and page.iconSize and page.externals, "the Party CD page is built")
check(page:IsShown() and not body.pages.spells:IsShown(), "it opens on the display page")
-- the debug page: the player's own row
CK.Options.Select("PartyCD", "debug")
check(body.pages.debug:IsShown() and body.pages.debug.showSelf:GetChecked(), "the debug page shows the own-row switch, on for this test")
body.pages.debug.showSelf:Click()
eq(AR.db.showSelf, false, "the checkbox writes the setting")
body.pages.debug.showSelf:Click()
-- the spells page: a class, its groups, a spell switched off
CK.Options.Select("PartyCD", "spells")
local spells = body.pages.spells
check(spells:IsShown() and spells.class == "DEMONHUNTER", "the spells page opens on the player's class")
local function shownRows()
	local out = {}
	for _, c in ipairs(spells.abilities) do if c:IsShown() then out[#out + 1] = c end end
	return out
end
eq(#shownRows(), #AR.SPELLS.DEMONHUNTER, "one row per demon hunter ability")
check(spells.headers.defense:IsShown() and spells.headers.burst:IsShown() and spells.headers.control:IsShown()
	and spells.headers.other:IsShown(), "the four categories, each with its own box (Spectral Sight is other)")
check(spells.trinket == nil, "no trinket box here: it is on the display page")
-- every class fits the window: the categories share two columns, none runs below the body
for _, class in ipairs({ "DEATHKNIGHT", "DEMONHUNTER", "DRUID", "EVOKER", "HUNTER", "MAGE", "MONK", "PALADIN",
	"PRIEST", "ROGUE", "SHAMAN", "WARLOCK", "WARRIOR" }) do
	spells.class = class; CK.Options.Refresh()
	local lowest = 0
	for _, c in ipairs(shownRows()) do
		local point = { c:GetPoint() }   -- ("TOPLEFT", x, y) as the page sets it
		lowest = math.min(lowest, point[#point])
	end
	check(lowest >= -300, class .. ": the lowest ability at " .. lowest .. ", inside the window")
end
spells.class = "DEMONHUNTER"; CK.Options.Refresh()
spells.class = "DRUID"; CK.Options.Refresh()
eq(#shownRows(), #AR.SPELLS.DRUID, "another class: its rows")
local barkskin
for _, c in ipairs(shownRows()) do if c.def.id == 22812 then barkskin = c end end
check(barkskin and barkskin:GetChecked(), "Barkskin is watched")
barkskin:Click()
check(AR.db.picked[22812] == false, "unticked: switched off")
check(TR.Get("party1") == nil or TR.Get("party1").spells[22812] == nil, "and no longer carried by the druid teammate")
barkskin:Click()
check(AR.db.picked[22812] == nil, "ticked again: back to the default, nothing kept")
check(not spells.headers.control:GetChecked(), "the crowd control box: not all on, the short ones wait to be ticked")
spells.headers.control:Click()
check(AR.db.picked[99] == true and AR.db.picked[5211] == nil and AR.db.picked[22812] == nil,
	"the category box: every druid crowd control on, the short ones kept as ticked, the rest left alone")
check(spells.headers.control:GetChecked(), "and the box shows it")
spells.headers.control:Click()
check(AR.db.picked[5211] == false and AR.db.picked[99] == nil, "unticked: every one off, the short ones back to their default")
spells.headers.control:Click()
check(spells.headers.other:IsShown(), "the other category for the druid (Innervate)")
CK.Options.Select("PartyCD", "main")
page.unlock:Click()
check(not AR.IsLocked(), "unlocked from the page")
main:Hide()
check(AR.IsLocked(), "closing the window locks the rows again")

-- ---------------------------------------------------------------- leaving the arena
W.inInstance, W.instanceType = false, "none"
fire("PLAYER_ENTERING_WORLD")
check(not fake.started, "leaving stops the backend")
check(TR.Get("party1") == nil, "and clears the teammates")
AR.UI.Refresh()
check(not AR.UI.Rows().party1:IsShown(), "no row outside")

-- the test switch: sample rows out here, with one icon of each look
SlashCmdList.COMBATKIT("")
main.tabs.PartyCD:Click()
page.test:Click()
check(AR.IsTesting() and AR.UI.Rows().party1:IsShown() and AR.UI.Rows().player:IsShown(), "test: the rows show in the world")
check(AR.IsLocked() and not AR.UI.Rows().player.bg:IsShown(), "without the drag background: still locked")
local sample = AR.UI.Rows().player
check(not sample.icons[1].halo:IsShown() and not sample.icons[1].mark:IsShown(), "the trinket leads the samples, plain")
check(sample.icons[2].halo:IsShown() and sample.icons[2].pulse:IsPlaying() and sample.icons[4].mark:IsShown(), "one active and breathing, one unknown among the samples")
check(not sample.icons[3].halo:IsShown(), "a cooling one has no glow")
-- the samples are the player's own specialization (havoc): vengeance's Metamorphosis is not among them
local want = AR.db.trinket and 1 or 0
for _, def in ipairs(AR.SpellsFor("DEMONHUNTER", AR.Selection())) do
	if not def.specs or def.specs[577] then want = want + 1 end
end
local shownIcons = 0
for _, icon in ipairs(sample.icons) do if icon:IsShown() then shownIcons = shownIcons + 1 end end
eq(shownIcons, want, "sample icons: the trinket and the havoc abilities only")
check(want < #AR.SpellsFor("DEMONHUNTER", AR.Selection()) + 1, "which is fewer than the whole class list")

-- the status command and the log
SlashCmdList.CKPARTYCD("")
check(T.said("not in arena"), "/ckpartycd says where we are")
SlashCmdList.CKPARTYCD("log")
check(T.said("log lines"), "/ckpartycd log counts the lines")
check(#AR.db.log > 0, "the match left a log in the saved variables")
SlashCmdList.CKPARTYCD("clear")
eq(#AR.db.log, 0, "cleared")
main:Hide()
check(not AR.IsTesting(), "closing the window ends the test")
AR.UI.Refresh()
check(not AR.UI.Rows().player:IsShown(), "and the rows are gone again")

-- ---------------------------------------------------------------- inspect: the talents' say
-- reading a talent's text
local IN = AR.Inspect
local byName = { spell22812 = AR.SPELL_BY_ID[22812], spell61336 = AR.SPELL_BY_ID[61336] }
local function parsed(text) return IN.Parse(text, byName) end
local r = parsed("Reduces the cooldown of spell22812 by 15 sec.")
check(#r == 1 and r[1].def.id == 22812 and r[1].sec == -15, "English: seconds off a named ability")
r = parsed("spell22812's cooldown is reduced by 20%.")
check(#r == 1 and r[1].pct == 20 and r[1].sec == 0, "English: a share off")
r = parsed("使spell22812的冷卻時間縮短30秒。")
check(#r == 1 and r[1].sec == -30, "Chinese: seconds off")
r = parsed("spell61336的冷卻時間縮短20%。")
check(#r == 1 and r[1].def.id == 61336 and r[1].pct == 20, "Chinese: a share off")
r = parsed("spell61336 gains an additional charge.")
check(#r == 1 and r[1].charges == 1, "an extra charge")
r = parsed("spell61336額外獲得1次充能。")
check(#r == 1 and r[1].charges == 1, "an extra charge, Chinese")
check(#parsed("Each time you take damage, the cooldown of spell22812 is reduced by 1 sec.") == 0, "a one-off reduction is not a modifier")
check(#parsed("Reduces the cooldown of spell999 by 10 sec.") == 0, "an ability not watched: nothing")
r = parsed("Reduces the cooldown of spell22812 and spell61336 by 10 sec.")
check(#r == 2 and r[1].sec == -10 and r[2].sec == -10, "two named abilities in one sentence: both")
r = parsed("Increases the cooldown of spell22812 by 30 sec.")
check(#r == 1 and r[1].sec == 30, "a longer cooldown")
r = parsed("Reduces the cooldown of spell22812 by 1.5 sec. Deals 10 damage.")
check(#r == 1 and r[1].sec == -1.5, "a decimal survives the sentence cut")
r = parsed("Reduces the cooldown of spell22812 by 1 min.")
check(#r == 1 and r[1].sec == -60, "minutes")

-- into an arena again: a druid with talents, the player with their own; the
-- talent spells are made up, and the data table below says what they do
W.inInstance, W.instanceType = true, "arena"
W.units.party1 = { friendly = true, class = "DRUID", guid = "Player-2-DRUID", spec = 105, pvp = { 9001 } }
W.units.party2 = nil
W.traits = {
	[-1] = { nodes = {
		{ entries = { { spell = 90001 } }, taken = 1, rank = 2 },   -- two ranks taken
		{ entries = { { spell = 102342 }, { spell = 90002 } }, taken = 2 },   -- Ironbark offered, the other choice taken
		{ entries = { { spell = 90003 } }, taken = 1 },
		{ entries = { { spell = 90004 } }, taken = 1, subTree = 7, subTreeActive = false },  -- a hero tree not chosen
		{ entries = { { spell = 90005 } } },   -- not taken
	} },
	[5] = { nodes = { { entries = { { spell = 90020 } }, taken = 1 } } },
}
local DATA = AR.TalentData
local dataBuild = DATA.build
DATA.build = (GetBuildInfo()) .. "." .. select(2, GetBuildInfo())   -- the data is for this build
DATA.mods[90001] = { [22812] = { sec = -10, ranks = { [9011] = { sec = { -10, -20 } } } } }   -- the stub's definition ID: config -1, node 1, entry 1
DATA.mods[90003] = { [61336] = { charges = 1 } }
DATA.mods[90004] = { [61336] = { pct = -50 } }
DATA.mods[90005] = { [61336] = { sec = -60 } }
DATA.mods[90010] = { [22812] = { sec = -5 } }     -- a PvP talent
DATA.mods[90020] = { [198589] = { sec = -15 } }   -- the player's talent
DATA.mods[90030] = { [22812] = { sec = -15 } }    -- a restoration passive
DATA.spec[105] = { 90030 }
W.activeTraitConfig = 5
W.pvpTalentInfo = { [9001] = { spellID = 90010 } }
W.pvpTalents = {}
W.inspectable = nil
W.now = 5000
fire("PLAYER_ENTERING_WORLD")
check(fake.started and TR.Get("party1") and TR.Get("party1").spells[22812].estimate, "entering: the druid's cooldowns are estimates")
check(not IN.TextFallback(), "the data is for this build: no texts are read")
IN.Tick(5000)
local me = TR.Get("player").spells[198589]
check(me.cd == AR.BaseCooldown(me.def) - 15 and not me.estimate, "the player's own talents at once: Blur 15 s shorter, no longer an estimate")
check(W.log[#W.log] == "inspect:party1", "the druid is asked for")
local barkskin = AR.BaseCooldown(AR.SPELL_BY_ID[22812])
eq(barkskin, 60, "Barkskin's base comes from the data")
check(TR.Get("party1").spells[22812].cd == barkskin, "nothing changes before the answer")
fire("INSPECT_READY", "Player-2-DRUID")
local d = TR.Get("party1")
eq(d.spells[22812].cd, barkskin - 20 - 5 - 15, "the answer: rank 2 of the talent, the PvP talent and the spec's passive off Barkskin")
check(not d.spells[22812].estimate, "no longer an estimate")
eq(d.spells[61336].charges, AR.BaseCharges(d.spells[61336].def) + 1, "Survival Instincts: a charge more")
eq(d.spells[61336].cd, AR.BaseCooldown(d.spells[61336].def), "the hero tree not chosen and the talent not taken count for nothing")
local function inRow(unit, id)
	for _, x in ipairs(TR.Get(unit).order) do if x == id then return true end end
	return false
end
check(not inRow("party1", 102342) and d.spells[102342], "Ironbark offered and not taken: out of the row, still known")
check(not IN.Pending("party1"), "answered in one go")

-- the game moved past the data: a talent the data does not know is read from its text
DATA.build = "0.0.0.0"
check(IN.TextFallback(), "another build: the texts are read for what the data lacks")
W.traits[-1].nodes[6] = { entries = { { spell = 90006, desc = "Reduces the cooldown of spell22812 by 3 sec." } }, taken = 1 }
IN.Want("party1", "Player-2-DRUID", "DRUID")
IN.Tick(5006)
fire("INSPECT_READY", "Player-2-DRUID")
eq(d.spells[22812].cd, barkskin - 20 - 5 - 15 - 3, "the data's talents as before, the unknown one from its text")
W.traits[-1].nodes[6] = nil
DATA.build = (GetBuildInfo()) .. "." .. select(2, GetBuildInfo())
AR.UI.Refresh(5006)
local row = AR.UI.Rows().party1
-- the crowd control box was left ticked on above: Incapacitating Roar is watched though under a minute
eq(table.concat(d.order, ","), "22812,740,473909,5211,99,22570,29166",
	"a restoration druid without Ironbark, by main tag: Barkskin, Tranquility, Ancient of Lore; Mighty Bash, Incapacitating Roar, Maim (a class talent); Innervate")
check(not inRow("party1", 61336) and d.spells[61336], "the spec (restoration) drops Survival Instincts, feral and guardian only")
check(not inRow("player", 187827) and inRow("player", 198589), "the player's own spec (havoc): vengeance's Metamorphosis gone, Blur kept")
check(not row.icons[#d.order + 2] or not row.icons[#d.order + 2]:IsShown(), "and no icon drawn for it")

-- the buff proves the ability after all
TR.SetAvailable("party1", 22812, false)
check(not inRow("party1", 22812), "Barkskin taken out")
shown("party1", 22812, 5010)
check(inRow("party1", 22812), "Barkskin seen on the druid: back in the row")
shown("party1", 102342, 5012)
check(inRow("party1", 102342), "Ironbark seen on the only druid: back as well")

-- the player looking at someone: no request that would replace them
W.units.party2 = { friendly = true, class = "PALADIN", guid = "Player-2-PALADIN", spec = 70 }
fire("GROUP_ROSTER_UPDATE")
InspectFrame = T.Mock("Frame", "InspectFrame")
InspectFrame:Show()
IN.Tick(5014)
check(W.log[#W.log] ~= "inspect:party2", "the inspect window is open: nothing sent")
InspectFrame:Hide()
IN.Tick(5015)
check(W.log[#W.log] == "inspect:party2", "closed: the request goes out")
local cleared = #W.log
InspectFrame:Show()
fire("INSPECT_READY", "Player-2-PALADIN")
check(W.log[#W.log] ~= "inspect-clear", "an answer while the window is open does not clear it")
check(not inRow("party2", 31850) and not inRow("party2", 86659) and inRow("party2", 498), "retribution: no Ardent Defender, no Guardian of Ancient Kings; Divine Protection kept")
InspectFrame:Hide()
InspectFrame = nil
W.units.party2 = nil
fire("GROUP_ROSTER_UPDATE")

-- a teammate out of inspect range: asked only once in range
W.inspectable = { party2 = false }
W.units.party2 = { friendly = true, class = "PRIEST", guid = "Player-2-PRIEST" }
fire("GROUP_ROSTER_UPDATE")
IN.Tick(5020)
check(W.log[#W.log] ~= "inspect:party2", "out of range: no request")
W.inspectable.party2 = true
IN.Tick(5026)
check(W.log[#W.log] == "inspect:party2", "in range: asked")
IN.Tick(5027)
check(W.log[#W.log] == "inspect:party2", "one request in flight at a time")
IN.Tick(5031)   -- no answer in time
IN.Tick(5032)
check(W.log[#W.log] == "inspect:party2" and #W.log > 0, "a lost answer: asked again after the interval")
fire("INSPECT_READY", "Player-2-PRIEST")
check(not IN.Pending("party2"), "answered (nothing to read in the tree: done)")

-- a new round asks everyone again; giving up after enough tries
W.matchState = 3
fire("PVP_MATCH_STATE_CHANGED")
check(IN.Pending("party1") and IN.Pending("party2"), "the round start wants every teammate's talents again")
local t0 = 5100
for i = 1, 30 do IN.Tick(t0); t0 = t0 + 6 end   -- a lost answer costs two ticks: the timeout, then the next request
check(not IN.Pending("party1"), "never answered: given up")
SlashCmdList.CKPARTYCD("")
check(T.said("inspect party1") and T.said("gave up"), "/ckpartycd tells what inspect found or did not")

W.inInstance, W.instanceType = false, nil
fire("ZONE_CHANGED_NEW_AREA")
W.traits, W.inspectable = nil, nil
DATA.build = dataBuild

-- ---------------------------------------------------------------- off
CK.SetModuleEnabled("PartyCD", false)
check(not AR.IsRunning(), "switched off: stopped")

return T.report("partycd " .. LOCALE)
