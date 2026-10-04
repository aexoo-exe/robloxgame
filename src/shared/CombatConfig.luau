-- Combat simulation settings. The combat time limit is MatchConfig.combatMaxDuration.

local function unit(unitType: string, column: number, row: number)
	return table.freeze({ unitType = unitType, column = column, row = row })
end

return table.freeze({
	-- Fixed simulation rate. Attack and move intervals are rounded to whole ticks.
	ticksPerSecond = 20,

	-- Seconds the Combat phase continues after the fight ends, so the last animations can finish.
	endPadding = 1.5,

	-- Opponents for a player who is alone, by round. Round n uses entry n; rounds past the end of
	-- the list reuse the last entry. Positions are in the enemy's own board coordinates
	-- (row 1 = back row, BoardConfig.rows = front row). Unit counts roughly track the player's
	-- unit cap (= level) when they do not buy XP.
	enemyBoardsByRound = table.freeze({
		-- Round 1: player is level 2 (2 units)
		table.freeze({ unit("Tank1", 4, 4), unit("Archer1", 4, 1) }),
		-- Round 2: level 3
		table.freeze({ unit("Tank1", 3, 4), unit("Tank1", 5, 4), unit("Archer1", 4, 1) }),
		-- Round 3
		table.freeze({ unit("Tank1", 3, 4), unit("Tank2", 4, 4), unit("Archer1", 4, 1) }),
		-- Round 4
		table.freeze({ unit("Tank2", 4, 4), unit("Striker2", 3, 4), unit("Archer1", 4, 1) }),
		-- Round 5: level 4
		table.freeze({ unit("Tank2", 3, 4), unit("Tank1", 5, 4), unit("Striker2", 4, 3), unit("Archer1", 4, 1) }),
		-- Round 6
		table.freeze({ unit("Tank2", 3, 4), unit("Tank2", 5, 4), unit("Striker2", 4, 3), unit("Archer1", 4, 1) }),
		-- Round 7
		table.freeze({ unit("Tank3", 4, 4), unit("Tank2", 3, 4), unit("Striker2", 5, 3), unit("Archer3", 4, 1) }),
		-- Round 8 onwards: level 5
		table.freeze({
			unit("Tank3", 4, 4),
			unit("Tank2", 3, 4),
			unit("Striker2", 5, 3),
			unit("Archer3", 4, 1),
			unit("Archer1", 2, 1),
		}),
	}),
})
