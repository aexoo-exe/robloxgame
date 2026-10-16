-- wolfstep (Tier 1): the dagger rush and its X. The real cast dashes him to the highest-AD enemy and
-- cuts it, at the Cast event.
--   -0.15  a low crouch, both daggers reversed
--    0     the lunge along the real dash (grey afterimages); two crossed cuts on the real hit, one
--          right after the other
--   +0.20  he skids to a stop, daggers ready

local FxKit = require(script.Parent.Parent.FxKit)
local ImpactEffects = require(script.Parent.Parent.ImpactEffects)

local WHITE = Color3.new(1, 1, 1)

local def = {}

def.pose = {
	crouch = { { -0.15, 0 }, { -0.05, 0.28 }, { 0.05, 0.12, "snap" }, { 0.25, 0.22 }, { 0.5, 0 } },
	lean = { { -0.15, 0 }, { -0.05, 18 }, { 0.25, 10 }, { 0.5, 0 } },
	rightArm = { { -0.15, 0 }, { -0.05, -20 }, { 0.03, 100, "snap" }, { 0.1, 40 }, { 0.5, 0 } },
	leftArm = { { -0.15, 0 }, { -0.05, -20 }, { 0.06, 40 }, { 0.1, 100, "snap" }, { 0.5, 0 } },
	twist = { { 0, 0 }, { 0.03, 22, "snap" }, { 0.1, -22, "snap" }, { 0.4, 0 } },
}

def.beats = {
	{
		at = -0.15,
		run = function(run)
			run:face(run:target())
		end,
	},
}

function def.release(_run): boolean
	return true
end

function def.event(run, event): boolean
	if event.kind ~= "Damage" or not event.target or event.dot then
		return false
	end
	local view = run.context.views[event.target]
	if view and not run.memo.hit then
		run.memo.hit = true -- one X per cast (it hits one enemy)
		local at = view.part.Position + Vector3.new(0, view.part.Size.Y * 0.1, 0)
		local facing = view.part.Position - run.view.part.Position
		FxKit.slashArc(at, facing, run.style.primary, 2.4, 0.8, 0.22)
		FxKit.slashArc(at, facing, run.style.secondary, 2.4, -0.8, 0.22, 0.07)
		ImpactEffects.burst("spark", at, nil, {
			color = WHITE,
			count = 6,
			size = 0.18,
			speed = { 6, 10 },
			lifetime = { 0.1, 0.2 },
		})
		run:hitStop(view, 0.04)
		run:at(0.2, function()
			ImpactEffects.burst("puff", run:ground() + Vector3.new(0, 0.2, 0), -run:forward(), {
				color = Color3.fromRGB(196, 186, 168),
				count = 5,
				size = 0.6,
				speed = { 2, 4 },
				lifetime = { 0.25, 0.45 },
				spread = 40,
				transparency = 0.35,
			})
		end)
		run:sound("whoosh", 2)
	end
	return true
end

return def
