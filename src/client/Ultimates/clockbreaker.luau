-- clockbreaker (Tier 3): the barrage, from a spirit behind a calm user. The real cast hits his
-- target four times (Damage at 0, +0.25, +0.5, +0.75) and then once hard with a stun (Damage and
-- Stun at +1.0; a 1-second cast time). Everything before 0 is anticipation. He never moves: hands in
-- his coat pockets, brim down; the spirit does everything.
-- Designed timeline (real seconds at full length; SEGMENTS):
--   -0.62  his hands go into his pockets, the brim down; the callout (an outline on him, a ground
--          ring); a tall see-through purple spirit (a torso, a head, two arms; a soft glow behind
--          it) rises in behind his shoulder
--   -0.42  set: the spirit's fists cocked back, shivering, until -0.26
--   -0.26  stillness, until -0.18
--   -0.18  a 0.12 s load: the spirit draws back further, he settles lower
--   -0.06  the spirit's 0.06 s lunge past his shoulder, ending on the cast
--    0     THE BARRAGE, on the real cast: the spirit's arms pump, fist streaks pour into the target;
--          a small purple hit star and a flinch on each real hit
--   +1.00  THE LAST PUNCH on the real last hit: the spirit's right fist thrown long; a purple hit
--          star, sparks, a core behind the target, one shock ring, a short light; hit-stop on the
--          bodies, a shake, the punch-in; he lifts his chin (the glare under the brim)
--   +1.12  the follow-through, held to +1.35; the spirit sinks back and fades by +1.65; he is idle
--          by +1.85, hands still in his pockets
-- When the real window before the cast is shorter (Cinematic run.k < 1, at least the tier's 0.6),
-- the anticipation is laid out again for it (planOf): the stillness gives first, then the set, then
-- the summon, and only past that does everything but the load and the snap shrink evenly. The load,
-- the snap and everything after the cast never shrink.
-- Readable from the match camera (ViewScale: 1 at close cameras, up to 1.8 there): the hit stars,
-- the sparks, the fist streaks, the core and the ring grow with it; the spirit is body-sized.
-- Layers (tier 3, within its 26; peak ~13 at the last punch, estimated): the spirit (5: torso, head,
-- two arms, the glow), fist streaks (particles, ~2 alive), each small hit's star and sparks (~2),
-- at the last punch a hit star, sparks, a core, one shock ring and a light (not when reduced); the
-- callout's ring. Poses: PoseAnimator; hit feel: HitFeel; callout: UltimateCallout; sounds: Sfx.

local HitFeel = require(script.Parent.Parent.HitFeel)
local ImpactEffects = require(script.Parent.Parent.ImpactEffects)
local PoseAnimator = require(script.Parent.Parent.PoseAnimator)
local Sfx = require(script.Parent.Parent.Sfx)
local UltimateCallout = require(script.Parent.Parent.UltimateCallout)
local UltimateKit = require(script.Parent.Parent.UltimateKit)
local VfxRecipe = require(script.Parent.Parent.VfxRecipe)

local Kit = UltimateKit
local rgb = Color3.fromRGB

-- The anticipation's segments in real seconds at full length, in order up to the cast (0.62 s in
-- all), and how far each may shrink when the window is short (`least`), in the order they give way
-- (the stillness first, then the set, then the summon).
local SEGMENTS = {
	summon = 0.2, -- windup start -> the spirit in, hands in pockets
	set = 0.16, -- the spirit's fists cocked, shivering
	still = 0.08, -- stillness
	load = 0.12, -- the spirit draws back
	snap = 0.06, -- the spirit's lunge, ending on the cast
}
local LEAST = { still = 0.03, set = 0.08, summon = 0.1 }
local SHRINK_ORDER = { "still", "set", "summon" }
local ORDER = { "summon", "set", "still", "load", "snap" }
local SNAPS = { load = true, snap = true } -- never shrink
local FULL = 0
for _, name in ORDER do
	FULL += SEGMENTS[name]
