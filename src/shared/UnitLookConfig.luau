-- Hand-built looks for roster units (client visuals only), keyed by unit id (UnitConfig key). A unit
-- with an entry here is drawn by src/client/LookKit.luau instead of the plain placeholder figure; a
-- unit without one keeps its placeholder (FigureConfig). The look replaces the body colors and the
-- class prop; the cost ring, star size, attack hand and animations stay as they are. Display names
-- stay in SkinConfig. Design notes per unit: docs/references/index.md (local only).
--
-- Every entry is data. Fields (all optional except skin, torso, pants and shoes):
--   skin, torso, pants, shoes   body colors: head and bare skin, shirt, trousers, footwear
--   sleeves, gloves, socks      arm cover (default: coat, else torso), hands (default skin), the leg
--                               between trousers and shoes (default skin)
--   sleeve      fraction of the arm the sleeve covers from the shoulder (default 0.8; 0 = bare)
--   shorts      fraction of the leg the trousers cover (default: down to the shoes)
--   shoe        fraction of the leg the shoes cover (default 0.16)
--   wideLegs    trouser width multiplier (baggy trousers, robes)
--   shortSleeves { color, length }  a short sleeve over the long one (a shirt over a long-sleeved top)
--   hair        { style, color, tip?, lift?, rings?, strands? }  styles: spiky, tall, fluffy, messy,
--               wild, neat, undercut, bob, long, bun, pompadour, twintails, short (see LookKit.HAIR).
--               `tip` colors the spike tips, `lift` (< 1) stands the spikes more upright, `rings` adds
--               spike rings, `strands` adds loose strands { x, length, width?, z? } (head fractions)
--   headwear    { kind = "knit" | "wide" | "peaked" | "band", color, ... }
--   face        { eyes = "open" | "sharp" | "closed" | "none", eyeColor, leftEye, rightEye, mouth,
--               mask = { color, teeth } }
--   ears        "elf": pointed ears
--   coat        { color, length (of the leg, below the hips), open (default true), inner, tail,
--               flare, sides, collar, cross, trim, stripes, band = { color, fraction },
--               pattern = { kind = "checker" | "triangles", color } }
--   collar, belt = { color, buckle? }, sash = { color }, scarf = { color }, tie, cravat
--   buttons     { color, count }
--   bands       { { limb, from, to, color, fine? } }: rings around "arms", "legs", "leftArm" ...
--               from/to are fractions of the limb from its top
--   emblems     { { shape = "heart" | "disc" | "diamond", anchor, at, size, color, fine? } }
--   gearBoxes   { color }: boxes on both hips
--   tendrils    { color }: four segmented tendrils from the lower back
--   weapons     { { kind, hand?, ... } }: katana, sheathedKatana, greatsword, greatswordBack,
--               dagger, thinBlade, staff, rod, ball, vial, basket (see LookKit.WEAPONS)
--   extras      raw parts { anchor, shape, size, at, turn?, color, material?, fine?, plain?,
--               transparency? }. `to` (instead of turn) makes a segment from `at` to `to` (size X
--               and Y are its thickness). `mirror = true` adds a copy mirrored to the other side;
--               `limbs = "Arm"` or `"Leg"` puts the part on both limbs (written for the right one)
--   hand, arms  attack hand ("left", "right", "both") and resting arm angles { left, right } in
--               degrees, replacing the class's (presentation only)
--   scale, bulk size multiplier and extra width (as FigureConfig.characters)
--   proportions body proportions replacing FigureConfig.body's (any of legLength, legWidth,
--               legSpacing, torsoHeight, torsoWidth, torsoDepth, neck, headSize, armLength,
--               armWidth), final: bulk does not widen them. The anchors follow, so poses still work
--   lean        a forward stoop in degrees (all poses)
--   headScale   the head block's size as multipliers of the head size (default a cube)
--   customArms, customLegs  leave out the standard arms or legs, to build them with extras
--   steam       { rate, color, size? }: soft see-through puffs drifting up from the body
-- A mounted rider's horse colors are in HorseLookConfig.
--
-- Sizes and positions (extras, emblems) are fractions of the figure's height, in the space of their
-- anchor: hips (top of the legs; the torso runs up 0.34, front is -Z), head (its center; the head is
-- 0.20 across), leftArm/rightArm (the shoulder; the arm hangs 0.33 down -Y), leftHand/rightHand
-- (the end of the arm), leftLeg/rightLeg (the hip joint; the leg hangs 0.40), root (the ground).
-- The figure's left is -X. `fine` parts are skipped by low-detail figures (hub statues).

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

local function deepFreeze<T>(value: T): T
	if type(value) == "table" and not table.isfrozen(value) then
		for _, child in value :: any do
			deepFreeze(child)
		end
		table.freeze(value)
	end
	return value
end

local v = Vector3.new

-- Shared colors.
local SKIN = rgb(245, 205, 165)
local TAN_SKIN = rgb(232, 184, 140)
local WHITE = rgb(238, 238, 236)
local BLACK = rgb(28, 28, 33)
local INK = rgb(20, 20, 26) -- black hair
local GOLD = rgb(225, 178, 62)
local STEEL = rgb(200, 205, 215)
local BROWN = rgb(100, 58, 36)
local NAVY = rgb(30, 34, 62)

