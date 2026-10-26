local ADDON, ns = ...

-- ===========================================================================
-- Profiles: named sets of the module's settings (the look, where the rows
-- go, which spells are watched), to switch between and to pass on as text.
--
-- The settings in force stay where they always were, at the top of the saved
-- data; db.profiles keeps a copy per name, brought up to date whenever the
-- copy is wanted (switching away, exporting, a new profile). The debug
-- settings and the log belong to no profile.
--
-- The text is PREFIX and the settings written as a small table literal.
-- Reading it back goes through a parser of that one format, never loadstring,
-- and every value is checked against what its setting can be before it is
-- taken: a pasted text can only ever set settings, to values they allow.
-- ===========================================================================

local Profiles = {}
ns.Profiles = Profiles

local PREFIX = "CombatKitPartyCD:1:"
local DEFAULT = "Default"
local MAX_TEXT = 20000   -- longer than any real profile; a paste beyond it is not read
local MAX_DEPTH = 4

-- what a profile holds, and what each value may be: numbers within the
-- settings page's ranges, one of a few words, true or false
local NUMBERS = { iconSize = { 16, 48 }, spacing = { 0, 12 }, maxPerRow = { 1, 12 }, lines = { 1, 6 },
	offset = { -40, 80 }, offsetAlong = { -80, 80 } }
local CHOICES = {
	side = { RIGHT = true, LEFT = true, TOP = true, BOTTOM = true },
	grow = { down = true, up = true, center = true, left = true, right = true },
	glowStyle = { ants = true, thin = true, proc = true },
	perRow = { max = true, even = true },
}
local FLAGS = { trinket = true, attach = true }
local POINTS = { TOPLEFT = true, TOP = true, TOPRIGHT = true, LEFT = true, CENTER = true, RIGHT = true,
	BOTTOMLEFT = true, BOTTOM = true, BOTTOMRIGHT = true }
local SCREEN = 5000   -- a loose row's position, in either direction

local function Copy(v)
	if type(v) ~= "table" then return v end
	local t = {}
	for k, x in pairs(v) do t[k] = Copy(x) end
	return t
end

local function Clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end

-- the profile's part of a set of settings (the saved data, or an imported table)
local function Take(db)
	local t = {}
	for k in pairs(NUMBERS) do t[k] = db[k] end
	for k in pairs(CHOICES) do t[k] = db[k] end
	for k in pairs(FLAGS) do t[k] = db[k] end
	t.picked = Copy(db.picked)
	t.rows = Copy(db.rows)
	return t
end

-- Only what a setting can be, from whatever came in; what is missing or
-- wrong takes the default
local function Clean(t)
	local d = ns.defaults
	local out = {}
	for k, range in pairs(NUMBERS) do
		local v = t[k]
		out[k] = type(v) == "number" and v == v and Clamp(math.floor(v + 0.5), range[1], range[2]) or d[k]
	end
	for k, set in pairs(CHOICES) do out[k] = set[t[k]] and t[k] or d[k] end
	for k in pairs(FLAGS) do
		if type(t[k]) == "boolean" then out[k] = t[k] else out[k] = d[k] end
	end
	out.picked = {}
	if type(t.picked) == "table" then
		for id, on in pairs(t.picked) do
			if type(id) == "number" and ns.SPELL_BY_ID[id] and type(on) == "boolean" then out.picked[id] = on end
		end
	end
	out.rows = {}
	local rows = type(t.rows) == "table" and t.rows or {}
	for _, unit in ipairs(ns.TEAM) do
		local r = rows[unit]
		if type(r) == "table" and POINTS[r.point] and POINTS[r.relPoint] and type(r.x) == "number"
			and type(r.y) == "number" and r.x == r.x and r.y == r.y then
			out.rows[unit] = { point = r.point, relPoint = r.relPoint,
				x = Clamp(math.floor(r.x + 0.5), -SCREEN, SCREEN), y = Clamp(math.floor(r.y + 0.5), -SCREEN, SCREEN) }
		else
			out.rows[unit] = Copy(d.rows[unit])
		end
	end
	return out
end

-- ---------------------------------------------------------------------------
-- Text
-- ---------------------------------------------------------------------------

