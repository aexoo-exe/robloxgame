-- orbit_breaker (Tier 2): the ricochet steel ball and its golden spiral. The real cast hits and
-- stuns the enemy in front, then bounces to the nearest other enemy (twice while mounted), at the
-- Cast event.
--   -0.35  a steel ball spins in his palm, golden spiral lines turning around it
--   -0.12  a sidearm whip: the ball flies to the target
--    0     the real hit: a spiral shock (the stun is the real one); on each real bounce a golden
--          spiral at the next enemy

local UltimateKit = require(script.Parent.Parent.UltimateKit)
local FxKit = require(script.Parent.Parent.FxKit)
local ImpactEffects = require(script.Parent.Parent.ImpactEffects)

local Kit = UltimateKit
local STEEL = Color3.fromRGB(205, 210, 220)

local def = {}

def.pose = {
	rightArm = { { -0.35, 0 }, { -0.2, 70, "out" }, { -0.14, 60 }, { -0.06, 85, "snap" }, { 0.3, 70 }, { 0.5, 0 } },
	rightArmOut = { { -0.35, 0 }, { -0.2, 20 }, { -0.14, 55 }, { -0.06, 10, "snap" }, { 0.5, 0 } },
	twist = { { -0.2, 0 }, { -0.14, -20 }, { -0.06, 22, "snap" }, { 0.3, 8 }, { 0.5, 0 } },
}

def.beats = {
	{
		at = -0.35,
		run = function(run)
			run:face(run:target())
			local gold = run.style.secondary
			for i = 1, (if run.reduced then 2 else 3) do
				Kit.live(run, -0.33, -0.12, "Ball", gold, function(part)
					local angle = i * 2.09 + run:now() * 18
					local hand = run:hand("right")
					part.Size = Vector3.one * 0.12
					part.CFrame = CFrame.new(
						hand + Vector3.new(math.cos(angle) * 0.45, math.sin(angle * 2) * 0.12, math.sin(angle) * 0.45)
					)
					part.Transparency = 0.1
				end)
			end
			run:sound("tick", 1.5)
		end,
	},
	{
		at = -0.12,
		run = function(run)
			local target = run:target()
			if not target then
				return
			end
			local from = run:hand("right")
			Kit.live(run, -0.12, 0, "Ball", STEEL, function(part, u)
				part.Size = Vector3.one * 0.45
				part.CFrame = CFrame.new(from:Lerp(target.part.Position, u)) * CFrame.Angles(u * 20, 0, 0)
				part.Transparency = 0
			end, Enum.Material.Metal)
			run:sound("whoosh", 1.8)
		end,
	},
}

function def.release(_run): boolean
	return true
end

-- A golden spiral shock at `view`.
local function spiralShock(run, view, scale: number)
	local floor = view.part.Position - Vector3.new(0, view.part.Size.Y / 2, 0)
	FxKit.spiral(floor, run.style.secondary, 1.2 * scale, view.part.Size.Y * 0.9, 0.35)
	ImpactEffects.ball(view.part.Position, STEEL, 1.4 * scale, 0.1)
end

function def.event(run, event): boolean
	local kind = event.kind
	if kind == "Damage" and event.target and not event.dot then
		local view = run.context.views[event.target]
		if view and not run.memo.first then
			run.memo.first = true
			spiralShock(run, view, 1)
			run:hitStop(view, 0.06)
			run:shake(0.1)
		end
		return true
	elseif kind == "Bounce" and event.target then
		local view = run.context.views[event.target]
		if view then
			spiralShock(run, view, 0.75)
		end
		return true
	end
	return false
end

return def
