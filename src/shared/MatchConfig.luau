-- Tunable match settings shared by server and client. Values from docs/design/match-structure.md
-- (timers: section 6, starting HP: section 2, leavers: section 7); lobby timings are our own.
return table.freeze({
	-- Phase durations in seconds. Combat ends earlier when every fight has finished.
	preparationDuration = 30,
	combatMaxDuration = 50,
	resultsDuration = 5,

	-- Lobby: once minPlayersToStart players are present, a countdown runs and the match starts with
	-- the players present (up to maxPlayers). 1 so a solo Studio test starts a practice match.
	minPlayersToStart = 1,
	maxPlayers = 8,
	lobbyCountdown = 10,
	-- Seconds the final placements stay on screen before the next match's lobby.
	finalPlacementsDuration = 15,

	startingHealth = 100,

	-- A disconnected player stays in the match; after this many complete rounds missed, their HP
	-- becomes 0 at that round's Results. Reconnecting before then gives them back control.
	leaverGraceRounds = 2,
})
