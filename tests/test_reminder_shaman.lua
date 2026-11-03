-- The Reminder module for an Enhancement shaman: imbues on either hand, or
-- their buff; no weapon oil on hands the imbues are for.

local T = dofile(HERE .. "/stubs.lua")
local check, eq, W, fire = T.check, T.eq, T.W, T.fire
T.captureChat()

local WINDFURY, FLAMETONGUE, LIGHTNING = 33757, 318038, 192106
W.units.player = { class = "SHAMAN" }
W.specs = { { 262, "Elemental" }, { 263, "Enhancement" }, { 264, "Restoration" } }
W.specIndex = 2
W.known = { [WINDFURY] = true, [FLAMETONGUE] = true, [LIGHTNING] = true }
W.playerAuras = { [LIGHTNING] = { expirationTime = W.now + 3600 } }
W.equip = { [16] = 1001, [17] = 1002 }
W.itemInfo = { [1001] = { 2, "INVTYPE_WEAPON" }, [1002] = { 2, "INVTYPE_WEAPON" } }
W.inInstance, W.instanceType, W.difficultyID = true, "party", 2
local CK = T.boot()
CK.SetModuleEnabled("Reminder", true)
local RM = CK.modules.Reminder
local L = CK.L
RM.db.consumables = { flask = false, food = false, rune = false, oil = true, healthstone = false }
fire("PLAYER_ENTERING_WORLD")
local function find(label)
	local frame, icons, buttons = RM.GetDisplay()
	if not frame or not frame:IsShown() then return nil end
	for i, b in ipairs(icons) do
		if b:IsShown() and b.label:GetText() == label then
			return { text = b.text:GetText(), icon = b.icon:GetTexture(), button = buttons[i] }
		end
	end
end

local WF, FT = "spell" .. WINDFURY, "spell" .. FLAMETONGUE

check(find(WF) and find(FT), "no imbue: both")
check(not find(L["Weapon oil"]) and not find(L["Off-hand oil"]), "no weapon oil on hands the imbues are for")
W.tempEnchant = { [16] = { 5400, 3000000 }, [17] = { 5401, 3000000 } }
fire("UNIT_INVENTORY_CHANGED", "player")
check(not find(WF) and not find(FT), "the two on the other hands than expected: fine, either hand counts")
W.tempEnchant = nil
W.playerAuras[319773] = { expirationTime = W.now + 3000 }
fire("UNIT_INVENTORY_CHANGED", "player")
check(not find(WF) and find(FT), "Windfury's buff counts as Windfury")

local spec = {}
for _, item in ipairs(RM.ClassItems()) do spec[item.key] = item.spec or "all" end
check(spec.skyfury == "all" and spec.windfury[263] and not spec.windfury[262] and spec.flametongue[262] and spec.flametongue[263]
	and spec.earthliving[264], "the class page's specs: Skyfury every spec's, Windfury Enhancement's, Flametongue two specs'")
W.playerAuras[319773] = nil
W.specIndex = 3
fire("PLAYER_SPECIALIZATION_CHANGED", "player")
check(not find(WF), "Restoration: no Windfury, known or not")

T.releaseChat()
return T.report("reminder shaman [" .. (LOCALE or "enUS") .. "]")
