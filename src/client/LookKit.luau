-- Turns a hand-built look (UnitLookConfig) into the parts of a figure: a list of specs (shape, size,
-- anchor, offset, color) that Figure creates and moves. Only math and data here: no instances.
-- Presentation only.
--
-- Every builder places parts in the space of a figure anchor (Figure): hips, head, leftArm,
-- rightArm, leftHand, rightHand, leftLeg, rightLeg. The figure faces -Z and its left is -X. Body
-- sizes come from the figure's proportions (FigureConfig.body, after bulk), so a look scales with
-- star level and form size. Hair and headwear are sized in head sizes, everything else in figure
-- heights.
--
-- Parts marked `fine` are small details that low-detail figures (hub statues) leave out. Parts
-- marked `plain` keep their color through hit flashes, cast glows and selection (faces, weapons).

local LookKit = {}

export type Spec = {
	anchor: string,
	shape: string, -- "Block", "Ball", "Cylinder", "Wedge" or "CornerWedge"
	size: Vector3,
	offset: CFrame,
	color: Color3,
	material: string,
	tinted: boolean,
	transparency: number, -- 0 for most parts (auras and steam are see-through)
	emitter: any?, -- a soft particle stream from this (invisible) part: { rate, color, size } (steam)
	drawn: boolean?, -- part of a weapon with `drawn`: shown only while it is out (Figure.setDrawn)
	-- A loose part (long hair, coat tails, a scarf end): { group, pivot, facing } shared by the parts
	-- that swing together about `pivot` (anchor space), in AnimationConfig.secondary.groups[group]'s
	-- way; `facing` 1 hangs behind the body, -1 in front, 0 beside it (Figure).
	swing: any?,
}

type Options = { material: string?, fine: boolean?, plain: boolean?, transparency: number?, emitter: any? }

type Context = {
	specs: { Spec },
	look: any,
	body: { [string]: number },
	h: number, -- figure height
	hs: number, -- head size
	low: boolean,
	thin: number, -- overlay thickness
	grip: CFrame?, -- the current held weapon's grip, when it rides an anchor other than a hand
	fists: boolean?, -- held by a catalog avatar: hilts reach past its blocky 0.2-thick fists
	swing: any?, -- the loose set the parts added now belong to (Spec `swing`), if any
}

local rad = math.rad
local V = Vector3.new
local CF = CFrame.new
local SIDES = { "left", "right" }
local SIGN = { left = -1, right = 1 }
local NONE: Options = {}
local PLAIN: Options = { plain = true }
local FINE: Options = { fine = true }
local FINE_PLAIN: Options = { fine = true, plain = true }
local DARK = Color3.fromRGB(28, 26, 32)

local function turn(x: number, y: number, z: number): CFrame
	return CFrame.Angles(rad(x), rad(y), rad(z))
end

local function add(
	ctx: Context,
	anchor: string,
	shape: string,
	size: Vector3,
	offset: CFrame,
	color: Color3,
	options: Options?
)
	local o = options or NONE
	if o.fine and ctx.low then
		return
	end
	table.insert(ctx.specs, {
		anchor = anchor,
		shape = shape,
		size = size,
		offset = offset,
		color = color,
		material = o.material or "SmoothPlastic",
		tinted = not o.plain,
		transparency = o.transparency or 0,
		emitter = o.emitter,
		swing = ctx.swing,
	})
end

-- A loose set: parts swinging together about `pivot` (anchor space) as `group` (Spec `swing`).
local function swingSet(group: string, pivot: Vector3, facing: number): any
	return { group = group, pivot = pivot, facing = facing }
end

-- Adds the parts of `build` to the loose set `set`.
local function loose(ctx: Context, set: any, build: () -> ())
	local outer = ctx.swing
	ctx.swing = set
	build()
	ctx.swing = outer
end

-- Body ------------------------------------------------------------------------------------------

-- The head block's size: a cube of the head size, or `headScale` (multipliers) times it.
local function headSize(ctx: Context): Vector3
	local scale = ctx.look.headScale or Vector3.one
	return scale * ctx.hs
end

-- The standard body: torso, head, two-tone arms and legs. A look can leave out the arms or legs
-- (`customArms`, `customLegs`) and build its own on the same anchors with extras, e.g. a crouching
-- creature's bent legs; the anchors, and so every pose, stay the same.
local function buildBody(ctx: Context)
	local look, b, h = ctx.look, ctx.body, ctx.h
	local coat = look.coat
	add(
		ctx,
		"hips",
		"Block",
		V(b.torsoWidth, b.torsoHeight, b.torsoDepth),
		CF(0, b.torsoHeight / 2, 0),
		if coat then coat.color else look.torso
	)
	add(ctx, "head", "Block", headSize(ctx), CFrame.identity, look.skin)

	local armLength, armWidth = b.armLength, b.armWidth
	local sleeve = look.sleeve or 0.8
	local sleeveColor = look.sleeves or (if coat then coat.color else look.torso)
	for _, side in if look.customArms then {} else SIDES do
		local anchor = side .. "Arm"
		local top = armLength * sleeve
		if top > 0 then
			add(ctx, anchor, "Block", V(armWidth, top, armWidth), CF(0, -top / 2, 0), sleeveColor)
		end
		local rest = armLength - top
		if rest > 0 then
			add(ctx, anchor, "Block", V(armWidth, rest, armWidth), CF(0, -top - rest / 2, 0), look.gloves or look.skin)
		end
		local short = look.shortSleeves
		if short then
			local length = armLength * short.length
			add(
				ctx,
				anchor,
				"Block",
				V(armWidth * 1.12, length, armWidth * 1.12),
				CF(0, -length / 2 + h * 0.005, 0),
				short.color
			)
		end
	end

	local legLength, legWidth = b.legLength, b.legWidth
	local shoe = look.shoe or 0.16
	local trousers = math.min(look.shorts or 1, 1 - shoe)
	local wide = look.wideLegs or 1
	for _, side in if look.customLegs then {} else SIDES do
		local anchor = side .. "Leg"
		local top = legLength * trousers
		add(ctx, anchor, "Block", V(legWidth * wide, top, legWidth * wide), CF(0, -top / 2, 0), look.pants)
		local middle = legLength * (1 - shoe) - top
		if middle > 1e-3 then
			add(
				ctx,
				anchor,
				"Block",
				V(legWidth * 0.96, middle, legWidth * 0.96),
				CF(0, -top - middle / 2, 0),
				look.socks or look.skin
			)
		end
		local foot = legLength * shoe
		add(
			ctx,
			anchor,
			"Block",
			V(legWidth * 1.04, foot, legWidth * 1.14),
			CF(0, -legLength + foot / 2, -legWidth * 0.07),
			look.shoes
		)
	end
end

-- Face ------------------------------------------------------------------------------------------

