-- Combat simulation settings. The combat time limit is MatchConfig.combatMaxDuration.

local function unit(unitType: string, column: number, row: number, starLevel: number?)
	return table.freeze({ unitType = unitType, column = column, row = row, starLevel = starLevel or 1 })
end

return table.freeze({
	-- Fixed simulation rate. Attack and move intervals are rounded to whole ticks.
	ticksPerSecond = 20,

	-- Seconds the Combat phase continues after the fight ends, so the last animations can finish.
	endPadding = 1.5,

	-- A fight that reaches the time limit is a draw when both sides' remaining health percentages are
	-- within this fraction (1 percentage point) of each other. docs/design/match-structure.md section 6.
	timeoutDrawMargin = 0.01,

	-- Every unit's combat health is its UnitConfig health times this (and its star multiplier); see
	-- StarLevel.scaleStats. UnitConfig keeps the design docs' base values. Player health and player
	-- damage are separate and unaffected. docs/design/balance-pass-v0.4.md section 3: 1.15 -> 1.12.
	globalHealthMultiplier = 1.12,

	-- Global combat rules from docs/design/combat-and-roster.md section 1. Every unit uses these.
	critChance = 0.25, -- per basic attack; abilities cannot crit
	critDamage = 1.4, -- multiplier on the raw basic-attack damage
	baseAbilityPower = 100, -- magic ability damage, heals and shields scale by AP / this
	manaPerAttack = 10, -- gained by the attacker for each completed basic attack
	manaPerPercentHealthLost = 5, -- gained per 1% of max health lost to post-mitigation damage
	maxManaPerDamage = 10, -- cap on mana gained from one damage event
	castTime = 0.75, -- seconds a caster cannot act after casting
	baseMoveSpeed = 1, -- hexes per second at a unit's move speed scalar of 1.0

	-- Opponents for a player who is alone, by round. Round n uses entry n; rounds past the end of
	-- the list reuse the last entry. Positions are in the enemy's own board coordinates
	-- (row 1 = back row, BoardConfig.rows = front row); the optional 4th argument is the star level.
	-- Unit counts roughly track the player's unit cap (= level), and from round 9 the boards add
	-- 2-star units. Costs, star levels, counts and positions were tuned for the old placeholder
	-- roster (docs/star-upgrades-plan.md); for roster v0.1 some units were swapped for a character
	-- of the same cost and a similar role so the full roster appears. They are not retuned.
	-- Practice enemies never draw from the shared pool.
	enemyBoardsByRound = table.freeze({
		-- Round 1: player is level 2 (2 units)
		table.freeze({ unit("Bren", 4, 4), unit("Sola", 4, 1) }),
		-- Round 2: level 3
		table.freeze({ unit("Kaien", 4, 4), unit("Mira", 3, 1), unit("Sola", 5, 1) }),
		-- Round 3
		table.freeze({ unit("Bren", 3, 4), unit("Rook", 4, 4), unit("Mira", 4, 1) }),
		-- Round 4
		table.freeze({ unit("Tarek", 4, 4), unit("Sena", 3, 4), unit("Ione", 4, 1) }),
		-- Round 5: level 4
		table.freeze({ unit("Rook", 3, 4), unit("Marek", 5, 4), unit("Sena", 4, 3), unit("Mira", 4, 1) }),
		-- Round 6: level 5
		table.freeze({
			unit("Rook", 3, 4),
			unit("Tarek", 5, 4),
			unit("Vela", 4, 3),
			unit("Mira", 3, 1),
			unit("Sola", 5, 1),
		}),
		-- Round 7
		table.freeze({
			unit("Vael", 4, 4),
			unit("Rook", 3, 4),
			unit("Sena", 5, 3),
			unit("Veyra", 4, 1),
			unit("Solenne", 2, 1),
		}),
		-- Round 8: level 6
		table.freeze({
			unit("Dax", 4, 4),
			unit("Rook", 3, 4),
			unit("Tarek", 5, 4),
			unit("Vela", 6, 3),
			unit("Veyra", 4, 1),
			unit("Solenne", 2, 1),
		}),
		-- Round 9: first 2-star
		table.freeze({
			unit("Dax", 4, 4),
			unit("Rook", 3, 4, 2),
			unit("Marek", 5, 4),
			unit("Sena", 6, 3),
			unit("Veyra", 4, 1),
			unit("Solenne", 2, 1),
		}),
		-- Round 10
		table.freeze({
			unit("Vael", 4, 4),
			unit("Rook", 3, 4, 2),
			unit("Tarek", 5, 4),
			unit("Sena", 6, 3, 2),
			unit("Veyra", 4, 1),
			unit("Solenne", 2, 1),
		}),
		-- Round 11
		table.freeze({
			unit("Dax", 4, 4),
			unit("Rook", 3, 4, 2),
			unit("Torra", 5, 4),
			unit("Sena", 6, 3, 2),
			unit("Veyra", 4, 1),
			unit("Solenne", 2, 1),
		}),
		-- Round 12 onwards
		table.freeze({
			unit("Dax", 4, 4, 2),
			unit("Rook", 3, 4, 2),
			unit("Orin", 5, 4),
			unit("Vela", 6, 3, 2),
			unit("Veyra", 4, 1),
			unit("Solenne", 2, 1),
		}),
	}),
})
