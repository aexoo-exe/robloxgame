-- snapfire (Tier 3): one small snap, one big fire. The real cast blasts everything within 1 hex of
-- his target (harder on enemies already burning) and sets them burning, at the Cast event.
--   -0.45  he raises his gloved hand, calm, two fingers ready; a hot glow and star sparks gather at
--          his fingers, a warm light pulse
--   -0.18  SNAP: a one-frame white-hot flash at his fingers, a pop of stars, a light flash, a tiny kick
--   -0.15  a fuse of fire races along the ground to the target: flames and streaking sparks, scorch
--          left behind
--    0     the real hit over the real area (VfxRecipe.burst): a short white-hot core, a yellow-orange
--          explosion with red edges, a fast ground shockwave, streak sparks arcing down, a tight light
--          flash; then (VfxRecipe.aftermath) ~1 s of ground flames across the area, small dark smoke
--          puffs rising and spreading, embers drifting up, the scorch fading. A second, bigger and
--          redder burst when his target was already burning
--   +0.30  he lowers his hand, unbothered (the burning markers are the real burns)
-- The layers and their tuned values are the shared recipe (src/client/VfxRecipe.luau), with the
-- batch 2 kit at the hit: a tiny spark at his fingers on the snap, then 2-3 staggered fire blooms
-- (fx_fire_burst) over the target, the largest last, then the smoke-flipbook aftermath.

local UltimateKit = require(script.Parent.Parent.UltimateKit)
local FxKit = require(script.Parent.Parent.FxKit)
local ImpactEffects = require(script.Parent.Parent.ImpactEffects)
local VfxRecipe = require(script.Parent.Parent.VfxRecipe)

local Kit = UltimateKit
local rgb = Color3.fromRGB
local curve = VfxRecipe.curve
local palettes = VfxRecipe.palettes
local WARM = rgb(255, 170, 70)
-- The aftermath's smoke: dark gray, a little lighter as it thins.
local SMOKE_GRAY = VfxRecipe.colors({ { 0, rgb(72, 70, 70) }, { 1, rgb(52, 51, 52) } })

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
					ImpactEffects.light(hand(), WARM, 1.2, 5 * s, 0.2)
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
			-- A tiny spark, not a flash ball: the snap is small, the fire is big.
			ImpactEffects.emit(at, {
				usage = "flash",
				count = 1,
				color = palettes.flash,
				size = curve({ { 0, 0.6 * s }, { 1, 0.85 * s } }),
				transparency = curve({ { 0, 0 }, { 1, 1 } }),
				lifetime = { 0.07, 0.08 },
				lightEmission = 1,
				brightness = 3,
			})
			ImpactEffects.emit(at, {
				usage = "star",
				count = 7,
				color = palettes.spark,
				size = curve({ { 0, 0.5 * s }, { 1, 0 } }),
				transparency = curve({ { 0, 0 }, { 1, 1 } }),
				lifetime = { 0.15, 0.25 },
				speed = { 7, 12 },
				drag = 8,
				lightEmission = 1,
				brightness = 3,
			})
			if not run.reduced then
				ImpactEffects.light(at, rgb(255, 235, 180), 3, 6 * s, 0.1)
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
					VfxRecipe.flames(at + Vector3.new(0, 0.1, 0), 2, 1.1 * s)
					if not run.reduced then
						VfxRecipe.sparks(at + Vector3.new(0, 0.2, 0), 0.5 * s, 8)
					end
					if i % 2 == 0 then
						VfxRecipe.scorch(at, 0.45 * s, 1.4)
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
		local target = run:find("Damage")
		local burning = target and target.target and wasBurning(run, target.target)
		-- Staggered fire blooms over the target, the largest last (a fourth, bigger and redder one
		-- when it was already burning), then the shock, sparks and light of the hit.
		local blooms = if run.reduced then 2 else 3
		for i = 1, blooms do
			local offset = if i < blooms then VfxRecipe.within(center, radius * 0.6) - center else Vector3.zero
			-- radius x 1.0, 1.4, 1.8: the last about as wide as the area
			VfxRecipe.kitFireBurst(center + offset, radius * (0.6 + 0.4 * i), 0.07 * (i - 1))
		end
		if burning then
			VfxRecipe.kitFireBurst(center, radius * 2.2, 0.07 * blooms + 0.05)
		end
		local fire = VfxRecipe.themes.fire
		VfxRecipe.shock(center, radius, fire.edge, 1)
		VfxRecipe.sparks(center + Vector3.new(0, 1.2, 0), 1, nil, fire.spark)
		VfxRecipe.light(run, center + Vector3.new(0, 1.2, 0), radius, fire.light, 1)
		-- The aftermath: ground flames, embers, the scorch, and the smoke-flipbook puffs half size,
		-- dark gray (not red) and gone within ~1.2 s (one wave).
		run:at(0.15, function()
			VfxRecipe.aftermath(run, center, radius, {
				smokeScale = 0.5,
				smokeLifetime = { 0.7, 0.95 },
				smoke = SMOKE_GRAY,
				smokeWaves = 1,
			})
		end)
		run:sound("whoosh", 0.9)
		return true
	elseif kind == "Damage" and event.target and not event.dot then
		return true
	end
	return false
end

return def
