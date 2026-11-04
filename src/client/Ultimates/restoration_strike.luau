-- restoration_strike (Tier 4): the fixer. The real cast shields him (Shield), heals his two
-- lowest-health other allies (Heal on each) and hits his target (Damage), all at the Cast event
-- (t = 0). Everything before 0 is anticipation; the spirit's three jabs start on the real hit and the
-- third, the heavy one, lands at +0.16 (the finisher).
-- Designed timeline (real seconds at full length; SEGMENTS):
--   -0.88  his palm raised out to the side; a see-through pink spirit (a torso, a head with a tall
--          crest, two arms) rises in off his right shoulder; the callout (a pink outline on him, a
--          ground ring)
--   -0.63  set: diamond shards swirl in around him, closing, his hand shivering, until -0.33
--   -0.33  stillness, until -0.18
--   -0.18  a 0.12 s load: he winds, the spirit cocks its fist
--   -0.06  the 0.06 s snap: he points at the target, the spirit lunges, ending on the cast
--    0     on the real cast: the shards lock into his real shield (a white glint at his chest; the
--          shield bubble is the real one); a pink beam from the spirit's hand to each really healed
--          ally, whose cracks close up with sparkles; the spirit's jabs into the target: +0 and +0.08
--          small (a pink hit star each)
--   +0.16  THE HEAVY JAB: a big pink hit star, sparks, one shock ring, a short light; hit-stop on the
--          bodies, a shake, the punch-in
--   +0.28  his proud pose, held to +0.5; the spirit sinks back and fades by +0.75; recovered by +0.7,
--          idle by +0.95
-- When the real window before the cast is shorter (Cinematic run.k < 1, at least the tier's 0.6),
-- the anticipation is laid out again for it (planOf): the stillness gives first, then the set, then
-- the summon, and only past that does everything but the load and the snap shrink evenly. The load,
-- the snap and everything after the cast never shrink.
-- Readable from the match camera (ViewScale: 1 at close cameras, up to 1.8 there): the shards, the
-- beams, the cracks, the sparkles, the hit stars, the sparks and the ring grow with it; the spirit is
-- body-sized.
-- Layers (tier 4, within its 34; peak ~17 at the heavy jab, estimated): the spirit (5: torso, head, crest,
-- two arms), 5 shards (3 when reduced) until the cast; at the cast 2 beams, a crack per healed ally,
-- sparkles (particles), the jabs' hit stars, at the heavy jab its sparks, one shock ring
-- and a light (not when reduced); the callout's ring. Poses: PoseAnimator; hit feel: HitFeel; callout:
-- UltimateCallout; sounds: Sfx.

local HitFeel = require(script.Parent.Parent.HitFeel)
local ImpactEffects = require(script.Parent.Parent.ImpactEffects)
local PoseAnimator = require(script.Parent.Parent.PoseAnimator)
local Sfx = require(script.Parent.Parent.Sfx)
local UltimateCallout = require(script.Parent.Parent.UltimateCallout)
local UltimateKit = require(script.Parent.Parent.UltimateKit)
local VfxRecipe = require(script.Parent.Parent.VfxRecipe)

local Kit = UltimateKit
local rgb = Color3.fromRGB

-- The anticipation's segments in real seconds at full length, in order up to the cast (0.88 s in
-- all), and how far each may shrink when the window is short (`least`), in the order they give way
-- (the stillness first, then the set, then the summon).
local SEGMENTS = {
	summon = 0.25, -- windup start -> the palm raised, the spirit in
	set = 0.3, -- the shards swirling in, shivering
	still = 0.15, -- stillness
	load = 0.12, -- the wind, the spirit's fist cocked
	snap = 0.06, -- the point and the lunge, ending on the cast
}
local LEAST = { still = 0.05, set = 0.12, summon = 0.12 }
local SHRINK_ORDER = { "still", "set", "summon" }
local ORDER = { "summon", "set", "still", "load", "snap" }
local SNAPS = { load = true, snap = true } -- never shrink
local FULL = 0
for _, name in ORDER do
	FULL += SEGMENTS[name]
end

