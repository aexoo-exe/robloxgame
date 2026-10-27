-- infinite_collapse (Tier 5): blue and red become violet. The real cast holds every enemy within 2
-- hexes of the highest-AD enemy (AreaStun), shields him (Shield) and blasts the same area (Area, a
-- Damage per enemy), all at the Cast event (t = 0). Everything before 0 is anticipation; the erasure
-- lands exactly on the real Area event. No weapon: his flicking right hand carries the trail. Every
-- movement is the figure's pose offset (UnitView): his real position never changes.
-- Designed timeline (real seconds at full length; SEGMENTS):
--   -1.34  a calm stop; the screen dims a little; the right hand goes out wide: a blue orb grows on
--          it, drawing motes in; the callout (a violet outline on him, a small ground ring)
--   -1.04  the left hand goes out the other way: a red orb grows on it, pushing motes out
--   -0.79  set: both arms spread far apart, the orbs held, shivering, until -0.44
--   -0.44  dead stillness: nothing moves, no motes, until -0.24
--   -0.24  a 0.06 s snap: the hands slam together, the orbs spiral into one violet sphere, crackling
--   -0.18  a 0.12 s load dip: the right hand cocks back, the sphere on its fingertips
--   -0.06  the flick's 0.06 s snap: the sphere crosses to the area in a blink (far faster than the
--          build: the signature), a violet trail off the flicking hand
--    0     THE ERASURE, on the real hit: a hollow violet shell swelling behind the main target (about
--          half the area radius across) and gone by +0.42, one mesh ring over the area, a white-violet core and a hit star on the main target, sparks, a
--          light; hit-stop on the bodies; a heavy boom, a strong shake, the punch-in and a camera
--          push; every enemy knocked back (the main one 2.5 studs, launched 0.8); a short blue
--          shimmer of his shield
--   +0.12  the air rushes back in (a gust); violet motes drift up off the area to +1.0
--   +0.06  the follow-through, held to +0.35
--   +0.62  recovered into a relaxed stand, one hand in his pocket, held; idle by +1.05
-- When the real window before the cast is shorter (Cinematic run.k < 1, at least the tier's 0.6),
-- the anticipation is laid out again for it (planOf): the stillness gives first, then the set, then
-- the red and the blue builds, and only past that does everything but the snaps shrink evenly. The
-- snaps, the load dip and everything after the hit never shrink.
-- Readable from the match camera (ViewScale: 1 at close cameras, up to 1.8 there): the orbs, the
-- sphere, the hand trail, the ring, the hit star, the sparks and the core grow with it.
-- Layers (tier 5, within its 44; peak ~17 in the set at full length, ~20 compressed to k = 0.6,
-- ~8 at the erasure, estimated): two orbs (core + halo each), up to 14 motes in flight (8 blue drawn
-- in, 6 red pushed out; half when reduced), the violet sphere (core + halo) and 2 crackle bolts
-- (1 when reduced), the flying sphere, a hand trail (BladeTrail), at the erasure one shell, one mesh
-- ring, a core flash, a hit star, sparks, a light (not when reduced), the shield shimmer, then
-- drifting motes (not when reduced); the callout's ring. Camera: a dim through the build and a push
-- at the erasure (tier 5 allows both). Poses: PoseAnimator; hit feel: HitFeel; callout:
-- UltimateCallout; sounds: Sfx.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RenderConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("RenderConfig"))

local BladeTrail = require(script.Parent.Parent.BladeTrail)
local FxKit = require(script.Parent.Parent.FxKit)
local HitFeel = require(script.Parent.Parent.HitFeel)
local ImpactEffects = require(script.Parent.Parent.ImpactEffects)
local PoseAnimator = require(script.Parent.Parent.PoseAnimator)
local Sfx = require(script.Parent.Parent.Sfx)
local UltimateCallout = require(script.Parent.Parent.UltimateCallout)
local UltimateKit = require(script.Parent.Parent.UltimateKit)
local VfxRecipe = require(script.Parent.Parent.VfxRecipe)

local Kit = UltimateKit
local rgb = Color3.fromRGB

