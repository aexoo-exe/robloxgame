-- The layered VFX recipe for ultimates (first built for snapfire): reusable layers drawn with the kit
-- textures through ImpactEffects.emit / light / shape, each tinted by a ColorSequence over its life
-- (the textures are white masks), sized from the real area, with tuned defaults (DEFAULTS) so every
-- ultimate built from it reads the same: a short, small white-hot core; an explosion (or, for
-- non-fire themes, a glow sheet) with darker edges and modest Brightness (units stay readable inside
-- it); a short, tight light flash; small smoke puffs that rise, spread and fade; many bright streak
-- sparks arcing down.
-- Themes (VfxRecipe.themes, VfxRecipe.energy) give each layer its palette: fire, steam (a fire
-- blast with pale steam instead of smoke), and energy from a unit's own colors (ki, magic, void).
-- Tiers (TIERS, from run.tier) scale size, side blasts and the aftermath: tier 1-2 smaller and
-- quicker, tier 4-5 bigger, more layers, longer aftermath.
-- Layers marked "extra" are skipped with ReducedEffects (run.reduced). Presentation only.

local FxKit = require(script.Parent.FxKit)
local ImpactEffects = require(script.Parent.ImpactEffects)

local VfxRecipe = {}

local rgb = Color3.fromRGB
local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)

-- A ColorSequence from { { time, Color3 }, ... }.
function VfxRecipe.colors(points: { any }): ColorSequence
	local keys = {}
	for _, point in points do
		table.insert(keys, ColorSequenceKeypoint.new(point[1], point[2]))
	end
	return ColorSequence.new(keys)
end
-- A NumberSequence from { { time, value }, ... }.
function VfxRecipe.curve(points: { { number } }): NumberSequence
	local keys = {}
	for _, point in points do
		table.insert(keys, NumberSequenceKeypoint.new(point[1], point[2]))
	end
	return NumberSequence.new(keys)
end
local colors, curve = VfxRecipe.colors, VfxRecipe.curve

-- Palettes over a particle's life.
VfxRecipe.palettes = {
	-- ground flames: white-yellow core -> orange -> deep red
	fire = colors({
		{ 0, rgb(255, 250, 225) },
		{ 0.2, rgb(255, 205, 90) },
		{ 0.55, rgb(255, 115, 30) },
		{ 1, rgb(140, 25, 10) },
	}),
	-- the explosion sheet: yellow-orange -> orange -> red edges (no white: the core flash is the white)
	explosion = colors({
		{ 0, rgb(255, 215, 110) },
		{ 0.3, rgb(255, 145, 45) },
		{ 0.65, rgb(220, 60, 20) },
		{ 1, rgb(110, 20, 10) },
	}),
	-- the bigger, redder variant
	explosionRed = colors({
		{ 0, rgb(255, 180, 90) },
		{ 0.25, rgb(250, 110, 35) },
		{ 0.6, rgb(210, 40, 18) },
		{ 1, rgb(90, 12, 8) },
	}),
	spark = colors({ { 0, rgb(255, 250, 200) }, { 0.35, rgb(255, 205, 80) }, { 1, rgb(255, 140, 40) } }),
	ember = colors({ { 0, rgb(255, 220, 140) }, { 0.5, rgb(255, 130, 40) }, { 1, rgb(170, 40, 15) } }),
	-- smoke: dark gray, never white and never pure black
	smoke = colors({ { 0, rgb(88, 80, 74) }, { 0.5, rgb(62, 57, 54) }, { 1, rgb(44, 41, 40) } }),
	-- steam: pale warm gray, a little orange from the heat at first (drawn more transparent)
	steam = colors({ { 0, rgb(255, 205, 165) }, { 0.3, rgb(205, 195, 188) }, { 1, rgb(150, 146, 144) } }),
	flash = colors({ { 0, rgb(255, 255, 255) }, { 1, rgb(255, 225, 150) } }),
}
local P = VfxRecipe.palettes

