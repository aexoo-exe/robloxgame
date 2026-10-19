-- cinder_arc (Tier 1): a three-strike spiral of fire, the last one the real hit. The real cast cuts
-- his target, splashes magic over everything within 1 hex of it and speeds up his attacks, all at
-- the Cast event (t = 0). Everything before 0 is anticipation (compressed when the real window is
-- short); the finisher lands exactly on the real hit. Sword in the right hand.
--   -0.85  he sinks into a low crouch, torso twisted far back, blade drawn behind his right hip,
--          weight on the back leg; heat gathers on the blade (embers, motes, a small flame)
--   -0.55  set: held, shivering with tension
--   -0.42  STRIKE 1: he snaps through a big horizontal spin slash (yellow swoosh along the blade's
--          real arc, flames off the blade); the target flashes and slides; a short hit-stop
--   -0.32  follow-through
--   -0.22  STRIKE 2: a rising backhand diagonal, still spinning (orange swoosh), the target hit again
--   -0.07  a quick dip to load the last one
--    0     STRIKE 3, the finisher, on the real hit: a rising cut to a high pose (crimson swoosh);
--          hit-stop, the fire bloom lands on it over the real splash, a boom, a stronger shake, a
--          punch-in, every target knocked back (the main one furthest); embers drift after
--   +0.30  the high pose held, then he recovers to idle by +0.55
-- Layers (tier 1, within its 14): the batch 2 kit's swoosh ribbon (fx_swoosh_ribbon), fire flipbook
-- flames, one fire bloom (fx_fire_burst), small hit stars, embers and motes. Poses: PoseAnimator;
-- hit feel: HitFeel; sounds: Sfx (SfxConfig names windup, whoosh, hitImpact, fireBurst, finisherBoom).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RenderConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("RenderConfig"))

local HitFeel = require(script.Parent.Parent.HitFeel)
local PoseAnimator = require(script.Parent.Parent.PoseAnimator)
local Sfx = require(script.Parent.Parent.Sfx)
local UltimateKit = require(script.Parent.Parent.UltimateKit)
local VfxRecipe = require(script.Parent.Parent.VfxRecipe)

local Kit = UltimateKit
local rgb = Color3.fromRGB

