-- severing_temple (Tier 5): the shrine and the cut storm. The real cast cuts every enemy within 2
-- hexes of his target (Area, a Damage per enemy) at the Cast event (t = 0) and leaves a 4-second
-- damage over time on them (Dot, then a Damage tick each second). Everything before 0 is
-- anticipation; the storm lands exactly on the real Area event. No weapon: his sweeping right hand
-- carries the trail. Every movement is the figure's pose offset (UnitView): his real position never
-- changes.
-- Designed timeline (real seconds at full length; SEGMENTS):
--   -1.23  he coils into a hand sign: both hands up at the chest, head bowed, weight sinking; the
--          ground under the area starts to darken into a shallow pool; the screen dims a little;
--          the callout (a crimson outline on him, a small ground ring)
--   -0.93  set: the right hand rises high over his head and holds there, shivering, the left still
--          in the sign; the shrine climbs out of the ground behind the area, red-lit, until -0.48
--   -0.48  the bell: one deep chime and one slow crimson ring across the area; then dead
--          stillness, nothing moves, until -0.18
--   -0.18  a 0.12 s load dip: the raised hand lifts a little higher, the knees give
--   -0.06  the sweep's 0.06 s snap
--    0     THE CUT STORM, on the real hit: the hand sweeps down and out (a crimson trail off it);
--          the area fills with fast cuts, each one wiping in along its length and gone in 0.14 s,
--          over 0.45 s; one mesh ring; a crimson core and a hit star on the main target, sparks, a
--          light; hit-stop on the bodies; the boom, the rapid metal cuts, a strong shake, the
--          punch-in; every enemy staggers (the main one knocked 2.5 studs and launched 0.8)
--   +0.06  the follow-through, the arm out wide, held to +0.4
--   +0.5   the shrine sinks back into the ground by +1.3; the pool fades by +1.5
--   +0.7   arms crossed in front of him, unmoved; idle by +1.6
--   ticks  each real damage-over-time tick: three fresh cuts wipe across that enemy
-- When the real window before the cast is shorter (Cinematic run.k < 1, at least the tier's 0.6),
-- the anticipation is laid out again for it (planOf): the stillness gives first, then the set, then
-- the coil, and only past that does everything but the load and the snap shrink evenly. The load,
-- the snap and everything after the hit never shrink.
-- Readable from the match camera (ViewScale: 1 at close cameras, up to 1.8 there): the cuts, the
-- hand trail, the ring, the hit star, the sparks and the core grow with it.
-- Layers (tier 5, within its 44; peak ~22 at the hit, estimated): the pool (1), the shrine (6 wood
-- blocks, 4 red neon strips with their glow layers, 3 teeth when not reduced: ~17 while it stands),
-- the bell ring, at the hit ~8 cuts alive at once (24 over 0.45 s; 12 when reduced), one mesh ring,
-- a core, a hit star, sparks, a light (not when reduced), a hand trail (BladeTrail); the callout's
-- ring. Camera: a dim through the build and a short push at the hit (tier 5 allows both). Poses:
-- PoseAnimator; hit feel: HitFeel; callout: UltimateCallout; sounds: Sfx.

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

-- The anticipation's segments in real seconds at full length, in order up to the hit (1.23 s in
-- all), and how far each may shrink when the window is short (`least`), in the order they give way
-- (the stillness first, then the set, then the coil).
local SEGMENTS = {
	coil = 0.3, -- windup start -> the hand sign reached
	set = 0.45, -- the hand raised, shivering, while the shrine rises
	still = 0.3, -- the bell, then dead stillness
	load = 0.12, -- the load dip
	snap = 0.06, -- the sweep's snap, ending on the hit
}
local LEAST = { still = 0.12, set = 0.15, coil = 0.15 }
local SHRINK_ORDER = { "still", "set", "coil" }
local ORDER = { "coil", "set", "still", "load", "snap" }
local SNAPS = { load = true, snap = true } -- never shrink
local FULL = 0
for _, name in ORDER do
	FULL += SEGMENTS[name]
end