local function face(ctx: Context)
	local f = ctx.look.face or {}
	local hs = ctx.hs
	local front = -headSize(ctx).Z / 2
	local depth = hs * 0.05
	local eyes = f.eyes or "open"
	for i, side in SIDES do
		local x = SIGN[side]
		local cx = x * hs * 0.22
		local color = (if i == 1 then f.leftEye else f.rightEye) or f.eyeColor or DARK
		if eyes == "closed" then
			add(ctx, "head", "Block", V(hs * 0.2, hs * 0.045, depth), CF(cx, 0, front), DARK, PLAIN)
		elseif eyes ~= "none" then
			local tall = if eyes == "sharp" then hs * 0.11 else hs * 0.17
			add(ctx, "head", "Block", V(hs * 0.15, tall, depth), CF(cx, hs * 0.02, front), color, PLAIN)
		end
		if eyes == "sharp" then
			-- brows slanting down toward the nose
			add(
				ctx,
				"head",
				"Block",
				V(hs * 0.24, hs * 0.05, depth),
				CF(cx, hs * 0.15, front) * turn(0, 0, 14 * x),
				DARK,
				FINE_PLAIN
			)
		end
	end
	if f.mouth then
		add(ctx, "head", "Block", V(hs * 0.22, hs * 0.04, depth), CF(0, -hs * 0.24, front), DARK, FINE_PLAIN)
	end
	local mask = f.mask
	if mask then
		add(ctx, "head", "Block", V(hs * 1.04, hs * 0.42, hs * 0.3), CF(0, -hs * 0.29, -hs * 0.39), mask.color)
		if mask.teeth then
			add(
				ctx,
				"head",
				"Block",
				V(hs * 0.62, hs * 0.1, hs * 0.04),
				CF(0, -hs * 0.28, -hs * 0.55),
				mask.teeth,
				PLAIN
			)
			add(
				ctx,
				"head",
				"Block",
				V(hs * 0.64, hs * 0.02, hs * 0.045),
				CF(0, -hs * 0.28, -hs * 0.55),
				mask.color,
				FINE_PLAIN
			)
		end
	end
	if ctx.look.ears == "elf" then
		for _, side in SIDES do
			local x = SIGN[side]
			local at = CF(x * hs * 0.48, -hs * 0.02, hs * 0.04) * turn(0, 90 * x, 0) * turn(68, 0, 0)
			add(ctx, "head", "Wedge", V(hs * 0.07, hs * 0.34, hs * 0.2), at * CF(0, hs * 0.17, 0), ctx.look.skin)
		end
	end
end

-- Hair ------------------------------------------------------------------------------------------

-- Hair styles, in head sizes. `cap` covers the top of the head, `back` hangs down the back of the
-- head, `sides` over the ears and `fringe` over the forehead (each a length). `rings` are rings of
-- spikes (wedges): `count` spikes standing `y` up at `radius` from the middle, each leaning `tilt`
-- degrees out from upright (over 90 points down), `length` long with a `base` wide footing;
-- `yaw` turns the ring (0 is the back, 180 the front) and `span` limits it to an arc centered on
-- `yaw`. `tips` colors the spike tips with the hair's `tip` color. `balls`, `panels` (blocks) and
-- `rolls` (cylinders along X) add other shapes.
local BANGS =
	{ count = 3, y = 0.38, radius = 0.42, tilt = 155, length = 0.3, base = 0.24, thick = 0.22, yaw = 180, span = 70 }

LookKit.HAIR = {
	spiky = {
		cap = 0.3,
		back = 0.7,
		fringe = 0.2,
		rings = {
			{ count = 6, y = 0.4, radius = 0.32, tilt = 58, length = 0.5, base = 0.34, thick = 0.3, tips = true },
			{
				count = 3,
				y = 0.5,
				radius = 0.1,
				tilt = 22,
				length = 0.5,
				base = 0.32,
				thick = 0.28,
				yaw = 30,
				tips = true,
			},
			BANGS,
		},
	},
	tall = {
		cap = 0.3,
		back = 0.6,
		fringe = 0.15,
		rings = {
			{ count = 7, y = 0.45, radius = 0.22, tilt = 22, length = 1.0, base = 0.38, thick = 0.26, tips = true },
			BANGS,
		},
	},
	fluffy = {
		cap = 0.3,
		back = 0.75,
		sides = 0.55,
		rings = {
			{ count = 6, y = 0.35, radius = 0.45, tilt = 82, length = 0.32, base = 0.3, thick = 0.28 },
			{ count = 2, y = 0.52, radius = 0.12, tilt = 30, length = 0.35, base = 0.3, yaw = 90 },
			BANGS,
		},
		balls = {
			{ at = V(-0.34, 0.42, 0), size = 0.5 },
			{ at = V(0.34, 0.42, 0.02), size = 0.5 },
			{ at = V(0, 0.56, 0.22), size = 0.5 },
			{ at = V(-0.18, 0.5, -0.22), size = 0.42 },
			{ at = V(0.2, 0.48, 0.32), size = 0.45 },
		},
	},
	messy = {
		cap = 0.3,
		back = 0.85,
		sides = 0.6,
		fringe = 0.25,
		rings = {
			{ count = 7, y = 0.32, radius = 0.48, tilt = 108, length = 0.35, base = 0.3, yaw = 0, span = 230 },
			{ count = 3, y = 0.5, radius = 0.15, tilt = 45, length = 0.35, base = 0.3, yaw = 60 },
			BANGS,
		},
	},
	wild = {
		cap = 0.3,
		back = 0.7,
		rings = {
			{ count = 7, y = 0.42, radius = 0.3, tilt = 62, length = 0.55, base = 0.32, thick = 0.28 },
			{ count = 6, y = 0.2, radius = 0.5, tilt = 100, length = 0.45, base = 0.3, yaw = 0, span = 240 },
			{ count = 3, y = 0.5, radius = 0.1, tilt = 25, length = 0.55, base = 0.3, yaw = 30 },
			{
				count = 3,
				y = 0.38,
				radius = 0.42,
				tilt = 140,
				length = 0.35,
				base = 0.24,
				thick = 0.22,
				yaw = 180,
				span = 80,
			},
		},
	},
	neat = {
		cap = 0.3,
		back = 0.75,
		sides = 0.45,
		fringe = 0.18,
		rings = {
			{
				count = 3,
				y = 0.38,
				radius = 0.42,
				tilt = 160,
				length = 0.26,
				base = 0.24,
				thick = 0.22,
				yaw = 180,
				span = 80,
			},
		},
	},
	undercut = {
		cap = 0.36,
		back = 0.35,
		panels = { -- a fringe parted in the middle
			{ size = V(0.5, 0.42, 0.1), at = V(-0.25, 0.32, -0.53), turn = V(0, 0, 12) },
			{ size = V(0.5, 0.42, 0.1), at = V(0.25, 0.32, -0.53), turn = V(0, 0, -12) },
		},
	},
	bob = {
		cap = 0.3,
		back = 1.0,
		sides = 0.95,
		sideWidth = 0.14,
		fringe = 0.3,
		rings = {
			{
				count = 3,
				y = 0.38,
				radius = 0.42,
				tilt = 165,
				length = 0.25,
				base = 0.24,
				thick = 0.22,
				yaw = 180,
				span = 80,
			},
		},
	},
	long = {
		cap = 0.3,
		back = 1.7,
		sides = 1.2,
		fringe = 0.2,
	},
	bun = {
		cap = 0.3,
		back = 0.75,
		sides = 0.45,
		fringe = 0.2,
		balls = { { at = V(0, 0.42, 0.6), size = 0.46 } },
	},
	pompadour = {
		cap = 0.3,
		back = 0.75,
		sides = 0.45,
		panels = { { size = V(0.95, 0.36, 0.75), at = V(0, 0.68, -0.12) } },
		rolls = { { length = 0.95, diameter = 0.46, at = V(0, 0.66, -0.48) } },
	},
	twintails = {
		cap = 0.3,
		back = 1.2,
		sides = 1.0,
		fringe = 0.25,
		panels = {
			{ size = V(0.3, 1.5, 0.3), at = V(-0.68, -0.25, 0.22), turn = V(0, 0, -6) },
			{ size = V(0.3, 1.5, 0.3), at = V(0.68, -0.25, 0.22), turn = V(0, 0, 6) },
		},
		balls = {
			{ at = V(-0.6, 0.42, 0.2), size = 0.2, fine = true },
			{ at = V(0.6, 0.42, 0.2), size = 0.2, fine = true },
		},
	},
	short = { -- under a hat
		back = 0.7,
		sides = 0.5,
		fringe = 0.22,
		rings = {
			{
				count = 3,
				y = 0.3,
				radius = 0.42,
				tilt = 160,
				length = 0.24,
				base = 0.24,
				thick = 0.22,
				yaw = 180,
				span = 80,
			},
		},
	},
}

