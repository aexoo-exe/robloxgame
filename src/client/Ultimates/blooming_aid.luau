-- blooming_aid (Tier 1): soft healing, or a ground-cracking punch. The real cast heals her
-- lowest-health ally if anyone is low, and otherwise hits her target, at the Cast event.
-- Heal:
--   -0.20  green glow in her palms; she reaches toward the ally
--    0     green motes stream to the ally she really heals; it glows green with petals of light
-- Punch:
--   -0.20  she tugs her glove; her fist glows pink
--    0     the punch into the ground: a crack races to the target and splits into a spiderweb, dust

local UltimateKit = require(script.Parent.Parent.UltimateKit)
local FxKit = require(script.Parent.Parent.FxKit)
local ImpactEffects = require(script.Parent.Parent.ImpactEffects)

local Kit = UltimateKit
local PINK = Color3.fromRGB(255, 140, 190)
local PETAL = Color3.fromRGB(255, 190, 215)
local CRACK = Color3.fromRGB(80, 64, 60)

local def = {}

local function healing(run): boolean
	return run:find("Heal") ~= nil
end

local HEAL = {
	leftArm = { { -0.2, 0 }, { -0.08, 80 }, { 0.3, 80 }, { 0.5, 0 } },
	rightArm = { { -0.2, 0 }, { -0.08, 80 }, { 0.3, 80 }, { 0.5, 0 } },
	leftArmOut = { { -0.2, 0 }, { -0.08, -10 }, { 0.5, 0 } },
	rightArmOut = { { -0.2, 0 }, { -0.08, -10 }, { 0.5, 0 } },
}

local PUNCH = {
	leftArm = { { -0.2, 0 }, { -0.12, 50 }, { -0.06, 50 }, { 0, 0 } },
	rightArm = { { -0.2, 0 }, { -0.12, 40 }, { -0.04, -30 }, { 0.03, 60, "snap" }, { 0.3, 50 }, { 0.5, 0 } },
	crouch = { { -0.1, 0 }, { 0.03, 0.28, "snap" }, { 0.45, 0 } },
	lean = { { -0.1, 0 }, { 0.03, 24, "snap" }, { 0.45, 0 } },
}

function def.poseFor(run)
	return if healing(run) then HEAL else PUNCH
end

def.beats = {
	{
		at = -0.2,
		run = function(run)
			local heal = healing(run)
			if not heal then
				run:face(run:target())
			end
			Kit.orb(run, -0.18, 0.02, if heal then run.style.secondary else PINK, function()
				return if heal then (run:hand("left") + run:hand("right")) / 2 else run:hand("right")
			end, function()
				return 0.35 * run:scale()
			end)
		end,
	},
}

function def.release(_run): boolean
	return true
end

function def.event(run, event): boolean
	local kind = event.kind
	if kind == "Heal" and event.target then
		local view = run.context.views[event.target]
		if view then
			Kit.converge(run, 0, 0.35, function()
				return view.part.Position
			end, run.style.secondary, 2.4, 4, false, 0.3)
			ImpactEffects.burst("mote", view.part.Position, Vector3.yAxis, {
				color = PETAL,
				color2 = run.style.secondary,
				count = 8,
				size = 0.3,
				speed = { 1, 3 },
				lifetime = { 0.5, 0.8 },
				spread = 60,
			})
		end
		return true
	elseif kind == "Damage" and event.target and not event.dot then
		local view = run.context.views[event.target]
		if view and not run.memo.hit then
			run.memo.hit = true
			local floor = view.part.Position - Vector3.new(0, view.part.Size.Y / 2, 0)
			Kit.groove(run, 0, 0.8, CRACK, run:ground() + run:forward() * 0.8, floor, 0.25)
			FxKit.mark(floor, CRACK, PINK, 2.2, "crack", 0.9)
			ImpactEffects.burst("puff", floor + Vector3.new(0, 0.3, 0), nil, {
				color = Kit.DUST,
				count = 6,
				size = 0.7,
				speed = { 2, 4 },
				lifetime = { 0.3, 0.5 },
				transparency = 0.35,
			})
			run:hitStop(view, 0.05)
			run:shake(0.08)
		end
		return true
	end
	return false
end

return def
