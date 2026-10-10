-- The hub ("Sky Dojo"): the place players spawn into and return to between matches. Layout,
-- colors, sizes, the queue rules and the hub's lighting all live here. HubBuilder (server) builds
-- the parts; HubScenery (client) adds the cloud sea, bobbing rocks, statues and item icons;
-- HubExhibits (client) shows statue and item info; HubLighting (client) sets the lighting. Only
-- the hub uses any of this, and the client-side pieces only exist while the player is in the hub.
--
-- Coordinates: every position is relative to `center`, whose height is the main floor's walking
-- height (y = 0 here). +X is right and -Z is "forward" as seen from the spawn, which faces down the
-- avenue toward the arena gate. Angles are in degrees around a point: 0 toward -Z, 90 toward +X.
-- Distances are in studs.

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

local function v(x: number, y: number, z: number): Vector3
	return Vector3.new(x, y, z)
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
	-- How often (seconds) the server checks who stands on the pads, and who fell.
	pollInterval = 0.2,

	-- Far from the arena (RenderConfig.arenaCenter) so it never shows in, or shades, the board view.
	center = v(-3000, 300, 0),

	-- Walkable ground (heights are floor tops). Rectangles are { x = { min, max }, z = { min, max } }.
	spine = table.freeze({ x = { -36, 36 }, z = { -160, 124 } }), -- the long main ground
	avenueHalfWidth = 10,
	plaza = table.freeze({ center = v(0, 0, 0), radius = 46 }),
	terrace = table.freeze({ x = { -82, 28 }, z = { 124, 166 }, height = 10 }), -- arrival + hall of fame
	stairs = table.freeze({ halfWidth = 15, steps = 9, depth = 2.6 }), -- from the terrace's front edge down

	-- Arrival.
	spawn = v(0, 10, 150), -- the SpawnLocation; players face -Z, down the stair and the avenue
	torii = v(0, 10, 160),

	-- Central plaza: the centerpiece with the nine faction banners in a ring around it.
	centerpiece = v(0, 0, 0),
	plazaBannerRadius = 15,
	plazaBannerFactions = table.freeze({
		"Shinobi", "Crew", "Heroes", "Corps", "Spirit", "Arcane", "Titans", "Cursed", "Hunters",
	}),

	-- Roster gallery: rows of plinths along the avenue, facing it. Each row holds whole factions in
	-- order; a faction's banner stands at the start of its group. Units go by cost, then name.
	gallery = table.freeze({
		spacing = 4.2, -- between plinth centers
		groupGap = 3, -- extra space before each faction group, for its banner
		plinthHeight = 2.2,
		statueHeight = 6, -- the figure's height on its plinth
		rows = table.freeze({
			table.freeze({ x = -17, from = 98, to = 47, factions = { "Shinobi", "Crew" } }),
			table.freeze({ x = 17, from = 98, to = 47, factions = { "Heroes", "Corps" } }),
			table.freeze({ x = -17, from = -48, to = -114, factions = { "Cursed", "Hunters" } }),
			table.freeze({ x = 17, from = -48, to = -114, factions = { "Spirit", "Arcane", "Titans" } }),
		}),
		infoDistance = 7, -- walk this close to a statue to see its card
	}),

	-- Pads. `kind` "circle" uses center + radius; "rect" uses the rectangle. Each pad has one display
	-- board at `display`, facing `displayFacing`.
	pads = table.freeze({
		play = table.freeze({
			kind = "circle",
			center = v(0, 0, -132),
			radius = 13,
			height = 1.2, -- the pad's top above the floor
			spots = 8, -- marked spots that light up one by one as players queue
			spotRadius = 8.5,
			color = rgb(70, 230, 110),
			title = "ARENA GATE",
			hint = "Stand on the platform to queue. Step off to leave.",
			display = v(26, 0, -122),
			displayFacing = v(0, 0, -80),
		}),
		practice = table.freeze({
			kind = "rect",
			x = { 43, 91 },
			z = { -27, 27 },
			height = 0.6,
			color = rgb(80, 170, 255),
			title = "TRAINING YARD",
			hint = "Step into the yard to start a solo practice match.",
			display = v(34, 0, 14),
			displayFacing = v(0, 0, 30),
		}),
	}),
	-- A player counts as standing on a pad when their root part is over it and at most this high above it.
	standHeight = 8,
	displaySize = Vector2.new(14, 9),
	beamHeight = 60, -- the light column over the Play platform

	-- The arena gate behind the Play platform.
	gate = table.freeze({ center = v(0, 0, -152), width = 32, height = 24 }),

	-- Training yard (its floor is the Practice pad): walls around the rectangle with an opening
	-- toward the plaza, and training dummies.
	yard = table.freeze({
		wallHeight = 7,
		openingHalfWidth = 6,
		dummies = table.freeze({ v(86, 0, -18), v(86, 0, -6), v(86, 0, 6), v(86, 0, 18), v(66, 0, -20), v(66, 0, 20) }),
	}),

	-- Item shrine: a pavilion off the plaza's -X side with the items on pedestals in an arc,
	-- open toward the plaza.
	shrine = table.freeze({
		center = v(-68, 0, 0),
		radius = 23,
		daisRadius = 13,
		pedestalRadius = 9,
		arc = { 120, 420 }, -- pedestals go from this angle to that one (the opening is toward +X)
		infoDistance = 5,
	}),

	-- Hall of fame, on the terrace's -X wing: leaderboard boards. Stats are not saved yet, so each
	-- board shows `placeholder` until HubService.setLeaderboard gives it rows.
	hall = table.freeze({
		boards = table.freeze({
			table.freeze({ id = "wins", title = "MOST WINS", position = v(-76, 10, 133) }),
			table.freeze({ id = "top4", title = "TOP 4 FINISHES", position = v(-76, 10, 145) }),
			table.freeze({ id = "played", title = "MATCHES PLAYED", position = v(-76, 10, 157) }),
		}),
		facing = v(0, 10, 145),
		rowsShown = 8,
		placeholder = "Rankings coming soon",
		podium = v(-58, 10, 145),
	}),

	-- Outer islands and bridges.
	islands = table.freeze({
		lookout = table.freeze({ center = v(88, 2, -140), radius = 14 }),
		garden = table.freeze({ center = v(-130, -3, 26), radius = 16 }),
		hidden = table.freeze({ center = v(144, 12.5, -179), radius = 6 }),
	}),
	bridges = table.freeze({
		table.freeze({ from = v(34, 0, -140), to = v(76, 2, -140) }),
		table.freeze({ from = v(-89, 0.3, 6), to = v(-116, -3, 20) }),
	}),
	-- The jumping route from the lookout to the hidden islet: stepping stones (centers).
	stones = table.freeze({
		v(108, 3.5, -146),
		v(113, 5, -152),
		v(119, 6.5, -157),
		v(125, 8, -162),
		v(131, 9.5, -167),
		v(137, 11, -172),
	}),
	stoneRadius = 2,

	-- Decoration.
	lanterns = table.freeze({ v(-13, 0, 92), v(13, 0, 92), v(-13, 0, -52), v(13, 0, -52), v(31, 0, -133), v(31, 0, -147) }),
	trees = table.freeze({ v(22, 10, 134), v(-30, 10, 160), v(-136, -3, 18), v(-124, -3, 36), v(-140, -3, 34) }),
	waterfall = table.freeze({ pond = v(28, 0, 66), width = 6, drop = 75 }), -- falls off the +X edge

	-- The boundary: an invisible box around the whole hub (walls and a ceiling). Players who fall
	-- below `fallHeight` are sent back to the spawn.
	bounds = table.freeze({ x = { -165, 175 }, z = { -205, 182 }, top = 70 }),
	fallHeight = -25,

	-- Client-side scenery (HubScenery).
	clouds = table.freeze({
		seaHeight = -45, -- the top of the cloud sea
		puffs = 36, -- drifting cloud puffs on the sea near the hub
		puffArea = 420, -- puffs drift within this distance of the center
		driftSpeed = 2, -- studs per second
	}),
	floatingRocks = table.freeze({
		v(-60, 18, -60), v(70, 24, 60), v(-110, 8, -90), v(120, 16, -40), v(-40, 30, 120), v(60, 12, -190), v(-150, 20, 90), v(150, 28, 110),
	}),

	colors = table.freeze({
		grass = rgb(98, 160, 82),
		rock = rgb(112, 98, 92),
		rockDark = rgb(78, 68, 66),
		ground = rgb(186, 178, 166),
		avenue = rgb(222, 212, 194),
		inlay = rgb(232, 196, 120),
		inlayInner = rgb(168, 160, 150),
		curb = rgb(150, 140, 132),
		plinth = rgb(214, 208, 198),
		torii = rgb(196, 48, 42),
		dark = rgb(36, 30, 32),
		lanternStone = rgb(168, 160, 150),
		lanternLight = rgb(255, 196, 110),
		blossom = rgb(255, 184, 214),
		trunk = rgb(92, 60, 48),
		wood = rgb(150, 104, 64),
		displayBoard = rgb(26, 24, 34),
		displayFrame = rgb(52, 44, 56),
		spawnStone = rgb(236, 232, 226),
		spawnGlow = rgb(255, 214, 120),
		gold = rgb(232, 184, 72),
		blade = rgb(214, 224, 236),
		hilt = rgb(40, 30, 36),
		glow = rgb(255, 170, 80),
		water = rgb(120, 190, 235),
		spotOff = rgb(40, 52, 46),
		portal = rgb(255, 120, 80),
		cloud = rgb(255, 246, 244),
		cloudShade = rgb(236, 222, 232),
	}),

	-- Hub lighting and sky (client only, while in the hub; the arena's own lighting comes back for
	-- matches). Warm late afternoon, toned down so colors and text stay readable. `properties` are
	-- Lighting properties; the rest are created in Lighting.
	lighting = table.freeze({
		properties = table.freeze({
			ClockTime = 16.4,
			Brightness = 1.8,
			Ambient = rgb(104, 96, 110),
			OutdoorAmbient = rgb(150, 140, 150),
			EnvironmentDiffuseScale = 0.4,
			EnvironmentSpecularScale = 0.3,
			ExposureCompensation = 0,
			GlobalShadows = true,
		}),
		atmosphere = table.freeze({
			Density = 0.36,
			Offset = 0.05,
			Color = rgb(246, 214, 204),
			Decay = rgb(160, 130, 170),
			Glare = 0.15,
			Haze = 1.4,
		}),
		sky = table.freeze({ CelestialBodiesShown = true, StarCount = 3000, SunAngularSize = 14 }),
		colorCorrection = table.freeze({ Brightness = 0, Contrast = 0.08, Saturation = 0.06, TintColor = rgb(255, 248, 242) }),
		bloom = table.freeze({ Intensity = 0.25, Size = 18, Threshold = 2.2 }),
	}),

	-- Where match participants' avatars wait during a match: under the arena's baseplate, out of
	-- sight, anchored. Absolute position (not relative to `center`).
	parkPosition = v(0, -60, -150),
})
