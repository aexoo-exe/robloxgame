-- ascending_core (Tier 5): stronger with every cast, then the full-board beam. His casts differ: in
-- Core I and Core II each cast hits an area around his target (Area) and steps him up a form (Form);
-- in Core III each cast is a line from him to the board's edge (Area with shape LINE and its cells);
-- every cast also stacks a buff (Buff) and hits (a Damage per enemy), all at the Cast event (t = 0).
-- One beat plan, two choreographies picked from the cast's real events ("power", "beam").
-- Everything before 0 is anticipation; the payoff lands exactly on the real Area event. Bare hands
-- (both carry short trails on the release). Every movement is the figure's pose offset (UnitView):
-- his real position never changes.
-- Designed timeline (real seconds at full length; SEGMENTS):
--   -1.06  fists clench, arms down and out, he leans back and yells; a gold aura climbs off him;
--          the callout (a gold outline on him, a small ground ring)
--   -0.78  set, by kind:
--            power: the strain grows, a shiver; blue crackle over him (more on the way to Core III)
--            beam:  hands cupped at his right hip, body turned away and low; blue-white light grows
--                   between his hands, motes drawn in, stones float up around him; the camera leans in
--          until -0.38
--   -0.38  stillness: nothing moves, until -0.18
--   -0.18  a 0.12 s load dip
--   -0.06  the release's 0.06 s snap
--    0     on the real hit, by kind:
--            power: one palm thrust at the target (a hand trail), a gold streak crossing to it; a gold
--                   hit star, sparks and one shock ring at the area, a light; then the real form
--                   change: a gold eruption off him (the aura flaring, sparks, embers)
--            beam:  both hands thrust (trails), a thick blue-white beam along the real line to the
--                   board's edge, a bright groove under it, a hit star on each enemy, one shock ring at
--                   the first; he is pushed back a little; the camera pulls back
--          hit-stop on the bodies; the boom, a strong shake, the punch-in; the main target knocked
--          2.5 studs and launched 0.8, the rest 1.5
--   +0.06  the follow-through, held to +0.4 (the beam thinning out by +0.7)
--   +0.75  the aura settles, steam off him after the beam; idle by +1.15
-- When the real window before the cast is shorter (Cinematic run.k < 1, at least the tier's 0.6),
-- the anticipation is laid out again for it (planOf): the stillness gives first, then the set, then
-- the clench, and only past that does everything but the load and the snap shrink evenly. The load,
-- the snap and everything after the hit never shrink.
-- Readable from the match camera (ViewScale: 1 at close cameras, up to 1.8 there): the trails, the
-- orb, the beam, the groove, the ring, the hit stars and the sparks grow with it (the aura sheets are
-- sized from his body).
-- Layers (tier 5, within its 44; peak ~22 at the power payoff with 3 enemies, ~17 in the beam's
-- charge, ~19 at the beam, estimated): the aura and crackle (the beam's aura only through the
-- clench), the beam's orb (core + halo), 8 motes, 4 stones (not when reduced), at the payoff the beam (core + glow) and groove, or the gold streak; one shock ring,
-- hit stars and sparks (particles), a light (not when reduced); the hand trails (BladeTrail); the
-- callout's ring. Camera: a push on him through the beam's charge and a pull at the beam (tier 5).
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

-- The anticipation's segments in real seconds at full length, in order up to the hit (1.06 s in
-- all), and how far each may shrink when the window is short (`least`), in the order they give way
-- (the stillness first, then the set, then the clench).
local SEGMENTS = {
	clench = 0.28, -- windup start -> fists clenched, the yell
	set = 0.4, -- the strain / the cupped-hands charge
	still = 0.2, -- stillness
	load = 0.12, -- the load dip
	snap = 0.06, -- the release's snap, ending on the hit
}
local LEAST = { still = 0.08, set = 0.15, clench = 0.14 }
local SHRINK_ORDER = { "still", "set", "clench" }
local ORDER = { "clench", "set", "still", "load", "snap" }
local SNAPS = { load = true, snap = true } -- never shrink
local FULL = 0
for _, name in ORDER do
	FULL += SEGMENTS[name]
end

