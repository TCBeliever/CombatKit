-- The PvP module: the ability table and talent modifiers, the tracker on a
-- fake probe backend, who an external is credited to, the arena lifecycle,
-- giving up when the probe cannot work, /ckpvp, its page.

local T = dofile(HERE .. "/stubs.lua")
local check, eq, W, fire, flush = T.check, T.eq, T.W, T.fire, T.flush
T.captureChat()

local CK = T.boot()
check(T.loaded.CombatKit_PvP == nil, "off by default: never loaded")

-- ---------------------------------------------------------------- a fake probe: a table of buffs
-- W.buffs[unit] = { [spellID] = true }; W.probeBroken = a reason the self test fails with;
-- W.controlsFail = every scan comes back invalid; W.refused = the probe is out
W.buffs = {}
local fake = { scans = 0 }
function fake.SelfTest() if W.probeBroken then return false, W.probeBroken end return true end
function fake.Prepare() return true end
function fake.Refused() return W.refused end
function fake.ResetCircuits() W.refused = nil end
function fake.Busy() return fake.pending ~= nil end
function fake.Reset() fake.pending = nil end
function fake.Status() return "fake" end
function fake.Scan(requests, done)
	fake.pending = { requests, done }
	fake.scans = fake.scans + 1
	return true
end
function fake.Tick()
	local p = fake.pending
	if not p then return end
	fake.pending = nil
	if W.refused then p[2](nil, false, "refused") return end
	local results = {}
	for i, r in ipairs(p[1]) do
		local has = false
		for _, id in ipairs(r.ids) do
			if W.buffs[r.unit] and W.buffs[r.unit][id] then has = true end
		end
		results[i] = has
	end
	p[2](results, not W.controlsFail, W.controlsFail and "controls" or nil)
end

T.loadAddon("CombatKit_PvP")
local PV = CK.modules.PvP
PV.Probe.SetBackend(fake)

