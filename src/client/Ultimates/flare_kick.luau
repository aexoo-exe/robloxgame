-- flare_kick (Tier 2): the spinning flaming leg. The real cast (instant, no cast time) dashes him to
-- the lowest-health enemy nearby and kicks it, at the Cast event.
--   -0.15  he spins on one leg; the leg catches fire, red-orange
--    0     a flaming dash kick along the real dash, a trail of fire; a flame burst on the real hit
--   +0.30  he lands balanced on one foot and straightens his tie
-- Layers: the shared recipe (VfxRecipe, fire theme, tier 2).

local UltimateKit = require(script.Parent.Parent.UltimateKit)
local VfxRecipe = require(script.Parent.Parent.VfxRecipe)

local Kit = UltimateKit

local def = {}

def.pose = {
	spin = { { -0.15, 0 }, { 0, 360, "in" }, { 0.01, 0, "hold" } },
	rightLeg = { { -0.15, 0 }, { -0.05, 40 }, { 0.02, 105, "snap" }, { 0.25, 60 }, { 0.4, 30 }, { 0.55, 0 } },
	lean = { { -0.15, 0 }, { 0.02, -18, "snap" }, { 0.25, -6 }, { 0.55, 0 } },
	rightArm = { { 0.3, 0 }, { 0.4, 120 }, { 0.5, 120 }, { 0.62, 0 } },
	rightArmOut = { { 0.3, 0 }, { 0.4, -30 }, { 0.5, -30 }, { 0.62, 0 } },
	leftArmOut = { { -0.15, 0 }, { 0, 40 }, { 0.3, 30 }, { 0.55, 0 } },
}

-- A point `f` of the way down his kicking leg (0 the hip, 1 the foot), following the pose; near the
-- foot for figures without legs.
local function legPoint(run, f: number): Vector3
	local figure = run.view.figure
	local leg = figure.anchors.rightLeg
	if leg and not figure.isModel then
		return (leg * CFrame.new(0, -run.view.part.Size.Y * 0.45 * f, 0)).Position
	end
	return run:ground() + run:forward() * 0.6 + Vector3.new(0, 0.9 + 0.6 * (1 - f), 0)
end

-- The leg on fire now: flames at the shin and foot, a few embers off it.
local function legFire(run, strong: boolean)
	local s = run:scale()
	VfxRecipe.flames(legPoint(run, 0.55), 1, 0.75 * s)
	VfxRecipe.flames(legPoint(run, 0.95), if strong then 2 else 1, 0.95 * s)
	VfxRecipe.embers(run, legPoint(run, 0.8), s, nil, 3)
end

-- The fire trail along the dash (or, with no real dash, along the kick to the target).
local function fireTrail(run, to: Vector3)
	VfxRecipe.trail(run, run:ground(), to, { steps = if run.reduced then 3 else 5, span = 0.12, size = 1.3 * run:scale() })
	VfxRecipe.sparks(run:chest(), 0.5, 14, nil, run:forward())
end

def.beats = {
	{
		at = -0.15,
		run = function(run)
			run:face(run:target())
			-- The leg catches fire through the spin and stays lit through the kick.
			for t = -0.14, 0.28, 0.04 do
				run:at(t, function()
					legFire(run, t >= -0.02 and t <= 0.15)
				end)
			end
		end,
	},
}

function def.release(run): boolean
	if not run:find("Dash") then
		local target = run:target()
		if target then
			fireTrail(run, target.part.Position - Vector3.new(0, target.part.Size.Y / 2, 0))
		end
	end
	return true
end

function def.event(run, event): boolean
	local kind = event.kind
	if kind == "Dash" then
		local to = run.context.toWorld(event.column, event.row)
		Kit.groove(run, 0, 0.45, run.style.primary, run:ground(), to, 0.4)
		-- The trail of fire along the real dash: flames, streak sparks, scorch.
		fireTrail(run, to)
		return false
	elseif kind == "Damage" and event.target and not event.dot then
		local view = run.context.views[event.target]
		if view then
			-- The fire burst on the real hit (the recipe's fire burst: core, fireball, shock ring,
			-- sparks, light, scorch), flames licking up the target, sparks flung along the kick.
			local at = view.part.Position
			local floor = at - Vector3.new(0, view.part.Size.Y / 2, 0)
			VfxRecipe.burst(run, floor, 1.3 * run:scale())
			VfxRecipe.sparks(at, 0.6, 18, nil, run:forward())
			VfxRecipe.flames(at - Vector3.new(0, view.part.Size.Y * 0.4, 0), 3, 1.3 * run:scale())
			run:hitStop(view, 0.06)
			run:shake(0.1)
			run:sound("whoosh", 1.6)
		end
		return true
	end
	return false
end

return def
