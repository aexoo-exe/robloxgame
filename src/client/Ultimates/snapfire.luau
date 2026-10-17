-- snapfire (Tier 3): one small snap, one big fire. The real cast blasts everything within 1 hex of
-- his target (harder on enemies already burning) and sets them burning, at the Cast event.
--   -0.45  he raises his gloved hand, calm, two fingers ready; a hot glow and star sparks gather at
--          his fingers, a warm light pulse
--   -0.18  SNAP: a one-frame white-hot flash at his fingers, a pop of stars, a light flash, a tiny kick
--   -0.15  a fuse of fire races along the ground to the target: flames and streaking sparks, scorch
--          left behind
--    0     the real hit over the real area: a starburst flash, an explosion sheet, a fast thick
--          shockwave on the ground, sparks flung out (drag and gravity), a light flash; then ~1 s of
--          flames on the ground, dark smoke rising slowly, embers drifting up, the scorch fading.
--          A second, bigger and redder burst when his target was already burning
--   +0.30  he lowers his hand, unbothered (the burning markers are the real burns)
--
-- The showcase recipe (copy it for other units): every layer is a kit texture (white masks) given its
-- whole color by a ColorSequence over its life (fire: white-yellow core -> orange -> deep red; smoke:
-- dark gray, never white), size and transparency curves that pop in fast and fade out slow,
-- LightEmission 1 on fire, glow and sparks (0 on smoke), Brightness up on hot layers, a PointLight
-- flash on each burst, and sizes taken from the real area. ReducedEffects drops the extra layers
-- (gathering stars, fuse sparks, side blasts, embers, lights, extra smoke).

local UltimateKit = require(script.Parent.Parent.UltimateKit)
local FxKit = require(script.Parent.Parent.FxKit)
local ImpactEffects = require(script.Parent.Parent.ImpactEffects)

local Kit = UltimateKit
local rgb = Color3.fromRGB

-- Palettes over each particle's life.
local function colors(points: { any }): ColorSequence
	local keys = {}
	for _, point in points do
		table.insert(keys, ColorSequenceKeypoint.new(point[1], point[2]))
	end
	return ColorSequence.new(keys)
end
local function curve(points: { { number } }): NumberSequence
	local keys = {}
	for _, point in points do
		table.insert(keys, NumberSequenceKeypoint.new(point[1], point[2]))
	end
	return NumberSequence.new(keys)
end

local FIRE = colors({
	{ 0, rgb(255, 250, 225) },
	{ 0.2, rgb(255, 205, 90) },
	{ 0.55, rgb(255, 115, 30) },
	{ 1, rgb(140, 25, 10) },
})
local FIRE_RED = colors({
	{ 0, rgb(255, 235, 205) },
	{ 0.15, rgb(255, 145, 55) },
	{ 0.45, rgb(230, 50, 20) },
	{ 1, rgb(90, 10, 8) },
})
local SPARK = colors({ { 0, rgb(255, 255, 235) }, { 0.4, rgb(255, 210, 110) }, { 1, rgb(255, 120, 40) } })
local EMBER = colors({ { 0, rgb(255, 220, 140) }, { 0.5, rgb(255, 130, 40) }, { 1, rgb(170, 40, 15) } })
local SMOKE = colors({ { 0, rgb(72, 60, 52) }, { 0.5, rgb(42, 37, 35) }, { 1, rgb(20, 18, 18) } })
local FLASH = colors({ { 0, rgb(255, 255, 255) }, { 1, rgb(255, 225, 150) } })
local WARM = rgb(255, 170, 70)

local def = {}

def.pose = {
	rightArm = { { -0.45, 0 }, { -0.25, 85, "out" }, { -0.2, 88 }, { -0.17, 95, "snap" }, { 0.3, 90 }, { 0.6, 0 } },
	rightArmOut = { { -0.45, 0 }, { -0.25, 8 }, { 0.6, 0 } },
	leftArm = { { -0.45, 0 }, { -0.25, -10 }, { 0.6, 0 } },
	lean = { { -0.45, 0 }, { -0.25, -3 }, { -0.17, -1, "snap" }, { 0.6, 0 } },
}

