-- burst_vector (Tier 2): loud orange explosions and the rocket jump. The real cast blasts everything
-- within 1 hex of his target and raises his attack damage, at the Cast event.
--   -0.35  his palms pop with little sparks
--   -0.22  a palm blast under him: a rocket jump up and toward the fight
--    0     the real hit: a big orange-black explosion on the target and its neighbors, smoke
--   +0.25  he drops into a crouch, sparks crackling, an orange glow for the buff

local UltimateKit = require(script.Parent.Parent.UltimateKit)
local FxKit = require(script.Parent.Parent.FxKit)
local ImpactEffects = require(script.Parent.Parent.ImpactEffects)

local Kit = UltimateKit
local WHITE = Kit.WHITE
local SMOKE = Color3.fromRGB(40, 36, 34)

local def = {}

def.pose = {
	leftArm = { { -0.35, 0 }, { -0.25, 60 }, { -0.22, -40, "snap" }, { 0, 90 }, { 0.3, 30 }, { 0.5, 0 } },
	rightArm = { { -0.35, 0 }, { -0.25, 60 }, { -0.22, -40, "snap" }, { 0, 90 }, { 0.3, 30 }, { 0.5, 0 } },
	rise = { { -0.22, 0 }, { -0.08, 1.8, "out" }, { 0.2, 0, "in" } },
	lean = { { -0.22, 0 }, { -0.08, 18 }, { 0.2, 10 }, { 0.5, 0 } },
	crouch = { { 0.15, 0 }, { 0.22, 0.25, "snap" }, { 0.5, 0 } },
}

def.beats = {
	{
		at = -0.35,
		run = function(run)
			run:face(run:target())
			for _, side in { "left", "right" } do
				ImpactEffects.burst("spark", run:hand(side), nil, {
					color = run.style.primary,
					count = 5,
					size = 0.2,
					speed = { 3, 6 },
					lifetime = { 0.1, 0.2 },
				})
			end
			run:sound("tick", 1.1)
		end,
	},
	{
		-- The palm blast he rides up.
		at = -0.22,
		run = function(run)
			ImpactEffects.ball(run:ground() + Vector3.new(0, 0.5, 0), run.style.primary, 2.4, 0.12)
			ImpactEffects.burst("smoke", run:ground() + Vector3.new(0, 0.3, 0), nil, {
				color = SMOKE,
				count = 6,
				size = 0.8,
				speed = { 2, 4 },
				lifetime = { 0.3, 0.5 },
				transparency = 0.3,
			})
			run:sound("whoosh", 1.3)
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
		local air = center + Vector3.new(0, 1.2, 0)
		ImpactEffects.ball(air, WHITE, radius * 1.1, 0.1)
		Kit.shell(run, 0, 0.3, run.style.primary, air, function(u)
			return radius * 2 * Kit.easeOut(u)
		end, function(u)
			return 0.2 + 0.8 * u
		end)
		ImpactEffects.burst("flame", air, nil, {
			color = run.style.primary,
			color2 = WHITE,
			count = 12,
			size = 1,
			speed = { 4, 8 },
			lifetime = { 0.25, 0.45 },
		})
		ImpactEffects.burst("smoke", air, Vector3.yAxis, {
			color = SMOKE,
			count = 8,
			size = 1.2,
			speed = { 2, 4 },
			lifetime = { 0.5, 0.9 },
			spread = 50,
			transparency = 0.3,
		})
		FxKit.mark(center, run.style.primary, SMOKE, radius, "scorch", 0.8)
		run:shake(0.12)
		run:sound("whoosh", 0.7)
		return true
	elseif kind == "Buff" and event.target == run.unitIndex then
		run:at(0.25, function()
			FxKit.ring(run:ground(), run.style.primary, 4, 0.35)
		end)
		return true
	elseif kind == "Damage" and event.target and not event.dot then
		return true
	end
	return false
end

return def
