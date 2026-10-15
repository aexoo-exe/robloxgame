-- redline_cut (Tier 2): the protector's dash. The real cast dashes her to the enemy attacking her
-- lowest-health ally, cuts it and speeds up her attacks, at the Cast event.
--   -0.20  her head snaps toward the threat; her red scarf flicks
--    0     grapple cables and a gas puff on the real dash; a spinning twin-blade cut on the real
--          hit, red and white
--   +0.30  she lands between them, blades crossed, a red glow for her attack speed

local UltimateKit = require(script.Parent.Parent.UltimateKit)
local FxKit = require(script.Parent.Parent.FxKit)
local ImpactEffects = require(script.Parent.Parent.ImpactEffects)

local Kit = UltimateKit
local WHITE = Kit.WHITE
local SCARF = Color3.fromRGB(200, 30, 40)
local CABLE = Color3.fromRGB(70, 74, 80)

local def = {}

def.pose = {
	twist = { { -0.2, 0 }, { -0.12, 28, "snap" }, { -0.02, 24 }, { 0.3, 0 } },
	lean = { { -0.2, 0 }, { -0.1, 10 }, { 0.3, 4 }, { 0.6, 0 } },
	spin = { { 0, 0 }, { 0.26, 360, "out" }, { 0.27, 0, "hold" } },
	leftArm = { { -0.2, 0 }, { 0, 40 }, { 0.26, 60 }, { 0.32, 70 }, { 0.55, 70 }, { 0.6, 0 } },
	leftArmOut = { { 0, 60 }, { 0.26, 60 }, { 0.32, -25 }, { 0.55, -25 }, { 0.6, 0 } },
	rightArm = { { -0.2, 0 }, { 0, 40 }, { 0.26, 60 }, { 0.32, 70 }, { 0.55, 70 }, { 0.6, 0 } },
	rightArmOut = { { 0, 60 }, { 0.26, 60 }, { 0.32, -25 }, { 0.55, -25 }, { 0.6, 0 } },
	crouch = { { 0.26, 0 }, { 0.32, 0.15 }, { 0.6, 0 } },
}

def.beats = {
	{
		at = -0.2,
		run = function(run)
			run:face(run:target())
			-- The scarf flicks out behind her neck.
			Kit.block(run, -0.18, 0.05, SCARF, function(u)
				local neck = run:head() - Vector3.new(0, run.view.part.Size.Y * 0.12, 0)
				return CFrame.lookAt(neck, neck - run:forward())
					* CFrame.new(0, 0, -0.4)
					* CFrame.Angles(0, math.sin(u * 12) * 0.5, 0)
			end, function()
				return Vector3.new(0.3, 0.08, 0.9)
			end, function(u)
				return u * 0.8
			end)
		end,
	},
}

function def.release(_run): boolean
	return true
end

function def.event(run, event): boolean
	local kind = event.kind
	if kind == "Dash" then
		local to = run.context.toWorld(event.column, event.row) + Vector3.new(0, 1.5, 0)
		FxKit.beam(run:chest(), to, CABLE, 0.06, 0.15, "straight")
		ImpactEffects.burst("puff", run:chest(), -run:forward(), {
			color = WHITE,
			count = 5,
			size = 0.7,
			speed = { 4, 7 },
			lifetime = { 0.25, 0.45 },
			spread = 40,
			transparency = 0.4,
		})
		return false
	elseif kind == "Damage" and event.target and not event.dot then
		local view = run.context.views[event.target]
		if view then
			local at = view.part.Position
			FxKit.slashArc(at, at - run.view.part.Position, run.style.primary, 2.8, 0.2, 0.25)
			ImpactEffects.ball(at, WHITE, 1.4, 0.08)
			run:hitStop(view, 0.05)
			run:shake(0.1)
			run:sound("whoosh", 1.7)
		end
		return true
	elseif kind == "Buff" and event.target == run.unitIndex then
		FxKit.ring(run:ground(), run.style.primary, 4, 0.4, 0.3)
		return true
	end
	return false
end

return def
