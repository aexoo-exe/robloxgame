-- Star level rules: stat scaling and how many 1-star copies a unit contains.
-- Pure Luau: no Roblox APIs, so it runs in Lune tests.

local StarConfig = if script then require(script.Parent.StarConfig) else require("./StarConfig")

local StarLevel = {}

-- Returns a copy of `stats` with health and attack damage scaled for `starLevel`, rounded to whole
-- numbers. Nothing else scales. This is the only place star multipliers are applied.
function StarLevel.scaleStats(stats: { [string]: any }, starLevel: number): { [string]: any }
	local scaled = table.clone(stats)
	scaled.health = math.round(stats.health * StarConfig.healthMultiplier[starLevel])
	scaled.attackDamage = math.round(stats.attackDamage * StarConfig.attackDamageMultiplier[starLevel])
	return scaled
end

-- Number of 1-star copies that make up one unit of `starLevel` (1, 3, 9).
function StarLevel.copiesIn(starLevel: number): number
	return StarConfig.copiesToMerge ^ (starLevel - 1)
end

return StarLevel
