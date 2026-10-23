-- volt_spear (Tier 3): the lightning in the hand, dragged along the ground. The real cast lunges him
-- at his target, hits it with lightning, stuns it and leaves it burning, at the Cast event.
--   -0.45  his hand held down and back; a crackling blue-white ball forms in it, flickering with a
--          rapid chirp
--   -0.15  he drops low, leaning in
--    0     the lunge on the real dash: lightning tears a line in the ground; the strike: a burst of
--          lightning through the target (the stun and the burn marker are the real ones)
-- Layers: the batch 2 kit in his blue-white (no part-based arcs, no neon rod): a 0.4 s charge of
-- crackle at his hand (fx_crackle), lightning bolts along the ground (fx_lightning), and on the
-- thrust a burst of 4-6 bolts out of the target, a hit star (fx_impact_star) and a shock ring
-- (mesh_shock_ring), over the recipe's core flash, glow sheet, sparks and light (tier 3).

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

-- His blue-white: the kit's white-cored textures tinted toward his blue.
local function blueWhite(run): Color3
	return theme(run).crackle:Lerp(WHITE, 0.25)
end

-- The bolt tearing along the ground from him to `to` (the real dash's end, or the target): two
-- kit bolts a stud up (a second 0.1 s later), sparks and scorch behind.
local function groundBolt(run, to: Vector3)
	local lift = Vector3.new(0, 1, 0)
	local from = run:ground()
	VfxRecipe.kitBolts(from + lift, to + lift, blueWhite(run), 1, 0.3, 1.2)
	run:at(run:designTime() + 0.1, function()
		VfxRecipe.kitBolts(from + lift, to + lift, blueWhite(run), 1, 0.25)
	end)
	VfxRecipe.trail(
		run,
		from,
		to,
		{ theme = theme(run), steps = 4, span = 0.1, size = 0.8 * run:scale(), sparks = false }
	)
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
			-- The charge: 0.4 s of blue-white crackle at his hand, flickering with a rapid chirp.
			for i = 0, (if run.reduced then 4 else 8) do
				run:at(-0.4 + i * 0.05, function()
					VfxRecipe.kit(run:hand("right"), "kitCrackle", {
						size = (1.4 + 0.08 * i) * run:scale(),
						color = blueWhite(run),
						lifetime = 0.1,
						rotation = { 0, 360 },
						lightEmission = 1,
						brightness = 2,
						zOffset = 1,
					})
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
			local floor = at - Vector3.new(0, view.part.Size.Y / 2, 0)
			local t = theme(run)
			local s = run:scale()
			-- The strike: 4-6 bolts bursting out of the target, a hit star, a shock ring, over a
			-- core flash, a blue glow sheet, sparks and a light (no part-based arcs).
			for _ = 1, if run.reduced then 4 else 6 do
				local out = Vector3.new(math.random() - 0.5, math.random() * 0.8 - 0.2, math.random() - 0.5)
				out = if out.Magnitude > 1e-3 then out.Unit else Vector3.xAxis
				VfxRecipe.kitBolts(at, at + out * (2.5 + math.random()) * s, blueWhite(run), 1, 0.25)
			end
			VfxRecipe.kitHitStar(at, view.part.Size.Y * 1.3, blueWhite(run))
			VfxRecipe.meshRing(floor, 3 * s, t.crackle, 0.35)
			VfxRecipe.core(at, 1.6 * s, 1, t.core, 1.7)
			VfxRecipe.explosion(at, 1.6 * s, t.blast, t.blastUsage, t.blastLight, 1.7)
			VfxRecipe.sparks(at, 0.6 * s, 20, t.spark)
			VfxRecipe.light(run, at, 1.8 * s, t.light, 0.9)
			run:hitStop(view, 0.1)
			run:shake(0.18)
		end
		return true
	end
	return false -- the stun and the burn keep their markers
end

return def
