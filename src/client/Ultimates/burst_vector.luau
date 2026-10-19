-- burst_vector (Tier 2): loud orange explosions and the rocket jump. The real cast blasts everything
-- within 1 hex of his target and raises his attack damage, at the Cast event.
--   -0.35  his palms pop with little sparks
--   -0.22  a palm blast under him: a rocket jump up and toward the fight
--    0     the real hit: a big orange-black explosion on the target and its neighbors, smoke
--   +0.25  he drops into a crouch, sparks crackling, an orange glow for the buff
-- Layers: the shared recipe (VfxRecipe, fire theme, tier 2: smaller and quicker than snapfire) and
-- the batch 2 kit: the hit is a chain of three fire blooms (fx_fire_burst) from his palm to the
-- target, each bigger, with embers and debris, the smoke aftermath, a shock ring
-- (mesh_shock_ring) on the last.

local FxKit = require(script.Parent.Parent.FxKit)
local VfxRecipe = require(script.Parent.Parent.VfxRecipe)

local rgb = Color3.fromRGB
-- The aftermath's smoke (snapfire's): dark gray, a little lighter as it thins.
local SMOKE_GRAY = VfxRecipe.colors({ { 0, rgb(72, 70, 70) }, { 1, rgb(52, 51, 52) } })

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
			VfxRecipe.smoke(run:ground(), 1.6 * s, 2, SMOKE_GRAY)
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
		-- The chain: three fire blooms from his palm to the target, each bigger, the last on the
		-- real area with a shock ring, sparks, two chunks of debris and a light; then fewer ground
		-- flames (budget) and snapfire's aftermath smoke: half size, dark gray (not red), one wave,
		-- gone within ~1.2 s.
		local center, radius = run:area()
		local palm = run:hand("right")
		local palmGround = Vector3.new(palm.X, center.Y, palm.Z)
		local fire = VfxRecipe.themes.fire
		for i = 1, 3 do
			local at = palmGround:Lerp(center, i / 3)
			VfxRecipe.kitFireBurst(at, radius * (0.6 + 0.4 * i), 0.08 * (i - 1))
		end
		run:at(run:designTime() + 0.16, function()
			VfxRecipe.meshRing(center, radius * 1.2, fire.edge, 0.4)
			VfxRecipe.sparks(center + Vector3.new(0, 1.2, 0), 0.85, nil, fire.spark)
			VfxRecipe.debris(center, 2, 0.3 * run:scale(), nil, radius)
			VfxRecipe.embers(run, center + Vector3.new(0, 0.8, 0), run:scale(), nil, 14)
			VfxRecipe.light(run, center + Vector3.new(0, 1.2, 0), radius, fire.light, 0.9)
			VfxRecipe.aftermath(run, center, radius, {
				flames = 0.4,
				smokeScale = 0.5,
				smokeLifetime = { 0.7, 0.95 },
				smoke = SMOKE_GRAY,
				smokeWaves = 1,
			})
		end)
		run:shake(0.18)
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
