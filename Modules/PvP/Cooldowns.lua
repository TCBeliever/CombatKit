local ADDON, ns = ...

-- ===========================================================================
-- The cooldown a teammate's ability has: the base one, changed by the talents
-- that were read (Inspect.lua), or set by hand (/ckpvp cd).
--
-- basis: "custom" (set by hand) | "talents" (every talent read) | "partial"
--        (some talents read, the rest unknown) | "base" (nothing read)
-- ===========================================================================

local C = {}
ns.Cooldowns = C

-- info: { spec=, talents = { spellID = rank }, pvp = { id = true }, traitComplete=, pvpComplete= } or nil
local function Applies(mod, info)
	if mod.specs and (not info.spec or not mod.specs[info.spec]) then return nil end
	if mod.pvp then
		if info.pvp and info.pvp[mod.talent] then return 1 end
		return nil
	end
	local rank = info.talents and info.talents[mod.talent]
	if type(rank) == "number" and rank > 0 then return rank end
	if info.pvp and info.pvp[mod.talent] then return 1 end
	return nil
end

-- Answers { cd=, charges=, basis=, assumes = { talent spellIDs } }
function C.Resolve(ability, info, custom)
	local out = { cd = ability.cd, charges = ability.charges or 1, basis = "base", assumes = {} }
	if custom and type(custom[ability.id]) == "number" and custom[ability.id] > 0 then
		out.cd, out.basis = custom[ability.id], "custom"
		return out
	end
	if not info or not (info.talents or info.pvp) then return out end
	local flat, pct, extra = 0, 1, 0
	for _, mod in ipairs(ability.mods or {}) do
		local rank = Applies(mod, info)
		if rank then
			local amount = mod.amount * (mod.perRank and rank or 1)
			if mod.kind == "flat" then flat = flat + amount
			elseif mod.kind == "percent" then pct = pct * (1 - amount / 100)
			elseif mod.kind == "charges" then extra = extra + amount end
			out.assumes[#out.assumes + 1] = mod.talent
		end
	end
	out.cd = math.max(1, math.floor((ability.cd - flat) * pct + 0.5))
	out.charges = out.charges + extra
	out.basis = (info.traitComplete and info.pvpComplete) and "talents" or "partial"
	return out
end

-- One line for /ckpvp entries
function C.Explain(resolved)
	if resolved.basis == "custom" then return "set by hand" end
	if resolved.basis == "base" then return "base cooldown, talents not read" end
	local ids = {}
	for _, id in ipairs(resolved.assumes) do ids[#ids + 1] = tostring(id) end
	local what = #ids > 0 and ("talents " .. table.concat(ids, ", ")) or "no talent changes it"
	if resolved.basis == "partial" then return what .. " (partial read)" end
	return what
end
