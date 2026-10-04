-- Tunable match settings shared by server and client.
-- Durations are in seconds and are provisional placeholders, not final balance.
return table.freeze({
	preparationDuration = 30,
	combatMaxDuration = 45,
	resultsDuration = 5,

	-- 1 so a solo Studio Play test runs the loop. Raise for real matches.
	minPlayersToStart = 1,

	-- Players who get a board. With one player they fight CombatConfig.presetEnemyBoard;
	-- with two they fight each other. Extra players only watch.
	maxPlayers = 2,
})