-- Whether his target was already burning: a BURN damage over time on it in the last 3 seconds.
local function wasBurning(run, targetIndex: number): boolean
	local events = run.context.events
	local index = run.castIndex
	if not index then
		return false
	end
	local castTick = events[index].tick
	for i = index - 1, 1, -1 do
		local event = events[i]
		if castTick - event.tick > 3 * run.context.ticksPerSecond then
			break
		end
		if event.kind == "Dot" and event.status == "BURN" and event.target == targetIndex then
			return true
		end
	end
	return false
end

-- A burnt patch on the ground (the kit's ground_scorch, soot-dark), `radius` studs, fading over
-- `seconds`; soft dark discs without the kit.
local function scorch(at: Vector3, radius: number, seconds: number, color: Color3)
	local texture = FxKit.textured("scorch", color, "plane")
	if not texture then
		FxKit.mark(at, color, color, radius, "scorch", seconds)
		return
	end
	local base = CFrame.new(at + Vector3.new(0, 0.07, 0)) * CFrame.Angles(0, math.random() * math.pi * 2, 0)
	ImpactEffects.shape("Block", color, seconds, function(part, progress)
		local grown = radius * 2.2 * (0.6 + 0.4 * math.min(1, progress * 8))
		part.Size = Vector3.new(grown, 0.05, grown)
		part.CFrame = base
		-- Burns in at once, holds, fades out over the last half.
		part.Transparency = 0.05 + 0.95 * math.max(0, progress - 0.5) * 2
	end, nil, nil, texture, true)
end

-- A random point within `radius` of `center` on the ground.
local function within(center: Vector3, radius: number): Vector3
	local angle = math.random() * math.pi * 2
	local r = radius * math.sqrt(math.random())
	return center + Vector3.new(math.cos(angle) * r, 0, math.sin(angle) * r)
end

-- Ground flames: `count` fire-flipbook flames standing at `at`, `size` studs tall-ish.
local function flames(at: Vector3, count: number, size: number, palette: ColorSequence)
	ImpactEffects.emit(at, {
		usage = "fire",
		count = count,
		color = palette,
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

-- One burst over the area. `big`: the second, bigger, brighter, redder one.
local function burst(run, center: Vector3, radius: number, big: boolean)
	local k = if big then 1.35 else 1
	local palette = if big then FIRE_RED else FIRE
	local air = center + Vector3.new(0, 1.2, 0)
	-- The flash: one starburst frame, huge and white-hot.
	ImpactEffects.emit(air, {
		usage = "critFlash",
		count = 1,
		color = FLASH,
		size = curve({ { 0, radius * 2 * k }, { 1, radius * 3.2 * k } }),
		transparency = curve({ { 0, 0 }, { 0.5, 0.3 }, { 1, 1 } }),
		lifetime = { 0.1, 0.12 },
		lightEmission = 1,
		brightness = 4,
	})
	-- The explosion sheet (one-shot flipbook: flash, fireball, smoke), sized to the real area; its
	-- color runs hot -> red as its frames turn to smoke.
	ImpactEffects.emit(air, {
		usage = "explosion",
		count = 1,
		color = palette,
		size = curve({ { 0, radius * 1.5 * k }, { 0.2, radius * 2.6 * k }, { 1, radius * 3.1 * k } }),
		transparency = curve({ { 0, 0 }, { 0.75, 0.1 }, { 1, 1 } }),
		lifetime = { 0.6, 0.6 },
		lightEmission = 0.8,
		brightness = 2.5,
	})
	if not run.reduced then
		-- Side blasts across the area, a beat apart.
		for i = 1, 3 do
			run:at(0.03 * i + (if big then 0.12 else 0), function()
				ImpactEffects.emit(within(center, radius * 0.7) + Vector3.new(0, 0.8, 0), {
					usage = "explosion",
					count = 1,
					color = palette,
					size = curve({ { 0, radius * 0.8 * k }, { 0.2, radius * 1.5 * k }, { 1, radius * 1.8 * k } }),
					transparency = curve({ { 0, 0 }, { 0.75, 0.15 }, { 1, 1 } }),
					lifetime = { 0.45, 0.55 },
					lightEmission = 0.8,
					brightness = 2,
				})
			end)
		end
	end
	-- The shockwave: the thick ring flat on the ground, out fast, then fading.
	ImpactEffects.emit(center + Vector3.new(0, 0.15, 0), {
		usage = "shock",
		count = 1,
		color = colors({ { 0, rgb(255, 235, 170) }, { 1, if big then rgb(230, 60, 25) else rgb(255, 120, 40) } }),
		size = curve({ { 0, radius * 0.6 }, { 0.35, radius * 2.5 * k }, { 1, radius * 3 * k } }),
		transparency = curve({ { 0, 0 }, { 0.4, 0.35 }, { 1, 1 } }),
		lifetime = { 0.4, 0.4 },
		lightEmission = 1,
		brightness = 2,
		flat = true,
	})
	-- Sparks flung out, slowed by drag and pulled down.
	ImpactEffects.emit(air, {
		usage = "sparks",
		count = math.floor(26 * k),
		color = SPARK,
		size = curve({ { 0, 0.55 * k }, { 1, 0 } }),
		transparency = curve({ { 0, 0 }, { 0.7, 0.1 }, { 1, 1 } }),
		lifetime = { 0.45, 0.85 },
		speed = { 16, 28 },
		spread = 80,
		drag = 3,
		acceleration = Vector3.new(0, -35, 0),
		lightEmission = 1,
		brightness = 2.5,
		rotation = { 0, 0 },
	})
	if not run.reduced then
		ImpactEffects.light(air, if big then rgb(255, 110, 50) else rgb(255, 160, 70), 9 * k, radius * 5, 0.5)
	end
	scorch(center, radius * k, 1.8, rgb(40, 30, 25))
	run:shake(if big then 0.22 else 0.16)
end

-- The aftermath: ~1 s of ground flames, dark smoke rising slowly, embers drifting up.
local function aftermath(run, center: Vector3, radius: number)
	local s = run:scale()
	for j = 0, 9 do
		run:at(0.05 + j * 0.1, function()
			flames(within(center, radius * 0.8), 2, 1.8 * s, FIRE)
		end)
	end
	for pass = 0, (if run.reduced then 0 else 2) do
		run:at(0.1 + pass * 0.25, function()
			local at = within(center, radius * 0.5) + Vector3.new(0, 1.2, 0)
			local smoke = {
				usage = "smoke",
				count = 3,
				color = SMOKE,
				size = curve({ { 0, radius * 0.7 }, { 0.3, radius * 1.3 }, { 1, radius * 2.1 } }),
				transparency = curve({ { 0, 0.5 }, { 0.15, 0.2 }, { 0.6, 0.35 }, { 1, 1 } }),
				lifetime = { 1.6, 2.2 },
				speed = { 1.5, 3 },
				spread = 35,
				drag = 0.6,
				acceleration = Vector3.new(0, 1.2, 0),
				lightEmission = 0,
				rotSpeed = { -25, 25 },
				zOffset = -0.5,
			}
			ImpactEffects.emit(at, smoke)
			smoke.usage = "smokePuff"
			smoke.count = 2
			ImpactEffects.emit(at, smoke)
		end)
	end
	if not run.reduced then
		run:at(0.2, function()
			ImpactEffects.emit(center + Vector3.new(0, 0.8, 0), {
				usage = "ember",
				count = 16,
				color = EMBER,
				size = curve({ { 0, 0.3 * s }, { 0.5, 0.22 * s }, { 1, 0 } }),
				transparency = curve({ { 0, 0 }, { 0.8, 0.2 }, { 1, 1 } }),
				lifetime = { 1, 1.7 },
				speed = { 2, 5 },
				spread = 60,
				drag = 1.2,
				acceleration = Vector3.new(0, 3, 0),
				lightEmission = 1,
				brightness = 3,
			})
		end)
	end
end

def.beats = {
	{
		-- Anticipation: a hot glow and star sparks gathering at his fingers, a warm light pulse.
		at = -0.45,
		run = function(run)
			run:face(run:target())
			local s = run:scale()
			local hand = function()
				return run:hand("right")
			end
			local glow = FxKit.textured("glowBlob", WARM, "billboard")
			Kit.live(run, -0.42, -0.18, "Ball", WARM, function(part, u)
				local pulse = 1 + 0.15 * math.sin(run:now() * 30)
				part.Size = Vector3.one * (0.35 + 0.45 * u) * s * pulse
				part.CFrame = CFrame.new(hand())
				part.Transparency = 0.35 - 0.25 * u
			end, nil, glow)
			Kit.converge(run, -0.42, -0.2, hand, rgb(255, 210, 120), 1.6 * s, if run.reduced then 5 else 12)
			if not run.reduced then
				run:at(-0.3, function()
					ImpactEffects.light(hand(), WARM, 2.5, 7 * s, 0.25)
				end)
			end
		end,
	},
	{
		-- The snap: a one-frame white-hot flash, a pop of stars, a light flash, a tiny kick.
		at = -0.18,
		run = function(run)
			local s = run:scale()
			local at = run:hand("right")
			ImpactEffects.emit(at, {
				usage = "flash",
				count = 1,
				color = FLASH,
				size = curve({ { 0, 2.8 * s }, { 1, 3.6 * s } }),
				transparency = curve({ { 0, 0 }, { 1, 1 } }),
				lifetime = { 0.07, 0.08 },
				lightEmission = 1,
				brightness = 4,
			})
			ImpactEffects.emit(at, {
				usage = "star",
				count = 7,
				color = SPARK,
				size = curve({ { 0, 0.5 * s }, { 1, 0 } }),
				transparency = curve({ { 0, 0 }, { 1, 1 } }),
				lifetime = { 0.15, 0.25 },
				speed = { 7, 12 },
				drag = 8,
				lightEmission = 1,
				brightness = 3,
			})
			if not run.reduced then
				ImpactEffects.light(at, rgb(255, 235, 180), 6, 10 * s, 0.12)
			end
			run:shake(0.04)
			run:sound("tick", 1.4)
		end,
	},
	{
		-- The fuse racing along the ground: flames and streaking sparks, scorch left behind.
		at = -0.15,
		run = function(run)
			local s = run:scale()
			local center = run:area()
			local from = run:ground()
			Kit.groove(run, -0.15, 0.3, rgb(255, 140, 50), from, center, 0.3 * s)
			local steps = 6
			for i = 1, steps do
				run:at(-0.15 + i * 0.025, function()
					local at = from:Lerp(center, i / steps)
					flames(at + Vector3.new(0, 0.1, 0), 2, 1.1 * s, FIRE)
					if not run.reduced then
						ImpactEffects.emit(at + Vector3.new(0, 0.2, 0), {
							usage = "sparks",
							count = 3,
							color = SPARK,
							size = curve({ { 0, 0.35 * s }, { 1, 0 } }),
							transparency = curve({ { 0, 0 }, { 1, 1 } }),
							lifetime = { 0.2, 0.35 },
							speed = { 6, 12 },
							spread = 55,
							drag = 4,
							acceleration = Vector3.new(0, -25, 0),
							lightEmission = 1,
							brightness = 2.5,
							rotation = { 0, 0 },
						})
					end
					if i % 2 == 0 then
						scorch(at, 0.45 * s, 1.4, rgb(40, 30, 25))
					end
				end)
			end
		end,
	},
}

function def.release(_run): boolean
	return true
end

function def.event(run, event): boolean
	local kind = event.kind
	if kind == "Area" then
		local center, radius = run:area()
		burst(run, center, radius, false)
		aftermath(run, center, radius)
		local target = run:find("Damage")
		if target and target.target and wasBurning(run, target.target) then
			-- Already burning: the bigger, redder second burst.
			run:at(0.12, function()
				burst(run, center, radius, true)
			end)
		end
		run:sound("whoosh", 0.9)
		return true
	elseif kind == "Damage" and event.target and not event.dot then
		return true
	end
	return false
end

return def
