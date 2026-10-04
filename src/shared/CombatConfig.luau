-- Combat simulation settings. The combat time limit is MatchConfig.combatMaxDuration.
return table.freeze({
	-- Fixed simulation rate. Attack and move intervals are rounded to whole ticks.
	ticksPerSecond = 20,

	-- Seconds the Combat phase continues after the fight ends, so the last animations can finish.
	endPadding = 1.5,

	-- The opponent when only one player is present, in that opponent's own board coordinates
	-- (row 1 = back row, BoardConfig.rows = front row).
	presetEnemyBoard = table.freeze({
		table.freeze({ unitType = "Guardian", column = 4, row = 4 }),
		table.freeze({ unitType = "Brawler", column = 3, row = 4 }),
		table.freeze({ unitType = "Striker", column = 6, row = 3 }),
		table.freeze({ unitType = "Archer", column = 2, row = 1 }),
	}),
})
