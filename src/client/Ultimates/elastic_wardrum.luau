-- elastic_wardrum (Tier 4): the gears, goofy and godlike. His casts differ: the first steps him into
-- Gear 2, the second into Gear 3 (both a Form event at the Cast event, t = 0), and every cast after
-- that shields him (Shield) and slams everything within 1 hex of him (Area, a Damage per enemy), all
-- at t = 0. One beat plan, three choreographies picked from the cast's real events ("gear2",
-- "gear3", "slam"). Everything before 0 is anticipation; the payoff lands exactly on the real Form or
-- Area event. Bare fists. Every movement is the figure's pose offset (UnitView): his real position
-- never changes.
-- Designed timeline (real seconds at full length; SEGMENTS):
--   -0.96  the coil: bouncing leg pumps, pink-white steam puffing off him on each pump (every kind);
--          the callout (a red outline on him, a small ground ring)
--   -0.68  set, by kind:
--            slam:  the right fist raised overhead and swelling (a growing fist, white clouds round
--                   it); drumbeat rings thump out from his feet (three beats across the build)
--            gear3: the thumb at his mouth, he blows and swells, rocking back
--            gear2: pumping on, steam pouring
--          a shiver of held tension, until -0.38
--   -0.38  stillness, on the last drumbeat, until -0.18
--   -0.18  a 0.12 s load dip
--   -0.06  the payoff's 0.06 s snap
--    0     on the real event:
--            slam:  a giant stretched fist slams down just in front of him (the arm stretching out
--                   to it, a long fist trail), a cartoon shock ring that bounces (a second, smaller
--                   ring after it), hit stars on the enemies hit; hit-stop on the bodies; the boom, a
--                   shake, the punch-in; the main target knocked 2.5 studs and launched 0.8, the rest
--                   1.5; the fist snaps back by +0.3
--            gear3: a burst of white clouds and a white flame aura; he hops, arms flung wide
--            gear2: a gush of pink-white steam and one steam ring; he straightens, fists up
--   +0.06  the follow-through, held to +0.3
--   +0.5   he deflates into a laughing pose, arms wide, held; idle by +1.0
--   shield the game's shield bubble is his (nothing added on top)
-- When the real window before the cast is shorter (Cinematic run.k < 1, at least the tier's 0.6),
-- the anticipation is laid out again for it (planOf): the stillness gives first, then the set, then
-- the coil, and only past that does everything but the load and the snap shrink evenly. The load,
-- the snap and everything after the hit never shrink.
-- Readable from the match camera (ViewScale: 1 at close cameras, up to 1.8 there): the fist, the
-- drum and shock rings, the trail, the hit stars and the clouds grow with it.
-- Layers (tier 4, within its 34; peak ~10 at the slam, estimated): steam and clouds (particles), the
-- swelling fist (1), 3 drum rings and 2 shock rings (5 rings in all, the cast's cap is 6), at the
-- slam the giant fist and its arm (2), hit stars and sparks (particles), a light (not when reduced),
-- the fist trail (BladeTrail); Gear 3's aura spikes; the callout's ring. Poses: PoseAnimator; hit
-- feel: HitFeel; callout: UltimateCallout; sounds: Sfx.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RenderConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("RenderConfig"))

local BladeTrail = require(script.Parent.Parent.BladeTrail)
local HitFeel = require(script.Parent.Parent.HitFeel)
local ImpactEffects = require(script.Parent.Parent.ImpactEffects)
local PoseAnimator = require(script.Parent.Parent.PoseAnimator)
local Sfx = require(script.Parent.Parent.Sfx)
local UltimateCallout = require(script.Parent.Parent.UltimateCallout)
local UltimateKit = require(script.Parent.Parent.UltimateKit)
local VfxRecipe = require(script.Parent.Parent.VfxRecipe)

local Kit = UltimateKit
local rgb = Color3.fromRGB

-- The anticipation's segments in real seconds at full length, in order up to the payoff (0.96 s in
-- all), and how far each may shrink when the window is short (`least`), in the order they give way
-- (the stillness first, then the set, then the coil).
local SEGMENTS = {
	coil = 0.28, -- windup start -> the pumps
	set = 0.3, -- the swell (by kind)
	still = 0.2, -- stillness on the last drumbeat
	load = 0.12, -- the load dip
	snap = 0.06, -- the payoff's snap, ending on the real event
}
local LEAST = { still = 0.08, set = 0.12, coil = 0.14 }
local SHRINK_ORDER = { "still", "set", "coil" }
local ORDER = { "coil", "set", "still", "load", "snap" }
local SNAPS = { load = true, snap = true } -- never shrink
local FULL = 0
for _, name in ORDER do
	FULL += SEGMENTS[name]