-- The anticipation's segments in real seconds at full length, in order up to the hit (1.34 s in
-- all), and how far each may shrink when the window is short (`least`), in the order they give way
-- (the stillness first, then the set, then the two builds).
local SEGMENTS = {
	blue = 0.3, -- windup start -> the right hand out, the blue orb grown
	red = 0.25, -- the left hand out, the red orb grown
	set = 0.35, -- both held apart, shivering
	still = 0.2, -- held in dead stillness
	merge = 0.06, -- the snap: hands together, the violet sphere
	load = 0.12, -- the load dip: the hand cocked back
	flick = 0.06, -- the flick's snap, ending on the hit
}
local LEAST = { still = 0.08, set = 0.12, red = 0.15, blue = 0.15 }
local SHRINK_ORDER = { "still", "set", "red", "blue" }
local ORDER = { "blue", "red", "set", "still", "merge", "load", "flick" }
local SNAPS = { merge = true, load = true, flick = true } -- never shrink
local FULL = 0
for _, name in ORDER do
	FULL += SEGMENTS[name]
end

-- After the hit (design seconds = real seconds: never compressed).
local AFTER = {
	finisher = 0,
	follow = 0.06, -- the follow-through pose reached
	trailOff = 0.12, -- the hand trail stops drawing
	gust = 0.12, -- the air rushes back in
	followEnd = 0.35, -- the follow-through held until here
	pocket = 0.62, -- the relaxed stand, hand in pocket
	rest = 1.05, -- back to idle
}

export type Plan = { [string]: number }

-- The beats for an anticipation speed `k` (Cinematic run.k), as design times: the real time
-- available is k x FULL; the segments give way in SHRINK_ORDER down to LEAST, then all but the snaps
-- shrink evenly; each real time is divided by k so Cinematic's own compression (t x k) lands it there.
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
	-- Real times, backward from the hit.
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
		windup = design(real.blue),
		red = design(real.red),
		set = design(real.set),
		still = design(real.still),
		merge = design(real.merge),
		load = design(real.load),
		flick = design(real.flick),
	}
	for name, value in AFTER do
		plan[name] = value
	end
	plans[k] = plan
	return plan
end

local BLUE = rgb(70, 140, 255)
local RED = rgb(255, 55, 70)
local VIOLET = rgb(170, 70, 255)
local VIOLET_LIGHT = rgb(215, 170, 255)
local SHIELD = rgb(130, 195, 255)
local WHITE = Kit.WHITE
local CALLOUT = VIOLET
local TRAIL = ColorSequence.new({
	ColorSequenceKeypoint.new(0, VIOLET_LIGHT),
	ColorSequenceKeypoint.new(0.45, VIOLET),
	ColorSequenceKeypoint.new(1, rgb(90, 30, 170)),
})
local TRAIL_LIFE = 0.22
local SPARKS = ColorSequence.new(WHITE, VIOLET)
local MOTES = { blue = 8, red = 6, reducedShare = 0.5 }
-- The erasure's light: a short, tight violet flash at the main target's chest.
local FINISH_LIGHT = { brightness = 1.8, range = 1.5, seconds = 0.25 } -- range in unit heights
local SHELL_SECONDS = 0.42
local FLICK_STEP = 0.4 -- studs (normal size) he steps into the flick (`lunge`)
local UNIT_HEIGHT = RenderConfig.unitSize.Y

-- The poses (PoseAnimator channels), about twice a realistic gesture: big, readable anime poses.
-- Every body pose names every body channel, so a held pose holds the whole body still. `lunge` (the
-- small step into the flick) runs on keys of its own.
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