-- A spike: a wedge standing on `at` (head space, studs), leaning `tilt` degrees out toward `yaw`.
-- Its point is on the outer side. With `tipColor`, the top `tipFraction` is a second, slightly larger
-- wedge in that color (scaled about the tip's centroid so it covers the spike there without
-- flickering).
local function spike(
	ctx: Context,
	at: Vector3,
	yaw: number,
	tilt: number,
	length: number,
	base: number,
	thick: number,
	color: Color3,
	tipColor: Color3?
)
	local frame = CF(at) * turn(0, yaw, 0) * turn(tilt, 0, 0)
	add(ctx, "head", "Wedge", V(thick, length, base), frame * CF(0, length / 2, 0), color)
	if tipColor then
		local t, k = 0.4, 1.1
		local center =
			CF(0, length * (1 - t / 2) + (k - 1) * length * t / 6, base / 2 - base * t / 2 - (k - 1) * base * t / 6)
		add(ctx, "head", "Wedge", V(thick * k, length * t * k, base * t * k), frame * center, tipColor)
	end
end

local function ring(ctx: Context, r: any, color: Color3, tip: Color3?, lift: number?)
	local hs = ctx.hs
	local span = r.span or 360
	local tilt = r.tilt
	if lift and tilt < 90 then
		tilt *= lift
	end
	for i = 1, r.count do
		local yaw = r.yaw or 0
		if span >= 360 then
			yaw += span * (i - 1) / r.count
		elseif r.count > 1 then
			yaw += -span / 2 + span * (i - 1) / (r.count - 1)
		end
		local a = rad(yaw)
		local at = V(math.sin(a) * r.radius, r.y, math.cos(a) * r.radius) * hs
		local vary = 1 + ((i * 37) % 7 - 3) * 0.04 -- a little variety in length
		spike(
			ctx,
			at,
			yaw,
			tilt,
			r.length * vary * hs,
			r.base * hs,
			(r.thick or r.base * 0.8) * hs,
			color,
			if r.tips then tip else nil
		)
	end
end

local function hair(ctx: Context)
	local config = ctx.look.hair
	if not config then
		return
	end
	local style = LookKit.HAIR[config.style]
	assert(style, "unknown hair style " .. tostring(config.style))
	local hs = ctx.hs
	local color = config.color
	local function block(size: Vector3, at: Vector3, angles: Vector3?, options: Options?)
		local offset = CF(at * hs)
		if angles then
			offset *= turn(angles.X, angles.Y, angles.Z)
		end
		add(ctx, "head", "Block", size * hs, offset, color, options)
	end

	-- Hair that hangs (a long back, long sides) swings as one loose set about the top of the back of
	-- the head; panels hanging below the head (twintails) each swing about their own top; front
	-- strands swing together (AnimationConfig.secondary "hair"). Caps, fringes and spikes stay put.
	local LONG = 0.6
	if style.cap then
		block(V(1.1, style.cap, 1.1), V(0, 0.55 - style.cap / 2, 0.02))
	end
	local function hanging()
		if style.back then
			block(V(1.06, style.back, 0.22), V(0, 0.5 - style.back / 2, 0.46))
		end
		if style.sides and style.sides >= LONG then
			local width = style.sideWidth or 0.1
			for _, side in SIDES do
				block(V(width, style.sides, 0.8), V(SIGN[side] * (0.49 + width / 2), 0.45 - style.sides / 2, 0.08))
			end
		end
	end
	if (style.back or 0) >= LONG or (style.sides or 0) >= LONG then
		loose(ctx, swingSet("hair", V(0, 0.5, 0.3) * hs, 1), hanging)
	else
		hanging()
	end
	if style.sides and style.sides < LONG then
		local width = style.sideWidth or 0.1
		for _, side in SIDES do
			block(V(width, style.sides, 0.8), V(SIGN[side] * (0.49 + width / 2), 0.45 - style.sides / 2, 0.08))
		end
	end
	if style.fringe then
		block(V(1.08, style.fringe, 0.12), V(0, 0.5 - style.fringe / 2, -0.5))
	end
	for _, panel in style.panels or {} do
		if panel.at.Y < 0 then
			local top = panel.at + Vector3.new(0, panel.size.Y / 2, 0)
			loose(ctx, swingSet("hair", top * hs, 0), function()
				block(panel.size, panel.at, panel.turn)
			end)
		else
			block(panel.size, panel.at, panel.turn)
		end
	end
	for _, roll in style.rolls or {} do
		add(ctx, "head", "Cylinder", V(roll.length, roll.diameter, roll.diameter) * hs, CF(roll.at * hs), color)
	end
	for _, ball in style.balls or {} do
		add(ctx, "head", "Ball", Vector3.one * ball.size * hs, CF(ball.at * hs), color, if ball.fine then FINE else nil)
	end
	for _, r in style.rings or {} do
		ring(ctx, r, color, config.tip, config.lift)
	end
	for _, r in config.rings or {} do
		ring(ctx, r, color, config.tip, config.lift)
	end
	local strands = config.strands
	if strands and #strands > 0 then
		loose(ctx, swingSet("hair", V(0, 0.45, -0.5) * hs, -1), function()
			for _, strand in strands do
				local width = strand.width or 0.11
				block(V(width, strand.length, 0.1), V(strand.x, 0.45 - strand.length / 2, strand.z or -0.53))
			end
		end)
	end
