-- The hub players spawn into and return to between matches: its layout (placeholder parts), the
-- two pads, and the queue rules. Distances are in studs; positions are relative to `center` unless
-- noted. The match's own timings are in MatchConfig.
return table.freeze({
	-- Queue (the Play pad). Standing on the pad queues the player; stepping off leaves the queue.
	-- Once `playersToStartCountdown` are queued, the match starts `countdownSeconds` later (the timer
	-- is cancelled if the queue drops below that again). It starts at once with
	-- `playersToStartAtOnce` queued. Keep that at most MatchConfig.maxPlayers.
	queue = table.freeze({
		playersToStartCountdown = 2,
		countdownSeconds = 15,
		playersToStartAtOnce = 8,
	}),
	-- How often (seconds) the server checks who stands on the pads.
	pollInterval = 0.2,

	-- The hub sits on the baseplate away from the arena (RenderConfig.arenaCenter), which clients
	-- hide while they are in the hub.
	center = Vector3.new(0, 0, -150),
	floorSize = Vector2.new(84, 64),
	wallHeight = 5,
	spawnOffset = Vector3.new(0, 0, 20), -- the SpawnLocation, toward the open side
	pads = table.freeze({
		play = table.freeze({ offset = Vector3.new(-16, 0, -8), size = 14, color = Color3.fromRGB(70, 200, 100) }),
		practice = table.freeze({ offset = Vector3.new(16, 0, -8), size = 14, color = Color3.fromRGB(70, 150, 240) }),
	}),
	-- A player counts as standing on a pad when their root part is over it and at most this high above it.
	standHeight = 8,
	floorColor = Color3.fromRGB(58, 60, 72),
	wallColor = Color3.fromRGB(40, 42, 52),
	signColor = Color3.fromRGB(28, 30, 38),

	-- Where match participants' avatars wait during a match: under the hub floor, out of sight,
	-- anchored. Absolute position.
	parkPosition = Vector3.new(0, -60, -150),
})
