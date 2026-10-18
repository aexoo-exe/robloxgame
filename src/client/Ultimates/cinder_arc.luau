-- cinder_arc (Tier 1): one clean arc of fire. The real cast cuts his target, splashes magic over
-- everything within 1 hex of it and speeds up his attacks, at the Cast event.
--   -0.20  the blade drawn back in both hands, low; embers glow along it
--    0     one wide circular slash leaving a ring of fire; it bursts out over the real splash
--   +0.30  the blade held forward, a warm glow for his attack speed
-- Layers: the shared recipe (VfxRecipe, fire theme, tier 1: small, quick, a short aftermath) and
-- the batch 2 kit: the slash is a fire spiral of three swoosh ribbons (fx_swoosh_ribbon; the slash
-- crescent until it loads) turning around the target, tinted yellow -> orange -> crimson, with
-- fire-flipbook flames trailing the arc and embers drifting up.

local FxKit = require(script.Parent.Parent.FxKit)
local VfxRecipe = require(script.Parent.Parent.VfxRecipe)

local rgb = Color3.fromRGB
-- The spiral's three turns, hottest first.
local SPIRAL = { rgb(255, 225, 90), rgb(255, 140, 40), rgb(200, 35, 30) }

local def = {}

def.pose = {
	rightArm = { { -0.2, 0 }, { -0.1, -30 }, { -0.02, -35 }, { 0.05, 80, "snap" }, { 0.45, 75 }, { 0.6, 0 } },
	leftArm = { { -0.2, 0 }, { -0.1, -25 }, { -0.02, -30 }, { 0.05, 75, "snap" }, { 0.45, 70 }, { 0.6, 0 } },
	twist = { { -0.2, 0 }, { -0.1, -32 }, { 0.05, 34, "snap" }, { 0.3, 10 }, { 0.6, 0 } },
	crouch = { { -0.2, 0 }, { -0.1, 0.16 }, { 0.05, 0.1, "snap" }, { 0.5, 0 } },
}

def.beats = {
	{
		at = -0.2,
		run = function(run)
			run:face(run:target())
			-- Embers glowing off the blade, and a small flame licking it.
			local s = run:scale()
			VfxRecipe.embers(run, run:hand("right"), s, nil, 8)
			VfxRecipe.flames(run:hand("right"), 1, 0.7 * s)
		end,
	},
}

function def.release(_run): boolean
	return true
end

function def.event(run, event): boolean
	local kind = event.kind
	if kind == "Area" then
		local center, radius = run:area()
		local at = center + Vector3.new(0, 1.4, 0)
		-- The fire spiral: three swooshes turning around the target, each bigger, hotter first.
		for i, color in SPIRAL do
			run:at(run:designTime() + 0.04 * (i - 1), function()
				VfxRecipe.kitSwoosh(at, radius * (1.6 + 0.35 * i), color, -40 + 120 * (i - 1), 0.28)
			end)
		end
		-- Flames trailing the arc (the ring of fire it leaves), embers drifting up, then it bursts out
		-- over the real splash.
		VfxRecipe.flameRing(center, radius * 1.1, if run.reduced then 6 else 10, 1.3 * run:scale())
		VfxRecipe.embers(run, center + Vector3.new(0, 1, 0), run:scale(), nil, 14)
		run:at(0.05, function()
			VfxRecipe.burst(run, center, radius)
			VfxRecipe.aftermath(run, center, radius)
		end)
		run:sound("whoosh", 1.4)
		return true
	elseif kind == "Buff" and event.target == run.unitIndex then
		run:at(0.3, function()
			FxKit.ring(run:ground(), run.style.secondary, 3.5, 0.35)
		end)
		return true
	elseif kind == "Damage" and event.target and not event.dot then
		return true
	end
	return false
end

return def