-- Tuned defaults (studs scale with the area radius `r` or the unit scale `s` where noted).
VfxRecipe.DEFAULTS = {
	-- the white-hot core at a burst: small and short
	core = { size = { 0.8, 1.25 }, lifetime = { 0.08, 0.12 }, brightness = 2.5 }, -- x r
	-- the explosion sheet: grows to ~2 r, modest brightness so units read inside it
	explosion = { size = { 1, 1.7, 2 }, lifetime = 0.55, brightness = 1.2, lightEmission = 0.6, side = 0.6 }, -- x r
	-- the light flash: tight and quick
	light = { brightness = 4.5, range = 1.5, seconds = 0.3 }, -- range x r
	-- the ground shockwave
	shock = { size = { 0.5, 2, 2.4 }, lifetime = 0.35, brightness = 1.8 }, -- x r
	-- sparks flung out, arcing down
	sparks = {
		count = 36,
		size = 0.9,
		speed = { 18, 30 },
		spread = 70,
		drag = 2.5,
		gravity = 40,
		lifetime = { 0.6, 1 },
		brightness = 3.5,
	},
	-- ground flames across the area
	flames = { size = 1.8, every = 0.07, seconds = 1, perStep = 2, reach = 0.9 }, -- size x s, reach x r
	-- smoke: small puffs that rise and spread
	smoke = { puffs = 8, reducedPuffs = 3, size = { 0.35, 0.7, 0.9 }, lifetime = { 1, 1.4 }, startTransparency = 0.4 }, -- x r
	embers = { count = 16, size = 0.3 }, -- size x s
}
local D = VfxRecipe.DEFAULTS

-- Per tier (UltimateConfig tier 1-5): `k` scales sizes and counts, `sides` side blasts, `after`
-- multiplies the aftermath's length and smoke, `light` the light flash.
VfxRecipe.TIERS = {
	{ k = 0.75, sides = 0, after = 0.5, light = 0.7 },
	{ k = 0.85, sides = 1, after = 0.7, light = 0.85 },
	{ k = 1, sides = 3, after = 1, light = 1 },
	{ k = 1.15, sides = 4, after = 1.3, light = 1.1 },
	{ k = 1.3, sides = 5, after = 1.6, light = 1.2 },
}
local function tierOf(run, tier: number?)
	return VfxRecipe.TIERS[math.clamp(tier or (run and run.tier) or 3, 1, 5)]
end

export type Theme = {
	core: ColorSequence,
	blast: ColorSequence, -- the explosion (or glow) sheet
	blastBig: ColorSequence,
	blastUsage: string, -- "explosion" (a fireball flipbook) or "glow" (a soft energy sheet)
	spark: ColorSequence,
	ember: ColorSequence,
	smoke: ColorSequence,
	smokeTransparency: number?, -- start transparency of the smoke puffs (default DEFAULTS.smoke)
	edge: Color3, -- the shockwave's outer color
	edgeBig: Color3,
	light: Color3,
	lightBig: Color3,
	flames: ColorSequence?, -- ground flames in the aftermath (nil: drifting embers instead)
	scorch: Color3?, -- the burnt patch's color (nil: no scorch)
}

VfxRecipe.themes = {
	fire = {
		core = P.flash,
		blast = P.explosion,
		blastBig = P.explosionRed,
		blastUsage = "explosion",
		spark = P.spark,
		ember = P.ember,
		smoke = P.smoke,
		edge = rgb(255, 120, 40),
		edgeBig = rgb(230, 60, 25),
		light = rgb(255, 160, 70),
		lightBig = rgb(255, 110, 50),
		flames = P.fire,
		scorch = rgb(40, 30, 25),
	} :: Theme,
	-- an eruption: a fire blast and flames, but pale steam rolling out instead of dark smoke
	steam = {
		core = P.flash,
		blast = P.explosion,
		blastBig = P.explosionRed,
		blastUsage = "explosion",
		spark = P.spark,
		ember = P.ember,
		smoke = P.steam,
		smokeTransparency = 0.55,
		edge = rgb(255, 140, 60),
		edgeBig = rgb(240, 80, 30),
		light = rgb(255, 165, 80),
		lightBig = rgb(255, 120, 55),
		flames = P.fire,
		scorch = rgb(36, 26, 22),
	} :: Theme,
}

