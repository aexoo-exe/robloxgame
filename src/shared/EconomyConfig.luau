-- Gold economy. Values from docs/design/unit-stats-economy.md sections 9-11.
return table.freeze({
	-- Section 10: temporary starting grant, written for a match without PvE rounds. Kept as-is now
	-- that the opening creep rounds exist (they add a free starting unit and creep gold); review it
	-- with the sim's PvE gold numbers.
	startingGold = 10,

	-- Section 9: paid at the start of every Preparation that follows a fight.
	baseIncome = 5,
	goldPerInterest = 10, -- +1 gold per this much gold held
	maxInterest = 5,

	-- Section 11: bonus by streak length (wins or losses), highest threshold first.
	streakBonuses = table.freeze({
		table.freeze({ minStreak = 5, gold = 3 }),
		table.freeze({ minStreak = 4, gold = 2 }),
		table.freeze({ minStreak = 2, gold = 1 }),
	}),
	winBonus = 1, -- extra gold for winning the last fight
})
