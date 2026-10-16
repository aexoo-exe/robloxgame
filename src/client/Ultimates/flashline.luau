-- flashline (Tier 1): the thunderclap quick-draw. The real cast dashes him to the farthest enemy and
-- cuts it, at the Cast event. His katana is drawn only for it (UnitAvatarConfig `drawn`).
--   -0.20  a low crouch, hand at the sword, eyes shut; small yellow sparks at his feet
--    0     gone: a single yellow streak along the real dash, no run
--   +0.12  a beat later, already past it, the cut flashes across the target with a crackle
--   +0.30  he settles back, the blade going home

local UltimateKit = require(script.Parent.Parent.UltimateKit)
local FxKit = require(script.Parent.Parent.FxKit)
local ImpactEffects = require(script.Parent.Parent.ImpactEffects)

local Kit = UltimateKit
local WHITE = Kit.WHITE

local DELAY = 0.12 -- the cut shows after he is past

local def = {}

def.pose = {
	crouch = { { -0.2, 0 }, { -0.1, 0.25 }, { 0, 0.25 }, { 0.05, 0.1, "snap" }, { 0.45, 0 } },
	lean = { { -0.2, 0 }, { -0.1, 14 }, { 0.05, 6, "snap" }, { 0.45, 0 } },
	rightArm = { { -0.2, 0 }, { -0.1, 25 }, { 0, 25 }, { 0.04, 110, "snap" }, { 0.25, 90 }, { 0.45, 0 } },
	rightArmOut = { { -0.2, 0 }, { -0.1, -25 }, { 0, -25 }, { 0.04, 55, "snap" }, { 0.45, 0 } },
}

def.beats = {
	{
		at = -0.2,
		run = function(run)
			run:face(run:target())
			ImpactEffects.burst("spark", run:ground() + Vector3.new(0, 0.2, 0), Vector3.yAxis, {
				color = run.style.primary,
				count = 5,
				size = 0.16,
				speed = { 2, 4 },
				lifetime = { 0.15, 0.25 },
				spread = 60,
			})
		end,
	},
}

function def.release(_run): boolean
	return true
end

function def.event(run, event): boolean
	local kind = event.kind
	if kind == "Dash" then
		local from = run:chest()
		local to = run.context.toWorld(event.column, event.row) + Vector3.new(0, run.view.part.Size.Y * 0.6, 0)
		FxKit.beam(from, to, run.style.primary, 0.3, 0.25, "straight")
		run:sound("whoosh", 2)
		return true -- the streak replaces the afterimages: no visible run
	elseif kind == "Damage" and event.target and not event.dot then
		local view = run.context.views[event.target]
		if view and not run.memo.hit then
			run.memo.hit = true -- one cut per cast (it hits one enemy)
			run:at(DELAY, function()
				local at = view.part.Position + Vector3.new(0, view.part.Size.Y * 0.1, 0)
				FxKit.slashArc(at, run:forward(), WHITE, 3, 0.15, 0.2)
				Kit.zap(at - Vector3.new(1, 0, 0), at + Vector3.new(1, 0.4, 0), run.style.primary, 0.1, 0.15, 2)
				run:hitStop(view, 0.05)
				run:shake(0.06)
			end)
		end
		return true
	end
	return false
end

return def
