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

	-- Bot opponents (server-side, BotService): a match from the Play pad with fewer than `botFillTo`
	-- players gets bots in the empty seats, and one queued player is enough to start the countdown.
	-- Practice matches never get bots. Set `botsEnabled` to false to play humans only.
	botsEnabled = true,
	botFillTo = 6,
	-- Display names, one per bot seat (at least maxPlayers - 1). Generic words only.
	botNames = { "Bot Ronin", "Bot Kaze", "Bot Tengu", "Bot Kitsune", "Bot Kumo", "Bot Tora", "Bot Hoshi" },
	-- Seconds the final placements stay on screen before everyone returns to the hub.
	finalPlacementsDuration = 15,

	startingHealth = 100,

	-- A disconnected player stays in the match; after this many complete rounds missed, their HP
	-- becomes 0 at that round's Results. Reconnecting before then gives them back control.
	leaverGraceRounds = 2,
})