-- The blue build: the right arm out wide and forward, palm open, weight settling back.
local BLUE_OUT = pose({
	lean = -6,
	twist = 14,
	rightArm = 88,
	rightArmOut = 55,
	leftArm = -10,
	leftArmOut = 12,
	leftLeg = 12,
	rightLeg = -10,
	headYaw = -14,
	headPitch = 2,
})
-- The red build: both arms spread far apart, the orbs as wide as he can hold them.
local SPREAD = pose({
	crouch = 0.18,
	lean = -8,
	rightArm = 90,
	rightArmOut = 75,
	leftArm = 90,
	leftArmOut = 75,
	leftLeg = 25,
	rightLeg = -22,
	headPitch = -6,
})
-- The set: spread wider and lower still, held (shivering, then dead still).
local SET = with(SPREAD, { crouch = 0.28, lean = -10, rightArmOut = 85, leftArmOut = 85, headPitch = -10 })
-- The merge: the hands slammed together in front of the chest.
local MERGE = pose({
	crouch = 0.3,
	lean = 10,
	twist = -8,
	rightArm = 82,
	rightArmOut = -18,
	leftArm = 82,
	leftArmOut = -18,
	leftLeg = 30,
	rightLeg = -26,
	headPitch = 8,
})
-- The load: the right hand cocked back by the shoulder, the sphere on its fingertips.
local LOAD = pose({
	crouch = 0.45,
	lean = -8,
	twist = -48,
	tilt = -6,
	rightArm = 70,
	rightArmOut = 70,
	leftArm = 35,
	leftArmOut = 25,
	leftLeg = 38,
	rightLeg = -32,
	headYaw = 38,
	headPitch = 4,
})
-- The flick: the arm whipped straight at the target and across, a long stride into it.
local FLICK = pose({
	crouch = 0.22,
	lean = 24,
	twist = 42,
	tilt = 6,
	rightArm = 100,
	rightArmOut = -30,
	leftArm = -25,
	leftArmOut = 30,
	leftLeg = 50,
	rightLeg = -42,
	headYaw = -22,
	headPitch = 6,
})
local FOLLOW = with(FLICK, { twist = 52, rightArmOut = -45, lean = 20 })
-- The recovery: a relaxed stand, the left hand in his pocket, head tipped a little.
local POCKET = pose({
	lean = -3,
	twist = 8,
	rightArm = 12,
	rightArmOut = 6,
	leftArm = -14,
	leftArmOut = 16,
	headYaw = -8,
	headPitch = -5,
})

-- The keys for a plan (planOf).
local function keyframes(T: Plan): { PoseAnimator.Keyframe }
	return {
		{ at = T.windup, pose = with(pose({}), { lunge = 0 }) },
		-- The two builds, then the spread held with a shiver, then in dead stillness.
		{ at = T.red, ease = "quadOut", pose = BLUE_OUT },
		{ at = T.set, ease = "quadOut", pose = SPREAD },
		{ at = T.set + 0.08, ease = "quadOut", hold = math.max(0, T.still - T.set - 0.08), shiver = 2.2, pose = SET },
		{ at = T.still, ease = "hold", hold = T.merge - T.still, pose = SET },
		-- The merge (a snap), then the load dip.
		{ at = T.load, ease = "snap", pose = MERGE },
		{ at = T.flick, ease = "quadOut", pose = LOAD },
		-- The flick (a snap) on the hit, a small step into it; the follow-through held.
		{ at = T.finisher, ease = "snap", pose = FLICK },
		{ at = T.flick, pose = { lunge = 0 } },
		{ at = T.finisher, ease = "expoOut", pose = { lunge = FLICK_STEP } },
		{ at = T.follow, ease = "quadOut", hold = T.followEnd - T.follow, pose = FOLLOW },
		-- The relaxed stand, hand in pocket, stepping back to where he stands; then idle.
		{ at = T.pocket, ease = "back", hold = 0.2, pose = POCKET },
		{ at = T.pocket, ease = "inOut", pose = { lunge = 0 } },
		{ at = T.rest, ease = "inOut", pose = pose({}) },
	}
end

local def = {}

-- This run's plan (by its anticipation speed), kept on the run for the beats.
local function planFor(run): Plan
	local plan = run.memo.plan
	if not plan then
		plan = planOf(run.k or 1)
		run.memo.plan = plan
	end
	return plan
end

-- Tracks by plan, built once each.
local tracks: { [Plan]: any } = {}
function def.poseFor(run)
	local plan = planFor(run)
	local track = tracks[plan]
	if not track then
		track = PoseAnimator.track(keyframes(plan))
		tracks[plan] = track
	end
	return track
end

-- Where his hands meet in front of the chest.
local function between(run): Vector3
	return (run:hand("left") + run:hand("right")) / 2
end

-- Where the sphere lands: the main target's chest, else above the area's center.
local function goal(run): Vector3
	local target = run:target()
	if target and target.part.Parent then
		return target.part.Position
	end
	local center = run:area()
	return center + Vector3.new(0, UNIT_HEIGHT * 0.6, 0)
end

-- The flicking hand's trail (BladeTrail on the bare hand: a short ribbon at the fingertips), made at
-- the windup; it follows the step and scales with the camera distance. Gone once it has faded.
local function attachHand(run)
	if run.memo.hand then
		return
	end
	local trail = BladeTrail.attach(run.view, { hand = "right", from = 0, to = 0.14, viewScale = true })
	trail:add("flick", { colors = TRAIL, lifetime = TRAIL_LIFE })
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
			trail:enable("flick")
		else
			trail:disable("flick")
		end
	end
