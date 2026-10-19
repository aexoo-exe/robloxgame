-- marsh_fortress (Tier 2): the hop and the splash landing. The real cast slams everything next to
-- him and heals him for each enemy hit, at the Cast event.
--   -0.40  he puffs up, rising on his legs; smoke from his pipe
--   -0.28  a big hop
--    0     the landing on the real hit: a big water splash (the hero) and a shockwave ring over
--          1 hex, a little dust and mud
--   +0.10  blue-green heal motes drift into him
-- Layers at the landing: the shared recipe (VfxRecipe, a water theme in his colors, tier 2) and the
-- batch 2 kit's crown splash (fx_water_splash) and dust (fx_dust_burst).

local UltimateKit = require(script.Parent.Parent.UltimateKit)
local ImpactEffects = require(script.Parent.Parent.ImpactEffects)
local VfxRecipe = require(script.Parent.Parent.VfxRecipe)

local Kit = UltimateKit
local SMOKE = Color3.fromRGB(225, 225, 225)
local MUD = Color3.fromRGB(110, 86, 60)
local SPLASH = Color3.fromRGB(220, 238, 255) -- white-blue (the splash texture bakes its own colors)

local def = {}

def.pose = {
	rise = { { -0.4, 0 }, { -0.3, 0.15 }, { -0.28, 0.1 }, { -0.14, 2.2, "out" }, { 0, 0, "in" } },
	crouch = {
		{ -0.4, 0 },
		{ -0.3, 0.05 },
		{ -0.29, 0.2 },
		{ -0.26, 0, "snap" },
		{ 0, 0 },
		{ 0.04, 0.3, "snap" },
		{ 0.45, 0 },
	},
	lean = { { -0.4, 0 }, { -0.3, -8 }, { -0.14, 4 }, { 0, 10 }, { 0.4, 0 } },
	leftArmOut = { { -0.28, 0 }, { -0.14, 40 }, { 0.04, 20 }, { 0.45, 0 } },
	rightArmOut = { { -0.28, 0 }, { -0.14, 40 }, { 0.04, 20 }, { 0.45, 0 } },
}

def.beats = {
	{
		at = -0.4,
		run = function(run)
			-- Smoke from the pipe at the right of his mouth.
			local forward = run:forward()
			ImpactEffects.burst(
				"puff",
				run:head() + forward * 1.2 + Vector3.new(-forward.Z, 0, forward.X) * 1.4,
				Vector3.yAxis,
				{
					color = SMOKE,
					count = 5,
					size = 0.6,
					speed = { 1, 2 },
					lifetime = { 0.6, 1 },
					spread = 30,
					transparency = 0.4,
				}
			)
			run:sound("whoosh", 0.7)
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
		-- The water-splash landing: the recipe's water burst (core, mist, the flat shock ring, droplet
		-- fountain, light), then bubbling and falling droplets with a little mist (one small wave).
		local water = VfxRecipe.water(run.style.primary, run.style.secondary)
		VfxRecipe.burst(run, center, radius, { theme = water })
		VfxRecipe.aftermath(run, center, radius, { theme = water, smokeScale = 0.6, smokeWaves = 1 })
		-- The hero: one big white-blue crown splash (fx_water_splash, rendered to fill its frame:
		-- emitted large, raised to clear the floor, drawn in front of the dust and mist). The dust is
		-- secondary: two small bursts at the area's edges, half the old size, behind the splash; a
		-- few mud clods thrown out. (No second ring and no mud cloud: they buried the splash.)
		local size = radius * 2.8
		VfxRecipe.kit(center + Vector3.new(0, size * 0.42, 0), "kitSplash", {
			size = size,
			color = SPLASH,
			rotation = { -6, 6 },
			zOffset = 2,
		})
		for i = 1, 2 do
			local angle = (i / 2) * math.pi * 2 + math.random() * 0.5
			local edge = center + Vector3.new(math.cos(angle), 0, math.sin(angle)) * radius * 0.9
			VfxRecipe.kitDust(edge, radius * 0.45, 1)
		end
		VfxRecipe.debris(center, if run.reduced then 2 else 3, 0.3 * run:scale(), MUD, radius)
		for _, target in run:targets() do
			run:hitStop(target, 0.06)
		end
		run:sound("splash", 0.8)
		return true
	elseif kind == "Heal" and event.target == run.unitIndex then
		Kit.converge(run, run:designTime(), run:designTime() + 0.35, function()
			return run:chest()
		end, Color3.fromRGB(110, 220, 190), 3, 6, false, 0.35)
		return true
	elseif kind == "Damage" and event.target and not event.dot then
		return true
	end
	return false
end

return def
