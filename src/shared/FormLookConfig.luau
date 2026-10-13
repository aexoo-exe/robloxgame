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

-- ascending_core: the gold forms keep the gi; the hair, eyes and aura step up.
local GI_ORANGE = rgb(240, 125, 35)
local GI_BLUE = rgb(35, 55, 150)
local GOLD_HAIR = rgb(250, 214, 80)
local AURA = rgb(255, 225, 90)
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
-- A see-through glowing shell around the whole figure.
local function aura(transparency: number)
	return {
		anchor = "hips",
		shape = "Ball",
		size = v(0.95, 0.95, 0.95),
		at = v(0, 0.1, 0),
		color = AURA,
		material = "Neon",
		transparency = transparency,
		plain = true,
	}
end

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

	-- The monster form: a big, hulking body with a shaggy tan mane over the shoulders and chest,
	-- dark claws, big branching antlers, the pink hat with a white X, a blue nose and red-brown shorts.
	field_medic = {
		Bruiser = {
			scale = 1.25,
			bulk = 1.35,
			skin = rgb(196, 150, 100),
			torso = rgb(212, 172, 118),
			sleeves = rgb(212, 172, 118),
			sleeve = 0.35,
			pants = rgb(150, 62, 52),
			shorts = 0.4,
			shoes = rgb(60, 45, 35), -- hooves
			shoe = 0.12,
			face = { eyes = "open", eyeColor = rgb(30, 30, 30), mouth = true },
			collar = rgb(212, 172, 118),
			extras = {
				-- the mane over the shoulders and chest, with shaggy points
				{
					anchor = "hips",
					shape = "Block",
					size = v(0.5, 0.18, 0.26),
					at = v(0, 0.29, 0),
					color = rgb(212, 172, 118),
				},
				{
					anchor = "hips",
					shape = "Block",
					size = v(0.07, 0.07, 0.03),
					at = v(-0.12, 0.18, -0.11),
					turn = v(0, 0, 45),
					color = rgb(212, 172, 118),
				},
				{
					anchor = "hips",
					shape = "Block",
					size = v(0.07, 0.07, 0.03),
					at = v(0, 0.17, -0.11),
					turn = v(0, 0, 45),
					color = rgb(212, 172, 118),
				},
				{
					anchor = "hips",
					shape = "Block",
					size = v(0.07, 0.07, 0.03),
					at = v(0.12, 0.18, -0.11),
					turn = v(0, 0, 45),
					color = rgb(212, 172, 118),
				},
				-- the pink hat with a white X
				{
					anchor = "head",
					shape = "Block",
					size = v(0.23, 0.1, 0.23),
					at = v(0, 0.13, 0),
					color = rgb(235, 120, 160),
				},
				{
					anchor = "head",
					shape = "Block",
					size = v(0.25, 0.025, 0.27),
					at = v(0, 0.085, -0.01),
					color = rgb(235, 120, 160),
				},
				{
					anchor = "head",
					shape = "Block",
					size = v(0.012, 0.08, 0.008),
					at = v(0, 0.13, -0.117),
					turn = v(0, 0, 45),
					color = WHITE,
				},
				{
					anchor = "head",
					shape = "Block",
					size = v(0.012, 0.08, 0.008),
					at = v(0, 0.13, -0.117),
					turn = v(0, 0, -45),
					color = WHITE,
				},
				-- antlers: a beam and two tines each side
				{
					anchor = "head",
					shape = "Block",
					size = v(0.025, 0.2, 0.025),
					at = v(-0.12, 0.25, 0),
					turn = v(0, 0, 35),
					color = rgb(110, 75, 45),
				},
				{
					anchor = "head",
					shape = "Block",
					size = v(0.025, 0.2, 0.025),
					at = v(0.12, 0.25, 0),
					turn = v(0, 0, -35),
					color = rgb(110, 75, 45),
				},
				{
					anchor = "head",
					shape = "Block",
					size = v(0.02, 0.1, 0.02),
					at = v(-0.2, 0.3, 0),
					turn = v(0, 0, 75),
					color = rgb(110, 75, 45),
				},
				{
					anchor = "head",
					shape = "Block",
					size = v(0.02, 0.1, 0.02),
					at = v(0.2, 0.3, 0),
					turn = v(0, 0, -75),
					color = rgb(110, 75, 45),
				},
				{
					anchor = "head",
					shape = "Block",
					size = v(0.02, 0.1, 0.02),
					at = v(-0.15, 0.36, 0),
					turn = v(0, 0, 10),
					color = rgb(110, 75, 45),
					fine = true,
				},
				{
					anchor = "head",
					shape = "Block",
					size = v(0.02, 0.1, 0.02),
					at = v(0.15, 0.36, 0),
					turn = v(0, 0, -10),
					color = rgb(110, 75, 45),
					fine = true,
				},
				-- a blue nose
				{
					anchor = "head",
					shape = "Block",
					size = v(0.05, 0.04, 0.03),
					at = v(0, -0.02, -0.11),
					color = rgb(60, 100, 220),
				},
				-- dark claws
				{
					anchor = "leftHand",
					shape = "Block",
					size = v(0.02, 0.07, 0.02),
					at = v(-0.03, -0.03, -0.04),
					color = rgb(40, 35, 35),
				},
				{
					anchor = "leftHand",
					shape = "Block",
					size = v(0.02, 0.07, 0.02),
					at = v(0.03, -0.03, -0.04),
					color = rgb(40, 35, 35),
				},
				{
					anchor = "rightHand",
					shape = "Block",
					size = v(0.02, 0.07, 0.02),
					at = v(-0.03, -0.03, -0.04),
					color = rgb(40, 35, 35),
				},
				{
					anchor = "rightHand",
					shape = "Block",
					size = v(0.02, 0.07, 0.02),
					at = v(0.03, -0.03, -0.04),
					color = rgb(40, 35, 35),
				},
			},
		},
	},

	-- The gold forms: the same gi; gold hair standing up, green eyes and a glow. Core III has taller,
	-- spikier hair, a stronger glow and small sparks.
	ascending_core = {
		["Core II"] = with(core, {
			hair = { style = "spiky", color = GOLD_HAIR, lift = 0.75 },
			extras = { aura(0.86) },
		}),
		["Core III"] = with(core, {
			hair = { style = "tall", color = GOLD_HAIR, tip = rgb(255, 244, 175) },
			extras = {
				aura(0.78),
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

	-- The giant form: a much larger, very muscular body with muscle lines, long straggly black hair,
	-- pointed ears, glowing green eyes, a wide grin of teeth and a ragged brown loincloth.
	titanheart = {
		Titan = {
			bulk = 1.35,
			skin = rgb(205, 140, 110),
			torso = rgb(205, 140, 110),
			sleeve = 0,
			pants = rgb(95, 65, 40), -- the loincloth
			shorts = 0.28,
			socks = rgb(205, 140, 110),
			shoes = rgb(205, 140, 110), -- bare feet
			shoe = 0.1,
			hair = { style = "long", color = INK },
			ears = "elf",
			face = { eyes = "open", eyeColor = rgb(80, 255, 90), mask = { color = rgb(120, 60, 55), teeth = WHITE } },
			bands = { -- muscle lines
				{ limb = "arms", from = 0.3, to = 0.33, color = rgb(168, 108, 84) },
				{ limb = "arms", from = 0.55, to = 0.58, color = rgb(168, 108, 84) },
				{ limb = "legs", from = 0.45, to = 0.48, color = rgb(168, 108, 84) },
			},
			extras = {
				{
					anchor = "hips",
					shape = "Block",
					size = v(0.012, 0.24, 0.006),
					at = v(0, 0.16, -0.092),
					color = rgb(168, 108, 84),
				},
				{
					anchor = "hips",
					shape = "Block",
					size = v(0.28, 0.012, 0.006),
					at = v(0, 0.24, -0.092),
					color = rgb(168, 108, 84),
				},
				{
					anchor = "hips",
					shape = "Block",
					size = v(0.14, 0.01, 0.006),
					at = v(0, 0.15, -0.092),
					color = rgb(168, 108, 84),
					fine = true,
				},
				{
					anchor = "hips",
					shape = "Block",
					size = v(0.14, 0.01, 0.006),
					at = v(0, 0.08, -0.092),
					color = rgb(168, 108, 84),
					fine = true,
				},
				-- ragged loincloth flaps
				{
					anchor = "hips",
					shape = "Block",
					size = v(0.22, 0.13, 0.02),
					at = v(0, -0.04, -0.1),
					color = rgb(95, 65, 40),
				},
				{
					anchor = "hips",
					shape = "Block",
					size = v(0.24, 0.12, 0.02),
					at = v(0, -0.04, 0.1),
					color = rgb(95, 65, 40),
				},
				-- glowing eyes
				{
					anchor = "head",
					shape = "Block",
					size = v(0.032, 0.03, 0.006),
					at = v(-0.044, 0.004, -0.103),
					color = rgb(80, 255, 90),
					material = "Neon",
					plain = true,
				},
				{
					anchor = "head",
					shape = "Block",
					size = v(0.032, 0.03, 0.006),
					at = v(0.044, 0.004, -0.103),
					color = rgb(80, 255, 90),
					material = "Neon",
					plain = true,
				},
			},
		},
	},
})
