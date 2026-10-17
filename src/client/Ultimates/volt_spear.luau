-- volt_spear (Tier 3): the lightning in the hand, dragged along the ground. The real cast lunges him
-- at his target, hits it with lightning, stuns it and leaves it burning, at the Cast event.
--   -0.45  his hand held down and back; a crackling blue-white ball forms in it, flickering with a
--          rapid chirp
--   -0.15  he drops low, leaning in
--    0     the lunge on the real dash: lightning tears a line in the ground; the strike: a burst of
--          lightning through the target (the stun and the burn marker are the real ones)
-- Layers: the shared recipe (VfxRecipe, a lightning theme in his blue, tier 3).

local UltimateKit = require(script.Parent.Parent.UltimateKit)
local VfxRecipe = require(script.Parent.Parent.VfxRecipe)

local Kit = UltimateKit
local WHITE = Kit.WHITE

local def = {}

-- His lightning: blue arcs with a white-hot core.
local function theme(run)
	run.memo.theme = run.memo.theme or VfxRecipe.lightning(run.style.primary, WHITE:Lerp(run.style.primary, 0.4))
	return run.memo.theme
end

def.pose = {
	rightArm = { { -0.45, 0 }, { -0.3, -35, "out" }, { -0.02, -40 }, { 0.04, 96, "snap" }, { 0.4, 85 }, { 0.7, 0 } },
	rightArmOut = { { -0.45, 0 }, { -0.3, 18 }, { 0.04, 0, "snap" }, { 0.7, 0 } },
	leftArm = { { -0.45, 0 }, { -0.3, 30 }, { 0.04, -10, "snap" }, { 0.7, 0 } },
	crouch = { { -0.3, 0 }, { -0.15, 0.2 }, { 0.04, 0.12, "snap" }, { 0.5, 0 } },
	lean = { { -0.3, 0 }, { -0.15, 18 }, { 0.04, 12, "snap" }, { 0.5, 0 } },
	twist = { { -0.3, 0 }, { -0.15, -16 }, { 0.04, 20, "snap" }, { 0.4, 8 }, { 0.7, 0 } },
}

def.beats = {
	{
		at = -0.45,
		run = function(run)
			run:face(run:target())
			local blue = run.style.primary
			Kit.orb(run, -0.4, 0.05, WHITE:Lerp(blue, 0.4), function()
				return run:hand("right")
			end, function(u)
				return (0.4 + 0.4 * u) * run:scale()
			end)
			-- The chirping flicker: short arcs off the ball.
			for i = 0, (if run.reduced then 5 else 11) do
				run:at(-0.42 + i * 0.04, function()
					-- 3 arcs ~1.5 studs off the ball, renewed before the last ones die: a constant crackle.
					VfxRecipe.crackle(run, run:hand("right"), 1.5, theme(run), if run.reduced then 2 else 3)
					if i % 2 == 0 then
						run:sound("tick", 2)
					end
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
	local blue = run.style.primary
	if kind == "Dash" then
		local to = run.context.toWorld(event.column, event.row)
		Kit.groove(run, 0, 0.6, blue, run:ground(), to, 0.3)
		-- Lightning tearing a line in the ground: arcs along it, sparks and scorch marks behind.
		-- A thick jagged bolt along the ground, 3 strands, renewed once so it holds ~0.45 s.
		local lift = Vector3.new(0, 0.45, 0)
		local from = run:ground()
		VfxRecipe.arcs(run, from + lift, to + lift, theme(run), 3, 1.3 * run:scale(), 0.3)
		run:at(run:designTime() + 0.15, function()
			VfxRecipe.arcs(run, from + lift, to + lift, theme(run), 2, 1.1 * run:scale(), 0.3)
		end)
		VfxRecipe.trail(
			run,
			run:ground(),
			to,
			{ theme = theme(run), steps = 4, span = 0.1, size = 0.8 * run:scale(), sparks = false }
		)
		run:sound("whoosh", 2)
		return false -- the afterimages still show the lunge
	elseif kind == "Damage" and event.target and not event.dot then
		local view = run.context.views[event.target]
		if view and not run.memo.hit then
			run.memo.hit = true -- one strike per cast (it hits one enemy)
			local at = view.part.Position
			-- The burst of lightning through the target: a core, a blue glow sheet, sparks, a light,
			-- and arcs leaping off it.
			-- A proper burst on the target: core, blue glow sheet, arcs out, shockwave, sparks, light.
			local floor = at - Vector3.new(0, view.part.Size.Y / 2, 0)
			VfxRecipe.burst(run, floor, 1.8 * run:scale(), { theme = theme(run) })
			VfxRecipe.crackle(run, at, 2.6 * run:scale(), theme(run), if run.reduced then 2 else 4)
			run:hitStop(view, 0.1)
			run:shake(0.18)
		end
		return true
	end
	return false -- the stun and the burn keep their markers
end

return def
