-- reelbreaker (Tier 4): reel in, then the charged punch. The real cast pulls the farthest enemy to
-- the cell next to him (Pull: the target's view slides over ~0.15 s) and hits it hard (Damage), both
-- at the Cast event (t = 0). Everything before 0 is anticipation; the yank lands on the real hit and
-- the punch on the pulled enemy's arrival (+0.12), the moment the hit can be seen. A fishing rod in
-- the right hand (LookKit `rod`), the free left fist. Every movement is the figure's pose offset
-- (UnitView): his real position never changes.
-- Designed timeline (real seconds at full length; SEGMENTS):
--   -1.02  the rod goes up overhead, the body coiling back; the callout (a yellow-green outline on
--          him, a small ground ring)
--   -0.74  the whip's 0.06 s snap: the rod whipped forward (a trail off its tip), the line flying out
--          to the farthest enemy; it hooks with a spark and a tick
--   -0.68  set: hooked, the line held taut; the free fist drawn far back, a yellow-green glow
--          gathering in it, growing, motes drawn in; a shiver of strain, until -0.33
--   -0.33  stillness, the camera leaning in on the fist, until -0.18
--   -0.18  a 0.12 s load dip: lower, the fist further back
--   -0.06  the yank's 0.06 s snap
--    0     THE YANK, on the real hit: the rod ripped back overhead (its trail), the line snapping
--          taut as the real pull slides the enemy in
--   +0.06  the punch's snap (a fist trail), landing as the enemy arrives:
--   +0.12  THE IMPACT: a big yellow-green hit star, sparks along the punch, one shock ring, dust,
--          a light; hit-stop on the bodies; the boom, a shake, the punch-in; the enemy knocked 2.5
--          studs and launched 0.8; the line gone
--   +0.18  the follow-through, the fist out, held to +0.45; the glow sheds away as sparks (+0.35)
--   +0.75  the rod shouldered; idle by +1.05
-- When the real window before the cast is shorter (Cinematic run.k < 1, at least the tier's 0.6),
-- the anticipation is laid out again for it (planOf): the stillness gives first, then the set, then
-- the coil, and only past that does everything but the snaps shrink evenly. The whip, the load, the
-- yank and everything after the hit never shrink.
-- Readable from the match camera (ViewScale: 1 at close cameras, up to 1.8 there): the trails, the
-- line, the glow, the hit star, the sparks, the ring and the dust grow with it.
-- Layers (tier 4, within its 34; peak ~12 in the set, ~10 at the impact, estimated): the line (1),
-- the fist's glow (core + halo), ~6 motes in flight, at the impact one shock ring, a hit star,
-- sparks and dust (particles), a light (not when reduced); the rod and fist trails (BladeTrail); the
-- callout's ring. Camera: a push on the fist through the set and a pull at the impact (tier 4).
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

-- The anticipation's segments in real seconds at full length, in order up to the hit (1.02 s in
-- all), and how far each may shrink when the window is short (`least`), in the order they give way
-- (the stillness first, then the set, then the coil).
local SEGMENTS = {
	coil = 0.28, -- windup start -> the rod overhead
	whip = 0.06, -- the whip's snap: the line flies out
	set = 0.35, -- hooked, the fist drawn back, the glow growing
	still = 0.15, -- stillness
	load = 0.12, -- the load dip
	snap = 0.06, -- the yank's snap, ending on the hit
}
local LEAST = { still = 0.06, set = 0.12, coil = 0.14 }
local SHRINK_ORDER = { "still", "set", "coil" }
local ORDER = { "coil", "whip", "set", "still", "load", "snap" }
local SNAPS = { whip = true, load = true, snap = true } -- never shrink
local FULL = 0
for _, name in ORDER do
	FULL += SEGMENTS[name]
end

-- After the hit (design seconds = real seconds: never compressed).
local AFTER = {
	finisher = 0, -- the yank
	punch = 0.06, -- the punch's snap starts
	arrive = 0.12, -- the pulled enemy arrives: the punch lands
	follow = 0.18, -- the follow-through pose reached
	trailOff = 0.2, -- the trails stop drawing
	shed = 0.35, -- the glow sheds away as sparks
	followEnd = 0.45, -- the follow-through held until here
	shoulder = 0.75, -- the rod shouldered
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
		windup = design(real.coil),
		whip = design(real.whip),
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
local GLOW = rgb(190, 235, 60) -- yellow-green
local GLOW_DEEP = rgb(90, 170, 30)
local LINE = rgb(235, 235, 225)
local CALLOUT = GLOW
local ROD_TRAIL = ColorSequence.new(WHITE, rgb(200, 200, 190))
local FIST_TRAIL = ColorSequence.new({
	ColorSequenceKeypoint.new(0, rgb(240, 255, 170)),
	ColorSequenceKeypoint.new(0.5, GLOW),
	ColorSequenceKeypoint.new(1, GLOW_DEEP),
})
local SPARKS = ColorSequence.new(WHITE, GLOW)
local ROD = { length = 0.9, tilt = math.rad(40), grip = 0.045 } -- LookKit `rod`, in figure heights
local STEP = 0.3 -- studs (normal size) he steps into the punch (`lunge`)
-- The impact's light: a short, tight yellow-green flash at the enemy's chest.
local FINISH_LIGHT = { brightness = 1.8, range = 1.5, seconds = 0.22 } -- range in unit heights
local UNIT_HEIGHT = RenderConfig.unitSize.Y

-- The poses (PoseAnimator channels), about twice realistic: big, readable anime poses. Every body
-- pose names every body channel, so a held pose holds the whole body still. `lunge` (the step into
-- the punch) runs on keys of its own.
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

-- The rod overhead, coiled back to cast.
local COCK = pose({
	crouch = 0.12,
	lean = -10,
	twist = 12,
	rightArm = 168,
	rightArmOut = 10,
	leftArm = 20,
	leftArmOut = 18,
	leftLeg = 16,
	rightLeg = -14,
	headPitch = -6,
})
-- The whip: the rod thrown forward, leaning into the cast.
local WHIP = pose({
	crouch = 0.18,
	lean = 12,
	twist = -8,
	rightArm = 70,
	leftArm = 10,
	leftArmOut = 20,
	leftLeg = 26,
	rightLeg = -22,
	headPitch = 4,
})
-- Hooked: the rod held forward, the free fist drawn far back, the left shoulder turned away.
local HOOKED = pose({
	crouch = 0.32,
	lean = -4,
	twist = 30,
	rightArm = 75,
	rightArmOut = 5,
	leftArm = -55,
	leftArmOut = 15,
	leftLeg = 30,
	rightLeg = -28,
	headYaw = -10,
})
local LOAD = with(HOOKED, { crouch = 0.4, twist = 36, leftArm = -65 })
-- The yank: the rod ripped back overhead, the fist still loaded.
local YANK = with(LOAD, { rightArm = 135, rightArmOut = 20, lean = -10, twist = 22 })
-- The punch: the fist thrown straight out, the body turning through it.
local PUNCH = pose({
	crouch = 0.26,
	lean = 16,
	twist = -36,
	rightArm = 120,
	rightArmOut = 20,
	leftArm = 98,
	leftArmOut = 0,
	leftLeg = 42,
	rightLeg = -38,
	headYaw = 10,
	headPitch = 4,
})
local FOLLOW = with(PUNCH, { lean = 13, twist = -32 })
-- Shouldered: the rod back over the shoulder, at ease.
local SHOULDER = pose({ lean = -4, rightArm = 150, rightArmOut = -30, leftArm = 8, headPitch = -4 })

-- The keys for a plan (planOf) and a step of `step` studs (normal size) into the punch.
local function keyframes(T: Plan, step: number): { PoseAnimator.Keyframe }
	return {
		{ at = T.windup, pose = with(pose({}), { lunge = 0 }) },
		{ at = T.whip, ease = "quadOut", pose = COCK },
		-- The whip (a snap), then hooked, held shivering, then in stillness.
		{ at = T.set, ease = "snap", pose = WHIP },
		{ at = T.set + 0.1, ease = "quadOut", hold = math.max(0, T.still - T.set - 0.1), shiver = 1.4, pose = HOOKED },
		{ at = T.still, ease = "hold", hold = T.load - T.still, pose = HOOKED },
		{ at = T.snap, ease = "quadOut", pose = LOAD },
		-- The yank (a snap) on the hit, then the punch (a snap) landing as the enemy arrives.
		{ at = T.finisher, ease = "snap", hold = T.punch - T.finisher, pose = YANK },
		{ at = T.arrive, ease = "snap", pose = PUNCH },
		{ at = T.punch, pose = { lunge = 0 } },
		{ at = T.arrive, ease = "snap", pose = { lunge = step } },
		{ at = T.follow, ease = "quadOut", hold = T.followEnd - T.follow, pose = FOLLOW },
		-- The rod shouldered, stepping back to where he stands; then idle.
		{ at = T.shoulder, ease = "inOut", hold = 0.12, pose = SHOULDER },
		{ at = T.shoulder, ease = "inOut", pose = { lunge = 0 } },
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

-- Tracks by plan (the step scaled to his size), built once each.
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

-- The rod's tip now (LookKit `rod`: along the hand's -Z, tilted 40 degrees), else ahead of his hand.
local function rodTip(run): Vector3
	local figure = run.view.figure
	local anchor = figure and figure.anchors and figure.anchors.rightHand
	if anchor and not figure.isModel then
		local h = run.view.part.Size.Y
		return (anchor * CFrame.new(0, h * ROD.grip, 0) * CFrame.Angles(ROD.tilt, 0, 0) * CFrame.new(
			0,
			0,
			-h * (ROD.length - 0.06)
		)).Position
	end
	return run:hand("right") + run:forward() * 2.2 + Vector3.new(0, 1.2, 0)
end

-- The trails: along the rod (its whip and yank) and on the bare left fist (the punch), made at the
-- windup; they scale with the camera distance. Gone once they have faded.
local function attachTrails(run)
	if run.memo.rod then
		return
	end
	local rod = BladeTrail.attach(run.view, { hand = "right", from = 0.5, to = 0.82, viewScale = true })
	rod:add("rod", { colors = ROD_TRAIL, lifetime = 0.2 })
	local fist = BladeTrail.attach(run.view, { hand = "left", from = 0, to = 0.12, viewScale = true })
	fist:add("fist", { colors = FIST_TRAIL, lifetime = 0.18 })
	run.memo.rod, run.memo.fist = rod, fist
	run:at(planFor(run).rest, function()
		rod:destroy()
		fist:destroy()
		run.memo.rod, run.memo.fist = nil, nil
	end)
end

local function setTrail(run, key: string, on: boolean)
	local trail = run.memo[key]
	if trail then
		if on then
			trail:enable(key)
		else
			trail:disable(key)
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
			local target = run:target()
			run:face(target)
			attachTrails(run)
			UltimateCallout.mark(run.view, CALLOUT, run:span(plan.windup, plan.finisher - plan.windup))
			-- The whip: the rod's trail on, the line flying out and holding taut until the punch lands.
			run:at(plan.whip - 0.01, function()
				setTrail(run, "rod", true)
				Sfx.play("whooshLight", { pitch = 1.1 })
			end)
			run:at(plan.set + 0.05, function()
				setTrail(run, "rod", false)
			end)
			if target then
				local view = VfxRecipe.viewScale(target.part.Position)
				Kit.live(run, plan.whip, AFTER.arrive, "Block", LINE, function(part, _u)
					local tip = rodTip(run)
					local far = target.part.Position
					local out =
						Kit.easeOut((run:designTime() - plan.whip) / math.max(plan.set - plan.whip + 0.08, 1e-3))
					local reach = tip:Lerp(far, math.clamp(out, 0.02, 1))
					local length = math.max((reach - tip).Magnitude, 0.05)
					part.Size = Vector3.new(0.05 * view, 0.05 * view, length)
					part.CFrame = CFrame.lookAt((tip + reach) / 2, reach)
					part.Transparency = 0.05
				end)
				run:at(plan.set + 0.08, function()
					if target.part.Parent then
						VfxRecipe.sparks(target.part.Position, 0.35 * view, 6, ColorSequence.new(WHITE), nil, view)
					end
				end)
			end
			-- The glow gathering in the drawn-back fist, motes drawn in, the camera leaning in on it.
			run:at(plan.set, function()
				local view = VfxRecipe.viewScale(run:hand("left"))
				Kit.orb(run, plan.set, AFTER.shed, GLOW, function()
					return run:hand("left")
				end, function(u)
					return (0.25 + 0.75 * Kit.easeIn(math.min(1, u * 1.3))) * s * view
				end)
				Kit.converge(run, plan.set, plan.still, function()
					return run:hand("left")
				end, GLOW, 2 * s * view, if run.reduced then 3 else 6)
				run:camera(
					plan.set,
					plan.finisher,
					{ key = "push", push = 2.2, focus = run:hand("left"), rise = 0.3, fall = 0.05 }
				)
				Sfx.play("energyCharge", { pitch = 1.1, volume = 0.7 })
			end)
			-- The yank: the rod's trail again.
			run:at(plan.snap - 0.01, function()
				setTrail(run, "rod", true)
			end)
			run:at(AFTER.punch - 0.01, function()
				setTrail(run, "fist", true)
			end)
			run:at(AFTER.trailOff, function()
				setTrail(run, "rod", false)
				setTrail(run, "fist", false)
			end)
			-- The impact waits for the real hit; should it never come, it still plays.
			run:at(plan.finisher + 0.05, function()
				if not run.memo.finished then
					run.memo.finished = true
					finisher(run, target)
				end
			end)
		end,
	},
}