-- After the hit (design seconds = real seconds: never compressed).
local AFTER = {
	finisher = 0,
	follow = 0.06, -- the follow-through pose reached
	trailOff = 0.14, -- the hand trails stop drawing
	followEnd = 0.4, -- the follow-through held until here
	beamEnd = 0.7, -- the beam thinned out
	settle = 0.75, -- the aura settles
	rest = 1.15, -- back to idle
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
		windup = design(real.clench),
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
local GOLD = rgb(255, 200, 40)
local GOLD_DEEP = rgb(255, 140, 0)
local BLUE = rgb(80, 160, 255)
local BLUE_LIGHT = rgb(190, 225, 255)
local STONE = rgb(150, 140, 128)
local CALLOUT = GOLD
local GOLD_SPARKS = ColorSequence.new(WHITE, GOLD)
local BLUE_SPARKS = ColorSequence.new(WHITE, BLUE)
local HAND_TRAIL = ColorSequence.new({
	ColorSequenceKeypoint.new(0, WHITE),
	ColorSequenceKeypoint.new(0.5, BLUE_LIGHT),
	ColorSequenceKeypoint.new(1, BLUE),
})
local BEAM_WIDTH = 0.3 -- unit heights: thick, but never wider than a unit is
local STONES = 4
local MOTES = 8
-- The payoff's light: a short, tight flash at the main target's chest.
local FINISH_LIGHT = { brightness = 1.8, range = 1.5, seconds = 0.25 } -- range in unit heights
local UNIT_HEIGHT = RenderConfig.unitSize.Y
local HEX = math.sqrt(3) * RenderConfig.hexRadius -- between neighboring cell centers

-- The poses (PoseAnimator channels), about twice realistic: big, readable anime poses. Every body
-- pose names every body channel, so a held pose holds the whole body still. `lunge` (the beam's
-- push back) runs on keys of its own.
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

-- The clench: fists down and out, leaning back, yelling at the sky.
local CLENCH = pose({
	crouch = 0.22,
	lean = -16,
	rightArm = -15,
	rightArmOut = 38,
	leftArm = -15,
	leftArmOut = 38,
	leftLeg = 22,
	rightLeg = -20,
	headPitch = -22,
})
local SET = {
	power = with(CLENCH, { crouch = 0.3, lean = -18, rightArmOut = 45, leftArmOut = 45 }),
	-- Hands cupped at his right hip, the body turned away and low, eyes on the target.
	beam = pose({
		crouch = 0.42,
		lean = 4,
		twist = -48,
		rightArm = 25,
		rightArmOut = 10,
		leftArm = 30,
		leftArmOut = -40,
		leftLeg = 36,
		rightLeg = -32,
		headYaw = 38,
		headPitch = 4,
	}),
}
local LOAD = {
	power = with(SET.power, { crouch = 0.36, lean = -20 }),
	beam = with(SET.beam, { twist = -58, crouch = 0.5 }),
}
local FIRE = {
	-- One palm thrust at the target, the right shoulder driving through.
	power = pose({
		crouch = 0.22,
		lean = 16,
		twist = 32,
		rightArm = 95,
		leftArm = -12,
		leftArmOut = 28,
		leftLeg = 32,
		rightLeg = -28,
		headPitch = 4,
	}),
	-- Both hands thrust straight out together.
	beam = pose({
		crouch = 0.34,
		lean = 14,
		twist = 14,
		rightArm = 92,
		rightArmOut = 5,
		leftArm = 92,
		leftArmOut = -5,
		leftLeg = 38,
		rightLeg = -34,
		headPitch = 2,
	}),
}
-- Settled: upright, arms loose, the aura going down.
local SETTLE = pose({ lean = -4, rightArm = 8, rightArmOut = 15, leftArm = 8, leftArmOut = 15, headPitch = 6 })

-- The keys for a plan (planOf), a kind and the beam's push back (studs, normal size).
local function keyframes(T: Plan, kind: string, push: number): { PoseAnimator.Keyframe }
	return {
		{ at = T.windup, pose = with(pose({}), { lunge = 0 }) },
		{ at = T.set, ease = "quadOut", pose = CLENCH },
		-- The set held with a shiver of strain, then in stillness.
		{
			at = T.set + 0.12,
			ease = "quadOut",
			hold = math.max(0, T.still - T.set - 0.12),
			shiver = if kind == "power" then 2 else 1.2,
			pose = SET[kind],
		},
		{ at = T.still, ease = "hold", hold = T.load - T.still, pose = SET[kind] },
		{ at = T.snap, ease = "quadOut", pose = LOAD[kind] },
		-- The release (a snap) on the hit; the follow-through held.
		{ at = T.finisher, ease = "snap", hold = T.followEnd - T.finisher, pose = FIRE[kind] },
		{ at = T.finisher, pose = { lunge = 0 } },
		{ at = T.follow, ease = "expoOut", pose = { lunge = -push } },
		-- The aura settles, back to where he stands; then idle.
		{ at = T.settle, ease = "inOut", hold = 0.15, pose = SETTLE },
		{ at = T.settle, ease = "inOut", pose = { lunge = 0 } },
		{ at = T.rest, ease = "inOut", pose = pose({}) },
	}
end

local def = {}

-- The cast's line (Core III), if it is one.
local function lineOf(run): any?
	for _, event in run.cast do
		if event.kind == "Area" and event.shape == "LINE" and event.cells then
			return event
		end
	end
	return nil
end

local function kindOf(run): string
	return if lineOf(run) then "beam" else "power"
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

-- Tracks by plan, kind and push (rounded to a hundredth of a stud: it depends on his size),
-- built once each.
local tracks: { [Plan]: { [string]: any } } = {}
function def.poseFor(run)
	local plan = planFor(run)
	local kind = kindOf(run)
	local push = if kind == "beam" then 0.25 / math.max(UnitView.sizeFactor(run.view), 0.1) else 0
	push = math.floor(push * 100 + 0.5) / 100
	local key = kind .. ":" .. push
	local byKey = tracks[plan]
	if not byKey then
		byKey = {}
		tracks[plan] = byKey
	end
	local track = byKey[key]
	if not track then
		track = PoseAnimator.track(keyframes(plan, kind, push))
		byKey[key] = track
	end
	return track
end

local function cupped(run): Vector3
	return (run:hand("left") + run:hand("right")) / 2
end

-- The hand trails (BladeTrail on both bare hands), made at the windup; they scale with the camera
-- distance. Gone once they have faded.
local function attachHands(run)
	if run.memo.hands then
		return
	end
	local hands = {}
	for _, side in { "right", "left" } do
		local trail = BladeTrail.attach(run.view, { hand = side, from = 0, to = 0.12, viewScale = true })
		trail:add("thrust", { colors = HAND_TRAIL, lifetime = 0.18 })
		table.insert(hands, trail)
	end
	run.memo.hands = hands
	run:at(planFor(run).rest, function()
		for _, trail in hands do
			trail:destroy()
		end
		run.memo.hands = nil
	end)
end

local function setTrails(run, on: boolean)
	for _, trail in run.memo.hands or {} do
		if on then
			trail:enable("thrust")
		else
			trail:disable("thrust")
		end
	end
end

-- Does this cast step him into Core III (more blue crackle on the way)?
local function toCoreThree(run): boolean
	for _, event in run.cast do
		if event.kind == "Form" and (event.formIndex or 0) >= 3 then
			return true
		end
	end
	return false
end

-- The beam's charge: light growing between his cupped hands, motes drawn in, stones floating up.
local function charge(run, plan: Plan)
	local s = run:scale()
	local view = VfxRecipe.viewScale(cupped(run))
	Kit.orb(run, plan.set, plan.finisher, BLUE_LIGHT, function()
		return cupped(run)
	end, function(u)
		return (0.3 + 1.0 * Kit.easeIn(u)) * s * view
	end)
	Kit.converge(run, plan.set, plan.still, function()
		return cupped(run)
	end, BLUE_LIGHT, 2.2 * s * view, if run.reduced then MOTES / 2 else MOTES)
	if not run.reduced then
		local ground = run:ground()
		for i = 1, STONES do
			local angle = i / STONES * 2 * math.pi + math.random() * 0.4
			local r = UNIT_HEIGHT * (0.45 + 0.3 * math.random())
			local at = ground + Vector3.new(math.cos(angle) * r, 0.15, math.sin(angle) * r)
			local spin = math.random() * 3
			Kit.block(run, plan.set, AFTER.followEnd, STONE, function(u)
				local lift = Kit.easeOut(u * 1.6) * (1 + i % 3 * 0.5)
				return CFrame.new(at + Vector3.new(0, lift, 0)) * CFrame.Angles(spin * u, spin, 0)
			end, function()
				return Vector3.new(0.35, 0.3, 0.32) * view
			end, function(u)
				return if u > 0.85 then (u - 0.85) * 6 else 0
			end, Enum.Material.Slate)
		end
	end
	run:camera(plan.set, plan.finisher, { key = "push", push = 2.6, focus = run:chest(), rise = 0.35, fall = 0.06 })
	Sfx.play("energyCharge", { pitch = 0.9 })
end

local finisher: (any, any?) -> () -- below

def.beats = {
	{
		at = planOf(1).windup, -- every plan starts its windup at the same design time (-FULL)
		run = function(run)
			local plan = planFor(run)
			local kind = kindOf(run)
			run.memo.kind = kind
			run:face(run:target())
			attachHands(run)
			UltimateCallout.mark(run.view, CALLOUT, run:span(plan.windup, plan.finisher - plan.windup))
			-- The gold aura climbing off him: through the power-up's build (ending at the load, so no
			-- sheets hang where he was at the release); for the beam one layer through the clench only
			-- (two layers through the charge buried his hands and the light between them).
			if kind == "beam" then
				VfxRecipe.kitAuraSpike(
					run,
					run.view,
					GOLD,
					plan.windup + 0.05,
					plan.set - plan.windup - 0.05,
					1,
					GOLD_DEEP
				)
			else
				VfxRecipe.kitAuraSpike(
					run,
					run.view,
					GOLD,
					plan.windup + 0.05,
					plan.load - plan.windup - 0.05,
					2,
					GOLD_DEEP
				)
			end
			Sfx.play("windGust", { pitch = 0.8, volume = 0.5 })
			if kind == "beam" then
				run:at(plan.set, function()
					charge(run, plan)
				end)
			else
				run:at(plan.set, function()
					VfxRecipe.kitCrackleAura(
						run,
						run.view,
						BLUE,
						plan.set,
						plan.load - plan.set,
						if toCoreThree(run) then 2 else 1
					)
					Sfx.play("electricBuzz", { volume = 0.6 })
				end)
			end
			run:at(plan.snap - 0.01, function()
				setTrails(run, true)
			end)
			run:at(AFTER.trailOff, function()
				setTrails(run, false)
			end)
			-- The payoff waits for the real Area event; should it never come, it still plays.
			run:at(plan.finisher + 0.05, function()
				if not run.memo.finished then
					run.memo.finished = true
					finisher(run, run:find("Area"))
				end
			end)
		end,
	},
}