-- After the cast (design seconds = real seconds: never compressed).
local AFTER = {
	cast = 0, -- the shield, the heals, the first jab (the real hit)
	finisher = 0.16, -- the heavy jab
	follow = 0.28, -- the proud pose reached
	followEnd = 0.5, -- held until here
	recover = 0.7, -- recovered
	fadeEnd = 0.75, -- the spirit gone
	rest = 0.95, -- back to idle
}
local JABS = { 0, 0.08 } -- the small jabs before the heavy one

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

local PINK = rgb(240, 120, 185)
local SPIRIT = rgb(250, 170, 215)
local DIAMOND = rgb(235, 240, 255)
local CRACK = rgb(70, 40, 60)
local CALLOUT = PINK
local SPARKS = VfxRecipe.colors({ { 0, Color3.new(1, 1, 1) }, { 0.35, SPIRIT }, { 1, PINK } })
local SPARKLE = VfxRecipe.colors({ { 0, Color3.new(1, 1, 1) }, { 1, SPIRIT } })
local UNIT_HEIGHT = VfxRecipe.UNIT_HEIGHT
local FINISH_LIGHT = { brightness = 1.8, range = 1.3, seconds = 0.25 } -- range in unit heights
local SPIRIT_SEEN = 0.45 -- the spirit's transparency while fully in

-- The poses (PoseAnimator channels): every channel named, so a held pose holds still. About twice a
-- realistic stance. The raised palm spreads with a small forward raise and a big Out (Figure: Out
-- turns about the front axis after the forward raise).
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

local PALM = pose({
	crouch = 0.04,
	lean = -8,
	twist = 8,
	rightArm = 25,
	rightArmOut = 80,
	leftArm = 15,
	leftArmOut = 30,
	headPitch = -6,
})
local WIND = pose({
	crouch = 0.16,
	lean = 2,
	twist = 30,
	rightArm = 35,
	rightArmOut = 55,
	leftArm = 20,
	leftArmOut = 25,
	headPitch = 4,
})
local POINT = pose({
	crouch = 0.08,
	lean = 16,
	twist = -30,
	rightArm = 100,
	rightArmOut = 6,
	leftArm = -15,
	leftArmOut = 20,
	headPitch = 4,
})
local HEAVY = with(POINT, { lean = 20, twist = -38, rightArm = 108 })
local PROUD = pose({
	crouch = 0.02,
	lean = -10,
	twist = -6,
	rightArm = -10,
	rightArmOut = 18,
	leftArm = -10,
	leftArmOut = 18,
	headPitch = -12,
})
local RECOVER = pose({ crouch = 0.02, lean = -3, headPitch = -4 })

