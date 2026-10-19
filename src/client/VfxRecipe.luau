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

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RenderConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("RenderConfig"))

local FxKit = require(script.Parent.FxKit)
local ImpactEffects = require(script.Parent.ImpactEffects)
local Vfx = require(script.Parent.Vfx)

local VfxRecipe = {}

local UNIT_HEIGHT = RenderConfig.unitSize.Y
VfxRecipe.UNIT_HEIGHT = UNIT_HEIGHT
local UNIT_WIDTH = RenderConfig.unitSize.X
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
	-- ground flames: saturated yellow-orange -> orange -> deep red (no white or cream: on the gray
	-- floor a pale start read as washed-out cream flames)
	fire = colors({
		{ 0, rgb(255, 190, 50) },
		{ 0.2, rgb(255, 145, 25) },
		{ 0.55, rgb(240, 80, 15) },
		{ 1, rgb(130, 20, 8) },
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
	-- steam: white -> pale gray (drawn more transparent)
	steam = colors({ { 0, rgb(250, 248, 245) }, { 0.4, rgb(222, 222, 224) }, { 1, rgb(170, 172, 176) } }),
	-- a steam blast: a faint warm tint at the very start only, then white -> pale gray
	steamBlast = colors({
		{ 0, rgb(255, 238, 220) },
		{ 0.15, rgb(250, 248, 245) },
		{ 0.6, rgb(220, 221, 224) },
		{ 1, rgb(175, 177, 181) },
	}),
	steamCore = colors({ { 0, rgb(255, 255, 255) }, { 1, rgb(255, 238, 220) } }),
	droplet = colors({ { 0, rgb(255, 255, 255) }, { 1, rgb(205, 215, 225) } }),
	-- dust kicked up by a slam: warm tan -> gray
	dust = colors({ { 0, rgb(205, 190, 165) }, { 0.5, rgb(170, 160, 145) }, { 1, rgb(130, 125, 118) } }),
	-- the darker cloud of a big impact
	dustDark = colors({ { 0, rgb(180, 165, 140) }, { 0.5, rgb(130, 120, 108) }, { 1, rgb(92, 86, 80) } }),
	-- spray and mist off water: white -> pale aqua
	mist = colors({ { 0, rgb(245, 252, 255) }, { 0.5, rgb(200, 230, 240) }, { 1, rgb(160, 200, 215) } }),
	-- warm from the start (a white start at full light read as a cream ball), then orange
	flash = colors({ { 0, rgb(255, 210, 110) }, { 0.15, rgb(255, 185, 80) }, { 1, rgb(255, 140, 50) } }),
}
local P = VfxRecipe.palettes

-- Glows around a body or a burst (the core flash, glow and cloud sheets, camera-facing rings): never
-- wider than this many unit heights. Wider, they read as a giant cream sphere or a see-through bubble
-- filling the close camera.
local GLOW_CAP = 1.5
VfxRecipe.GLOW_CAP = GLOW_CAP
local GLOW_SECONDS = 0.2 -- a glow sheet's life (the core flash is shorter)
local CORE_LIGHT = 0.6 -- the core flash's LightEmission: tinted, never cream-white at full light

-- Tuned defaults (studs scale with the area radius `r` or the unit scale `s` where noted).
VfxRecipe.DEFAULTS = {
	-- the hot core at a burst: small and short. Its size is x r, capped at `cap` unit heights (x the
	-- tier's k), never more than `maxCap` (GLOW_CAP): a big area's core must not hide the caster.
	core = { size = { 0.8, 1.25 }, lifetime = { 0.06, 0.1 }, brightness = 1.6, cap = 1.2, maxCap = GLOW_CAP },
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

-- Lightning values (studs at unit scale): arc widths, life, how often a strand re-jitters, how
-- many segments, how far kinks push sideways, strands per tier for VfxRecipe.arcs.
local LIGHTNING = {
	width = 0.9, -- arcs between two points (a dash, a spear line)
	burstWidth = 0.8, -- arcs from a burst out to the area's edge (x tier k)
	crackleWidth = 0.6, -- short arcs off a body or hand
	life = 0.35,
	jitter = 0.05, -- seconds between re-jitters
	segments = { 2, 3 }, -- the strip texture is jagged itself: 2-3 kinked segments read as a bolt
	segmentLength = 2.5, -- studs per segment, within `segments`
	push = 0.22, -- sideways push of a kink, share of the arc's length
	coreWidth = 0.2, -- the bright core, share of the width (0.4 without the kit's glow)
	minFacing = 0.5, -- end-on thinning never draws a glow narrower than this share
	strike = { size = 0.9, lifetime = 0.08 }, -- the small flash at a strike's end (x width)
	coreWhite = 0.5, -- how far the core's color goes toward white (the glow keeps the full color)
	strands = { 2, 2, 3, 4, 5 }, -- VfxRecipe.arcs by tier
}
VfxRecipe.LIGHTNING = LIGHTNING

-- Per tier (UltimateConfig tier 1-5): `k` scales sizes and counts, `sides` side blasts, `after`
-- multiplies the aftermath's length and smoke, `light` the light flash, `arcs` the lightning arcs
-- a crackling (lightning) burst throws.
-- The readability floor (tier 1-2: short, fewer layers, but every layer must read at the close
-- camera): `minSize` the smallest a burst's main layers (core, blast sheet, shock ring) start, in
-- unit widths; `glow` adds a colored glow sheet to bursts whose blast is not one already (dust,
-- mist, steam), so every cast has one clear colored glow. Main layers never start more than ~0.3
-- transparent (DEFAULTS and VfxRecipe.explosion).
VfxRecipe.TIERS = {
	{ k = 0.75, sides = 0, after = 0.5, light = 0.7, arcs = 1, minSize = 0.6, glow = true },
	{ k = 0.85, sides = 1, after = 0.7, light = 0.85, arcs = 2, minSize = 0.6, glow = true },
	{ k = 1, sides = 3, after = 1, light = 1, arcs = 3 },
	{ k = 1.15, sides = 4, after = 1.3, light = 1.1, arcs = 4 },
	{ k = 1.3, sides = 5, after = 1.6, light = 1.2, arcs = 5 },
}
local function tierOf(run, tier: number?)
	return VfxRecipe.TIERS[math.clamp(tier or (run and run.tier) or 3, 1, 5)]
end

export type Theme = {
	core: ColorSequence,
	blast: ColorSequence, -- the explosion (or glow) sheet
	blastBig: ColorSequence,
	blastUsage: string, -- "explosion" (a fireball flipbook), "glow" (a soft energy sheet), "smoke" (steam)
	blastLight: number?, -- the blast sheet's LightEmission (default DEFAULTS.explosion; 1 for glow)
	spark: ColorSequence,
	ember: ColorSequence,
	smoke: ColorSequence,
	smokeTransparency: number?, -- start transparency of the smoke puffs (default DEFAULTS.smoke)
	edge: Color3, -- the shockwave's outer color
	edgeBig: Color3,
	light: Color3,
	lightBig: Color3,
	flames: ColorSequence?, -- ground flames in the aftermath
	-- without flames, what lingers: "embers" (default), "steam" (columns, bubbling), "dust" (rolling
	-- dust, settling debris) or "splash" (bubbling, falling droplets)
	residue: string?,
	debris: Color3?, -- stone chunks thrown by a burst (impact themes)
	embers: boolean?, -- false: no embers at all
	crackle: Color3?, -- lightning themes: the arcs' color (bursts throw arcs, residue crackles)
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
	-- a steam eruption: white -> pale gray clouds (a faint warm tint at the core only), droplets
	-- for sparks, no flames, no dark smoke, no scorch; it leaves rising steam columns and bubbling
	steam = {
		core = P.steamCore,
		blast = P.steamBlast,
		blastBig = P.steamBlast,
		blastUsage = "smoke",
		blastLight = 0.1,
		spark = P.droplet,
		ember = P.droplet,
		smoke = P.steam,
		smokeTransparency = 0.5,
		edge = rgb(235, 238, 242),
		edgeBig = rgb(220, 224, 230),
		light = rgb(255, 240, 225),
		lightBig = rgb(255, 235, 215),
		flames = nil,
		residue = "steam",
		embers = false,
		scorch = nil,
	} :: Theme,
}

-- An energy theme from a unit's colors (ki, magic, void...): a white core, a glow sheet running
-- from pale `color` to deep `color`, sparks and embers from `accent` to `color`, dark `color`-tinted
-- smoke, no flames or scorch (the residue is drifting embers).
function VfxRecipe.energy(color: Color3, accent: Color3?): Theme
	local hot = accent or color:Lerp(WHITE, 0.5)
	local deep = color:Lerp(BLACK, 0.55)
	-- The core and the glow sheet start only a little paler than `color` (a white or `hot` start at
	-- full light read as a giant cream sphere around the caster).
	local lit = color:Lerp(WHITE, 0.2)
	return {
		core = colors({ { 0, lit }, { 0.5, color }, { 1, color } }),
		blast = colors({ { 0, lit }, { 0.25, color }, { 0.7, color:Lerp(BLACK, 0.25) }, { 1, deep } }),
		blastBig = colors({
			{ 0, lit },
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

-- A lightning theme: an energy theme whose bursts throw jittering arcs to the ground (`color`, with
-- a white-hot core) and whose residue crackles.
function VfxRecipe.lightning(color: Color3, accent: Color3?): Theme
	local theme = VfxRecipe.energy(color, accent or color:Lerp(WHITE, 0.6))
	theme.crackle = color
	theme.smokeTransparency = 0.65
	theme.scorch = color:Lerp(BLACK, 0.8) -- strikes mark the ground
	return theme
end

-- A wind theme: an energy theme in `color` whose smoke is a faint pale haze and whose residue is
-- pale motes (no dark smoke, no scorch).
function VfxRecipe.wind(color: Color3, accent: Color3?): Theme
	local pale = accent or color:Lerp(WHITE, 0.7)
	local theme = VfxRecipe.energy(color, pale)
	theme.smoke = colors({ { 0, pale:Lerp(WHITE, 0.5) }, { 1, pale } })
	theme.smokeTransparency = 0.75
	theme.ember = colors({ { 0, WHITE }, { 0.5, pale }, { 1, color } })
	return theme
end

-- An impact theme (punches, slams, rocks): a small white core tinted `color`, a dust cloud for the
-- blast, pale streak sparks, stone debris, dust rolling out after; no embers, flames or scorch.
function VfxRecipe.impact(color: Color3?): Theme
	local tint = color or rgb(235, 225, 205)
	return {
		core = colors({ { 0, tint:Lerp(WHITE, 0.3) }, { 1, tint } }),
		blast = P.dust,
		blastBig = P.dustDark,
		blastUsage = "smoke",
		blastLight = 0.05,
		spark = colors({ { 0, WHITE }, { 0.4, rgb(240, 225, 195) }, { 1, rgb(190, 170, 140) } }),
		ember = P.dust,
		smoke = P.dust,
		smokeTransparency = 0.45,
		edge = tint:Lerp(rgb(220, 205, 180), 0.5),
		edgeBig = tint,
		light = tint:Lerp(WHITE, 0.6),
		lightBig = tint:Lerp(WHITE, 0.4),
		flames = nil,
		residue = "dust",
		embers = false,
		debris = rgb(120, 108, 96),
		scorch = nil,
	}
end

-- A water theme (`color`, `accent` for highlights): a mist blast, a spray of droplets, pale mist
-- instead of smoke, bubbling and falling droplets after; no embers, flames or scorch.
function VfxRecipe.water(color: Color3, accent: Color3?): Theme
	local pale = accent or color:Lerp(WHITE, 0.6)
	return {
		core = colors({ { 0, pale }, { 1, color } }),
		blast = P.mist,
		blastBig = colors({ { 0, WHITE }, { 0.4, pale }, { 1, color } }),
		blastUsage = "smoke",
		blastLight = 0.2,
		spark = colors({ { 0, WHITE }, { 0.4, pale }, { 1, color } }),
		ember = P.mist,
		smoke = P.mist,
		smokeTransparency = 0.6,
		edge = color,
		edgeBig = pale,
		light = pale,
		lightBig = color,
		flames = nil,
		residue = "splash",
		embers = false,
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
function VfxRecipe.scorch(at: Vector3, radius: number, seconds: number, color: Color3?, start: number?)
	local tint = color or rgb(40, 30, 25)
	local texture = FxKit.textured("scorch", tint, "plane")
	if not texture then
		FxKit.mark(at, tint, tint, radius, "scorch", seconds)
		return
	end
	local base = CFrame.new(at + Vector3.new(0, 0.07, 0)) * CFrame.Angles(0, math.random() * math.pi * 2, 0)
	ImpactEffects.shape("Block", tint, seconds, function(part, progress)
		-- Burns in fast, keeps spreading a little, fades over the last half (never a solid sticker:
		-- the scorch usage caps its opacity).
		local grown = radius * 2.2 * (0.6 + 0.4 * math.min(1, progress * 8) + 0.15 * progress)
		part.Size = Vector3.new(grown, 0.05, grown)
		part.CFrame = base
		local first = start or 0.2 -- how see-through it starts (`start`: a softer mark)
		part.Transparency = first + (1 - first) * math.max(0, progress - 0.5) * 2
	end, nil, nil, texture, true)
end

-- A light flash at `at` for an area of `radius` (DEFAULTS.light), `k` times stronger. Extra.
function VfxRecipe.light(run, at: Vector3, radius: number, color: Color3, k: number?)
	if run.reduced then
		return
	end
	local config = D.light
	ImpactEffects.light(
		at + Vector3.new(0, 1.5, 0),
		color,
		config.brightness * (k or 1),
		math.max(4, radius * config.range),
		config.seconds
	)
end

-- The hot core: one short, small starburst frame in the theme's color (CORE_LIGHT, never cream-white
-- at full light), never wider than DEFAULTS.core.cap unit heights (x `k`, at most maxCap: GLOW_CAP).
function VfxRecipe.core(at: Vector3, radius: number, k: number?, palette: ColorSequence?, minSize: number?)
	local config = D.core
	local scale = k or 1
	local cap = UNIT_HEIGHT * math.min(config.cap * scale, config.maxCap)
	local least = math.min(minSize or 0, cap * 0.75)
	ImpactEffects.emit(at, {
		usage = "critFlash",
		count = 1,
		color = palette or P.flash,
		size = curve({
			{ 0, math.max(math.min(radius * config.size[1] * scale, cap * 0.75), least) },
			{ 1, math.min(math.max(radius * config.size[2] * scale, least * 1.3), cap) },
		}),
		transparency = curve({ { 0, 0.25 }, { 0.5, 0.55 }, { 1, 1 } }),
		lifetime = config.lifetime,
		lightEmission = CORE_LIGHT,
		brightness = config.brightness,
	})
end

-- One explosion sheet at `at`, `size` times DEFAULTS.explosion.size studs: the one-shot explosion
-- flipbook, or (`usage` "glow") a soft energy sheet, or ("smoke") a cloud (steam, dust, mist).
-- Glow and cloud sheets never grow past GLOW_CAP unit heights (a wider one, centered on the caster,
-- read as a giant sphere or dome over him); a glow sheet lives GLOW_SECONDS, at most half light.
function VfxRecipe.explosion(
	at: Vector3,
	size: number,
	palette: ColorSequence?,
	usage: string?,
	light: number?,
	minSize: number?
)
	local config = D.explosion
	local isGlow = usage == "glow"
	local sheet = isGlow or usage == "smoke"
	-- A glow sheet adds light everywhere it covers: smaller than a fireball so units stay readable.
	local scale = if isGlow then size * 0.6 else size
	local cap = if sheet then UNIT_HEIGHT * GLOW_CAP else math.huge
	local least = math.min(minSize or 0, cap / 1.6)
	local life = if isGlow then GLOW_SECONDS else config.lifetime
	ImpactEffects.emit(at, {
		usage = usage or "explosion",
		count = 1,
		color = palette or P.explosion,
		size = curve({
			{ 0, math.min(math.max(scale * config.size[1], least), cap * 0.5) },
			{ 0.2, math.min(math.max(scale * config.size[2], least * 1.4), cap * 0.85) },
			{ 1, math.min(math.max(scale * config.size[3], least * 1.6), cap) },
		}),
		-- a glow sheet has no frames of its own: it thins out sooner
		transparency = if sheet
			then curve({ { 0, 0.3 }, { 0.4, 0.45 }, { 1, 1 } })
			else curve({ { 0, 0.1 }, { 0.7, 0.2 }, { 1, 1 } }),
		lifetime = { life, life },
		lightEmission = if isGlow then math.min(light or 0.5, 0.5) else (light or config.lightEmission),
		brightness = config.brightness,
		rotSpeed = if sheet then { -40, 40 } else nil,
	})
end

-- The camera-facing shock ring sprite: only the fallback while the ring mesh is not loaded, never
-- wider than GLOW_CAP unit heights (wider, it read as a see-through bubble around the caster),
-- raised so its lower edge stays above the floor.
local function shockSprite(at: Vector3, widest: number, edge: Color3, seconds: number?)
	local config = D.shock
	local diameter = math.min(widest, UNIT_HEIGHT * GLOW_CAP)
	ImpactEffects.emit(at + Vector3.new(0, 0.3 + diameter * 0.5, 0), {
		usage = "shock",
		count = 1,
		color = colors({ { 0, edge:Lerp(WHITE, 0.25) }, { 1, edge } }),
		size = curve({ { 0, diameter * 0.3 }, { 0.35, diameter * 0.75 }, { 1, diameter } }),
		transparency = curve({ { 0, 0.15 }, { 0.4, 0.4 }, { 1, 1 } }),
		lifetime = { seconds or config.lifetime, seconds or config.lifetime },
		lightEmission = 0.6,
		brightness = config.brightness,
	})
end

-- The shock ring racing out then fading over an area of `radius`: the flat ring mesh just above the
-- ground (VfxRecipe.meshRing), out to DEFAULTS.shock.size[3] x `radius` (x `k`).
function VfxRecipe.shock(at: Vector3, radius: number, edge: Color3, k: number?, minSize: number?)
	local config = D.shock
	local widest = math.max(radius * config.size[3] * (k or 1), (minSize or 0) * 1.6)
	VfxRecipe.meshRing(at, widest / 3, edge, config.lifetime)
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

-- Ground flames: `count` fire-flipbook flames standing at `at`, `size` studs, living `lifetime`
-- { min, max } seconds (default 0.4-0.65; short ones for a flame that must not outlast what it is on).
function VfxRecipe.flames(at: Vector3, count: number, size: number, palette: ColorSequence?, lifetime: { number }?)
	ImpactEffects.emit(at, {
		usage = "fire",
		count = count,
		color = palette or P.fire,
		size = curve({ { 0, size * 0.45 }, { 0.15, size }, { 0.7, size * 0.85 }, { 1, size * 0.4 } }),
		transparency = curve({ { 0, 0.15 }, { 0.1, 0 }, { 0.65, 0.2 }, { 1, 1 } }),
		lifetime = lifetime or { 0.4, 0.65 },
		speed = { 1, 2.5 },
		spread = 12,
		acceleration = Vector3.new(0, 3, 0),
		-- Modest light so the saturated palette shows (full light washed flames out to cream).
		lightEmission = 0.45,
		brightness = 1.8,
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
function VfxRecipe.smoke(
	center: Vector3,
	radius: number,
	count: number,
	palette: ColorSequence?,
	start: number?,
	lifetime: { number }?
)
	local config = D.smoke
	local first = start or config.startTransparency
	for i = 1, count do
		local at = within(center, radius * 0.6)
		local out = at - center
		local heading = Vector3.new(out.X, 0, out.Z)
		heading = if heading.Magnitude > 1e-3 then heading.Unit else Vector3.xAxis
		ImpactEffects.emit(at + Vector3.new(0, 0.6 + radius * 0.35, 0), {
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
			lifetime = lifetime or config.lifetime,
			speed = { 2, 3.5 },
			spread = 25,
			direction = (Vector3.yAxis * 1.4 + heading).Unit,
			drag = 1,
			acceleration = Vector3.new(0, 1, 0),
			lightEmission = 0,
			rotSpeed = { -30, 30 },
		})
	end
end

-- A rising column of steam at `at` (ground): narrow puffs climbing fast and widening, `width` studs.
function VfxRecipe.steamColumn(at: Vector3, width: number, palette: ColorSequence?)
	ImpactEffects.emit(at + Vector3.new(0, 0.4, 0), {
		usage = "smoke",
		count = 3,
		color = palette or P.steam,
		size = curve({ { 0, width * 0.6 }, { 0.3, width * 1.2 }, { 1, width * 2.2 } }),
		transparency = curve({ { 0, 1 }, { 0.1, 0.5 }, { 0.5, 0.65 }, { 1, 1 } }),
		lifetime = { 0.8, 1.2 },
		speed = { 4, 6.5 },
		spread = 8,
		drag = 0.8,
		acceleration = Vector3.new(0, 2, 0),
		lightEmission = 0.05,
		rotSpeed = { -40, 40 },
	})
end

-- Bubbling at `at` (ground): small bubbles popping up within `radius`.
function VfxRecipe.bubbles(at: Vector3, radius: number, s: number)
	ImpactEffects.burst("bubble", at + Vector3.new(0, 0.2, 0), Vector3.yAxis, {
		color = Color3.fromRGB(235, 240, 245),
		count = 6,
		size = 0.35 * s,
		speed = { 1.5, 3.5 },
		lifetime = { 0.25, 0.45 },
		spread = math.clamp(radius * 20, 20, 60),
		transparency = 0.3,
	})
end

-- Stone debris from `at` (ground): `count` chunks of `size` studs thrown up and out on arcs within
-- `reach`, landing and fading (real parts, not glowing).
function VfxRecipe.debris(at: Vector3, count: number, size: number, color: Color3?, reach: number?)
	local spread = reach or 2
	for i = 1, count do
		local angle = math.random() * math.pi * 2
		local out = Vector3.new(math.cos(angle), 0, math.sin(angle)) * spread * (0.4 + 0.6 * math.random())
		local up = 3 + math.random() * 4
		local life = 0.55 + math.random() * 0.3
		local spin = Vector3.new(math.random(), math.random(), math.random()) * 12
		local chunk = size * (0.6 + 0.6 * math.random())
		ImpactEffects.shape("Block", color or rgb(120, 108, 96), life, function(part, progress)
			local t = progress * life
			-- out along the ground, up and back down (gravity 30), resting on the ground
			local height = math.max(chunk * 0.5, 0.3 + up * t - 15 * t * t)
			part.Size = Vector3.one * chunk
			part.CFrame = CFrame.new(at + out * math.min(1, progress * 1.4) + Vector3.new(0, height, 0))
				* CFrame.Angles(spin.X * t, spin.Y * t, spin.Z * t)
			part.Transparency = if progress > 0.75 then (progress - 0.75) * 4 else 0
		end, 0.01 * i, Enum.Material.Slate)
	end
end

-- A splash at `at` (ground): a fountain of droplets thrown up and falling back, and a mist puff.
function VfxRecipe.splash(at: Vector3, size: number, theme: Theme?)
	local t = themeOf(theme)
	ImpactEffects.emit(at + Vector3.new(0, 0.5, 0), {
		usage = "sparks",
		count = math.floor(28 * math.clamp(size / 2, 0.6, 1.6)),
		color = t.spark,
		size = curve({ { 0, 0.45 }, { 0.7, 0.3 }, { 1, 0 } }),
		transparency = curve({ { 0, 0.05 }, { 0.8, 0.2 }, { 1, 1 } }),
		lifetime = { 0.5, 0.9 },
		speed = { 9, 17 },
		spread = 40,
		direction = Vector3.yAxis,
		drag = 1,
		acceleration = Vector3.new(0, -38, 0),
		lightEmission = 0.6,
		brightness = 2,
		stretch = true,
	})
	VfxRecipe.smoke(at, size * 0.8, 3, t.smoke, t.smokeTransparency)
end

-- Dust kicked up at `at` (ground) by a slam or a landing: `count` puffs within `radius`, rolling out.
function VfxRecipe.dust(at: Vector3, radius: number, count: number)
	VfxRecipe.smoke(at - Vector3.new(0, 0.5, 0), radius, count, P.dust, 0.45)
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

export type Options = {
	big: boolean?,
	theme: Theme?,
	tier: number?,
	scorchScale: number?, -- burst: the scorch's size, times (default 1)
	scorchStart: number?, -- burst: the scorch's starting transparency (default 0.2; higher is softer)
	smokeScale: number?, -- aftermath: the smoke puffs' size, times (default 1)
	smokeLifetime: { number }?, -- aftermath: the smoke puffs' life { min, max } (default DEFAULTS)
	smoke: ColorSequence?, -- aftermath: the smoke's colors (default the theme's)
	smokeWaves: number?, -- aftermath: 1 for a single wave of puffs (default 2)
	flames: number?, -- aftermath: the ground flames' count, times (default 1; each emit is a counted layer)
}

local function optionsOf(opts: (Options | boolean)?): Options
	if type(opts) == "boolean" then
		return { big = opts }
	end
	return (opts :: Options?) or {}
end

-- A burst over an area: core flash, explosion or glow sheet (plus side blasts by tier: extra), the
-- flat shock ring (VfxRecipe.shock: no need for a second ring at the same spot), sparks, light,
-- scorch (fire themes), shake. `opts.big`: bigger (x1.35), darker or redder; `opts.theme` (default
-- fire); `opts.tier` (default the run's).
function VfxRecipe.burst(run, center: Vector3, radius: number, opts: (Options | boolean)?)
	local o = optionsOf(opts)
	local theme = themeOf(o.theme)
	local tier = tierOf(run, o.tier)
	local k = (if o.big then 1.35 else 1) * tier.k
	local blast = if o.big then theme.blastBig else theme.blast
	-- The readability floor (TIERS minSize, glow): small tiers' main layers stay big enough to read.
	local least = UNIT_WIDTH * (tier.minSize or 0)
	local air = center + Vector3.new(0, math.max(1.2, least * 0.6), 0)
	VfxRecipe.core(air, radius, k, theme.core, least)
	VfxRecipe.explosion(air, radius * k, blast, theme.blastUsage, theme.blastLight, least)
	if tier.glow and theme.blastUsage ~= "glow" then
		-- One clear colored glow per burst (a dust, mist or steam blast has none of its own).
		local tint = if o.big then theme.edgeBig else theme.edge
		VfxRecipe.explosion(
			air,
			radius * k,
			colors({ { 0, tint:Lerp(WHITE, 0.15) }, { 0.35, tint }, { 1, tint:Lerp(BLACK, 0.45) } }),
			"glow",
			0.5,
			least
		)
	end
	if not run.reduced then
		for i = 1, tier.sides do
			run:at(run:designTime() + 0.03 * i, function()
				VfxRecipe.explosion(
					within(center, radius * 0.7) + Vector3.new(0, 0.8 + radius * D.explosion.side * k, 0),
					radius * D.explosion.side * k,
					blast,
					theme.blastUsage,
					theme.blastLight
				)
			end)
		end
	end
	VfxRecipe.shock(center, radius, if o.big then theme.edgeBig else theme.edge, k, least)
	if theme.crackle then
		-- Arcs snapping from the blast down to the edge of the area.
		local arcs = if run.reduced then math.ceil(tier.arcs / 2) else tier.arcs
		for i = 1, arcs do
			local angle = (i / arcs) * math.pi * 2 + math.random() * 0.5
			local edge = center
				+ Vector3.new(math.cos(angle), 0, math.sin(angle)) * radius * (0.95 + 0.35 * math.random())
			VfxRecipe.arc(
				air + Vector3.new(0, 0.4, 0),
				edge + Vector3.new(0, 0.7, 0),
				theme.crackle,
				LIGHTNING.burstWidth * k * run:scale(),
				LIGHTNING.life,
				0.03 * i,
				i <= 2 and not run.reduced
			)
		end
	end
	VfxRecipe.sparks(air, k, nil, theme.spark)
	if theme.debris then
		VfxRecipe.debris(center, math.floor((if run.reduced then 3 else 5) * k), 0.35 * k, theme.debris, radius)
	end
	if theme.residue == "splash" then
		VfxRecipe.splash(center, radius * k, theme)
	end
	VfxRecipe.light(run, air, radius, if o.big then theme.lightBig else theme.light, k * tier.light)
	if theme.scorch then
		VfxRecipe.scorch(center, radius * k * (o.scorchScale or 1), 1.8 * tier.after, theme.scorch, o.scorchStart)
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
		local share = o.flames or 1
		local steps = math.max(2, math.floor(flames.seconds * tier.after / flames.every * share))
		-- fewer steps still span the same time
		local every = if share == 1 then flames.every else flames.seconds * tier.after / steps
		-- flames across the area, a few at a time (no ring of flames at once: it was decoration,
		-- 2-4 counted layers on top of the burst)
		for j = 0, steps - 1 do
			run:at(now + 0.05 + j * every, function()
				VfxRecipe.flames(
					within(center, radius * flames.reach),
					flames.perStep,
					flames.size * s * tier.k,
					theme.flames
				)
			end)
		end
	elseif theme.residue == "dust" then
		-- dust rolling out low across the area, a few chunks settling
		for j = 0, math.max(1, math.floor(2 * tier.after)) - 1 do
			run:at(now + 0.12 + j * 0.25, function()
				VfxRecipe.dust(within(center, radius * 0.6), radius * 0.7, if run.reduced then 1 else 3)
			end)
		end
	elseif theme.residue == "splash" then
		-- bubbling and droplets falling back across the area
		for j = 0, math.max(1, math.floor(2 * tier.after)) - 1 do
			run:at(now + 0.15 + j * 0.25, function()
				VfxRecipe.bubbles(within(center, radius * 0.7), radius * 0.3, s)
				if not run.reduced then
					VfxRecipe.sparks(within(center, radius * 0.6) + Vector3.new(0, 1.5, 0), 0.4, 10, theme.spark)
				end
			end)
		end
	elseif theme.residue == "steam" then
		-- rising steam columns and bubbling across the area
		for j = 0, math.max(1, math.floor(3 * tier.after)) - 1 do
			run:at(now + 0.15 + j * 0.25, function()
				VfxRecipe.steamColumn(within(center, radius * 0.7), radius * 0.35, theme.smoke)
				if not run.reduced then
					VfxRecipe.bubbles(within(center, radius * 0.8), radius * 0.3, s)
				end
			end)
		end
	else
		-- the residue of an energy blast: embers rising off the area in waves (crackling arcs too,
		-- for lightning themes)
		for j = 0, math.max(1, math.floor(3 * tier.after)) - 1 do
			run:at(now + 0.1 + j * 0.25, function()
				local at = within(center, radius * 0.6)
				VfxRecipe.embers(run, at + Vector3.new(0, 0.5, 0), s, theme.ember, 8)
				if theme.crackle and not run.reduced then
					VfxRecipe.crackle(run, at + Vector3.new(0, 0.4, 0), radius * 0.4, theme, 1)
				end
			end)
		end
	end
	local puffs = math.max(
		1,
		math.floor((if run.reduced then D.smoke.reducedPuffs else D.smoke.puffs) * math.min(tier.after, 1.4))
	)
	local smokeRadius = radius * (o.smokeScale or 1)
	local smokeColors = o.smoke or theme.smoke
	local single = o.smokeWaves == 1
	local first = if single then puffs else math.ceil(puffs * 0.6)
	run:at(now + 0.1, function()
		VfxRecipe.smoke(center, smokeRadius, first, smokeColors, theme.smokeTransparency, o.smokeLifetime)
	end)
	if puffs > first then
		run:at(now + 0.3, function()
			VfxRecipe.smoke(center, smokeRadius, puffs - first, smokeColors, theme.smokeTransparency, o.smokeLifetime)
		end)
	end
	if theme.embers ~= false then
		run:at(now + 0.2, function()
			VfxRecipe.embers(run, center + Vector3.new(0, 0.8, 0), s, theme.ember)
		end)
	end
end

-- Lightning ------------------------------------------------------------------------------------

-- The points of a jagged strand from `a` to `b`: `kinks` kinks pushed sideways by up to `jitter` of
-- its length.
local function jag(a: Vector3, b: Vector3, kinks: number, jitter: number): { Vector3 }
	local along = b - a
	local length = along.Magnitude
	local side = along:Cross(Vector3.yAxis)
	side = if side.Magnitude > 1e-3 then side.Unit else Vector3.xAxis
	local up = if length > 1e-3 then side:Cross(along.Unit) else Vector3.yAxis
	local points = { a }
	for i = 1, kinks do
		local push = (math.random() - 0.5) * 2 * jitter * length
		local lift = (math.random() - 0.5) * jitter * length
		table.insert(points, a:Lerp(b, i / (kinks + 1)) + side * push + up * lift)
	end
	table.insert(points, b)
	return points
end

-- One lightning arc from `a` to `b`, `width` studs, living `life` seconds from `delay`: a jagged
-- strand of 2-3 segments that re-jitters every LIGHTNING.jitter seconds, each segment the kit's
-- lightning strip (itself jagged; VfxConfig.uses `boltGlow`: wide, colored, LightEmission 0.5).
-- `core`: a thin bright neon core under it too (main strands only: it doubles the parts). Without the
-- kit, a neon strand. It flickers on and off for most of its life, then fades. `lit`: a small raised
-- flash at the strike. Cost: segments (x2 with a core) pooled shapes per arc.
function VfxRecipe.arc(
	a: Vector3,
	b: Vector3,
	color: Color3,
	width: number,
	life: number,
	delay: number?,
	lit: boolean?,
	withCore: boolean?
)
	local glow = FxKit.textured("boltGlow", color, "beam")
	local core = color:Lerp(WHITE, LIGHTNING.coreWhite)
	local length = (b - a).Magnitude
	local segments =
		math.clamp(math.floor(length / LIGHTNING.segmentLength), LIGHTNING.segments[1], LIGHTNING.segments[2])
	local kinks = segments - 1
	-- One shared strand for every segment and layer: re-jittered on a clock, so a few shapes crackle.
	local state = { points = jag(a, b, kinks, LIGHTNING.push), tick = 0 }
	local function strandAt(progress: number): { Vector3 }
		local tick = math.floor(progress * life / LIGHTNING.jitter)
		if tick ~= state.tick then
			state.tick = tick
			state.points = jag(a, b, kinks, LIGHTNING.push)
		end
		return state.points
	end
	local coreShare = if glow then LIGHTNING.coreWidth else 0.4
	-- Layer 1 the neon core (always without the kit, else only when asked), layer 2 the strip.
	local first = if withCore or not glow then 1 else 2
	local last = if glow then 2 else 1
	for i = 1, segments do
		for layer = first, last do
			local isCore = layer == 1
			ImpactEffects.shape("Block", if isCore then core else color, life, function(part, progress)
				local points = strandAt(progress)
				local p, q = points[i], points[i + 1]
				local w = width * (if isCore then coreShare else 1) * (1 - 0.3 * progress)
				-- A camera-facing glow seen end-on collapses into a fat oval: thin it the more the
				-- segment points at the camera.
				local camera = if workspace then workspace.CurrentCamera else nil
				local along = q - p
				if not isCore and camera and along.Magnitude > 1e-3 then
					local facing = math.abs(along.Unit:Dot(camera.CFrame.LookVector))
					w *= math.clamp(math.sqrt(1 - facing * facing), LIGHTNING.minFacing, 1)
				end
				part.Size = Vector3.new(w, w, math.max((q - p).Magnitude, 0.05))
				part.CFrame = CFrame.lookAt((p + q) / 2, q)
				-- On/off with every other re-jitter for the first 70% (2-4 flickers), then a fade.
				local seen = if progress < 0.7 then (if state.tick % 2 == 1 then 0.6 else 0) else (progress - 0.7) / 0.3
				part.Transparency = math.min(1, seen + (if isCore then 0 else 0.1))
			end, delay, nil, if isCore then nil else glow, not isCore)
		end
	end
	if lit then
		-- No PointLight here (near the floor it paints a hard disc): a small, short camera-facing
		-- flash where it strikes, raised off the ground.
		ImpactEffects.later(delay, function()
			local size = width * LIGHTNING.strike.size
			ImpactEffects.emit(b + Vector3.new(0, 0.3 + size * 0.5, 0), {
				usage = "flash",
				count = 1,
				color = colors({ { 0, color:Lerp(WHITE, 0.6) }, { 1, color } }),
				size = curve({ { 0, size }, { 1, size * 1.4 } }),
				transparency = curve({ { 0, 0.1 }, { 1, 1 } }),
				lifetime = { LIGHTNING.strike.lifetime, LIGHTNING.strike.lifetime },
				lightEmission = 1,
				brightness = 2,
			})
		end)
	end
end

-- Crackling around a point (a body, a head, a hand): `count` short arcs leaping out from near `at`
-- in random directions, up to `reach` studs, colored by the theme's crackle (or its edge), with a
-- flicker of light and a few sparks.
function VfxRecipe.crackle(run, at: Vector3, reach: number, theme: Theme?, count: number?)
	local t = themeOf(theme)
	local color = t.crackle or t.edge
	for i = 1, if run.reduced then math.ceil((count or 2) / 2) else count or 2 do
		local direction = Vector3.new(math.random() - 0.5, math.random() - 0.3, math.random() - 0.5)
		direction = if direction.Magnitude > 1e-3 then direction.Unit else Vector3.yAxis
		local from = at + direction * reach * 0.1
		VfxRecipe.arc(
			from,
			at + direction * reach * (0.8 + 0.4 * math.random()),
			color,
			LIGHTNING.crackleWidth * math.clamp(reach / 1.6, 0.7, 1.6),
			LIGHTNING.life * 0.6,
			0.03 * (i - 1),
			false
		)
	end
	VfxRecipe.sparks(at, 0.35, 6, t.spark)
end

-- Several arcs from `a` to `b` at once (a lightning dash, a bolt, a spear), the first the widest and
-- (unless `core` is false) with a bright neon core.
function VfxRecipe.arcs(
	run,
	a: Vector3,
	b: Vector3,
	theme: Theme?,
	strands: number?,
	width: number?,
	life: number?,
	core: boolean?
)
	local t = themeOf(theme)
	local color = t.crackle or t.edge
	local tierStrands = LIGHTNING.strands[math.clamp(run.tier or 3, 1, 5)]
	local n = if run.reduced then 1 else (strands or tierStrands)
	for i = 1, n do
		VfxRecipe.arc(
			a,
			b,
			color,
			(width or LIGHTNING.width) * (if i == 1 then 1 else 0.6),
			life or LIGHTNING.life,
			0.03 * (i - 1),
			i == 1 and not run.reduced,
			i == 1 and core ~= false
		)
	end
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
	local least = UNIT_WIDTH * (tierOf(run).minSize or 0) -- the readability floor (TIERS)
	VfxRecipe.core(at, radius, 1, t.core, least)
	VfxRecipe.explosion(at, radius * 0.8, t.blast, t.blastUsage, t.blastLight, least)
	VfxRecipe.sparks(at, 0.6, 24, t.spark, direction)
	VfxRecipe.light(run, at, radius, t.light, 0.7)
end

-- An aura around a body from design time `from` for `seconds`: glow motes rising around it and a few
-- sparks, in the theme's colors, `intensity` times (default 1). `body` is a unit view (the caster, a
-- summon, a healed ally) or, for a body with no view (a spirit, a clone), a function returning its
-- center and height now. Never a solid or see-through part, and no rim glow sheet any more (a
-- camera-facing glow 1-2 bodies wide read as a giant cream sphere around the unit): a spirit reads
-- from the particles shaped around it. Sparks are extra. Cost: particles only (no shapes).
function VfxRecipe.aura(run, body: any, theme: Theme?, intensity: number?, from: number?, seconds: number?)
	local t = themeOf(theme)
	local k = intensity or 1
	local start = from or run:designTime()
	local length = seconds or 1
	local every = 0.15
	local function where(): (Vector3?, number)
		if type(body) == "function" then
			return body()
		end
		local part = body and body.part
		if not part or not part.Parent then
			return nil, 0
		end
		return part.Position, part.Size.Y
	end
	for j = 0, math.max(1, math.floor(length / every)) - 1 do
		run:at(start + j * every, function()
			local center, height = where()
			if not center then
				return
			end
			local feet = center - Vector3.new(0, height / 2, 0)
			local around = height * 0.22
			for _ = 1, if run.reduced then 1 else 2 do
				ImpactEffects.emit(within(feet, around) + Vector3.new(0, height * 0.15, 0), {
					usage = "ember",
					count = math.max(1, math.floor(3 * k)),
					color = t.ember,
					-- ~0.45 studs at a unit's height: readable at the close camera
					size = curve({ { 0, 0.1 * height }, { 0.6, 0.08 * height }, { 1, 0 } }),
					transparency = curve({ { 0, 0.2 }, { 0.7, 0.35 }, { 1, 1 } }),
					lifetime = { 0.55, 0.85 },
					speed = { 2.5, 4.5 },
					spread = 18,
					direction = Vector3.yAxis,
					drag = 1,
					acceleration = Vector3.new(0, 2, 0),
					lightEmission = 1,
					brightness = 2,
				})
			end
			if run.reduced then
				return
			end
			if j % 3 == 0 then
				VfxRecipe.sparks(center, 0.3 * k, 4, t.spark)
			end
		end)
	end
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
			elseif t.residue == "steam" then
				VfxRecipe.steamColumn(at, size * 0.4, t.smoke)
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

-- Batch 2 kit (assets/vfx/src_b2): flipbook particles and theme presets -----------------------------
-- Not used by any ultimate yet (the next step wires units to them). Each preset names, per layer,
-- the VfxConfig usage that draws it; the textures' flipbook layout, mode and frame rate come from
-- the catalog (VfxConfig.traits), which ImpactEffects.emit applies to the particle.

local FRAMES = { ["2x2"] = 4, ["4x4"] = 16, ["8x8"] = 64 }

-- How long a particle of `usage` lives so its flipbook plays at the catalog's frame rate (OneShot:
-- every frame once; Random and Loop: one cycle), or nil when it has no flipbook or no texture yet.
function VfxRecipe.flipbookLife(usage: string, color: Color3?): number?
	local texture = FxKit.textured(usage, color or WHITE, "particle")
	local flipbook = texture and texture.flipbook
	if not flipbook or not flipbook.fps then
		return nil
	end
	return (FRAMES[flipbook.layout] or 16) / flipbook.fps
end

export type KitEmit = {
	size: number, -- studs
	grow: number?, -- end size, times `size` (default 1)
	color: Color3?, -- tint for white textures (baked ones ignore it: tint = false); default white
	palette: ColorSequence?, -- the tint over its life instead of `color`
	flicker: boolean?, -- its transparency flickers through its life
	sizeCurve: NumberSequence?, -- its size over its life instead of `size` -> `size` x `grow`
	fadeCurve: NumberSequence?, -- its transparency over its life instead of `start` (and `flicker`)
	count: number?,
	lifetime: number?, -- default: the flipbook's own length (flipbookLife), else 0.6
	speed: { number }?,
	spread: number?,
	direction: Vector3?,
	rotation: { number }?, -- default upright (0)
	lightEmission: number?,
	brightness: number?,
	zOffset: number?,
	stretch: boolean?, -- turned along its velocity (a bolt along a path: give `direction`)
	start: number?, -- starting transparency (default 0)
	-- World-oriented, not camera-facing: the image lies flat in the plane whose normal is
	-- `normal` (a swing plane), turned by `rotation` within it.
	normal: Vector3?,
}

-- One batch 2 kit particle (or `count`) of `usage` at `at`: its flipbook plays over its life. Draws
-- nothing until the texture is uploaded, loaded and warmed up as a particle (Vfx.particleReady; never
-- the plain sparkle fallback).
function VfxRecipe.kit(at: Vector3, usage: string, opts: KitEmit)
	local texture = FxKit.textured(usage, opts.color or WHITE, "particle")
	if not texture or not Vfx.particleReady(texture.id) then
		return -- not uploaded, still loading or warming, or failed: nothing (never a blank square)
	end
	local life = opts.lifetime or VfxRecipe.flipbookLife(usage, opts.color) or 0.6
	local first = opts.start or 0
	ImpactEffects.emit(at, {
		usage = usage,
		count = opts.count or 1,
		color = opts.palette or ColorSequence.new(opts.color or WHITE),
		size = opts.sizeCurve or curve({ { 0, opts.size }, { 1, opts.size * (opts.grow or 1) } }),
		transparency = if opts.fadeCurve
			then opts.fadeCurve
			elseif opts.flicker then curve({
				{ 0, first },
				{ 0.18, math.min(1, first + 0.35) },
				{ 0.36, first },
				{ 0.54, math.min(1, first + 0.3) },
				{ 0.72, first + 0.05 },
				{ 1, 1 },
			})
			else curve({
				{ 0, first },
				{ 0.85, math.min(1, first + 0.05) },
				{ 1, 1 },
			}),
		lifetime = { life, life },
		speed = opts.speed,
		spread = opts.spread,
		-- A flat particle lies across its (tiny) velocity: aim it along the plane's normal.
		direction = opts.normal or opts.direction,
		rotation = opts.rotation or { 0, 0 },
		lightEmission = opts.lightEmission or 0,
		brightness = opts.brightness or 1,
		zOffset = opts.zOffset,
		stretch = opts.stretch,
		flat = opts.normal ~= nil,
	})
end

-- Kit layers (batch 2) ---------------------------------------------------------------------------------
-- Each draws nothing (or its stated fallback) until its texture or mesh is loaded.

local function tinted(color: Color3, white: number): Color3
	return color:Lerp(WHITE, white) -- white-cored kit textures keep a hot core when tinted
end

-- `count` lightning bolts (fx_lightning, a different bolt each frame) from `a` to `b`: each a
-- particle as long as the path, turned along it, the ends jittered so strands fan a little.
-- The particle is square, as wide as the path is long, and each frame carries a faint glow band
-- (~10% alpha over half its width) cut off flat at the frame's ends: at full light, tinted toward
-- white and many studs long, that band read as a straight-edged cream wedge across the screen. So
-- the bolts keep their color (barely toward white) at moderate light; `brightness` (default 1.8)
-- for a strike that must read big and bright.
function VfxRecipe.kitBolts(
	a: Vector3,
	b: Vector3,
	color: Color3,
	count: number,
	life: number?,
	width: number?,
	brightness: number?
)
	local along = b - a
	local length = along.Magnitude
	if length < 0.2 then
		return
	end
	for _ = 1, count do
		local jitter = Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5) * length * 0.12
		local from, to = a + jitter * 0.3, b + jitter
		VfxRecipe.kit((from + to) / 2, "kitBolt", {
			-- the bolt art fills ~85% of its frame's height
			size = (to - from).Magnitude / 0.85 * (width or 1),
			color = tinted(color, 0.1),
			lifetime = (life or 0.22) * (0.8 + 0.4 * math.random()),
			speed = { 0.01, 0.01 },
			spread = 0,
			direction = (to - from).Unit,
			stretch = true,
			lightEmission = 0.7,
			brightness = brightness or 1.8,
		})
	end
end

-- Crackle crawling over a body (fx_crackle, Random frames) from design time `from` for `seconds`:
-- short arcs flickering at points on it, `per` each step. `body` is a unit view.
function VfxRecipe.kitCrackleAura(
	run,
	view: any,
	color: Color3,
	from: number,
	seconds: number,
	per: number?,
	scale: number? -- arc size, times (default 1: about half the body's height)
)
	local every = 0.08
	for j = 0, math.max(1, math.floor(seconds / every)) - 1 do
		run:at(from + j * every, function()
			local part = view and view.part
			if not part or not part.Parent then
				return
			end
			local size = part.Size
			for _ = 1, if run.reduced then 1 else (per or 2) do
				local at = part.Position
					+ Vector3.new(
						(math.random() - 0.5) * size.X,
						(math.random() - 0.4) * size.Y,
						(math.random() - 0.5) * size.Z
					)
				VfxRecipe.kit(at, "kitCrackle", {
					size = size.Y * (0.35 + 0.25 * math.random()) * (scale or 1),
					color = tinted(color, 0.25),
					lifetime = 0.12,
					rotation = { 0, 360 },
					lightEmission = 1,
					brightness = 2,
					zOffset = 1,
				})
			end
		end)
	end
end

-- A flame aura on a body (fx_aura_spike): `layers` overlapping sheets on the torso, rising off it,
-- each turned a little (+-10 degrees) and flickering, from design time `from` for `seconds`, in
-- `color` fading to `deep` (default a darker `color`): saturated, at moderate light (full light and a
-- white tint read as pale paper). The art stands on a flat base at the bottom of its frame: emitted
-- at the body's center it stood on the floor like a ring of teeth, so each sheet is centered above
-- the torso (its base at the hips) and drifts up.
function VfxRecipe.kitAuraSpike(
	run,
	view: any,
	color: Color3,
	from: number,
	seconds: number,
	layers: number?,
	deep: Color3?
)
	local every = 0.12
	local palette = colors({ { 0, color }, { 1, deep or color:Lerp(BLACK, 0.3) } })
	for j = 0, math.max(1, math.floor(seconds / every)) - 1 do
		run:at(from + j * every, function()
			local part = view and view.part
			if not part or not part.Parent then
				return
			end
			local height = part.Size.Y
			for k = 1, if run.reduced then 1 else (layers or 3) do
				local size = height * (1 + 0.3 * math.random()) -- 1-1.3x the body
				VfxRecipe.kit(part.Position + Vector3.new(0, size * 0.22, 0), "kitAuraSpike", {
					size = size,
					grow = 1.1,
					palette = palette,
					lifetime = 0.3,
					speed = { 1.5, 2.5 },
					spread = 8,
					direction = Vector3.yAxis,
					rotation = { -10, 10 },
					lightEmission = 0.45,
					brightness = 1.6,
					start = 0.15 + 0.15 * (k - 1),
					flicker = true,
					zOffset = if k == 1 then -1 else 0.3, -- one sheet behind the body, the rest over it
				})
			end
		end)
	end
end

-- A hit star (fx_impact_star) at `at`, `size` studs, turned at random.
function VfxRecipe.kitHitStar(at: Vector3, size: number, color: Color3)
	VfxRecipe.kit(at, "kitHitStar", {
		size = size,
		color = tinted(color, 0.4),
		rotation = { 0, 360 },
		lightEmission = 1,
		brightness = 2.5,
		zOffset = 1,
	})
end

-- A brief anime speed-lines flash (fx_speed_lines) centered on `at`.
function VfxRecipe.kitSpeedLines(at: Vector3, size: number, color: Color3?, life: number?)
	-- Kept in its color and well see-through: a near-white, opaque one read as a cream sheet
	-- whose square edges cut across the screen.
	VfxRecipe.kit(at, "kitSpeedLines", {
		size = size,
		grow = 1.15,
		color = tinted(color or WHITE, 0.15),
		lifetime = life or 0.18,
		rotation = { 0, 360 },
		lightEmission = 0.5,
		start = 0.45,
		zOffset = -1,
	})
end

-- Dust kicked up (fx_dust_burst, baked tan): `count` billows around `at` (ground), each 0.8-1.3x
-- `size` and turned at random so they never stack into the same shape; raised to clear the floor.
-- `lifetime` (seconds) plays the flipbook faster, so it is gone sooner (default its own ~0.8 s).
function VfxRecipe.kitDust(at: Vector3, size: number, count: number?, lifetime: number?)
	for _ = 1, count or 3 do
		local s = size * (0.8 + 0.5 * math.random())
		local offset = Vector3.new((math.random() - 0.5) * size * 0.5, 0, (math.random() - 0.5) * size * 0.5)
		VfxRecipe.kit(at + offset + Vector3.new(0, s * 0.38, 0), "kitDust", {
			size = s,
			rotation = { -12, 12 },
			lifetime = lifetime,
		})
	end
end

-- A fire bloom (fx_fire_burst, baked colors) at `at` (ground), raised to clear the floor. `opts`:
-- `lifetime` plays its flipbook faster (default its own ~0.67 s), `zOffset` moves it toward the
-- camera (default: half its size, so it covers what is behind it) or away (negative: drawn behind
-- what is in front of it).
function VfxRecipe.kitFireBurst(
	at: Vector3,
	size: number,
	delay: number?,
	opts: { lifetime: number?, zOffset: number? }?
)
	ImpactEffects.later(delay, function()
		VfxRecipe.kit(at + Vector3.new(0, size * 0.42, 0), "kitFireBurst", {
			size = size,
			rotation = { -15, 15 },
			lifetime = opts and opts.lifetime,
			zOffset = opts and opts.zOffset,
		})
	end)
end

-- Steam billows (fx_steam_billow, baked white, a dense wall) from `at`, `count` of them thrown out
-- along `direction` (default up) by `speed` studs/s, starting `start` transparent (default 0).
function VfxRecipe.kitSteam(
	at: Vector3,
	size: number,
	count: number?,
	direction: Vector3?,
	speed: number?,
	spread: number?,
	start: number?
)
	VfxRecipe.kit(at, "kitSteam", {
		size = size,
		grow = 1.3,
		count = count or 1,
		speed = { (speed or 2) * 0.7, speed or 2 },
		spread = spread or 25,
		direction = direction,
		rotation = { 0, 360 },
		start = start,
	})
end

-- A swoosh ribbon (fx_swoosh_ribbon; fx_slash_crescent until it loads) at `at`, `size` studs, lying
-- in the swing plane whose normal is `normal` (world-oriented, never camera-facing), turned `angle`
-- degrees within it, in `color`. A low LightEmission and the color untouched by white, so the tint
-- shows (a strong glow washed it out to cream). It swells a little and fades over `life` seconds.
-- `wipe` (seconds): instead it wipes in from a third of its size over `wipe`, then fades out over
-- the rest of `life` (never a static sticker).
function VfxRecipe.kitSwoosh(
	at: Vector3,
	size: number,
	color: Color3,
	normal: Vector3,
	angle: number?,
	life: number?,
	wipe: number?
)
	local seconds = life or 0.3
	local inShare = if wipe then math.clamp(wipe / seconds, 0.05, 0.8) else nil
	VfxRecipe.kit(at, "kitSwoosh", {
		size = size * 0.85,
		grow = 1.18,
		sizeCurve = if inShare then curve({ { 0, size * 0.33 }, { inShare, size }, { 1, size * 1.08 } }) else nil,
		fadeCurve = if inShare then curve({ { 0, 0.5 }, { inShare, 0.05 }, { 1, 1 } }) else nil,
		color = color,
		lifetime = seconds,
		normal = if normal.Magnitude > 1e-3 then normal.Unit else Vector3.yAxis,
		rotation = { (angle or 0) - 6, (angle or 0) + 6 },
		lightEmission = 0.42,
		brightness = 1.6,
		start = 0.05,
	})
end

-- A short expanding shock ring (mesh_shock_ring, ImpactEffects.flatRing): it lies flat `lift`
-- (>= 0.25) studs above the ground point `at`, grows from `diameter` to 3x and fades out over
-- `seconds` (<= 0.45). Without the mesh, the capped camera-facing shock sprite instead.
function VfxRecipe.meshRing(at: Vector3, diameter: number, color: Color3, seconds: number?, lift: number?)
	if not ImpactEffects.flatRing(at, diameter, color, seconds, lift) then
		shockSprite(at, diameter * 3, color, math.min(seconds or 0.35, 0.45))
	end
end

-- Theme presets: per layer, the usage that draws it. Batch 1 usages fill what batch 2 skipped (the
-- flame loop is "fire", the smoke billow "smoke"). `baked`: the preset's textures carry their own
-- colors (draw them white); otherwise pass the unit's color.
VfxRecipe.KIT = {
	fire = {
		burst = "kitFireBurst",
		flame = "fire",
		smoke = "smoke",
		hit = "kitHitStar",
		swoosh = "kitSwoosh",
		baked = true,
	},
	lightning = { bolt = "kitBolt", crackle = "kitCrackle", hit = "kitHitStar", slash = "kitSlashLine" },
	steam = { burst = "kitSteam", smoke = "kitSteam", hit = "kitHitStar", baked = true },
	dust = { burst = "kitDust", smoke = "smoke", hit = "kitHitStar", baked = true },
	water = { burst = "kitSplash", smoke = "kitSteam", hit = "kitHitStar", baked = true },
	toon = {
		burst = "kitPoof",
		hit = "kitHitStar",
		lines = "kitSpeedLines",
		halftone = "kitHalftone",
		smear = "kitSmear",
	},
	ink = {
		burst = "kitInkBurst",
		splatter = "kitInk",
		brush = "kitBrush",
		slash = "kitSlashLine",
		crescent = "kitCrescent",
	},
	shadow = { pool = "kitShadow", smoke = "smoke", aura = "kitAuraSpike" },
	aura = { aura = "kitAuraSpike", crackle = "kitCrackle", runes = "kitRunes" },
}

-- A preset's main burst at `at` (ground): its burst flipbook (raised so it clears the floor) and,
-- if it has one, the hit star. `size` studs; `color` for white textures.
function VfxRecipe.kitBurst(preset: string, at: Vector3, size: number, color: Color3?)
	local kit = VfxRecipe.KIT[preset]
	if not kit then
		return
	end
	local tint = if kit.baked then WHITE else (color or WHITE)
	if kit.burst then
		VfxRecipe.kit(at + Vector3.new(0, size * 0.45, 0), kit.burst, { size = size, color = tint })
	end
	if kit.hit then
		VfxRecipe.kit(
			at + Vector3.new(0, size * 0.4, 0),
			kit.hit,
			{ size = size * 0.8, color = color or WHITE, lightEmission = 1 }
		)
	end
end

return VfxRecipe
