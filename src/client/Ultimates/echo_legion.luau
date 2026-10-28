-- echo_legion (Tier 4): clones form it, then the wind sphere. The real cast hits a 2-hex area at his
-- target four times (Area, a Damage per enemy each), at +0.25, +0.5, +0.75 and +1.0 after the Cast
-- event (t = 0). Everything before 0 is anticipation; the throw lands on t = 0 and the sphere opens on
-- the first real hit. The clones are visual only: this ultimate draws its own (def.ownClones), the
-- generic cast clones are skipped. Bare hands: the throwing hand carries a short trail. Every
-- movement is the figure's pose offset (UnitView): his real position never changes.
-- Designed timeline (real seconds at full length; SEGMENTS):
--   -1.06  two shadow clones pop in beside him in puffs of smoke (a wind aura where each stands); his
--          right hand rises; the callout (a blue outline on him, a small ground ring)
--   -0.78  set: the hand high, a blue sphere forming over it as the clones reach in, four white blades
--          spinning out of it, growing, a rising whine; a shiver, until -0.38
--   -0.38  the clones vanish in smoke; stillness, until -0.18
--   -0.18  a 0.12 s load dip: the hand cocked back
--   -0.06  the throw's 0.06 s snap
--    0     THE THROW, on the real cast: the arm whipped forward (a hand trail), the spinning sphere
--          flying to the target (it arrives at +0.25)
--   +0.25  the first real hit: it opens into a wide white-blue sphere of wind over the area (one see-
--          through shell, the area's size, pulsing) with one shock ring and a gust; quick cuts and
--          sparks; the enemies flinch
--   +0.5, +0.75  a pulse on each real hit: cuts, sparks, a flinch, a small shake
--   +1.0   the last real hit (a fallback at +1.05): the sphere collapses in a white-blue flash behind
--          the main target, sparks; hit-stop on the bodies, the boom, a stronger shake, the punch-in;
--          the main target knocked 2.5 studs and launched 0.8, the rest 1.5
--   +0.06  the follow-through, held to +0.35
--   +0.6   he shakes his hand out; idle by +1.2
-- When the real window before the cast is shorter (Cinematic run.k < 1, at least the tier's 0.6),
-- the anticipation is laid out again for it (planOf): the stillness gives first, then the set, then
-- the pop-in, and only past that does everything but the load and the snap shrink evenly. The load,
-- the snap and everything after the throw never shrink.
-- Readable from the match camera (ViewScale: 1 at close cameras, up to 1.8 there): the sphere, the
-- blades, the trail, the shell, the ring, the cuts and the sparks grow with it.
-- Layers (tier 4, within its 34; peak ~17 in the set, ~16 when the sphere opens, estimated): the
-- clones' auras and smoke (particles), the sphere (core + halo), 4 blades (plain, not neon), the
-- shell (1, from the first hit to the last), one shock ring, ~5 cuts alive per hit (4 cuts each, 3
-- when reduced), sparks (particles), the collapse flash (1), a light at the collapse (not when
-- reduced); the hand trail (BladeTrail); the callout's ring. Camera: a push on the sphere through
-- the set (tier 4). Poses: PoseAnimator; hit feel: HitFeel; callout: UltimateCallout; sounds: Sfx.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RenderConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("RenderConfig"))

local BladeTrail = require(script.Parent.Parent.BladeTrail)
local HitFeel = require(script.Parent.Parent.HitFeel)
local ImpactEffects = require(script.Parent.Parent.ImpactEffects)
local PoseAnimator = require(script.Parent.Parent.PoseAnimator)
local Sfx = require(script.Parent.Parent.Sfx)
local UltimateCallout = require(script.Parent.Parent.UltimateCallout)
local UltimateKit = require(script.Parent.Parent.UltimateKit)
local UnitView = require(script.Parent.Parent.UnitView)
local VfxRecipe = require(script.Parent.Parent.VfxRecipe)

local Kit = UltimateKit
local rgb = Color3.fromRGB

-- The anticipation's segments in real seconds at full length, in order up to the throw (1.06 s in
-- all), and how far each may shrink when the window is short (`least`), in the order they give way
-- (the stillness first, then the set, then the pop-in).
local SEGMENTS = {
	pop = 0.28, -- windup start -> the clones in, the hand up
	set = 0.4, -- the sphere forming over the hand
	still = 0.2, -- the clones gone, stillness
	load = 0.12, -- the load dip
	snap = 0.06, -- the throw's snap, ending on the cast
}
local LEAST = { still = 0.08, set = 0.15, pop = 0.14 }
local SHRINK_ORDER = { "still", "set", "pop" }
local ORDER = { "pop", "set", "still", "load", "snap" }
local SNAPS = { load = true, snap = true } -- never shrink
local FULL = 0
for _, name in ORDER do
	FULL += SEGMENTS[name]
