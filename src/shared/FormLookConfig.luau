-- Hand-built looks for transformations (client visuals only), by unit id (UnitConfig key) and then
-- form name (the unit's UnitConfig `forms`). When a unit changes into a form listed here, its whole
-- figure is redrawn as this look (LookKit, the UnitLookConfig format) in place of its base figure
-- (catalog avatar, hand-built look or placeholder), with a puff of smoke (UnitView). A form not
-- listed keeps the base figure and its RenderConfig.formLooks `tint`. The form's RenderConfig
-- `scale` still applies; `scale` here multiplies it (and `bulk` widens the body).
-- Drafts from docs/references/<unit_id>_form*.png and index.md (local only); part 2 refines them.
-- No blood or gore: the references that show any are drawn clean.

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

local v = Vector3.new

local function deepFreeze<T>(value: T): T
	if type(value) == "table" and not table.isfrozen(value) then
		for _, child in value :: any do
			deepFreeze(child)
		end
		table.freeze(value)
	end
	return value
end

-- A copy of `base` with `changes` on top (shallow).
local function with(base: { [string]: any }, changes: { [string]: any }): { [string]: any }
	local result = table.clone(base)
	for key, value in changes do
		result[key] = value
	end
	return result
end

local SKIN = rgb(245, 205, 165)
local WHITE = rgb(240, 240, 238)
local BLACK = rgb(28, 28, 33)
local INK = rgb(20, 20, 26)
local STEEL = rgb(200, 205, 215)

-- ascending_core: the gold forms keep the gi; the hair and eyes step up. No glow shell around the
-- figure (a see-through Neon ball read as a cheap yellow bubble): its aura is the ultimate's
-- particles (VfxRecipe.aura, Ultimates/ascending_core).
local GI_ORANGE = rgb(240, 125, 35)
local GI_BLUE = rgb(35, 55, 150)
local GOLD_HAIR = rgb(250, 214, 80)
local core = {
	skin = SKIN,
	torso = GI_BLUE,
	sleeves = GI_BLUE,
	sleeve = 0.35,
	pants = GI_ORANGE,
	shoes = GI_BLUE,
	shoe = 0.2,
	face = { eyes = "sharp", eyeColor = rgb(60, 205, 95) },
	coat = { color = GI_ORANGE, length = 0, inner = GI_BLUE, gap = 0.3 },
	belt = { color = GI_BLUE },
	bands = { { limb = "arms", from = 0.74, to = 0.88, color = GI_BLUE } }, -- wristbands
	emblems = {
		{ shape = "disc", anchor = "hips", at = v(-0.085, 0.24, -0.102), size = 0.065, color = WHITE },
	},
}

-- elastic_wardrum: Gear 2 keeps the red vest, yellow sash and blue shorts.
local DARK_RED = rgb(92, 20, 26)
local STEAM = rgb(250, 250, 250)
local function steam(at: Vector3, size: number)
	return {
		anchor = "hips",
		shape = "Ball",
		size = v(size, size, size),
		at = at,
		color = STEAM,
		transparency = 0.35,
		plain = true,
	}
end

return deepFreeze({
	-- The chainsaw form: an orange engine block for a head with a blade standing out of the top,
	-- a jagged dark mouth of teeth, and a long blade out of each forearm; same shirt, tie and
	-- trousers.
	ripcord_frenzy = {
		Chainsaw = {
			skin = rgb(240, 140, 32), -- the head is the engine
			gloves = SKIN,
			torso = rgb(236, 236, 230),
			sleeve = 0.62,
			pants = BLACK,
			shoes = rgb(205, 45, 45),
			shoe = 0.15,
			tie = BLACK,
			belt = { color = rgb(70, 45, 30) },
			face = { eyes = "none", mask = { color = rgb(72, 16, 22), teeth = rgb(235, 235, 230) } },
			extras = {
				{
					anchor = "head",
					shape = "Block",
					size = v(0.03, 0.2, 0.1),
					at = v(0, 0.19, 0),
					color = STEEL,
					material = "Metal",
				},
				{
					anchor = "head",
					shape = "Block",
					size = v(0.034, 0.03, 0.104),
					at = v(0, 0.28, 0),
					color = rgb(45, 45, 50),
				},
				{
					anchor = "head",
					shape = "Block",
					size = v(0.02, 0.04, 0.06),
					at = v(0.11, 0.03, 0.02),
					color = rgb(45, 45, 50),
					fine = true,
				},
				-- a blade out of each forearm, past the hand
				{
					anchor = "leftArm",
					shape = "Block",
					size = v(0.025, 0.42, 0.075),
					at = v(-0.07, -0.33, 0),
					color = STEEL,
					material = "Metal",
				},
				{
					anchor = "rightArm",
					shape = "Block",
					size = v(0.025, 0.42, 0.075),
					at = v(0.07, -0.33, 0),
					color = STEEL,
					material = "Metal",
				},
				{
					anchor = "leftArm",
					shape = "Block",
					size = v(0.027, 0.4, 0.014),
					at = v(-0.07, -0.34, -0.042),
					color = rgb(45, 45, 50),
					fine = true,
				},
				{
					anchor = "rightArm",
					shape = "Block",
					size = v(0.027, 0.4, 0.014),
					at = v(0.07, -0.34, -0.042),
					color = rgb(45, 45, 50),
					fine = true,
				},
			},
		},
	},

	elastic_wardrum = {
		-- Gear 2: wild black hair, dark red forearms and oversized fists, dark red lower legs and
		-- feet, steam around the body; the red vest, yellow sash and blue shorts with white cuffs.
		["Gear 2"] = {
			skin = SKIN,
			torso = SKIN,
			sleeves = SKIN,
			sleeve = 0.45,
			gloves = DARK_RED,
			pants = rgb(45, 85, 165),
			shorts = 0.5,
			socks = DARK_RED,
			shoes = DARK_RED,
			shoe = 0.1,
			hair = { style = "wild", color = INK },
			face = { eyes = "sharp", eyeColor = rgb(30, 30, 30), mouth = true },
			coat = { color = rgb(200, 35, 35), length = 0, inner = SKIN, gap = 0.5 },
			sash = { color = rgb(240, 200, 40) },
			bands = { { limb = "legs", from = 0.46, to = 0.56, color = WHITE } }, -- fur cuffs
			extras = {
				{
					anchor = "leftHand",
					shape = "Block",
					size = v(0.15, 0.13, 0.15),
					at = v(0, -0.02, 0),
					color = DARK_RED,
				},
				{
					anchor = "rightHand",
					shape = "Block",
					size = v(0.15, 0.13, 0.15),
					at = v(0, -0.02, 0),
					color = DARK_RED,
				},
				steam(v(0.26, 0.32, 0.08), 0.2),
				steam(v(-0.27, 0.2, 0.1), 0.17),
				steam(v(0.2, 0.02, 0.12), 0.15),
				steam(v(-0.16, 0.42, 0.14), 0.14),
			},
		},
		-- Gear 3: everything white: wild white hair, an open white coat and white shorts, a purple
		-- sash, red-pink markings on the chest, red ringed eyes and a big grin, bare feet in
		-- sandals, a soft glow.
		["Gear 3"] = {
			skin = SKIN,
			torso = SKIN,
			sleeve = 0.85,
			pants = WHITE,
			shorts = 0.55,
			shoes = rgb(130, 82, 50), -- sandals
			shoe = 0.07,
			hair = { style = "wild", color = rgb(248, 248, 252) },
			face = { eyes = "open", eyeColor = rgb(215, 40, 60), mouth = true },
			coat = { color = WHITE, length = 0.3, inner = SKIN, gap = 0.4 },
			sash = { color = rgb(120, 60, 170) },
			bands = { { limb = "legs", from = 0.5, to = 0.56, color = rgb(250, 250, 250) } }, -- ruffled hems
			extras = {
				{
					anchor = "hips",
					shape = "Block",
					size = v(0.14, 0.022, 0.006),
					at = v(0, 0.24, -0.093),
					turn = v(0, 0, 35),
					color = rgb(230, 90, 110),
				},
				{
					anchor = "hips",
					shape = "Block",
					size = v(0.14, 0.022, 0.006),
					at = v(0, 0.24, -0.093),
					turn = v(0, 0, -35),
					color = rgb(230, 90, 110),
				},
				{
					anchor = "hips",
					shape = "Ball",
					size = v(0.9, 0.9, 0.9),
					at = v(0, 0.1, 0),
					color = WHITE,
					material = "Neon",
					transparency = 0.88,
					plain = true,
				},
				steam(v(0.24, 0.36, 0.1), 0.18),
				steam(v(-0.25, 0.34, 0.1), 0.16),
			},
		},
	},

	-- The monster form: a big, hulking body with a full shaggy tan mane over the shoulders, chest and
	-- back; long arms with dark claws; thin bent legs on hooves; big branching antlers; the pink hat
	-- with a white X; a blue nose; red-brown shorts.
	field_medic = {
		Bruiser = {
			scale = 1.25,
			proportions = {
				legLength = 0.4,
				legWidth = 0.08,
				legSpacing = 0.1,
				torsoHeight = 0.34,
				torsoWidth = 0.46,
				torsoDepth = 0.24,
				neck = 0,
				headSize = 0.23,
				armLength = 0.44,
				armWidth = 0.14,
			},
			customLegs = true,
			skin = rgb(196, 150, 100),
			torso = rgb(212, 172, 118),
			sleeves = rgb(212, 172, 118),
			sleeve = 0.32,
			pants = rgb(150, 62, 52),
			shoes = rgb(60, 45, 35),
			face = { eyes = "open", eyeColor = rgb(30, 30, 30), mouth = true },
			collar = rgb(212, 172, 118),
			extras = {
				-- the mane: a big ruff, fur down the back, rows of shaggy points over the chest,
				-- fur over the shoulders and tufts at the elbows
				{
					anchor = "hips",
					shape = "Block",
					size = v(0.56, 0.2, 0.32),
					at = v(0, 0.3, 0),
					color = rgb(212, 172, 118),
				},
				{
					anchor = "hips",
					shape = "Block",
					size = v(0.46, 0.22, 0.05),
					at = v(0, 0.2, 0.125),
					color = rgb(180, 138, 88),
				},
				-- shaggy points: a pale fringe hanging from the ruff's front edge (in front of it, so it
				-- shows), a darker row on the chest below, a fringe at the back and tufts standing up
				-- along the ruff's top (the board camera sees it from above and behind)
				{
					anchor = "hips",
					shape = "Block",
					size = v(0.09, 0.09, 0.03),
					at = v(0, 0.2, -0.165),
					turn = v(0, 0, 45),
					color = rgb(236, 210, 160),
				},
				{
					anchor = "hips",
					shape = "Block",
					size = v(0.09, 0.09, 0.03),
					at = v(0.1, 0.2, -0.165),
					turn = v(0, 0, 45),
					color = rgb(236, 210, 160),
					mirror = true,
				},
				{
					anchor = "hips",
					shape = "Block",
					size = v(0.09, 0.09, 0.03),
					at = v(0.2, 0.2, -0.165),
					turn = v(0, 0, 45),
					color = rgb(236, 210, 160),
					mirror = true,
				},
				{
					anchor = "hips",
					shape = "Block",
					size = v(0.07, 0.07, 0.03),
					at = v(0.05, 0.12, -0.13),
					turn = v(0, 0, 45),
					color = rgb(180, 138, 88),
					mirror = true,
				},
				{
					anchor = "hips",
					shape = "Block",
					size = v(0.07, 0.07, 0.03),
					at = v(0.15, 0.12, -0.13),
					turn = v(0, 0, 45),
					color = rgb(180, 138, 88),
					mirror = true,
					fine = true,
				},
				{
					anchor = "hips",
					shape = "Block",
					size = v(0.09, 0.09, 0.03),
					at = v(0, 0.2, 0.165),
					turn = v(0, 0, 45),
					color = rgb(236, 210, 160),
				},
				{
					anchor = "hips",
					shape = "Block",
					size = v(0.09, 0.09, 0.03),
					at = v(0.14, 0.2, 0.165),
					turn = v(0, 0, 45),
					color = rgb(236, 210, 160),
					mirror = true,
				},
				{
					anchor = "hips",
					shape = "Block",
					size = v(0.08, 0.08, 0.12),
					at = v(0.2, 0.41, 0.06),
					turn = v(0, 0, 45),
					color = rgb(236, 210, 160),
					mirror = true,
				},
				{
					anchor = "hips",
					shape = "Block",
					size = v(0.12, 0.08, 0.08),
					at = v(0, 0.41, 0.12),
					turn = v(45, 0, 0),
					color = rgb(236, 210, 160),
				},
				{
					limbs = "Arm",
					shape = "Block",
					size = v(0.2, 0.12, 0.2),
					at = v(0, 0, 0),
					color = rgb(212, 172, 118),
				},
				{
					limbs = "Arm",
					shape = "Block",
					size = v(0.07, 0.07, 0.04),
					at = v(0.07, -0.2, 0),
					turn = v(0, 0, 45),
					color = rgb(212, 172, 118),
					fine = true,
				},
				-- long dark claws
				{
					limbs = "Hand",
					shape = "Block",
					size = v(0.022, 0.022),
					at = v(-0.045, 0, -0.03),
					to = v(-0.05, -0.08, -0.08),
					color = rgb(40, 35, 35),
				},
				{
					limbs = "Hand",
					shape = "Block",
					size = v(0.022, 0.022),
					at = v(0, 0, -0.03),
					to = v(0, -0.09, -0.08),
					color = rgb(40, 35, 35),
				},
				{
					limbs = "Hand",
					shape = "Block",
					size = v(0.022, 0.022),
					at = v(0.045, 0, -0.03),
					to = v(0.05, -0.08, -0.08),
					color = rgb(40, 35, 35),
				},
				-- red-brown shorts
				{
					anchor = "hips",
					shape = "Block",
					size = v(0.44, 0.11, 0.26),
					at = v(0, -0.025, 0),
					color = rgb(150, 62, 52),
				},
				{
					limbs = "Leg",
					shape = "Block",
					size = v(0.12, 0.08, 0.12),
					at = v(0, -0.04, 0),
					color = rgb(150, 62, 52),
				},
				-- thin bent legs: a furry thigh forward, a thin shin back, a hoof
				{
					limbs = "Leg",
					shape = "Block",
					size = v(0.11, 0.11),
					at = v(0, -0.04, 0),
					to = v(0, -0.17, -0.06),
					color = rgb(212, 172, 118),
				},
				{
					limbs = "Leg",
					shape = "Block",
					size = v(0.055, 0.055),
					at = v(0, -0.17, -0.06),
					to = v(0, -0.35, 0.03),
					color = rgb(196, 150, 100),
				},
				{
					limbs = "Leg",
					shape = "Block",
					size = v(0.08, 0.05, 0.1),
					at = v(0, -0.375, 0.01),
					color = rgb(60, 45, 35),
				},
				-- the pink hat with a white X
				{
					anchor = "head",
					shape = "Block",
					size = v(0.26, 0.11, 0.26),
					at = v(0, 0.15, 0),
					color = rgb(235, 120, 160),
				},
				{
					anchor = "head",
					shape = "Block",
					size = v(0.28, 0.025, 0.3),
					at = v(0, 0.1, -0.01),
					color = rgb(235, 120, 160),
				},
				{
					anchor = "head",
					shape = "Block",
					size = v(0.014, 0.09, 0.008),
					at = v(0, 0.15, -0.132),
					turn = v(0, 0, 45),
					color = WHITE,
				},
				{
					anchor = "head",
					shape = "Block",
					size = v(0.014, 0.09, 0.008),
					at = v(0, 0.15, -0.132),
					turn = v(0, 0, -45),
					color = WHITE,
				},
				-- branching antlers: a beam and three tines each side
				{
					anchor = "head",
					shape = "Block",
					size = v(0.03, 0.03),
					at = v(0.08, 0.13, 0),
					to = v(0.2, 0.36, 0.02),
					color = rgb(110, 75, 45),
					mirror = true,
				},
				{
					anchor = "head",
					shape = "Block",
					size = v(0.022, 0.022),
					at = v(0.15, 0.25, 0.01),
					to = v(0.28, 0.3, 0.01),
					color = rgb(110, 75, 45),
					mirror = true,
				},
				{
					anchor = "head",
					shape = "Block",
					size = v(0.022, 0.022),
					at = v(0.18, 0.31, 0.02),
					to = v(0.16, 0.44, 0.02),
					color = rgb(110, 75, 45),
					mirror = true,
				},
				{
					anchor = "head",
					shape = "Block",
					size = v(0.02, 0.02),
					at = v(0.2, 0.36, 0.02),
					to = v(0.31, 0.45, 0.03),
					color = rgb(110, 75, 45),
					mirror = true,
					fine = true,
				},
				-- a blue nose
				{
					anchor = "head",
					shape = "Block",
					size = v(0.055, 0.045, 0.03),
					at = v(0, -0.02, -0.125),
					color = rgb(60, 100, 220),
				},
			},
		},
	},

	-- The gold forms: the same gi; gold hair standing up, green eyes. Core III has taller, spikier
	-- hair and small sparks.
	ascending_core = {
		["Core II"] = with(core, {
			hair = { style = "spiky", color = GOLD_HAIR, lift = 0.75 },
		}),
		["Core III"] = with(core, {
			hair = { style = "tall", color = GOLD_HAIR, tip = rgb(255, 244, 175) },
			extras = {
				{
					anchor = "head",
					shape = "Block",
					size = v(0.012, 0.09, 0.012),
					at = v(0.16, 0.2, -0.05),
					turn = v(0, 0, 30),
					color = rgb(160, 230, 255),
					material = "Neon",
					plain = true,
				},
				{
					anchor = "head",
					shape = "Block",
					size = v(0.012, 0.08, 0.012),
					at = v(-0.17, 0.14, 0.04),
					turn = v(0, 0, -25),
					color = rgb(160, 230, 255),
					material = "Neon",
					plain = true,
				},
				{
					anchor = "hips",
					shape = "Block",
					size = v(0.012, 0.1, 0.012),
					at = v(0.26, 0.3, 0),
					turn = v(0, 0, 40),
					color = rgb(160, 230, 255),
					material = "Neon",
					plain = true,
					fine = true,
				},
			},
		}),
	},

	-- The giant form: a much larger, heavily muscled body (raised pecs, abs, obliques, traps,
	-- deltoids, biceps, quads, calves with dark lines between), long straggly black hair, pointed
	-- ears, glowing green eyes, a wide lipless grin showing all the teeth, a ragged brown loincloth.
	titanheart = {
		Titan = {
			proportions = {
				legLength = 0.38,
				legWidth = 0.17,
				legSpacing = 0.115,
				torsoHeight = 0.36,
				torsoWidth = 0.46,
				torsoDepth = 0.24,
				neck = 0.01,
				headSize = 0.23,
				armLength = 0.36,
				armWidth = 0.15,
			},
			skin = rgb(205, 140, 110),
			torso = rgb(205, 140, 110),
			sleeve = 0,
			pants = rgb(95, 65, 40), -- the loincloth
			shorts = 0.26,
			socks = rgb(205, 140, 110),
			shoes = rgb(205, 140, 110), -- bare feet
			shoe = 0.1,
			hair = {
				style = "long",
				color = INK,
				strands = { -- straggly strands over the face
					{ x = 0.3, length = 0.9, width = 0.08, z = -0.5 },
					{ x = -0.22, length = 0.8, width = 0.07, z = -0.52 },
				},
			},
			ears = "elf",
			face = { eyes = "open", eyeColor = rgb(80, 255, 90) },
			extras = {
				-- glowing eyes
				{
					anchor = "head",
					shape = "Block",
					size = v(0.035, 0.032, 0.006),
					at = v(0.05, 0.006, -0.118),
					color = rgb(80, 255, 90),
					material = "Neon",
					plain = true,
					mirror = true,
				},
				-- the lipless grin: gums and two full rows of teeth, lines up the cheeks
				{
					anchor = "head",
					shape = "Block",
					size = v(0.19, 0.014, 0.01),
					at = v(0, -0.03, -0.117),
					color = rgb(120, 45, 45),
				},
				{
					anchor = "head",
					shape = "Block",
					size = v(0.18, 0.03, 0.012),
					at = v(0, -0.045, -0.118),
					color = rgb(246, 244, 236),
					plain = true,
				},
				{
					anchor = "head",
					shape = "Block",
					size = v(0.17, 0.026, 0.012),
					at = v(0, -0.075, -0.118),
					color = rgb(246, 244, 236),
					plain = true,
				},
				{
					anchor = "head",
					shape = "Block",
					size = v(0.18, 0.012, 0.01),
					at = v(0, -0.092, -0.117),
					color = rgb(120, 45, 45),
				},
				{
					anchor = "head",
					shape = "Block",
					size = v(0.004, 0.06, 0.014),
					at = v(0.04, -0.06, -0.119),
					color = rgb(120, 45, 45),
					mirror = true,
					fine = true,
				},
				{
					anchor = "head",
					shape = "Block",
					size = v(0.004, 0.06, 0.014),
					at = v(0, -0.06, -0.119),
					color = rgb(120, 45, 45),
					fine = true,
				},
				{
					anchor = "head",
					shape = "Block",
					size = v(0.01, 0.006),
					at = v(0.095, -0.06, -0.117),
					to = v(0.07, 0.02, -0.117),
					color = rgb(160, 100, 78),
					mirror = true,
				},
				-- chest and belly
				{
					anchor = "hips",
					shape = "Block",
					size = v(0.2, 0.1, 0.03),
					at = v(0.105, 0.27, -0.125),
					color = rgb(222, 160, 128),
					mirror = true,
				},
				{
					anchor = "hips",
					shape = "Block",
					size = v(0.2, 0.01, 0.006),
					at = v(0.105, 0.218, -0.141),
					color = rgb(160, 100, 78),
					mirror = true,
					fine = true,
				},
				{
					anchor = "hips",
					shape = "Block",
					size = v(0.08, 0.05, 0.025),
					at = v(0.045, 0.17, -0.125),
					color = rgb(222, 160, 128),
					mirror = true,
				},
				{
					anchor = "hips",
					shape = "Block",
					size = v(0.08, 0.05, 0.025),
					at = v(0.045, 0.11, -0.125),
					color = rgb(222, 160, 128),
					mirror = true,
				},
				{
					anchor = "hips",
					shape = "Block",
					size = v(0.08, 0.05, 0.025),
					at = v(0.045, 0.05, -0.125),
					color = rgb(222, 160, 128),
					mirror = true,
				},
				{
					anchor = "hips",
					shape = "Block",
					size = v(0.03, 0.16, 0.18),
					at = v(0.235, 0.12, -0.02),
					color = rgb(222, 160, 128),
					mirror = true,
				},
				{
					anchor = "hips",
					shape = "Block",
					size = v(0.12, 0.05, 0.14),
					at = v(0.13, 0.37, 0.02),
					color = rgb(222, 160, 128),
					mirror = true,
				},
				-- arms and legs
				{
					limbs = "Arm",
					shape = "Ball",
					size = v(0.19, 0.19, 0.19),
					at = v(0, -0.03, 0),
					color = rgb(222, 160, 128),
				},
				{
					limbs = "Arm",
					shape = "Block",
					size = v(0.12, 0.12, 0.04),
					at = v(0, -0.13, -0.07),
					color = rgb(222, 160, 128),
				},
				{
					limbs = "Arm",
					shape = "Block",
					size = v(0.155, 0.01, 0.155),
					at = v(0, -0.22, 0),
					color = rgb(160, 100, 78),
				},
				{
					limbs = "Leg",
					shape = "Block",
					size = v(0.15, 0.15, 0.03),
					at = v(0, -0.11, -0.09),
					color = rgb(222, 160, 128),
				},
				{
					limbs = "Leg",
					shape = "Block",
					size = v(0.175, 0.01, 0.175),
					at = v(0, -0.21, 0),
					color = rgb(160, 100, 78),
					fine = true,
				},
				{
					limbs = "Leg",
					shape = "Block",
					size = v(0.12, 0.1, 0.04),
					at = v(0, -0.28, 0.08),
					color = rgb(222, 160, 128),
				},
				-- a ragged loincloth: front and back flaps with torn points
				{
					anchor = "hips",
					shape = "Block",
					size = v(0.22, 0.13, 0.02),
					at = v(0, -0.05, -0.125),
					color = rgb(95, 65, 40),
				},
				{
					anchor = "hips",
					shape = "Block",
					size = v(0.24, 0.12, 0.02),
					at = v(0, -0.04, 0.125),
					color = rgb(95, 65, 40),
				},
				{
					anchor = "hips",
					shape = "Block",
					size = v(0.05, 0.05, 0.02),
					at = v(0.07, -0.115, -0.125),
					turn = v(0, 0, 45),
					color = rgb(95, 65, 40),
					mirror = true,
				},
				{
					anchor = "hips",
					shape = "Block",
					size = v(0.05, 0.05, 0.02),
					at = v(0, -0.12, -0.125),
					turn = v(0, 0, 45),
					color = rgb(95, 65, 40),
				},
			},
		},
	},
})