end

-- One orb's build on a hand: the orb (core and halo) from `from` to the merge, growing in, and motes
-- drawn in (blue) or pushed out (red, `outward`) until the stillness.
local function build(run, plan: Plan, side: string, color: Color3, from: number, count: number, outward: boolean)
	local s = run:scale()
	local function at(): Vector3
		return run:hand(side)
	end
	local view = VfxRecipe.viewScale(at())
	Kit.orb(run, from, plan.merge, color, at, function(u)
		return (0.25 + 0.5 * Kit.easeOut(u * 2.5)) * s * view
	end)
	if outward then
		Kit.converge(run, from + 0.02, plan.still, at, color:Lerp(WHITE, 0.3), 2.4 * s, count, true)
	else
		Kit.converge(run, from + 0.02, plan.still, at, color:Lerp(WHITE, 0.4), 2.6 * s, count)
	end
end

local finisher: (any) -> () -- below

def.beats = {
	{
		at = planOf(1).windup, -- every plan starts its windup at the same design time (-FULL)
		run = function(run)
			local plan = planFor(run)
			local s = run:scale()
			local share = if run.reduced then MOTES.reducedShare else 1
			run:face(run:target())
			attachHand(run)
			-- The callout through the build and the flick; the screen dims a little while he builds.
			UltimateCallout.mark(run.view, CALLOUT, run:span(plan.windup, plan.finisher - plan.windup))
			run:camera(plan.windup, plan.finisher + 0.3, { key = "dim", dim = 0.18, rise = 0.35, fall = 0.3 })
			-- The blue build on the right hand, then the red one on the left, pitched apart.
			build(run, plan, "right", BLUE, plan.windup + 0.08, math.floor(MOTES.blue * share), false)
			Sfx.play("energyCharge", { pitch = 0.8, volume = 0.8 })
			run:at(plan.red, function()
				build(run, plan, "left", RED, plan.red + 0.06, math.floor(MOTES.red * share), true)
				Sfx.play("energyCharge", { pitch = 1.3, volume = 0.8 })
			end)
			-- The merge: the orbs spiral into the point between his hands over the snap, and the violet
			-- sphere rides his right fingertips through the load, crackling.
			run:at(plan.merge, function()
				local view = VfxRecipe.viewScale(between(run))
				for i, color in { BLUE, RED } do
					local phase = if i == 1 then 0 else math.pi
					local side = if i == 1 then "right" else "left"
					Kit.live(run, plan.merge, plan.load, "Ball", color, function(part, u)
						local k = Kit.easeIn(u)
						local center = run:hand(side):Lerp(between(run), k)
						local angle = phase + u * 7
						local r = 0.45 * (1 - k) * s
						part.Size = Vector3.one * 0.7 * (1 - 0.5 * k) * s * view
						part.CFrame = CFrame.new(center + Vector3.new(math.cos(angle) * r, math.sin(angle) * r * 0.6, 0))
						part.Transparency = 0.05
					end)
				end
			end)
			run:at(plan.load, function()
				local view = VfxRecipe.viewScale(run:hand("right"))
				Kit.orb(run, plan.load, plan.flick, VIOLET, function()
					return run:hand("right")
				end, function(u)
					return (0.55 + 0.35 * Kit.easeOut(u * 2)) * s * view
				end)
				for i = 0, (if run.reduced then 0 else 1) do
					run:at(plan.load + 0.02 + i * 0.05, function()
						local center = run:hand("right")
						local offset = Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5)
						FxKit.beam(center, center + offset * 1.4 * s * view, VIOLET_LIGHT, 0.12 * view, 0.07, "jagged")
					end)
				end
				Sfx.play("windGust", { pitch = 1.4, volume = 0.5 })
			end)
			-- The flick: the hand trail on, and the sphere crosses to the area in a blink.
			run:at(plan.flick - 0.01, function()
				setTrail(run, true)
			end)
			run:at(plan.flick, function()
				local start = run:hand("right")
				local to = goal(run)
				local view = VfxRecipe.viewScale(to)
				Kit.live(run, plan.flick, plan.finisher, "Ball", VIOLET_LIGHT, function(part, u)
					part.Size = Vector3.one * 0.9 * s * view
					part.CFrame = CFrame.new(start:Lerp(to, Kit.easeIn(u)))
					part.Transparency = 0
				end)
				Sfx.play("energyRelease")
			end)
			run:at(plan.trailOff, function()
				setTrail(run, false)
			end)
			-- The erasure waits for the real Area event; should it never come, it still plays.
			run:at(plan.finisher + 0.05, function()
				if not run.memo.finished then
					run.memo.finished = true
					finisher(run)
				end
			end)
		end,
	},
}