end

-- After the payoff (design seconds = real seconds: never compressed).
local AFTER = {
	finisher = 0,
	follow = 0.06, -- the follow-through pose reached
	slammed = 0.08, -- the giant fist down
	trailOff = 0.14, -- the fist trail stops drawing
	bounce = 0.15, -- the shock ring's bounce
	retracted = 0.3, -- the giant fist snapped back
	followEnd = 0.3, -- the follow-through held until here
	laugh = 0.5, -- deflated, laughing
	rest = 1.0, -- back to idle
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
	-- Real times, backward from the payoff.
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
local RED = rgb(225, 45, 45)
local STEAM = rgb(255, 200, 210)
local SKIN = rgb(240, 200, 160)
local CALLOUT = RED
local TRAIL = ColorSequence.new({
	ColorSequenceKeypoint.new(0, WHITE),
	ColorSequenceKeypoint.new(0.4, rgb(255, 150, 150)),
	ColorSequenceKeypoint.new(1, RED),
})
local TRAIL_LIFE = 0.24
local SPARKS = ColorSequence.new(WHITE, RED)
local PUMPS = 3 -- leg pumps across the coil and the set
local GIANT_FIST = 2.6 -- the slam's fist, studs across (normal size)
-- The slam's light: a short, tight warm flash where the fist lands.
local FINISH_LIGHT = { brightness = 1.8, range = 1.5, seconds = 0.2 } -- range in unit heights
local UNIT_HEIGHT = RenderConfig.unitSize.Y

-- The poses (PoseAnimator channels), about twice realistic: big, goofy anime poses. Every body pose
-- names every body channel, so a held pose holds the whole body still.
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

-- The pumps: fists up, a wide stance; the crouch bounces on keys of its own.
local PUMP = pose({
	crouch = 0.3,
	lean = 10,
	rightArm = 45,
	rightArmOut = 20,
	leftArm = 45,
	leftArmOut = 20,
	leftLeg = 24,
	rightLeg = -22,
	headPitch = 6,
})
local SET = {
	-- The fist raised overhead, swelling; leaning back under its weight.
	slam = pose({
		crouch = 0.22,
		lean = -12,
		tilt = 6,
		rightArm = 175,
		rightArmOut = 10,
		leftArm = 30,
		leftArmOut = 35,
		leftLeg = 22,
		rightLeg = -20,
		headPitch = -16,
	}),
	-- The thumb at his mouth, blowing, swelling, rocking back.
	gear3 = pose({
		crouch = 0.15,
		lean = -12,
		rightArm = 120,
		rightArmOut = -40,
		leftArm = 20,
		leftArmOut = 30,
		leftLeg = 16,
		rightLeg = -14,
		headPitch = -6,
	}),
	-- Pumping on, low.
	gear2 = with(PUMP, { crouch = 0.36, lean = 14 }),
}
local LOAD = {
	slam = with(SET.slam, { lean = -16, crouch = 0.3, rightArm = 180 }),
	gear3 = with(SET.gear3, { crouch = 0.24, lean = -16 }),
	gear2 = with(SET.gear2, { crouch = 0.42 }),
}
local FINISH = {
	-- The arm thrown down and forward after the giant fist, the body pitched over it.
	slam = pose({
		crouch = 0.36,
		lean = 22,
		twist = 18,
		rightArm = 40,
		rightArmOut = 5,
		leftArm = -20,
		leftArmOut = 30,
		leftLeg = 36,
		rightLeg = -32,
		headPitch = 12,
	}),
	-- Arms flung wide, hopping, head back.
	gear3 = pose({
		lean = -16,
		rise = 0.45,
		rightArm = 30,
		rightArmOut = 85,
		leftArm = 30,
		leftArmOut = 85,
		leftLeg = 20,
		rightLeg = -10,
		headPitch = -18,
	}),
	-- Straightened in the gush, fists up.
	gear2 = pose({ lean = -6, rightArm = 60, rightArmOut = 15, leftArm = 60, leftArmOut = 15, headPitch = -6 }),
}
-- Deflated and laughing: arms wide, head back, a little sag.
local LAUGH = pose({
	crouch = 0.08,
	lean = -10,
	rightArm = 20,
	rightArmOut = 70,
	leftArm = 20,
	leftArmOut = 70,
	headPitch = -20,
})

-- The keys for a plan (planOf) and a kind.
local function keyframes(T: Plan, kind: string): { PoseAnimator.Keyframe }
	local keys: { PoseAnimator.Keyframe } = {
		{ at = T.windup, pose = pose({}) },
		{ at = T.set, ease = "quadOut", pose = PUMP },
	}
	-- The pumps: the crouch bouncing up and down across the coil and the set.
	local step = (T.still - T.windup) / (PUMPS * 2)
	for i = 1, PUMPS * 2 - 1 do
		table.insert(keys, {
			at = T.windup + i * step,
			ease = if i % 2 == 1 then "quadOut" else "quadIn",
			pose = { crouch = if i % 2 == 1 then 0.08 else 0.36 },
		})
	end
	local set = SET[kind]
	table.insert(keys, { at = T.still, ease = "quadOut", pose = set })
	table.insert(keys, { at = T.still + 0.001, ease = "hold", hold = T.load - T.still, shiver = 1.4, pose = set })
	table.insert(keys, { at = T.snap, ease = "quadOut", pose = LOAD[kind] })
	table.insert(keys, { at = T.finisher, ease = "snap", pose = FINISH[kind] })
	table.insert(keys, {
		at = T.follow,
		ease = "quadOut",
		hold = T.followEnd - T.follow,
		pose = with(FINISH[kind], { rise = FINISH[kind].rise * 0.6 }),
	})
	table.insert(keys, { at = T.laugh, ease = "back", hold = 0.25, pose = LAUGH })
	table.insert(keys, { at = T.rest, ease = "inOut", pose = pose({}) })
	return keys
end

local def = {}

-- Which cast this is: "gear2", "gear3" or "slam", from its real events.
local function kindOf(run): string
	for _, event in run.cast do
		if event.kind == "Form" then
			return if (event.formIndex or 0) >= 3 then "gear3" else "gear2"
		end
	end
	return "slam"
end

-- This run's plan (by its anticipation speed), kept on the run for the beats.
local function planFor(run): Plan
	local plan = run.memo.plan
	if not plan then
		plan = planOf(run.k or 1)
		run.memo.plan = plan
	end
	return plan
end

-- Tracks by plan and kind, built once each.
local tracks: { [Plan]: { [string]: any } } = {}
function def.poseFor(run)
	local plan = planFor(run)
	local kind = kindOf(run)
	local byKind = tracks[plan]
	if not byKind then
		byKind = {}
		tracks[plan] = byKind
	end
	local track = byKind[kind]
	if not track then
		track = PoseAnimator.track(keyframes(plan, kind))
		byKind[kind] = track
	end
	return track
end

-- The fist's trail (BladeTrail on the bare hand), for the slam. Gone once it has faded.
local function attachFist(run)
	if run.memo.fist then
		return
	end
	local trail = BladeTrail.attach(run.view, { hand = "right", from = 0, to = 0.12, viewScale = true })
	trail:add("slam", { colors = TRAIL, lifetime = TRAIL_LIFE })
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
			trail:enable("slam")
		else
			trail:disable("slam")
		end
	end
end

-- A puff of steam (or clouds) off his chest.
local function puff(run, color: Color3, count: number, size: number)
	local at = run:chest()
	ImpactEffects.burst("puff", at, Vector3.yAxis, {
		color = color,
		count = count,
		size = size * VfxRecipe.viewScale(at),
		speed = { 2, 5 },
		lifetime = { 0.4, 0.7 },
		spread = 70,
		transparency = 0.35,
	})
end

-- Where the slam's giant fist lands: just in front of him (the real area is centered on him).
local function slamPoint(run): Vector3
	return run:ground() + run:forward() * UNIT_HEIGHT * 0.8
end

local finisher: (any, string) -> () -- below

def.beats = {
	{
		at = planOf(1).windup, -- every plan starts its windup at the same design time (-FULL)
		run = function(run)
			local plan = planFor(run)
			local kind = kindOf(run)
			run.memo.kind = kind
			local s = run:scale()
			run:face(run:target())
			UltimateCallout.mark(run.view, CALLOUT, run:span(plan.windup, plan.finisher - plan.windup))
			-- Steam off him on each pump.
			local step = (plan.still - plan.windup) / PUMPS
			for i = 0, PUMPS - 1 do
				run:at(plan.windup + i * step + 0.02, function()
					puff(run, STEAM, if run.reduced then 2 else 4, 0.9)
				end)
			end
			if kind == "slam" then
				attachFist(run)
				-- Drumbeats: a ring thumping out from his feet on each beat, the last on the stillness.
				Sfx.play("punchRush", { volume = 0.6 })
				for i = 1, 3 do
					local beat = plan.windup + (plan.still - plan.windup) * i / 3
					run:at(beat, function()
						local ground = run:ground()
						VfxRecipe.meshRing(ground, (1.4 + 0.3 * i) * s * VfxRecipe.viewScale(ground), WHITE, 0.3, 0.3)
					end)
				end
				-- The fist raised and swelling, white clouds round it.
				run:at(plan.set, function()
					local view = VfxRecipe.viewScale(run:hand("right"))
					Kit.live(run, plan.set, plan.snap, "Ball", SKIN, function(part, u)
						part.Size = Vector3.one * (0.5 + 0.9 * Kit.easeOut(u)) * s * view
						part.CFrame = CFrame.new(run:hand("right"))
						part.Transparency = 0
					end, Enum.Material.SmoothPlastic)
					ImpactEffects.burst("puff", run:hand("right"), Vector3.yAxis, {
						color = WHITE,
						count = if run.reduced then 3 else 6,
						size = 1.1 * view,
						speed = { 1, 3 },
						lifetime = { 0.4, 0.7 },
						spread = 180,
						transparency = 0.3,
					})
				end)
				run:at(plan.snap - 0.01, function()
					setTrail(run, true)
				end)
				run:at(plan.trailOff, function()
					setTrail(run, false)
				end)
			elseif kind == "gear3" then
				-- The thumb at his mouth: he blows and swells.
				Kit.orb(run, plan.set, plan.snap, SKIN, function()
					return run:head() + run:forward() * 0.6
				end, function(u)
					return (0.2 + 0.8 * u) * s * VfxRecipe.viewScale(run:head())
				end)
				Sfx.play("energyCharge", { pitch = 0.9, volume = 0.7 })
			else
				run:at(plan.set, function()
					puff(run, STEAM, if run.reduced then 4 else 8, 1.2)
				end)
			end
			-- The payoff waits for the real event; should it never come, it still plays.
			run:at(plan.finisher + 0.05, function()
				if not run.memo.finished then
					run.memo.finished = true
					finisher(run, kind)
				end
			end)
		end,
	},
}

-- The cast itself: no generic burst (the payoff is the release).
function def.release(_run): boolean
	return true
end

-- The giant fist: it stretches down from the raised hand onto the slam point by AFTER.slammed and
-- snaps back by AFTER.retracted, the arm stretching after it.
local function giantFist(run)
	local s = run:scale()
	local land = slamPoint(run) + Vector3.new(0, GIANT_FIST * 0.4 * s, 0)
	local view = VfxRecipe.viewScale(land)
	local size = GIANT_FIST * s * view
	local function fistAt(): Vector3
		local t = run:designTime()
		local hand = run:hand("right")
		local out = if t < AFTER.slammed
			then Kit.easeIn(t / AFTER.slammed)
			else 1 - Kit.easeIn((t - AFTER.slammed) / (AFTER.retracted - AFTER.slammed))
		return hand:Lerp(land, math.clamp(out, 0, 1))
	end
	Kit.live(run, 0, AFTER.retracted, "Ball", SKIN, function(part, _u)
		part.Size = Vector3.one * size
		part.CFrame = CFrame.new(fistAt())
		part.Transparency = 0
	end, Enum.Material.SmoothPlastic)
	Kit.live(run, 0, AFTER.retracted, "Block", RED, function(part, _u)
		local fist = fistAt()
		local shoulder = run:chest()
		local length = math.max((fist - shoulder).Magnitude, 0.05)
		part.Size = Vector3.new(size * 0.35, size * 0.35, length)
		part.CFrame = CFrame.lookAt((fist + shoulder) / 2, fist)
		part.Transparency = 0
	end, Enum.Material.SmoothPlastic)
end

-- The payoff on the real event, by kind (see the header).
finisher = function(run, kind: string)
	local s = run:scale()
	if kind == "slam" then
		giantFist(run)
		Sfx.play("whooshHeavy")
		run:at(AFTER.slammed, function()
			local land = slamPoint(run)
			local view = VfxRecipe.viewScale(land)
			VfxRecipe.meshRing(land, UNIT_HEIGHT * 0.7 * s * view, WHITE, 0.3, 0.3)
			run:at(AFTER.bounce, function()
				VfxRecipe.meshRing(land, UNIT_HEIGHT * 0.45 * s * view, RED, 0.25, 0.3)
			end)
			VfxRecipe.kitDust(land, UNIT_HEIGHT * 0.6 * s * view, 3, 0.6)
			if not run.reduced then
				ImpactEffects.light(
					land + Vector3.new(0, UNIT_HEIGHT * 0.4, 0),
					rgb(255, 220, 190),
					FINISH_LIGHT.brightness,
					FINISH_LIGHT.range * UNIT_HEIGHT,
					FINISH_LIGHT.seconds
				)
			end
			local main = run:target()
			local targets = run:targets()
			local held = { run.view }
			for _, target in targets do
				table.insert(held, target)
				local at = target.part.Position
				local hitView = VfxRecipe.viewScale(at)
				VfxRecipe.kitHitStar(at, UNIT_HEIGHT * 0.6 * hitView, WHITE, hitView)
				VfxRecipe.sparks(at, 0.5 * hitView, 8, SPARKS, nil, hitView)
			end
			HitFeel.hitStop(held, 0.07, { caster = run.view })
			for _, target in targets do
				HitFeel.react(target, land, if target == main then { final = true } else { knock = 1.5, tilt = 18 })
			end
			HitFeel.cameraShake(0.25, 0.3)
			HitFeel.punchIn(1)
			Sfx.play("impactHeavy")
		end)
	elseif kind == "gear3" then
		-- White clouds round him and a white flame aura; he hops, arms wide.
		local ground = run:ground()
		local view = VfxRecipe.viewScale(ground)
		for i = 1, (if run.reduced then 3 else 6) do
			local angle = i / 6 * 2 * math.pi
			ImpactEffects.burst(
				"puff",
				ground + Vector3.new(math.cos(angle) * 2, 1, math.sin(angle) * 2),
				Vector3.yAxis,
				{
					color = WHITE,
					count = 4,
					size = 1.6 * view,
					speed = { 2, 4 },
					lifetime = { 0.5, 0.8 },
					spread = 50,
					transparency = 0.25,
				}
			)
		end
		VfxRecipe.kitAuraSpike(run, run.view, WHITE, 0, 0.45, 1, rgb(255, 210, 220))
		HitFeel.cameraShake(0.2, 0.3)
		Sfx.play("whooshHeavy", { pitch = 0.8 })
		Sfx.play("impactHeavy", { volume = 0.5, pitch = 1.2 })
	else
		-- A gush of steam and one steam ring.
		puff(run, STEAM, if run.reduced then 6 else 12, 1.3)
		local ground = run:ground()
		VfxRecipe.meshRing(ground, UNIT_HEIGHT * 0.6 * s * VfxRecipe.viewScale(ground), STEAM, 0.35, 0.3)
		HitFeel.cameraShake(0.15, 0.25)
		Sfx.play("whooshHeavy", { pitch = 1.1 })
	end
end

function def.event(run, event): boolean
	local kind = event.kind
	if kind == "Form" or kind == "Area" then
		if not run.memo.finished then
			run.memo.finished = true
			finisher(run, run.memo.kind or kindOf(run))
		end
		return true
	elseif kind == "Shield" and event.target == run.unitIndex then
		return false -- the shield bubble (CombatPlayback) is his: nothing on top of it
	elseif kind == "Damage" and event.target and not event.dot then
		return true -- the slam draws every hit
	end
	return false
end

return def
