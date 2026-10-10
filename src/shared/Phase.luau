-- Match phase names. Replicated to clients through the MatchState "Phase" attribute.
--   Waiting      no match is running (players are in the hub; HubService starts matches)
--   Preparation, Combat, Results   one round of a match
--   MatchOver    final placements, before everyone returns to the hub
return table.freeze({
	Waiting = "Waiting",
	Preparation = "Preparation",
	Combat = "Combat",
	Results = "Results",
	MatchOver = "MatchOver",
})
