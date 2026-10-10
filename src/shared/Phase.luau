-- Match phase names. Replicated to clients through the MatchState "Phase" attribute.
--   Waiting      no match is running (players are in the hub; HubService starts matches)
--   Intro        before round 1: each player's starting unit is shown on their board
--   Preparation, Combat, Results   one round of a match
--   MatchOver    final placements, before everyone returns to the hub
return table.freeze({
	Waiting = "Waiting",
	Intro = "Intro",
	Preparation = "Preparation",
	Combat = "Combat",
	Results = "Results",
	MatchOver = "MatchOver",
})
