-- boiling_crown (Tier 5): a giant becoming a volcano. The real cast is a blast over everything within
-- 2 hexes of him (Area centered on him, a Damage per enemy) at the Cast event (t = 0); his aura keeps
-- ticking on its own (Damage with `aura`, left to its own effects). Everything before 0 is
-- anticipation; the eruption lands exactly on the real Area event. He is a store model: no limbs to
-- pose, only his whole body (Figure: a crouch is a dip, plus lean, twist, rise, tremble), so the
-- choreography is the sink, the tremble and the heave. Every movement is the figure's pose offset
-- (UnitView): his real position never changes.
-- Designed timeline (real seconds at full length; SEGMENTS):
--   -1.18  he goes still and sinks; steam thickens off his head; the screen dims a little; the
--          callout (an orange outline on him, a small ground ring)
--   -0.88  set: the heat builds: his steam turns from white to orange, a red-orange glow grows over
--          him, cracks glow and run outward through the ground; he trembles harder and harder; a
--          crackle of heat; the camera leans in, until -0.38
--   -0.38  stillness: the tremble stops dead, until -0.18
--   -0.18  a 0.12 s load dip: he sinks lower
--   -0.06  the heave's 0.06 s snap
--    0     THE ERUPTION, on the real hit: he heaves up and back; the eruption over the real area
--          (the steam recipe: core, steam clouds, one shock ring, sparks, light), large steam billows
--          thrown out in a ring from his body and a column rising over his head (all kept off the
--          camera's line to him), orange embers, a brief speed-lines flash; steam scalding up under
--          each enemy hit; hit-stop on the bodies; the explosion and the slam, a strong shake, the
--          punch-in, the camera pulling back; the enemies knocked back (the main one 2.5 studs and
--          launched 0.8, the rest 1.5)
--   +0.12  the top of the heave; he lands by +0.4, steam rolling out across the area
--   +0.9   settled; idle by +1.3
-- When the real window before the cast is shorter (Cinematic run.k < 1, at least the tier's 0.6),
-- the anticipation is laid out again for it (planOf): the stillness gives first, then the set, then
-- the sink, and only past that does everything but the load and the snap shrink evenly. The load,
-- the snap and everything after the hit never shrink.
-- Readable from the match camera (ViewScale: 1 at close cameras, up to 1.8 there): the steam
-- puffs, the cracks, the billows and the embers grow with it (the recipe's burst sizes itself).
-- Layers (tier 5, within its 44; peak ~24 at the eruption, estimated): the build's steam puffs and
-- glow (particles), 4 glowing cracks (2 when reduced), at the eruption the recipe's burst and
-- aftermath (core, clouds, one ring, sparks, light), up to 9 billows and a column (6 when reduced:
-- particles), embers, the speed-lines flash, steam columns under the enemies (particles); the
-- callout's ring. Camera: a dim through the build, a push in and a pull at the eruption (tier 5).
-- Poses: PoseAnimator; hit feel: HitFeel; callout: UltimateCallout; sounds: Sfx.

local UltimateKit = require(script.Parent.Parent.UltimateKit)
local HitFeel = require(script.Parent.Parent.HitFeel)
local ImpactEffects = require(script.Parent.Parent.ImpactEffects)
local PoseAnimator = require(script.Parent.Parent.PoseAnimator)
local Sfx = require(script.Parent.Parent.Sfx)
local UltimateCallout = require(script.Parent.Parent.UltimateCallout)
local VfxRecipe = require(script.Parent.Parent.VfxRecipe)

local Kit = UltimateKit
local rgb = Color3.fromRGB

-- The anticipation's segments in real seconds at full length, in order up to the hit (1.18 s in
-- all), and how far each may shrink when the window is short (`least`), in the order they give way
-- (the stillness first, then the set, then the sink).
local SEGMENTS = {
	sink = 0.3, -- windup start -> sunk, still
	set = 0.5, -- the heat building, trembling
	still = 0.2, -- stillness
	load = 0.12, -- the load dip
	snap = 0.06, -- the heave's snap, ending on the hit
}
local LEAST = { still = 0.08, set = 0.2, sink = 0.15 }
local SHRINK_ORDER = { "still", "set", "sink" }
local ORDER = { "sink", "set", "still", "load", "snap" }
local SNAPS = { load = true, snap = true } -- never shrink
local FULL = 0
for _, name in ORDER do
	FULL += SEGMENTS[name]
end

-- After the hit (design seconds = real seconds: never compressed).
local AFTER = {
	finisher = 0,
	apex = 0.12, -- the top of the heave
	land = 0.4,
	settle = 0.9,
	rest = 1.3,
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
		windup = design(real.sink),
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
local HOT = rgb(255, 140, 60)
local EMBER = rgb(255, 80, 40)
local CRACK = rgb(255, 110, 40)
local CALLOUT = HOT
local CRACKS = { full = 4, reduced = 2 }
-- The eruption's steam billows: at most this many unit heights once grown, at least this
-- transparent, and never within CAMERA_CLEAR studs of the camera's line to him (three billows on
-- that line once filled the close camera with white).
local BILLOW_CAP = 1.6
local BILLOW_START = 0.4
local CAMERA_CLEAR = 6

-- How far `point` is from the segment from `a` to `b`.
local function offLine(point: Vector3, a: Vector3, b: Vector3): number
	local along = b - a
	local t = math.clamp((point - a):Dot(along) / math.max(along:Dot(along), 1e-6), 0, 1)
	return (point - (a + along * t)).Magnitude
end

-- The poses (PoseAnimator channels). A store model takes only the whole-body channels (the crouch
-- as a dip, lean, twist, rise, tremble); the rest are named so a held pose holds still. About twice
-- a realistic heave.
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

local SINK = pose({ crouch = 0.35, lean = 5 })
local BUILD = pose({ crouch = 0.45, lean = 8 })
local LOAD = pose({ crouch = 0.6, lean = 10 })
-- The heave: thrown up and back.
local HEAVE = pose({ lean = -16, rise = 0.7 })
local SETTLE = pose({ crouch = 0.08, lean = -3 })

-- The keys for a plan (planOf).
local function keyframes(T: Plan): { PoseAnimator.Keyframe }
	return {
		{ at = T.windup, pose = pose({}) },
		{ at = T.set, ease = "inOut", pose = SINK },
		-- The build, trembling harder (a shiver through the set), then dead still.
		{ at = T.set + 0.15, ease = "quadOut", hold = math.max(0, T.still - T.set - 0.15), shiver = 2.4, pose = BUILD },
		{ at = T.still, ease = "hold", hold = T.load - T.still, pose = BUILD },
		{ at = T.snap, ease = "quadOut", pose = LOAD },
		-- The heave (a snap) on the hit, up to the apex, back down; then settled and idle.
		{ at = T.finisher, ease = "snap", pose = HEAVE },
		{ at = T.apex, ease = "quadOut", pose = { rise = 0.9 } },
		{ at = T.land, ease = "quadIn", pose = { rise = 0, crouch = 0.2, lean = -8 } },
		{ at = T.settle, ease = "inOut", hold = 0.1, pose = SETTLE },
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

-- The build's steam, thickening and heating from white to orange: a puff every 0.15 s (budget),
-- small and see-through, rising off his head so he stays visible.
local function steamBuild(run, plan: Plan)
	local t = plan.windup + 0.05
	local span = plan.still - plan.windup
	while t < plan.still do
		local heat = math.clamp((t - plan.windup) / span, 0, 1)
		run:at(t, function()
			local at = run:chest() + Vector3.new(0, run.view.part.Size.Y * 0.45, 0)
			ImpactEffects.burst("puff", at, Vector3.yAxis, {
				color = WHITE:Lerp(HOT, heat),
				count = if run.reduced then 2 else 3,
				size = (0.8 + 0.5 * heat) * VfxRecipe.viewScale(at),
				speed = { 2, 4 + heat * 3 },
				lifetime = { 0.6, 1 },
				spread = 40,
				transparency = 0.55,
			})
		end)
		t += 0.15
	end
end

-- Glowing cracks running outward through the ground from under him across the area, through the set
-- and fading after the eruption.
local function cracks(run, plan: Plan)
	local center, radius = run:area()
	local count = if run.reduced then CRACKS.reduced else CRACKS.full
	local view = VfxRecipe.viewScale(center)
	for i = 1, count do
		local angle = (i / count) * math.pi * 2 + math.random() * 0.5
		local reach = radius * (0.7 + 0.3 * math.random())
		local to = center + Vector3.new(math.cos(angle) * reach, 0, math.sin(angle) * reach)
		Kit.groove(run, plan.set + 0.05 * i, AFTER.settle, CRACK, center, to, 0.35 * view)
	end
end

local finisher: (any) -> () -- below

def.beats = {
	{
		at = planOf(1).windup, -- every plan starts its windup at the same design time (-FULL)
		run = function(run)
			local plan = planFor(run)
			UltimateCallout.mark(run.view, CALLOUT, run:span(plan.windup, plan.finisher - plan.windup))
			run:camera(plan.windup, plan.finisher + 0.4, { key = "dim", dim = 0.25, rise = 0.4, fall = 0.4 })
			steamBuild(run, plan)
			Sfx.play("energyCharge", { pitch = 0.6, volume = 0.6 })
			-- The heat building: the glow over him (stronger near the end), the cracks, the crackle.
			run:at(plan.set, function()
				local warm = VfxRecipe.energy(EMBER, HOT)
				VfxRecipe.aura(run, run.view, warm, 1.2, plan.set, (plan.still - plan.set) * 0.6)
				VfxRecipe.aura(
					run,
					run.view,
					warm,
					1.8,
					plan.set + (plan.still - plan.set) * 0.6,
					(plan.still - plan.set) * 0.4
				)
				cracks(run, plan)
				run:camera(
					plan.set,
					plan.finisher,
					{ key = "push", push = 2.6, focus = run:chest(), rise = 0.35, fall = 0.05 }
				)
				Sfx.play("fireCrackle", { pitch = 0.8, volume = 0.7 })
			end)
			-- The eruption waits for the real Area event; should it never come, it still plays.
			run:at(plan.finisher + 0.05, function()
				if not run.memo.finished then
					run.memo.finished = true
					finisher(run)
				end
			end)
		end,
	},
}

-- The cast itself: no generic burst (the eruption is the release, on the real area hit).
function def.release(_run): boolean
	return true
end

-- The eruption on the real hit (see the header). The steam wall stays see-through and off the
-- camera: each billow at most BILLOW_CAP unit heights after it grows, starting BILLOW_START
-- transparent, spawned clear of his body and thrown outward and sideways, none toward the camera and
-- none within CAMERA_CLEAR studs of the line from the camera to him; no second wave of steam (it
-- whited the screen). He stays visible through the whole ultimate.
finisher = function(run)
	local center, radius = run:area()
	local height = run.view.part.Size.Y * 2.6
	local theme = VfxRecipe.themes.steam
	VfxRecipe.burst(run, center, radius, { theme = theme })
	VfxRecipe.aftermath(run, center, radius, { theme = theme, smokeScale = 0.6 })
	local body = run.view.part.Position
	local bodySize = run.view.part.Size
	local view = VfxRecipe.viewScale(body)
	local billowSize = math.min(height * 0.55, BILLOW_CAP * VfxRecipe.UNIT_HEIGHT / 1.3) * view
	local camera = workspace.CurrentCamera
	local eye = if camera then camera.CFrame.Position else nil
	local toward = if eye then Vector3.new(eye.X - body.X, 0, eye.Z - body.Z) else Vector3.zero
	toward = if toward.Magnitude > 1e-3 then toward.Unit else Vector3.zero
	local function clear(from: Vector3, to: Vector3): boolean
		if not eye then
			return true
		end
		return offLine(from, eye, body) >= CAMERA_CLEAR and offLine(to, eye, body) >= CAMERA_CLEAR
	end
	local billows = if run.reduced then 6 else 9
	local throw = radius * 2.2
	for i = 1, billows do
		local angle = (i / billows) * math.pi * 2 + math.random() * 0.3
		local out = Vector3.new(math.cos(angle), 0.25, math.sin(angle)).Unit
		local flat = Vector3.new(out.X, 0, out.Z).Unit
		local from = body + flat * (bodySize.X * 0.5 + billowSize * 0.5)
		local to = from + out * throw * 0.6 -- about where it is when it has grown
		if flat:Dot(toward) < 0.25 and clear(from, to) then
			VfxRecipe.kitSteam(from, billowSize, 1, out, throw, 8, BILLOW_START)
		end
	end
	-- The column: rising from above his head (never over his body).
	local top = body + Vector3.new(0, bodySize.Y * 0.5 + billowSize * 0.5, 0)
	if clear(top, top + Vector3.new(0, height * 0.6, 0)) then
		VfxRecipe.kitSteam(top, billowSize, 2, Vector3.yAxis, height * 1.2, 15, BILLOW_START + 0.1)
	end
	VfxRecipe.embers(
		run,
		center + Vector3.new(0, 1, 0),
		run:scale() * 1.4 * view,
		VfxRecipe.energy(EMBER, HOT).ember,
		22
	)
	VfxRecipe.kitSpeedLines(run:chest(), bodySize.Y * 1.5, HOT, 0.2)
	-- The hits.
	local main = run:target()
	local targets = run:targets()
	local held = { run.view }
	for _, target in targets do
		table.insert(held, target)
	end
	HitFeel.hitStop(held, 0.07, { caster = run.view })
	for _, target in targets do
		HitFeel.react(target, body, if target == main then { final = true } else { knock = 1.5, tilt = 18 })
	end
	HitFeel.cameraShake(0.4, 0.4)
	HitFeel.punchIn(1)
	run:camera(0, 0.6, { key = "pull", push = -2.2, focus = run:chest(), rise = 0.04, fall = 0.45 })
	Sfx.play("explosion")
	Sfx.play("groundSlam", { volume = 0.8 })
end

function def.event(run, event): boolean
	local kind = event.kind
	if kind == "Area" then
		if not run.memo.finished then
			run.memo.finished = true
			finisher(run)
		end
		return true
	elseif kind == "Damage" and event.target and not event.dot and not event.aura then
		local view = run.context.views[event.target]
		if view then
			-- Steam scalding up around each unit caught in it.
			local at = view.part.Position - Vector3.new(0, view.part.Size.Y * 0.5, 0)
			VfxRecipe.steamColumn(at, 0.9 * run:scale() * VfxRecipe.viewScale(at))
		end
		return true
	end
	return false -- aura ticks and the rest keep their own effects
end

return def
