-- The layered VFX recipe for ultimates (first built for snapfire): reusable layers drawn with the kit
-- textures through ImpactEffects.emit / light / shape, each tinted by a ColorSequence over its life
-- (the textures are white masks), sized from the real area, with tuned defaults (DEFAULTS) so every
-- ultimate built from it reads the same: a short, small white-hot core; a yellow-orange explosion
-- with red edges and modest Brightness (units stay readable inside it); a short, tight light flash;
-- small dark-gray smoke puffs that rise, spread and fade; many bright streak sparks arcing down.
-- Layers marked "extra" are skipped with ReducedEffects (run.reduced). Presentation only.

local FxKit = require(script.Parent.FxKit)
local ImpactEffects = require(script.Parent.ImpactEffects)

local VfxRecipe = {}

local rgb = Color3.fromRGB

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
	flash = colors({ { 0, rgb(255, 255, 255) }, { 1, rgb(255, 225, 150) } }),
}

-- Tuned defaults (studs scale with the area radius `r` or the unit scale `s` where noted).
VfxRecipe.DEFAULTS = {
	-- the white-hot core at a burst: ~40% of the old size, 0.08-0.12 s
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
	-- smoke: small dark puffs that rise and spread
	smoke = { puffs = 8, reducedPuffs = 3, size = { 0.35, 0.7, 0.9 }, lifetime = { 1, 1.4 }, startTransparency = 0.4 }, -- x r
	embers = { count = 16, size = 0.3 }, -- size x s
}
local D = VfxRecipe.DEFAULTS

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
function VfxRecipe.core(at: Vector3, radius: number, k: number?)
	local config = D.core
	local scale = k or 1
	ImpactEffects.emit(at, {
		usage = "critFlash",
		count = 1,
		color = VfxRecipe.palettes.flash,
		size = curve({ { 0, radius * config.size[1] * scale }, { 1, radius * config.size[2] * scale } }),
		transparency = curve({ { 0, 0 }, { 0.5, 0.35 }, { 1, 1 } }),
		lifetime = config.lifetime,
		lightEmission = 1,
		brightness = config.brightness,
	})
end

-- One explosion sheet (one-shot flipbook) at `at`, `size` times DEFAULTS.explosion.size studs.
function VfxRecipe.explosion(at: Vector3, size: number, palette: ColorSequence?)
	local config = D.explosion
	ImpactEffects.emit(at, {
		usage = "explosion",
		count = 1,
		color = palette or VfxRecipe.palettes.explosion,
		size = curve({ { 0, size * config.size[1] }, { 0.2, size * config.size[2] }, { 1, size * config.size[3] } }),
		transparency = curve({ { 0, 0.1 }, { 0.7, 0.2 }, { 1, 1 } }),
		lifetime = { config.lifetime, config.lifetime },
		lightEmission = config.lightEmission,
		brightness = config.brightness,
	})
end