-- The cast itself: no generic burst at his hands (the flick is the release).
function def.release(_run): boolean
	return true
end

-- The erasure on the real hit: a hollow violet shell swelling over the area (see-through, gone by
-- +0.42), one mesh ring, a white-violet core and a hit star on the main target, sparks, a light;
-- hit-stop on the bodies (0.07 s); the boom, the shake, the punch-in and a short camera push; every
-- enemy knocked back (the main one 2.5 studs and launched 0.8; the rest 1.5); then the gust and the
-- drifting motes.
finisher = function(run)
	local center, radius = run:area()
	local s = run:scale()
	local main = run:target()
	local targets = run:targets()
	local held = { run.view }
	for _, view in targets do
		table.insert(held, view)
	end
	local hit = goal(run)
	local view = VfxRecipe.viewScale(hit)
	-- The shell is a bloom: about half the area radius across, behind the main target as the camera
	-- sees it, so the caster and the hit stay in view.
	local bloomAt = (if main then main.part.Position else center + Vector3.new(0, UNIT_HEIGHT * 0.6, 0))
	local camera = workspace.CurrentCamera
	if camera then
		local away = bloomAt - camera.CFrame.Position
		away = Vector3.new(away.X, 0, away.Z)
		if away.Magnitude > 1e-3 then
			bloomAt += away.Unit * 0.6
		end
	end
	local bloomView = VfxRecipe.viewScale(bloomAt)
	Kit.shell(run, 0, SHELL_SECONDS, VIOLET, bloomAt, function(u)
		return radius * (0.6 + 0.4 * Kit.easeOut(u)) * bloomView
	end, function(u)
		return 0.5 + 0.5 * Kit.easeIn(u)
	end)
	VfxRecipe.meshRing(center, radius * 0.7, VIOLET, 0.4, 0.3)
	ImpactEffects.ball(hit, VIOLET_LIGHT, UNIT_HEIGHT * 0.9 * s * view, 0.15)
	VfxRecipe.kitHitStar(hit, UNIT_HEIGHT * 0.8 * view, VIOLET, view)
	VfxRecipe.sparks(hit, 0.7 * view, 12, SPARKS, nil, view)
	if not run.reduced then
		ImpactEffects.light(hit, VIOLET, FINISH_LIGHT.brightness, FINISH_LIGHT.range * UNIT_HEIGHT, FINISH_LIGHT.seconds)
	end
	HitFeel.hitStop(held, 0.07, { caster = run.view })
	for _, target in targets do
		HitFeel.react(target, run:chest(), if target == main then { final = true } else { knock = 1.5, tilt = 18 })
	end
	HitFeel.cameraShake(0.3, 0.35)
	HitFeel.punchIn(1)
	run:camera(0, 0.45, { key = "push", push = 2, focus = center, rise = 0.05, fall = 0.35 })
	Sfx.play("impactHeavy")
	run:at(AFTER.gust, function()
		Sfx.play("windGust", { pitch = 0.8 })
	end)
	if not run.reduced then
		Kit.drift(run, 0.15, 1.0, VIOLET_LIGHT, center, radius * 0.8, 0.18)
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
	elseif kind == "AreaStun" then
		return true -- the erasure is the held area's mark
	elseif kind == "Damage" and event.target and not event.dot then
		return true -- the erasure draws every hit
	elseif kind == "Shield" and event.target == run.unitIndex then
		-- A short blue shimmer around him; the shield bubble still shows (CombatPlayback).
		local at = run.view.part.Position
		Kit.shell(run, 0, 0.4, SHIELD, at, function(u)
			return run.view.part.Size.Y * (1.2 + 0.2 * u)
		end, function(u)
			return 0.7 + 0.3 * u
		end)
		return false
	end
	return false
end

return def
