-- Star levels from duplicate copies. Values from docs/design/unit-stats-economy.md section 4.
-- Star level is its own unit field and is used for nothing else (section 15).
return table.freeze({
	maxStarLevel = 3,

	-- Owning this many copies of one unit at one star level merges them into one unit of the next
	-- star level. A unit's sell value is its cost times the copies it contains:
	-- copiesToMerge ^ (starLevel - 1).
	copiesToMerge = 3,

	-- Multipliers by star level (1, 2, 3). Only health and attack damage scale.
	healthMultiplier = table.freeze({ 1, 1.8, 3.24 }),
	attackDamageMultiplier = table.freeze({ 1, 1.5, 2.25 }),
})