-- ---------------------------------------------------------------- the ability table
local count = 0
for class, list in pairs(PV.Spells.BY_CLASS) do
	for _, a in ipairs(list) do
		count = count + 1
		check(type(a.id) == "number" and a.cd > 0 and a.dur > 0 and #a.auras > 0, class .. " " .. tostring(a.name) .. " is complete")
		check(a.kind == "self" or a.kind == "ally" or a.kind == "enemy", a.name .. " has a kind")
		for _, m in ipairs(a.mods or {}) do
			check(type(m.talent) == "number" and (m.kind == "flat" or m.kind == "percent" or m.kind == "charges")
				and type(m.amount) == "number", a.name .. " modifier " .. tostring(m.talent))
		end
	end
end
check(count > 50, "a few dozen abilities")
eq(#PV.Spells.For("PRIEST", 256), 5, "a Discipline priest: four defensives and Psychic Scream")
eq(#PV.Spells.For("PRIEST"), 12, "spec unknown: the whole class, crowd control and burst included")
check(PV.Spells.BY_ID[228260].role == "offensive" and PV.Spells.BY_ID[33206].role == "defensive"
	and PV.Spells.BY_ID[8122].kind == "enemy" and PV.Spells.BY_ID[8122].role == "cc", "roles and kinds")
eq(#PV.Spells.For("UNKNOWN"), 0, "an unknown class: nothing")
check(PV.Spells.ClassHas("PRIEST", 33206) and not PV.Spells.ClassHas("MAGE", 33206), "ClassHas")

-- ---------------------------------------------------------------- cooldowns from talents
local CD = PV.Cooldowns
local ams = PV.Spells.BY_ID[48707]
local r = CD.Resolve(ams, nil, {})
check(r.cd == 60 and r.basis == "base", "no talents read: the base cooldown")
r = CD.Resolve(ams, { talents = { [205727] = 1 }, pvp = {}, traitComplete = true, pvpComplete = true }, {})
check(r.cd == 40 and r.basis == "talents" and r.assumes[1] == 205727, "Anti-Magic Barrier: 20 s off")
r = CD.Resolve(ams, { talents = { [205727] = 1 }, pvp = { [410320] = true }, traitComplete = true, pvpComplete = false }, {})
check(r.cd == 30 and r.basis == "partial", "plus the PvP talent; some talents unread: partial")
r = CD.Resolve(PV.Spells.BY_ID[642], { talents = { [114154] = 1 }, pvp = {}, traitComplete = true, pvpComplete = true }, {})
eq(r.cd, 210, "Unbreakable Spirit: 30% off Divine Shield")
r = CD.Resolve(PV.Spells.BY_ID[45438], { talents = { [382424] = 1, [1244110] = 1 }, pvp = {}, traitComplete = true, pvpComplete = true }, {})
check(r.cd == 180 and r.charges == 2, "Winter's Protection and Glacial Bulwark: 60 s off Ice Block and a second charge")
r = CD.Resolve(PV.Spells.BY_ID[363916], { talents = { [375406] = 1 }, pvp = {}, traitComplete = true, pvpComplete = true }, {})
eq(r.charges, 2, "Obsidian Bulwark: a second charge")
r = CD.Resolve(ams, { talents = { [205727] = 1 }, pvp = {}, traitComplete = true, pvpComplete = true }, { [48707] = 45 })
check(r.cd == 45 and r.basis == "custom", "set by hand wins")

-- ---------------------------------------------------------------- FrameSort: its frames, and its callback
local sorted = {}
local postSort
FrameSortApi = { v3 = { Sorting = {
	GetPartyFrames = function() return { Blizzard = sorted } end,
	RegisterPostSortCallback = function(_, fn) postSort = fn end,
} } }
local fsFrame = T.Mock("Frame", "FrameSortParty1")
fsFrame.unit = "party1"
sorted[1] = fsFrame

-- ---------------------------------------------------------------- outside arena: nothing
CK.SetModuleEnabled("PvP", true)
check(postSort ~= nil and PV.Display.FrameSortHooked(), "FrameSort's post-sort callback is registered")
local found, source = PV.Display.FindFrame("party1")
check(found == fsFrame and source == "FrameSort", "a teammate's frame is found through FrameSort")
check(PV.Display.FindFrame("party2") == nil, "a frame FrameSort does not list is not invented")
postSort()   -- sorting happened: the rows re-anchor at the next paint
check(PV.enabled and PV.IsRunning(), "switched on")
eq(PV.State(), "idle", "no arena: idle")
check(PV.Display.Rows().party1 == nil, "no rows")

-- ---------------------------------------------------------------- an arena, two teammates
W.units.party1 = { friendly = true, class = "PRIEST", guid = "G1", spec = 256, talents = {}, pvp = {} }
W.units.party2 = { friendly = true, class = "PALADIN", guid = "G2", spec = 65, talents = { [114154] = 1 }, pvp = {} }
W.inInstance, W.instanceType, W.matchState = true, "arena", 1
fire("PLAYER_ENTERING_WORLD")
eq(PV.State(), "ready", "in the arena, gates closed: ready")
eq(#PV.Tracker.Entries("party1"), 12, "spec not known yet: the whole class is watched")
PV._Tick(1)
check(W.inspected == "party1", "the slow tick inspects the first teammate")
fire("INSPECT_READY", "G1")
eq(#PV.Tracker.Entries("party1"), 5, "spec read: narrowed to Discipline")
W.now = W.now + 2
PV._Tick(1)
fire("INSPECT_READY", "G2")
local function entry(unit, id)
	for _, e in ipairs(PV.Tracker.Entries(unit)) do if e.key == id then return e end end
end
eq(#PV.Tracker.Entries("party2"), 7, "a Holy paladin: four defensives, two crowd controls, Avenging Wrath")
local p2 = PV.Tracker.Entries("party2")
check(p2[5].ability.role == "cc" and p2[7].key == 31884, "defensives, then crowd control, then the burst cooldown")
local ds = entry("party2", 642)
check(ds.cd == 210 and ds.basis == "talents", "his Unbreakable Spirit was read: Divine Shield 210 s")
check(not PV.IsLive(), "nothing is scanned before the gates open")

W.matchState = 3
fire("PVP_MATCH_STATE_CHANGED")
check(PV.IsLive(), "gates open: scanning")
local function tick(n)
	for _ = 1, (n or 2) do
		W.now = W.now + 0.2
		PV._Tick(0.2)
	end
end
tick(2)
check(fake.scans >= 1, "a scan went out")
local rapture = entry("party1", 47536)
eq(rapture.last, false, "no buff: the entry says so")
eq(PV.Tracker.Charges(rapture, W.now), 1, "and the ability is ready")
check(not rapture.unknown, "a fresh round: known to be ready")

-- ---------------------------------------------------------------- a buff appears: the estimate starts
W.buffs.party1 = { [47536] = true }
tick(2)
check(rapture.active, "Rapture is up")
local available, nextIn = PV.Tracker.Charges(rapture, W.now)
eq(available, 0, "and on cooldown")
check(nextIn > 85 and nextIn <= 90, "for its base cooldown")
local row = PV.Display.Rows().party1
check(row and row:IsShown(), "the teammate has a row")
eq(#row.icons, 5, "with one icon per ability")
local icon = row.icons[3]
check(icon.cd:IsShown() and icon.glow:IsShown(), "the icon shows the cooldown and (no lane in the stubs) the plain glow")
check(icon.time:GetText() == "1:30" or icon.time:GetText() == "1:29", "and the time left")
local firstReady = rapture.queue[1]
tick(4)
check(rapture.active and #rapture.queue == 1, "the buff staying up starts nothing new")
-- one flaky "no" between two "yes": the same use
W.buffs.party1 = nil
tick(2)
W.buffs.party1 = { [47536] = true }
tick(2)
eq(rapture.queue[1], firstReady, "one missing read does not count as a new use")
W.buffs.party1 = nil
tick(4)
check(not rapture.active and #rapture.queue == 1, "the buff gone: still on cooldown")
W.now = W.now + 91
tick(2)
eq(PV.Tracker.Charges(rapture, W.now), 1, "ready again after the cooldown")

-- ---------------------------------------------------------------- an external lands on me
W.buffs.player = { [33206] = true }
tick(2)
local ps = entry("party1", 33206)
check(ps.active and PV.Tracker.Charges(ps, W.now) == 0, "Pain Suppression on the player is credited to the priest")
check(not ps.uncertain, "the only priest: no doubt")
local psReady = ps.queue[1]
W.buffs.player = nil
tick(4)
W.buffs.party2 = { [33206] = true }   -- seen again on another friend within its duration: the same use
tick(2)
eq(ps.queue[1], psReady, "the same external seen on another friend right after: still one use")
W.buffs.party2 = nil
tick(4)
W.now = W.now + 12
W.buffs.party2 = { [33206] = true }
tick(2)
check(ps.queue[1] > psReady, "seen again after its duration: a second use")
W.buffs.party2 = nil
tick(4)

-- ---------------------------------------------------------------- two priests: whose was it?
W.units.party2 = { friendly = true, class = "PRIEST", guid = "G3", spec = 256, talents = {}, pvp = {} }
fire("GROUP_ROSTER_UPDATE")
W.inspected = "party2"; fire("INSPECT_READY", "G3")
local ps2 = entry("party2", 33206)
check(ps2 and ps2.unknown, "a teammate who arrives mid-round: his cooldowns are unknown")
check(entry("party1", 47536) == rapture, "a teammate who stays keeps his timers")
W.now = W.now + 200
W.buffs.player = { [33206] = true }
tick(2)
check(ps.uncertain and ps2.uncertain, "two priests: the external is marked uncertain")
check(ps.queue == ps2.queue and PV.Tracker.Charges(ps2, W.now) == 0, "and both icons share one estimate")
check(not ps2.unknown, "seen once: no longer unknown")
W.buffs.player = nil
tick(4)
W.now = W.now + 200
-- the second priest is stunned: the first cast it
W.loc.party2 = { { priority = 5 } }
W.buffs.player = { [33206] = true }
tick(2)
check(not ps.uncertain and not ps2.uncertain, "one of them crowd controlled: settled")
check(PV.Tracker.Charges(ps, W.now) == 0 and PV.Tracker.Charges(ps2, W.now) == 1, "on the free one, the other is ready")
W.loc.party2 = nil
W.buffs.player = nil
tick(4)

-- ---------------------------------------------------------------- an external that cannot be self-cast
W.units.party1 = { friendly = true, class = "PALADIN", guid = "G4", spec = 65, talents = {}, pvp = {} }
W.units.party2 = { friendly = true, class = "PALADIN", guid = "G5", spec = 65, talents = {}, pvp = {} }
fire("GROUP_ROSTER_UPDATE")
W.inspected = "party1"; fire("INSPECT_READY", "G4")
W.inspected = "party2"; fire("INSPECT_READY", "G5")
W.buffs.party1 = { [6940] = true }   -- Sacrifice on the first paladin
tick(2)
check(PV.Tracker.Charges(entry("party2", 6940), W.now) == 0 and PV.Tracker.Charges(entry("party1", 6940), W.now) == 1,
	"Blessing of Sacrifice on one paladin: the other cast it")
check(not entry("party2", 6940).uncertain, "no doubt")
W.buffs.party1 = nil
tick(4)

-- ---------------------------------------------------------------- my own class: my casts are known
W.units.party1 = { friendly = true, class = "DEMONHUNTER", guid = "G6", spec = 577, talents = {}, pvp = {} }
W.units.party2 = { friendly = true, class = "WARRIOR", guid = "G2", spec = 71, talents = {}, pvp = {} }
fire("GROUP_ROSTER_UPDATE")
W.inspected = "party1"; fire("INSPECT_READY", "G6")
W.inspected = "party2"; fire("INSPECT_READY", "G2")
W.now = W.now + 10
W.buffs.player = { [209426] = true }   -- Darkness on me, no cast of mine
tick(2)
local dark = entry("party1", 196718)
check(PV.Tracker.Charges(dark, W.now) == 0 and not dark.uncertain, "Darkness on me, none cast by me: the other demon hunter's")
W.buffs.player = nil
tick(4)
W.now = W.now + 320
fire("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-1", 196718)
W.buffs.player = { [209426] = true }
tick(2)
eq(PV.Tracker.Charges(dark, W.now), 1, "Darkness right after my own cast: mine, his stays ready")
W.buffs.player = nil
tick(4)

-- ---------------------------------------------------------------- a crowd control lands on an enemy
W.units.party1 = { friendly = true, class = "PRIEST", guid = "G8", spec = 256, talents = {}, pvp = {} }
W.units.arena1 = { friendly = false, guid = "E1" }
fire("GROUP_ROSTER_UPDATE")
W.inspected = "party1"; fire("INSPECT_READY", "G8")
tick(2)
check(PV.Tracker.enemies.arena1 ~= nil, "the enemy is on the list")
W.now = W.now + 20
W.buffs.arena1 = { [8122] = true }   -- Psychic Scream on arena1
tick(2)
local scream = entry("party1", 8122)
check(scream and scream.active and PV.Tracker.Charges(scream, W.now) == 0, "Psychic Scream on an enemy: the priest's cooldown starts")
W.buffs.arena1 = nil
tick(4)
W.units.arena1 = nil
W.units.party1 = { friendly = true, class = "DEMONHUNTER", guid = "G6", spec = 577, talents = {}, pvp = {} }
fire("GROUP_ROSTER_UPDATE")
W.inspected = "party1"; fire("INSPECT_READY", "G6")

-- ---------------------------------------------------------------- a scan that straddled a roster change is discarded
W.buffs.party2 = { [118038] = true }
tick(1)   -- the scan goes out
local dbts = entry("party2", 118038)
W.units.party2.guid = "G7"
fire("GROUP_ROSTER_UPDATE")
tick(1)   -- its answer comes back for a roster that is gone
eq(PV.Tracker.stats.discarded, 1, "discarded")
check(entry("party2", 118038) ~= dbts, "the new teammate has his own entries")
W.buffs.party2 = nil
tick(4)

-- ---------------------------------------------------------------- a new round: everything ready and known
W.buffs.party2 = { [118038] = true }
tick(2)
check(PV.Tracker.Charges(entry("party2", 118038), W.now) == 0, "used")
W.matchState = 2
fire("PVP_MATCH_STATE_CHANGED")
check(not PV.IsLive(), "between rounds: not scanning")
W.matchState = 3
fire("PVP_MATCH_STATE_CHANGED")
eq(PV.Tracker.Charges(entry("party2", 118038), W.now), 1, "a new round: cooldowns reset")
W.buffs.party2 = nil

-- ---------------------------------------------------------------- /ckpvp
T.chat = {}
SlashCmdList.COMBATKITPVP("status")
check(T.said("arena") and T.said("party1"), "status: the arena and the teammates")
SlashCmdList.COMBATKITPVP("cd 118038 90")
local custom = entry("party2", 118038)
check(custom.cd == 90 and custom.basis == "custom", "a cooldown set by hand")
eq(PV.db.cooldowns[118038], 90, "and saved")
SlashCmdList.COMBATKITPVP("cd 118038 reset")
check(custom.cd == 120 and custom.basis ~= "custom", "and taken back")
T.chat = {}
SlashCmdList.COMBATKITPVP("log 5")
check(T.said("log:"), "the log prints")
SlashCmdList.COMBATKITPVP("entries")
check(T.said("Die by the Sword"), "entries lists the abilities")
local snap = PV.db.debug
check(snap and snap.why == "slash entries" and #snap.status > 0 and #snap.log > 0, "a snapshot of status, entries and log is kept in the saved variables")
local found = false
for _, line in ipairs(snap.entries) do if line:find("Die by the Sword", 1, true) then found = true end end
check(found, "with the entries")
PV.db.debug = nil
for _ = 1, PV.SNAPSHOT_EVERY do PV._Tick(1) end
check(PV.db.debug ~= nil and PV.db.debug.why == "tick", "and refreshed every few seconds")

-- ---------------------------------------------------------------- controls failing: paused
W.controlsFail = true
T.chat = {}
tick(14)
eq(PV.State(), "paused", "five bad scans: paused")
check(T.said("PvP"), "and said in chat")
check(not row:IsShown(), "icons hidden")
W.controlsFail = false

-- ---------------------------------------------------------------- leaving
W.inInstance, W.instanceType, W.matchState = false, "none", 0
fire("ZONE_CHANGED_NEW_AREA")
eq(PV.State(), "idle", "out of the arena: idle")
check(not row:IsShown(), "rows gone")
eq(#PV.Tracker.Entries("party1"), 0, "roster cleared")

-- the next arena starts clean: paused no more
W.inInstance, W.instanceType, W.matchState = true, "arena", 3
fire("PLAYER_ENTERING_WORLD")
eq(PV.State(), "scanning", "a new arena after a pause: scanning again")
-- the probe refused: paused with the client's words
W.refused = "SetAuraSlotCandidateFilters: boom"
tick(2)
local state, text = PV.State()
check(state == "paused" and text:find("boom", 1, true), "the client refused a call: paused, and the reason names the call")
W.refused = nil
W.inInstance, W.instanceType, W.matchState = false, "none", 0
fire("ZONE_CHANGED_NEW_AREA")

-- ---------------------------------------------------------------- the probe cannot work here
local real = PV.Probe.Real()
local ok, reason = real.SelfTest()
check(ok == false and reason == "duration", "the real backend: no duration objects in the stubs, says which")
CK.SetModuleEnabled("PvP", false)
W.probeBroken = "api"
T.chat = {}
CK.SetModuleEnabled("PvP", true)
state, text = PV.State()
eq(state, "unavailable", "self test failed: unavailable")
check(text and text ~= "", "with a reason")
check(T.said("PvP"), "said once in chat")
W.inInstance, W.instanceType, W.matchState = true, "arena", 3
fire("PLAYER_ENTERING_WORLD")
check(not PV.IsLive(), "an arena changes nothing")
W.inInstance, W.instanceType, W.matchState = false, "none", 0
fire("ZONE_CHANGED_NEW_AREA")
CK.SetModuleEnabled("PvP", false)
W.probeBroken = nil
CK.SetModuleEnabled("PvP", true)
eq(PV.State(), "idle", "switched off and on: tried again")

-- ---------------------------------------------------------------- solo: the player stands in, anywhere
W.units.player = { friendly = true, talents = { [389783] = 1 } }
W.inspected = "player"
W.activeTraitConfig = -1
C_ClassTalents.GetActiveConfigID = function() return W.activeTraitConfig end
C_SpecializationInfo.GetAllSelectedPvpTalentIDs = function() return {} end
T.chat = {}
SlashCmdList.COMBATKITPVP("solo")
check(PV.IsSolo() and T.said("solo"), "solo on, said so")
eq(PV.State(), "scanning", "and scanning at once, outside any arena")
local mine = PV.Tracker.Entries("player")
check(#mine > 0 and mine[1].unit == "player", "the player has entries")
local darkness = entry("player", 196718)
check(darkness.cd == 180 and darkness.basis == "talents", "the player's own talents were read: Pitch Black")
W.buffs.player = { [212800] = true }   -- Blur
tick(2)
local blur = entry("player", 198589)
check(blur.active and PV.Tracker.Charges(blur, W.now) == 0, "my own Blur: tracked like a teammate's")
W.buffs.player = { [209426] = true }   -- Darkness on myself
tick(2)
check(PV.Tracker.Charges(darkness, W.now) == 0, "an external on myself counts in solo mode")
W.buffs.player = nil
W.units.target = { friendly = false, guid = "T1" }
fire("PLAYER_TARGET_CHANGED")
W.buffs.target = { [179057] = true }   -- Chaos Nova on the target
tick(2)
check(PV.Tracker.Charges(entry("player", 179057), W.now) == 0, "a crowd control on my target counts too")
W.buffs.target = nil
W.units.target = nil
eq(PV.db.solo, true, "solo is saved")
SlashCmdList.COMBATKITPVP("solo")
check(not PV.IsSolo() and PV.State() == "idle", "solo off: idle again")
eq(#PV.Tracker.Entries("player"), 0, "and nothing tracked")
eq(PV.db.solo, false, "and the saved flag follows")
-- a reload with solo on: the module comes back in solo mode without a word typed
PV.db.solo = true
CK.SetModuleEnabled("PvP", false)
PV.db.solo = true
T.chat = {}
CK.SetModuleEnabled("PvP", true)
check(PV.IsSolo() and PV.State() == "scanning" and T.said("solo"), "solo survives a reload, and says so")
SlashCmdList.COMBATKITPVP("solo")

-- ---------------------------------------------------------------- /ckpvp scan
C_Spell.GetSpellName = function(id) return "spell" .. id end
C_Spell.GetSpellDescription = function(id) return "desc of " .. id .. "\nline two" end
C_Spell.RequestLoadSpellData = function() end
function GetSpellBaseCooldown(id) return id == 48707 and 60000 or 0 end
T.chat = {}
SlashCmdList.COMBATKITPVP("scan")
check(PV.Scan.Running() and T.said("scan"), "the scan starts and says so")
for _ = 1, 40 do flush() end
check(not PV.Scan.Running() and PV.db.scan ~= nil, "and finishes into the saved variables")
check(PV.db.scan.count > 150, "every ability, buff, modifier and candidate talent")
local ams
for _, item in ipairs(PV.db.scan.items) do if item:find("^48707|") then ams = item end end
check(ams and ams:find("|ability|spell48707|60000|") and ams:find("desc of 48707 / line two", 1, true), "an item: id, kind, name, base cooldown, description on one line")

-- ---------------------------------------------------------------- settings page
SlashCmdList.COMBATKIT("")
local main = CK.Options.GetFrame()
main.tabs.PvP:Click()
local page = main.bodies.PvP
check(page.state:GetText():find(CK.L["PVP_STATE_idle"], 1, true), "the page shows the state")
eq(page.fontSize:GetText(), "12", "font size shown")
eq(page.maxPerRow:GetText(), "8", "max per row shown")
page.test:Click()
check(PV.Display.IsTesting(), "sample rows on")
local sample = PV.Display.Rows().party2
local shown = 0
for _, b in ipairs(sample.icons) do if b:IsShown() then shown = shown + 1 end end
check(sample:IsShown() and shown == 6, "a sample row for the second teammate, an Arms warrior: two defensives, three crowd controls, Avatar")
page.offensive:Click()
page.cc:Click()
shown = 0
for _, b in ipairs(sample.icons) do if b:IsShown() then shown = shown + 1 end end
eq(shown, 2, "burst cooldowns and crowd control can be hidden")
page.offensive:Click()
page.cc:Click()
page.unlock:Click()
check(not PV.Display.IsLocked() and sample.bg:IsShown(), "unlocked: the loose row shows its handle")
main:Hide()
check(PV.Display.IsLocked() and not PV.Display.IsTesting(), "closing the window locks and ends the samples")
check(not sample:IsShown(), "samples gone")

-- ---------------------------------------------------------------- off
CK.SetModuleEnabled("PvP", false)
check(not PV.IsRunning(), "off: nothing running")

T.releaseChat()
return T.report("pvp   [" .. (LOCALE or "enUS") .. "]")
