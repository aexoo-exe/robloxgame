-- titanheart (Tier 3): lightning strike and steam reveal. His real cast is one heavy hit on his
-- target (a Damage) at the Cast event (t = 0), in either form. The shift into the titan is a real
-- form change when his health drops (not a cast: def.shift), and back to human when the titan's pool
-- breaks; both play as shifts. Everything before 0 is anticipation; the blow lands exactly on the
-- real hit. Bare fists: the punching hand carries a short trail. Every movement is the figure's pose
-- offset (UnitView): his real position never changes.
-- Cast (real seconds at full length; SEGMENTS):
--   -0.85  he plants, steam venting off him; the callout (a yellow outline on him, a ground ring)
--   -0.60  set: the fist drawn far back, the shoulder turned away, low; steam pouring off him; a
--          shiver of strain, until -0.30
--   -0.30  stillness, until -0.18
--   -0.18  a 0.12 s load dip
--   -0.06  the blow's 0.06 s snap
--    0     THE BLOW, on the real hit: the fist thrown through the target (a short trail) with a step
--          into it; a steam-white hit star, a column of steam scalding up, a crack along the blow,
--          dust, one shock ring, sparks; hit-stop on the bodies; the boom, a shake, the punch-in; the
--          target knocked 2.5 studs and launched 0.8
--   +0.06  the follow-through, held to +0.35; recovered by +0.6, idle by +0.9
-- When the real window before the cast is shorter (Cinematic run.k < 1, at least the tier's 0.6),
-- the anticipation is laid out again for it (planOf): the stillness gives first, then the set, then
-- the plant, and only past that does everything but the load and the snap shrink evenly. The load,
-- the snap and everything after the hit never shrink.
-- Shift into the titan (the real form change, no anticipation):
--    0     his hand to his mouth (no blood); 2-3 big yellow lightning bolts strike down on him from
--          the sky, a beat apart (each a chain of short bolts, VfxRecipe.kitBolts); a yellow core and
--          a small light where they land, one yellow shock ring; steam billows burst out at his feet
--          and pale steam rises as the titan emerges; he roars, arms wide; the crack and the boom, a
--          shake. (No full-screen impact frame: the quality bar keeps every effect off the screen.)
-- Shift back to human:
--    0     a steam burst; the giant collapses into steam and he stumbles out
-- Readable from the match camera (ViewScale: 1 at close cameras, up to 1.8 there): the trail, the
-- hit star, the steam, the crack, the dust, the ring, the sparks and the shift's core grow with it.
-- Layers (tier 3, within its 26; cast peak ~11 at the blow, shift peak ~15, estimated): the cast's
-- steam puffs (particles), at the blow a hit star, a steam column, dust, sparks (particles), the
-- crack (1), one shock ring; at the shift 2-3 bolt chains (particles), a core (2), a light (not when
-- reduced), one ring, 4 billows (3 when reduced), steam puffs; the fist trail (BladeTrail); the
-- callout's ring. Poses: PoseAnimator; hit feel: HitFeel; callout: UltimateCallout; sounds: Sfx.

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

-- The anticipation's segments in real seconds at full length, in order up to the hit (0.85 s in
-- all), and how far each may shrink when the window is short (`least`), in the order they give way
-- (the stillness first, then the set, then the plant).
local SEGMENTS = {
	plant = 0.25, -- windup start -> planted
	set = 0.3, -- the fist drawn back, shivering
	still = 0.12, -- stillness
	load = 0.12, -- the load dip
	snap = 0.06, -- the blow's snap, ending on the hit
}
local LEAST = { still = 0.05, set = 0.1, plant = 0.12 }
local SHRINK_ORDER = { "still", "set", "plant" }
local ORDER = { "plant", "set", "still", "load", "snap" }
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
	recover = 0.6, -- recovered where he stands
	rest = 0.9, -- back to idle
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
		windup = design(real.plant),
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
local BOLT = rgb(255, 230, 90)
local STEAM = rgb(245, 240, 232)
local CRACK = rgb(70, 60, 52)
local CALLOUT = BOLT
local STEAM_THEME = VfxRecipe.themes.steam
local TRAIL = ColorSequence.new({
	ColorSequenceKeypoint.new(0, WHITE),
	ColorSequenceKeypoint.new(0.5, rgb(255, 245, 200)),
	ColorSequenceKeypoint.new(1, BOLT),
})
local SPARKS = ColorSequence.new(WHITE, BOLT)
local STRIKE_HEIGHT = 18 -- studs above him the transform's bolts start
local STEP = 0.35 -- studs (normal size) he steps into the blow (`lunge`)
local SHIFT_LIGHT = { brightness = 1.8, range = 1.5, seconds = 0.3 } -- range in unit heights
local UNIT_HEIGHT = RenderConfig.unitSize.Y