return deepFreeze({
	-- Hunters --------------------------------------------------------------------------------

	flashline = {
		skin = SKIN,
		torso = BLACK,
		pants = BLACK,
		shoes = BLACK,
		sleeve = 0.82,
		hair = { style = "spiky", color = rgb(250, 208, 60), tip = rgb(240, 128, 32) },
		face = { eyes = "closed" },
		coat = {
			color = rgb(246, 178, 46),
			tail = rgb(238, 130, 34),
			length = 0.9,
			flare = 5,
			pattern = { kind = "triangles", color = WHITE },
		},
		belt = { color = WHITE },
		weapons = { { kind = "sheathedKatana", side = "left", sheath = rgb(45, 45, 55), hilt = WHITE } },
	},

	cinder_arc = {
		skin = SKIN,
		torso = BLACK,
		pants = BLACK,
		shorts = 0.55,
		socks = WHITE, -- leg wraps
		shoes = rgb(95, 72, 50),
		shoe = 0.12,
		hair = { style = "messy", color = rgb(118, 30, 36) },
		face = { eyes = "open", eyeColor = rgb(130, 40, 42) },
		coat = { color = rgb(45, 168, 118), length = 0.3, pattern = { kind = "checker", color = BLACK } },
		belt = { color = WHITE },
		bands = { { limb = "legs", from = 0.66, to = 0.7, color = BLACK, fine = true } },
		weapons = { { kind = "katana", hand = "right", blade = rgb(28, 28, 34), hilt = rgb(40, 40, 46) } },
		extras = {
			-- hanafuda earrings
			{
				anchor = "head",
				shape = "Block",
				size = v(0.012, 0.045, 0.03),
				at = v(-0.104, -0.07, 0),
				color = WHITE,
				fine = true,
			},
			{
				anchor = "head",
				shape = "Block",
				size = v(0.012, 0.045, 0.03),
				at = v(0.104, -0.07, 0),
				color = WHITE,
				fine = true,
			},
		},
	},

	thunder_nest = {
		scale = 0.94,
		skin = SKIN,
		torso = rgb(240, 240, 244),
		sleeves = rgb(36, 46, 116),
		shortSleeves = { color = rgb(240, 240, 244), length = 0.36 },
		pants = rgb(142, 130, 206),
		shorts = 0.42,
		shoes = rgb(124, 66, 150),
		shoe = 0.14,
		hair = { style = "fluffy", color = rgb(236, 232, 252) },
		face = { eyes = "open", eyeColor = rgb(70, 120, 232) },
		-- the loose white shirt hangs a little past the waist; a navy high collar shows above it
		coat = { color = rgb(240, 240, 244), length = 0.12, open = false, collar = rgb(36, 46, 116) },
	},

	horizon_cut = {
		skin = SKIN,
		torso = rgb(30, 30, 36),
		pants = BLACK,
		shoes = rgb(215, 215, 215),
		shoe = 0.1,
		sleeve = 0.86,
		hair = { style = "spiky", color = rgb(245, 112, 32) },
		face = { eyes = "sharp", eyeColor = rgb(110, 70, 40) },
		coat = { color = rgb(18, 18, 22), length = 0.9, flare = 9, sides = true, cross = WHITE },
		sash = { color = WHITE },
		weapons = {
			{
				kind = "greatswordBack",
				blade = rgb(22, 22, 26),
				edge = rgb(195, 200, 210),
				hilt = WHITE,
				cloth = WHITE,
			},
		},
	},

	reelbreaker = {
		skin = SKIN,
		torso = rgb(44, 140, 64),
		pants = rgb(44, 140, 64),
		shorts = 0.45,
		shoes = rgb(44, 140, 64),
		shoe = 0.26,
		hair = { style = "tall", color = rgb(24, 27, 30), tip = rgb(46, 150, 70) },
		face = { eyes = "open", eyeColor = rgb(90, 60, 40) },
		belt = { color = BLACK },
		bands = { { limb = "legs", from = 0.8, to = 0.85, color = WHITE } }, -- boot tops
		extras = {
			-- orange trim: zip, collar and hem
			{
				anchor = "hips",
				shape = "Block",
				size = v(0.014, 0.3, 0.01),
				at = v(0, 0.18, -0.092),
				color = rgb(240, 120, 40),
			},
			{
				anchor = "hips",
				shape = "Block",
				size = v(0.2, 0.022, 0.194),
				at = v(0, 0.33, 0),
				color = rgb(240, 120, 40),
			},
			{
				anchor = "hips",
				shape = "Block",
				size = v(0.348, 0.016, 0.186),
				at = v(0, 0.075, 0),
				color = rgb(240, 120, 40),
				fine = true,
			},
		},
		weapons = { { kind = "rod", hand = "right", shaft = rgb(70, 50, 36), line = WHITE, float = rgb(225, 45, 45) } },
		hand = "right",
		arms = { 10, 35 },
	},

	-- Corps ----------------------------------------------------------------------------------

	wolfstep = {
		skin = SKIN,
		torso = rgb(192, 162, 98),
		sleeves = rgb(48, 42, 36),
		shortSleeves = { color = rgb(192, 162, 98), length = 0.38 },
		pants = rgb(60, 50, 40),
		shoes = rgb(50, 40, 32),
		hair = { style = "messy", color = rgb(226, 220, 200) },
		face = { eyes = "sharp", eyeColor = rgb(70, 60, 50) },
		coat = {
			color = rgb(192, 162, 98),
			length = 0.45,
			open = false,
			band = { color = rgb(66, 50, 34), fraction = 0.32 }, -- patterned dark hem
		},
		belt = { color = rgb(66, 50, 34), buckle = rgb(150, 130, 90) },
		weapons = { { kind = "dagger", hand = "both", blade = rgb(175, 180, 190), hilt = rgb(30, 30, 30) } },
		hand = "both",
		arms = { 20, 20 },
	},

	redline_cut = {
		skin = SKIN,
		torso = rgb(234, 234, 230),
		pants = rgb(236, 233, 222),
		shoes = rgb(70, 38, 32),
		shoe = 0.34,
		hair = { style = "bob", color = INK },
		face = { eyes = "open", eyeColor = rgb(60, 60, 72) },
		coat = { color = rgb(92, 96, 58), length = 0 },
		scarf = { color = rgb(205, 30, 38) },
		belt = { color = BROWN },
		bands = {
			{ limb = "legs", from = 0.12, to = 0.17, color = BROWN },
			{ limb = "legs", from = 0.36, to = 0.41, color = BROWN },
		},
		gearBoxes = { color = rgb(150, 155, 160) },
		extras = {
			-- the shirt below the cropped jacket, and the wing emblem
			{
				anchor = "hips",
				shape = "Block",
				size = v(0.345, 0.07, 0.185),
				at = v(0, 0.035, 0),
				color = rgb(234, 234, 230),
			},
			{
				anchor = "hips",
				shape = "Block",
				size = v(0.04, 0.04, 0.01),
				at = v(0.1, 0.25, -0.094),
				color = WHITE,
				fine = true,
			},
		},
		weapons = { { kind = "thinBlade", hand = "both", blade = STEEL, handle = rgb(60, 62, 66) } },
		hand = "both",
		arms = { 25, 25 },
	},

	cyclone_edge = {
		scale = 0.92,
		skin = SKIN,
		torso = WHITE,
		pants = rgb(35, 35, 42),
		shoes = BLACK,
		shoe = 0.2,
		hair = { style = "undercut", color = INK },
		face = { eyes = "sharp", eyeColor = rgb(70, 75, 88) },
		coat = { color = rgb(120, 86, 56), length = 0 },
		cravat = WHITE,
		belt = { color = BROWN },
		bands = {
			{ limb = "legs", from = 0.12, to = 0.17, color = BROWN },
			{ limb = "legs", from = 0.36, to = 0.41, color = BROWN, fine = true },
		},
		gearBoxes = { color = rgb(92, 106, 86) },
		weapons = { { kind = "thinBlade", hand = "both", reverse = true, blade = STEEL, handle = rgb(60, 62, 66) } },
		hand = "both",
		arms = { 30, 30 },
	},

	snapfire = {
		skin = SKIN,
		torso = rgb(42, 62, 125),
		pants = rgb(42, 62, 125),
		shoes = BLACK,
		shoe = 0.2,
		gloves = WHITE,
		hair = { style = "neat", color = INK },
		face = { eyes = "sharp", eyeColor = rgb(40, 40, 46) },
		coat = { color = rgb(42, 62, 125), length = 0.28, open = false, collar = rgb(42, 62, 125) },
		buttons = { color = GOLD, count = 3 },
		extras = {
			-- gold aiguillette on the right shoulder
			{
				anchor = "hips",
				shape = "Block",
				size = v(0.022, 0.14, 0.022),
				at = v(0.12, 0.24, -0.1),
				turn = v(0, 0, 28),
				color = GOLD,
			},
			{
				anchor = "hips",
				shape = "Block",
				size = v(0.08, 0.02, 0.02),
				at = v(0.1, 0.18, -0.1),
				color = GOLD,
				fine = true,
			},
		},
	},

	-- Spirit ---------------------------------------------------------------------------------

	spurshot = {
		skin = SKIN,
		torso = rgb(150, 200, 236),
		pants = rgb(150, 200, 236),
		shoes = rgb(30, 42, 92),
		shoe = 0.32,
		hair = { style = "short", color = rgb(232, 200, 120) },
		headwear = {
			kind = "knit",
			color = rgb(150, 200, 236),
			band = rgb(128, 180, 226),
			ornament = GOLD,
			horns = rgb(205, 175, 125),
		},
		face = { eyes = "open", eyeColor = rgb(90, 150, 222) },
		extras = {
			-- dark straps down the chest, and a few stars
			{
				anchor = "hips",
				shape = "Block",
				size = v(0.03, 0.32, 0.01),
				at = v(-0.06, 0.17, -0.093),
				color = rgb(30, 42, 92),
			},
			{
				anchor = "hips",
				shape = "Block",
				size = v(0.03, 0.32, 0.01),
				at = v(0.06, 0.17, -0.093),
				color = rgb(30, 42, 92),
			},
		},
		emblems = {
			{
				shape = "diamond",
				anchor = "hips",
				at = v(-0.11, 0.08, -0.092),
				size = 0.04,
				color = rgb(160, 100, 200),
				fine = true,
			},
			{
				shape = "diamond",
				anchor = "leftLeg",
				at = v(0, -0.1, -0.067),
				size = 0.04,
				color = rgb(230, 120, 180),
				fine = true,
			},
			{
				shape = "diamond",
				anchor = "rightLeg",
				at = v(0, -0.16, -0.067),
				size = 0.04,
				color = rgb(160, 100, 200),
				fine = true,
			},
		},
	},

	orbit_breaker = {
		skin = SKIN,
		torso = rgb(72, 46, 110),
		pants = rgb(205, 172, 110),
		shoes = rgb(70, 45, 32),
		shoe = 0.2,
		hair = { style = "long", color = rgb(236, 214, 128) },
		headwear = {
			kind = "wide",
			color = rgb(56, 40, 36),
			band = rgb(36, 30, 30),
			goggles = rgb(150, 162, 172),
			crest = rgb(205, 40, 40),
		},
		face = { eyes = "open", eyeColor = rgb(70, 110, 90) },
		coat = { color = rgb(72, 46, 110), length = 0.25, open = false },
		belt = { color = rgb(40, 35, 35), buckle = rgb(70, 165, 80) },
		buttons = { color = GOLD, count = 4 }, -- gold studs
		weapons = { { kind = "ball", hand = "both", color = STEEL } },
	},

	clockbreaker = {
		skin = SKIN,
		torso = rgb(95, 115, 72),
		pants = BLACK,
		shoes = BLACK,
		shoe = 0.14,
		sleeve = 0.85,
		hair = {
			style = "neat",
			color = INK,
			-- the back of the cap runs into jagged hair
			rings = { { count = 3, y = 0.2, radius = 0.45, tilt = 130, length = 0.3, base = 0.3, yaw = 0, span = 120 } },
		},
		headwear = { kind = "peaked", color = rgb(22, 22, 28), badge = GOLD },
		face = { eyes = "sharp", eyeColor = rgb(60, 72, 92) },
		coat = { color = rgb(22, 22, 28), length = 0.85, flare = 5, collar = rgb(22, 22, 28) },
		extras = {
			-- gold chain from the left collar
			{
				anchor = "hips",
				shape = "Block",
				size = v(0.026, 0.17, 0.02),
				at = v(-0.09, 0.26, -0.1),
				turn = v(0, 0, -12),
				color = GOLD,
			},
			{
				anchor = "hips",
				shape = "Block",
				size = v(0.024, 0.08, 0.02),
				at = v(-0.11, 0.15, -0.1),
				turn = v(0, 0, 20),
				color = GOLD,
				fine = true,
			},
		},
		hand = "both",
	},

	frozen_moment = {
		skin = SKIN,
		torso = BLACK,
		pants = rgb(228, 172, 62),
		shoes = rgb(205, 150, 50),
		hair = { style = "messy", color = rgb(236, 196, 76) },
		headwear = { kind = "band", color = rgb(56, 166, 84), heart = rgb(60, 196, 96) },
		face = { eyes = "sharp", eyeColor = rgb(170, 60, 90) },
		coat = { color = rgb(228, 172, 62), length = 0.22 },
		bands = {
			{ limb = "arms", from = 0.66, to = 0.74, color = rgb(56, 166, 84) },
			{ limb = "legs", from = 0.72, to = 0.78, color = rgb(56, 166, 84) },
		},
		emblems = {
			{
				shape = "heart",
				anchor = "leftLeg",
				at = v(0, -0.2, -0.068),
				size = 0.06,
				color = rgb(56, 166, 84),
				fine = true,
			},
			{
				shape = "heart",
				anchor = "rightLeg",
				at = v(0, -0.2, -0.068),
				size = 0.06,
				color = rgb(56, 166, 84),
				fine = true,
			},
		},
		weapons = { { kind = "dagger", hand = "both", length = 0.12, blade = STEEL, hilt = GOLD } }, -- thrown knives
	},

	restoration_strike = {
		skin = SKIN,
		torso = rgb(26, 26, 36),
		pants = rgb(26, 26, 36),
		shoes = BLACK,
		shoe = 0.14,
		sleeve = 0.85,
		hair = { style = "pompadour", color = rgb(62, 42, 92) },
		face = { eyes = "sharp", eyeColor = rgb(60, 80, 140) },
		coat = { color = rgb(26, 26, 36), length = 0.35, open = false, collar = rgb(26, 26, 36) },
		buttons = { color = GOLD, count = 3 },
		emblems = {
			{ shape = "heart", anchor = "hips", at = v(-0.075, 0.355, -0.115), size = 0.05, color = GOLD },
			{ shape = "disc", anchor = "hips", at = v(0.075, 0.355, -0.115), size = 0.045, color = GOLD },
		},
		bands = { { limb = "arms", from = 0.76, to = 0.8, color = GOLD, fine = true } },
	},

	-- Cursed ---------------------------------------------------------------------------------

	ripcord_frenzy = {
		skin = SKIN,
		torso = rgb(236, 236, 230),
		sleeve = 0.62,
		pants = BLACK,
		shoes = rgb(205, 45, 45),
		shoe = 0.15,
		hair = { style = "messy", color = rgb(228, 190, 100) },
		face = { eyes = "open", eyeColor = rgb(110, 80, 40), mouth = true },
		tie = BLACK,
		belt = { color = rgb(70, 45, 30) },
		bands = { { limb = "legs", from = 0.95, to = 1, color = WHITE, fine = true } }, -- white soles
		extras = {
			-- the pull cord on his chest
			{
				anchor = "hips",
				shape = "Block",
				size = v(0.05, 0.02, 0.02),
				at = v(0.08, 0.22, -0.1),
				color = rgb(40, 40, 40),
				fine = true,
			},
		},
	},

	crimson_hunger = {
		skin = SKIN,
		torso = rgb(26, 26, 31),
		sleeve = 0.84,
		pants = rgb(38, 38, 44),
		shoes = BLACK,
		shoe = 0.14,
		hair = { style = "messy", color = rgb(236, 236, 240) },
		face = {
			eyes = "open",
			leftEye = rgb(222, 30, 42),
			rightEye = rgb(60, 60, 70),
			mask = { color = rgb(22, 22, 26), teeth = WHITE },
		},
		buttons = { color = WHITE, count = 3 },
		bands = {
			{ limb = "arms", from = 0.48, to = 0.54, color = rgb(192, 192, 198) },
			{ limb = "arms", from = 0.6, to = 0.66, color = rgb(192, 192, 198) },
		},
		tendrils = { color = rgb(178, 22, 38) },
	},

	shade_pack = {
		skin = SKIN,
		torso = NAVY,
		pants = NAVY,
		shoes = rgb(110, 72, 42),
		shoe = 0.12,
		sleeve = 0.86,
		collar = NAVY,
		hair = { style = "wild", color = INK },
		face = { eyes = "open", eyeColor = rgb(40, 40, 52) },
		extras = {
			-- blue highlights on the uniform
			{
				anchor = "hips",
				shape = "Block",
				size = v(0.012, 0.22, 0.008),
				at = v(-0.1, 0.16, -0.093),
				turn = v(0, 0, 8),
				color = rgb(64, 88, 180),
				fine = true,
			},
			{
				anchor = "hips",
				shape = "Block",
				size = v(0.012, 0.18, 0.008),
				at = v(0.11, 0.12, -0.093),
				turn = v(0, 0, -6),
				color = rgb(64, 88, 180),
				fine = true,
			},
		},
	},

	night_parade = {
		bulk = 1.1, -- loose, baggy clothes
		skin = SKIN,
		torso = rgb(30, 34, 60),
		pants = rgb(30, 34, 60),
		wideLegs = 1.15,
		shoes = BLACK,
		shoe = 0.1,
		sleeve = 0.86,
		hair = {
			style = "bun",
			color = INK,
			strands = { { x = 0.32, length = 0.78 } }, -- the long fringe strand
		},
		face = { eyes = "closed" },
		coat = { color = rgb(30, 34, 60), length = 0.18, open = false, collar = rgb(30, 34, 60) },
		emblems = {
			{ shape = "disc", anchor = "hips", at = v(0.05, 0.31, -0.104), size = 0.035, color = GOLD, fine = true },
		},
	},

	severing_temple = {
		bulk = 1.1, -- muscular
		skin = TAN_SKIN,
		torso = TAN_SKIN, -- shirtless
		sleeve = 0,
		pants = rgb(238, 232, 220), -- loose white robe bottom
		wideLegs = 1.25,
		shoes = BLACK,
		shoe = 0.1,
		hair = { style = "spiky", color = rgb(240, 146, 156) },
		face = { eyes = "sharp", eyeColor = rgb(170, 40, 50) },
		sash = { color = rgb(25, 25, 25) },
		bands = { -- tattoo stripes
			{ limb = "arms", from = 0.28, to = 0.32, color = rgb(25, 25, 25) },
			{ limb = "arms", from = 0.5, to = 0.54, color = rgb(25, 25, 25) },
		},
		extras = {
			{
				anchor = "hips",
				shape = "Block",
				size = v(0.22, 0.014, 0.006),
				at = v(0, 0.25, -0.092),
				color = rgb(25, 25, 25),
			},
			{
				anchor = "hips",
				shape = "Block",
				size = v(0.16, 0.014, 0.006),
				at = v(0, 0.17, -0.092),
				color = rgb(25, 25, 25),
			},
			{
				anchor = "head",
				shape = "Block",
				size = v(0.034, 0.008, 0.006),
				at = v(-0.044, -0.03, -0.101),
				color = rgb(25, 25, 25),
				fine = true,
			},
			{
				anchor = "head",
				shape = "Block",
				size = v(0.034, 0.008, 0.006),
				at = v(0.044, -0.03, -0.101),
				color = rgb(25, 25, 25),
				fine = true,
			},
		},
	},

	infinite_collapse = {
		skin = SKIN,
		torso = rgb(26, 26, 31),
		sleeve = 0.42,
		pants = rgb(228, 228, 236),
		wideLegs = 1.2,
		shoes = BLACK,
		shoe = 0.12,
		hair = { style = "spiky", color = rgb(234, 240, 252), lift = 0.6 },
		face = { eyes = "open", eyeColor = rgb(110, 190, 246) },
		sash = { color = rgb(40, 40, 72) },
	},

	-- Arcane ---------------------------------------------------------------------------------

	null_edge = {
		bulk = 1.08,
		skin = SKIN,
		torso = SKIN, -- bare chest under the open coat
		pants = rgb(30, 30, 32),
		shoes = rgb(110, 70, 42),
		shoe = 0.26,
		sleeve = 0.85,
		hair = { style = "spiky", color = rgb(216, 206, 172) },
		headwear = { kind = "band", color = rgb(24, 24, 24) },
		face = { eyes = "sharp", eyeColor = rgb(160, 40, 40), mouth = true },
		coat = { color = rgb(22, 22, 26), length = 0, gap = 0.4 },
		belt = { color = rgb(100, 65, 40) },
		weapons = {
			{
				kind = "greatsword",
				hand = "right",
				blade = rgb(22, 22, 28),
				edge = rgb(70, 75, 86),
				hilt = rgb(40, 30, 25),
			},
		},
	},

	bitter_vapor = {
		skin = SKIN,
		torso = rgb(170, 210, 165),
		pants = rgb(128, 40, 70),
		shoes = rgb(60, 45, 40),
		shoe = 0.12,
		sleeve = 0.9,
		hair = {
			style = "bun",
			color = rgb(72, 98, 62),
			strands = { -- long side strands
				{ x = -0.5, z = -0.28, length = 1.2, width = 0.16 },
				{ x = 0.5, z = -0.28, length = 1.2, width = 0.16 },
			},
		},
		face = { eyes = "open", eyeColor = rgb(120, 100, 170) },
		coat = { color = rgb(170, 210, 165), length = 0.28, open = false },
		weapons = {
			{ kind = "vial", hand = "left", color = rgb(110, 220, 130) },
			{ kind = "basket", color = rgb(150, 110, 65) },
		},
	},

	starless_burst = {
		skin = SKIN,
		torso = WHITE,
		pants = rgb(58, 52, 62),
		shoes = rgb(40, 36, 42),
		shoe = 0.3,
		sleeve = 0.85,
		hair = { style = "twintails", color = rgb(240, 240, 246) },
		ears = "elf",
		face = { eyes = "open", eyeColor = rgb(80, 160, 130) },
		coat = {
			color = rgb(242, 242, 244),
			length = 0.55,
			flare = 5,
			trim = rgb(222, 182, 72),
			stripes = BLACK, -- the black-and-white striped top
		},
		belt = { color = rgb(40, 35, 35), buckle = GOLD },
		bands = { { limb = "arms", from = 0.76, to = 0.82, color = rgb(222, 182, 72), fine = true } },
		weapons = {
			{
				kind = "staff",
				hand = "right",
				shaft = rgb(95, 58, 40),
				head = rgb(222, 182, 72),
				orb = rgb(210, 35, 45),
			},
		},
	},

	night_command = {
		skin = SKIN,
		torso = rgb(230, 230, 232),
		pants = BLACK,
		shoes = BLACK,
		shoe = 0.14,
		sleeve = 0.82,
		hair = { style = "messy", color = INK },
		face = { eyes = "sharp", eyeColor = rgb(90, 110, 150) },
		coat = { color = rgb(20, 20, 24), length = 0.7, flare = 6 },
		extras = {
			-- dark lines on the shirt
			{
				anchor = "hips",
				shape = "Block",
				size = v(0.1, 0.01, 0.006),
				at = v(0, 0.24, -0.094),
				turn = v(0, 0, 10),
				color = rgb(60, 60, 66),
				fine = true,
			},
			{
				anchor = "hips",
				shape = "Block",
				size = v(0.1, 0.01, 0.006),
				at = v(0, 0.16, -0.094),
				turn = v(0, 0, -10),
				color = rgb(60, 60, 66),
				fine = true,
			},
		},
		weapons = {
			{
				kind = "dagger",
				hand = "left",
				length = 0.19,
				blade = rgb(150, 205, 245),
				hilt = rgb(40, 50, 70),
				material = "Neon",
			},
			{
				kind = "dagger",
				hand = "right",
				length = 0.19,
				blade = rgb(150, 20, 34),
				hilt = rgb(50, 30, 30),
				material = "Neon",
			},
		},
		hand = "both",
		arms = { 25, 25 },
	},

	-- Titans and the toad: the big signature units, more detailed than a standard figure. They keep
	-- their FigureConfig.characters size (or `scale` here); their own proportions replace bulk.

	-- An armored giant: gold-tan plates over red muscle on the chest, shoulders, forearms and shins,
	-- short white hair, a heavy brow.
	iron_rush = {
		proportions = {
			legLength = 0.38,
			legWidth = 0.17,
			legSpacing = 0.11,
			torsoHeight = 0.36,
			torsoWidth = 0.46,
			torsoDepth = 0.25,
			neck = 0.01,
			headSize = 0.22,
			armLength = 0.36,
			armWidth = 0.15,
		},
		skin = rgb(214, 172, 100), -- the armored face
		torso = rgb(150, 38, 34),
		sleeves = rgb(150, 38, 34),
		sleeve = 1,
		pants = rgb(150, 38, 34),
		shoes = rgb(170, 128, 68),
		shoe = 0.16,
		hair = { style = "neat", color = rgb(236, 234, 226) },
		face = { eyes = "sharp", eyeColor = rgb(40, 28, 22) },
		belt = { color = rgb(170, 128, 68) },
		extras = {
			-- face armor: a heavy brow, a clenched jaw line, jaw guards
			{
				anchor = "head",
				shape = "Block",
				size = v(0.24, 0.04, 0.05),
				at = v(0, 0.03, -0.105),
				color = rgb(170, 128, 68),
			},
			{
				anchor = "head",
				shape = "Block",
				size = v(0.16, 0.02, 0.01),
				at = v(0, -0.06, -0.112),
				color = rgb(110, 26, 24),
			},
			{
				anchor = "head",
				shape = "Block",
				size = v(0.03, 0.09, 0.03),
				at = v(0.1, -0.04, -0.09),
				color = rgb(170, 128, 68),
				mirror = true,
			},
			-- chest: pec plates, three rows of ab plates, side plates, back plate, collar guard, hip faulds
			{
				anchor = "hips",
				shape = "Block",
				size = v(0.2, 0.11, 0.03),
				at = v(0.105, 0.29, -0.13),
				color = rgb(214, 172, 100),
				mirror = true,
			},
			{
				anchor = "hips",
				shape = "Block",
				size = v(0.085, 0.055, 0.025),
				at = v(0.05, 0.19, -0.13),
				color = rgb(214, 172, 100),
				mirror = true,
			},
			{
				anchor = "hips",
				shape = "Block",
				size = v(0.085, 0.055, 0.025),
				at = v(0.05, 0.125, -0.13),
				color = rgb(214, 172, 100),
				mirror = true,
			},
			{
				anchor = "hips",
				shape = "Block",
				size = v(0.085, 0.055, 0.025),
				at = v(0.05, 0.06, -0.13),
				color = rgb(214, 172, 100),
				mirror = true,
			},
			{
				anchor = "hips",
				shape = "Block",
				size = v(0.03, 0.18, 0.2),
				at = v(0.235, 0.15, -0.01),
				color = rgb(214, 172, 100),
				mirror = true,
			},
			{
				anchor = "hips",
				shape = "Block",
				size = v(0.38, 0.26, 0.03),
				at = v(0, 0.2, 0.13),
				color = rgb(214, 172, 100),
			},
			{
				anchor = "hips",
				shape = "Block",
				size = v(0.3, 0.06, 0.27),
				at = v(0, 0.37, 0),
				color = rgb(170, 128, 68),
			},
			{
				anchor = "hips",
				shape = "Block",
				size = v(0.17, 0.1, 0.03),
				at = v(0.11, -0.04, -0.13),
				turn = v(10, 0, 0),
				color = rgb(214, 172, 100),
				mirror = true,
			},
			{
				anchor = "hips",
				shape = "Block",
				size = v(0.012, 0.25, 0.006),
				at = v(0, 0.15, -0.141),
				color = rgb(110, 26, 24),
				fine = true,
			},
			-- arms: a pauldron, an outer plate on the upper arm, a forearm guard with a dark edge
			{
				limbs = "Arm",
				shape = "Block",
				size = v(0.21, 0.13, 0.21),
				at = v(0, -0.02, 0),
				color = rgb(214, 172, 100),
			},
			{
				limbs = "Arm",
				shape = "Block",
				size = v(0.03, 0.12, 0.13),
				at = v(0.085, -0.15, 0),
				color = rgb(214, 172, 100),
			},
			{
				limbs = "Arm",
				shape = "Block",
				size = v(0.17, 0.13, 0.17),
				at = v(0, -0.27, 0),
				color = rgb(214, 172, 100),
			},
			{
				limbs = "Arm",
				shape = "Block",
				size = v(0.175, 0.02, 0.175),
				at = v(0, -0.205, 0),
				color = rgb(170, 128, 68),
				fine = true,
			},
			-- legs: thigh plate, knee guard, shin guard
			{
				limbs = "Leg",
				shape = "Block",
				size = v(0.15, 0.14, 0.03),
				at = v(0, -0.1, -0.095),
				color = rgb(214, 172, 100),
			},
			{
				limbs = "Leg",
				shape = "Block",
				size = v(0.18, 0.05, 0.18),
				at = v(0, -0.2, 0),
				color = rgb(170, 128, 68),
			},
			{
				limbs = "Leg",
				shape = "Block",
				size = v(0.185, 0.12, 0.19),
				at = v(0, -0.28, 0),
				color = rgb(214, 172, 100),
			},
		},
	},

	-- Very tall and ape-like, stooping: shaggy dark brown fur in rough layers, a lighter tan chest,
	-- long arms reaching near the knees, a bearded human-like face.
	skyboulder = {
		proportions = {
			legLength = 0.36,
			legWidth = 0.16,
			legSpacing = 0.1,
			torsoHeight = 0.38,
			torsoWidth = 0.44,
			torsoDepth = 0.26,
			neck = 0,
			headSize = 0.2,
			armLength = 0.5,
			armWidth = 0.15,
		},
		lean = 10,
		skin = rgb(200, 160, 126),
		torso = rgb(74, 48, 32),
		sleeves = rgb(74, 48, 32),
		sleeve = 0.9,
		gloves = rgb(160, 120, 82),
		pants = rgb(74, 48, 32),
		shoes = rgb(52, 33, 22),
		shoe = 0.12,
		hair = { style = "messy", color = rgb(52, 33, 22) },
		face = { eyes = "sharp", eyeColor = rgb(30, 22, 18), mouth = true },
		extras = {
			-- a beard, whiskers down the sides, a broad nose
			{
				anchor = "head",
				shape = "Block",
				size = v(0.17, 0.08, 0.05),
				at = v(0, -0.075, -0.095),
				color = rgb(52, 33, 22),
			},
			{
				anchor = "head",
				shape = "Block",
				size = v(0.04, 0.11, 0.12),
				at = v(0.1, -0.04, -0.03),
				color = rgb(52, 33, 22),
				mirror = true,
			},
			{
				anchor = "head",
				shape = "Block",
				size = v(0.05, 0.04, 0.03),
				at = v(0, -0.015, -0.105),
				color = rgb(160, 120, 82),
			},
			-- the tan chest and belly, with muscle lines
			{
				anchor = "hips",
				shape = "Block",
				size = v(0.34, 0.12, 0.03),
				at = v(0, 0.28, -0.135),
				color = rgb(192, 152, 108),
			},
			{
				anchor = "hips",
				shape = "Block",
				size = v(0.24, 0.16, 0.03),
				at = v(0, 0.13, -0.135),
				color = rgb(192, 152, 108),
			},
			{
				anchor = "hips",
				shape = "Block",
				size = v(0.008, 0.15, 0.006),
				at = v(0, 0.13, -0.151),
				color = rgb(160, 120, 82),
				fine = true,
			},
			{
				anchor = "hips",
				shape = "Block",
				size = v(0.22, 0.008, 0.006),
				at = v(0, 0.16, -0.151),
				color = rgb(160, 120, 82),
				fine = true,
			},
			{
				anchor = "hips",
				shape = "Block",
				size = v(0.22, 0.008, 0.006),
				at = v(0, 0.1, -0.151),
				color = rgb(160, 120, 82),
				fine = true,
			},
			-- a hump of fur over the shoulders, and fur down the back
			{
				anchor = "hips",
				shape = "Block",
				size = v(0.46, 0.1, 0.22),
				at = v(0, 0.38, 0.03),
				color = rgb(52, 33, 22),
			},
			{
				anchor = "hips",
				shape = "Block",
				size = v(0.4, 0.3, 0.04),
				at = v(0, 0.2, 0.135),
				color = rgb(52, 33, 22),
			},
			-- shaggy points along the waist and a V of fur on the belly
			{
				anchor = "hips",
				shape = "Block",
				size = v(0.08, 0.08, 0.04),
				at = v(0.13, 0, -0.13),
				turn = v(0, 0, 45),
				color = rgb(74, 48, 32),
				mirror = true,
			},
			{
				anchor = "hips",
				shape = "Block",
				size = v(0.08, 0.08, 0.04),
				at = v(0.12, 0, 0.13),
				turn = v(0, 0, 45),
				color = rgb(52, 33, 22),
				mirror = true,
			},
			{
				anchor = "hips",
				shape = "Block",
				size = v(0.1, 0.1, 0.03),
				at = v(0, 0.04, -0.137),
				turn = v(0, 0, 45),
				color = rgb(74, 48, 32),
			},
			-- arms: a ruff at the shoulder, shaggy tufts at the elbow and forearm, a ruff at the wrist
			{ limbs = "Arm", shape = "Block", size = v(0.2, 0.1, 0.2), at = v(0, -0.01, 0), color = rgb(52, 33, 22) },
			{
				limbs = "Arm",
				shape = "Block",
				size = v(0.07, 0.07, 0.04),
				at = v(0.08, -0.24, 0),
				turn = v(0, 0, 45),
				color = rgb(52, 33, 22),
			},
			{
				limbs = "Arm",
				shape = "Block",
				size = v(0.07, 0.07, 0.04),
				at = v(0.08, -0.36, 0.02),
				turn = v(0, 0, 45),
				color = rgb(52, 33, 22),
				fine = true,
			},
			{
				limbs = "Arm",
				shape = "Block",
				size = v(0.17, 0.04, 0.17),
				at = v(0, -0.44, 0),
				color = rgb(52, 33, 22),
			},
			-- legs: shaggy tufts on the thigh, knee and calf
			{
				limbs = "Leg",
				shape = "Block",
				size = v(0.07, 0.07, 0.04),
				at = v(0.08, -0.1, 0),
				turn = v(0, 0, 45),
				color = rgb(52, 33, 22),
			},
			{
				limbs = "Leg",
				shape = "Block",
				size = v(0.08, 0.08, 0.04),
				at = v(0, -0.18, -0.085),
				turn = v(0, 0, 45),
				color = rgb(52, 33, 22),
			},
			{
				limbs = "Leg",
				shape = "Block",
				size = v(0.07, 0.07, 0.04),
				at = v(0.085, -0.27, 0),
				turn = v(0, 0, 45),
				color = rgb(52, 33, 22),
				fine = true,
			},
		},
	},

	-- The largest unit, gaunt: red exposed muscle bands with pale tendon stripes, a pale skinless face
	-- with teeth, and soft steam drifting off the body. No wounds or gore: stylized muscle.
	boiling_crown = {
		proportions = {
			legLength = 0.42,
			legWidth = 0.14,
			legSpacing = 0.09,
			torsoHeight = 0.34,
			torsoWidth = 0.4,
			torsoDepth = 0.2,
			neck = 0.02,
			headSize = 0.18,
			armLength = 0.38,
			armWidth = 0.12,
		},
		skin = rgb(236, 218, 204),
		torso = rgb(188, 40, 38),
		sleeves = rgb(188, 40, 38),
		sleeve = 1,
		pants = rgb(188, 40, 38),
		shoes = rgb(128, 24, 26),
		shoe = 0.1,
		face = {
			eyes = "sharp",
			eyeColor = rgb(30, 20, 20),
			mask = { color = rgb(128, 24, 26), teeth = rgb(246, 240, 230) },
		},
		belt = { color = rgb(30, 24, 24) },
		bands = { -- pale tendon stripes across the limbs
			{ limb = "arms", from = 0.18, to = 0.21, color = rgb(242, 208, 188) },
			{ limb = "arms", from = 0.42, to = 0.45, color = rgb(242, 208, 188) },
			{ limb = "arms", from = 0.66, to = 0.69, color = rgb(242, 208, 188) },
			{ limb = "legs", from = 0.2, to = 0.23, color = rgb(242, 208, 188) },
			{ limb = "legs", from = 0.55, to = 0.58, color = rgb(242, 208, 188) },
		},
		steam = { rate = 4, color = rgb(245, 240, 235), size = 0.16 },
		extras = {
			-- a red crown of muscle over the skull and red lines down the cheeks
			{
				anchor = "head",
				shape = "Block",
				size = v(0.19, 0.05, 0.19),
				at = v(0, 0.075, 0),
				color = rgb(188, 40, 38),
			},
			{
				anchor = "head",
				shape = "Block",
				size = v(0.02, 0.08, 0.01),
				at = v(0.05, -0.005, -0.092),
				color = rgb(188, 40, 38),
				mirror = true,
			},
			-- chest: raised pecs with pale edges, abdominal lines, obliques, ribs, collarbones
			{
				anchor = "hips",
				shape = "Block",
				size = v(0.17, 0.1, 0.03),
				at = v(0.09, 0.27, -0.105),
				color = rgb(128, 24, 26),
				mirror = true,
			},
			{
				anchor = "hips",
				shape = "Block",
				size = v(0.17, 0.012, 0.006),
				at = v(0.09, 0.218, -0.121),
				color = rgb(242, 208, 188),
				mirror = true,
				fine = true,
			},
			{
				anchor = "hips",
				shape = "Block",
				size = v(0.012, 0.2, 0.006),
				at = v(0, 0.12, -0.103),
				color = rgb(242, 208, 188),
			},
			{
				anchor = "hips",
				shape = "Block",
				size = v(0.15, 0.01, 0.006),
				at = v(0, 0.17, -0.103),
				color = rgb(242, 208, 188),
			},
			{
				anchor = "hips",
				shape = "Block",
				size = v(0.15, 0.01, 0.006),
				at = v(0, 0.12, -0.103),
				color = rgb(242, 208, 188),
			},
			{
				anchor = "hips",
				shape = "Block",
				size = v(0.15, 0.01, 0.006),
				at = v(0, 0.07, -0.103),
				color = rgb(242, 208, 188),
			},
			{
				anchor = "hips",
				shape = "Block",
				size = v(0.012, 0.006),
				at = v(0.12, 0.2, -0.104),
				to = v(0.075, 0.04, -0.104),
				color = rgb(242, 208, 188),
				mirror = true,
			},
			{
				anchor = "hips",
				shape = "Block",
				size = v(0.006, 0.2, 0.12),
				at = v(0.203, 0.18, 0),
				color = rgb(128, 24, 26),
				mirror = true,
				fine = true,
			},
			{
				anchor = "hips",
				shape = "Block",
				size = v(0.012, 0.006),
				at = v(0.02, 0.33, -0.104),
				to = v(0.17, 0.31, -0.104),
				color = rgb(242, 208, 188),
				mirror = true,
			},
			-- raised biceps, forearms and thighs; a pale line down each shin
			{
				limbs = "Arm",
				shape = "Block",
				size = v(0.1, 0.12, 0.04),
				at = v(0, -0.1, -0.06),
				color = rgb(128, 24, 26),
			},
			{
				limbs = "Arm",
				shape = "Block",
				size = v(0.1, 0.12, 0.04),
				at = v(0, -0.27, -0.06),
				color = rgb(128, 24, 26),
			},
			{
				limbs = "Leg",
				shape = "Block",
				size = v(0.11, 0.15, 0.03),
				at = v(0, -0.12, -0.075),
				color = rgb(128, 24, 26),
			},
			{
				limbs = "Leg",
				shape = "Block",
				size = v(0.01, 0.12, 0.006),
				at = v(0, -0.3, -0.073),
				color = rgb(242, 208, 188),
			},
		},
	},

	-- A giant samurai toad, not a humanoid: a wide, low crouch; a broad flat head with heavy brow
	-- ridges and yellow eyes; red-pink skin with darker red stripes; a navy short kimono jacket with
	-- white trim over a pale belly and a white sash; wide webbed hands and feet; a katana in the right
	-- hand and a long pipe with a white bowl in the mouth. The standard anchors stay: short wide-set
	-- legs (the hips sit low), shoulders at the jacket's edge, the head sunk into the body.
	marsh_fortress = {
		proportions = {
			legLength = 0.2,
			legWidth = 0.12,
			legSpacing = 0.17,
			torsoHeight = 0.34,
			torsoWidth = 0.56,
			torsoDepth = 0.44,
			neck = -0.08,
			headSize = 0.3,
			armLength = 0.3,
			armWidth = 0.13,
		},
		scale = 1.2,
		lean = 6,
		headScale = v(1.55, 0.6, 1.15),
		customArms = true,
		customLegs = true,
		skin = rgb(196, 98, 98),
		torso = rgb(36, 42, 78),
		pants = rgb(196, 98, 98),
		shoes = rgb(196, 98, 98),
		face = { eyes = "none" },
		coat = {
			color = rgb(36, 42, 78),
			length = 0.15,
			inner = rgb(226, 162, 150),
			gap = 0.45,
			cross = rgb(240, 238, 230),
			trim = rgb(240, 238, 230),
		},
		sash = { color = rgb(240, 238, 230) },
		weapons = {
			{
				kind = "katana",
				hand = "right",
				length = 0.55,
				blade = rgb(205, 210, 220),
				hilt = rgb(235, 225, 200),
				guard = rgb(60, 55, 50),
			},
		},
		hand = "right",
		arms = { 15, 25 },
		extras = {
			-- a round pale belly with the sash across it
			{
				anchor = "hips",
				shape = "Ball",
				size = v(0.36, 0.36, 0.36),
				at = v(0, 0.14, -0.13),
				color = rgb(226, 162, 150),
			},
			{
				anchor = "hips",
				shape = "Block",
				size = v(0.4, 0.09, 0.06),
				at = v(0, 0.07, -0.27),
				color = rgb(240, 238, 230),
			},
			-- the head: big yellow eyes bulging from the top of the head with slit pupils, heavy brow
			-- ridges over them like lids, a wide mouth, stripes on top, cheek pouches, warts
			{
				anchor = "head",
				shape = "Block",
				size = v(0.15, 0.07, 0.12),
				at = v(0.12, 0.135, -0.105),
				turn = v(0, 0, -12),
				color = rgb(140, 42, 46),
				mirror = true,
			},
			{
				anchor = "head",
				shape = "Ball",
				size = v(0.11, 0.11, 0.11),
				at = v(0.13, 0.1, -0.14),
				color = rgb(236, 200, 60),
				plain = true,
				mirror = true,
			},
			{
				anchor = "head",
				shape = "Block",
				size = v(0.06, 0.016, 0.01),
				at = v(0.13, 0.095, -0.196),
				color = rgb(20, 18, 18),
				plain = true,
				mirror = true,
			},
			{
				anchor = "head",
				shape = "Block",
				size = v(0.42, 0.016, 0.01),
				at = v(0, -0.035, -0.174),
				color = rgb(140, 42, 46),
			},
			{
				anchor = "head",
				shape = "Block",
				size = v(0.05, 0.016, 0.01),
				at = v(0.215, -0.045, -0.165),
				turn = v(0, 0, -20),
				color = rgb(140, 42, 46),
				mirror = true,
			},
			{
				anchor = "head",
				shape = "Block",
				size = v(0.035, 0.01, 0.3),
				at = v(0, 0.091, 0),
				color = rgb(140, 42, 46),
			},
			{
				anchor = "head",
				shape = "Block",
				size = v(0.035, 0.01, 0.28),
				at = v(0.1, 0.091, 0.01),
				color = rgb(140, 42, 46),
				mirror = true,
			},
			{
				anchor = "head",
				shape = "Ball",
				size = v(0.12, 0.12, 0.12),
				at = v(0.2, -0.03, -0.06),
				color = rgb(196, 98, 98),
				mirror = true,
			},
			{
				anchor = "head",
				shape = "Ball",
				size = v(0.025, 0.025, 0.025),
				at = v(0.18, 0.05, -0.12),
				color = rgb(140, 42, 46),
				mirror = true,
				fine = true,
			},
			-- the pipe from the right corner of the mouth, with a white bowl
			{
				anchor = "head",
				shape = "Block",
				size = v(0.018, 0.018),
				at = v(0.17, -0.045, -0.165),
				to = v(0.36, -0.12, -0.31),
				color = rgb(200, 160, 70),
			},
			{
				anchor = "head",
				shape = "Ball",
				size = v(0.09, 0.09, 0.09),
				at = v(0.38, -0.12, -0.33),
				color = rgb(240, 238, 230),
			},
			{
				anchor = "head",
				shape = "Ball",
				size = v(0.035, 0.035, 0.035),
				at = v(0.355, -0.115, -0.305),
				color = rgb(200, 160, 70),
				fine = true,
			},
			-- arms: a navy sleeve with a white cuff, a striped red forearm, a wide webbed hand
			{
				limbs = "Arm",
				shape = "Block",
				size = v(0.18, 0.13, 0.18),
				at = v(0, -0.045, 0),
				color = rgb(36, 42, 78),
			},
			{
				limbs = "Arm",
				shape = "Block",
				size = v(0.185, 0.025, 0.185),
				at = v(0, -0.11, 0),
				color = rgb(240, 238, 230),
			},
			{
				limbs = "Arm",
				shape = "Block",
				size = v(0.12, 0.16, 0.12),
				at = v(0, -0.19, 0),
				color = rgb(196, 98, 98),
			},
			{
				limbs = "Arm",
				shape = "Block",
				size = v(0.125, 0.02, 0.125),
				at = v(0, -0.2, 0),
				color = rgb(140, 42, 46),
			},
			{
				limbs = "Arm",
				shape = "Block",
				size = v(0.17, 0.04, 0.15),
				at = v(0, -0.29, -0.02),
				color = rgb(196, 98, 98),
			},
			{
				limbs = "Arm",
				shape = "Block",
				size = v(0.025, 0.02, 0.08),
				at = v(-0.055, -0.295, -0.1),
				color = rgb(196, 98, 98),
				fine = true,
			},
			{
				limbs = "Arm",
				shape = "Block",
				size = v(0.025, 0.02, 0.08),
				at = v(0, -0.295, -0.1),
				color = rgb(196, 98, 98),
				fine = true,
			},
			{
				limbs = "Arm",
				shape = "Block",
				size = v(0.025, 0.02, 0.08),
				at = v(0.055, -0.295, -0.1),
				color = rgb(196, 98, 98),
				fine = true,
			},
			-- legs: a thick thigh bent out, a shin back in, a wide webbed foot with toes
			{
				limbs = "Leg",
				shape = "Block",
				size = v(0.15, 0.13),
				at = v(0, 0, 0.03),
				to = v(0.1, -0.1, 0.02),
				color = rgb(196, 98, 98),
			},
			{
				limbs = "Leg",
				shape = "Block",
				size = v(0.1, 0.1),
				at = v(0.1, -0.1, 0),
				to = v(0.06, -0.165, -0.04),
				color = rgb(196, 98, 98),
			},
			{
				limbs = "Leg",
				shape = "Block",
				size = v(0.155, 0.02),
				at = v(0.03, -0.03, 0.03),
				to = v(0.09, -0.09, 0.02),
				color = rgb(140, 42, 46),
				fine = true,
			},
			{
				limbs = "Leg",
				shape = "Block",
				size = v(0.22, 0.025, 0.25),
				at = v(0.07, -0.17, -0.09),
				color = rgb(196, 98, 98),
			},
			{
				limbs = "Leg",
				shape = "Block",
				size = v(0.03, 0.02, 0.1),
				at = v(0, -0.173, -0.22),
				color = rgb(196, 98, 98),
				fine = true,
			},
			{
				limbs = "Leg",
				shape = "Block",
				size = v(0.03, 0.02, 0.1),
				at = v(0.07, -0.173, -0.23),
				color = rgb(196, 98, 98),
				fine = true,
			},
			{
				limbs = "Leg",
				shape = "Block",
				size = v(0.03, 0.02, 0.1),
				at = v(0.14, -0.173, -0.22),
				color = rgb(196, 98, 98),
				fine = true,
			},
		},
	},
})
