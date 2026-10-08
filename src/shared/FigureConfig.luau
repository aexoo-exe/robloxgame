-- Placeholder character figures (client visuals only; see src/client/Figure.luau). Every unit is a
-- simple humanoid built from parts: head with a dark visor marking its front, torso, two arms, two
-- legs, a class prop, and for roster units a ring in the cost's color under its feet.
--
-- Sizes and positions are fractions of the figure's height, so they scale with star level, summons
-- and the PvE size multipliers. Angles are in degrees.
-- A character can use a finished model instead of its placeholder: see `model` in SkinConfig.
-- Class names match UnitConfig `classes`; a unit with two classes uses its first.

local function part(shape: string, size: Vector3, at: Vector3, turn: Vector3?, color: Color3, material: string?)
	return table.freeze({
		shape = shape, -- "Block", "Ball" or "Cylinder" (a cylinder's length is its X size)
		size = size,
		at = at, -- position in the hand's space: -Y runs down the arm, -Z is the figure's front
		turn = turn or Vector3.zero,
		color = color,
		material = material or "SmoothPlastic",
	})
end

local STEEL = Color3.fromRGB(205, 210, 220)
local DARK_STEEL = Color3.fromRGB(120, 125, 140)
local GOLD = Color3.fromRGB(225, 180, 60)
local WOOD = Color3.fromRGB(110, 75, 45)

return table.freeze({
	-- Roster body proportions (fractions of height). Legs + torso + neck + head fill 0.96.
	body = table.freeze({
		legLength = 0.40,
		legWidth = 0.13,
		legSpacing = 0.085, -- from the center line to each leg
		torsoHeight = 0.34,
		torsoWidth = 0.34,
		torsoDepth = 0.18,
		neck = 0.02,
		headSize = 0.20,
		armLength = 0.33,
		armWidth = 0.11,
	}),

	-- Creeps and bosses: stockier and hunched, with no prop or cost ring, so they never read as roster
	-- units. Values override `body`. Bosses also get horns and glowing eyes.
	pveBody = table.freeze({
		legLength = 0.30,
		legWidth = 0.15,
		legSpacing = 0.11,
		torsoHeight = 0.40,
		torsoWidth = 0.46,
		torsoDepth = 0.30,
		neck = 0,
		headSize = 0.22,
		armLength = 0.40,
		armWidth = 0.14,
	}),
	pveLean = 18, -- hunched forward
	bossHorn = table.freeze({ size = Vector3.new(0.06, 0.16, 0.06), color = Color3.fromRGB(235, 225, 200) }),
	bossEyeColor = Color3.fromRGB(255, 70, 50),

	visorColor = Color3.fromRGB(30, 30, 40),
	-- Cost ring: a flat disc under roster units, in RenderConfig.costColors.
	ring = table.freeze({ diameter = 0.62, thickness = 0.05, material = "Neon" }),

	-- One prop or shape per class. `hand` is the arm it rides on ("left", "right" or "both": the same
	-- parts on each hand), and `arms` the resting arm angles (raised forward) as { left, right }.
	classes = table.freeze({
		Blade = table.freeze({ -- a sword
			hand = "right",
			arms = table.freeze({ 10, 30 }),
			parts = table.freeze({
				part("Block", Vector3.new(0.035, 0.05, 0.50), Vector3.new(0, 0, -0.28), nil, STEEL, "Metal"),
				part("Block", Vector3.new(0.16, 0.035, 0.035), Vector3.new(0, 0, -0.03), nil, GOLD),
			}),
		}),
		Assassin = table.freeze({ -- a dagger in each hand
			hand = "both",
			arms = table.freeze({ 25, 25 }),
			parts = table.freeze({
				part("Block", Vector3.new(0.03, 0.035, 0.20), Vector3.new(0, 0, -0.11), nil, DARK_STEEL, "Metal"),
			}),
		}),
		Marksman = table.freeze({ -- a long rifle, held level
			hand = "right",
			arms = table.freeze({ 60, 75 }),
			parts = table.freeze({
				part(
					"Block",
					Vector3.new(0.04, 0.04, 0.50),
					Vector3.new(0, 0, -0.20),
					Vector3.new(-75, 0, 0),
					DARK_STEEL,
					"Metal"
				),
				part("Block", Vector3.new(0.06, 0.10, 0.15), Vector3.new(0, 0, 0.06), Vector3.new(-75, 0, 0), WOOD),
			}),
		}),
		Brawler = table.freeze({ -- big fists
			hand = "both",
			arms = table.freeze({ 35, 35 }),
			parts = table.freeze({
				part(
					"Block",
					Vector3.new(0.17, 0.17, 0.17),
					Vector3.new(0, -0.02, 0),
					nil,
					Color3.fromRGB(200, 60, 50)
				),
			}),
		}),
		Caster = table.freeze({ -- a staff topped with a glowing orb
			hand = "right",
			arms = table.freeze({ 0, 15 }),
			parts = table.freeze({
				part("Cylinder", Vector3.new(0.85, 0.045, 0.045), Vector3.new(0, 0.12, 0), Vector3.new(0, 0, 90), WOOD),
				part(
					"Ball",
					Vector3.new(0.13, 0.13, 0.13),
					Vector3.new(0, 0.56, 0),
					nil,
					Color3.fromRGB(150, 120, 255),
					"Neon"
				),
			}),
		}),
		Guardian = table.freeze({ -- a shield on the left arm
			hand = "left",
			arms = table.freeze({ 35, 5 }),
			parts = table.freeze({
				part(
					"Block",
					Vector3.new(0.30, 0.38, 0.05),
					Vector3.new(0, 0.10, -0.08),
					Vector3.new(-35, 0, 0),
					STEEL,
					"Metal"
				),
				part("Block", Vector3.new(0.10, 0.10, 0.05), Vector3.new(0, 0.10, -0.12), Vector3.new(-35, 0, 0), GOLD),
			}),
		}),
		Support = table.freeze({ -- a glowing orb held out in the left hand
			hand = "left",
			arms = table.freeze({ 55, 5 }),
			parts = table.freeze({
				part(
					"Ball",
					Vector3.new(0.16, 0.16, 0.16),
					Vector3.new(0, -0.06, -0.06),
					nil,
					Color3.fromRGB(255, 225, 130),
					"Neon"
				),
			}),
		}),
	}),

	-- Placeholder horse under a mounted rider (RenderConfig.formLooks `mount` gives its color). It
	-- faces the rider's front (-Z); the rider sits on its back with legs astride.
	horse = table.freeze({
		backHeight = 0.42, -- top of the body, where the rider sits
		bodyLength = 0.78,
		bodyWidth = 0.26,
		bodyHeight = 0.20,
		legWidth = 0.075,
		legInset = 0.06, -- from the body's ends to the legs
		neckLength = 0.30,
		neckWidth = 0.11,
		neckAngle = 35, -- forward tilt from upright
		headLength = 0.24,
		headSize = 0.11,
		tailLength = 0.26,
		tailWidth = 0.05,
		tailAngle = 35, -- down from level
		accentColor = Color3.fromRGB(55, 38, 25), -- tail
		riderLegs = 70, -- rider's legs, raised forward
		riderLegSplay = 22, -- and spread to straddle the body
	}),

	-- Animations. Durations are in seconds; none of them change fight timing.
	animation = table.freeze({
		idlePeriod = 2.4,
		idleBob = 0.012, -- fraction of height
		idleArmSway = 4,
		walkCycle = 0.55, -- seconds per stride (two steps)
		walkLegSwing = 32,
		walkArmSwing = 26,
		walkBob = 0.02,
		attackArm = 95, -- extra raise of the attacking arm at the peak of a melee lunge
		attackLean = 14,
		shootDuration = 0.3, -- ranged attack recoil
		shootArm = 25,
		shootLean = -8,
		castDuration = 0.5,
		castArms = 150, -- both arms thrown up
		hitDuration = 0.2,
		hitLean = -16, -- knocked back
		defeatFall = 80, -- falls backward as it fades
		horseLegSwing = 30,
	}),
})
