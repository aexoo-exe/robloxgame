-- Player levels and XP. Values from docs/design/unit-stats-economy.md section 12.
-- A player's level is also their cap on units placed on the board.
return table.freeze({
	startingLevel = 2,
	maxLevel = 10,

	xpPerRound = 2, -- gained automatically at the start of every Preparation that follows a fight
	buyXpCost = 4, -- gold
	buyXpAmount = 4, -- XP

	-- XP needed to go from level n to level n + 1. Extra XP carries over.
	xpToNextLevel = table.freeze({
		[2] = 2,
		[3] = 6,
		[4] = 10,
		[5] = 20,
		[6] = 36,
		[7] = 56,
		[8] = 68,
		[9] = 68,
	}),
})
