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

local VOLT = Color3.fromRGB(70, 150, 255) -- a saturated electric blue his pale blue leans toward

-- His lightning: arcs in a strong blue (never washed out to white), with a white-hot core.
local function theme(run)
	if not run.memo.theme then
		local blue = run.style.primary:Lerp(VOLT, 0.55)
		run.memo.theme = VfxRecipe.lightning(blue, WHITE:Lerp(blue, 0.5))
	end
	return run.memo.theme
end

-- Thick crackle off a point: `count` blue arcs ~`reach` studs out (wider than VfxRecipe.crackle's).
local function crackle(run, at: Vector3, reach: number, count: number)
	local color = theme(run).crackle
	for i = 1, if run.reduced then 1 else count do
		local direction = Vector3.new(math.random() - 0.5, math.random() - 0.3, math.random() - 0.5)
		direction = if direction.Magnitude > 1e-3 then direction.Unit else Vector3.yAxis
		VfxRecipe.arc(at + direction * reach * 0.1, at + direction * reach, color, 0.9 * run:scale(), 0.25, 0.03 * (i - 1))
	end
	VfxRecipe.sparks(at, 0.35, 6, theme(run).spark)
end

-- The bolt tearing along the ground from him to `to` (the real dash's end, or the target), a
-- second strand crossing it 0.1 s later, sparks and scorch behind (~0.45 s in all).
local function groundBolt(run, to: Vector3)
	-- Raised a full stud: its thin neon core never grazes the floor.
	local lift = Vector3.new(0, 1, 0)
	local from = run:ground()
	VfxRecipe.arcs(run, from + lift, to + lift, theme(run), 1, 1.6 * run:scale(), 0.4)
	run:at(run:designTime() + 0.1, function()
		VfxRecipe.arcs(run, from + lift, to + lift, theme(run), 1, 1.2 * run:scale(), 0.35, false)
	end)
	VfxRecipe.trail(run, from, to, { theme = theme(run), steps = 4, span = 0.1, size = 0.8 * run:scale(), sparks = false })
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
			local blue = theme(run).crackle
			Kit.orb(run, -0.4, 0.05, WHITE:Lerp(blue, 0.5), function()
				return run:hand("right")
			end, function(u)
				return (0.4 + 0.4 * u) * run:scale()
			end)
			-- The chirping flicker: short arcs off the ball.
			for i = 0, (if run.reduced then 3 else 6) do
				run:at(-0.42 + i * 0.06, function()
					-- An arc ~1.5 studs off the ball every beat; they overlap (each lives longer than a beat), so
					-- several crackle at once, all the windup long.
					crackle(run, run:hand("right"), 1.6, 1)
					if i % 2 == 0 then
						run:sound("tick", 2)
					end
				end)
			end
		end,
	},
}

function def.release(run): boolean
	-- Already next to his target (no real dash): the bolt still tears along the ground to it.
	if not run:find("Dash") then
		local target = run:target()
		if target then
			groundBolt(run, target.part.Position - Vector3.new(0, target.part.Size.Y / 2, 0))
		end
	end
	return true
end

function def.event(run, event): boolean
	local kind = event.kind
	if kind == "Dash" then
		local to = run.context.toWorld(event.column, event.row)
		Kit.groove(run, 0, 0.6, theme(run).crackle, run:ground(), to, 0.3)
		groundBolt(run, to)
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
			-- One thick arc leaping off it (more would pass the tier's part budget with the bolt).
			crackle(run, at, 2.6 * run:scale(), 1)
			run:hitStop(view, 0.1)
			run:shake(0.18)
		end
		return true
	end
	return false -- the stun and the burn keep their markers
end

return def