-- An energy theme from a unit's colors (ki, magic, void...): a white core, a glow sheet running
-- from pale `color` to deep `color`, sparks and embers from `accent` to `color`, dark `color`-tinted
-- smoke, no flames or scorch (the residue is drifting embers).
function VfxRecipe.energy(color: Color3, accent: Color3?): Theme
	local hot = accent or color:Lerp(WHITE, 0.5)
	local deep = color:Lerp(BLACK, 0.55)
	return {
		core = colors({ { 0, WHITE }, { 1, hot:Lerp(WHITE, 0.4) } }),
		blast = colors({ { 0, hot:Lerp(WHITE, 0.35) }, { 0.3, color:Lerp(WHITE, 0.15) }, { 0.7, color }, { 1, deep } }),
		blastBig = colors({
			{ 0, hot },
			{ 0.25, color },
			{ 0.65, color:Lerp(BLACK, 0.3) },
			{ 1, deep:Lerp(BLACK, 0.3) },
		}),
		blastUsage = "glow",
		spark = colors({ { 0, WHITE }, { 0.35, hot }, { 1, color } }),
		ember = colors({ { 0, hot }, { 0.5, color }, { 1, deep } }),
		smoke = colors({
			{ 0, color:Lerp(rgb(70, 66, 72), 0.7) },
			{ 1, deep:Lerp(rgb(40, 38, 42), 0.6) },
		}),
		smokeTransparency = 0.5,
		edge = color,
		edgeBig = color:Lerp(BLACK, 0.2),
		light = color:Lerp(WHITE, 0.3),
		lightBig = color,
		flames = nil,
		scorch = nil,
	}
end

local function themeOf(theme: Theme?): Theme
	return theme or VfxRecipe.themes.fire
end

-- A random point within `radius` of `center` on the ground.
function VfxRecipe.within(center: Vector3, radius: number): Vector3
	local angle = math.random() * math.pi * 2
	local r = radius * math.sqrt(math.random())
	return center + Vector3.new(math.cos(angle) * r, 0, math.sin(angle) * r)
end
local within = VfxRecipe.within

