local ADDON, ns = ...
local L = ns.L

-- ===========================================================================
-- Smart gear check: a text on screen when the gear does not fit the scenario
--
-- "PvP gear" is both trinkets being PvP items. Those carry the Gladiator set
-- whatever the season, and the tooltip names it ("Gladiator's Distinction
-- (2/2)"), as it names a Gladiator item itself. Arena and battlegrounds want
-- PvP gear; dungeons and raids do not. Open world and delves are not judged: a
-- player waiting for a PvP queue wears what the queue wants.
--
-- The text stays until the first combat of that visit, then keeps quiet unless
-- the gear was put right and goes wrong again. Nothing while a key or a match
-- runs, since nothing can be changed then.
-- ===========================================================================

local TRINKETS  = { 13, 14 }   -- INVSLOT_TRINKET1, INVSLOT_TRINKET2
local WANTS_PVP = { arena = true, bg = true, dungeon = false, raid = false }   -- absent: not judged
local FONT_SIZE, Y = 24, 200   -- above the character, clear of the combat alert's default spot
local TEXT = { pvp = "Switch to PvP gear", pve = "Switch to PvE gear" }
-- "Gladiator" as the clients spell it. Lines are matched in lower case (the
-- French write it small); lower() leaves other scripts alone, so both cases.
local KEYWORDS = { "gladiator", "gladiateur", "gladiador", "gladiatore", "Гладиатор", "гладиатор", "검투사", "角斗士", "鬥士" }

local function HasKeyword(text)
	local lower = text:lower()
	for _, kw in ipairs(KEYWORDS) do
		if lower:find(kw, 1, true) then return true end
	end
	return false
end

-- The set line "Gladiator's Distinction (2/2)", in the client's own format:
-- returns the set's name, or nil for any other line
local setPattern
local function SetName(text)
	if not setPattern then
		local s = type(ITEM_SET_NAME) == "string" and ITEM_SET_NAME or "%s (%d/%d)"
		s = s:gsub("[%(%)%.%%%+%-%*%?%[%]%^%$]", "%%%0")   -- magic characters escaped
		s = s:gsub("%%%%s", "(.-)"):gsub("%%%%d", "%%d+")   -- the name, the counts
		setPattern = "^" .. s .. "$"
	end
	return text:match(setPattern)
end

-- A PvP item names the Gladiator set in its tooltip, or is a Gladiator item itself
local function IsPvPItem(slot)
	if not (C_TooltipInfo and C_TooltipInfo.GetInventoryItem) then return false end
	local ok, data = pcall(C_TooltipInfo.GetInventoryItem, "player", slot)
	if not ok or type(data) ~= "table" then return false end
	if TooltipUtil and TooltipUtil.SurfaceArgs then pcall(TooltipUtil.SurfaceArgs, data) end
	for i, line in ipairs(data.lines or {}) do
		local text = line.leftText
		if not (issecretvalue and issecretvalue(text)) and type(text) == "string" then
			if i == 1 then
				if HasKeyword(text) then return true end   -- the item's name
			else
				local set = SetName(text)
				if set and HasKeyword(set) then return true end
			end
		end
	end
	return false
end

-- "pvp" (a PvP scenario without PvP gear), "pve" (a PvE one with it), or nil
function ns.JudgeGear(key)
	local wants = WANTS_PVP[key]
	if wants == nil then return nil end
	local pvp = IsPvPItem(TRINKETS[1]) and IsPvPItem(TRINKETS[2])
	if wants and not pvp then return "pvp" end
	if not wants and pvp then return "pve" end
	return nil
end

local frame
local lastKey, dismissed   -- the scenario of the last check; combat was seen while the text showed

local function Create()
	frame = CreateFrame("Frame", "CombatKitGearWarning", UIParent)
	frame:SetSize(600, 40)
	frame:SetPoint("CENTER", UIParent, "CENTER", 0, Y)
	frame:SetFrameStrata("MEDIUM")
	frame.text = frame:CreateFontString(nil, "ARTWORK")
	frame.text:SetAllPoints()
	frame.text:SetJustifyH("CENTER")
	frame.text:SetJustifyV("MIDDLE")
	frame.text:SetFont(STANDARD_TEXT_FONT, FONT_SIZE, "OUTLINE")
	frame.text:SetTextColor(1, 0.25, 0.25)
	frame:Hide()
end

-- Called with the scenario by every check, and with nil when the module goes off.
function ns.UpdateGearWarning(key)
	if key ~= lastKey then lastKey, dismissed = key, false end
	local verdict
	if key and ns.db.settings.gearCheck and not ns.IsLocked() then verdict = ns.JudgeGear(key) end
	if not verdict then dismissed = false end   -- put right: a later slip is told again
	if dismissed then verdict = nil end
	if not verdict and not frame then return end
	if not frame then Create() end
	if verdict then frame.text:SetText(L[TEXT[verdict]]) end
	frame:SetShown(verdict ~= nil)
end

-- Combat started: the text has done its job for this visit
function ns.OnGearWarningCombat()
	if frame and frame:IsShown() then
		dismissed = true
		frame:Hide()
	end
end
