local CK = CombatKit
local L, Skin, O = CK.L, CK.Skin, CK.Options

-- Settings page of the Stats module. Left: how they are shown. Right: which
-- stats, in which order; each with its English name next to it, since that is
-- what guides and the HUD's English option use.

local ROW_H       = 22
local ARROWS_W    = 18 + 2 + 18   -- the up and down buttons and the gap between them
local LIST_GAP    = 10            -- between the buttons and the checkbox
local LIST_MARGIN = 80            -- between the list and the right edge of the page
local ST   -- the module, set whenever the section is used

local function Changed()
	O.Changed()
end

-- The list sits at the right of the page, a margin from its edge and as wide
-- as its widest label; the fields on the left get the rest, whatever the language.
local function PlaceList(p)
	local w = 0
	for _, r in ipairs(p.rows) do w = math.max(w, r.check:GetWidth()) end
	local x = O.PageWidth() - LIST_MARGIN - (ARROWS_W + LIST_GAP + w)
	for i, r in ipairs(p.rows) do
		r.up:SetPoint("TOPLEFT", x, -(i - 1) * ROW_H)
	end
end

local function Build(p)
	Skin.Field(p, "Decimals", 0, 0)
	local stepper = Skin.Stepper(p, function(dir)
		ST.db.decimals = math.max(0, math.min(2, ST.db.decimals + dir))
		Changed()
	end)
	stepper:SetPoint("TOPLEFT", O.FIELD_X, 0)
	p.decimals = stepper.value

	p.english = CK.Bind(Skin.Checkbox(p, "", function(checked)
		ST.db.english = checked or nil
		Changed()
	end), "English on the HUD")
	p.english:SetPoint("TOPLEFT", O.FIELD_X, -29)

	p.rows = {}
	for i = 1, #ST.STATS do
		local r = {}
		r.check = Skin.Checkbox(p, "", function(checked)
			ST.db.shown[r.key] = checked or nil
			Changed()
		end)
		r.up = Skin.ArrowButton(p, true, function() ST.Move(r.key, -1); Changed() end)
		r.down = Skin.ArrowButton(p, false, function() ST.Move(r.key, 1); Changed() end)
		r.down:SetPoint("LEFT", r.up, "RIGHT", 2, 0)
		r.check:SetPoint("LEFT", r.down, "RIGHT", LIST_GAP, 0)
		p.rows[i] = r
	end
	PlaceList(p)
end

local function Refresh(p)
	p.decimals:SetText(tostring(ST.db.decimals))
	p.english:SetChecked(ST.db.english)
	for i, key in ipairs(ST.db.order) do
		local r = p.rows[i]
		r.key = key
		local name, english = ST.StatLabel(key), ST.StatEnglish(key)
		r.check:SetLabel(name == english and name or (name .. "  " .. Skin.Text("dim", english)))
		r.check:SetChecked(ST.db.shown[key])
	end
	PlaceList(p)
end

O.AddSection({
	key = "Stats",
	module = "Stats",
	order = 20,
	tab = function() return L["MOD_Stats"] end,
	GetNodes = function() return { { key = "stats", label = L["MOD_Stats"] } } end,
	GetHeader = function() return L["MOD_Stats"], L["STATS_DESC"] end,
	Build = function(body) ST = CK.modules.Stats; Build(body) end,
	Refresh = function(_, body) ST = CK.modules.Stats; Refresh(body) end,
})