end

-- After the throw (design seconds = real seconds: never compressed).
local AFTER = {
	finisher = 0, -- the throw
	follow = 0.06, -- the follow-through pose reached
	trailOff = 0.14, -- the hand trail stops drawing
	arrive = 0.25, -- the sphere reaches the area (the first real hit)
	followEnd = 0.35, -- the follow-through held until here
	shake = 0.6, -- the hand shaken out
	rest = 1.2, -- back to idle
	last = 1.0, -- the last real hit
}

export type Plan = { [string]: number }

-- The beats for an anticipation speed `k` (Cinematic run.k), as design times: the real time
-- available is k x FULL; the segments give way in SHRINK_ORDER down to LEAST, then all but the load
-- and the snap shrink evenly; each real time is divided by k so Cinematic's own compression (t x k)
-- lands it there.
local plans: { [number]: Plan } = {}
local function planOf(k: number): Plan
	k = math.clamp(math.floor(k * 100 + 0.5) / 100, 0.05, 1)
	local cached = plans[k]
	if cached then
		return cached
	end
	local lengths = table.clone(SEGMENTS)
	local deficit = FULL - k * FULL
	for _, name in SHRINK_ORDER do
		if deficit <= 0 then
			break
		end
		local give = math.min(lengths[name] - LEAST[name], deficit)
		lengths[name] -= give
		deficit -= give
	end
	if deficit > 1e-6 then
		local total = 0
		for _, name in ORDER do
			if not SNAPS[name] then
				total += lengths[name]
			end
		end
		local even = (total - deficit) / total
		for _, name in ORDER do
			if not SNAPS[name] then
				lengths[name] *= even
			end
		end
	end
	-- Real times, backward from the throw.
	local real: Plan = {}
	local at = 0
	for i = #ORDER, 1, -1 do
		local name = ORDER[i]
		at -= lengths[name]
		real[name] = at -- the segment's start
	end
	local function design(t: number): number
		return t / k
	end
	local plan: Plan = {
		windup = design(real.pop),
		set = design(real.set),
		still = design(real.still),
		load = design(real.load),
		snap = design(real.snap),
	}
	for name, value in AFTER do
		plan[name] = value
	end
	plans[k] = plan
	return plan
end

local WHITE = Kit.WHITE
local BLUE = rgb(70, 150, 255)
local PALE = rgb(200, 230, 255)
local SMOKE = rgb(235, 235, 235)
local CALLOUT = BLUE
local CLONE_SMOKE = VfxRecipe.colors({ { 0, SMOKE }, { 1, SMOKE:Lerp(rgb(150, 150, 155), 0.6) } })
local SPARKS = ColorSequence.new(WHITE, BLUE)
local TRAIL = ColorSequence.new({
	ColorSequenceKeypoint.new(0, WHITE),
	ColorSequenceKeypoint.new(0.5, PALE),
	ColorSequenceKeypoint.new(1, BLUE),
})
local CUTS = { full = 4, reduced = 3 }
local STEP = 0.45 -- studs (normal size) he steps into the throw (`lunge`)
-- The collapse's light: a short, tight blue flash over the area.
local FINISH_LIGHT = { brightness = 1.8, range = 1.5, seconds = 0.22 } -- range in unit heights
local UNIT_HEIGHT = RenderConfig.unitSize.Y

-- The poses (PoseAnimator channels), about twice realistic: big, readable anime poses. Every body
-- pose names every body channel, so a held pose holds the whole body still. `lunge` (the step into
-- the throw) runs on keys of its own.
local function pose(values: { [string]: number }): { [string]: number }
	local full = {
		crouch = 0,
		lean = 0,
		twist = 0,
		tilt = 0,
		spin = 0,
		rise = 0,
		rightArm = 0,
		rightArmOut = 0,
		leftArm = 0,
		leftArmOut = 0,
		leftLeg = 0,
		rightLeg = 0,
		headYaw = 0,
		headPitch = 0,
	}
	for channel, value in values do
		full[channel] = value
	end
	return full
