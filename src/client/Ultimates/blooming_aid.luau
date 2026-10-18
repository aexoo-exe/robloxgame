-- blooming_aid (Tier 1): soft healing, or a ground-cracking punch. The real cast heals her
-- lowest-health ally if anyone is low, and otherwise hits her target, at the Cast event.
-- Heal:
--   -0.20  a soft green-pink glow gathers around her; she reaches toward the ally
--    0     green motes stream to the ally she really heals; it glows green (an aura), pink petals
--          of light rise off it, a gentle green ring
-- Punch:
--   -0.20  she tugs her glove; her fist glows pink
--    0     the punch into the ground: a crack races to the target and splits into a spiderweb, dust
-- Layers on the punch: the shared recipe (VfxRecipe, an impact theme in her pink, tier 1).

local UltimateKit = require(script.Parent.Parent.UltimateKit)
local FxKit = require(script.Parent.Parent.FxKit)
local ImpactEffects = require(script.Parent.Parent.ImpactEffects)
local VfxRecipe = require(script.Parent.Parent.VfxRecipe)

local Kit = UltimateKit
local PINK = Color3.fromRGB(255, 140, 190)
local PETAL = Color3.fromRGB(255, 190, 215)
local CRACK = Color3.fromRGB(80, 64, 60)

local def = {}

local function healing(run): boolean
	return run:find("Heal") ~= nil
end

-- The heal's colors: her green with pink petals (motes pink -> green, a green glow).
local function healTheme(run)
	local green = run.style.secondary
	local theme = VfxRecipe.energy(green, PETAL)
	theme.ember = VfxRecipe.colors({ { 0, Color3.new(1, 1, 1):Lerp(PETAL, 0.6) }, { 0.4, PETAL }, { 1, green } })
	theme.spark = VfxRecipe.colors({ { 0, PETAL }, { 1, green } })
	return theme
end

-- Petals of light rising off a healed ally's feet and drifting up around it.
local function petals(run, view, theme)
	local part = view.part
	ImpactEffects.emit(part.Position - Vector3.new(0, part.Size.Y * 0.4, 0), {
		usage = "ember",
		count = if run.reduced then 5 else 12,
		color = theme.ember,
		size = VfxRecipe.curve({ { 0, 0.3 * run:scale() }, { 0.7, 0.24 * run:scale() }, { 1, 0 } }),
		transparency = VfxRecipe.curve({ { 0, 0.1 }, { 0.75, 0.3 }, { 1, 1 } }),
		lifetime = { 0.9, 1.4 },
		speed = { 1.5, 3.5 },
		spread = 35,
		direction = Vector3.yAxis,
		drag = 1.2,
		acceleration = Vector3.new(0, 1.5, 0),
		lightEmission = 1,
		brightness = 2,
		rotSpeed = { -90, 90 },
	})
end

local HEAL = {
	leftArm = { { -0.2, 0 }, { -0.08, 80 }, { 0.3, 80 }, { 0.5, 0 } },
	rightArm = { { -0.2, 0 }, { -0.08, 80 }, { 0.3, 80 }, { 0.5, 0 } },
	leftArmOut = { { -0.2, 0 }, { -0.08, -10 }, { 0.5, 0 } },
	rightArmOut = { { -0.2, 0 }, { -0.08, -10 }, { 0.5, 0 } },
}

local PUNCH = {
	leftArm = { { -0.2, 0 }, { -0.12, 50 }, { -0.06, 50 }, { 0, 0 } },
	rightArm = { { -0.2, 0 }, { -0.12, 40 }, { -0.04, -30 }, { 0.03, 60, "snap" }, { 0.3, 50 }, { 0.5, 0 } },
	crouch = { { -0.1, 0 }, { 0.03, 0.28, "snap" }, { 0.45, 0 } },
	lean = { { -0.1, 0 }, { 0.03, 24, "snap" }, { 0.45, 0 } },
}

function def.poseFor(run)
	return if healing(run) then HEAL else PUNCH
end

def.beats = {
	{
		at = -0.2,
		run = function(run)
			local heal = healing(run)
			if heal then
				-- A soft green-pink glow gathering around her (an aura, not a ball).
				VfxRecipe.aura(run, run.view, healTheme(run), 0.8, -0.2, 0.35)
				return
			end
			run:face(run:target())
			Kit.orb(run, -0.18, 0.02, PINK, function()
				return run:hand("right")
			end, function()
				return 0.35 * run:scale()
			end)
		end,
	},
}

function def.release(_run): boolean
	return true
end

function def.event(run, event): boolean
	local kind = event.kind
	if kind == "Heal" and event.target then
		local view = run.context.views[event.target]
		if view then
			-- Green motes stream in; the ally glows (an aura of rising petals and a soft rim glow),
			-- petals rise off its feet, a gentle raised ring of green.
			local theme = healTheme(run)
			Kit.converge(run, 0, 0.35, function()
				return view.part.Position
			end, run.style.secondary, 2.4, if run.reduced then 4 else 8, false, 0.3)
			VfxRecipe.aura(run, view, theme, 1, run:designTime(), 0.9)
			petals(run, view, theme)
			VfxRecipe.shock(
				view.part.Position - Vector3.new(0, view.part.Size.Y / 2, 0),
				1.1 * run:scale(),
				run.style.secondary,
				0.7
			)
		end
		return true
	elseif kind == "Damage" and event.target and not event.dot then
		local view = run.context.views[event.target]
		if view and not run.memo.hit then
			run.memo.hit = true
			local floor = view.part.Position - Vector3.new(0, view.part.Size.Y / 2, 0)
			Kit.groove(run, 0, 0.8, CRACK, run:ground() + run:forward() * 0.8, floor, 0.25)
			FxKit.mark(floor, CRACK, PINK, 2.2, "crack", 0.9)
			-- A pink impact at the target (tier 1: quick): pink sparks (not white streaks), dust and
			-- a few chips, a pink shock ring.
			local impact = VfxRecipe.impact(PINK)
			impact.spark = VfxRecipe.colors({ { 0, PETAL }, { 0.5, PINK }, { 1, PINK:Lerp(CRACK, 0.4) } })
			impact.edge = PINK
			VfxRecipe.burst(run, floor, 1.6 * run:scale(), { theme = impact })
			VfxRecipe.dust(floor, 1.2 * run:scale(), if run.reduced then 1 else 2)
			run:hitStop(view, 0.05)
		end
		return true
	end
	return false
end

return def