local function Write(v)
	local kind = type(v)
	if kind == "number" then
		if v == math.floor(v) then return string.format("%d", v) end
		return string.format("%.3f", v)
	elseif kind == "boolean" then
		return v and "true" or "false"
	elseif kind == "string" then
		return '"' .. v:gsub('[\\"]', "") .. '"'   -- the words a profile holds have neither
	elseif kind == "table" then
		local keys = {}
		for k in pairs(v) do keys[#keys + 1] = k end
		table.sort(keys, function(a, b)
			if type(a) == type(b) then return a < b end
			return type(a) == "number"
		end)
		local parts = {}
		for _, k in ipairs(keys) do
			local key = type(k) == "number" and ("[" .. string.format("%d", k) .. "]") or k
			parts[#parts + 1] = key .. "=" .. Write(v[k])
		end
		return "{" .. table.concat(parts, ",") .. "}"
	end
	return "false"
end

-- The one format Write gives, read back: tables, whole or decimal numbers,
-- true / false, plain words in quotes. Anything else is not a profile.
local function Read(s)
	local pos = 1
	local function skip() pos = s:find("[^ \t\r\n]", pos) or #s + 1 end
	local function char() return s:sub(pos, pos) end
	local value
	local function key()
		skip()
		local id = s:match("^[%a_][%w_]*", pos)
		if id then pos = pos + #id return id end
		local num = s:match("^%[(%-?%d+)%]", pos)
		if num then pos = pos + #num + 2 return tonumber(num) end
		error("key", 0)
	end
	function value(depth)
		if depth > MAX_DEPTH then error("depth", 0) end
		skip()
		local c = char()
		if c == "{" then
			pos = pos + 1
			local t = {}
			skip()
			if char() == "}" then pos = pos + 1 return t end
			while true do
				local k = key()
				skip()
				if char() ~= "=" then error("=", 0) end
				pos = pos + 1
				t[k] = value(depth + 1)
				skip()
				local d = char()
				pos = pos + 1
				if d == "}" then return t end
				if d ~= "," then error(",", 0) end
			end
		elseif c == '"' then
			local str = s:match('^"([^"\\]*)"', pos)
			if not str then error("string", 0) end
			pos = pos + #str + 2
			return str
		end
		local word = s:match("^%a+", pos)
		if word == "true" or word == "false" then pos = pos + #word return word == "true" end
		local num = s:match("^%-?%d+%.?%d*", pos)
		if num then pos = pos + #num return tonumber(num) end
		error("value", 0)
	end
	local ok, v = pcall(value, 1)
	if not ok then return nil end
	skip()
	if pos <= #s then return nil end
	return v
end

-- ---------------------------------------------------------------------------
-- Profiles
-- ---------------------------------------------------------------------------

-- once the saved data is read: every install has at least the default profile, and one in force
function Profiles.Init(db)
	if type(db.profiles) ~= "table" then db.profiles = {} end
	if type(db.profile) ~= "string" or type(db.profiles[db.profile]) ~= "table" then
		db.profile = DEFAULT
		db.profiles[DEFAULT] = db.profiles[DEFAULT] or Take(db)
	end
end

local function Save()
	local db = ns.db
	db.profiles[db.profile] = Take(db)
end

function Profiles.Current() return ns.db.profile end

function Profiles.Names()
	local names = {}
	for name in pairs(ns.db.profiles) do names[#names + 1] = name end
	table.sort(names)
	return names
end

-- switch to another profile: the one in force is kept as it is now, the other's settings take over
function Profiles.Use(name)
	local db = ns.db
	if type(db.profiles[name]) ~= "table" then return false end
	if name ~= db.profile then
		Save()
		local t = Clean(db.profiles[name])
		for k, v in pairs(t) do db[k] = Copy(v) end
		db.profile = name
	end
	ns.Apply()
	return true
end

-- a new profile, a copy of the settings in force, and in force from now on
function Profiles.New(name)
	local db = ns.db
	name = type(name) == "string" and strtrim(name) or ""
	if name == "" or db.profiles[name] then return false end
	Save()
	db.profiles[name] = Take(db)
	db.profile = name
	return true
end

-- a profile removed; the one in force gives way to another first; the last one stays
function Profiles.Delete(name)
	local db = ns.db
	if type(db.profiles[name]) ~= "table" then return false end
	local names = Profiles.Names()
	if #names < 2 then return false end
	if name == db.profile then
		for _, other in ipairs(names) do
			if other ~= name then Profiles.Use(other) break end
		end
	end
	db.profiles[name] = nil
	return true
end

-- a profile as text (the one in force as it is now)
function Profiles.Export(name)
	local db = ns.db
	name = name or db.profile
	if name == db.profile then Save() end
	local t = db.profiles[name]
	if type(t) ~= "table" then return nil end
	return PREFIX .. Write(Clean(t))
end

-- Text back into a profile, under the name given (or "Imported"), never over
-- one that exists: a number is added. It is put in force. Returns the name, or
-- nil when the text is not a profile.
function Profiles.Import(text, name)
	if type(text) ~= "string" or #text > MAX_TEXT then return nil end
	text = strtrim(text)
	if text:sub(1, #PREFIX) ~= PREFIX then return nil end
	local t = Read(text:sub(#PREFIX + 1))
	if type(t) ~= "table" then return nil end
	local db = ns.db
	local base = type(name) == "string" and strtrim(name) ~= "" and strtrim(name) or "Imported"
	name = base
	local n = 1
	while db.profiles[name] do
		n = n + 1
		name = base .. " " .. n
	end
	Save()
	db.profiles[name] = Clean(t)
	Profiles.Use(name)
	return name
end

-- for the tests
Profiles.Write, Profiles.Read, Profiles.PREFIX = Write, Read, PREFIX
