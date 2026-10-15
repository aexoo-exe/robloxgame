-- null_edge (Tier 1): black flakes and the giant sword. The real cast cuts his target and hardens
-- his magic resist, at the Cast event.
--   -0.20  he hoists the huge black sword; black anti-magic flakes rise off it
--    0     a heavy overhead chop: a black slash on the real hit, sparks of magic "erased" around it
--   +0.20  black wisps around him (the magic resist); a determined stance

local FxKit = require(script.Parent.Parent.FxKit)
local ImpactEffects = require(script.Parent.Parent.ImpactEffects)

local BLACK = Color3.fromRGB(20, 20, 24)
local WHITE = Color3.new(1, 1, 1)

local def = {}

def.pose = {
	rightArm = { { -0.2, 0 }, { -0.08, 170, "out" }, { -0.02, 172 }, { 0.04, 30, "snap" }, { 0.3, 40 }, { 0.5, 0 } },
	leftArm = { { -0.2, 0 }, { -0.08, 150 }, { 0.04, 30, "snap" }, { 0.5, 0 } },
	lean = { { -0.2, 0 }, { -0.08, -8 }, { 0.04, 16, "snap" }, { 0.3, 4 }, { 0.5, 0 } },
	crouch = { { -0.08, 0 }, { 0.04, 0.16, "snap" }, { 0.45, 0 } },
}

def.beats = {
	{
		at = -0.2,
		run = function(run)
			run:face(run:target())
			ImpactEffects.burst("spark", run:hand("right") + Vector3.new(0, 2, 0), Vector3.yAxis, {
				color = BLACK,
				count = 8,
				size = 0.22,
				speed = { 1, 3 },
				lifetime = { 0.3, 0.5 },
				spread = 50,
			})
		end,
	},
}

function def.release(_run): boolean
	return true
end

function def.event(run, event): boolean
	local kind = event.kind
	if kind == "Damage" and event.target and not event.dot then
		local view = run.context.views[event.target]
		if view and not run.memo.hit then
			run.memo.hit = true
			local at = view.part.Position + Vector3.new(0, view.part.Size.Y * 0.1, 0)
			FxKit.slashArc(at, at - run.view.part.Position, BLACK, 3.4, 1.4, 0.3)
			ImpactEffects.burst("glow", at, nil, {
				color = run.style.secondary,
				color2 = WHITE,
				count = 8,
				size = 0.3,
				speed = { 5, 9 },
				lifetime = { 0.15, 0.3 },
			})
			run:hitStop(view, 0.06)
			run:shake(0.08)
			run:sound("whoosh", 0.9)
		end
		return true
	elseif kind == "Buff" and event.target == run.unitIndex then
		run:at(0.2, function()
			ImpactEffects.burst("smoke", run:ground() + Vector3.new(0, 0.5, 0), Vector3.yAxis, {
				color = BLACK,
				count = 6,
				size = 0.8,
				speed = { 1, 2 },
				lifetime = { 0.5, 0.8 },
				spread = 40,
				transparency = 0.3,
			})
		end)
		return true
	end
	return false
end

return def
