-- marsh_fortress (Tier 2): the hop and the splash landing. The real cast slams everything next to
-- him and heals him for each enemy hit, at the Cast event.
--   -0.40  he puffs up, rising on his legs; smoke from his pipe
--   -0.28  a big hop
--    0     the landing on the real hit: a water-splash shockwave ring over 1 hex, mud and spray
--   +0.10  blue-green heal motes drift into him

local UltimateKit = require(script.Parent.Parent.UltimateKit)
local FxKit = require(script.Parent.Parent.FxKit)
local ImpactEffects = require(script.Parent.Parent.ImpactEffects)

local Kit = UltimateKit
local SMOKE = Color3.fromRGB(225, 225, 225)
local MUD = Color3.fromRGB(110, 86, 60)

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
		FxKit.mark(center, run.style.primary, run.style.secondary, radius, "splash", 0.7)
		FxKit.ring(center, run.style.primary, radius * 2.4, 0.4)
		ImpactEffects.burst("bubble", center + Vector3.new(0, 0.6, 0), Vector3.yAxis, {
			color = run.style.primary,
			count = 12,
			size = 0.6,
			speed = { 4, 8 },
			lifetime = { 0.4, 0.7 },
			spread = 70,
		})
		ImpactEffects.burst("puff", center + Vector3.new(0, 0.3, 0), nil, {
			color = MUD,
			count = 8,
			size = 0.9,
			speed = { 3, 6 },
			lifetime = { 0.3, 0.6 },
			transparency = 0.3,
		})
		for _, target in run:targets() do
			run:hitStop(target, 0.06)
		end
		run:shake(0.12)
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