-- The thick ring flat on the ground, racing out then fading.
function VfxRecipe.shock(at: Vector3, radius: number, edge: Color3, k: number?)
	local config = D.shock
	local scale = k or 1
	ImpactEffects.emit(at + Vector3.new(0, 0.15, 0), {
		usage = "shock",
		count = 1,
		color = colors({ { 0, rgb(255, 230, 160) }, { 1, edge } }),
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
function VfxRecipe.sparks(at: Vector3, k: number?, count: number?)
	local config = D.sparks
	local scale = k or 1
	ImpactEffects.emit(at, {
		usage = "sparks",
		count = math.floor((count or config.count) * scale),
		color = VfxRecipe.palettes.spark,
		size = curve({ { 0, config.size * scale }, { 0.6, config.size * 0.65 * scale }, { 1, 0 } }),
		transparency = curve({ { 0, 0 }, { 0.75, 0.1 }, { 1, 1 } }),
		lifetime = config.lifetime,
		speed = config.speed,
		spread = config.spread,
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
		color = palette or VfxRecipe.palettes.fire,
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

-- A burst over an area: core flash, explosion (plus side blasts: extra), ground shockwave, sparks,
-- light, scorch, shake. `big`: bigger (x1.35), redder.
function VfxRecipe.burst(run, center: Vector3, radius: number, big: boolean?)
	local k = if big then 1.35 else 1
	local palette = if big then VfxRecipe.palettes.explosionRed else VfxRecipe.palettes.explosion
	local air = center + Vector3.new(0, 1.2, 0)
	VfxRecipe.core(air, radius, k)
	VfxRecipe.explosion(air, radius * k, palette)
	if not run.reduced then
		for i = 1, 3 do
			run:at(run:designTime() + 0.03 * i, function()
				VfxRecipe.explosion(
					within(center, radius * 0.7) + Vector3.new(0, 0.8, 0),
					radius * D.explosion.side * k,
					palette
				)
			end)
		end
	end
	VfxRecipe.shock(center, radius, if big then rgb(230, 60, 25) else rgb(255, 120, 40), k)
	VfxRecipe.sparks(air, k)
	VfxRecipe.light(run, air, radius, if big then rgb(255, 110, 50) else rgb(255, 160, 70), k)
	VfxRecipe.scorch(center, radius * k, 1.8)
	run:shake(if big then 0.22 else 0.16)
end

-- Small dark puffs: `count` of them from points across the area, rising and spreading outward,
-- fading by ~1.4 s.
function VfxRecipe.smoke(center: Vector3, radius: number, count: number)
	local config = D.smoke
	local start = config.startTransparency
	for i = 1, count do
		local at = within(center, radius * 0.6)
		local out = at - center
		local heading = Vector3.new(out.X, 0, out.Z)
		heading = if heading.Magnitude > 1e-3 then heading.Unit else Vector3.xAxis
		ImpactEffects.emit(at + Vector3.new(0, 0.8, 0), {
			-- alternate the puff flipbook and the soft puff so they do not look stamped
			usage = if i % 2 == 0 then "smokePuff" else "smoke",
			count = 1,
			color = VfxRecipe.palettes.smoke,
			size = curve({
				{ 0, radius * config.size[1] },
				{ 0.35, radius * config.size[2] },
				{ 1, radius * config.size[3] },
			}),
			transparency = curve({ { 0, 1 }, { 0.08, start }, { 0.45, start + 0.15 }, { 1, 1 } }),
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
function VfxRecipe.embers(run, at: Vector3, s: number)
	if run.reduced then
		return
	end
	local config = D.embers
	ImpactEffects.emit(at, {
		usage = "ember",
		count = config.count,
		color = VfxRecipe.palettes.ember,
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

-- The aftermath of a burst at design time now: ground flames spread across the area for
-- DEFAULTS.flames.seconds, small dark smoke puffs in two waves, embers drifting up.
function VfxRecipe.aftermath(run, center: Vector3, radius: number)
	local s = run:scale()
	local now = run:designTime()
	local flames = D.flames
	local steps = math.floor(flames.seconds / flames.every)
	-- a ring of flames at once, then more across the area
	for i = 1, 4 do
		local angle = i * math.pi / 2 + math.random() * 0.6
		VfxRecipe.flames(center + Vector3.new(math.cos(angle), 0, math.sin(angle)) * radius * 0.6, 1, flames.size * s)
	end
	for j = 0, steps - 1 do
		run:at(now + 0.05 + j * flames.every, function()
			VfxRecipe.flames(within(center, radius * flames.reach), flames.perStep, flames.size * s)
		end)
	end
	local puffs = if run.reduced then D.smoke.reducedPuffs else D.smoke.puffs
	local first = math.ceil(puffs * 0.6)
	run:at(now + 0.1, function()
		VfxRecipe.smoke(center, radius, first)
	end)
	if puffs > first then
		run:at(now + 0.3, function()
			VfxRecipe.smoke(center, radius, puffs - first)
		end)
	end
	run:at(now + 0.2, function()
		VfxRecipe.embers(run, center + Vector3.new(0, 0.8, 0), s)
	end)
end

return VfxRecipe
