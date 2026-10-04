-- Match phase names. Replicated to clients through the MatchState "Phase" attribute.
--   Waiting      fewer than MatchConfig.minPlayersToStart players in the server
--   Lobby        countdown before a match starts
--   Preparation, Combat, Results   one round of a match
--   MatchOver    final placements, before the next lobby
return table.freeze({
	Waiting = "Waiting",
	Lobby = "Lobby",
	Preparation = "Preparation",
	Combat = "Combat",
	Results = "Results",
	MatchOver = "MatchOver",
})