end
local function with(base: { [string]: number }, changes: { [string]: number }): { [string]: number }
	local out = table.clone(base)
	for channel, value in changes do
		out[channel] = value
	end
	return out
end

-- The hand rising as the clones pop in.
local RISE = pose({
	lean = -4,
	rightArm = 110,
	rightArmOut = 10,
	leftArm = 20,
	leftArmOut = 30,
	leftLeg = 14,
	rightLeg = -12,
	headPitch = -10,
})
-- The sphere over the raised hand, the other hand out guiding it, looking up at it.
local SET = pose({
	crouch = 0.2,
	lean = -10,
	twist = -12,
	rightArm = 172,
	rightArmOut = 8,
	leftArm = 40,
	leftArmOut = 45,
	leftLeg = 24,
	rightLeg = -22,
	headPitch = -22,
})
-- The load: the hand cocked back, the body turned away.
local LOAD = with(SET, { rightArm = 182, lean = -16, twist = -30, crouch = 0.3 })
-- The throw: the arm whipped forward and down, the body turning through it.
local THROW = pose({
	crouch = 0.34,
	lean = 26,
	twist = 50,
	rightArm = 80,
	rightArmOut = -10,
	leftArm = -15,
	leftArmOut = 25,
	leftLeg = 36,
	rightLeg = -32,
	headPitch = 4,
})
local FOLLOW = with(THROW, { lean = 22, twist = 44 })
-- Shaking the hand out: the arm loose to the side.
local SHAKE = pose({ lean = -2, rightArm = 40, rightArmOut = 30, leftArm = 5, headPitch = 4 })

-- The keys for a plan (planOf) and a step of `step` studs (normal size) into the throw.
local function keyframes(T: Plan, step: number): { PoseAnimator.Keyframe }
	return {
		{ at = T.windup, pose = with(pose({}), { lunge = 0 }) },
		{ at = T.set, ease = "quadOut", pose = RISE },
		-- The set held with a shiver, then in stillness.
		{ at = T.set + 0.12, ease = "quadOut", hold = math.max(0, T.still - T.set - 0.12), shiver = 1, pose = SET },
		{ at = T.still, ease = "hold", hold = T.load - T.still, pose = SET },
		{ at = T.snap, ease = "quadOut", pose = LOAD },
		-- The throw (a snap) on the cast, a step into it; the follow-through held.
		{ at = T.finisher, ease = "snap", pose = THROW },
		{ at = T.snap, pose = { lunge = 0 } },
		{ at = T.finisher, ease = "snap", pose = { lunge = step } },
		{ at = T.follow, ease = "quadOut", hold = T.followEnd - T.follow, pose = FOLLOW },
		{ at = T.followEnd, ease = "hold", pose = { lunge = step } },
		-- The hand shaken out (a quick shiver), stepping back; then idle.
		{ at = T.shake, ease = "inOut", hold = 0.2, shiver = 2.5, pose = SHAKE },
		{ at = T.shake, ease = "inOut", pose = { lunge = 0 } },
		{ at = T.rest, ease = "inOut", pose = pose({}) },
	}
end

local def = {}

def.ownClones = true

-- This run's plan (by its anticipation speed), kept on the run for the beats.
local function planFor(run): Plan
	local plan = run.memo.plan
	if not plan then
		plan = planOf(run.k or 1)
		run.memo.plan = plan
	end
	return plan
end

-- Tracks by plan and step (rounded to a hundredth of a stud: it depends on his size), built once
-- each.
local tracks: { [Plan]: { [number]: any } } = {}
function def.poseFor(run)
	local plan = planFor(run)
	local step = math.floor(STEP / math.max(UnitView.sizeFactor(run.view), 0.1) * 100 + 0.5) / 100
	local byStep = tracks[plan]
	if not byStep then
		byStep = {}
		tracks[plan] = byStep
	end
	local track = byStep[step]
	if not track then
		track = PoseAnimator.track(keyframes(plan, step))
		byStep[step] = track
	end
	return track
end

-- Over his raised hand.
local function overHand(run): Vector3
	return run:hand("right") + Vector3.new(0, 0.8, 0)
end

