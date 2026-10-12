-- Tunable match settings shared by server and client. Values from docs/design/match-structure.md
-- (timers: section 6, starting HP: section 2, leavers: section 7). How a match is started (the
-- hub's pads and queue) is in HubConfig.
return table.freeze({
	-- Phase durations in seconds. Combat ends earlier when every fight has finished.
	preparationDuration = 30,
	combatMaxDuration = 50,
	resultsDuration = 5,
	-- The match intro before round 1 (Phase.Intro): the starting unit is shown on the board with a
	-- countdown; round 1's creep fight starts when it ends.
	introDuration = 8,

	-- Most players in one match.
	maxPlayers = 8,
	-- Seconds the final placements stay on screen before everyone returns to the hub.
	finalPlacementsDuration = 15,

	startingHealth = 100,

	-- A disconnected player stays in the match; after this many complete rounds missed, their HP
	-- becomes 0 at that round's Results. Reconnecting before then gives them back control.
	leaverGraceRounds = 2,
})