end

-- After the cast (design seconds = real seconds: never compressed).
local AFTER = {
	barrage = 0, -- the barrage (the real first hit)
	finisher = 1.0, -- the last punch (the real last hit)
	follow = 1.12, -- the follow-through pose reached
	followEnd = 1.35, -- the follow-through held until here
	fadeEnd = 1.65, -- the spirit gone
	recover = 1.6, -- recovered
	rest = 1.85, -- back to idle
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
	-- Real times, backward from the cast.
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
		windup = design(real.summon),
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

local PURPLE = rgb(150, 90, 225)
local SPIRIT = rgb(185, 140, 245)
local GOLD = rgb(235, 195, 80)
local CALLOUT = PURPLE
local SPARKS = VfxRecipe.colors({ { 0, Color3.new(1, 1, 1) }, { 0.3, SPIRIT }, { 1, PURPLE } })
local STREAK = VfxRecipe.colors({ { 0, Color3.new(1, 1, 1):Lerp(SPIRIT, 0.3) }, { 1, PURPLE } })
local UNIT_HEIGHT = VfxRecipe.UNIT_HEIGHT
local FINISH_LIGHT = { brightness = 1.8, range = 1.3, seconds = 0.25 } -- range in unit heights
local SPIRIT_SEEN = 0.45 -- the spirit's transparency while fully in
local STREAK_EVERY = 0.08 -- design seconds between fist streaks (twice that when reduced)

-- The poses (PoseAnimator channels): every channel named, so a held pose holds still. His hands stay
-- in his pockets (arms a little back and out); only his weight, his lean and his head move.
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

local function with(base: { [string]: number }, values: { [string]: number }): { [string]: number }
	local out = table.clone(base)
	for channel, value in values do
		out[channel] = value
	end
	return out
end

local POCKETS = pose({
	crouch = 0.04,
	lean = -4,
	rightArm = -14,
	rightArmOut = 12,
	leftArm = -14,
	leftArmOut = 12,
	headPitch = 16,
})
local SETTLE = with(POCKETS, { crouch = 0.1, lean = -6, twist = -8, headPitch = 22 })
local BARRAGE = with(POCKETS, { crouch = 0.06, lean = 3, twist = -4, headPitch = 18 })
local GLARE = with(POCKETS, { crouch = 0.08, lean = 6, twist = -10, headPitch = -6 })
local FOLLOW = with(POCKETS, { crouch = 0.06, lean = 4, twist = -8, headPitch = 0 })
local RECOVER = with(POCKETS, { crouch = 0.02, lean = -2, headPitch = 10 })

-- The keys for a plan (planOf).
local function keyframes(T: Plan): { PoseAnimator.Keyframe }
	return {
		{ at = T.windup, pose = pose({}) },
		-- Hands into the pockets, the brim down; then settled, shivering a little, then still.
		{ at = T.set, ease = "quadOut", pose = POCKETS },
		{
			at = T.set + 0.06,
			ease = "quadOut",
			hold = math.max(0, T.still - T.set - 0.06),
			shiver = 0.6,
			pose = with(POCKETS, { crouch = 0.07 }),
		},
		{ at = T.still, ease = "hold", hold = T.load - T.still, pose = with(POCKETS, { crouch = 0.07 }) },
		{ at = T.snap, ease = "quadOut", pose = SETTLE },
		-- The barrage (a snap) on the cast, held; the glare (a snap) on the last punch, then held.
		{ at = T.barrage, ease = "snap", hold = T.finisher - T.barrage - 0.06, pose = BARRAGE },
		{ at = T.finisher, ease = "snap", pose = GLARE },
		{ at = T.follow, ease = "quadOut", hold = T.followEnd - T.follow, pose = FOLLOW },
		-- Recovered; then idle (the hands come out of the pockets only as he goes idle).
		{ at = T.recover, ease = "inOut", hold = 0.08, pose = RECOVER },
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

-- The spirit at design time `t`: how far it has lunged (0 behind his shoulder, 1 out in front of
-- him; below 0 drawn back, above 1 thrown into the last punch), and how much of it is in (0..1).
local function spiritLunge(T: Plan, t: number): number
	if t < T.load then
		return 0
	elseif t < T.snap then
		return -0.2 * Kit.smooth((t - T.load) / (T.snap - T.load))
	elseif t < T.barrage then
		return -0.2 + 1.2 * Kit.smooth((t - T.snap) / (T.barrage - T.snap))
	elseif t < T.finisher then
		return 1
	elseif t < T.followEnd then
		return 1 + 0.15 * math.min(1, (t - T.finisher) / 0.06)
	end
	return 1.15 * (1 - Kit.smooth((t - T.followEnd) / (T.fadeEnd - T.followEnd)))
end

local function spiritIn(T: Plan, t: number): number
	return Kit.smooth((t - T.windup) / (T.set - T.windup))
		* (1 - Kit.smooth((t - T.followEnd) / (T.fadeEnd - T.followEnd)))
end

-- How far one of the spirit's arms reaches at design time `t` (`side` 1 right, -1 left): 0 hanging,
-- 1 punched straight out, below 0 cocked back.
local function spiritReach(T: Plan, t: number, side: number): number
	if t < T.set then
		return 0
	elseif t < T.load then
		return -0.4
	elseif t < T.snap then
		return -0.55
	elseif t < T.barrage then
		return -0.55 + 1.35 * Kit.smooth((t - T.snap) / (T.barrage - T.snap))
	elseif t < T.finisher - 0.06 then
		-- The pumping fists, alternating.
		return 0.25 + 0.95 * math.abs(math.sin(math.pi * 6 * t + (if side > 0 then 0 else math.pi / 2)))
	elseif t < T.followEnd then
		return if side > 0 then 1.5 else -0.3
	end
	local back = Kit.smooth((t - T.followEnd) / (T.fadeEnd - T.followEnd))
	return (if side > 0 then 1.5 else -0.3) * (1 - back)
end

type Body = {
	center: CFrame, -- the spirit's torso
	size: number, -- its height
	fists: { [number]: Vector3 }, -- by side
	shoulders: { [number]: Vector3 },
}

-- Where the spirit is at design time `t`: behind his right shoulder, lunged out in front of him.
local function spiritBody(run, T: Plan, t: number): Body
	local forward = run:forward()
	local right = forward:Cross(Vector3.yAxis)
	local size = run.view.part.Size.Y * 1.25
	local ground = run:ground()
	local back = ground - forward * 1.0 + right * 0.8
	local front = ground + forward * 1.6 + right * 0.5
	local lunge = spiritLunge(T, t)
	local shiver = if t > T.set and t < T.still then math.sin(t * 90) * 0.04 else 0
	local risen = Kit.smooth((t - T.windup) / (T.set - T.windup))
	local at = back + (front - back) * lunge + Vector3.new(shiver, size * (0.55 + 0.25 * risen), 0)
	local center = CFrame.lookAt(at, at + forward) * CFrame.Angles(-math.rad(12) * math.clamp(lunge, 0, 1), 0, 0)
	local fists, shoulders = {}, {}
	local arm = size * 0.5
	for _, side in { 1, -1 } do
		local shoulder = (center * CFrame.new(side * size * 0.3, size * 0.2, 0)).Position
		local reach = spiritReach(T, t, side)
		local hang = 1 - math.clamp(reach, 0, 1)
		shoulders[side] = shoulder
		fists[side] = shoulder + center.LookVector * arm * reach - Vector3.yAxis * arm * 0.6 * hang
	end
	return { center = center, size = size, fists = fists, shoulders = shoulders }
end

-- The spirit: a torso, a head and two arms, see-through purple, with a soft glow behind it; drawn
-- from the windup until it has faded. Each part reads the body for the moment it draws.
local function buildSpirit(run, T: Plan)
	local from, to = T.windup, T.fadeEnd
	local function now(): (Body, number)
		local t = run:designTime()
		return spiritBody(run, T, t), 1 - (1 - SPIRIT_SEEN) * spiritIn(T, t)
	end
	local material = Enum.Material.SmoothPlastic
	Kit.live(run, from, to, "Block", SPIRIT, function(part, _u)
		local body, seen = now()
		part.Size = Vector3.new(body.size * 0.5, body.size * 0.48, body.size * 0.26)
		part.CFrame = body.center
		part.Transparency = seen
	end, material)
	Kit.live(run, from, to, "Ball", SPIRIT, function(part, _u)
		local body, seen = now()
		part.Size = Vector3.one * body.size * 0.24
		part.CFrame = body.center * CFrame.new(0, body.size * 0.38, 0)
		part.Transparency = seen
	end, material)
	for _, side in { 1, -1 } do
		Kit.live(run, from, to, "Block", SPIRIT, function(part, _u)
			local body, seen = now()
			local shoulder, fist = body.shoulders[side], body.fists[side]
			local length = math.max((fist - shoulder).Magnitude, 0.1)
			part.Size = Vector3.new(body.size * 0.13, body.size * 0.13, length + body.size * 0.08)
			part.CFrame = CFrame.lookAt((shoulder + fist) / 2, fist)
			part.Transparency = seen
		end, material)
	end
	-- The glow: a soft purple ball behind the spirit's torso (it never covers him: the spirit stands
	-- off his shoulder).
	Kit.live(run, from, to, "Ball", PURPLE, function(part, _u)
		local body, seen = now()
		part.Size = Vector3.one * body.size * 0.85
		part.CFrame = body.center * CFrame.new(0, 0, body.size * 0.2)
		part.Transparency = 0.8 + 0.2 * (seen - SPIRIT_SEEN) / (1 - SPIRIT_SEEN)
	end)
end

-- One fist afterimage: a short purple streak flying from `from` into `to`.
local function fistStreak(from: Vector3, to: Vector3)
	local along = to - from
	if along.Magnitude < 1e-3 then
		return
	end
	local view = VfxRecipe.viewScale(to)
	ImpactEffects.emit(from, {
		usage = "sparks",
		count = 2,
		color = STREAK,
		size = VfxRecipe.curve({ { 0, 0.5 * view }, { 1, 0.2 * view } }),
		transparency = VfxRecipe.curve({ { 0, 0.1 }, { 0.7, 0.3 }, { 1, 1 } }),
		lifetime = { 0.1, 0.12 },
		speed = { along.Magnitude / 0.11, along.Magnitude / 0.1 },
		spread = 6,
		direction = along.Unit,
		lightEmission = 1,
		brightness = 2.5,
		stretch = true,
	})
end

local finisher: (any, any?) -> () -- below

def.beats = {
	{
		at = planOf(1).windup, -- every plan starts its windup at the same design time (-FULL)
		run = function(run)
			local plan = planFor(run)
			local target = run:target()
			run:face(target)
			UltimateCallout.mark(run.view, CALLOUT, run:span(plan.windup, plan.finisher - plan.windup))
			buildSpirit(run, plan)
			Sfx.play("magicChime", { pitch = 0.6, volume = 0.5 })
			-- Count the real hits, so the last one is known when it comes.
			run.memo.hits, run.memo.total = 0, 0
			for _, event in run.cast do
				if event.kind == "Damage" and not event.dot then
					run.memo.total += 1
				end
			end
			-- The barrage: fist streaks from the spirit's pumping fists into the target.
			run:at(plan.barrage, function()
				Sfx.play("punchRush")
			end)
			local every = if run.reduced then STREAK_EVERY * 2 else STREAK_EVERY
			local count = math.floor((plan.finisher - plan.barrage - 0.06) / every)
			for i = 0, count do
				local t = plan.barrage + i * every
				run:at(t, function()
					local view = run:target()
					if not view or not view.part.Parent then
						return
					end
					local body = spiritBody(run, plan, t)
					local fist = body.fists[if i % 2 == 0 then 1 else -1]
					local to = view.part.Position
						+ Vector3.new((math.random() - 0.5) * 1.2, (math.random() - 0.5) * 1.2, 0)
					fistStreak(fist, to)
				end)
			end
			-- The last punch waits for the real last hit; should it never come, it still plays.
			run:at(plan.finisher + 0.05, function()
				if not run.memo.finished then
					run.memo.finished = true
					finisher(run, run:target())
				end
			end)
		end,
	},
}

-- The cast itself: no generic burst (the barrage is the release).
function def.release(_run): boolean
	return true
end

-- One barrage hit: a small purple hit star and sparks, a flinch, a tick of shake.
local function smallHit(run, view: any)
	local at = view.part.Position
	local scale = VfxRecipe.viewScale(at)
	VfxRecipe.kitHitStar(at, UNIT_HEIGHT * 0.45 * scale, SPIRIT, scale)
	VfxRecipe.sparks(at, 0.35 * scale, 5, SPARKS, run:forward(), scale)
	HitFeel.react(view, run:chest(), { knock = 0.6, tilt = 8 })
	HitFeel.cameraShake(0.04, 0.08)
	Sfx.play("impactLight", { pitch = 1 + (math.random() - 0.5) * 0.2, volume = 0.6 })
end

-- The last punch (AFTER.finisher): a purple hit star, sparks, a core behind the target (as the
-- camera sees it), one shock ring, a short light; hit-stop on the bodies (0.07 s); the shake, the
-- punch-in; the target thrown.
finisher = function(run, target: any?)
	local s = run:scale()
	local hit = if target and target.part.Parent
		then target.part.Position
		else run:chest() + run:forward() * UNIT_HEIGHT
	local view = VfxRecipe.viewScale(hit)
	local floor = Vector3.new(hit.X, run:ground().Y, hit.Z)
	VfxRecipe.kitHitStar(hit, UNIT_HEIGHT * 0.95 * view, SPIRIT, view)
	VfxRecipe.sparks(hit, 0.7 * view, 16, SPARKS, run:forward(), view)
	local coreAt = hit
	local camera = workspace.CurrentCamera
	if camera then
		local away = hit - camera.CFrame.Position
		away = Vector3.new(away.X, 0, away.Z)
		if away.Magnitude > 1e-3 then
			coreAt += away.Unit * 0.7
		end
	end
	ImpactEffects.ball(coreAt, PURPLE:Lerp(Color3.new(1, 1, 1), 0.3), UNIT_HEIGHT * 0.8 * view, 0.16)
	VfxRecipe.meshRing(floor, UNIT_HEIGHT * 0.6 * s * view, GOLD:Lerp(SPIRIT, 0.5), 0.3, 0.3)
	if not run.reduced then
		ImpactEffects.light(
			hit,
			PURPLE,
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
	HitFeel.cameraShake(0.18, 0.25)
	HitFeel.punchIn(1)
	Sfx.play("impactHeavy")
	Sfx.play("whooshLight", { pitch = 0.8, volume = 0.6 })
end

function def.event(run, event): boolean
	if event.kind ~= "Damage" or not event.target or event.dot then
		return false
	end
	local view = run.context.views[event.target]
	run.memo.hits = (run.memo.hits or 0) + 1
	if run.memo.hits >= (run.memo.total or 5) then
		if not run.memo.finished then
			run.memo.finished = true
			finisher(run, view)
		end
	elseif view then
		smallHit(run, view)
	end
	return true
end

return def
