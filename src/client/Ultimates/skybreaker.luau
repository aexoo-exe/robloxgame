-- skybreaker (Tier 2): the air pressure behind the target. The real cast hits his target hard (a
-- Damage) and carries on through the enemies in a line behind it (Area with shape LINE and its
-- cells, a Damage per enemy on it), all at the Cast event (t = 0). Everything before 0 is
-- anticipation; the smash lands exactly on the real hit. Bare fists: the punching hand carries a
-- short trail. Every movement is the figure's pose offset (UnitView): his real position never
-- changes.
-- Designed timeline (real seconds at full length; SEGMENTS):
--   -0.80  green lightning starts crackling over his body; the fist draws back, the shoulder turned
--          away, low; the callout (a green outline on him, a small ground ring)
--   -0.55  set: held, shivering with the charge, until -0.30
--   -0.30  stillness (the crackle stops), until -0.18
--   -0.18  a 0.12 s load dip: lower, the fist further back
--   -0.06  the smash's 0.06 s snap
--    0     THE SMASH, on the real hit: the fist thrown through the target (a short green trail) with
--          a step into it; a green hit star, dust bursting up, one shock ring at the target; green
--          pressure streaks carrying through the real line behind it, dust on every cell of it;
--          hit-stop on the bodies; the boom, a shake, the punch-in; the target knocked 2.5 studs and
--          launched 0.8, the line's enemies 1.5
--   +0.06  the follow-through, the fist out, held to +0.35
--   +0.5   the arm hangs, a wince (the cost of the punch), stepping back; idle by +0.8
-- When the real window before the cast is shorter (Cinematic run.k < 1, at least the tier's 0.6),
-- the anticipation is laid out again for it (planOf): the stillness gives first, then the set, then
-- the coil, and only past that does everything but the load and the snap shrink evenly. The load,
-- the snap and everything after the hit never shrink.
-- Readable from the match camera (ViewScale: 1 at close cameras, up to 1.8 there): the trail, the
-- hit star, the dust, the ring and the streaks grow with it (the crackle is sized from his body).
-- Layers (tier 2, within its 18; peak ~11 at the smash, estimated): the crackle (particles, ending at
-- the stillness), the hit star and 2 dust billows, one shock ring, 4 streaks (3 when reduced),
-- dust on each line cell (particles); the fist trail (BladeTrail); the callout's ring. Poses:
-- PoseAnimator; hit feel: HitFeel; callout: UltimateCallout; sounds: Sfx.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RenderConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("RenderConfig"))

local BladeTrail = require(script.Parent.Parent.BladeTrail)
local HitFeel = require(script.Parent.Parent.HitFeel)
local PoseAnimator = require(script.Parent.Parent.PoseAnimator)
local Sfx = require(script.Parent.Parent.Sfx)
local UltimateCallout = require(script.Parent.Parent.UltimateCallout)
local UltimateKit = require(script.Parent.Parent.UltimateKit)
local UnitView = require(script.Parent.Parent.UnitView)
local VfxRecipe = require(script.Parent.Parent.VfxRecipe)

local Kit = UltimateKit
local rgb = Color3.fromRGB

-- The anticipation's segments in real seconds at full length, in order up to the hit (0.80 s in
-- all), and how far each may shrink when the window is short (`least`), in the order they give way
-- (the stillness first, then the set, then the coil).
local SEGMENTS = {
	coil = 0.25, -- windup start -> the fist drawn back
	set = 0.25, -- held, shivering, crackling
	still = 0.12, -- stillness
	load = 0.12, -- the load dip
	snap = 0.06, -- the smash's snap, ending on the hit
}
local LEAST = { still = 0.05, set = 0.1, coil = 0.12 }
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
	trailOff = 0.14, -- the fist trail stops drawing
	followEnd = 0.35, -- the follow-through held until here
	wince = 0.5, -- the arm hangs, the wince
	rest = 0.8, -- back to idle
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

