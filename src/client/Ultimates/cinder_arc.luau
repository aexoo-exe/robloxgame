-- cinder_arc (Tier 1): one clean arc of fire. The real cast cuts his target, splashes magic over
-- everything within 1 hex of it and speeds up his attacks, at the Cast event.
--   -0.20  the blade drawn back in both hands, low; embers glow along it
--    0     one wide circular slash leaving a ring of fire; it bursts out over the real splash
--   +0.30  the blade held forward, a warm glow for his attack speed

local FxKit = require(script.Parent.Parent.FxKit)
local ImpactEffects = require(script.Parent.Parent.ImpactEffects)

local def = {}

def.pose = {
	rightArm = { { -0.2, 0 }, { -0.1, -30 }, { -0.02, -35 }, { 0.05, 80, "snap" }, { 0.45, 75 }, { 0.6, 0 } },
	leftArm = { { -0.2, 0 }, { -0.1, -25 }, { -0.02, -30 }, { 0.05, 75, "snap" }, { 0.45, 70 }, { 0.6, 0 } },
	twist = { { -0.2, 0 }, { -0.1, -32 }, { 0.05, 34, "snap" }, { 0.3, 10 }, { 0.6, 0 } },
	crouch = { { -0.2, 0 }, { -0.1, 0.16 }, { 0.05, 0.1, "snap" }, { 0.5, 0 } },
}

def.beats = {
	{
		at = -0.2,
		run = function(run)
			run:face(run:target())
			ImpactEffects.burst("ember", run:hand("right"), Vector3.yAxis, {
				color = run.style.primary,
				color2 = run.style.secondary,
				count = 5,
				size = 0.2,
				speed = { 1, 3 },
				lifetime = { 0.25, 0.4 },
				spread = 40,
			})
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
		local at = center + Vector3.new(0, 1.2, 0)
		FxKit.slashArc(at, at - run.view.part.Position, run.style.primary, radius * 2.4, 0.15, 0.3)
		FxKit.ring(center, run.style.primary, radius * 2.4, 0.35, 0.05)
		ImpactEffects.burst("flame", center + Vector3.new(0, 0.4, 0), nil, {
			color = run.style.primary,
			color2 = run.style.secondary,
			count = 10,
			size = 0.9,
			speed = { 3, 6 },
			lifetime = { 0.25, 0.45 },
		})
		run:shake(0.08)
		run:sound("whoosh", 1.4)
		return true
	elseif kind == "Buff" and event.target == run.unitIndex then
		run:at(0.3, function()
			FxKit.ring(run:ground(), run.style.secondary, 3.5, 0.35)
		end)
		return true
	elseif kind == "Damage" and event.target and not event.dot then
		return true
	end
	return false
end

return def