-- The keys for a plan (planOf).
local function keyframes(T: Plan): { PoseAnimator.Keyframe }
	return {
		{ at = T.windup, pose = pose({}) },
		-- The palm raised, held shivering as the shards close in, then in stillness.
		{ at = T.set, ease = "quadOut", pose = PALM },
		{
			at = T.set + 0.08,
			ease = "quadOut",
			hold = math.max(0, T.still - T.set - 0.08),
			shiver = 1.2,
			pose = with(PALM, { crouch = 0.07 }),
		},
		{ at = T.still, ease = "hold", hold = T.load - T.still, pose = with(PALM, { crouch = 0.07 }) },
		{ at = T.snap, ease = "quadOut", pose = WIND },
		-- The point (a snap) on the cast, held through the jabs; the heavy jab (a snap); proud, held.
		{ at = T.cast, ease = "snap", hold = T.finisher - T.cast - 0.06, pose = POINT },
		{ at = T.finisher, ease = "snap", pose = HEAVY },
		{ at = T.follow, ease = "quadOut", hold = T.followEnd - T.follow, pose = PROUD },
		-- Recovered; then idle.
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

-- The spirit at design time `t`: how far it has lunged (0 off his shoulder, 1 out toward the target;
-- below 0 drawn back), and how much of it is in (0..1).
local function spiritLunge(T: Plan, t: number): number
	if t < T.load then
		return 0
	elseif t < T.snap then
		return -0.2 * Kit.smooth((t - T.load) / (T.snap - T.load))
	elseif t < T.cast then
		return -0.2 + 1.2 * Kit.smooth((t - T.snap) / (T.cast - T.snap))
	elseif t < T.followEnd then
		return 1
	end
	return 1 - Kit.smooth((t - T.followEnd) / (T.fadeEnd - T.followEnd))
end

local function spiritIn(T: Plan, t: number): number
	return Kit.smooth((t - T.windup) / (T.set - T.windup))
		* (1 - Kit.smooth((t - T.followEnd) / (T.fadeEnd - T.followEnd)))
end

-- A jab's reach over time: out over 0.03 s, back over 0.05 s.
local function jab(t: number, at: number, peak: number): number
	local u = t - at
	if u < 0 or u > 0.08 then
		return 0
	end
	return peak * (if u < 0.03 then u / 0.03 else 1 - (u - 0.03) / 0.05)
end

-- How far one of the spirit's arms reaches at design time `t` (`side` 1 right, -1 left): 0 hanging,
-- 1 straight out, below 0 cocked back. The right throws the jabs; the left reaches out with the
-- beams. Eased between beats.
local function spiritReach(T: Plan, t: number, side: number): number
	if side < 0 then
		return 0.7 * Kit.smooth((t - T.snap) / 0.06) * (1 - Kit.smooth((t - T.followEnd) / 0.2))
	end
	if t < T.load then
		return -0.3 * Kit.smooth((t - T.windup) / (T.set - T.windup))
	elseif t < T.cast then
		return -0.3 - 0.3 * Kit.smooth((t - T.load) / (T.cast - T.load))
	end
	local reach = -0.6 + 0.8 * Kit.smooth((t - T.cast) / 0.03)
	for _, at in JABS do
		reach = math.max(reach, jab(t, at, 1.1))
	end
	reach = math.max(reach, jab(t, T.finisher - 0.03, 1.5))
	if t >= T.finisher and t < T.followEnd then
		reach = math.max(reach, 1.2)
	end
	return reach * (1 - Kit.smooth((t - T.followEnd) / (T.fadeEnd - T.followEnd)))
end

type Body = {
	center: CFrame, -- the spirit's torso
	size: number, -- its height
	fists: { [number]: Vector3 }, -- by side
	shoulders: { [number]: Vector3 },
}

-- Where the spirit is at design time `t`: a body's width off his right shoulder at his chest's height
-- (never over him: from the match camera a spirit over him covered him), lunged out toward the target,
-- still wide of him; from the lunge on its right fist aims at the target.
local function spiritBody(run, T: Plan, t: number): Body
	local forward = run:forward()
	local right = forward:Cross(Vector3.yAxis)
	local size = run.view.part.Size.Y * 1.25
	local ground = run:ground()
	local back = ground - forward * 0.6 + right * 3.0
	local front = ground + forward * 2.0 + right * 2.6
	local lunge = spiritLunge(T, t)
	local shiver = if t > T.set and t < T.still then math.sin(t * 90) * 0.04 else 0
	local risen = Kit.smooth((t - T.windup) / (T.set - T.windup))
	local at = back + (front - back) * lunge + right * shiver + Vector3.new(0, size * (0.3 + 0.15 * risen), 0)
	local center = CFrame.lookAt(at, at + forward) * CFrame.Angles(-math.rad(10) * math.clamp(lunge, 0, 1), 0, 0)
	local fists, shoulders = {}, {}
	local arm = size * 0.5
	local target = run:target()
	for _, side in { 1, -1 } do
		local shoulder = (center * CFrame.new(side * size * 0.3, size * 0.2, 0)).Position
		local reach = spiritReach(T, t, side)
		local hang = 1 - math.clamp(reach, 0, 1)
		local aim = if side > 0
				and t >= T.snap
				and t < T.followEnd
				and target
				and target.part.Parent
			then target.part.Position
			else nil
		local toward = if aim and (aim - shoulder).Magnitude > 1e-3 then (aim - shoulder).Unit else center.LookVector
		shoulders[side] = shoulder
		fists[side] = shoulder + toward * arm * reach - Vector3.yAxis * arm * 0.6 * hang
	end
	return { center = center, size = size, fists = fists, shoulders = shoulders }
end

-- The spirit: a torso, a head with a tall crest and two arms, see-through pink; drawn from the windup
-- until it has faded. Each part reads the body for the moment it draws.
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
	-- The tall crest, swept back over its head.
	Kit.live(run, from, to, "Block", PINK, function(part, _u)
		local body, seen = now()
		part.Size = Vector3.new(body.size * 0.07, body.size * 0.3, body.size * 0.2)
		part.CFrame = body.center
			* CFrame.new(0, body.size * 0.58, body.size * 0.04)
			* CFrame.Angles(math.rad(-20), 0, 0)
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
end

-- The diamond shards: swirling in around him from the set, closing, and shooting into his chest on
-- the cast (locking into the shield).
local function shards(run, T: Plan)
	local count = if run.reduced then 3 else 5
	for i = 1, count do
		local phase = i / count * 2 * math.pi
		local color = if i % 2 == 0 then PINK:Lerp(DIAMOND, 0.4) else DIAMOND
		Kit.live(run, T.set, T.cast + 0.02, "Block", color, function(part, _u)
			local t = run:designTime()
			local chest = run:chest()
			local close = Kit.smooth((t - T.set) / (T.cast - T.set))
			local lock = Kit.smooth((t - T.snap) / (T.cast - T.snap))
			local angle = phase + (t - T.set) * 5
			local r = UNIT_HEIGHT * (0.75 - 0.3 * close) * (1 - lock)
			local scale = VfxRecipe.viewScale(chest)
			local at = chest
				+ Vector3.new(math.cos(angle) * r, math.sin(t * 6 + i) * 0.4 * (1 - lock), math.sin(angle) * r)
			part.Size = Vector3.new(0.3, 0.3, 0.12) * scale
			part.CFrame = CFrame.new(at) * CFrame.Angles(t * 6, t * 4, math.rad(45))
			part.Transparency = 0.1
		end, Enum.Material.SmoothPlastic)
	end
end

local heavyJab: (any, any?) -> () -- below

def.beats = {
	{
		at = planOf(1).windup, -- every plan starts its windup at the same design time (-FULL)
		run = function(run)
			local plan = planFor(run)
			run:face(run:target())
			UltimateCallout.mark(run.view, CALLOUT, run:span(plan.windup, plan.finisher - plan.windup))
			buildSpirit(run, plan)
			shards(run, plan)
			Sfx.play("magicChime", { pitch = 1.2, volume = 0.45 })
			run:at(plan.set, function()
				Sfx.play("healTwinkle", { pitch = 1.3, volume = 0.4 })
			end)
			run:camera(plan.set, plan.cast, { key = "push", push = 1.8, focus = run:chest(), rise = 0.3, fall = 0.15 })
			-- The heavy jab waits for the real hit; should it never come, it still lands.
			run:at(plan.finisher + 0.05, function()
				if not run.memo.finished then
					run.memo.finished = true
					heavyJab(run, run:target())
				end
			end)
		end,
	},
}

-- The cast itself: no generic burst (the shield, the repairs and the jabs carry the moment).
function def.release(_run): boolean
	return true
end

-- A repair on a healed ally: a pink beam to it from the spirit's left hand; a crack across it
-- that closes up; sparkles.
local function repair(run, view: any)
	local plan = planFor(run)
	local now = run:designTime()
	local scale = VfxRecipe.viewScale(view.part.Position)
	Kit.live(run, now, now + 0.35, "Block", SPIRIT:Lerp(DIAMOND, 0.3), function(part, u)
		if not view.part.Parent then
			part.Transparency = 1
			return
		end
		local from = spiritBody(run, plan, run:designTime()).fists[-1]
		local to = view.part.Position
		local length = math.max((to - from).Magnitude, 0.1)
		local width = 0.16 * scale * (1 - 0.5 * u)
		part.Size = Vector3.new(width, width, length)
		part.CFrame = CFrame.lookAt((from + to) / 2, to)
		part.Transparency = 0.15 + 0.85 * Kit.easeIn(u)
	end, Enum.Material.SmoothPlastic)
	do
		local tilt = 0.5
		Kit.live(run, now + 0.05, now + 0.5, "Block", CRACK, function(part, u)
			if not view.part.Parent then
				part.Transparency = 1
				return
			end
			local toward = run:chest() - view.part.Position
			toward = Vector3.new(toward.X, 0, toward.Z)
			toward = if toward.Magnitude > 1e-3 then toward.Unit else Vector3.zAxis
			local at = view.part.Position + toward * view.part.Size.Z * 0.55 + Vector3.new(0, 0.2, 0)
			part.Size = Vector3.new(math.max(0.05, view.part.Size.X * 0.9 * (1 - Kit.easeIn(u))), 0.07 * scale, 0.05)
			part.CFrame = CFrame.lookAt(at, at + toward) * CFrame.Angles(0, 0, tilt)
			part.Transparency = 0.1
		end, Enum.Material.SmoothPlastic)
	end
	run:at(now + 0.3, function()
		if view.part.Parent then
			VfxRecipe.sparks(view.part.Position, 0.6 * scale, 10, SPARKLE, Vector3.yAxis, scale)
		end
	end)
end

-- One small jab on `view`: a pink hit star (no sparks: they outlive the heavy jab), a flinch.
local function smallJab(run, view: any)
	if not view or not view.part.Parent then
		return
	end
	local at = view.part.Position
	local scale = VfxRecipe.viewScale(at)
	VfxRecipe.kitHitStar(at, UNIT_HEIGHT * 0.5 * scale, SPIRIT, scale)
	HitFeel.react(view, run:chest(), { knock = 1, tilt = 15 })
	HitFeel.cameraShake(0.08, 0.1)
	Sfx.play("impactLight", { pitch = 1.05 + (math.random() - 0.5) * 0.15 })
end

-- The heavy jab (AFTER.finisher): a big pink hit star, sparks, one shock ring, a short light;
-- hit-stop on the bodies (0.07 s); the shake, the punch-in; the target thrown.
heavyJab = function(run, target: any?)
	local s = run:scale()
	local hit = if target and target.part.Parent
		then target.part.Position
		else run:chest() + run:forward() * UNIT_HEIGHT
	local view = VfxRecipe.viewScale(hit)
	local floor = Vector3.new(hit.X, run:ground().Y, hit.Z)
	VfxRecipe.kitHitStar(hit, UNIT_HEIGHT * 0.95 * view, SPIRIT, view)
	VfxRecipe.sparks(hit, 0.7 * view, 16, SPARKS, hit - run:chest(), view)
	VfxRecipe.meshRing(floor, UNIT_HEIGHT * 0.6 * s * view, PINK, 0.3, 0.3)
	if not run.reduced then
		ImpactEffects.light(hit, PINK, FINISH_LIGHT.brightness, FINISH_LIGHT.range * UNIT_HEIGHT, FINISH_LIGHT.seconds)
	end
	local held = { run.view }
	if target then
		table.insert(held, target)
	end
	HitFeel.hitStop(held, 0.07, { caster = run.view })
	if target then
		HitFeel.react(target, run:chest(), { final = true })
	end
	HitFeel.cameraShake(0.26, 0.28)
	HitFeel.punchIn(1)
	Sfx.play("impactHeavy")
end

function def.event(run, event): boolean
	local kind = event.kind
	if kind == "Shield" and event.target == run.unitIndex then
		-- The shards lock in: a white glint at his chest (small: the real bubble shows him).
		local chest = run:chest()
		local scale = VfxRecipe.viewScale(chest)
		VfxRecipe.kitHitStar(chest + run:forward() * 0.6, UNIT_HEIGHT * 0.45 * scale, DIAMOND, scale)
		Sfx.play("magicChime", { pitch = 1.5, volume = 0.5 })
		return false -- the shield bubble still shows
	elseif kind == "Heal" and event.target and event.target ~= run.unitIndex then
		local view = run.context.views[event.target]
		if view then
			repair(run, view)
		end
		if not run.memo.chimed then
			run.memo.chimed = true
			Sfx.play("healTwinkle")
		end
		return true
	elseif kind == "Damage" and event.target and not event.dot then
		local view = run.context.views[event.target]
		if run.memo.jabbed then
			return true
		end
		run.memo.jabbed = true
		-- The spirit's jabs: two small, then the heavy one.
		Sfx.play("punchRush", { volume = 0.6 })
		for _, at in JABS do
			run:at(at, function()
				smallJab(run, view)
			end)
		end
		run:at(AFTER.finisher, function()
			if not run.memo.finished then
				run.memo.finished = true
				heavyJab(run, view)
			end
		end)
		return true
	end
	return false
end

return def