-- The cast itself: no generic burst at his hands (the yank and the punch are the release).
function def.release(_run): boolean
	return true
end

-- The yank on the real hit, then the impact as the pulled enemy arrives (AFTER.arrive): a big
-- yellow-green hit star, sparks along the punch, one shock ring, dust, a light; hit-stop on the
-- bodies (0.07 s); the boom, the shake, the punch-in and the camera pulling back; knocked 2.5 studs
-- and launched 0.8. Then the glow sheds away as sparks.
finisher = function(run, target: any?)
	local s = run:scale()
	Sfx.play("whooshLight", { pitch = 0.85 })
	run:at(AFTER.arrive, function()
		local hit = if target and target.part.Parent
			then target.part.Position
			else run:chest() + run:forward() * UNIT_HEIGHT
		local view = VfxRecipe.viewScale(hit)
		local floor = Vector3.new(hit.X, run:ground().Y, hit.Z)
		VfxRecipe.kitHitStar(hit, UNIT_HEIGHT * 0.95 * view, GLOW, view)
		VfxRecipe.sparks(hit, 0.7 * view, 14, SPARKS, run:forward(), view)
		VfxRecipe.meshRing(floor, UNIT_HEIGHT * 0.7 * s * view, GLOW, 0.35, 0.3)
		VfxRecipe.kitDust(floor, UNIT_HEIGHT * 0.5 * s * view, 2, 0.6)
		if not run.reduced then
			ImpactEffects.light(
				hit,
				GLOW,
				FINISH_LIGHT.brightness,
				FINISH_LIGHT.range * UNIT_HEIGHT,
				FINISH_LIGHT.seconds
			)
		end
		local held = { run.view }
		if target then
			table.insert(held, target)
		end
		HitFeel.hitStop(held, 0.07, { caster = run.view })
		if target then
			HitFeel.react(target, run:chest(), { final = true })
		end
		HitFeel.cameraShake(0.25, 0.3)
		HitFeel.punchIn(1)
		run:camera(AFTER.arrive, 0.6, { key = "pull", push = -1.6, focus = run:chest(), rise = 0.04, fall = 0.4 })
		Sfx.play("impactHeavy")
	end)
	run:at(AFTER.shed, function()
		local at = run:hand("left")
		VfxRecipe.sparks(at, 0.4 * VfxRecipe.viewScale(at), 10, SPARKS, nil, VfxRecipe.viewScale(at))
	end)
end

function def.event(run, event): boolean
	local kind = event.kind
	if kind == "Pull" then
		return true -- the yank is the pull
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
