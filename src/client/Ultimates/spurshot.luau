-- spurshot (Tier 1): the spinning nail and its spiral. The real cast (at full spin stacks) shoots
-- the enemy in front, slows it and heals his horse (himself on foot), at the Cast event.
--   -0.20  he points; a small gold nail spins at his fingertip
--    0     it fires: a spinning gold-purple shot along a spiral; a spiral burst on the target (the
--          slow marker is the real one)
--   +0.15  green-gold motes drift back to the horse

local UltimateKit = require(script.Parent.Parent.UltimateKit)
local FxKit = require(script.Parent.Parent.FxKit)
local ImpactEffects = require(script.Parent.Parent.ImpactEffects)

local Kit = UltimateKit

local def = {}

def.pose = {
	rightArm = { { -0.2, 0 }, { -0.1, 88, "out" }, { 0, 90 }, { 0.03, 100, "snap" }, { 0.3, 90 }, { 0.45, 0 } },
	twist = { { -0.2, 0 }, { -0.1, 12 }, { 0.03, 4, "snap" }, { 0.45, 0 } },
}

local function fingertip(run): Vector3
	return run:hand("right") + run:forward() * 0.3
end

def.beats = {
	{
		at = -0.2,
		run = function(run)
			run:face(run:target())
			Kit.block(run, -0.18, 0, run.style.primary, function()
				return CFrame.new(fingertip(run)) * CFrame.Angles(0, 0, run:now() * 30)
			end, function()
				return Vector3.new(0.08, 0.3, 0.08)
			end, function()
				return 0
			end)
			run:sound("tick", 1.7)
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
		if view and not run.memo.shot then
			run.memo.shot = true
			FxKit.beam(fingertip(run), view.part.Position, run.style.primary, 0.5, 0.25, "spiral")
			local floor = view.part.Position - Vector3.new(0, view.part.Size.Y / 2, 0)
			FxKit.ring(floor, run.style.secondary, 3, 0.3)
			ImpactEffects.ball(view.part.Position, run.style.primary, 1.2, 0.08)
			run:hitStop(view, 0.04)
			run:sound("whoosh", 2)
		end
		return true
	elseif kind == "Heal" and event.target == run.unitIndex then
		-- The heal goes to the horse under him.
		Kit.converge(run, 0.15, 0.45, function()
			return run:ground() + Vector3.new(0, 1.2, 0)
		end, Color3.fromRGB(150, 225, 120), 2.4, 5, false, 0.3)
		return true
	end
	return false
end

return def
