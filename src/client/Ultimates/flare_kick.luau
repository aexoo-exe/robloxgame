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

-- Near his kicking foot.
local function foot(run): Vector3
	return run:ground() + run:forward() * 0.6 + Vector3.new(0, 0.9, 0)
end

def.beats = {
	{
		at = -0.15,
		run = function(run)
			run:face(run:target())
			for t = -0.14, 0, 0.05 do
				run:at(t, function()
					-- The leg catching fire: flames climbing it, a few embers.
					local s = run:scale()
					VfxRecipe.flames(foot(run), 2, 0.9 * s)
					VfxRecipe.embers(run, foot(run), s, nil, 3)
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
	if kind == "Dash" then
		local to = run.context.toWorld(event.column, event.row)
		Kit.groove(run, 0, 0.45, run.style.primary, run:ground(), to, 0.4)
		-- The trail of fire along the real dash: flames, streak sparks, scorch.
		VfxRecipe.trail(run, run:ground(), to, { steps = 4, span = 0.12, size = 1.2 * run:scale() })
		return false
	elseif kind == "Damage" and event.target and not event.dot then
		local view = run.context.views[event.target]
		if view then
			-- The flame burst on the real hit, sparks flung along the kick.
			local at = view.part.Position
			VfxRecipe.hit(run, at, view.part.Size.Y, nil, run:forward())
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