-- A burnt patch (the kit's ground_scorch, soot-dark), `radius` studs, fading over the last half of
-- `seconds`; soft dark discs without the kit.
function VfxRecipe.scorch(at: Vector3, radius: number, seconds: number, color: Color3?)
	local tint = color or rgb(40, 30, 25)
	local texture = FxKit.textured("scorch", tint, "plane")
	if not texture then
		FxKit.mark(at, tint, tint, radius, "scorch", seconds)
		return
	end
	local base = CFrame.new(at + Vector3.new(0, 0.07, 0)) * CFrame.Angles(0, math.random() * math.pi * 2, 0)
	ImpactEffects.shape("Block", tint, seconds, function(part, progress)
		local grown = radius * 2.2 * (0.6 + 0.4 * math.min(1, progress * 8))
		part.Size = Vector3.new(grown, 0.05, grown)
		part.CFrame = base
		part.Transparency = 0.05 + 0.95 * math.max(0, progress - 0.5) * 2
	end, nil, nil, texture, true)
end

-- A light flash at `at` for an area of `radius` (DEFAULTS.light), `k` times stronger. Extra.
function VfxRecipe.light(run, at: Vector3, radius: number, color: Color3, k: number?)
	if run.reduced then
		return
	end
	local config = D.light
	ImpactEffects.light(at, color, config.brightness * (k or 1), math.max(4, radius * config.range), config.seconds)
end

-- The white-hot core: one short, small starburst frame.
function VfxRecipe.core(at: Vector3, radius: number, k: number?, palette: ColorSequence?)
	local config = D.core
	local scale = k or 1
	ImpactEffects.emit(at, {
		usage = "critFlash",
		count = 1,
		color = palette or P.flash,
		size = curve({ { 0, radius * config.size[1] * scale }, { 1, radius * config.size[2] * scale } }),
		transparency = curve({ { 0, 0 }, { 0.5, 0.35 }, { 1, 1 } }),
		lifetime = config.lifetime,
		lightEmission = 1,
		brightness = config.brightness,
	})
end

-- One explosion sheet at `at`, `size` times DEFAULTS.explosion.size studs: the one-shot explosion
-- flipbook, or (`usage` "glow") a soft energy sheet.
function VfxRecipe.explosion(at: Vector3, size: number, palette: ColorSequence?, usage: string?)
	local config = D.explosion
	local glow = usage == "glow"
	ImpactEffects.emit(at, {
		usage = usage or "explosion",
		count = 1,
		color = palette or P.explosion,
		size = curve({ { 0, size * config.size[1] }, { 0.2, size * config.size[2] }, { 1, size * config.size[3] } }),
		-- a glow sheet has no frames of its own: it thins out sooner
		transparency = if glow
			then curve({ { 0, 0.15 }, { 0.4, 0.35 }, { 1, 1 } })
			else curve({ { 0, 0.1 }, { 0.7, 0.2 }, { 1, 1 } }),
		lifetime = { config.lifetime, config.lifetime },
		lightEmission = if glow then 1 else config.lightEmission,
		brightness = config.brightness,
		rotSpeed = if glow then { -40, 40 } else nil,
	})
end

-- The thick ring flat on the ground, racing out then fading.
function VfxRecipe.shock(at: Vector3, radius: number, edge: Color3, k: number?)
	local config = D.shock
	local scale = k or 1
	ImpactEffects.emit(at + Vector3.new(0, 0.15, 0), {
		usage = "shock",
		count = 1,
		color = colors({ { 0, edge:Lerp(WHITE, 0.6) }, { 1, edge } }),
		size = curve({
			{ 0, radius * config.size[1] },
			{ 0.35, radius * config.size[2] * scale },
			{ 1, radius * config.size[3] * scale },
		}),
		transparency = curve({ { 0, 0 }, { 0.4, 0.35 }, { 1, 1 } }),
		lifetime = { config.lifetime, config.lifetime },
		lightEmission = 1,
		brightness = config.brightness,
		flat = true,
	})
end

-- Streak sparks flung out from `at`, turned along their flight, arcing down.
function VfxRecipe.sparks(at: Vector3, k: number?, count: number?, palette: ColorSequence?, direction: Vector3?)
	local config = D.sparks
	local scale = k or 1
	ImpactEffects.emit(at, {
		usage = "sparks",
		count = math.max(1, math.floor((count or config.count) * scale)),
		color = palette or P.spark,
		size = curve({ { 0, config.size * scale }, { 0.6, config.size * 0.65 * scale }, { 1, 0 } }),
		transparency = curve({ { 0, 0 }, { 0.75, 0.1 }, { 1, 1 } }),
		lifetime = config.lifetime,
		speed = config.speed,
		spread = config.spread,
		direction = direction,
		drag = config.drag,
		acceleration = Vector3.new(0, -config.gravity, 0),
		lightEmission = 1,
		brightness = config.brightness,
		stretch = true,
	})
end

-- Ground flames: `count` fire-flipbook flames standing at `at`, `size` studs.
function VfxRecipe.flames(at: Vector3, count: number, size: number, palette: ColorSequence?)
	ImpactEffects.emit(at, {
		usage = "fire",
		count = count,
		color = palette or P.fire,
		size = curve({ { 0, size * 0.45 }, { 0.15, size }, { 0.7, size * 0.85 }, { 1, size * 0.4 } }),
		transparency = curve({ { 0, 0.15 }, { 0.1, 0 }, { 0.65, 0.2 }, { 1, 1 } }),
		lifetime = { 0.4, 0.65 },
		speed = { 1, 2.5 },
		spread = 12,
		acceleration = Vector3.new(0, 3, 0),
		lightEmission = 1,
		brightness = 2.2,
		rotation = { -8, 8 },
	})
end

-- A ring of `count` flames standing on a circle of `radius` around `center` (a ring of fire).
function VfxRecipe.flameRing(center: Vector3, radius: number, count: number, size: number, palette: ColorSequence?)
	for i = 1, count do
		local angle = (i / count) * math.pi * 2 + math.random() * 0.3
		VfxRecipe.flames(center + Vector3.new(math.cos(angle), 0.1, math.sin(angle)) * radius, 1, size, palette)
	end
end

-- Small puffs: `count` of them from points across the area, rising and spreading outward, fading by
-- ~1.4 s.
function VfxRecipe.smoke(center: Vector3, radius: number, count: number, palette: ColorSequence?, start: number?)
	local config = D.smoke
	local first = start or config.startTransparency
	for i = 1, count do
		local at = within(center, radius * 0.6)
		local out = at - center
		local heading = Vector3.new(out.X, 0, out.Z)
		heading = if heading.Magnitude > 1e-3 then heading.Unit else Vector3.xAxis
		ImpactEffects.emit(at + Vector3.new(0, 0.8, 0), {
			-- alternate the puff flipbook and the soft puff so they do not look stamped
			usage = if i % 2 == 0 then "smokePuff" else "smoke",
			count = 1,
			color = palette or P.smoke,
			size = curve({
				{ 0, radius * config.size[1] },
				{ 0.35, radius * config.size[2] },
				{ 1, radius * config.size[3] },
			}),
			transparency = curve({ { 0, 1 }, { 0.08, first }, { 0.45, math.min(1, first + 0.15) }, { 1, 1 } }),
			lifetime = config.lifetime,
			speed = { 2, 3.5 },
			spread = 25,
			direction = (Vector3.yAxis * 1.4 + heading).Unit,
			drag = 1,
			acceleration = Vector3.new(0, 1, 0),
			lightEmission = 0,
			rotSpeed = { -30, 30 },
			zOffset = -0.5,
		})
	end
end

-- Embers drifting up from `at`. Extra.
function VfxRecipe.embers(run, at: Vector3, s: number, palette: ColorSequence?, count: number?)
	if run.reduced then
		return
	end
	local config = D.embers
	ImpactEffects.emit(at, {
		usage = "ember",
		count = count or config.count,
		color = palette or P.ember,
		size = curve({ { 0, config.size * s }, { 0.5, config.size * 0.75 * s }, { 1, 0 } }),
		transparency = curve({ { 0, 0 }, { 0.8, 0.2 }, { 1, 1 } }),
		lifetime = { 1, 1.7 },
		speed = { 2, 5 },
		spread = 60,
		drag = 1.2,
		acceleration = Vector3.new(0, 3, 0),
		lightEmission = 1,
		brightness = 3,
	})
end

export type Options = { big: boolean?, theme: Theme?, tier: number? }

local function optionsOf(opts: (Options | boolean)?): Options
	if type(opts) == "boolean" then
		return { big = opts }
	end
	return (opts :: Options?) or {}
end

-- A burst over an area: core flash, explosion or glow sheet (plus side blasts by tier: extra), ground
-- shockwave, sparks, light, scorch (fire themes), shake. `opts.big`: bigger (x1.35), darker or
-- redder; `opts.theme` (default fire); `opts.tier` (default the run's).
function VfxRecipe.burst(run, center: Vector3, radius: number, opts: (Options | boolean)?)
	local o = optionsOf(opts)
	local theme = themeOf(o.theme)
	local tier = tierOf(run, o.tier)
	local k = (if o.big then 1.35 else 1) * tier.k
	local blast = if o.big then theme.blastBig else theme.blast
	local air = center + Vector3.new(0, 1.2, 0)
	VfxRecipe.core(air, radius, k, theme.core)
	VfxRecipe.explosion(air, radius * k, blast, theme.blastUsage)
	if not run.reduced then
		for i = 1, tier.sides do
			run:at(run:designTime() + 0.03 * i, function()
				VfxRecipe.explosion(
					within(center, radius * 0.7) + Vector3.new(0, 0.8, 0),
					radius * D.explosion.side * k,
					blast,
					theme.blastUsage
				)
			end)
		end
	end
	VfxRecipe.shock(center, radius, if o.big then theme.edgeBig else theme.edge, k)
	VfxRecipe.sparks(air, k, nil, theme.spark)
	VfxRecipe.light(run, air, radius, if o.big then theme.lightBig else theme.light, k * tier.light)
	if theme.scorch then
		VfxRecipe.scorch(center, radius * k, 1.8 * tier.after, theme.scorch)
	end
	run:shake((if o.big then 0.22 else 0.16) * tier.k)
end

-- The aftermath of a burst at design time now: the lingering element across the area (ground
-- flames for themes with flames, else drifting embers), smoke or steam puffs in two waves, embers
-- drifting up. Length and smoke scale with the tier.
function VfxRecipe.aftermath(run, center: Vector3, radius: number, opts: Options?)
	local o = opts or {}
	local theme = themeOf(o.theme)
	local tier = tierOf(run, o.tier)
	local s = run:scale()
	local now = run:designTime()
	local flames = D.flames
	if theme.flames then
		local steps = math.max(2, math.floor(flames.seconds * tier.after / flames.every))
		-- a ring of flames at once, then more across the area
		VfxRecipe.flameRing(center, radius * 0.6, 4, flames.size * s * tier.k, theme.flames)
		for j = 0, steps - 1 do
			run:at(now + 0.05 + j * flames.every, function()
				VfxRecipe.flames(
					within(center, radius * flames.reach),
					flames.perStep,
					flames.size * s * tier.k,
					theme.flames
				)
			end)
		end
	else
		-- the residue of an energy blast: embers rising off the area in waves
		for j = 0, math.max(1, math.floor(3 * tier.after)) - 1 do
			run:at(now + 0.1 + j * 0.25, function()
				VfxRecipe.embers(run, within(center, radius * 0.6) + Vector3.new(0, 0.5, 0), s, theme.ember, 8)
			end)
		end
	end
	local puffs = math.max(
		1,
		math.floor((if run.reduced then D.smoke.reducedPuffs else D.smoke.puffs) * math.min(tier.after, 1.4))
	)
	local first = math.ceil(puffs * 0.6)
	run:at(now + 0.1, function()
		VfxRecipe.smoke(center, radius, first, theme.smoke, theme.smokeTransparency)
	end)
	if puffs > first then
		run:at(now + 0.3, function()
			VfxRecipe.smoke(center, radius, puffs - first, theme.smoke, theme.smokeTransparency)
		end)
	end
	run:at(now + 0.2, function()
		VfxRecipe.embers(run, center + Vector3.new(0, 0.8, 0), s, theme.ember)
	end)
end

-- A small pop at `at` (a snap, a palm, a muzzle): a one-frame flash, a pop of stars, a little light,
-- a tiny kick. `size` studs across.
function VfxRecipe.pop(run, at: Vector3, size: number, theme: Theme?)
	local t = themeOf(theme)
	ImpactEffects.emit(at, {
		usage = "flash",
		count = 1,
		color = t.core,
		size = curve({ { 0, size }, { 1, size * 1.35 } }),
		transparency = curve({ { 0, 0 }, { 1, 1 } }),
		lifetime = { 0.07, 0.08 },
		lightEmission = 1,
		brightness = 3,
	})
	ImpactEffects.emit(at, {
		usage = "star",
		count = 6,
		color = t.spark,
		size = curve({ { 0, size * 0.35 }, { 1, 0 } }),
		transparency = curve({ { 0, 0 }, { 1, 1 } }),
		lifetime = { 0.15, 0.25 },
		speed = { 7, 12 },
		drag = 8,
		lightEmission = 1,
		brightness = 3,
	})
	if not run.reduced then
		ImpactEffects.light(at, t.light:Lerp(WHITE, 0.4), 3, size * 4.3, 0.1)
	end
	run:shake(0.04)
end

-- A hit on one unit at `at` (no area): a small core, a small blast sheet, sparks along `direction`,
-- a light. `size` studs (~ the unit's height).
function VfxRecipe.hit(run, at: Vector3, size: number, theme: Theme?, direction: Vector3?)
	local t = themeOf(theme)
	local radius = size * 0.6
	VfxRecipe.core(at, radius, 1, t.core)
	VfxRecipe.explosion(at, radius * 0.8, t.blast, t.blastUsage)
	VfxRecipe.sparks(at, 0.6, 24, t.spark, direction)
	VfxRecipe.light(run, at, radius, t.light, 0.7)
end

export type TrailOptions = {
	theme: Theme?,
	steps: number?, -- default 6
	from: number?, -- design time of the first step (default now)
	span: number?, -- design seconds from the first to the last step (default 0.15)
	size: number?, -- flame size in studs (default 1.1)
	sparks: boolean?, -- streak sparks at each step (default true; extra)
	scorch: boolean?, -- scorch every other step (default: the theme's)
}

-- A trail racing from `a` to `b` on the ground (a fuse, a dash, a fiery kick): flames and streak
-- sparks at each step, scorch left behind.
function VfxRecipe.trail(run, a: Vector3, b: Vector3, opts: TrailOptions?)
	local o = opts or {}
	local t = themeOf(o.theme)
	local steps = o.steps or 6
	local start = o.from or run:designTime()
	local span = o.span or 0.15
	local size = o.size or 1.1
	local scorched = if o.scorch == nil then t.scorch ~= nil else o.scorch
	for i = 1, steps do
		run:at(start + span * i / steps, function()
			local at = a:Lerp(b, i / steps)
			if t.flames then
				VfxRecipe.flames(at + Vector3.new(0, 0.1, 0), 2, size, t.flames)
			else
				VfxRecipe.embers(run, at + Vector3.new(0, 0.3, 0), size, t.ember, 4)
			end
			if o.sparks ~= false and not run.reduced then
				VfxRecipe.sparks(at + Vector3.new(0, 0.2, 0), 0.5 * size / 1.1, 8, t.spark)
			end
			if scorched and i % 2 == 0 then
				VfxRecipe.scorch(at, 0.4 * size, 1.4, t.scorch)
			end
		end)
	end
end

return VfxRecipe