local WHITE = Kit.WHITE
local GREEN = rgb(90, 240, 150)
local GREEN_DEEP = rgb(30, 170, 90)
local CALLOUT = GREEN
local TRAIL = ColorSequence.new({
	ColorSequenceKeypoint.new(0, rgb(220, 255, 230)),
	ColorSequenceKeypoint.new(0.5, GREEN),
	ColorSequenceKeypoint.new(1, GREEN_DEEP),
})
local STREAKS = { full = 4, reduced = 3 }
local STEP = 0.35 -- studs (normal size) he steps into the smash (`lunge`)
local UNIT_HEIGHT = RenderConfig.unitSize.Y

-- The poses (PoseAnimator channels), about twice a realistic punch: big, readable anime poses.
-- Every body pose names every body channel, so a held pose holds the whole body still. `lunge` (the
-- step into the smash) runs on keys of its own.
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

-- The fist drawn back, the right shoulder turned away, low, the other hand up in front.
local DRAW = pose({
	crouch = 0.4,
	lean = -8,
	twist = -55,
	rightArm = -50,
	rightArmOut = 20,
	leftArm = 70,
	leftArmOut = 10,
	leftLeg = 36,
	rightLeg = -32,
	headYaw = 30,
})
local LOAD = with(DRAW, { crouch = 0.5, twist = -64, rightArm = -62 })
-- The smash: the fist thrown straight through, the body turning hard into it, a long stride.
local SMASH = pose({
	crouch = 0.3,
	lean = 24,
	twist = 52,
	tilt = 4,
	rightArm = 96,
	rightArmOut = -5,
	leftArm = -30,
	leftArmOut = 20,
	leftLeg = 48,
	rightLeg = -42,
	headYaw = -14,
	headPitch = 6,
})
local FOLLOW = with(SMASH, { lean = 20, twist = 46 })
-- The wince: the punching arm hanging, the shoulder dropped, head tipped down and away.
local WINCE = pose({
	crouch = 0.12,
	lean = 8,
	tilt = 10,
	rightArm = -6,
	rightArmOut = 6,
	leftArm = 20,
	leftArmOut = -10,
	headPitch = 14,
	headYaw = 12,
})