-- The throwing hand's trail (BladeTrail on the bare hand), made at the windup. Gone once it has
-- faded.
local function attachHand(run)
	if run.memo.hand then
		return
	end
	local trail = BladeTrail.attach(run.view, { hand = "right", from = 0, to = 0.12, viewScale = true })
	trail:add("throw", { colors = TRAIL, lifetime = 0.2 })
	run.memo.hand = trail
	run:at(planFor(run).rest, function()
		trail:destroy()
		run.memo.hand = nil
	end)
end

local function setTrail(run, on: boolean)
	local trail = run.memo.hand
	if trail then
		if on then
			trail:enable("throw")
		else
			trail:disable("throw")
		end
	end
end

-- A shadow clone at `side` (-1 left, 1 right): a wind aura shaped where it stands (no see-through
-- parts), popping in and out in pale smoke.
local function clone(run, plan: Plan, side: number)
	local h = run.view.part.Size.Y
	local function base(): Vector3
		local forward = run:forward()
		local across = Vector3.new(-forward.Z, 0, forward.X) * side
		return run:ground() + across * h * 0.55 - forward * 0.3 + Vector3.new(0, h * 0.5, 0)
	end
	run.memo.wind = run.memo.wind or VfxRecipe.wind(BLUE, WHITE)
	VfxRecipe.aura(run, function()
		return base(), h
	end, run.memo.wind, 1, plan.windup + 0.05, plan.still - plan.windup - 0.05)
	for _, at in { plan.windup + 0.02, plan.still } do
		run:at(at, function()
			local where = base() - Vector3.new(0, 0.5, 0)
			VfxRecipe.smoke(where, 1.3 * VfxRecipe.viewScale(where), if run.reduced then 2 else 4, CLONE_SMOKE, 0.45)
		end)
	end
end

-- Four white blades spinning around `center()`, `reach(u)` studs out (plain parts: neon would add a
-- glow layer to each).
local function blades(run, from: number, to: number, center: () -> Vector3, reach: (number) -> number)
	for i = 1, 4 do
		Kit.block(run, from, to, WHITE, function(u)
			local angle = i * math.pi / 2 + run:now() * 16
			local r = reach(u)
			return CFrame.new(center() + Vector3.new(math.cos(angle) * r, 0, math.sin(angle) * r))
				* CFrame.Angles(0, -angle, 0)
		end, function(u)
			return Vector3.new(0.12, 0.06, 0.4 + reach(u) * 0.8)
		end, function()
			return 0.1
		end)
	end
end

local collapse: (any) -> () -- below

def.beats = {
	{
		at = planOf(1).windup, -- every plan starts its windup at the same design time (-FULL)
		run = function(run)
			local plan = planFor(run)
			local s = run:scale()
			run:face(run:target())
			attachHand(run)
			UltimateCallout.mark(run.view, CALLOUT, run:span(plan.windup, plan.finisher - plan.windup))
			clone(run, plan, -1)
			clone(run, plan, 1)
			run.memo.hits, run.memo.total = 0, 0
			for _, event in run.cast do
				if event.kind == "Area" then
					run.memo.total += 1
				end
			end
			-- The sphere forming over the raised hand, the blades spinning out of it.
			run:at(plan.set, function()
				local view = VfxRecipe.viewScale(overHand(run))
				Kit.orb(run, plan.set, plan.finisher, BLUE, function()
					return overHand(run)
				end, function(u)
					return (0.35 + 0.6 * Kit.easeOut(u)) * s * view
				end)
				blades(run, plan.set + 0.08, plan.finisher, function()
					return overHand(run)
				end, function(u)
					return (0.5 + 0.8 * Kit.easeOut(u)) * s * view
				end)
				run:camera(
					plan.set,
					plan.finisher,
					{ key = "push", push = 1.8, focus = overHand(run), rise = 0.3, fall = 0.1 }
				)
				Sfx.play("energyCharge", { pitch = 1.4 })
			end)
			run:at(plan.snap - 0.01, function()
				setTrail(run, true)
			end)
			run:at(AFTER.trailOff, function()
				setTrail(run, false)
			end)
			-- The collapse waits for the last real hit; should it never come, it still plays.
			run:at(AFTER.last + 0.05, function()
				collapse(run)
			end)
		end,
	},
}