end

-- Headwear --------------------------------------------------------------------------------------

-- A heart: a diamond with two balls on top, facing -Z, centered on `at`, `size` studs across.
local function heart(ctx: Context, anchor: string, at: CFrame, size: number, color: Color3, options: Options?)
	local depth = ctx.h * 0.012
	add(
		ctx,
		anchor,
		"Block",
		V(size * 0.62, size * 0.62, depth),
		at * CF(0, -size * 0.08, 0) * turn(0, 0, 45),
		color,
		options
	)
	local fine: Options = { fine = true, plain = options and options.plain }
	for _, x in { -1, 1 } do
		add(ctx, anchor, "Ball", Vector3.one * size * 0.46, at * CF(x * size * 0.2, size * 0.14, 0), color, fine)
	end
end

local function headwear(ctx: Context)
	local w = ctx.look.headwear
	if not w then
		return
	end
	local hs = ctx.hs
	local function block(size: Vector3, at: Vector3, color: Color3, options: Options?)
		add(ctx, "head", "Block", size * hs, CF(at * hs), color, options)
	end
	if w.kind == "knit" then
		block(V(1.16, 0.48, 1.16), V(0, 0.46, 0.02), w.color)
		block(V(1.2, 0.14, 1.2), V(0, 0.26, 0.02), w.band or w.color)
		-- a horseshoe on the front
		local z = -0.6
		block(V(0.07, 0.26, 0.06), V(-0.12, 0.4, z), w.ornament)
		block(V(0.07, 0.26, 0.06), V(0.12, 0.4, z), w.ornament)
		block(V(0.31, 0.07, 0.06), V(0, 0.29, z), w.ornament)
		if w.horns then
			for _, x in { -1, 1 } do
				add(ctx, "head", "Wedge", V(0.08, 0.2, 0.14) * hs, CF(x * hs * 0.36, hs * 0.78, 0), w.horns, FINE)
			end
		end
	elseif w.kind == "wide" then
		add(ctx, "head", "Cylinder", V(0.05, 2.1, 2.1) * hs, CF(0, hs * 0.45, 0) * turn(0, 0, 90), w.color)
		block(V(1.14, 0.42, 1.14), V(0, 0.68, 0), w.color) -- wider than a hair cap
		block(V(1.18, 0.11, 1.18), V(0, 0.53, 0), w.band or w.color)
		if w.goggles then
			for _, x in { -1, 1 } do
				add(
					ctx,
					"head",
					"Cylinder",
					V(0.06, 0.17, 0.17) * hs,
					CF(x * hs * 0.16, hs * 0.56, -hs * 0.6) * turn(0, 90, 0),
					w.goggles,
					{ fine = true, material = "Glass" }
				)
			end
		end
		if w.crest then
			for i, z in { -0.28, 0, 0.28 } do
				add(
					ctx,
					"head",
					"Wedge",
					V(0.08, 0.26 - math.abs(i - 2) * 0.05, 0.3) * hs,
					CF(0, hs * (1.0 - math.abs(i - 2) * 0.025), z * hs),
					w.crest
				)
			end
		end
	elseif w.kind == "peaked" then
		block(V(1.14, 0.34, 1.14), V(0, 0.5, 0.02), w.color)
		add(ctx, "head", "Block", V(0.9, 0.05, 0.4) * hs, CF(0, hs * 0.36, -hs * 0.72) * turn(-8, 0, 0), w.color)
		if w.badge then
			block(V(0.15, 0.15, 0.04), V(0, 0.52, -0.59), w.badge, FINE)
		end
	elseif w.kind == "band" then
		block(V(1.13, 0.14, 1.13), V(0, 0.2, 0), w.color)
		if w.heart then
			heart(ctx, "head", CF(0, hs * 0.2, -hs * 0.575), hs * 0.24, w.heart)
		end
	end
end

-- Clothes ---------------------------------------------------------------------------------------

-- Thin squares in alternating cells of a `cols` x `rows` grid on a face, centered on `center` (its
-- surface, facing out along -Z of `center`). `parity` picks which cells are filled.
local function checker(
	ctx: Context,
	anchor: string,
	center: CFrame,
	width: number,
	height: number,
	cols: number,
	rows: number,
	color: Color3,
	parity: number
)
	local cellW, cellH = width / cols, height / rows
	for row = 1, rows do
		for col = 1, cols do
			if (row + col) % 2 == parity then
				local x = -width / 2 + cellW * (col - 0.5)
				local y = height / 2 - cellH * (row - 0.5)
				add(ctx, anchor, "Block", V(cellW, cellH, ctx.thin * 1.4), center * CF(x, y, 0), color)
			end
		end
	end
end

-- A small triangle facing out along -Z of `at` (or +Z: it is a thin wedge seen side-on).
local function triangle(ctx: Context, anchor: string, at: CFrame, size: number, color: Color3, options: Options?)
	add(ctx, anchor, "Wedge", V(ctx.thin * 1.4, size, size), at * turn(0, 90, 0), color, options)
end

