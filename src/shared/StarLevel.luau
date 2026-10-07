-- Star level rules: stat scaling and how many 1-star copies a unit contains.
-- Pure Luau: no Roblox APIs, so it runs in Lune tests.

local CombatConfig = if script then require(script.Parent.CombatConfig) else require("./CombatConfig")
local StarConfig = if script then require(script.Parent.StarConfig) else require("./StarConfig")

local StarLevel = {}

-- Combat health for a listed health value at `starLevel`: times the star multiplier and
-- CombatConfig.globalHealthMultiplier (the roster health dial), rounded. Roster unit health and
-- form health pools (rider horses) both use it.
function StarLevel.scaleHealth(health: number, starLevel: number): number
	return math.round(health * StarConfig.healthMultiplier[starLevel] * CombatConfig.globalHealthMultiplier)
end

-- Creeps and bosses (PveThemeConfig units, `kind` "creep" or "boss") list their final combat
-- health: the roster health dial does not apply to them.
local function isPveUnit(stats): boolean
	return stats.kind == "creep" or stats.kind == "boss"
end

-- Returns a copy of `stats` scaled for combat at `starLevel`: health by the star multiplier and
-- (roster units only) CombatConfig.globalHealthMultiplier, attack damage by the star multiplier,
-- each rounded to a whole number. Nothing else scales. This is the only place a unit's combat
-- health is computed.
function StarLevel.scaleStats(stats: { [string]: any }, starLevel: number): { [string]: any }
	local scaled = table.clone(stats)
	scaled.health = if isPveUnit(stats)
		then math.round(stats.health * StarConfig.healthMultiplier[starLevel])
		else StarLevel.scaleHealth(stats.health, starLevel)
	scaled.attackDamage = math.round(stats.attackDamage * StarConfig.attackDamageMultiplier[starLevel])
	return scaled
end

-- Number of 1-star copies that make up one unit of `starLevel` (1, 3, 9).
function StarLevel.copiesIn(starLevel: number): number
	return StarConfig.copiesToMerge ^ (starLevel - 1)
end

return StarLevel