-- After the hit (design seconds = real seconds: never compressed).
local AFTER = {
	finisher = 0,
	follow = 0.06, -- the follow-through pose reached
	trailOff = 0.14, -- the hand trail stops drawing
	storm = 0.45, -- the cuts end
	followEnd = 0.4, -- the follow-through held until here
	sink = 0.5, -- the shrine starts sinking
	sunk = 1.3, -- gone under the ground
	poolGone = 1.5,
	fold = 0.7, -- arms crossed, held
	rest = 1.6, -- back to idle
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
		windup = design(real.coil),
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

local CRIMSON = rgb(225, 30, 50)
local DEEP = rgb(120, 10, 24)
local IVORY = rgb(236, 226, 206)
local WOOD = rgb(42, 22, 20)
local POOL = rgb(34, 6, 10)
local CALLOUT = CRIMSON
local TRAIL = ColorSequence.new({
	ColorSequenceKeypoint.new(0, rgb(255, 120, 130)),
	ColorSequenceKeypoint.new(0.4, CRIMSON),
	ColorSequenceKeypoint.new(1, DEEP),
})
local TRAIL_LIFE = 0.22
local SPARKS = ColorSequence.new(IVORY, CRIMSON)
local CUT_COLORS = { CRIMSON, IVORY, CRIMSON, rgb(255, 90, 100) }
local STORM = { full = 24, reduced = 12, life = 0.14, wipe = 0.35 } -- wipe: share of the life spent drawing in
local TICK_CUTS = 3
local SHRINK_DEPTH = 9 -- studs the shrine starts (and ends) under the ground
-- The hit's light: a short, tight crimson flash at the main target's chest.
local FINISH_LIGHT = { brightness = 1.8, range = 1.5, seconds = 0.25 } -- range in unit heights
local UNIT_HEIGHT = RenderConfig.unitSize.Y

-- The poses (PoseAnimator channels), about twice a realistic gesture: big, readable anime poses.
-- Every body pose names every body channel, so a held pose holds the whole body still. (Arms: `Out`
-- turns a raised arm about the body's front axis, so a forward raise with a big `Out` only rolls it;
-- the playbook's arm rule.)
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

-- The coil: both hands up at the chest in a sign, head bowed, weight sinking.
local SIGN = pose({
	crouch = 0.2,
	lean = 8,
	twist = -8,
	rightArm = 80,
	rightArmOut = -10,
	leftArm = 80,
	leftArmOut = -10,
	leftLeg = 14,
	rightLeg = -12,
	headPitch = 22,
})
-- The set: the right hand raised high overhead, the left still in the sign, leaning back a little,
-- looking up past it.
local RAISE = pose({
	crouch = 0.25,
	lean = -8,
	twist = 10,
	tilt = -4,
	rightArm = 168,
	rightArmOut = 12,
	leftArm = 80,
	leftArmOut = -10,
	leftLeg = 22,
	rightLeg = -20,
	headPitch = -14,
})
-- The load: higher still, the knees giving.
local LOAD = with(RAISE, { rightArm = 178, crouch = 0.34, lean = -12, headPitch = -18 })
-- The sweep: the right arm cut down and out to the side, the body turning into it.
local SWEEP = pose({
	crouch = 0.42,
	lean = 16,
	twist = -32,
	tilt = 6,
	rightArm = 35,
	rightArmOut = 75,
	leftArm = -20,
	leftArmOut = 20,
	leftLeg = 34,
	rightLeg = -30,
	headYaw = -12,
	headPitch = 8,
})
local FOLLOW = with(SWEEP, { rightArmOut = 88, twist = -40, lean = 12 })
-- The recovery: arms crossed low in front of him, upright, unmoved.
local FOLD = pose({
	lean = -3,
	rightArm = 35,
	rightArmOut = -35,
	leftArm = 35,
	leftArmOut = -35,
	headPitch = 6,
})

-- The keys for a plan (planOf).
local function keyframes(T: Plan): { PoseAnimator.Keyframe }
	return {
		{ at = T.windup, pose = pose({}) },
		-- The sign, then the raised hand held with a shiver, then in dead stillness.
		{ at = T.set, ease = "quadOut", pose = SIGN },
		{ at = T.set + 0.12, ease = "quadOut", hold = math.max(0, T.still - T.set - 0.12), shiver = 1.8, pose = RAISE },
		{ at = T.still, ease = "hold", hold = T.load - T.still, pose = RAISE },
		-- The load dip.
		{ at = T.snap, ease = "quadOut", pose = LOAD },
		-- The sweep (a snap) on the hit; the follow-through held.
		{ at = T.finisher, ease = "snap", pose = SWEEP },
		{ at = T.follow, ease = "quadOut", hold = T.followEnd - T.follow, pose = FOLLOW },
		-- Arms crossed, held; then idle.
		{ at = T.fold, ease = "back", hold = 0.5, pose = FOLD },
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

-- The sweeping hand's trail (BladeTrail on the bare hand: a short ribbon at the fingertips), made at
-- the windup; it scales with the camera distance. Gone once it has faded.
local function attachHand(run)
	if run.memo.hand then
		return
	end
	local trail = BladeTrail.attach(run.view, { hand = "right", from = 0, to = 0.14, viewScale = true })
	trail:add("sweep", { colors = TRAIL, lifetime = TRAIL_LIFE })
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
			trail:enable("sweep")
		else
			trail:disable("sweep")
		end
	end
end

-- The shrine's place: past the area, facing back toward him.
local function shrineFrame(run): CFrame
	local center, radius = run:area()
	local away = center - run:ground()
	away = Vector3.new(away.X, 0, away.Z)
	away = if away.Magnitude > 1e-3 then away.Unit else run:forward()
	local base = center + away * radius * 0.85
	return CFrame.lookAt(base, base - away)
end

-- How far up the shrine stands now (0 under the ground, 1 standing): it rises through the set and
-- sinks after the hit.
local function shrineUp(run, plan: Plan): number
	local t = run:designTime()
	if t < 0 then
		return Kit.easeOut((t - plan.set) / math.max(plan.still - plan.set, 1e-3))
	end
	return 1 - Kit.easeIn((t - plan.sink) / (plan.sunk - plan.sink))
end

-- One shrine part: `offset` from the shrine's base frame, `size`, at `solid` transparency (fully
-- clear while under the ground).
local function shrinePart(
	run,
	plan: Plan,
	frame: CFrame,
	color: Color3,
	offset: CFrame,
	size: Vector3,
	solid: number,
	material: Enum.Material?
)
	Kit.block(run, plan.set, plan.sunk, color, function()
		local up = shrineUp(run, plan)
		return frame * CFrame.new(0, -SHRINK_DEPTH * (1 - up), 0) * offset
	end, function()
		return size
	end, function()
		return if shrineUp(run, plan) <= 0.01 then 1 else solid
	end, material)
end

-- The shrine: two pillars with red neon strips, a beam with a strip under it, a pitched roof and a
-- ridge, a few ivory teeth along the beam (not when reduced), a faint red glow between the pillars.
local function buildShrine(run, plan: Plan)
	local frame = shrineFrame(run)
	local v, c = Vector3.new, CFrame.new
	for _, x in { -3.2, 3.2 } do
		shrinePart(run, plan, frame, WOOD, c(x, 3.4, 0), v(0.7, 6.8, 0.7), 0.05)
		shrinePart(run, plan, frame, CRIMSON, c(x * 0.97, 3.4, -0.36), v(0.12, 6.2, 0.05), 0.15, Enum.Material.Neon)
	end
	shrinePart(run, plan, frame, WOOD, c(0, 6.9, 0), v(8.6, 0.55, 1.4), 0.05)
	shrinePart(run, plan, frame, CRIMSON, c(0, 6.6, -0.72), v(8.2, 0.1, 0.05), 0.1, Enum.Material.Neon)
	for _, side in { -1, 1 } do
		shrinePart(
			run,
			plan,
			frame,
			WOOD,
			c(side * 2.6, 7.75, 0) * CFrame.Angles(0, 0, -side * 0.28),
			v(5.8, 0.4, 3.2),
			0.05
		)
	end
	shrinePart(run, plan, frame, WOOD, c(0, 8.45, 0), v(1.2, 0.5, 3.4), 0.05)
	if not run.reduced then
		for i = -1, 1 do
			shrinePart(
				run,
				plan,
				frame,
				IVORY,
				c(i * 2.2, 6.35, -0.5) * CFrame.Angles(0, 0, math.rad(45)),
				v(0.32, 0.32, 0.2),
				0.05
			)
		end
	end
	shrinePart(run, plan, frame, CRIMSON, c(0, 3.3, 0.2), v(5.6, 6, 0.08), 0.82, Enum.Material.Neon)
end

-- One cut: a thin blade at `frame` (its length along X) that wipes in from one end over the first
-- part of its life, then fades: a slash being drawn, never a sprite popping in at full size.
local function cut(frame: CFrame, length: number, color: Color3, delay: number)
	local blade = FxKit.textured("slash", color, "plane")
	ImpactEffects.shape("Block", color, STORM.life, function(part, u)
		local drawn = math.min(1, u / STORM.wipe)
		local long = math.max(0.05, length * drawn)
		part.Size = Vector3.new(long, if blade then length * 0.28 else 0.08, 0.08)
		part.CFrame = frame * CFrame.new(-length / 2 + long / 2, 0, 0)
		part.Transparency = if u < STORM.wipe then 0 else (u - STORM.wipe) / (1 - STORM.wipe) * 0.95
	end, delay, nil, blade)
end

-- `count` cuts across a disc of `radius` around `center` (ground), spread over `span` real seconds
-- from now, each at a random height, heading and slant.
local function cutsAcross(center: Vector3, radius: number, count: number, span: number, scale: number)
	for i = 1, count do
		local angle = math.random() * 2 * math.pi
		local r = radius * math.sqrt(math.random())
		local at = center
			+ Vector3.new(math.cos(angle) * r, UNIT_HEIGHT * (0.2 + 0.7 * math.random()), math.sin(angle) * r)
		local frame = CFrame.new(at)
			* CFrame.Angles(0, math.random() * math.pi * 2, 0)
			* CFrame.Angles(0, 0, (math.random() - 0.5) * 1.8)
		local length = UNIT_HEIGHT * (0.8 + 0.6 * math.random()) * scale
		cut(frame, length, CUT_COLORS[(i - 1) % #CUT_COLORS + 1], (i - 1) / count * span)
	end
end

local finisher: (any) -> () -- below

def.beats = {
	{
		at = planOf(1).windup, -- every plan starts its windup at the same design time (-FULL)
		run = function(run)
			local plan = planFor(run)
			local center, radius = run:area()
			run:face(run:target())
			attachHand(run)
			-- The callout through the build and the sweep; the screen dims a little while he builds.
			UltimateCallout.mark(run.view, CALLOUT, run:span(plan.windup, plan.finisher - plan.windup))
			run:camera(plan.windup, plan.finisher + 0.4, { key = "dim", dim = 0.22, rise = 0.4, fall = 0.4 })
			-- The ground under the area darkens into a shallow pool, then fades after the storm.
			Kit.pool(run, plan.windup, plan.poolGone, POOL, center, function()
				local t = run:designTime()
				return radius * 2 * Kit.easeOut((t - plan.windup) / math.max(plan.set - plan.windup + 0.2, 1e-3))
			end, function()
				local t = run:designTime()
				return 0.35 + 0.65 * Kit.smooth((t - plan.sink) / (plan.poolGone - plan.sink))
			end, Enum.Material.Glass)
			Sfx.play("energyCharge", { pitch = 0.7, volume = 0.6 })
			-- The shrine climbs out of the ground through the set.
			run:at(plan.set, function()
				buildShrine(run, plan)
				ImpactEffects.burst("puff", center + Vector3.new(0, 0.3, 0), nil, {
					color = POOL:Lerp(IVORY, 0.25),
					count = 8,
					size = 1.1,
					speed = { 2, 4 },
					lifetime = { 0.4, 0.7 },
					transparency = 0.4,
				})
			end)
			-- The bell: one deep chime and one slow ring across the area, then stillness.
			run:at(plan.still, function()
				FxKit.ring(
					center,
					CRIMSON,
					radius * 2.4 * VfxRecipe.viewScale(center),
					run:span(plan.still, plan.load - plan.still) + 0.1
				)
				Sfx.play("magicChime", { pitch = 0.5 })
			end)
			-- The sweep's trail draws through the snap and the cut.
			run:at(plan.snap - 0.01, function()
				setTrail(run, true)
			end)
			run:at(plan.trailOff, function()
				setTrail(run, false)
			end)
			-- The storm waits for the real Area event; should it never come, it still plays.
			run:at(plan.finisher + 0.05, function()
				if not run.memo.finished then
					run.memo.finished = true
					finisher(run)
				end
			end)
		end,
	},
}

-- The cast itself: no generic burst at his hands (the sweep is the release).
function def.release(_run): boolean
	return true
end

-- The cut storm on the real hit: the cuts across the area over 0.45 s, one mesh ring, a crimson core
-- (behind the main target as the camera sees it) and a hit star on it, sparks, a light; hit-stop on
-- the bodies (0.07 s); the boom and the rapid metal cuts, the shake, the punch-in and a short push;
-- every enemy staggers (the main one 2.5 studs and launched 0.8; the rest 1.5).
finisher = function(run)
	local center, radius = run:area()
	local main = run:target()
	local targets = run:targets()
	local held = { run.view }
	for _, view in targets do
		table.insert(held, view)
	end
	local view = VfxRecipe.viewScale(center)
	cutsAcross(center, radius, if run.reduced then STORM.reduced else STORM.full, AFTER.storm, view)
	VfxRecipe.meshRing(center, radius * 0.7, CRIMSON, 0.4, 0.3)
	local hit = if main then main.part.Position else center + Vector3.new(0, UNIT_HEIGHT * 0.6, 0)
	local hitView = VfxRecipe.viewScale(hit)
	local coreAt = hit
	local camera = workspace.CurrentCamera
	if camera then
		local away = hit - camera.CFrame.Position
		away = Vector3.new(away.X, 0, away.Z)
		if away.Magnitude > 1e-3 then
			coreAt += away.Unit * 0.6
		end
	end
	ImpactEffects.ball(coreAt, CRIMSON, UNIT_HEIGHT * 0.8 * hitView, 0.14)
	VfxRecipe.kitHitStar(hit, UNIT_HEIGHT * 0.8 * hitView, CRIMSON, hitView)
	VfxRecipe.sparks(hit, 0.7 * hitView, 12, SPARKS, nil, hitView)
	if not run.reduced then
		ImpactEffects.light(
			hit,
			CRIMSON,
			FINISH_LIGHT.brightness,
			FINISH_LIGHT.range * UNIT_HEIGHT,
			FINISH_LIGHT.seconds
		)
	end
	HitFeel.hitStop(held, 0.07, { caster = run.view })
	for _, target in targets do
		HitFeel.react(target, run:chest(), if target == main then { final = true } else { knock = 1.5, tilt = 18 })
	end
	HitFeel.cameraShake(0.3, 0.35)
	HitFeel.punchIn(1)
	run:camera(0, 0.45, { key = "push", push = 1.8, focus = center, rise = 0.05, fall = 0.35 })
	Sfx.play("impactHeavy")
	-- The rapid metal cuts through the storm.
	for i = 0, 4 do
		run:at(0.03 + i * 0.08, function()
			Sfx.play("slashMetal", { pitch = 1 + 0.08 * (i % 3), volume = 0.7 })
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
	elseif kind == "Damage" and event.target and not event.dot then
		return true -- the storm draws every hit
	elseif kind == "Damage" and event.target and event.dot then
		-- A real tick of the damage over time: a few fresh cuts wipe across that enemy.
		local view = run.context.views[event.target]
		if view and view.part.Parent then
			local at = view.part.Position - Vector3.new(0, view.part.Size.Y / 2, 0)
			cutsAcross(at, view.part.Size.X, TICK_CUTS, 0.12, VfxRecipe.viewScale(at) * 0.7)
		end
		return true
	elseif kind == "Dot" then
		return true -- the ticks draw it
	end
	return false
end

return def