-- The cast itself: no generic burst (the thrust is the release).
function def.release(_run): boolean
	return true
end

-- Where the beam ends: half a cell past the line's farthest cell from him.
local function beamEnd(run, line: any?): Vector3
	local start = cupped(run)
	local far, distance = nil, -1
	for _, cell in (line and line.cells) or {} do
		local at = run.context.toWorld(cell[1], cell[2])
		local d = (Vector3.new(at.X, start.Y, at.Z) - start).Magnitude
		if d > distance then
			far, distance = at, d
		end
	end
	if not far then
		return start + run:forward() * HEX * 4
	end
	local flat = Vector3.new(far.X, start.Y, far.Z)
	local along = flat - start
	along = if along.Magnitude > 1e-3 then along.Unit else run:forward()
	return flat + along * HEX * 0.5
end

-- The hits shared by both kinds: a hit star and sparks on each enemy, hit-stop on the bodies, the
-- reactions (the main target knocked 2.5 studs and launched 0.8, the rest 1.5), the shake and the
-- punch-in.
local function strikeAll(run, from: Vector3, color: Color3, sparks: ColorSequence)
	local main = run:target()
	local targets = run:targets()
	local held = { run.view }
	for _, target in targets do
		table.insert(held, target)
		local at = target.part.Position
		local view = VfxRecipe.viewScale(at)
		VfxRecipe.kitHitStar(at, UNIT_HEIGHT * 0.7 * view, color, view)
		VfxRecipe.sparks(at, 0.5 * view, 10, sparks, nil, view)
	end
	HitFeel.hitStop(held, 0.07, { caster = run.view })
	for _, target in targets do
		HitFeel.react(target, from, if target == main then { final = true } else { knock = 1.5, tilt = 18 })
	end
	HitFeel.cameraShake(0.32, 0.35)
	HitFeel.punchIn(1)
