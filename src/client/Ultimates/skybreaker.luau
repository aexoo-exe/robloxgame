-- skybreaker (Tier 2): the air pressure behind the target. The real cast hits his target hard and
-- carries on through the enemies in a line behind it, at the Cast event.
--   -0.30  green lightning crackles over his body; he draws his fist back
--    0     the smash on the real hit, and a green shockwave carrying through the real line behind
--          the target: pressure streaks, dust on every cell
--   +0.30  the follow-through holds; green sparks fade
-- Kit layers (batch 2): a green-cyan crackle aura over his body through the wind-up (fx_crackle);
-- on the smash a dust burst (fx_dust_burst), a hit star (fx_impact_star) and a shock ring
-- (mesh_shock_ring).

local UltimateKit = require(script.Parent.Parent.UltimateKit)
local FxKit = require(script.Parent.Parent.FxKit)
local ImpactEffects = require(script.Parent.Parent.ImpactEffects)
local VfxRecipe = require(script.Parent.Parent.VfxRecipe)

local Kit = UltimateKit
local WHITE = Kit.WHITE
local TEAL = Color3.fromRGB(90, 255, 200)

local function greenCyan(run): Color3
	return run.style.primary:Lerp(TEAL, 0.5)
end

local def = {}

def.pose = {
	rightArm = { { -0.3, 0 }, { -0.15, -45, "out" }, { -0.02, -50 }, { 0.03, 96, "snap" }, { 0.35, 90 }, { 0.55, 0 } },
	leftArm = { { -0.3, 0 }, { -0.15, 40 }, { 0.03, 0, "snap" }, { 0.55, 0 } },
	twist = { { -0.3, 0 }, { -0.15, -26 }, { 0.03, 26, "snap" }, { 0.35, 12 }, { 0.55, 0 } },
	lean = { { -0.3, 0 }, { -0.15, -6 }, { 0.03, 14, "snap" }, { 0.35, 6 }, { 0.55, 0 } },
	crouch = { { -0.15, 0 }, { -0.02, 0.12 }, { 0.03, 0.06, "snap" }, { 0.4, 0 } },
	lunge = { { 0.02, 0 }, { 0.05, 0.3, "snap" }, { 0.4, 0 } },
}

def.beats = {
	{
		at = -0.3,
		run = function(run)
			run:face(run:target())
			-- Green-cyan crackle crawling over him through the wind-up and the smash.
			VfxRecipe.kitCrackleAura(run, run.view, greenCyan(run), -0.3, 0.45, 2)
		end,
	},
}

function def.release(_run): boolean
	return true
end

function def.event(run, event): boolean
	local kind = event.kind
	if kind == "Area" and event.shape == "LINE" and event.cells then
		-- The pressure line carrying on behind the target.
		local target = run:target()
		local from = if target then target.part.Position else run:chest()
		local far = from
		for _, cell in event.cells do
			local at = run.context.toWorld(cell[1], cell[2])
			ImpactEffects.burst("puff", at + Vector3.new(0, 0.4, 0), nil, {
				color = Kit.DUST,
				count = 5,
				size = 0.8,
				speed = { 2, 5 },
				lifetime = { 0.3, 0.6 },
				transparency = 0.35,
			})
			if (at - from).Magnitude > (far - from).Magnitude then
				far = at
			end
		end
		Kit.streaks(
			run,
			0,
			from,
			far - from,
			if run.reduced then 4 else 7,
			(far - from).Magnitude + 3,
			2.4,
			run.style.secondary
		)
		return true
	elseif kind == "Damage" and event.target and not event.dot then
		local view = run.context.views[event.target]
		if view and not run.memo.smash then
			run.memo.smash = true
			local at = view.part.Position
			local floor = at - Vector3.new(0, view.part.Size.Y / 2, 0)
			-- The smash: a hit star, dust bursting up, a shock ring, the pressure cone onward.
			VfxRecipe.kitHitStar(at, view.part.Size.Y * 1.3, greenCyan(run):Lerp(WHITE, 0.3))
			VfxRecipe.kitDust(floor, 3.2 * run:scale(), if run.reduced then 2 else 3)
			VfxRecipe.meshRing(floor, 3 * run:scale(), greenCyan(run), 0.35)
			FxKit.pressureCone(at, at - run.view.part.Position, 6, math.rad(16), run.style.primary, 0.4)
			run:hitStop(view, 0.08)
			run:shake(0.12)
			run:sound("whoosh", 1)
		end
		return true
	end
	return false
end

return def