-- The throw, on the real cast: the spinning sphere crosses to the area, arriving at the first real
-- hit (+0.25).
function def.release(run): boolean
	local s = run:scale()
	local center = run:area()
	local start = overHand(run)
	local goal = center + Vector3.new(0, UNIT_HEIGHT * 0.3, 0)
	local view = VfxRecipe.viewScale(goal)
	local function at(): Vector3
		return start:Lerp(goal, Kit.easeIn(math.clamp(run:designTime() / AFTER.arrive, 0, 1)))
	end
	Kit.orb(run, 0, AFTER.arrive, BLUE, at, function()
		return 0.95 * s * view
	end)
	blades(run, 0, AFTER.arrive, at, function()
		return 1.3 * s * view
	end)
	Sfx.play("whooshLight", { pitch = 1.3 })
	return true
end

-- Quick cuts across the area (UltimateKit.slashes), `count` of them over 0.2 s, longer and higher
-- from far away (ViewScale).
local function cuts(run, center: Vector3, radius: number, view: number)
	Kit.slashes(
		run,
		run:designTime(),
		run:designTime() + 0.2,
		center,
		radius * 0.8 * view,
		if run.reduced then CUTS.reduced else CUTS.full,
		{ WHITE, BLUE },
		1.6 * view
	)
end

-- The collapse on the last hit (or its fallback): a white-blue flash behind the main target as the
-- camera sees it, a light; hit-stop on the bodies, the reactions (from him, so the main target on
-- the area's center is knocked in a real direction), the shake and the punch-in.
collapse = function(run)
	if run.memo.collapsed then
		return
	end
	run.memo.collapsed = true
	local center = run:area()
	local air = center + Vector3.new(0, UNIT_HEIGHT * 0.3, 0)
	local view = VfxRecipe.viewScale(air)
	local flashAt = air
	local camera = workspace.CurrentCamera
	if camera then
		local away = air - camera.CFrame.Position
		away = Vector3.new(away.X, 0, away.Z)
		if away.Magnitude > 1e-3 then
			flashAt += away.Unit * 0.8
		end
	end
	ImpactEffects.ball(flashAt, PALE, UNIT_HEIGHT * 0.8 * run:scale() * view, 0.14)
	if not run.reduced then
		ImpactEffects.light(air, BLUE, FINISH_LIGHT.brightness, FINISH_LIGHT.range * UNIT_HEIGHT, FINISH_LIGHT.seconds)
	end
	local main = run:target()
	local targets = run:targets()
	local held = { run.view }
	for _, target in targets do
		table.insert(held, target)
	end
	HitFeel.hitStop(held, 0.07, { caster = run.view })
	for _, target in targets do
		HitFeel.react(target, run:chest(), if target == main then { final = true } else { knock = 1.5, tilt = 18 })
	end
	HitFeel.cameraShake(0.28, 0.32)
	HitFeel.punchIn(1)
	Sfx.play("impactHeavy")
end

function def.event(run, event): boolean
	local kind = event.kind
	if kind == "Area" then
		local center, radius = run:area()
		local air = center + Vector3.new(0, UNIT_HEIGHT * 0.3, 0)
		local view = VfxRecipe.viewScale(air)
		run.memo.hits = (run.memo.hits or 0) + 1
		local hit, total = run.memo.hits, math.max(run.memo.total or 4, 1)
		local now = run:designTime()
		if hit == 1 then
			-- It opens into the wide sphere of wind over the whole area, see-through and pulsing, held
			-- until the last hit.
			local last = now + (total - 1) * 0.25 + 0.15
			Kit.shell(run, now, last, PALE, air, function(u)
				local open = Kit.easeOut(math.min(1, u * 4))
				return radius * 2 * view * open * (1 + 0.06 * math.sin(run:now() * 24))
			end, function(u)
				return 0.55 + 0.4 * Kit.easeIn(u)
			end)
			VfxRecipe.meshRing(center, radius * 0.8 * view, PALE, 0.35, 0.3)
			Sfx.play("windGust", { pitch = 1.1 })
		end
		cuts(run, center, radius, view)
		VfxRecipe.sparks(air, 0.45 * view, 12, SPARKS, nil, view)
		if hit >= total then
			collapse(run)
		else
			-- A pulse: the enemies flinch (no hit-stop: four in a row would stutter).
			for _, target in run:targets() do
				HitFeel.react(target, run:chest(), { knock = 1, tilt = 15 })
			end
			HitFeel.cameraShake(0.1, 0.15)
		end
		return true
	elseif kind == "Damage" and event.target and not event.dot then
		return true -- the pulses draw every hit
	end
	return false
end

return def