end

-- The payoff on the real Area event (see the header).
finisher = function(run, area: any?)
	local s = run:scale()
	if run.memo.kind == "beam" then
		local start = cupped(run)
		local finish = beamEnd(run, area)
		local view = VfxRecipe.viewScale(start)
		Kit.beam(run, 0, AFTER.beamEnd, BLUE_LIGHT, BLUE, function()
			return start
		end, function()
			return finish
		end, function(u)
			local pulse = if u < 0.4 then 1 + 0.12 * math.sin(run:now() * 40) else 1 - Kit.easeIn((u - 0.4) / 0.6) * 0.9
			return BEAM_WIDTH * UNIT_HEIGHT * s * view * pulse
		end)
		local ground = run:ground()
		Kit.groove(run, 0, 1.0, BLUE_LIGHT, ground, Vector3.new(finish.X, ground.Y, finish.Z), 0.5 * view)
		local first = run:target()
		if first and first.part.Parent then
			local at = first.part.Position
			VfxRecipe.meshRing(
				Vector3.new(at.X, ground.Y, at.Z),
				UNIT_HEIGHT * 0.7 * s * VfxRecipe.viewScale(at),
				BLUE,
				0.35,
				0.3
			)
		end
		if not run.reduced then
			ImpactEffects.light(
				start,
				BLUE_LIGHT,
				FINISH_LIGHT.brightness,
				FINISH_LIGHT.range * UNIT_HEIGHT,
				FINISH_LIGHT.seconds
			)
		end
		strikeAll(run, start, BLUE_LIGHT, BLUE_SPARKS)
		run:camera(0, 0.6, { key = "pull", push = -2, focus = run:chest(), rise = 0.05, fall = 0.4 })
		Sfx.play("energyRelease", { pitch = 0.85 })
		Sfx.play("explosion", { volume = 0.7 })
		-- Steam rising off him after the beam.
		for t = AFTER.beamEnd - 0.1, AFTER.rest, 0.2 do
			run:at(t, function()
				ImpactEffects.burst("puff", run:chest(), Vector3.yAxis, {
					color = WHITE,
					count = 3,
					size = 0.7 * VfxRecipe.viewScale(run:chest()),
					speed = { 1, 2 },
					lifetime = { 0.5, 0.8 },
					spread = 30,
					transparency = 0.5,
				})
			end)
		end
	else
		local center = run:area()
		local hit = center + Vector3.new(0, UNIT_HEIGHT * 0.5, 0)
		local from = run:hand("right")
		local along = hit - from
		local streakView = VfxRecipe.viewScale(hit)
		if along.Magnitude > 1e-3 then
			-- The gold streak crossing to the target (no solid ball).
			ImpactEffects.emit(from, {
				usage = "sparks",
				count = if run.reduced then 2 else 4,
				color = VfxRecipe.colors({ { 0, WHITE:Lerp(GOLD, 0.35) }, { 1, GOLD } }),
				size = VfxRecipe.curve({ { 0, 0.8 * s * streakView }, { 1, 0.35 * s * streakView } }),
				transparency = VfxRecipe.curve({ { 0, 0.1 }, { 0.8, 0.3 }, { 1, 1 } }),
				lifetime = { 0.08, 0.1 },
				speed = { along.Magnitude / 0.09, along.Magnitude / 0.08 },
				spread = 4,
				direction = along.Unit,
				lightEmission = 1,
				brightness = 2.5,
				stretch = true,
			})
		end
		local view = VfxRecipe.viewScale(center)
		VfxRecipe.meshRing(center, UNIT_HEIGHT * 0.7 * s * view, GOLD, 0.35, 0.3)
		if not run.reduced then
			ImpactEffects.light(
				hit,
				GOLD,
				FINISH_LIGHT.brightness,
				FINISH_LIGHT.range * UNIT_HEIGHT,
				FINISH_LIGHT.seconds
			)
		end
		strikeAll(run, from, GOLD, GOLD_SPARKS)
		Sfx.play("energyRelease")
		Sfx.play("explosion", { volume = 0.6, pitch = 1.2 })
	end
end

-- The real form change (power casts): a gold eruption off him, the aura flaring, sparks (blue on the
-- way to Core III) and embers.
local function erupt(run)
	local chest = run:chest()
	local view = VfxRecipe.viewScale(chest)
	VfxRecipe.kitAuraSpike(run, run.view, GOLD, run:designTime(), 0.3, 2, GOLD_DEEP)
	VfxRecipe.sparks(chest, 0.7 * view, 20, if toCoreThree(run) then BLUE_SPARKS else GOLD_SPARKS, Vector3.yAxis, view)
	VfxRecipe.embers(run, run:ground() + Vector3.new(0, 0.5, 0), run:scale() * view, nil, 10)
end

function def.event(run, event): boolean
	local kind = event.kind
	if kind == "Area" then
		if not run.memo.finished then
			run.memo.finished = true
			finisher(run, event)
		end
		return true
	elseif kind == "Form" then
		erupt(run)
		return true
	elseif kind == "Damage" and event.target and not event.dot then
		return true -- the payoff draws every hit
	elseif kind == "Buff" and event.target == run.unitIndex then
		return true -- his stacks: the aura already says it
	end
	return false
end

return def
