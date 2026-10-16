-- bitter_vapor (Tier 1): the thrown vial and the bubbling cloud. The real cast poisons everything
-- within 1 hex of her target (they also deal less damage) and heals her lowest-health ally, at the
-- Cast event.
--   -0.20  she lifts a vial from her sleeve, sniffs it, and tosses it
--    0     it shatters on the target as the real poison lands: glass glints and a green bubbling
--          cloud over the area (the poison markers are the real ones)
--   +0.10  a little green leaf drifts to the ally she really heals

local UltimateKit = require(script.Parent.Parent.UltimateKit)
local FxKit = require(script.Parent.Parent.FxKit)
local ImpactEffects = require(script.Parent.Parent.ImpactEffects)

local Kit = UltimateKit
local GLASS = Color3.fromRGB(200, 240, 210)
local LEAF = Color3.fromRGB(110, 190, 90)

local def = {}

def.pose = {
	leftArm = { { -0.2, 0 }, { -0.12, 140, "out" }, { -0.08, 140 }, { -0.02, 70, "snap" }, { 0.3, 40 }, { 0.5, 0 } },
	leftArmOut = { { -0.2, 0 }, { -0.12, -20 }, { -0.02, 10 }, { 0.5, 0 } },
	lean = { { -0.2, 0 }, { -0.12, -4 }, { -0.02, 8, "snap" }, { 0.5, 0 } },
}

def.beats = {
	{
		at = -0.2,
		run = function(run)
			run:face(run:target())
		end,
	},
	{
		-- The toss: the vial arcs to the target, landing on the real hit.
		at = -0.1,
		run = function(run)
			local target = run:target()
			if not target then
				return
			end
			local from = run:hand("left")
			local to = target.part.Position
			Kit.live(run, -0.1, 0, "Block", run.style.primary, function(part, u)
				part.Size = Vector3.new(0.18, 0.3, 0.18)
				part.CFrame = CFrame.new(from:Lerp(to, u) + Vector3.new(0, math.sin(u * math.pi) * 2.2, 0))
					* CFrame.Angles(u * 10, 0, 0)
				part.Transparency = 0.1
			end, Enum.Material.Glass)
		end,
	},
}

function def.release(_run): boolean
	return true
end

function def.event(run, event): boolean
	local kind = event.kind
	if kind == "Dot" and event.target and not run.memo.cloud then
		run.memo.cloud = true
		local center, radius = run:area()
		ImpactEffects.burst("spark", center + Vector3.new(0, 1, 0), nil, {
			color = GLASS,
			count = 8,
			size = 0.16,
			speed = { 5, 9 },
			lifetime = { 0.12, 0.25 },
		})
		FxKit.disc(center, run.style.primary, radius * 2.2, 1.0, 0.55)
		ImpactEffects.burst("bubble", center + Vector3.new(0, 0.5, 0), Vector3.yAxis, {
			color = run.style.primary,
			count = 12,
			size = 0.5,
			speed = { 1, 3 },
			lifetime = { 0.5, 0.9 },
			spread = 60,
		})
		run:sound("splash", 1.6)
		return false -- the poison marker is the real status
	elseif kind == "Heal" and event.target and event.target ~= run.unitIndex then
		local view = run.context.views[event.target]
		if view then
			local from = run:hand("left")
			local to = view.part.Position
			Kit.block(run, 0.1, 0.6, LEAF, function(u)
				return CFrame.new(from:Lerp(to, Kit.smooth(u)) + Vector3.new(0, math.sin(u * math.pi) * 1.5, 0))
					* CFrame.Angles(0, u * 6, math.sin(u * 9) * 0.6)
			end, function()
				return Vector3.new(0.3, 0.05, 0.2)
			end, function(u)
				return if u > 0.85 then (u - 0.85) * 6 else 0
			end)
		end
		return true
	end
	return false
end

return def