local function coat(ctx: Context)
	local c = ctx.look.coat
	if not c then
		return
	end
	local b, h, thin = ctx.body, ctx.h, ctx.thin
	local tW, tH, tD = b.torsoWidth, b.torsoHeight, b.torsoDepth
	local open = c.open ~= false
	local gap = c.gap or 0.34
	local front = -tD / 2
	if open then
		-- the shirt (or chest) showing between the open fronts
		add(
			ctx,
			"hips",
			"Block",
			V(tW * gap, tH * 0.98, thin),
			CF(0, tH * 0.49, front - thin / 2),
			c.inner or ctx.look.torso
		)
		if c.stripes then
			for _, y in { 0.3, 0.5, 0.7 } do
				add(ctx, "hips", "Block", V(tW * gap, h * 0.026, thin), CF(0, tH * y, front - thin * 1.2), c.stripes)
			end
		end
		if c.cross then
			for _, x in { -1, 1 } do
				add(
					ctx,
					"hips",
					"Block",
					V(h * 0.032, tH * 0.55, thin),
					CF(x * h * 0.04, tH * 0.72, front - thin * 1.5) * turn(0, 0, -25 * x),
					c.cross
				)
			end
		end
		if c.trim then
			for _, x in { -1, 1 } do
				add(ctx, "hips", "Block", V(h * 0.022, tH, thin), CF(x * tW * gap / 2, tH / 2, front - thin), c.trim)
			end
		end
	end
	local collar = c.collar
	if collar then
		add(ctx, "hips", "Block", V(tW * 0.62, h * 0.07, tD * 1.15), CF(0, tH + h * 0.015, 0), collar)
	end

	-- Tails below the hips: back, front (two halves when open) and optionally the sides. Each hangs
	-- from a little above the hips and flares out by `flare` degrees, and swings about its top as a
	-- loose set (AnimationConfig.secondary "coat"), with its band and pattern.
	local tails: { { frame: CFrame, width: number, length: number, facing: number, swing: any } } = {}
	local length = (c.length or 0) * b.legLength
	if length > 0 then
		local depth = h * 0.03
		local top = h * 0.03
		local full = length + top
		local flare = c.flare or 4
		local function tail(width: number, at: CFrame, angles: CFrame, facing: number)
			local frame = at * angles * CF(0, -full / 2, 0)
			local set = swingSet("coat", at.Position, facing)
			table.insert(tails, { frame = frame, width = width, length = full, facing = facing, swing = set })
			loose(ctx, set, function()
				add(ctx, "hips", "Block", V(width, full, depth), frame, c.tail or c.color)
				if c.band then
					local bandLength = full * c.band.fraction
					add(
						ctx,
						"hips",
						"Block",
						V(width * 1.01, bandLength, depth * 1.3),
						frame * CF(0, -full / 2 + bandLength / 2, 0),
						c.band.color
					)
				end
			end)
		end
		local outset = h * 0.006
		tail(tW * 1.04, CF(0, top, tD / 2 - depth / 2 + outset), turn(-flare, 0, 0), 1)
		if open then
			for _, x in { -1, 1 } do
				tail(tW * 0.46, CF(x * tW * 0.27, top, -tD / 2 + depth / 2 - outset), turn(flare, 0, 0), -1)
			end
		else
			tail(tW * 1.04, CF(0, top, -tD / 2 + depth / 2 - outset), turn(flare, 0, 0), -1)
		end
		if c.sides then
			for _, x in { -1, 1 } do
				local at = CF(x * (tW / 2 - depth / 2 + outset), top, 0)
				local frame = at * turn(0, 0, flare * x) * CF(0, -full / 2, 0)
				loose(ctx, swingSet("coat", at.Position, 0), function()
					add(ctx, "hips", "Block", V(depth, full, tD * 0.96), frame, c.tail or c.color)
				end)
			end
		end
	end

	local pattern = c.pattern
	if not pattern then
		return
	end
	local sleeveLength = b.armLength * (ctx.look.sleeve or 0.8)
	if pattern.kind == "checker" then
		local panel = tW * (1 - gap) / 2
		checker(ctx, "hips", CF(0, tH / 2, tD / 2 + thin * 0.7) * turn(0, 180, 0), tW, tH, 3, 3, pattern.color, 0)
		for i, x in { -1, 1 } do
			checker(
				ctx,
				"hips",
				CF(x * (tW / 2 - panel / 2), tH / 2, front - thin * 0.7),
				panel,
				tH,
				1,
				3,
				pattern.color,
				i % 2
			)
		end
		for _, t in tails do
			local cols = if t.width > tW then 3 else 1
			loose(ctx, t.swing, function()
				checker(
					ctx,
					"hips",
					t.frame * CF(0, 0, t.facing * h * 0.022),
					t.width,
					t.length,
					cols,
					1,
					pattern.color,
					1
				)
			end)
		end
		-- bands around the sleeves, alternating between the arms
		for i, side in SIDES do
			local segment = sleeveLength / 3
			for row = 1, 3 do
				if (row + i) % 2 == 0 then
					add(
						ctx,
						side .. "Arm",
						"Block",
						V(b.armWidth * 1.06, segment, b.armWidth * 1.06),
						CF(0, (b.armTop or 0) - segment * (row - 0.5), 0),
						pattern.color
					)
				end
			end
		end
	elseif pattern.kind == "triangles" then
		local size = h * 0.07
		triangle(ctx, "hips", CF(-tW * 0.22, tH * 0.7, tD / 2 + thin * 0.7), size, pattern.color)
		triangle(ctx, "hips", CF(tW * 0.2, tH * 0.35, tD / 2 + thin * 0.7), size, pattern.color)
		for index, t in tails do
			local y = -t.length * 0.2 + (index % 2) * t.length * 0.25
			loose(ctx, t.swing, function()
				triangle(ctx, "hips", t.frame * CF(t.width * 0.15, y, t.facing * h * 0.022), size, pattern.color)
				if t.width > tW then
					triangle(
						ctx,
						"hips",
						t.frame * CF(-t.width * 0.25, -y, t.facing * h * 0.022),
						size,
						pattern.color,
						FINE
					)
				end
			end)
		end
		for _, side in SIDES do
			local x = SIGN[side] * (b.armWidth / 2 + thin * 0.5)
			add(
				ctx,
				side .. "Arm",
				"Wedge",
				V(thin * 1.4, size, size),
				CF(x, (b.armTop or 0) - sleeveLength * 0.55, 0),
				pattern.color
			)
		end
	end
end

