-- The hub players spawn into and return to between matches: a floating sky island built from
-- parts (HubService), its two pads and their displays, decoration, the queue rules, and the hub's
-- lighting (applied on each client only while that player is in the hub; HubLighting). Distances
-- are in studs. Positions are relative to `center` (the plaza floor's top is at center.Y + 1)
-- unless noted; angles are in degrees around the center, 0 toward -Z (behind the pads) and
-- increasing toward +X. The match's own timings are in MatchConfig.

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

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
	-- How often (seconds) the server checks who stands on the pads, and who fell off.
	pollInterval = 0.2,

	-- The island floats high above the arena (RenderConfig.arenaCenter), out of the board camera's
	-- view. Clients hide the baseplate while they are in the hub.
	center = Vector3.new(0, 200, -150),
	islandRadius = 40, -- the grass edge; the stone plaza and the rim sit inside it
	plazaRadius = 36,
	rimRadius = 38.5,
	-- The invisible barrier: a ring of walls just outside the island and a ceiling over it, far
	-- higher than any jump.
	barrierRadius = 40.5,
	barrierHeight = 55, -- above the floor; the ceiling sits on top
	-- Players (not in a match) below this far under the floor, or this far outside the island, are
	-- sent back to the spawn.
	fallDepth = 15,
	outsideMargin = 4,

	spawnOffset = Vector3.new(0, 0, 20), -- the SpawnLocation; players face -Z (the pads)
	toriiOffset = Vector3.new(0, 0, 30), -- the gate behind the spawn
	centerpieceOffset = Vector3.new(0, 0, -17), -- the sword in the stone, between the pads
	pads = table.freeze({
		play = table.freeze({
			offset = Vector3.new(-16, 0, -8),
			size = 14, -- diameter of the standing area
			color = rgb(70, 230, 110),
			title = "PLAY",
			hint = "Stand on the pad to queue. Step off to leave.",
			displayOffset = Vector3.new(-30, 0, -4), -- beside the pad, facing the spawn
		}),
		practice = table.freeze({
			offset = Vector3.new(16, 0, -8),
			size = 14,
			color = rgb(80, 170, 255),
			title = "PRACTICE",
			hint = "Stand on the pad for a solo match against creeps.",
			displayOffset = Vector3.new(30, 0, -4),
		}),
	}),
	padHeight = 1.2, -- the pads stand this far above the floor (two easy steps)
	beamHeight = 50, -- the translucent light column over each pad
	-- A player counts as standing on a pad when their root part is over it and at most this high above it.
	standHeight = 8,
	displaySize = Vector2.new(14, 9), -- width and height of each pad's display board

	lanternAngles = table.freeze({ 45, 135, -135, -45 }),
	lanternRadius = 34,
	-- One banner per origin trait (TraitIconConfig colors and letters) around the rim.
	banners = table.freeze({
		{ trait = "Shinobi", angle = 0 },
		{ trait = "Cursed", angle = 22 },
		{ trait = "Corps", angle = -22 },
		{ trait = "Crew", angle = 64 },
		{ trait = "Heroes", angle = -64 },
		{ trait = "Titans", angle = 100 },
		{ trait = "Hunters", angle = -100 },
		{ trait = "Spirit", angle = 158 },
		{ trait = "Arcane", angle = -158 },
	}),
	bannerRadius = 36.8,
	-- Cherry trees: { angle, radius }.
	trees = table.freeze({
		table.freeze({ angle = 28, radius = 27 }),
		table.freeze({ angle = -28, radius = 27 }),
	}),

	colors = table.freeze({
		grass = rgb(98, 160, 82),
		rock = rgb(112, 98, 92),
		rockDark = rgb(78, 68, 66),
		plaza = rgb(196, 188, 176),
		inlay = rgb(232, 196, 120), -- the gold ring around the centerpiece
		inlayInner = rgb(168, 160, 150),
		path = rgb(224, 214, 196),
		rim = rgb(150, 140, 132),
		torii = rgb(205, 45, 40),
		toriiTop = rgb(36, 30, 32),
		lanternStone = rgb(168, 160, 150),
		lanternLight = rgb(255, 196, 110),
		blossom = rgb(255, 184, 214),
		trunk = rgb(92, 60, 48),
		displayBoard = rgb(26, 24, 34),
		displayFrame = rgb(52, 44, 56),
		spawnStone = rgb(236, 232, 226),
		spawnGlow = rgb(255, 214, 120),
		blade = rgb(214, 224, 236),
		hilt = rgb(40, 30, 36),
		guard = rgb(232, 184, 72),
		centerpieceGlow = rgb(255, 170, 80),
	}),

	-- Hub lighting and sky (client only, while in the hub; the arena's own lighting comes back for
	-- matches). `properties` are Lighting properties; the rest are created in Lighting.
	lighting = table.freeze({
		properties = table.freeze({
			ClockTime = 16.9,
			Brightness = 2.6,
			Ambient = rgb(120, 104, 122),
			OutdoorAmbient = rgb(176, 156, 168),
			EnvironmentDiffuseScale = 0.5,
			EnvironmentSpecularScale = 0.5,
			ExposureCompensation = 0.15,
			GlobalShadows = true,
		}),
		atmosphere = table.freeze({
			Density = 0.3,
			Offset = 0.1,
			Color = rgb(255, 208, 196),
			Decay = rgb(150, 122, 176),
			Glare = 0.4,
			Haze = 1.6,
		}),
		sky = table.freeze({ CelestialBodiesShown = true, StarCount = 3000, SunAngularSize = 16 }),
		colorCorrection = table.freeze({ Brightness = 0.02, Contrast = 0.06, Saturation = 0.15, TintColor = rgb(255, 246, 240) }),
		bloom = table.freeze({ Intensity = 0.6, Size = 24, Threshold = 1.6 }),
	}),

	-- Where match participants' avatars wait during a match: far below the island and under the
	-- baseplate, out of sight, anchored. Absolute position.
	parkPosition = Vector3.new(0, -60, -150),
})