-- The beats (design seconds; 0 is the real hit).
local T = {
	windup = -0.85,
	set = -0.55,
	strike1 = -0.42,
	follow1 = -0.32,
	strike2 = -0.22,
	follow2 = -0.12,
	load = -0.07,
	finisher = 0,
	held = 0.3,
	rest = 0.55,
}
-- Each strike's contact time, swoosh color (yellow -> orange -> crimson: saturated, so the tint
-- shows) and, if the blade's real arc cannot be read, its swing plane's tilt from level (degrees).
local STRIKES = {
	{ at = T.strike1, color = rgb(255, 210, 60), tilt = 12 },
	{ at = T.strike2, color = rgb(255, 120, 20), tilt = 40 },
	{ at = T.finisher, color = rgb(215, 35, 20), tilt = 70 },
}
local HEAT = rgb(255, 170, 60)
local SAMPLE = 0.035 -- design seconds before a contact the blade is sampled (its arc's direction)
local BLADE = 0.55 -- the sword's reach past the hand, in unit heights
local UNIT_HEIGHT = RenderConfig.unitSize.Y

-- The poses (PoseAnimator channels): big, readable anime poses, not realistic ones.
local KEYFRAMES: { PoseAnimator.Keyframe } = {
	{
		at = T.windup,
		pose = { crouch = 0, lean = 0, twist = 0, rightArm = 0, rightArmOut = 0, spin = 0 },
	},
	-- Anticipation: low, twisted back, blade behind the right hip, weight on the back leg.
	{
		at = T.set,
		ease = "quadOut",
		hold = 0.05,
		shiver = 1.6,
		pose = {
			crouch = 0.42,
			lean = 16,
			twist = -70,
			tilt = -6,
			rightArm = -30,
			rightArmOut = 65,
			leftArm = 40,
			leftArmOut = -25,
			leftLeg = 38,
			rightLeg = -32,
			headYaw = 45,
			headPitch = 6,
		},
	},
	-- Strike 1: a horizontal spin slash, the torso fully round, the arm out straight across.
	{
		at = T.strike1,
		ease = "snap",
		pose = {
			crouch = 0.3,
			lean = 24,
			twist = 65,
			tilt = 4,
			rightArm = 92,
			rightArmOut = -55,
			leftArm = -15,
			leftArmOut = 45,
			leftLeg = 42,
			rightLeg = -38,
			headYaw = -25,
			headPitch = 0,
			spin = 120,
			lunge = 0.6,
		},
	},
	{
		at = T.follow1,
		ease = "quadOut",
		pose = { twist = 78, rightArm = 80, rightArmOut = -80, spin = 145, lean = 18 },
	},
	-- Strike 2: a rising backhand diagonal, still turning.
	{
		at = T.strike2,
		ease = "snap",
		pose = {
			crouch = 0.18,
			lean = 6,
			twist = -35,
			tilt = -8,
			rightArm = 135,
			rightArmOut = 70,
			leftArm = 30,
			leftArmOut = -35,
			leftLeg = 15,
			rightLeg = -15,
			headYaw = 20,
			headPitch = -8,
			spin = 250,
			rise = 0.5,
			lunge = 0.4,
		},
	},
	{ at = T.follow2, ease = "quadOut", pose = { rightArm = 145, rightArmOut = 85, spin = 268, twist = -45 } },
	-- A quick dip that loads the finisher.
	{
		at = T.load,
		ease = "quadOut",
		pose = { crouch = 0.32, rise = 0.1, rightArm = 60, rightArmOut = 30, lean = 20, twist = -55 },
	},
	-- Strike 3, the finisher: a rising cut to a high finishing pose, held.
	{
		at = T.finisher,
		ease = "snap",
		hold = T.held - T.finisher,
		pose = {
			crouch = 0,
			lean = -14,
			twist = 20,
			tilt = 0,
			rightArm = 178,
			rightArmOut = 8,
			leftArm = 70,
			leftArmOut = 60,
			leftLeg = -12,
			rightLeg = 28,
			headYaw = 0,
			headPitch = -14,
			spin = 360,
			rise = 0.7,
			lunge = 0.2,
		},
	},
	-- One whole turn is facing front again: drop it to 0 at once (no unwinding spin in the recovery).
	{ at = T.held + 0.001, ease = "hold", pose = { spin = 0 } },
	-- Recover to idle, settling with a small overshoot ("back": ~10%; "backOut" swung the sword arm
	-- ~25 degrees past rest coming down from overhead).
	{
		at = T.rest,
		ease = "back",
		pose = {
			crouch = 0,
			lean = 0,
			twist = 0,
			tilt = 0,
			rightArm = 0,
			rightArmOut = 0,
			leftArm = 0,
			leftArmOut = 0,
			leftLeg = 0,
			rightLeg = 0,
			headYaw = 0,
			headPitch = 0,
			rise = 0,
			lunge = 0,
		},
	},
}

local def = {}

def.pose = PoseAnimator.track(KEYFRAMES)

local function hand(run): Vector3
	return run:hand("right")
end

-- The blade's tip now: past the hand along the arm.
local function tip(run): Vector3
	local h = hand(run)
	local arm = h - run:chest()
	local along = if arm.Magnitude > 1e-3 then arm.Unit else run:forward()
	return h + along * UNIT_HEIGHT * BLADE * 0.6 * run:scale()
end

-- The swing plane's normal at a strike: from the blade's real motion (the hand a moment ago and
-- now, about the chest), or the strike's fallback tilt when that cannot be read.
local function swingNormal(run, strike, before: Vector3?): Vector3
	local now = hand(run)
	local pivot = run:chest()
	if before then
		local motion = now - before
		local arm = now - pivot
		local normal = arm:Cross(motion)
		if motion.Magnitude > 0.05 and normal.Magnitude > 1e-3 then
			return normal.Unit
		end
	end
	return (CFrame.fromAxisAngle(run:forward(), math.rad(strike.tilt)) * Vector3.yAxis).Unit
end

-- One strike at its contact: the swoosh along the blade's arc, flames off the blade, the whoosh;
-- strikes 1-2 also hit the target (a small hit star, its reaction, a short hit-stop and shake).
local function strike(run, index: number)
	local s = run:scale()
	local spec = STRIKES[index]
	local pivot = run:chest()
	local reach = (hand(run) - pivot).Magnitude + UNIT_HEIGHT * BLADE * s
	VfxRecipe.kitSwoosh(
		pivot,
		reach * 2.1,
		spec.color,
		swingNormal(run, spec, run.memo["blade" .. index]),
		120 * (index - 1),
		0.3
	)
	-- Flames trailing the blade (one emit of two), embers flung off it.
	VfxRecipe.flames(tip(run), 2, (1.2 + 0.2 * index) * s)
	VfxRecipe.embers(run, tip(run), s, nil, 6)
	Sfx.play("whoosh", { pitch = 1 + 0.06 * (index - 1) })
	if index >= #STRIKES then
		return -- the finisher's hit is the real one (def.event, Area)
	end
	local target = run:target()
	if not target or not target.part.Parent then
		return
	end
	local at = target.part.Position + Vector3.new(0, target.part.Size.Y * 0.1, 0)
	VfxRecipe.kitHitStar(at, target.part.Size.Y * 0.8, spec.color)
	VfxRecipe.sparks(at, 0.4, 10, nil, run:forward())
	HitFeel.react(target, pivot)
	HitFeel.hitStop({ run.view, target }, if index == 1 then 0.05 else 0.06, { caster = run.view })
	HitFeel.cameraShake(if index == 1 then 0.12 else 0.15, 0.18)
	Sfx.play("hitImpact", { volume = 0.8 })
end

local finisher: (any) -> () -- below

def.beats = {
	{
		at = T.windup,
		run = function(run)
			run:face(run:target())
			local s = run:scale()
			Sfx.play("windup")
			-- Heat gathering on the blade: motes drawn in, embers glowing off it, a small flame.
			Kit.converge(run, T.windup + 0.05, T.set + 0.03, function()
				return tip(run)
			end, HEAT, 1.4 * s, if run.reduced then 5 else 10)
			VfxRecipe.embers(run, hand(run), s, nil, 8)
			run:at(T.set, function()
				VfxRecipe.flames(tip(run), 1, 0.7 * s)
			end)
			-- Each strike: the blade sampled just before contact (its arc), then the strike itself.
			for index, spec in STRIKES do
				run:at(spec.at - SAMPLE, function()
					run.memo["blade" .. index] = hand(run)
				end)
				if index < #STRIKES then
					run:at(spec.at, function()
						strike(run, index)
					end)
				end
			end
			-- The finisher waits for the real Area event; should it never come, it still plays.
			run:at(T.finisher + 0.05, function()
				if not run.memo.finished then
					run.memo.finished = true
					finisher(run)
				end
			end)
		end,
	},
}

function def.release(_run): boolean
	return true
end

-- The finisher on the real hit: the strike, hit-stop (poses and the effects around them), the
-- fire bloom landing on it over the real splash, the boom, a stronger shake, the punch-in, every
-- target knocked back (the main one furthest), embers drifting after.
finisher = function(run)
	local center, radius = run:area()
	local s = run:scale()
	local main = run:target()
	local targets = run:targets()
	local held = { run.view }
	for _, view in targets do
		table.insert(held, view)
	end
	-- The swoosh first (it is not paused), then the hold: the bloom emitted after it plays through.
	strike(run, #STRIKES)
	HitFeel.hitStop(held, 0.09, { caster = run.view })
	VfxRecipe.kitFireBurst(center, radius * 1.5)
	VfxRecipe.sparks(center + Vector3.new(0, 1.2, 0), 0.8, nil, VfxRecipe.themes.fire.spark)
	VfxRecipe.light(run, center + Vector3.new(0, 1.2, 0), radius, VfxRecipe.themes.fire.light, 0.8)
	for _, view in targets do
		HitFeel.react(view, run:chest(), if view == main then { final = true } else { knock = 1.2 })
	end
	HitFeel.cameraShake(0.3, 0.35)
	HitFeel.punchIn(1)
	Sfx.play("finisherBoom")
	Sfx.play("fireBurst")
	-- Embers drifting up off the splash after.
	for i = 0, 2 do
		run:at(0.12 + 0.25 * i, function()
			VfxRecipe.embers(run, VfxRecipe.within(center, radius * 0.6) + Vector3.new(0, 0.4, 0), s, nil, 8)
		end)
	end
end

function def.event(run, event): boolean
	local kind = event.kind
	if kind == "Area" then
		if not run.memo.finished then
			run.memo.finished = true
			finisher(run)
		end
		return true
	elseif kind == "Buff" and event.target == run.unitIndex then
		-- The attack speed: embers off the blade once he has recovered.
		run:at(T.rest, function()
			VfxRecipe.embers(run, tip(run), run:scale(), nil, 8)
		end)
		return true
	elseif kind == "Damage" and event.target and not event.dot then
		return true -- the strikes and the finisher draw the hits
	end
	return false
end

return def
