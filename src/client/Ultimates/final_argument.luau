-- final_argument (Tier 5): bored, then serious, then one punch that changes the board. The real
-- cast is a single huge true-damage hit on his target (one Damage) at the Cast event (t = 0).
-- Everything before 0 is anticipation; the punch lands exactly on the real hit. Bare fists: the
-- punching hand carries a short trail. Every movement is the figure's pose offset (UnitView): his real
-- position never changes.
-- Designed timeline (real seconds at full length; SEGMENTS):
--   -1.38  slouched and bored: leaning, head tipped, arms hanging; the screen dims a little; the
--          callout (a pale gold outline on him, a small ground ring)
--   -1.08  he straightens: chest up, chin level (the face changes)
--   -0.88  set: the fist draws back slowly, the other hand up, the stance dropping; a low aura on him,
--          the air bending around the fist, dust lifting off the board; a rising wind, until -0.43
--   -0.43  stillness: nothing moves; the camera pushes to his face, then to the fist
--   -0.18  a 0.12 s load dip: lower, the fist further back
--   -0.06  the punch's 0.06 s snap
--    0     THE PUNCH, almost invisible, on the real hit: the arm thrown straight at the target (a
--          short fist trail) with a step into it; a brief white flash behind the target and a white
--          hit star, streaks of air blasting past it along the punch, one shock ring, a long ground
--          crack along the punch, dust rolling out, a few stones flung (not when reduced), a light;
--          hit-stop on the bodies; the boom and the slam, a strong shake, the punch-in and the camera
--          pulling back; the target knocked 2.5 studs and launched 0.8
--   +0.06  the follow-through, the arm out, held to +0.4
--   +0.15  stones and debris clatter
--   +0.85  back to bored, slouched again; idle by +1.3
-- When the real window before the cast is shorter (Cinematic run.k < 1, at least the tier's 0.6),
-- the anticipation is laid out again for it (planOf): the stillness gives first, then the draw, then
-- the straightening, then the bored opening, and only past that does everything but the load and the
-- snap shrink evenly. The load, the snap and everything after the hit never shrink.
-- Not used from the concept: the full-screen white impact frame (the quality bar: no effect covers
-- most of the screen); the brief white core at the target is the flash.
-- Readable from the match camera (ViewScale: 1 at close cameras, up to 1.8 there): the fist trail,
-- the air bend, the dust, the streaks, the shock ring, the crack, the flash, the hit star and the
-- sparks grow with it. (The aura's sheets are sized from his body.)
-- Layers (tier 5, within its 44; peak ~25 at the hit, estimated): the aura spikes (particles, ending
-- at the load), the air bend (1, through the draw), at the hit 10 streaks (5 when reduced), the
-- groove (1), the shock ring (1, the only ring), the flash (2), the hit star, sparks and dust
-- (particles), 3 stones (not when reduced), a light (not when reduced), the fist trail
-- (BladeTrail); the callout's ring. Camera: a
-- dim through the build, pushes to the face and fist, a pull at the hit (tier 5 allows them).
-- Poses: PoseAnimator; hit feel: HitFeel; callout: UltimateCallout; sounds: Sfx.

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

-- The anticipation's segments in real seconds at full length, in order up to the hit (1.38 s in
-- all), and how far each may shrink when the window is short (`least`), in the order they give way
-- (the stillness first, then the draw, then the straightening, then the bored opening).
local SEGMENTS = {
	bored = 0.3, -- windup start -> slouched and bored
	straighten = 0.2, -- chest up, chin level
	draw = 0.45, -- the fist drawn back slowly (the set)
	still = 0.25, -- stillness: the camera to the face, then the fist
	load = 0.12, -- the load dip
	snap = 0.06, -- the punch's snap, ending on the hit
}
local LEAST = { still = 0.1, draw = 0.2, straighten = 0.12, bored = 0.15 }
local SHRINK_ORDER = { "still", "draw", "straighten", "bored" }
local ORDER = { "bored", "straighten", "draw", "still", "load", "snap" }
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
	debris = 0.15, -- the stones clatter
	followEnd = 0.4, -- the follow-through held until here
	bored = 0.85, -- slouched again
	rest = 1.3, -- back to idle
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
		windup = design(real.bored),
		straighten = design(real.straighten),
		draw = design(real.draw),
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
local GOLD = rgb(255, 222, 140)
local AURA = rgb(255, 185, 50) -- saturated: the pale gold read as cream
local CRACK = rgb(70, 60, 52)
local STONE = rgb(150, 140, 128)
local CALLOUT = GOLD
local TRAIL = ColorSequence.new({
	ColorSequenceKeypoint.new(0, WHITE),
	ColorSequenceKeypoint.new(0.5, GOLD),
	ColorSequenceKeypoint.new(1, rgb(230, 170, 70)),
})
local TRAIL_LIFE = 0.16
local SPARKS = ColorSequence.new(WHITE, GOLD)
local BLAST = { count = 10, reduced = 5, length = 14, width = 5 } -- the air torn past the target: streaks, not rings
local CRACK_LENGTH = 10 -- studs along the punch
local STONES = 3
local STEP = 0.8 -- studs (normal size) he steps into the punch (`lunge`)
-- The punch's light: a short, tight white flash at the target's chest.
local FINISH_LIGHT = { brightness = 1.8, range = 1.5, seconds = 0.2 } -- range in unit heights
local UNIT_HEIGHT = RenderConfig.unitSize.Y

-- The poses (PoseAnimator channels), about twice a realistic punch: big, readable anime poses.
-- Every body pose names every body channel, so a held pose holds the whole body still. `lunge` (the
-- step into the punch) runs on keys of its own.
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

-- Bored: slouched forward, tipped to one side, arms hanging, head down and turned away.
local BORED = pose({
	crouch = 0.06,
	lean = 14,
	tilt = 10,
	rightArm = -4,
	leftArm = -4,
	headPitch = 22,
	headYaw = 14,
})
-- Straight: chest up, chin level, eyes on the target.
local STRAIGHT = pose({ lean = -6, rightArm = 4, leftArm = 4, headPitch = -2 })
-- The draw: the fist drawn far back by the hip, the right shoulder turned away, the other hand up in
-- front, the stance low and wide, eyes on the target.
local DRAW = pose({
	crouch = 0.38,
	lean = -10,
	twist = -62,
	tilt = -4,
	rightArm = -45,
	rightArmOut = 25,
	leftArm = 78,
	leftArmOut = 10,
	leftLeg = 42,
	rightLeg = -38,
	headYaw = 32,
	headPitch = 4,
})
-- The load: lower, the fist further back.
local LOAD = with(DRAW, { crouch = 0.48, twist = -72, rightArm = -58, lean = -12 })
-- The punch: the arm thrown straight at the target, the body turning through it, a long stride.
local PUNCH = pose({
	crouch = 0.25,
	lean = 22,
	twist = 52,
	tilt = 4,
	rightArm = 95,
	rightArmOut = -5,
	leftArm = -30,
	leftArmOut = 20,
	leftLeg = 52,
	rightLeg = -46,
	headYaw = -16,
	headPitch = 6,
})
local FOLLOW = with(PUNCH, { lean = 18, twist = 46, crouch = 0.2 })

-- The keys for a plan (planOf) and a step of `step` studs (normal size) into the punch (`lunge`).
local function keyframes(T: Plan, step: number): { PoseAnimator.Keyframe }
	return {
		{ at = T.windup, pose = with(pose({}), { lunge = 0 }) },
		-- Bored, then straight.
		{ at = T.straighten, ease = "inOut", pose = BORED },
		{ at = T.draw, ease = "quadOut", pose = STRAIGHT },
		-- The slow draw, held with a faint shiver, then in stillness.
		{ at = T.still, ease = "inOut", pose = DRAW },
		{ at = T.still + 0.001, ease = "hold", hold = T.load - T.still, pose = DRAW },
		-- The load dip.
		{ at = T.snap, ease = "quadOut", pose = LOAD },
		-- The punch (a snap) on the hit, a step into it; the follow-through held.
		{ at = T.finisher, ease = "snap", pose = PUNCH },
		{ at = T.snap, pose = { lunge = 0 } },
		{ at = T.finisher, ease = "snap", pose = { lunge = step } },
		{ at = T.follow, ease = "quadOut", hold = T.followEnd - T.follow, pose = FOLLOW },
		-- Back to bored, stepping back to where he stands; then idle.
		{ at = T.bored, ease = "inOut", hold = 0.2, pose = BORED },
		{ at = T.bored, ease = "inOut", pose = { lunge = 0 } },
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

-- Tracks by plan and step length (normal size, scaled by UnitView), built once each.
local tracks: { [Plan]: any } = {}
function def.poseFor(run)
	local plan = planFor(run)
	local track = tracks[plan]
	if not track then
		track = PoseAnimator.track(keyframes(plan, STEP / math.max(UnitView.sizeFactor(run.view), 0.1)))
		tracks[plan] = track
	end
	return track
end

-- The fist's trail (BladeTrail on the bare hand: a short ribbon at the knuckles), made at the windup;
-- it follows the step and scales with the camera distance. Gone once it has faded.
local function attachFist(run)
	if run.memo.fist then
		return
	end
	local trail = BladeTrail.attach(run.view, { hand = "right", from = 0, to = 0.12, viewScale = true })
	trail:add("punch", { colors = TRAIL, lifetime = TRAIL_LIFE })
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
			trail:enable("punch")
		else
			trail:disable("punch")
		end
	end
end

local finisher: (any, any?) -> () -- below

def.beats = {
	{
		at = planOf(1).windup, -- every plan starts its windup at the same design time (-FULL)
		run = function(run)
			local plan = planFor(run)
			local s = run:scale()
			run:face(run:target())
			attachFist(run)
			UltimateCallout.mark(run.view, CALLOUT, run:span(plan.windup, plan.finisher - plan.windup))
			run:camera(plan.windup, plan.finisher + 0.4, { key = "dim", dim = 0.22, rise = 0.4, fall = 0.3 })
			-- The draw: a low aura, the air bending around the fist, dust lifting, a rising wind.
			run:at(plan.draw, function()
				-- Ends at the load: its sheets live ~0.3 s where they were emitted, so none hang behind the step.
				VfxRecipe.kitAuraSpike(run, run.view, AURA, plan.draw, plan.load - plan.draw, 1)
				local view = VfxRecipe.viewScale(run:hand("right"))
				Kit.live(run, plan.draw, plan.finisher, "Ball", WHITE, function(part, u)
					local pulse = 1 + 0.06 * math.sin(run:now() * 30)
					part.Size = Vector3.one * (0.6 + 1.2 * Kit.easeIn(u)) * pulse * s * view
					part.CFrame = CFrame.new(run:hand("right"))
					part.Transparency = 0.86 - 0.12 * u
				end, Enum.Material.Glass)
				local ground = run:ground()
				VfxRecipe.kitDust(ground, UNIT_HEIGHT * 0.45 * s * VfxRecipe.viewScale(ground), 2, 0.6)
				Sfx.play("windGust", { pitch = 0.75, volume = 0.6 })
			end)
			-- Stillness: the camera to his face, then to the fist; the wind rises.
			run:at(plan.still, function()
				run:camera(
					plan.still,
					plan.load,
					{ key = "push", push = 3, focus = run:head(), rise = 0.12, fall = 0.02 }
				)
				run:camera(plan.load, plan.finisher, {
					key = "fist",
					push = 3.4,
					focus = run:hand("right"),
					rise = 0.03,
					fall = 0.03,
				})
				Sfx.play("windGust", { pitch = 1.25, volume = 0.5 })
			end)
			-- The fist's trail draws through the punch.
			run:at(plan.snap - 0.01, function()
				setTrail(run, true)
			end)
			run:at(plan.trailOff, function()
				setTrail(run, false)
			end)
			-- The punch waits for the real hit; should it never come, it still plays.
			run:at(plan.finisher + 0.05, function()
				if not run.memo.finished then
					run.memo.finished = true
					finisher(run, run:target())
				end
			end)
		end,
	},
}

-- The cast itself: no generic burst at his hands (the punch is the release).
function def.release(_run): boolean
	return true
end

-- The punch on the real hit: a brief white core and a hit star at the target, two cones of air
-- tearing past it, one shock ring, a long crack along the punch, dust rolling out, stones flung, a
-- light; hit-stop on the bodies (0.07 s); the boom and the slam, the shake, the punch-in and the
-- camera pulling back; the target knocked 2.5 studs and launched 0.8.
finisher = function(run, target: any?)
	local s = run:scale()
	local direction = run:forward()
	local hit = run:chest() + direction * UNIT_HEIGHT
	if target and target.part and target.part.Parent then
		local flat = target.part.Position - run.view.part.Position
		flat = Vector3.new(flat.X, 0, flat.Z)
		direction = if flat.Magnitude > 1e-3 then flat.Unit else direction
		hit = target.part.Position
	end
	local floor = Vector3.new(hit.X, run:ground().Y, hit.Z)
	local view = VfxRecipe.viewScale(hit)
	local past = hit + direction * (target and target.part.Size.X * 0.5 or 1)
	-- The white flash: behind the target as the camera sees it, so it never covers the hit.
	local coreAt = hit
	local camera = workspace.CurrentCamera
	if camera then
		local away = hit - camera.CFrame.Position
		away = Vector3.new(away.X, 0, away.Z)
		if away.Magnitude > 1e-3 then
			coreAt += away.Unit * 0.8
		end
	end
	ImpactEffects.ball(coreAt, WHITE, UNIT_HEIGHT * 0.9 * s * view, 0.12)
	VfxRecipe.kitHitStar(hit, UNIT_HEIGHT * 0.8 * view, WHITE, view)
	VfxRecipe.sparks(hit, 0.7 * view, 12, SPARKS, direction, view)
	-- The air torn past the target: streaks blasting along the punch (no rings: one shock ring is
	-- the cast's only ring at this point).
	Kit.streaks(
		run,
		0,
		past,
		direction,
		if run.reduced then BLAST.reduced else BLAST.count,
		BLAST.length * view,
		BLAST.width * view,
		WHITE
	)
	VfxRecipe.shock(floor, UNIT_HEIGHT * 0.9 * s, WHITE, view)
	Kit.groove(run, 0, 1.2, CRACK, floor, floor + direction * CRACK_LENGTH * view, 0.8 * view)
	VfxRecipe.kitDust(floor, UNIT_HEIGHT * 0.9 * s * view, 4, 0.7)
	for i = 1, 2 do
		run:at(0.06 * i, function()
			local at = floor + direction * (i * 3)
			VfxRecipe.kitDust(at, UNIT_HEIGHT * 0.45 * s * VfxRecipe.viewScale(at), 1, 0.6)
		end)
	end
	if not run.reduced then
		ImpactEffects.light(hit, WHITE, FINISH_LIGHT.brightness, FINISH_LIGHT.range * UNIT_HEIGHT, FINISH_LIGHT.seconds)
		for i = 1, STONES do
			local at = floor + Vector3.new(0, 0.3, 0)
			local fling = direction * (5 + math.random() * 5)
				+ Vector3.new((math.random() - 0.5) * 3, 3 + math.random() * 2, 0)
			local spin = math.random() * 4
			Kit.block(run, 0, 0.6, STONE, function(u)
				local p = at + fling * u + Vector3.new(0, -9 * u * u, 0)
				return CFrame.new(p) * CFrame.Angles(spin * u * 6, spin, 0)
			end, function()
				return Vector3.one * (0.25 + i * 0.05) * view
			end, function(u)
				return if u > 0.8 then (u - 0.8) * 5 else 0
			end, Enum.Material.Slate)
		end
	end
	local held = { run.view }
	if target then
		table.insert(held, target)
	end
	HitFeel.hitStop(held, 0.07, { caster = run.view })
	if target then
		HitFeel.react(target, run:chest(), { final = true })
	end
	HitFeel.cameraShake(0.3, 0.35)
	HitFeel.punchIn(1)
	run:camera(0, 0.6, { key = "pull", push = -2.4, focus = run:chest(), rise = 0.03, fall = 0.5 })
	Sfx.play("impactHeavy")
	Sfx.play("groundSlam", { volume = 0.8 })
	run:at(AFTER.debris, function()
		Sfx.play("rockDebris", { volume = 0.7 })
	end)
end

function def.event(run, event): boolean
	if event.kind == "Damage" and event.target and not event.dot then
		-- One punch, one board-changing impact (should a cast ever hit twice, the second is drawn by
		-- the first).
		if not run.memo.finished then
			run.memo.finished = true
			finisher(run, run.context.views[event.target])
		end
		return true
	end
	return false
end

return def
