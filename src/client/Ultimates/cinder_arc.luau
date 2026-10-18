-- cinder_arc (Tier 1): one clean arc of fire. The real cast cuts his target, splashes magic over
-- everything within 1 hex of it and speeds up his attacks, at the Cast event.
--   -0.20  the blade drawn back in both hands, low; embers glow along it
--    0     one wide circular slash leaving a ring of fire; it bursts out over the real splash
--   +0.30  the blade held forward, a warm glow for his attack speed
-- Layers (tier 1, within its 14): the batch 2 kit's fire spiral is the hero: three swoosh ribbons
-- (fx_swoosh_ribbon; the slash crescent until it loads) turning around him, tinted yellow -> orange
-- -> crimson, each trailing fire-flipbook flames, embers drifting up; one modest fire bloom
-- (fx_fire_burst) over the real splash. No recipe burst (its glow sheet washed out the screen).

local VfxRecipe = require(script.Parent.Parent.VfxRecipe)

local rgb = Color3.fromRGB
-- The spiral's three turns, hottest first: saturated, so the tint shows (not cream).
local SPIRAL = { rgb(255, 210, 60), rgb(255, 120, 20), rgb(200, 30, 20) }

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
		local s = run:scale()
		local height = run.view.part.Size.Y
		local body = run:chest()
		local ground = run:ground()
		-- The hero: a fire spiral of three swooshes turning around him (yellow -> orange -> crimson,
		-- each a little bigger and a beat later, at most 1.4x his height), each lying in its own
		-- tilted swing plane turned 120 degrees on from the last (world-oriented, never facing the
		-- camera), trailing two fire-flipbook flames on its turn around him.
		for i, color in SPIRAL do
			local turn = math.rad(120 * (i - 1))
			local plane = (CFrame.Angles(0, turn, 0) * CFrame.Angles(math.rad(28), 0, 0)).UpVector
			run:at(run:designTime() + 0.05 * (i - 1), function()
				local lift = Vector3.new(0, height * (0.05 * i - 0.1), 0) -- rising: a spiral, not a stack
				VfxRecipe.kitSwoosh(body + lift, height * (0.95 + 0.15 * i) * s, color, plane, 120 * (i - 1), 0.32)
				local reach = height * (0.55 + 0.15 * i) * s
				for k = 0, if run.reduced then 0 else 1 do
					local angle = turn + math.rad(50 * k)
					local at = ground + Vector3.new(math.cos(angle), 0, math.sin(angle)) * reach
					VfxRecipe.flames(at + Vector3.new(0, 0.1, 0), 1, (1.3 + 0.2 * i) * s)
				end
			end)
		end
		-- Embers drifting up off the spiral, and the cut bursting out over the real splash: one
		-- modest fire bloom (no big glow sheet: the spiral is the hero). Tier 1: ~11 layers live.
		VfxRecipe.embers(run, body, s, nil, 14)
		VfxRecipe.kitFireBurst(center, radius * 0.9, 0.12)
		run:sound("whoosh", 1.4)
		return true
	elseif kind == "Buff" and event.target == run.unitIndex then
		-- The attack speed glow: embers off the blade (no ring).
		run:at(0.3, function()
			VfxRecipe.embers(run, run:hand("right"), run:scale(), nil, 8)
		end)
		return true
	elseif kind == "Damage" and event.target and not event.dot then
		return true
	end
	return false
end

return def
