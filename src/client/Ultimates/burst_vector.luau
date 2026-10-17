-- burst_vector (Tier 2): loud orange explosions and the rocket jump. The real cast blasts everything
-- within 1 hex of his target and raises his attack damage, at the Cast event.
--   -0.35  his palms pop with little sparks
--   -0.22  a palm blast under him: a rocket jump up and toward the fight
--    0     the real hit: a big orange-black explosion on the target and its neighbors, smoke
--   +0.25  he drops into a crouch, sparks crackling, an orange glow for the buff
-- Layers: the shared recipe (VfxRecipe, fire theme, tier 2: smaller and quicker than snapfire).

local FxKit = require(script.Parent.Parent.FxKit)
local VfxRecipe = require(script.Parent.Parent.VfxRecipe)

local def = {}

def.pose = {
	leftArm = { { -0.35, 0 }, { -0.25, 60 }, { -0.22, -40, "snap" }, { 0, 90 }, { 0.3, 30 }, { 0.5, 0 } },
	rightArm = { { -0.35, 0 }, { -0.25, 60 }, { -0.22, -40, "snap" }, { 0, 90 }, { 0.3, 30 }, { 0.5, 0 } },
	rise = { { -0.22, 0 }, { -0.08, 1.8, "out" }, { 0.2, 0, "in" } },
	lean = { { -0.22, 0 }, { -0.08, 18 }, { 0.2, 10 }, { 0.5, 0 } },
	crouch = { { 0.15, 0 }, { 0.22, 0.25, "snap" }, { 0.5, 0 } },
}

def.beats = {
	{
		at = -0.35,
		run = function(run)
			run:face(run:target())
			-- His palms pop: a small flash, stars, a little light at each.
			for _, side in { "left", "right" } do
				VfxRecipe.pop(run, run:hand(side), 0.9 * run:scale())
			end
			run:sound("tick", 1.1)
		end,
	},
	{
		-- The palm blast he rides up.
		at = -0.22,
		run = function(run)
			-- A small explosion under his palms, sparks, a puff of dark smoke he rises out of.
			local s = run:scale()
			local under = run:ground() + Vector3.new(0, 0.5, 0)
			VfxRecipe.core(under, 1.2 * s, 1)
			VfxRecipe.explosion(under, 1 * s)
			VfxRecipe.sparks(under, 0.5 * s, 16)
			VfxRecipe.smoke(run:ground(), 1.6 * s, if run.reduced then 2 else 4)
			VfxRecipe.light(run, under, 1.6 * s, VfxRecipe.themes.fire.light, 0.6)
			run:sound("whoosh", 1.3)
		end,
	},
}

function def.release(_run): boolean
	return true
end

function def.event(run, event): boolean
	local kind = event.kind
	if kind == "Area" then
		-- The orange-black explosion over the real area (core, explosion, shockwave, sparks, light,
		-- scorch), then flames and dark smoke.
		local center, radius = run:area()
		VfxRecipe.burst(run, center, radius)
		VfxRecipe.aftermath(run, center, radius)
		run:sound("whoosh", 0.7)
		return true
	elseif kind == "Buff" and event.target == run.unitIndex then
		run:at(0.25, function()
			FxKit.ring(run:ground(), run.style.primary, 4, 0.35)
			VfxRecipe.sparks(run:ground() + Vector3.new(0, 0.4, 0), 0.4 * run:scale(), 10)
		end)
		return true
	elseif kind == "Damage" and event.target and not event.dot then
		return true
	end
	return false
end

return def