-- A copy of an extra mirrored across X (the figure's left-right), on `anchor`.
local function mirrored(extra: any, anchor: string): any
	local copy = table.clone(extra)
	copy.anchor = anchor
	copy.at = V(-extra.at.X, extra.at.Y, extra.at.Z)
	if extra.to then
		copy.to = V(-extra.to.X, extra.to.Y, extra.to.Z)
	end
	if extra.turn then
		copy.turn = V(extra.turn.X, -extra.turn.Y, -extra.turn.Z)
	end
	return copy
end

-- Extras with their symmetric copies: `mirror = true` adds a copy mirrored across X on the same
-- anchor; `limbs = "Arm"` or `"Leg"` puts the extra (written for the right limb, +X outward) on
-- both limbs, mirrored for the left.
local function expandExtras(extras: { any }?): { any }
	local result = {}
	for _, extra in extras or {} do
		if extra.limbs then
			local right = table.clone(extra)
			right.anchor = "right" .. extra.limbs
			table.insert(result, right)
			table.insert(result, mirrored(extra, "left" .. extra.limbs))
		else
			table.insert(result, extra)
			if extra.mirror then
				table.insert(result, mirrored(extra, extra.anchor))
			end
		end
	end
	return result
end

local function accessories(ctx: Context)
	local look, b, h, thin = ctx.look, ctx.body, ctx.h, ctx.thin
	local tW, tH, tD = b.torsoWidth, b.torsoHeight, b.torsoDepth
	local front = -tD / 2

	if look.collar then
		add(ctx, "hips", "Block", V(tW * 0.62, h * 0.07, tD * 1.15), CF(0, tH + h * 0.015, 0), look.collar)
	end
	if look.belt then
		add(ctx, "hips", "Block", V(tW * 1.05, h * 0.045, tD * 1.14), CF(0, h * 0.03, 0), look.belt.color)
		if look.belt.buckle then
			add(
				ctx,
				"hips",
				"Block",
				V(h * 0.05, h * 0.04, h * 0.02),
				CF(0, h * 0.03, -tD * 0.57 - h * 0.006),
				look.belt.buckle
			)
		end
	end
	if look.sash then
		add(ctx, "hips", "Block", V(tW * 1.06, h * 0.065, tD * 1.16), CF(0, h * 0.035, 0), look.sash.color)
		add(
			ctx,
			"hips",
			"Block",
			V(h * 0.045, h * 0.13, h * 0.02),
			CF(h * 0.07, -h * 0.03, -tD * 0.58 - h * 0.006) * turn(0, 0, 8),
			look.sash.color,
			FINE
		)
	end
	if look.scarf then
		add(ctx, "hips", "Block", V(tW * 0.72, h * 0.075, tD * 1.4), CF(0, tH + h * 0.01, 0), look.scarf.color)
		-- The hanging end swings about its top (AnimationConfig.secondary "scarf").
		loose(ctx, swingSet("scarf", V(h * 0.05, tH, front - h * 0.02), -1), function()
			add(
				ctx,
				"hips",
				"Block",
				V(h * 0.07, h * 0.2, h * 0.03),
				CF(h * 0.05, tH - h * 0.1, front - h * 0.02) * turn(0, 0, -6),
				look.scarf.color
			)
		end)
	end
	if look.tie then
		add(ctx, "hips", "Block", V(h * 0.045, h * 0.2, h * 0.015), CF(0, tH - h * 0.12, front - h * 0.008), look.tie)
		add(
			ctx,
			"hips",
			"Block",
			V(h * 0.05, h * 0.04, h * 0.02),
			CF(0, tH - h * 0.025, front - h * 0.01),
			look.tie,
			FINE
		)
	end
	if look.cravat then
		add(
			ctx,
			"hips",
			"Block",
			V(h * 0.1, h * 0.11, h * 0.035),
			CF(0, tH - h * 0.045, front - h * 0.016),
			look.cravat
		)
	end
	local buttons = look.buttons
	if buttons then
		for i = 1, buttons.count do
			local y = tH * (0.85 - 0.7 * (i - 0.5) / buttons.count)
			add(
				ctx,
				"hips",
				"Block",
				V(h * 0.022, h * 0.022, h * 0.012),
				CF(0, y, front - thin * 2),
				buttons.color,
				FINE
			)
		end
	end
	for _, band in look.bands or {} do
		local limbs = if band.limb == "arms"
			then { "leftArm", "rightArm" }
			elseif band.limb == "legs" then { "leftLeg", "rightLeg" }
			else { band.limb }
		for _, limb in limbs do
			local arm = string.sub(limb, -3) == "Arm"
			local length = if arm then b.armLength else b.legLength
			local width = (if arm then b.armWidth else b.legWidth * math.max(look.wideLegs or 1, 1.04)) * 1.08
			local size = length * (band.to - band.from)
			add(
				ctx,
				limb,
				"Block",
				V(width, size, width),
				CF(0, (if arm then b.armTop or 0 else 0) - length * (band.from + band.to) / 2, 0),
				band.color,
				if band.fine then FINE else nil
			)
		end
	end
	for _, emblem in look.emblems or {} do
		local at = CF(emblem.at * h)
		local size = emblem.size * h
		local options: Options = { fine = emblem.fine }
		if emblem.shape == "heart" then
			heart(ctx, emblem.anchor, at, size, emblem.color, options)
		elseif emblem.shape == "disc" then
			add(ctx, emblem.anchor, "Cylinder", V(h * 0.012, size, size), at * turn(0, 90, 0), emblem.color, options)
		else
			add(
				ctx,
				emblem.anchor,
				"Block",
				V(size * 0.7, size * 0.7, h * 0.012),
				at * turn(0, 0, 45),
				emblem.color,
				options
			)
		end
	end
	if look.gearBoxes then
		for _, x in { -1, 1 } do
			add(
				ctx,
				"hips",
				"Block",
				V(h * 0.06, h * 0.11, h * 0.22),
				CF(x * (tW / 2 + h * 0.032), 0, h * 0.03),
				look.gearBoxes.color,
				{ material = "Metal" }
			)
			add(
				ctx,
				"hips",
				"Block",
				V(h * 0.062, h * 0.015, h * 0.2),
				CF(x * (tW / 2 + h * 0.032), h * 0.02, h * 0.03),
				DARK,
				FINE
			)
		end
	end
	local tendrils = look.tendrils
	if tendrils then
		-- two per side from the lower back: an upper pair reaching up and out, a lower pair out and down
		for _, x in { -1, 1 } do
			for _, setup in { { yaw = 50, rise = -35, bend = 16 }, { yaw = 72, rise = 12, bend = 12 } } do
				local frame = CF(x * h * 0.05, h * 0.09, tD / 2) * turn(0, setup.yaw * x, 0) * turn(setup.rise, 0, 0)
				for segment, width in { 0.07, 0.056, 0.042 } do
					local length = h * (0.22 - segment * 0.02)
					add(
						ctx,
						"hips",
						"Block",
						V(width * h, width * h, length),
						frame * CF(0, 0, length / 2),
						tendrils.color,
						{ material = "Neon" }
					)
					frame = frame * CF(0, 0, length * 0.92) * turn(setup.bend, 10 * x, 0)
				end
			end
		end
	end
	for _, extra in expandExtras(look.extras) do
		local size, offset
		if extra.to then
			-- A segment from `at` to `to`: its Z size is the distance between them.
			local from, to = extra.at * h, extra.to * h
			size = V(extra.size.X * h, extra.size.Y * h, (to - from).Magnitude)
			offset = CFrame.lookAt((from + to) / 2, to)
		else
			local angles = extra.turn or Vector3.zero
			size = extra.size * h
			offset = CF(extra.at * h) * turn(angles.X, angles.Y, angles.Z)
		end
		add(ctx, extra.anchor, extra.shape, size, offset, extra.color, {
			material = extra.material,
			fine = extra.fine,
			plain = extra.plain,
			transparency = extra.transparency,
		})
	end
	-- Steam (or any soft stream): an invisible part in the chest that emits see-through puffs.
	if look.steam then
		add(
			ctx,
			"hips",
			"Block",
			V(b.torsoWidth * 0.8, b.torsoHeight * 0.8, b.torsoDepth * 0.8),
			CF(0, b.torsoHeight * 0.55, 0),
			Color3.new(1, 1, 1),
			{ plain = true, transparency = 1, emitter = look.steam }
		)
	end
end

-- Weapons ---------------------------------------------------------------------------------------

-- Held weapons ride a hand anchor (the end of the arm, -Z is the arm's front) so they follow every
-- swing; the grip is just inside the hand. Worn weapons ride the hips. A held weapon with an
-- `anchor` rides that anchor instead, its grip at `at` (height fractions) turned by `turn`
-- (degrees), e.g. a sword held in the mouth; the blade still runs along the grip's -Z.
local function grip(ctx: Context): CFrame
	return ctx.grip or CF(0, ctx.h * 0.045, 0)
end

local function metal(w: any): Options
	return { plain = true, material = w.material or "Metal" }
end

LookKit.WEAPONS = {
	katana = function(ctx: Context, w: any, anchor: string)
		local h, g = ctx.h, grip(ctx)
		local length = (w.length or 0.5) * h
		-- `hiltLength` (height fraction): longer hilts show either side of an avatar's blocky fist.
		local hiltLength = (w.hiltLength or (if ctx.fists then 0.3 else 0.14)) * h
		local front = h * 0.01 - hiltLength / 2
		add(ctx, anchor, "Block", V(h * 0.032, h * 0.036, hiltLength), g * CF(0, 0, h * 0.01), w.hilt, PLAIN)
		add(
			ctx,
			anchor,
			"Block",
			V(h * 0.07, h * 0.07, h * 0.016),
			g * CF(0, 0, front - h * 0.008),
			w.guard or w.hilt,
			PLAIN
		)
		add(
			ctx,
			anchor,
			"Block",
			V(h * 0.018, h * 0.042, length),
			g * CF(0, 0, front - h * 0.016 - length / 2),
			w.blade,
			metal(w)
		)
	end,
	sheathedKatana = function(ctx: Context, w: any)
		local h, b = ctx.h, ctx.body
		local x = if w.side == "right" then 1 else -1
		local length = h * 0.5
		local base = CF(x * (b.torsoWidth / 2 + h * 0.03), h * 0.03, 0) * turn(18, 0, 0)
		add(ctx, "hips", "Block", V(h * 0.036, h * 0.04, length), base * CF(0, 0, length * 0.15), w.sheath)
		add(
			ctx,
			"hips",
			"Block",
			V(h * 0.034, h * 0.038, h * 0.14),
			base * CF(0, 0, length * 0.15 - length / 2 - h * 0.07),
			w.hilt,
			PLAIN
		)
		add(
			ctx,
			"hips",
			"Block",
			V(h * 0.06, h * 0.06, h * 0.014),
			base * CF(0, 0, length * 0.15 - length / 2),
			w.guard or w.sheath,
			FINE_PLAIN
		)
	end,
	greatsword = function(ctx: Context, w: any, anchor: string)
		local h, g = ctx.h, grip(ctx)
		local length, width = (w.length or 0.62) * h, (w.width or 0.15) * h
		-- On an avatar the guard and blade start past the blocky fist, and the hilt shows behind it.
		local out = if ctx.fists then h * 0.07 else 0
		local mid = -h * 0.085 - out - length / 2
		local hilt = if ctx.fists then h * 0.3 else h * 0.15
		add(ctx, anchor, "Block", V(h * 0.034, h * 0.04, hilt), g * CF(0, 0, h * 0.02), w.hilt, PLAIN)
		add(
			ctx,
			anchor,
			"Block",
			V(h * 0.05, width * 1.2, h * 0.035),
			g * CF(0, width * 0.3, -h * 0.07 - out),
			w.hilt,
			PLAIN
		)
		add(ctx, anchor, "Block", V(h * 0.03, width, length), g * CF(0, width * 0.35, mid), w.blade, metal(w))
		add(
			ctx,
			anchor,
			"Block",
			V(h * 0.032, h * 0.02, length * 0.96),
			g * CF(0, width * 0.35 - width / 2, mid),
			w.edge or w.blade,
			metal(w)
		)
		for i = 1, 3 do -- a jagged back edge
			local z = mid + length * (0.3 - (i - 1) * 0.25)
			add(
				ctx,
				anchor,
				"Wedge",
				V(h * 0.03, h * 0.045, h * 0.07),
				g * CF(0, width * 0.85 + h * 0.02, z),
				w.blade,
				{ plain = true, fine = true }
			)
		end
	end,
	greatswordBack = function(ctx: Context, w: any)
		local h, b = ctx.h, ctx.body
		local length, width = h * 0.78, h * 0.15
		local frame = CF(h * 0.02, b.torsoHeight * 0.5, b.torsoDepth / 2 + h * 0.03) * turn(0, 0, -28)
		add(ctx, "hips", "Block", V(width, length, h * 0.025), frame, w.blade, metal(w))
		add(
			ctx,
			"hips",
			"Block",
			V(h * 0.02, length * 0.96, h * 0.03),
			frame * CF(width / 2, 0, 0),
			w.edge or w.blade,
			metal(w)
		)
		add(
			ctx,
			"hips",
			"Block",
			V(h * 0.04, h * 0.15, h * 0.04),
			frame * CF(-width * 0.2, length / 2 + h * 0.075, 0),
			w.hilt,
			PLAIN
		)
		if w.cloth then
			local pommel = frame * CF(-width * 0.2, length / 2 + h * 0.15, 0)
			add(
				ctx,
				"hips",
				"Block",
				V(h * 0.03, h * 0.28, h * 0.008),
				CF(pommel.Position) * turn(0, 0, 60) * CF(0, -h * 0.14, 0),
				w.cloth,
				PLAIN
			)
		end
	end,
	dagger = function(ctx: Context, w: any, anchor: string)
		local h, g = ctx.h, grip(ctx)
		local length = (w.length or 0.17) * h
		local direction = if w.reverse then 1 else -1
		local hilt = (w.hiltLength or (if ctx.fists then 0.22 else 0.08)) * h
		add(ctx, anchor, "Block", V(h * 0.03, h * 0.034, hilt), g, w.hilt, PLAIN)
		add(
			ctx,
			anchor,
			"Block",
			V(h * 0.014, h * 0.034, length),
			g * CF(0, 0, direction * (hilt / 2 + length / 2)),
			w.blade,
			metal(w)
		)
	end,
	thinBlade = function(ctx: Context, w: any, anchor: string)
		local h, g = ctx.h, grip(ctx)
		local length = (w.length or 0.42) * h
		local direction = if w.reverse then 1 else -1
		local handle = if ctx.fists then h * 0.22 else h * 0.1
		add(ctx, anchor, "Block", V(h * 0.045, h * 0.06, handle), g, w.handle, PLAIN)
		add(
			ctx,
			anchor,
			"Block",
			V(h * 0.01, h * 0.04, length),
			g * CF(0, 0, direction * (handle / 2 + length / 2)),
			w.blade,
			metal(w)
		)
	end,
	staff = function(ctx: Context, w: any, anchor: string)
		local h, g = ctx.h, grip(ctx)
		local length = (w.length or 0.95) * h
		add(ctx, anchor, "Block", V(h * 0.03, length, h * 0.03), g * CF(0, length * 0.25, 0), w.shaft, PLAIN)
		-- a gold crescent around a red orb, open at the bottom where the shaft comes in
		local radius = h * 0.1
		local center = g * CF(0, length * 0.75 + radius, 0)
		local segment = 2 * math.pi * radius * 50 / 360 * 1.1
		for i = 0, 5 do
			local a = -30 + 50 * i
			local at = center * CF(radius * math.cos(rad(a)), radius * math.sin(rad(a)), 0) * turn(0, 0, a + 90)
			add(ctx, anchor, "Block", V(segment, h * 0.03, h * 0.03), at, w.head, { plain = true, material = "Metal" })
		end
		add(ctx, anchor, "Ball", Vector3.one * h * 0.1, center, w.orb, { plain = true, material = "Neon" })
	end,
	rod = function(ctx: Context, w: any, anchor: string)
		local h = ctx.h
		local length = (w.length or 0.9) * h
		local frame = grip(ctx) * turn(40, 0, 0)
		add(
			ctx,
			anchor,
			"Block",
			V(h * 0.018, h * 0.018, length),
			frame * CF(0, 0, -length / 2 + h * 0.06),
			w.shaft,
			PLAIN
		)
		local tip = frame * CF(0, 0, -length + h * 0.06) * turn(-40, 0, 0)
		add(ctx, anchor, "Block", V(h * 0.006, h * 0.3, h * 0.006), tip * CF(0, -h * 0.15, 0), w.line, PLAIN)
		add(ctx, anchor, "Ball", Vector3.one * h * 0.055, tip * CF(0, -h * 0.3, 0), w.float, PLAIN)
	end,
	-- A big grenade-shaped gauntlet over the fist and forearm: a round shell, a band around it and a
	-- gold pin on top.
	gauntlet = function(ctx: Context, w: any, anchor: string)
		local h = ctx.h
		local size = (w.size or (if ctx.fists then 0.3 else 0.2)) * h
		local center = CF(0, size * 0.3, -size * 0.05)
		add(ctx, anchor, "Ball", Vector3.one * size, center, w.color, { plain = true, material = "Metal" })
		add(
			ctx,
			anchor,
			"Cylinder",
			V(size * 0.16, size * 1.04, size * 1.04),
			center * turn(0, 0, 90),
			w.band or w.color,
			PLAIN
		)
		add(
			ctx,
			anchor,
			"Block",
			V(size * 0.12, size * 0.2, size * 0.3),
			center * CF(0, size * 0.52, 0),
			w.pin or w.color,
			{ plain = true, fine = true }
		)
	end,
	ball = function(ctx: Context, w: any, anchor: string)
		local h = ctx.h
		add(
			ctx,
			anchor,
			"Ball",
			Vector3.one * h * (w.size or 0.085),
			CF(0, -h * 0.03, -h * (if ctx.fists then 0.15 else 0.06)),
			w.color,
			metal(w)
		)
	end,
	vial = function(ctx: Context, w: any, anchor: string)
		local h = ctx.h
		add(
			ctx,
			anchor,
			"Block",
			V(h * 0.04, h * 0.075, h * 0.04),
			CF(0, -h * 0.02, -h * (if ctx.fists then 0.13 else 0.06)),
			w.color,
			{ plain = true, material = "Glass" }
		)
		add(
			ctx,
			anchor,
			"Block",
			V(h * 0.03, h * 0.02, h * 0.03),
			CF(0, h * 0.027, -h * (if ctx.fists then 0.13 else 0.06)),
			Color3.fromRGB(150, 110, 70),
			FINE_PLAIN
		)
	end,
	basket = function(ctx: Context, w: any)
		local h, b = ctx.h, ctx.body
		local at = CF(0, b.torsoHeight * 0.55, b.torsoDepth / 2 + h * 0.055)
		add(ctx, "hips", "Block", V(h * 0.2, h * 0.15, h * 0.11), at, w.color, { material = "Wood" })
		add(
			ctx,
			"hips",
			"Block",
			V(h * 0.16, h * 0.05, h * 0.08),
			at * CF(0, h * 0.09, 0),
			Color3.fromRGB(110, 170, 90),
			FINE
		)
	end,
}

-- A weapon with `drawn = true` is held only while attacking or casting (a quick-draw from a sheath
-- drawn elsewhere); its specs are marked `drawn`.
local function weapons(ctx: Context)
	for _, w in ctx.look.weapons or {} do
		local build = LookKit.WEAPONS[w.kind]
		assert(build, "unknown weapon kind " .. tostring(w.kind))
		local first = #ctx.specs + 1
		if w.anchor then
			local angles = w.turn or Vector3.zero
			ctx.grip = CF((w.at or Vector3.zero) * ctx.h) * turn(angles.X, angles.Y, angles.Z)
			build(ctx, w, w.anchor)
			ctx.grip = nil
		elseif w.hand == "both" then
			build(ctx, w, "leftHand")
			build(ctx, w, "rightHand")
		else
			build(ctx, w, (w.hand or "right") .. "Hand")
		end
		if w.drawn then
			for i = first, #ctx.specs do
				ctx.specs[i].drawn = true
			end
		end
	end
end

-- Only the block-built pieces of `outfit` (UnitLookConfig fields: coat, collar, belt, sash, scarf,
-- tie, cravat, buttons, bands, emblems, gearBoxes, tendrils, extras, hair, headwear; `torso` and
-- `sleeve` as for a look), for figures whose body comes from elsewhere: a catalog avatar
-- (UnitAvatarConfig `outfit`) adding what its catalog items lack. Hair and headwear are sized to
-- the avatar's head as drawn (`headVisual` in the body, else its head size).
function LookKit.outfitSpecs(outfit: any, body: { [string]: number }, height: number, low: boolean?): { Spec }
	local ctx: Context = {
		specs = {},
		look = outfit,
		body = body,
		h = height,
		hs = body.headVisual or body.headSize,
		low = low == true,
		thin = height * 0.012,
	}
	hair(ctx)
	headwear(ctx)
	coat(ctx)
	accessories(ctx)
	return ctx.specs
end

-- Only the weapons of `weapons` (UnitLookConfig `weapons` format), for figures whose body comes
-- from elsewhere (catalog avatars, UnitAvatarConfig).
function LookKit.weaponSpecs(weaponList: { any }, body: { [string]: number }, height: number, low: boolean?): { Spec }
	local ctx: Context = {
		specs = {},
		look = { weapons = weaponList },
		body = body,
		h = height,
		hs = body.headSize,
		low = low == true,
		thin = height * 0.012,
		fists = true,
	}
	weapons(ctx)
	return ctx.specs
end

-- The parts of `look` (a UnitLookConfig entry) for a figure with proportions `body` (studs) and
-- height `height`. `low` leaves out fine details.
function LookKit.specs(look: any, body: { [string]: number }, height: number, low: boolean?): { Spec }
	local ctx: Context = {
		specs = {},
		look = look,
		body = body,
		h = height,
		hs = body.headSize,
		low = low == true,
		thin = height * 0.012,
	}
	buildBody(ctx)
	face(ctx)
	hair(ctx)
	headwear(ctx)
	coat(ctx)
	accessories(ctx)
	weapons(ctx)
	return ctx.specs
end

return LookKit
