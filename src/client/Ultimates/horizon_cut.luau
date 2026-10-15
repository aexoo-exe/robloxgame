-- horizon_cut (Tier 3): the black crescent across the board. The real cast is one big magic hit on
-- the farthest enemy at the Cast event, so the crescent launches just before and lands on it.
--   -0.75  the huge cleaver goes up, black energy with a red edge pouring off it
--   -0.45  held high, the energy thickening; the ground darkens under him
--   -0.28  the swing: a giant black crescent with a red rim launches flat across the board, cutting
--          a scorched line on the ground behind it
--    0     the real hit: a black-red slash cross on the target, a flash, a shockwave
--   +0.20  the blade comes to rest on his shoulder; the line fades

local UltimateKit = require(script.Parent.Parent.UltimateKit)
local FxKit = require(script.Parent.Parent.FxKit)
local ImpactEffects = require(script.Parent.Parent.ImpactEffects)

local Kit = UltimateKit
local WHITE = Kit.WHITE
local SCORCH = Color3.fromRGB(30, 14, 18)

local LAUNCH = -0.28 -- the crescent leaves the blade

local def = {}

def.pose = {
	rightArm = {
		{ -0.75, 0 },
		{ -0.5, 172, "out" },
		{ -0.32, 175 },
		{ -0.22, 30, "snap" },
		{ 0.15, 40 },
		{ 0.3, 150 },
		{ 0.5, 150 },
		{ 0.75, 0 },
	},
	rightArmOut = { { 0.15, 0 }, { 0.3, -30 }, { 0.5, -30 }, { 0.75, 0 } },
	leftArm = { { -0.75, 0 }, { -0.5, 160 }, { -0.32, 165 }, { -0.22, 25, "snap" }, { 0.4, 0 } },
	twist = { { -0.5, 0 }, { -0.32, -18 }, { -0.22, 24, "snap" }, { 0.2, 10 }, { 0.75, 0 } },
	lean = { { -0.75, 0 }, { -0.5, -10 }, { -0.32, -12 }, { -0.22, 16, "snap" }, { 0.2, 4 }, { 0.75, 0 } },
	crouch = { { -0.32, 0.04 }, { -0.22, 0.16, "snap" }, { 0.3, 0 } },
}

def.beats = {
	{
		at = -0.75,
		run = function(run)
			local target = run:target()
			run:face(target)
			-- Energy pouring off the raised blade.
			for i = 0, (if run.reduced then 3 else 6) do
				run:at(-0.7 + i * 0.06, function()
					ImpactEffects.burst("smoke", run:hand("right") + Vector3.new(0, 1.5, 0), Vector3.yAxis, {
						color = run.style.primary,
						color2 = run.style.secondary,
						count = 4,
						size = 0.8 + i * 0.1,
						speed = { 1, 3 },
						lifetime = { 0.4, 0.7 },
						spread = 40,
						transparency = 0.25,
					})
				end)
			end
			Kit.pool(run, -0.45, 0.4, SCORCH, run:ground(), function(u)
				return 6 * Kit.easeOut(u * 2)
			end, function(u)
				return 0.3 + 0.7 * Kit.easeIn(u)
			end, Enum.Material.Glass)
			run:sound("charge", 0.6)
		end,
	},
	{
		-- The swing: the crescent crosses the board to the target, a scorched line behind it.
		at = LAUNCH,
		run = function(run)
			local target = run:target()
			if not target then
				return
			end
			local from = run:chest() + run:forward() * 1.5
			local to = target.part.Position
			FxKit.wave(from, to, run.style.primary, 2.6 * run:scale(), -LAUNCH)
			FxKit.wave(from, to, run.style.secondary, 1.6 * run:scale(), -LAUNCH, 0.02)
			Kit.groove(run, LAUNCH, 0.5, SCORCH, run:ground(), to - Vector3.new(0, target.part.Size.Y / 2, 0), 0.5)
			run:sound("whoosh", 1.4)
		end,
	},
}

function def.release(_run): boolean
	return true
end

function def.event(run, event): boolean
	if event.kind ~= "Damage" or not event.target or event.dot then
		return false
	end
	local view = run.context.views[event.target]
	if view and not run.memo.hit then
		run.memo.hit = true -- one cross per cast (it hits one enemy)
		local at = view.part.Position + Vector3.new(0, view.part.Size.Y * 0.1, 0)
		local facing = view.part.Position - run.view.part.Position
		FxKit.slashArc(at, facing, run.style.primary, 3 * run:scale(), 0.8, 0.3)
		FxKit.slashArc(at, facing, run.style.secondary, 2.8 * run:scale(), -0.8, 0.3, 0.03)
		ImpactEffects.ball(at, WHITE, 1.8, 0.1)
		FxKit.ring(view.part.Position - Vector3.new(0, view.part.Size.Y / 2, 0), run.style.secondary, 5, 0.3)
		run:hitStop(view, 0.08)
		run:shake(0.18)
	end
	return true
end

return def
