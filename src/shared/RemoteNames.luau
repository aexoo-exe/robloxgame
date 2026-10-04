-- Names of the RemoteEvents the server creates under ReplicatedStorage.Remotes.
-- Requests are only requests: the server validates each one against the sender's own state, ignores
-- invalid ones, and replies to the sender with BoardUpdated and PlayerStateUpdated if it changed
-- anything. Requests are only accepted during Preparation.
return table.freeze({
	-- Client -> server: (unitId: string, target: { slot: number } | { column: number, row: number }).
	-- Moving onto an occupied place swaps the two units.
	RequestMoveUnit = "RequestMoveUnit",
	-- Client -> server: (shopSlot: number)
	RequestBuyUnit = "RequestBuyUnit",
	-- Client -> server: (unitId: string)
	RequestSellUnit = "RequestSellUnit",
	-- Client -> server: ()
	RequestReroll = "RequestReroll",
	-- Client -> server: ()
	RequestBuyXp = "RequestBuyXp",

	-- Server -> owning client: the player's units (Board.getUnits).
	BoardUpdated = "BoardUpdated",
	-- Server -> owning client: gold, level, XP and shop (PlayerState.getView).
	PlayerStateUpdated = "PlayerStateUpdated",
	-- Server -> owning client: (reason: string) why a request was refused, from PlayerState.Refusal.
	RequestRefused = "RequestRefused",

	-- Server -> all clients: { startsAt, sideUserIds, result } where result is a CombatSim result.
	-- Clients play the events back starting at server time `startsAt`.
	CombatStarted = "CombatStarted",
})
