-- Stage, player damage and elimination ranking rules (docs/design/match-structure.md sections 2, 3
-- and 5). Pure Luau: no Roblox APIs, so it runs in Lune tests.

local SeededRandom = if script then require(script.Parent.SeededRandom) else require("./SeededRandom")
local StageConfig = if script then require(script.Parent.StageConfig) else require("./StageConfig")

local MatchRules = {}

-- Stage number (1, 2, ...) for a round.
function MatchRules.stage(round: number): number
	local current = 1
	for index, stage in StageConfig.stages do
		if round >= stage.firstRound then
			current = index
		end
	end
	return current
end

function MatchRules.baseDamage(round: number): number
	return StageConfig.stages[MatchRules.stage(round)].baseDamage
end

-- Damage a player takes for losing a fight in `round` against `survivingEnemyUnits` survivors.
function MatchRules.playerDamage(round: number, survivingEnemyUnits: number): number
	return MatchRules.baseDamage(round) + survivingEnemyUnits * StageConfig.damagePerSurvivingUnit
end

export type EliminationEntry = {
	id: number,
	healthAfter: number, -- HP after this round's damage (0 or less)
	healthBefore: number, -- HP entering this round
	survivors: number, -- the player's own surviving units in their final combat
}

-- Orders players eliminated in the same round from best to worst: higher HP after damage, then
-- higher HP entering the round, then more surviving units in their final combat, then a random
-- tie-break drawn from `rng`.
function MatchRules.rankEliminated(entries: { EliminationEntry }, rng: SeededRandom.SeededRandom): { number }
	local keyed = {}
	for _, entry in entries do
		table.insert(keyed, { entry = entry, random = SeededRandom.nextInt(rng, 1000000) })
	end
	table.sort(keyed, function(a, b)
		local x, y = a.entry, b.entry
		if x.healthAfter ~= y.healthAfter then
			return x.healthAfter > y.healthAfter
		elseif x.healthBefore ~= y.healthBefore then
			return x.healthBefore > y.healthBefore
		elseif x.survivors ~= y.survivors then
			return x.survivors > y.survivors
		elseif a.random ~= b.random then
			return a.random > b.random
		end
		return x.id < y.id
	end)
	local ranked = {}
	for _, item in keyed do
		table.insert(ranked, item.entry.id)
	end
	return ranked
end

return MatchRules
