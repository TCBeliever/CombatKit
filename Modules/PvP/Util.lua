local ADDON, ns = ...

-- Small shared things: safe reads of values that may be secret, the clock,
-- a ring log for /ckpvp log.

local U = {}
ns.Util = U

U.LOG_CAP = 300

function U.clock() return GetTime() end

-- a value an addon may use: not secret (and not an error)
function U.Access(v)
	return canaccessvalue(v) == true
end

-- fn(...) when it answers with a value the addon may use, else nil
function U.Plain(fn, ...)
	if type(fn) ~= "function" then return nil end
	local ok, v = pcall(fn, ...)
	if ok and canaccessvalue(v) then return v end
	return nil
end

-- t[key] of a table the addon may read, else nil
function U.Field(t, key)
	if type(t) ~= "table" or not canaccessvalue(t) then return nil end
	if type(canaccesstable) == "function" and not canaccesstable(t) then return nil end
	return U.Plain(function() return t[key] end)
end

-- the regime the probe runs in; a scan that straddles a change is discarded
function U.Regime()
	local secret = C_Secrets and U.Plain(C_Secrets.ShouldAurasBeSecret)
	return tostring(secret) .. "/" .. tostring(InCombatLockdown())
end

-- ---------------------------------------------------------------------------
-- Log
-- ---------------------------------------------------------------------------

local rows, total = {}, 0
local epoch

local function text(v)
	if v == nil then return "-" end
	if not canaccessvalue(v) then return "<secret>" end
	return tostring(v)
end

function U.Log(kind, unit, key, detail)
	local now = U.clock()
	epoch = epoch or now
	total = total + 1
	rows[((total - 1) % U.LOG_CAP) + 1] = string.format("%7.1f %-9s %-7s %-7s %s",
		now - epoch, text(kind), text(unit), text(key), text(detail))
end

function U.LogLines(n)
	n = math.min(n or 20, total, U.LOG_CAP)
	local out = {}
	for i = total - n + 1, total do out[#out + 1] = rows[((i - 1) % U.LOG_CAP) + 1] end
	return out
end

function U.LogCount() return math.min(total, U.LOG_CAP), total end

function U.LogReset()
	rows, total, epoch = {}, 0, nil
end
