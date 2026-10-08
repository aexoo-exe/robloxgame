-- Board skins: the look of the arena (client visuals only; see src/client/Arena.luau). A skin sets
-- the hex tiles, the bench, the platform under the board, the floor and backdrop around it, the
-- lighting and sky, and the placement highlight colors. The hex layout, sizes and positions come
-- from RenderConfig and BoardConfig and never change with the skin.
--
-- Arena builds each half of the field from its own skin, so each player's half could later use
-- that player's skin; everything else (bench, surroundings, lighting, sky, highlights) comes from
-- the local player's skin. Only "default" exists for now, and Arena always uses it: there is no
-- skin selection or unlocking yet. A new skin is a new entry with the same fields.
--
-- Heights are in studs above RenderConfig.arenaCenter.Y; tile tops stay at RenderConfig's
-- cellThickness above it, where units stand.

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

local function freezeAll(value)
	if type(value) == "table" and not table.isfrozen(value) then
		for _, child in value do
			freezeAll(child)
		end
		table.freeze(value)
	end
	return value
end

return freezeAll({
	default = {
		-- Hex tiles. "beveled": each tile's top sits on a darker rim that fills the whole cell, so the
		-- rim shows as a border in the gap between tops; "flat": the tops only.
		-- `own` is the local player's half, `enemy` the opponent's.
		tiles = {
			style = "beveled",
			material = "SmoothPlastic",
			own = { top = rgb(84, 126, 170), rim = rgb(44, 70, 102) },
			enemy = { top = rgb(170, 92, 88), rim = rgb(102, 48, 48) },
			rimHeight = 0.12, -- rim thickness above the platform
		},
		-- A glowing strip across the field between the two halves.
		divider = { color = rgb(235, 225, 190), width = 0.25, material = "Neon" },

		-- Bench: a tray under the slots, set apart from the board by its color and a raised lip.
		bench = {
			tray = rgb(58, 52, 48),
			lip = rgb(120, 98, 70),
			slot = rgb(112, 104, 96),
			slotRim = rgb(78, 72, 66),
			material = "WoodPlanks",
			lipHeight = 0.3,
		},

		-- The platform under the field and bench, with a trim around its edge.
		platform = {
			color = rgb(70, 74, 82),
			trim = rgb(150, 130, 90),
			material = "Slate",
			margin = 3, -- beyond the outermost tiles and bench slots
			height = 0.2, -- top of the platform
			trimWidth = 0.8,
			trimHeight = 0.45,
		},

		-- The ground around the platform; it covers the place's baseplate.
		floor = { color = rgb(92, 120, 78), material = "Grass", size = 360, height = 0.08 },

		-- A ring of low walls with pillars behind the field, open toward the camera.
		backdrop = {
			wall = rgb(132, 120, 104),
			pillar = rgb(160, 146, 124),
			cap = rgb(255, 205, 120), -- glowing pillar tops
			material = "Cobblestone",
			radius = 46, -- from the arena center
			arc = 230, -- degrees of the ring, centered on the far side
			segments = 11,
			wallHeight = 5,
			wallThickness = 2,
			pillarSize = 3,
			pillarHeight = 7,
		},

		-- Lighting properties set on this client only.
		lighting = {
			ClockTime = 14.5,
			Brightness = 2.2,
			Ambient = rgb(95, 95, 105),
			OutdoorAmbient = rgb(150, 150, 160),
			EnvironmentDiffuseScale = 0.4,
			EnvironmentSpecularScale = 0.3,
			ExposureCompensation = 0.1,
			GlobalShadows = true,
		},
		atmosphere = {
			Density = 0.28,
			Offset = 0.2,
			Color = rgb(200, 216, 236),
			Decay = rgb(110, 118, 136),
			Glare = 0,
			Haze = 1.2,
		},
		-- Roblox's built-in sky (no custom textures).
		sky = { CelestialBodiesShown = true, StarCount = 2000 },
		colorCorrection = { Brightness = 0.02, Contrast = 0.08, Saturation = 0.08 },

		-- Placement feedback while dragging or with a unit selected.
		highlight = {
			valid = rgb(90, 230, 120),
			invalid = rgb(235, 70, 70),
			dropZone = rgb(150, 200, 255), -- every place a dragged unit may go, tinted
			material = "Neon",
			dropZoneBlend = 0.35, -- how far drop zones are tinted toward `dropZone`
		},
	},
})
