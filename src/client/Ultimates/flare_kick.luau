-- flare_kick (Tier 2): the spinning flaming leg. The real cast (instant, no cast time) dashes him to
-- the lowest-health enemy nearby and kicks it, at the Cast event.
--   -0.15  he spins on one leg; the leg catches fire, red-orange
--    0     a flaming dash kick along the real dash, a trail of fire; a flame burst on the real hit
--   +0.30  he lands balanced on one foot and straightens his tie
-- Layers: the shared recipe (VfxRecipe, fire theme, tier 2) and the batch 2 kit: the fire flipbook
-- loop licking up the leg (shin and foot) through the spin and the kick, an orange-red swoosh
-- (fx_swoosh_ribbon; the slash crescent until it loads) on the kick, a fire bloom (fx_fire_burst)
-- on the hit, embers.

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

-- Real flames on the leg: orange -> red -> deep red (no white or pale yellow wisps).
local LEG_FIRE = VfxRecipe.colors({
	{ 0, Color3.fromRGB(255, 165, 45) },
	{ 0.35, Color3.fromRGB(255, 100, 25) },
	{ 0.75, Color3.fromRGB(210, 40, 15) },
	{ 1, Color3.fromRGB(110, 15, 8) },
})
-- The fire theme with the leg's flames (the trail along the ground too).
local KICK_FIRE = table.clone(VfxRecipe.themes.fire)
KICK_FIRE.flames = LEG_FIRE

-- The leg on fire now: tall fire-flipbook flames standing on the foot and reaching the knee (one
-- emit of three flames: one effect host, inside the tier's budget).
local function legFire(run, strong: boolean)
	local s = run:scale()
	local foot, knee = legPoint(run, 0.95), legPoint(run, 0.45)
	VfxRecipe.flames(foot:Lerp(knee, 0.45), 3, (if strong then 2.6 else 2.2) * s, LEG_FIRE)
end

-- The fire trail along the dash (or, with no real dash, along the kick to the target).
local function fireTrail(run, to: Vector3)
	VfxRecipe.trail(
		run,
		run:ground(),
		to,
		{ theme = KICK_FIRE, steps = 3, span = 0.12, size = 1.4 * run:scale(), sparks = false }
	)
	VfxRecipe.sparks(run:chest(), 0.5, 14, nil, run:forward())
end

def.beats = {
	{
		at = -0.15,
		run = function(run)
			run:face(run:target())
			-- The leg catches fire through the spin and stays lit through the kick (7 bursts of
			-- flames, each living ~0.6 s, so the leg burns without gaps), a few embers off it.
			for t = -0.14, 0.31, 0.07 do
				run:at(t, function()
					legFire(run, t >= -0.05 and t <= 0.15)
				end)
			end
			run:at(-0.05, function()
				VfxRecipe.embers(run, legPoint(run, 0.8), run:scale(), nil, 6)
			end)
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
			-- The kick: an orange-red swoosh across the target, the fire bloom on the hit, flames
			-- licking up it, sparks flung along the kick, embers, a light.
			local at = view.part.Position
			local floor = at - Vector3.new(0, view.part.Size.Y / 2, 0)
			local s = run:scale()
			-- (No light here: the PointLight read as a pinkish glow blob on the floor.) The swoosh
			-- lies in the kick's swing plane (forward and up: its normal is his side), 1.2x the
			-- target's height, orange-red. No flames at the hit: the leg fire is enough (budget).
			local forward = run:forward()
			local sideways = Vector3.new(-forward.Z, 0, forward.X)
			VfxRecipe.kitSwoosh(at, view.part.Size.Y * 1.2, Color3.fromRGB(255, 90, 25), sideways, 30, 0.28)
			VfxRecipe.kitFireBurst(floor, view.part.Size.Y * 1.4 * s)
			VfxRecipe.sparks(at, 0.6, 18, nil, forward)
			VfxRecipe.embers(run, at, s, nil, 10)
			run:hitStop(view, 0.06)
			run:shake(0.1)
			run:sound("whoosh", 1.6)
		end
		return true
	end
	return false
end

return def
