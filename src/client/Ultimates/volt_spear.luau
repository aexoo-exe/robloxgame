-- volt_spear (Tier 3): the lightning in the hand, dragged along the ground. The real cast lunges him
-- at his target, hits it with lightning, stuns it and leaves it burning, at the Cast event.
--   -0.45  his hand held down and back; a crackling blue-white ball forms in it, flickering with a
--          rapid chirp
--   -0.15  he drops low, leaning in
--    0     the lunge on the real dash: lightning tears a line in the ground; the strike: a burst of
--          lightning through the target (the stun and the burn marker are the real ones)

local UltimateKit = require(script.Parent.Parent.UltimateKit)
local ImpactEffects = require(script.Parent.Parent.ImpactEffects)

local Kit = UltimateKit
local WHITE = Kit.WHITE

local def = {}

def.pose = {
	rightArm = { { -0.45, 0 }, { -0.3, -35, "out" }, { -0.02, -40 }, { 0.04, 96, "snap" }, { 0.4, 85 }, { 0.7, 0 } },
	rightArmOut = { { -0.45, 0 }, { -0.3, 18 }, { 0.04, 0, "snap" }, { 0.7, 0 } },
	leftArm = { { -0.45, 0 }, { -0.3, 30 }, { 0.04, -10, "snap" }, { 0.7, 0 } },
	crouch = { { -0.3, 0 }, { -0.15, 0.2 }, { 0.04, 0.12, "snap" }, { 0.5, 0 } },
	lean = { { -0.3, 0 }, { -0.15, 18 }, { 0.04, 12, "snap" }, { 0.5, 0 } },
	twist = { { -0.3, 0 }, { -0.15, -16 }, { 0.04, 20, "snap" }, { 0.4, 8 }, { 0.7, 0 } },
}

def.beats = {
	{
		at = -0.45,
		run = function(run)
			run:face(run:target())
			local blue = run.style.primary
			Kit.orb(run, -0.4, 0.05, WHITE:Lerp(blue, 0.4), function()
				return run:hand("right")
			end, function(u)
				return (0.4 + 0.4 * u) * run:scale()
			end)
			-- The chirping flicker: short arcs off the ball.
			for i = 0, (if run.reduced then 3 else 7) do
				run:at(-0.4 + i * 0.05, function()
					local at = run:hand("right")
					Kit.zap(
						at,
						at + Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5) * 1.6,
						WHITE,
						0.08,
						0.06,
						2
					)
					if i % 2 == 0 then
						run:sound("tick", 2)
					end
				end)
			end
		end,
	},
}

function def.release(_run): boolean
	return true
end

function def.event(run, event): boolean
	local kind = event.kind
	local blue = run.style.primary
	if kind == "Dash" then
		local to = run.context.toWorld(event.column, event.row)
		Kit.groove(run, 0, 0.6, blue, run:ground(), to, 0.3)
		Kit.zap(run:ground() + Vector3.new(0, 0.3, 0), to + Vector3.new(0, 0.3, 0), WHITE, 0.15, 0.25, 4)
		run:sound("whoosh", 2)
		return false -- the afterimages still show the lunge
	elseif kind == "Damage" and event.target and not event.dot then
		local view = run.context.views[event.target]
		if view and not run.memo.hit then
			run.memo.hit = true -- one strike per cast (it hits one enemy)
			local at = view.part.Position
			ImpactEffects.ball(at, WHITE, 2.2, 0.1)
			Kit.shell(run, 0, 0.25, blue, at, function(u)
				return 3.6 * Kit.easeOut(u)
			end, function(u)
				return 0.3 + 0.7 * u
			end)
			for i = 1, (if run.reduced then 2 else 4) do
				local angle = i / 4 * 2 * math.pi
				Kit.zap(
					at,
					at + Vector3.new(math.cos(angle) * 2.5, (math.random() - 0.3) * 1.5, math.sin(angle) * 2.5),
					WHITE,
					0.14,
					0.18,
					2
				)
			end
			run:hitStop(view, 0.1)
			run:shake(0.18)
		end
		return true
	end
	return false -- the stun and the burn keep their markers
end

return def
