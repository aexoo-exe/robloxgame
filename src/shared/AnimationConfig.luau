-- Combat animation and effects (client visuals only): how units move when they attack, get hit,
-- cast, get stunned, die and win, and the effects around them (sparks, bursts, rings, puffs,
-- projectile trails, camera shake, hit-stop, floating number pops). Used by src/client/UnitMotion
-- (poses), UnitView (per-unit state), ImpactEffects (pooled effects) and CombatFx (what each
-- playback event shows). Nothing here changes fight timing or results: every moment comes from the
-- server's event list (CombatPlayback).
--
-- Units: durations in seconds of fight time (they follow the playback speed), angles in degrees,
-- distances in studs for a 1-star unit of normal size (scaled with the unit's height), particle
-- sizes in studs. Colors are Color3.

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

return deepFreeze({
	-- Quality ------------------------------------------------------------------------------------
	-- "low", "medium", "high" or "auto" (touch-only devices: `autoTouch`; others: `autoDefault`).
	-- ImpactEffects.setQuality changes it at run time (the dev preview's Q key).
	quality = "auto",
	autoTouch = "medium",
	autoDefault = "high",
	-- Per level: `particles` multiplies every particle count; `maxParticles` caps the particles
	-- alive at once (new bursts shrink to fit); `rings` turns ground rings and flash balls on;
	-- `trails` turns projectile trails on; `charge` turns the cast charge sparkles on.
	qualityLevels = {
		low = { particles = 0.35, maxParticles = 120, rings = false, trails = false, charge = false },
		medium = { particles = 0.65, maxParticles = 260, rings = true, trails = true, charge = false },
		high = { particles = 1, maxParticles = 520, rings = true, trails = true, charge = true },
	},
	cameraShake = true, -- false: no camera shake at all

	-- Effect pools: how many of each pooled effect exist at most. A burst that finds its pool busy
	-- reuses the oldest one.
	pools = {
		emitters = 8, -- particle hosts per particle kind (sparks, puffs, motes)
		rings = 14, -- flat ground rings
		balls = 14, -- flash balls
		-- ability effect parts: beams, waves, sweeps, ground marks, ghosts (AbilityFx) and ultimates
		-- (made only as needed; scripts/audit-units caps each ultimate's peak by tier)
		shapes = 120,
	},

	-- Effects grow with the unit's star level (1, 2, 3): sizes and particle counts.
	starScale = { 1, 1.2, 1.45 },

	-- Faction colors, by origin (UnitConfig `origin`): cast glows, charge, release bursts and the
	-- touch on every ability target. `creep`, `boss` and `summon` are for units without an origin.
	factionColors = {
		Hunters = rgb(120, 230, 140),
		Corps = rgb(110, 200, 255),
		Spirit = rgb(255, 225, 120),
		Cursed = rgb(200, 70, 255),
		Arcane = rgb(140, 120, 255),
		Titans = rgb(255, 150, 80),
		Shinobi = rgb(255, 90, 90),
		Crew = rgb(255, 200, 60),
		Heroes = rgb(90, 255, 220),
		creep = rgb(200, 200, 210),
		boss = rgb(255, 80, 60),
		summon = rgb(210, 220, 255),
	},

	-- Attack motion ------------------------------------------------------------------------------
	-- Every attack is one motion in four parts: anticipation (wind-up), a fast strike, the
	-- follow-through and the recovery. `timing` gives where each part ends, as fractions of the
	-- motion: the strike lands (melee) or the shot leaves (ranged) at `strike`. Each channel lists its
	-- value at the end of the wind-up, at the strike, and at the end of the follow-through
	-- ({ windup, strike, follow }); it starts and ends at rest.
	--   arm      the attacking arm, degrees raised forward on top of its rest angle
	--   offArm   the other arm (`bothArms`: it copies `arm`)
	--   lean     forward lean in degrees (negative leans back)
	--   twist    body turn in degrees; positive brings the attacking shoulder forward
	--   crouch   how far the hips drop, as a fraction of leg length (a squash)
	--   lunge    studs toward the target (negative: back, as a recoil)
	--   armOut   the attacking arm raised out to its side, degrees (negative: across the body).
	--            With `arm` this bends the swing into an arc: a slash comes from high outside and
	--            carries across, instead of chopping straight down.
	--   offArmOut  the same for the other arm (`bothArms`: it copies `armOut`)
	--   weight   optional: replaces `overlap.weight` (below) for this style
	-- `duration` is the motion's length when the unit attacks slowly. A faster attacker's motion is
	-- shortened to `maxIntervalShare` of the time to its next attack (never below `minDuration`), so
	-- the timing fits each unit's actual attack interval. `alternate`: attacks switch arms.
	-- `projectile`: ranged styles, the look of the shot (`projectiles` below).
	maxIntervalShare = 0.8,
	minDuration = 0.14,
	styles = {
		-- Swords, daggers: raise, slash down and across, carry through.
		blade = {
			duration = 0.42,
			timing = { windup = 0.36, strike = 0.5, follow = 0.72 },
			arm = { 140, 50, -20 },
			offArm = { 25, -10, -20 },
			lean = { -6, 16, 10 },
			twist = { -28, 18, 30 },
			crouch = { 0.06, 0.14, 0.1 },
			lunge = { -0.15, 1.0, 0.85 },
			armOut = { 38, 6, -28 }, -- high and outside, through the front, across the body
			offArmOut = { 10, -4, 6 },
		},
		-- Fists: pull back, straight punch, the other fist up as a guard.
		brawler = {
			duration = 0.34,
			timing = { windup = 0.3, strike = 0.42, follow = 0.62 },
			arm = { -25, 85, 75 },
			offArm = { 55, 35, 45 },
			lean = { -4, 18, 12 },
			twist = { -30, 28, 18 },
			crouch = { 0.1, 0.04, 0.06 },
			lunge = { -0.2, 1.1, 0.95 },
			armOut = { 22, 6, -4 }, -- drawn back from the side, a slight hook into the punch
			offArmOut = { 6, 10, 8 },
			alternate = true,
		},
		-- Guardians and giants: both arms high, a heavy two-handed slam, a dust ring on landing.
		heavy = {
			duration = 0.6,
			timing = { windup = 0.46, strike = 0.58, follow = 0.78 },
			arm = { 165, 70, 40 },
			bothArms = true,
			lean = { -12, 24, 18 },
			twist = { 0, 0, 0 },
			crouch = { 0.04, 0.24, 0.2 },
			lunge = { -0.25, 0.8, 0.7 },
			armOut = { 18, -2, 8 }, -- arms wide overhead, close at the slam, spread on the follow
			slam = true,
		},
		-- Rifles, bows, throws: raise to aim, fire, kick back.
		ranged = {
			duration = 0.5,
			timing = { windup = 0.44, strike = 0.5, follow = 0.66 },
			arm = { 75, 95, 80 },
			offArm = { 60, 70, 60 },
			lean = { 2, -10, -4 },
			twist = { -10, 4, 0 },
			crouch = { 0.06, 0.08, 0.04 },
			lunge = { 0, -0.25, -0.15 },
			projectile = "shot",
		},
		-- Pointing shooters (FigureConfig.characters attackPose "point"): the arm snaps to point.
		point = {
			duration = 0.45,
			timing = { windup = 0.3, strike = 0.38, follow = 0.7 },
			arm = { 78, 88, 86 },
			offArm = { 0, -10, -5 },
			lean = { 0, -6, -3 },
			twist = { -6, 10, 8 },
			crouch = { 0.03, 0.05, 0.03 },
			lunge = { 0, -0.12, -0.08 },
			projectile = "shot",
		},
		-- Ranged blades: the blade swing (raise, slash down and across) with a small step in, and a
		-- slash wave leaves the blade at the strike.
		slashWave = {
			duration = 0.46,
			timing = { windup = 0.38, strike = 0.5, follow = 0.72 },
			arm = { 145, 45, -25 },
			offArm = { 25, -10, -20 },
			lean = { -8, 18, 12 },
			twist = { -32, 22, 32 },
			crouch = { 0.06, 0.14, 0.1 },
			lunge = { -0.15, 0.35, 0.25 },
			armOut = { 40, 6, -30 },
			offArmOut = { 10, -4, 6 },
			projectile = "wave",
		},
		-- Casters' basic attacks: draw in, push both hands out, a glowing orb leaves.
		caster = {
			duration = 0.5,
			timing = { windup = 0.42, strike = 0.52, follow = 0.7 },
			arm = { 30, 100, 85 },
			offArm = { 20, 80, 60 },
			lean = { -6, 10, 6 },
			twist = { -12, 10, 6 },
			crouch = { 0.08, 0.02, 0.03 },
			lunge = { -0.1, 0.15, 0.1 },
			armOut = { 28, 8, 14 }, -- hands gather wide, push out together, open up
			offArmOut = { 28, 8, 14 },
			projectile = "orb",
		},
	},
	-- Which style a unit attacks with. In order: `formStyles` (by the unit's current form name; form
	-- names are unique), `unitStyles` (by unit id), then for melee units
	-- (range 1) a held weapon's kind (`weaponStyles`), then its first class (`meleeClasses` or
	-- `rangedClasses`), then `defaultMelee` / `defaultRanged`. Bosses fight `heavy` in melee;
	-- attack pose "point" units use `point`. Range comes from the unit's current form.
	formStyles = {
		Chainsaw = "blade", -- ripcord_frenzy's chainsaw form: arm-blade swings, not punches
	},
	unitStyles = {
		ascending_core = "caster", -- energy blasts from both hands, not a rifle aim
		snapfire = "point", -- a finger snap toward the target, not a two-handed push
		horizon_cut = "slashWave", -- swings his greatsword and throws a slash wave, not a rifle aim
	},
	weaponStyles = {
		greatsword = "heavy",
		katana = "blade",
		dagger = "blade",
		thinBlade = "blade",
		gauntlet = "brawler",
	},
	meleeClasses = {
		Blade = "blade",
		Assassin = "blade",
		Brawler = "brawler",
		Guardian = "heavy",
		Support = "brawler",
		Caster = "brawler",
		Marksman = "brawler",
	},
	rangedClasses = { Caster = "caster", Support = "caster", Marksman = "ranged" },
	defaultMelee = "brawler",
	defaultRanged = "ranged",

	-- Projectiles: a ball with a trail that lands as the hit lands. Ranged attacks launch at their
	-- strike and fly `flightTime`. `size` is the ball's diameter, `arc` its peak height, `trail` the
	-- trail's lifetime and `trailWidth` its width (fractions of `size`).
	projectiles = {
		flightTime = 0.25,
		ownColor = rgb(150, 200, 255),
		enemyColor = rgb(255, 160, 140),
		shot = { size = 0.32, arc = 0.5, trail = 0.12, trailWidth = 0.9 },
		orb = { size = 0.55, arc = 1.2, trail = 0.2, trailWidth = 1.2 },
		tongue = { size = 0.6 }, -- RenderConfig.tongueAttacks: a stretching bar, no trail
		bounce = { size = 0.45, arc = 1.0, trail = 0.15, trailWidth = 1 },
		-- A slash wave: a flat blade of light `width` times `size` across, flying straight, with a
		-- ribbon trail as wide as it is.
		wave = { size = 0.5, width = 3.2, arc = 0, trail = 0.1, flat = true },
	},

	-- Overlapping action, weight and settle (every motion above) -------------------------------------
	-- Rigid limbs cannot bend, so motion reads as alive through timing: body parts start and settle
	-- at different moments, strikes snap, and everything overshoots a little before it settles.
	-- None of this moves a strike: the attacking arm stays on the style's timing, so hits land and
	-- shots leave exactly when they did.
	overlap = {
		-- Shares of the attack motion (0-1). The body (lean, twist, crouch, lunge, hip shift) runs
		-- `bodyLead` ahead of the attacking arm: the hips start the swing. The off arm trails by
		-- `offArmLag`, the head by `headLag` (it catches up after the body moves). All three ease to
		-- zero at the start and end of the motion, so nothing pops.
		bodyLead = 0.06,
		offArmLag = 0.07,
		headLag = 0.1,
		-- The head turns against the body's twist by this share, so the eyes stay on the target.
		headCounter = 0.55,
		-- Wind-up to strike: values accelerate as t ^ `snapPower` (2 was a plain ease-in; higher snaps
		-- harder out of the anticipation).
		snapPower = 3.2,
		-- Recovery after the follow-through: back to rest by `settleAt` of the recovery, then past it
		-- by `settle` of the follow-through value and back (a small overshoot that settles). Also used
		-- by cast releases, the signature punch and the end of ultimate poses.
		settle = 0.18,
		settleAt = 0.62,
		ultimateSettle = 0.28, -- seconds over which an ultimate pose settles out (was a 0.2 s blend)
		-- Weight on strikes: the hips shift sideways onto the planted leg (the one opposite the
		-- attacking arm) by `strikeShift` of the figure's height and drop with the style's crouch;
		-- the legs split by `strikeStance` degrees (front leg forward, back leg back by
		-- `backLegShare` of it). `weight` is the shape over the motion: { windup, strike, follow }
		-- (negative: weight rocks back onto the rear leg in the anticipation).
		strikeShift = 0.035,
		strikeStance = 12,
		backLegShare = 0.6,
		weight = { -0.35, 1, 0.75 },
		-- The upper body rolls toward the planted leg, degrees per unit of weight.
		strikeRoll = 4,
	},

	-- Living motion: idle, walking, landings (client visuals only) --------------------------------
	-- On top of the base idle and walk cycles in FigureConfig.animation (idlePeriod, idleBob,
	-- walkCycle, walkLegSwing, walkArmSwing, walkBob). Every unit gets its own phase and a rate
	-- between `rateSpread` below and above 1, so no two units move in step.
	living = {
		rateSpread = 0.12,
		-- How fast the idle layers fade out while a unit acts (attacks, casts, ultimates, hits,
		-- stuns, walking) and back in after: 1 / seconds.
		calmRate = 5,
		-- Breathing: one breath every `breathPeriod` seconds; the chest lifts (lean back, degrees),
		-- the arms float out a little (degrees) and the head nods against it.
		breathPeriod = 3.4,
		breathLean = 1.4,
		breathArms = 2.5,
		breathHead = 1.2,
		-- Weight shifts: every `shiftEvery` seconds (varied per unit) the weight moves to the other
		-- leg over `shiftBlend` of that time. The hips move `shift` of the height sideways, the upper
		-- body rolls back over them by `shiftRoll` degrees, the head tips by `shiftHead`.
		shiftEvery = 4.2,
		shiftBlend = 0.22,
		shift = 0.018,
		shiftRoll = 2.2,
		shiftHead = 2,
		-- Looking: with a target, the head turns toward it ahead of the body (up to `lookMax`
		-- degrees, `lookLead` of the remaining turn), so turns start at the eyes. Without one, every
		-- `glanceEvery` seconds (varied per unit) the head glances up to `glanceYaw` degrees aside
		-- for `glanceHold` of that time.
		lookMax = 50,
		lookLead = 0.6,
		glanceEvery = 5.5,
		glanceHold = 0.3,
		glanceYaw = 28,
		glancePitch = 6,
		-- Walking: heel-to-toe bob (lowest at each heel strike, highest as the legs pass, with a
		-- quick `heelDip` of the height just after contact), arms counter-swinging `armLag` radians
		-- behind the legs, the shoulders counter-twisting `twist` degrees, the hips swaying over the
		-- stance leg (`shift` of the height, `roll` degrees), and the body leaning `lean` degrees into
		-- the direction at `leanSpeed` studs per second (more when faster, up to `maxLean`); a dash
		-- leans `dashLean`. The head keeps `headSteady` of the lean off (eyes level).
		walk = {
			heelDip = 0.008,
			armLag = 0.35,
			twist = 7,
			shift = 0.012,
			roll = 2,
			lean = 6,
			leanSpeed = 8,
			maxLean = 12,
			dashLean = 14,
			headSteady = 0.6,
		},
		-- Landing at the end of a walk or dash: the hips drop `depth` (crouch fraction; a dash
		-- `dashDepth`) by `dropAt` of `duration` and shift `shift` of the height onto one leg
		-- (alternating), then rise back past rest by `lift` of the height and settle. The head nods
		-- `headNod` degrees, a beat after the body.
		land = {
			duration = 0.34,
			dropAt = 0.3,
			depth = 0.07,
			dashDepth = 0.16,
			shift = 0.02,
			lift = 0.008,
			headNod = 7,
		},
	},

	-- Secondary motion: loose parts (hair, capes and back accessories, scarves, coat tails, horse
	-- manes and tails) swing on a cheap spring each, about the point they hang from. They lag when
	-- the body moves, hang toward the ground when it leans, and settle. Which parts are loose:
	-- hand-built looks mark long hair (back, long sides, strands, hanging panels), coat tails and
	-- the scarf's hanging end (LookKit); catalog avatars their accessories held on by the hair,
	-- back, waist-back and neck attachments; horses their mane and tail. Per group:
	--   frequency  springiness in swings per second (higher: stiffer)
	--   damping    1 = settles without bouncing; lower bounces more
	--   drag       radians of swing per (figure heights per second) of movement: trails behind motion
	--   hang       0-1: how much the part keeps hanging straight down when the body tilts
	--   back, front  the most it swings away from the body / toward it, degrees (hair and capes hang
	--              behind: `front` stops them swinging into the head or back)
	--   side       the most it swings sideways, degrees
	secondary = {
		maxPerFigure = 6, -- loose sets per figure that swing; any more stay rigid
		teleport = 0.6, -- a jump of more than this many heights in one frame (a drag, a redraw) resets
		maxStep = 1 / 60, -- seconds per integration step (at most 4 steps a frame)
		groups = {
			hair = { frequency = 2.6, damping = 0.45, drag = 0.25, hang = 0.5, back = 14, front = 3, side = 8 },
			-- catalog hair accessories wrap the whole head, so they only sway a little before they
			-- would lift off the forehead
			hairWrap = { frequency = 3, damping = 0.5, drag = 0.12, hang = 0.15, back = 6, front = 1.5, side = 4 },
			cape = { frequency = 1.6, damping = 0.4, drag = 0.45, hang = 0.7, back = 40, front = 2, side = 14 },
			coat = { frequency = 2.2, damping = 0.45, drag = 0.35, hang = 0.6, back = 26, front = 3, side = 10 },
			scarf = { frequency = 2.4, damping = 0.4, drag = 0.4, hang = 0.6, back = 30, front = 6, side = 14 },
			tail = { frequency = 1.8, damping = 0.35, drag = 0.35, hang = 0.4, back = 20, front = 20, side = 18 },
			mane = { frequency = 3.2, damping = 0.5, drag = 0.15, hang = 0.2, back = 8, front = 4, side = 6 },
		},
	},

	-- What each effect quality level (`quality` above) keeps of the motion, for phones. `secondary`:
	-- loose parts swing; `benchDetail`: bench units get the living idle and secondary motion (off: a
	-- plain idle); `skipOffscreen`: units off screen are not posed at all (their click box still
	-- moves), and are posed again as soon as they come into view (`offscreenMargin`: share of the
	-- screen past each edge that still counts as on screen).
	offscreenMargin = 0.15,
	motionQuality = {
		low = { secondary = false, benchDetail = false, skipOffscreen = true },
		medium = { secondary = true, benchDetail = true, skipOffscreen = false },
		high = { secondary = true, benchDetail = true, skipOffscreen = false },
	},

	-- Getting hit ------------------------------------------------------------------------------
	-- A white flash (crits: orange), a small knock away from the attacker that eases back, a squash
	-- (crouch) that recovers, and the body leans back. The head snaps first and the body follows:
	-- the head reaches its full snap in 1 / `headSnap` of the reaction, the body starts `bodyDelay`
	-- of the reaction later (the knock itself is not delayed).
	hit = {
		duration = 0.24,
		flashDuration = 0.08,
		flashColor = rgb(255, 255, 255),
		critFlashColor = rgb(255, 150, 40),
		knock = 0.28, -- studs, at the start
		critKnock = 0.45,
		squash = 0.16, -- crouch fraction
		lean = -14,
		armFlail = 18, -- both arms jerk up, degrees
		headSnap = 18,
		headLean = -16, -- the head thrown back, degrees (on top of the body's lean)
		headRoll = 7, -- and tipped to one side (alternating hit to hit), degrees
		bodyDelay = 0.07,
	},

	-- Hit-stop: on a big hit, the attacker and the target hold their pose for a moment. Big: a crit,
	-- an execute, or damage of at least `bigShare` of the target's max health. `cooldown` keeps a
	-- unit from being held again right away.
	hitStop = { duration = 0.05, bigDuration = 0.08, bigShare = 0.18, cooldown = 0.3, jitter = 0.06 },

	-- Camera shake: each kick adds "trauma" (capped at 1), which decays per second; the offset is
	-- trauma squared times the max offset and roll, so small kicks stay tiny.
	shake = {
		crit = 0.22,
		ability = 0.12,
		big = 0.32,
		slam = 0.1,
		decay = 2.6,
		maxOffset = 0.5, -- studs
		maxRoll = 0.7, -- degrees
		frequency = 22, -- shakes per second
	},

	-- Impact sparks, by damage type (CombatMath.DamageType). `color` sparks, `core` the flash ball.
	-- Counts are at high quality for a 1-star (scaled by quality and star level).
	impact = {
		PHYSICAL = { color = rgb(255, 210, 140), core = rgb(255, 245, 225) },
		MAGIC = { color = rgb(190, 120, 255), core = rgb(235, 210, 255) },
		TRUE = { color = rgb(255, 255, 255), core = rgb(255, 250, 200) },
		sparks = 7,
		critSparks = 14,
		abilitySparks = 10,
		sparkSpeed = { 9, 18 },
		sparkLifetime = { 0.12, 0.26 },
		sparkSize = 0.22,
		spread = 70, -- degrees around the direction away from the attacker
		ballSize = 1.0, -- flash ball diameter (crits and ability hits grow it)
		critBall = 1.7,
		abilityBall = 1.4,
		ballDuration = 0.14,
		shieldBreak = rgb(170, 230, 255), -- shards when a hit breaks a shield
		shieldBreakSparks = 12,
	},

	-- Casting --------------------------------------------------------------------------------------
	-- Wind-up: the arms rise, the body crouches, an orb of the faction color gathers between the
	-- hands (with sparkles drawn in at high quality) and the body glows in the last part. It starts
	-- `windup` before the cast (a signature's own length for units with one), taking over the motion
	-- of the unit's attacks that overlap it (they still land). Release: arms thrust
	-- up, the body leans back then forward, and a burst at the caster (a ring, a flash ball and
	-- sparks). Every target of the ability gets a hit effect in the caster's faction color.
	cast = {
		windup = 0.4,
		release = 0.3,
		glowFrom = 0.6, -- fraction of the wind-up where the body starts to glow
		glowBlend = 0.5, -- how far the glow tints the body toward the color (0-1), keeping it readable
		windupArms = 125,
		releaseArms = 165,
		windupCrouch = 0.12,
		windupLean = -6,
		releaseLean = 10,
		orbSize = 0.55, -- the orb's diameter at full charge, studs
		chargeRate = 40, -- sparkles drawn in per second (high quality)
		burstRing = 6, -- ring diameter, studs
		burstBall = 2.2,
		burstSparks = 16,
		targetWindow = 1.0, -- seconds after a cast in which its caster's hits count as ability hits
		targetRing = 2.4,
		targetSparks = 6,
	},

	-- Signature poses (AbilityFxConfig.signatures). "punch": the wind-up draws the right fist back
	-- with the body coiled (arm, offArm, twist and lean in degrees; crouch as above), reaching it at
	-- `stillFrom` of the wind-up and then holding still with a faint tremble; the release snaps the
	-- fist straight out with a step in (`lunge` studs), holds to `hold`, then recovers.
	signaturePoses = {
		punch = {
			stillFrom = 0.72,
			windupArm = -55,
			windupOffArm = 70,
			windupTwist = -42,
			windupLean = -6,
			windupCrouch = 0.22,
			tremble = 0.012,
			releaseArm = 92,
			releaseOffArm = -20,
			releaseTwist = 38,
			releaseLean = 22,
			releaseCrouch = 0.12,
			lunge = 1.1,
			snap = 0.12, -- share of the release taken by the snap
			hold = 0.55,
			release = 0.6, -- seconds
		},
	},

	-- Stun: the unit droops (lean forward, arms hang), sways, and small stars circle its head over
	-- the halo (RenderConfig.stunMarkerColor).
	stun = { lean = 14, sway = 6, swayRate = 3, arms = 0.25, stars = 3, starSize = 0.18, starSpeed = 5 },

	-- Death: a stagger back, a crumple to the ground, a fade and a small puff. Fractions of
	-- `duration`.
	death = {
		duration = 0.8,
		staggerEnd = 0.22,
		crumpleEnd = 0.6,
		fadeFrom = 0.35,
		puffAt = 0.55,
		staggerStep = 0.35, -- studs back
		staggerLean = -18,
		staggerTilt = 10,
		fall = 82,
		crouch = 0.35,
		sink = 1.0, -- studs, by the end
		puffColor = rgb(210, 210, 215),
		puffCount = 12,
		puffSize = { 0.5, 1.1 },
	},

	-- Victory: survivors of the winning side cheer when the fight ends: hops with arms up.
	victory = { delay = 0.15, duration = 1.1, hops = 2, hopHeight = 0.55, arms = 160 },

	-- Shields and heals.
	shield = { color = rgb(150, 220, 255), pop = 0.22, popScale = 1.3, ring = 3.2 },
	heal = { color = rgb(110, 255, 140), motes = 9, moteSpeed = { 2, 4 }, ring = 3.0 },

	-- Floating numbers pop: they start `pop` times their size and settle over `popTime`. Ability hits
	-- are drawn `abilitySize` pixels.
	numbers = { pop = 1.35, critPop = 1.8, popTime = 0.12, abilitySize = 15 },

	-- Dev preview (Studio lineup close-up, DevLineup): how far in front the target dummy stands for a
	-- melee or ranged unit (studs), the attack interval the preview's motions are timed to, and the
	-- damage shown (the dummy and the unit have `health`).
	preview = {
		meleeDistance = 4.8,
		rangedDistance = 11,
		interval = 1.2,
		health = 1000,
		damage = 85,
		critDamage = 190,
		abilityDamage = 240,
		heal = 120,
		shield = 200,
		stun = 2,
	},
})