local def = {}

def.shiftLinger = 1.2

-- The poses (PoseAnimator channels), about twice a realistic punch: big, readable anime poses.
-- Every body pose names every body channel, so a held pose holds the whole body still. `lunge` (the
-- step into the blow) runs on keys of its own.
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

-- Planted: feet wide, a little low, fists up.
local PLANT = pose({
	crouch = 0.2,
	lean = 6,
	rightArm = 40,
	rightArmOut = 15,
	leftArm = 50,
	leftArmOut = 10,
	leftLeg = 24,
	rightLeg = -22,
})
-- The draw: the fist far back, the shoulder turned away, low.
local DRAW = pose({
	crouch = 0.42,
	lean = -8,
	twist = -56,
	rightArm = -50,
	rightArmOut = 20,
	leftArm = 70,
	leftArmOut = 10,
	leftLeg = 38,
	rightLeg = -34,
	headYaw = 30,
})
local LOAD = with(DRAW, { crouch = 0.52, twist = -64, rightArm = -62 })
-- The blow: the fist thrown straight through, the body turning hard into it, a long stride.
local BLOW = pose({
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
local FOLLOW = with(BLOW, { lean = 20, twist = 46 })
-- Recovered: upright, heavy, arms loose.
local RECOVER = pose({ crouch = 0.1, lean = 4, rightArm = 10, leftArm = 10, headPitch = 8 })

-- The keys for a plan (planOf) and a step of `step` studs (normal size) into the blow.
local function keyframes(T: Plan, step: number): { PoseAnimator.Keyframe }
	return {
		{ at = T.windup, pose = with(pose({}), { lunge = 0 }) },
		{ at = T.set, ease = "quadOut", pose = PLANT },
		-- The draw held shivering, then in stillness.
		{ at = T.set + 0.1, ease = "quadOut", hold = math.max(0, T.still - T.set - 0.1), shiver = 1.6, pose = DRAW },
		{ at = T.still, ease = "hold", hold = T.load - T.still, pose = DRAW },
		{ at = T.snap, ease = "quadOut", pose = LOAD },
		-- The blow (a snap) on the hit, a step into it; the follow-through held.
		{ at = T.finisher, ease = "snap", pose = BLOW },
		{ at = T.snap, pose = { lunge = 0 } },
		{ at = T.finisher, ease = "snap", pose = { lunge = step } },
		{ at = T.follow, ease = "quadOut", hold = T.followEnd - T.follow, pose = FOLLOW },
		{ at = T.followEnd, ease = "hold", pose = { lunge = step } },
		-- Recovered, stepping back to where he stands; then idle.
		{ at = T.recover, ease = "inOut", hold = 0.1, pose = RECOVER },
		{ at = T.recover, ease = "inOut", pose = { lunge = 0 } },
		{ at = T.rest, ease = "inOut", pose = pose({}) },
	}
end

-- The shifts (no anticipation: the real form change happens on its own), in the old channel-track
-- format run:pose plays.
local ROAR = {
	rightArm = { { 0, 150 }, { 0.15, 150 }, { 0.5, 30 }, { 0.9, 0 } },
	leftArm = { { 0, 0 }, { 0.5, 30 }, { 0.9, 0 } },
	leftArmOut = { { 0.3, 0 }, { 0.5, 60 }, { 0.9, 0 } },
	rightArmOut = { { 0.3, 0 }, { 0.5, 60 }, { 0.9, 0 } },
	lean = { { 0, 0 }, { 0.3, -18, "back" }, { 0.8, -6 }, { 1.1, 0 } },
	tremble = { { 0.3, 0 }, { 0.35, 1.5 }, { 0.8, 1.5 }, { 0.85, 0, "hold" } },
}
local STUMBLE = {
	lean = { { 0, 0 }, { 0.2, 18, "out" }, { 0.45, -6 }, { 0.8, 0 } },
	crouch = { { 0, 0.2 }, { 0.3, 0.1 }, { 0.8, 0 } },
	leftArm = { { 0, 40 }, { 0.5, 20 }, { 0.8, 0 } },
}

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

-- Steam venting at `at`: pale puffs rising and spreading (the recipe's steam), `size` studs.
local function steamBurst(at: Vector3, count: number, size: number)
	VfxRecipe.smoke(at, size * 1.2, math.max(1, math.ceil(count / 2)), STEAM_THEME.smoke, STEAM_THEME.smokeTransparency)
end

-- The fist's trail (BladeTrail on the bare hand), made at the windup. Gone once it has faded.
local function attachFist(run)
	if run.memo.fist then
		return
	end
	local trail = BladeTrail.attach(run.view, { hand = "right", from = 0, to = 0.12, viewScale = true })
	trail:add("blow", { colors = TRAIL, lifetime = 0.16 })
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
			trail:enable("blow")
		else
			trail:disable("blow")
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
			-- Steam venting off him through the plant and the set; it stops for the stillness.
			local t = plan.windup + 0.04
			while t < plan.still do
				run:at(t, function()
					local at = run:chest()
					steamBurst(at, if run.reduced then 2 else 4, 0.7 * VfxRecipe.viewScale(at))
				end)
				t += 0.11
			end
			Sfx.play("windGust", { pitch = 0.7, volume = 0.5 })
			run:at(plan.snap - 0.01, function()
				setTrail(run, true)
			end)
			run:at(AFTER.trailOff, function()
				setTrail(run, false)
			end)
			-- The blow waits for the real hit; should it never come, it still plays.
			run:at(plan.finisher + 0.05, function()
				if not run.memo.finished then
					run.memo.finished = true
					finisher(run, run:target())
				end
			end)
		end,
	},
}

-- The cast itself: no generic burst (the blow is the release).
function def.release(_run): boolean
	return true
end

-- The blow on the real hit (see the header).
finisher = function(run, target: any?)
	local s = run:scale()
	local hit = if target and target.part.Parent
		then target.part.Position
		else run:chest() + run:forward() * UNIT_HEIGHT
	local view = VfxRecipe.viewScale(hit)
	local floor = Vector3.new(hit.X, run:ground().Y, hit.Z)
	local forward = run:forward()
	VfxRecipe.kitHitStar(hit, UNIT_HEIGHT * 0.9 * view, STEAM:Lerp(BOLT, 0.25), view)
	VfxRecipe.sparks(hit, 0.6 * view, 12, SPARKS, forward, view)
	VfxRecipe.steamColumn(floor, s * view)
	VfxRecipe.kitDust(floor, UNIT_HEIGHT * 0.55 * s * view, if run.reduced then 1 else 2, 0.6)
	VfxRecipe.meshRing(floor, UNIT_HEIGHT * 0.6 * s * view, STEAM, 0.35, 0.3)
	Kit.groove(run, 0, 0.9, CRACK, floor, floor + forward * UNIT_HEIGHT * 1.2 * view, 0.4 * view)
	local held = { run.view }
	if target then
		table.insert(held, target)
	end
	HitFeel.hitStop(held, 0.07, { caster = run.view })
	if target then
		HitFeel.react(target, run:chest(), { final = true })
	end
	HitFeel.cameraShake(0.2, 0.3)
	HitFeel.punchIn(1)
	Sfx.play("impactHeavy")
	Sfx.play("groundSlam", { volume = 0.6 })
end

function def.event(run, event): boolean
	if event.kind == "Damage" and event.target and not event.dot then
		if not run.memo.finished then
			run.memo.finished = true
			finisher(run, run.context.views[event.target])
		end
		return true
	end
	return false
end

-- The real form change: into the titan (lightning and steam) or back (a collapse into steam).
function def.shift(run, event): boolean
	local ground = run:ground()
	local height = run.view.part.Size.Y
	local view = VfxRecipe.viewScale(ground)
	if (event.formIndex or 1) >= 2 then
		run:pose(ROAR)
		local now = run:designTime()
		-- The strike: 2-3 big yellow bolts from high above (STRIKE_HEIGHT: inside the match camera's
		-- view, not above it) clearly hitting him, a beat apart, each from a slightly different point
		-- in the sky; chains of short bolts (kitBolts), so no bolt is a huge sprite.
		local strikes = if run.reduced then 2 else 3
		local land = ground + Vector3.new(0, height * 0.5, 0)
		for i = 1, strikes do
			run:at(now + 0.07 * (i - 1), function()
				local angle = (i / strikes) * math.pi * 2 + math.random() * 0.6
				local sky = ground + Vector3.new(math.cos(angle) * 2, STRIKE_HEIGHT, math.sin(angle) * 2)
				VfxRecipe.kitBolts(sky, land, BOLT, 1, 0.4, 1.2, 2.2)
				if i == 1 then
					-- Where it lands: a yellow core (behind him as the camera sees it), one ring, a light.
					local coreAt = land
					local camera = workspace.CurrentCamera
					if camera then
						local away = land - camera.CFrame.Position
						away = Vector3.new(away.X, 0, away.Z)
						if away.Magnitude > 1e-3 then
							coreAt += away.Unit * 0.8
						end
					end
					ImpactEffects.ball(coreAt, BOLT:Lerp(WHITE, 0.3), UNIT_HEIGHT * 1.1 * view, 0.18)
					VfxRecipe.meshRing(ground, UNIT_HEIGHT * 0.8 * view, BOLT, 0.4, 0.3)
					if not run.reduced then
						ImpactEffects.light(
							land,
							BOLT,
							SHIFT_LIGHT.brightness,
							SHIFT_LIGHT.range * UNIT_HEIGHT,
							SHIFT_LIGHT.seconds
						)
					end
					HitFeel.cameraShake(0.2, 0.35)
					Sfx.play("lightningCrack")
					Sfx.play("explosion", { volume = 0.7 })
				end
			end)
		end
		-- Steam billows bursting out at his feet as the titan emerges (few and see-through: at the
		-- match camera more of them covered the board).
		local billows = if run.reduced then 3 else 4
		for i = 1, billows do
			local angle = (i / billows) * math.pi * 2 + math.random() * 0.4
			local out = Vector3.new(math.cos(angle), 0.35, math.sin(angle)).Unit
			VfxRecipe.kitSteam(ground + Vector3.new(0, height * 0.3, 0), height * 0.6, 1, out, 7, 10, 0.4)
		end
		for i = 0, 1 do
			run:at(now + 0.1 + i * 0.2, function()
				steamBurst(ground + Vector3.new(0, 1 + 1.5 * i, 0), 4, 2 * view)
			end)
		end
	else
		run:pose(STUMBLE)
		-- The giant collapses into steam.
		ImpactEffects.ball(run:chest(), STEAM, UNIT_HEIGHT * 0.9 * view, 0.15)
		steamBurst(run:chest(), 10, 2 * view)
		Sfx.play("windGust", { pitch = 0.8 })
	end
	return true
end

return def
