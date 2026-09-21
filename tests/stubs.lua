-- WoW API stubs shared by the CombatKit tests (stock Lua 5.1 via lupa).
-- ROOT (repo root) and LOCALE are set by the runner. Returns T (helpers);
-- world state is T.W.

local T = { passed = 0, failed = 0 }
local realPrint = print

function T.check(cond, name)
	if cond then T.passed = T.passed + 1 else T.failed = T.failed + 1; realPrint("FAIL: " .. name) end
end
function T.eq(a, b, name)
	T.check(a == b, name .. " (got " .. tostring(a) .. ", want " .. tostring(b) .. ")")
end

local W = {
	inInstance = false, instanceType = "none", difficultyID = 0,
	warMode = false, challengeActive = false, keystone = false, matchState = 0,
	combat = false, now = 0,
	specIndex = 1,
	specs = { { 577, "Havoc" }, { 581, "Vengeance" }, { 1480, "Devourer" } },
	configs = { [577] = { 101, 102 }, [581] = { 201 }, [1480] = {} },
	configNames = { [101] = "M+ AoE", [102] = "Raid ST", [201] = "Tank" },
	activeConfig = { [577] = 102, [581] = 201 },
	sets = { [1] = { "PvE", false }, [2] = { "PvP", true }, [3] = { "Tank", false } },
	loadResult = 3,          -- Ready
	battlefield = {},        -- i -> { status, teamSize, queueType }
	lfg = nil,               -- subtypeID
	log = {},
}
T.W = W
local function log(s) W.log[#W.log + 1] = s end

function GetLocale() return LOCALE or "enUS" end
function strtrim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
function wipe(t) for k in pairs(t) do t[k] = nil end return t end
tinsert = table.insert
function IsInInstance() return W.inInstance, W.instanceType end
function GetInstanceInfo() return "X", W.instanceType, W.difficultyID end
function InCombatLockdown() return W.combat end
function GetTime() return W.now end
function UnitName() return "Tester" end
function GetRealmName() return "Realm" end
function UnitClass() return "Demon Hunter", "DEMONHUNTER" end
function GetMaxBattlefieldID() return 3 end
function GetBattlefieldStatus(i)
	local b = W.battlefield[i]
	if not b then return "none" end
	return b[1], "map", b[2], false, false, b[3]
end
function GetLFGProposal()
	if not W.lfg then return false end
	return true, 1, 1, W.lfg
end
function IsControlKeyDown() return W.ctrl or false end
function IsInGroup() return W.inGroup or false end
-- W.role: the role the group assigned ("TANK" | "HEALER" | "DAMAGER"); none by default
function UnitGroupRolesAssigned() return W.role or "NONE" end
function UnitCastingInfo() if W.casting then return "Casting" end end
function UnitChannelInfo() return nil end
-- ---------------------------------------------------------------------------
-- Player stats. W.secretStats = true makes every stat API hand out T.SECRET,
-- which behaves like a 12.x secret value: issecretvalue() knows it, and any
-- arithmetic or comparison on it raises an error.
-- ---------------------------------------------------------------------------
T.SECRET = setmetatable({}, { __tostring = function() return "<secret>" end })
function issecretvalue(v) return v == T.SECRET end
W.stats = { crit = 23.44, spellcrit = 30.04, rangedcrit = 10, haste = 18.02, mastery = 41.5, versRating = 6.5, versFlat = 1.5,
	leech = 3.2, avoidance = 1.1, dodge = 12.34, parry = 8, block = 0, primary = 12345, ilvl = 702.56, armor = 9876 }
local function Stat(name, second)
	return function()
		if W.secretStats then return T.SECRET, T.SECRET end
		if second then return 0, W.stats[name] end
		return W.stats[name]
	end
end
GetCritChance, GetSpellCritChance, GetRangedCritChance = Stat("crit"), Stat("spellcrit"), Stat("rangedcrit")
GetHaste, GetMasteryEffect = Stat("haste"), Stat("mastery")
GetCombatRatingBonus, GetVersatilityBonus = Stat("versRating"), Stat("versFlat")
GetLifesteal, GetAvoidance = Stat("leech"), Stat("avoidance")
GetDodgeChance, GetParryChance, GetBlockChance = Stat("dodge"), Stat("parry"), Stat("block")
UnitStat, GetAverageItemLevel, UnitArmor = Stat("primary", true), Stat("ilvl", true), Stat("armor", true)
-- current, run, flight, swim. Skyriding (W.gliding = yards per second) is not in it, as in the game.
function GetUnitSpeed(unit)
	if W.secretStats then return T.SECRET, T.SECRET, T.SECRET, T.SECRET end
	if unit == "vehicle" then return W.vehicleSpeed or 0 end
	return W.speed or (W.moving and 7 or 0), W.runSpeed or 7, W.flightSpeed or 28.7, W.swimSpeed or 4.7
end
C_PlayerInfo = { GetGlidingInfo = function() return W.gliding ~= nil, W.gliding ~= nil, W.gliding or 0 end }
function IsFlying() return W.flying or W.gliding ~= nil end
function IsSwimming() return W.swimming or false end
-- W.durability[slot] = { current, full }; slots without an entry have no durability
function GetInventoryItemDurability(slot)
	local d = W.durability and W.durability[slot]
	if d then return d[1], d[2] end
end
-- ---------------------------------------------------------------------------
-- Units and range. W.units[unit] = { friendly = bool, yards = number }; an item
-- or spell is "in range" when its range covers the distance.
-- ---------------------------------------------------------------------------
W.units = {}
W.itemRange = { [37727] = 5, [63427] = 6, [34368] = 8, [32321] = 10, [1251] = 15, [33069] = 15, [21519] = 20,
	[10645] = 20, [31463] = 25, [24268] = 25, [1180] = 30, [835] = 30, [18904] = 35, [24269] = 35, [34471] = 40,
	[28767] = 40, [32698] = 45, [23836] = 45, [116139] = 50, [32825] = 60, [41265] = 70, [35278] = 80, [33119] = 100 }
W.spells = {}   -- { { id, maxRange }, ... } in the spell book
STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
function UnitExists(unit) return W.units[unit] ~= nil end
function UnitIsUnit(a, b) return a == b end
function UnitCanAttack(_, unit) return W.units[unit] and not W.units[unit].friendly or false end
function GetCursorPosition() return 500, 400 end
C_Item = {
	GetItemInfo = function(id) return "item" .. id end,
	RequestLoadItemDataByID = function() end,
	IsItemInRange = function(id, unit)
		local u = W.units[unit]
		if W.combat and u and u.friendly then return nil end   -- blocked for friendly units in combat
		return u ~= nil and W.itemRange[id] ~= nil and u.yards <= W.itemRange[id]
	end,
}
C_Spell = {
	GetOverrideSpell = function() return nil end,
	GetSpellInfo = function(id)
		for _, s in ipairs(W.spells) do if s[1] == id then return { spellID = id, maxRange = s[2] } end end
	end,
	IsSpellInRange = function(id, unit)
		local u = W.units[unit]
		for _, s in ipairs(W.spells) do if s[1] == id then return u ~= nil and u.yards <= s[2] end end
		return false
	end,
}
C_SpellBook = {
	GetNumSpellBookSkillLines = function() return 1 end,
	GetSpellBookSkillLineInfo = function() return { itemIndexOffset = 0, numSpellBookItems = #W.spells } end,
	GetSpellBookItemName = function(i) return W.spells[i] and ("spell" .. i) or nil end,
	GetSpellBookItemType = function(i) return "SPELL", nil, W.spells[i] and W.spells[i][1] end,
	IsSpellBookItemPassive = function() return false end,
}

-- secure state drivers (the RightClick feature)
W.drivers = {}
SecureStateDriverManager = { RegisterEvent = function() end }
function RegisterStateDriver(frame, state, condition) W.drivers[state] = condition; log("driver:on") end
function UnregisterStateDriver(frame, state) W.drivers[state] = nil; log("driver:off") end
function ClearOverrideBindings() log("bindings:cleared") end
function MouselookStart() log("mouselook:start") end
function MouselookStop() log("mouselook:stop") end

function IsMouseButtonDown() return false end
function GameTooltip_Hide() end
function ReloadUI() W.reloaded = true end
SlashCmdList = {}
UISpecialFrames = {}

local timers, longTimers = {}, {}
-- short delays run on flush(); long ones (timeouts) only when a test asks
C_Timer = { After = function(d, fn)
	if d > 10 then longTimers[#longTimers + 1] = fn else timers[#timers + 1] = { d = d, fn = fn } end
end }
-- runs the timers whose delay is <= limit (default: all short ones), and whatever they schedule
function T.flush(limit)
	limit = limit or 10
	for _ = 1, 10 do
		local run, keep = {}, {}
		for _, t in ipairs(timers) do
			if t.d <= limit then run[#run + 1] = t else keep[#keep + 1] = t end
		end
		if #run == 0 then break end
		timers = keep
		table.sort(run, function(a, b) return a.d < b.d end)
		for _, t in ipairs(run) do t.fn() end
	end
end
function T.runLongTimers()
	local run = longTimers
	longTimers = {}
	for _, fn in ipairs(run) do fn() end
	T.flush()
end

Enum = {
	SpellBookSpellBank = { Player = 0 },
	PvPMatchState = { Inactive = 0, Engaged = 3 },
	LoadConfigResult = { Error = 0, NoChangesNecessary = 1, LoadInProgress = 2, Ready = 3 },
}
C_PvP = {
	IsWarModeDesired = function() return W.warMode end,
	GetActiveMatchState = function() return W.matchState end,
}
C_ChallengeMode = {
	IsChallengeModeActive = function() return W.challengeActive end,
	HasSlottedKeystone = function() return W.keystone end,
}
C_SpecializationInfo = {
	GetSpecialization = function() return W.specIndex end,
	GetSpecializationInfo = function(i)
		local s = W.specs[i]
		-- the live client answers an index just past the class's specs with an empty record
		if not s then if i == #W.specs + 1 then return 0 end return nil end
		return s[1], s[2], "", 134400, s[3] or "DAMAGER"
	end,
	-- W.specRefused: the client says no. Otherwise it says yes; the test decides whether it lands.
	SetSpecialization = function(i)
		log("spec:" .. i)
		if W.specRefused then return false end
		return true
	end,
}
C_ClassTalents = {
	GetConfigIDsBySpecID = function(specID) return W.configs[specID] or {} end,
	GetLastSelectedSavedConfigID = function(specID) return W.activeConfig[specID] end,
	LoadConfig = function(id) log("talents:" .. id); return W.loadResult end,
	UpdateLastSelectedSavedConfigID = function(specID, id) W.activeConfig[specID] = id end,
	GetActiveConfigID = function() return W.activeTraitConfig end,
}
C_Traits = {
	GetConfigInfo = function(id) return W.configNames[id] and { name = W.configNames[id] } or nil end,
}
C_EquipmentSet = {
	GetEquipmentSetIDs = function() local t = {} for id in pairs(W.sets) do t[#t + 1] = id end table.sort(t) return t end,
	GetEquipmentSetInfo = function(id)
		local s = W.sets[id]
		if not s or W.setsHidden then return nil end   -- setsHidden: data not loaded yet
		return s[1], 134400, id, s[2]
	end,
	GetEquipmentSetID = function(name) for id, s in pairs(W.sets) do if s[1] == name then return id end end end,
	UseEquipmentSet = function(id)
		log("equip:" .. id)
		if W.equipFails then return false end
		for k, s in pairs(W.sets) do s[2] = (k == id) end
		return true
	end,
}

-- ---------------------------------------------------------------------------
-- A frame that accepts any widget method. Field reads that are not methods
-- (b.Text, b.text) stay nil, as on a real frame. Scripts and registered events
-- are kept so tests can click things and fire events at every listener.
-- ---------------------------------------------------------------------------
T.frames = {}      -- by global name
T.all = {}

local function Mock(kind, name)
	local scripts = {}
	local obj = { __kind = kind, __name = name, __shown = true, __scripts = scripts, __events = {} }
	T.all[#T.all + 1] = obj
	local methods = {
		SetScript = function(self, n, fn) scripts[n] = fn end,
		GetScript = function(self, n) return scripts[n] end,
		RegisterEvent = function(self, e)
			if T.unknownEvents and T.unknownEvents[e] then error("unknown event " .. e) end
			self.__events[e] = true
		end,
		RegisterUnitEvent = function(self, e) self.__events[e] = true end,
		UnregisterEvent = function(self, e) self.__events[e] = nil end,
		UnregisterAllEvents = function(self) self.__events = {} end,
		IsShown = function(self) return self.__shown end,
		Show = function(self)
			local was = self.__shown
			self.__shown = true
			if not was and scripts.OnShow then scripts.OnShow(self) end
		end,
		Hide = function(self)
			local was = self.__shown
			self.__shown = false
			if was and scripts.OnHide then scripts.OnHide(self) end
		end,
		SetShown = function(self, v) if v then self:Show() else self:Hide() end end,
		SetText = function(self, text) self.__text = text; self.__secret = nil end,
		-- the game formats a secret number; the text is then secret too, and so is its width
		SetFormattedText = function(self, fmt, ...)
			local args, secret = { ... }, false
			for i, a in ipairs(args) do if a == T.SECRET then args[i] = 99.9; secret = true end end
			self.__text = string.format(fmt, unpack(args))
			self.__secret = secret or nil
		end,
		GetText = function(self) return self.__text end,
		GetName = function(self) return self.__name end,
		GetFontString = function(self)
			self.__fs = self.__fs or Mock("FontString")
			return self.__fs
		end,
		CreateFontString = function() return Mock("FontString") end,
		CreateTexture = function() return Mock("Texture") end,
		CreateAnimationGroup = function() return Mock("AnimationGroup") end,
		CreateAnimation = function() return Mock("Animation") end,
		GetStringWidth = function(self) if self.__secret then return T.SECRET end return 60 end,
		GetWidth = function() return 120 end,
		GetEffectiveScale = function(self) return self.__scale or 1 end,
		GetPoint = function() return "TOP", nil, "TOP", 10.4, -20.6 end,
		IsMouseOver = function() return false end,
		SetScale = function(self, s) self.__scale = s end,
		SetAlpha = function(self, a) self.__alpha = a end,
		GetAlpha = function(self) return self.__alpha end,
		-- W.badFonts[file]: a font file that is not there (its addon was removed)
		SetFont = function(self, file, size, flags)
			if W.badFonts and W.badFonts[file] then return false end
			self.__font = { file, size, flags }
			return true
		end,
		GetFont = function(self) if self.__font then return unpack(self.__font) end end,
		SetFontObject = function(self, object) self.__font = nil; self.__fontObject = object end,
		SetBackdropColor = function(self, r, g, b, a) self.__bg = { r, g, b, a } end,
		SetBackdropBorderColor = function(self, r, g, b, a) self.__border = { r, g, b, a } end,
		SetPoint = function(self, ...) self.__point = { ... } end,
		SetAttribute = function(self, k, v) self.__attributes = self.__attributes or {}; self.__attributes[k] = v end,
		-- animation groups
		Play = function(self) self.__playing = true; self.__plays = (self.__plays or 0) + 1 end,
		Stop = function(self) self.__playing = false end,
		IsPlaying = function(self) return self.__playing or false end,
		Click = function(self, button) if scripts.OnClick then scripts.OnClick(self, button or "LeftButton") end end,
	}
	return setmetatable(obj, { __index = function(_, k)
		if methods[k] then return methods[k] end
		if k == "SetLabel" then return nil end   -- only the addon's own widgets have it
		if type(k) == "string" and k:match("^%u%l+%u") then return function() end end
		return nil
	end })
end
T.Mock = Mock

function CreateFrame(kind, name, parent, template)
	local f = Mock(kind, name)
	f.__template = template
	if name then
		T.frames[name] = f
		_G[name] = f
	end
	return f
end
UIParent = Mock("Frame", "UIParent")
GameTooltip = Mock("GameTooltip", "GameTooltip")

-- Every frame listening to `event` hears it, then the short timers run.
function T.raw(event, ...)
	local listeners = {}
	for _, f in ipairs(T.all) do
		if f.__events[event] and f.__scripts.OnEvent then listeners[#listeners + 1] = f end
	end
	for _, f in ipairs(listeners) do f.__scripts.OnEvent(f, event, ...) end
end
function T.fire(event, ...)
	T.raw(event, ...)
	T.flush()
end

-- ---------------------------------------------------------------------------
-- Addons: loaded from their .toc, as the game does. Load-on-demand ones only
-- when C_AddOns.LoadAddOn asks for them.
-- ---------------------------------------------------------------------------
T.ADDONS = {
	CombatKit         = "",
	CombatKit_Loadout = "Modules/Loadout/",
	CombatKit_Stats   = "Modules/Stats/",
	CombatKit_Range   = "Modules/Range/",
	CombatKit_Misc    = "Modules/Misc/",
	CombatKit_Options = "Modules/Options/",
}
T.loaded = {}          -- addon name -> its private table
T.missing = {}         -- addon name -> true: pretend it is not installed
T.unticked = {}        -- addon name -> true: disabled in the game's AddOns list
T.loadOrder = {}

local function TocPath(name)
	local dir = T.ADDONS[name]
	return dir and (ROOT .. "/" .. dir .. name .. ".toc"), dir
end

local function Exists(name)
	if T.missing[name] then return false end
	local path = TocPath(name)
	if not path then return false end
	local f = io.open(path, "r")
	if f then f:close() return true end
	return false
end

function T.loadAddon(name)
	if T.loaded[name] then return true end
	local path, dir = TocPath(name)
	local private = {}
	for line in io.lines(path) do
		line = line:gsub("\r", "")
		if line ~= "" and not line:match("^#") then
			local file = ROOT .. "/" .. dir .. line:gsub("\\", "/")
			local chunk, err = loadfile(file)
			assert(chunk, err)
			chunk(name, private)
		end
	end
	T.loaded[name] = private
	T.loadOrder[#T.loadOrder + 1] = name
	T.raw("ADDON_LOADED", name)
	return true
end

C_AddOns = {
	GetAddOnMetadata = function() return "0.0.0" end,
	DoesAddOnExist = function(name) return Exists(name) end,
	IsAddOnLoaded = function(name) return T.loaded[name] ~= nil end,
	GetAddOnEnableState = function(name) return T.unticked[name] and 0 or 2 end,
	EnableAddOn = function(name) T.unticked[name] = nil; log("enableaddon:" .. name) end,
	LoadAddOn = function(name)
		if not Exists(name) then return false, "MISSING" end
		if T.unticked[name] then return false, "DISABLED" end
		return T.loadAddon(name)
	end,
}

-- Load the core the way a login does.
function T.boot()
	T.loadAddon("CombatKit")
	T.fire("PLAYER_LOGIN")
	return CombatKit
end

-- print is captured so addon chat output does not drown the results
T.chat = {}
function T.captureChat() print = function(...) T.chat[#T.chat + 1] = table.concat({ ... }, " ") end end
function T.releaseChat() print = realPrint end
function T.said(text)
	for _, line in ipairs(T.chat) do if line:find(text, 1, true) then return true end end
	return false
end

function T.report(label)
	realPrint(("%s: %d passed, %d failed"):format(label, T.passed, T.failed))
	return T.failed
end

return T