-- The keys for a plan (planOf) and a step of `step` studs (normal size) into the smash.
local function keyframes(T: Plan, step: number): { PoseAnimator.Keyframe }
	return {
		{ at = T.windup, pose = with(pose({}), { lunge = 0 }) },
		-- The draw, held shivering, then in stillness.
		{ at = T.set, ease = "quadOut", hold = T.still - T.set, shiver = 1.6, pose = DRAW },
		{ at = T.still, ease = "hold", hold = T.load - T.still, pose = DRAW },
		{ at = T.snap, ease = "quadOut", pose = LOAD },
		-- The smash (a snap) on the hit, a step into it; the follow-through held.
		{ at = T.finisher, ease = "snap", pose = SMASH },
		{ at = T.snap, pose = { lunge = 0 } },
		{ at = T.finisher, ease = "snap", pose = { lunge = step } },
		{ at = T.follow, ease = "quadOut", hold = T.followEnd - T.follow, pose = FOLLOW },
		{ at = T.followEnd, ease = "hold", pose = { lunge = step } },
		-- The wince, stepping back to where he stands; then idle.
		{ at = T.wince, ease = "inOut", hold = 0.12, pose = WINCE },
		{ at = T.wince, ease = "inOut", pose = { lunge = 0 } },
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

-- The fist's trail (BladeTrail on the bare hand), made at the windup. Gone once it has faded.
local function attachFist(run)
	if run.memo.fist then
		return
	end
	local trail = BladeTrail.attach(run.view, { hand = "right", from = 0, to = 0.12, viewScale = true })
	trail:add("smash", { colors = TRAIL, lifetime = 0.16 })
	run.memo.fist = trail
	run:at(planFor(run).rest, function()
		trail:destroy()
		run.memo.fist = nil
	end)
end

local function setTrail(run, on: boolean)
	local trail = run.memo.fist
	if trail then
		if on then
			trail:enable("smash")
		else
			trail:disable("smash")
		end
	end
end

local finisher: (any, any?) -> () -- below

def.beats = {
	{
		at = planOf(1).windup, -- every plan starts its windup at the same design time (-FULL)
		run = function(run)
			local plan = planFor(run)
			run:face(run:target())
			attachFist(run)
			UltimateCallout.mark(run.view, CALLOUT, run:span(plan.windup, plan.finisher - plan.windup))
			-- Green lightning crackling over him through the coil and the set; it stops for the stillness.
			VfxRecipe.kitCrackleAura(run, run.view, GREEN, plan.windup + 0.03, plan.still - plan.windup - 0.03, 2, 1.6)
			Sfx.play("electricBuzz", { volume = 0.7 })
			run:at(plan.snap - 0.01, function()
				setTrail(run, true)
			end)
			run:at(AFTER.trailOff, function()
				setTrail(run, false)
			end)
			-- The smash waits for the real hit; should it never come, it still plays.
			run:at(plan.finisher + 0.05, function()
				if not run.memo.finished then
					run.memo.finished = true
					finisher(run, run:target())
				end
			end)
		end,
	},
}

-- The cast itself: no generic burst (the smash is the release).
function def.release(_run): boolean
	return true
end

-- The pressure through the real line behind the target: green streaks along it, dust on every cell.
local function pressure(run, line: any)
	local target = run:target()
	local from = if target and target.part.Parent then target.part.Position else run:chest()
	local far = from
	for _, cell in line.cells do
		local at = run.context.toWorld(cell[1], cell[2])
		VfxRecipe.kitDust(at, UNIT_HEIGHT * 0.35 * VfxRecipe.viewScale(at), 1, 0.5)
		if (at - from).Magnitude > (far - from).Magnitude then
			far = at
		end
	end
	local view = VfxRecipe.viewScale(from)
	local along = far - from
	if along.Magnitude < 0.5 then
		along = run:forward() * UNIT_HEIGHT * 2
	end
	Kit.streaks(
		run,
		run:designTime(),
		from,
		along,
		if run.reduced then STREAKS.reduced else STREAKS.full,
		(along.Magnitude + 3) * view,
		2.4 * view,
		GREEN
	)
	Sfx.play("windGust", { pitch = 1.2, volume = 0.6 })
end

-- The smash on the real hit: a green hit star, dust bursting up and one shock ring at the target;
-- hit-stop on the bodies (0.06 s); the boom, the shake, the punch-in; the target knocked 2.5 studs
-- and launched 0.8, the line's enemies 1.5.
finisher = function(run, target: any?)
	local s = run:scale()
	local hit = if target and target.part.Parent
		then target.part.Position
		else run:chest() + run:forward() * UNIT_HEIGHT
	local view = VfxRecipe.viewScale(hit)
	local floor = Vector3.new(hit.X, run:ground().Y, hit.Z)
	VfxRecipe.kitHitStar(hit, UNIT_HEIGHT * 0.9 * view, GREEN:Lerp(WHITE, 0.25), view)
	VfxRecipe.kitDust(floor, UNIT_HEIGHT * 0.6 * s * view, if run.reduced then 1 else 2, 0.6)
	VfxRecipe.meshRing(floor, UNIT_HEIGHT * 0.6 * s * view, GREEN, 0.35, 0.3)
	local held = { run.view }
	for _, view_ in run:targets() do
		table.insert(held, view_)
	end
	HitFeel.hitStop(held, 0.06, { caster = run.view })
	for _, other in run:targets() do
		HitFeel.react(other, run:chest(), if other == target then { final = true } else { knock = 1.5, tilt = 18 })
	end
	HitFeel.cameraShake(0.12, 0.2)
	HitFeel.punchIn(1)
	Sfx.play("impactHeavy", { volume = 0.85 })
end

function def.event(run, event): boolean
	local kind = event.kind
	if kind == "Area" and event.shape == "LINE" and event.cells then
		pressure(run, event)
		return true
	elseif kind == "Damage" and event.target and not event.dot then
		if not run.memo.finished then
			run.memo.finished = true
			finisher(run, run.context.views[event.target])
		end
		return true
	end
	return false
end

return def
