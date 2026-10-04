-- Names of the RemoteEvents the server creates under ReplicatedStorage.Remotes.
return table.freeze({
	-- Client -> server: (unitId: string, target: { slot: number } | { column: number, row: number }).
	-- A request only; the server validates it and replies with BoardUpdated if it was accepted.
	RequestMoveUnit = "RequestMoveUnit",

	-- Server -> owning client: the player's units (Board.getUnits), sent after every change.
	BoardUpdated = "BoardUpdated",

	-- Server -> all clients: { startsAt, sideUserIds, result } where result is a CombatSim result.
	-- Clients play the events back starting at server time `startsAt`.
	CombatStarted = "CombatStarted",
})
