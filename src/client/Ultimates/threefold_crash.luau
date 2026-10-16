-- threefold_crash (Tier 3): three blades, two cuts and a tornado. The real cast hits his target at
-- the Cast event and again 0.25 s later, then at 0.5 s hits everything next to him and stuns his
-- target.
--   -0.25  the third sword in his teeth, the two in his hands crossed before him; a green aura
--    0     cut one on the real first hit: a green-white arc, the right blade sweeping across
--   +0.25  cut two on the real second hit: the crossing arc, the left blade
--   +0.50  the full spin on the real area hit: a green tornado ring of three blade trails around
--          him, every neighbor hit (the stun on his target is the real one)
--   +0.85  he stops with both blades out, his back to the enemy, then turns back

local UltimateKit = require(script.Parent.Parent.UltimateKit)
local FxKit = require(script.Parent.Parent.FxKit)
local ImpactEffects = require(script.Parent.Parent.ImpactEffects)

local Kit = UltimateKit
local WHITE = Kit.WHITE

local def = {}

def.pose = {
	-- Crossed, cut right, cut left, arms wide through the spin, held, down.
	rightArm = {
		{ -0.25, 0 },
		{ -0.12, 75 },
		{ -0.02, 78 },
		{ 0.04, 30, "snap" },
		{ 0.2, 60 },
		{ 0.3, 50 },
		{ 0.5, 80 },
		{ 1.15, 80 },
		{ 1.35, 0 },
	},
	rightArmOut = {
		{ -0.25, 0 },
		{ -0.12, -28 },
		{ -0.02, -28 },
		{ 0.04, 45, "snap" },
		{ 0.2, 10 },
		{ 0.5, 85 },
		{ 1.15, 85 },
		{ 1.35, 0 },
	},
	leftArm = {
		{ -0.25, 0 },
		{ -0.12, 75 },
		{ 0.2, 78 },
		{ 0.29, 30, "snap" },
		{ 0.42, 60 },
		{ 0.5, 80 },
		{ 1.15, 80 },
		{ 1.35, 0 },
	},
	leftArmOut = {
		{ -0.25, 0 },
		{ -0.12, -28 },
		{ 0.2, -28 },
		{ 0.29, 45, "snap" },
		{ 0.42, 10 },
		{ 0.5, 85 },
		{ 1.15, 85 },
		{ 1.35, 0 },
	},
	twist = { { -0.25, 0 }, { -0.02, -10 }, { 0.04, 26, "snap" }, { 0.2, 8 }, { 0.29, -26, "snap" }, { 0.45, 0 } },
	crouch = { { -0.25, 0 }, { -0.12, 0.14 }, { 0.5, 0.1 }, { 0.8, 0.06 }, { 1.35, 0 } },
	-- One and a half turns (his back to the enemy), held, then the turn back to face it.
	spin = { { 0.5, 0 }, { 0.82, 540, "out" }, { 1.15, 540 }, { 1.32, 360 }, { 1.33, 0, "hold" } },
}

def.beats = {
	{
		at = -0.25,
		run = function(run)
			run:face(run:target())
			Kit.aura(run, -0.25, 0.4, run.style.primary, if run.reduced then 4 else 7, function(u)
				return run.view.part.Size.Y * (0.5 + 0.4 * u)
			end)
		end,
	},
}

function def.release(_run): boolean
	return true
end

function def.event(run, event): boolean
	local kind = event.kind
	local green = run.style.primary
	if kind == "Damage" and event.target and not event.dot and not run.memo.spun then
		local view = run.context.views[event.target]
		if view then
			run.memo.cuts = (run.memo.cuts or 0) + 1
			local tilt = if run.memo.cuts % 2 == 1 then 0.7 else -0.7
			local at = view.part.Position + Vector3.new(0, view.part.Size.Y * 0.1, 0)
			local facing = view.part.Position - run.view.part.Position
			FxKit.slashArc(at, facing, green, 3 * run:scale(), tilt, 0.28)
			ImpactEffects.ball(at, WHITE, 1.4, 0.08)
			run:hitStop(view, 0.06)
			run:shake(0.1)
			run:sound("whoosh", 1.8)
		end
		return true
	elseif kind == "Area" then
		if run.memo.spun then
			return true -- one tornado per cast
		end
		run.memo.spun = true
		local center, radius = run:area()
		for i = 0, 2 do
			FxKit.ring(center, if i == 1 then WHITE else green, radius * (1.7 + 0.35 * i), 0.35, i * 0.07)
		end
		FxKit.spiral(center, green, radius * 0.75, 2.6, 0.45)
		Kit.slashes(
			run,
			run:designTime(),
			run:designTime() + 0.3,
			center,
			radius,
			if run.reduced then 4 else 6,
			{ green, WHITE },
			0.8
		)
		for _, target in run:targets() do
			run:hitStop(target, 0.08)
		end
		run:shake(0.18)
		run:sound("whoosh", 1.2)
		return true
	elseif kind == "Damage" and event.target and not event.dot then
		return true -- the spin's neighbors: the tornado covers them
	end
	return false
end

return def
