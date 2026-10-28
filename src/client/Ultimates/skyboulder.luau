-- skyboulder (Tier 3): the pitcher's wind-up and the rock spray. The real cast hits a cone toward his
-- target (Area with its cells, a Damage per enemy, hardest next to him) and hardens his armor (a Buff
-- on him), all at the Cast event (t = 0). Everything before 0 is anticipation; the fragments land on
-- the real hit. He is a store model: no limbs to pose (and no arm to trail), only his whole body
-- (Figure: a crouch is a dip, plus lean, twist, rise, lunge), so the wind-up is his whole body turning
-- far away and whipping back. Every movement is the figure's pose offset (UnitView): his real
-- position never changes.
-- Designed timeline (real seconds at full length; SEGMENTS):
--   -0.93  a boulder grows at his throwing side; the callout (an earthen outline on him, a ground
--          ring)
--   -0.65  he crushes it: dust bursting off it, chips flying, a slam; then the wind-up: he turns far
--          away, leans back and sinks, shivering, until -0.30
--   -0.30  stillness, until -0.18
--   -0.18  a 0.12 s load dip: turned further, lower
--   -0.06  the throw's 0.06 s snap: he whips around and lunges, the fragments flying out over the
--          cone's real cells (one each, two on the nearest), the nearest ones the biggest
--    0     THE SPRAY, on the real hit: the fragments land; dust bursting where each lands (bigger
--          nearer him), one shock ring and a hit star on the nearest, sparks on the near cells; hit-
--          stop on the bodies; the rocks clatter, a shake, the punch-in; the main target knocked 2.5
--          studs and launched 0.8, the rest 1.5
--   +0.06  the follow-through, held to +0.35
--   +0.6   he stands tall; his real armor buff flares as an earthen glow off him; idle by +0.9
-- When the real window before the cast is shorter (Cinematic run.k < 1, at least the tier's 0.6),
-- the anticipation is laid out again for it (planOf): the stillness gives first, then the wind-up,
-- then the boulder, and only past that does everything but the load and the snap shrink evenly. The
-- load, the snap and everything after the hit never shrink.
-- Readable from the match camera (ViewScale: 1 at close cameras, up to 1.8 there): the boulder, the
-- fragments, the dust, the ring, the hit star and the sparks grow with it.
-- Layers (tier 3, within its 26; peak ~13 at the spray, estimated): the boulder (1), its dust and
-- chips, at the throw one fragment per cone cell (+1 on the nearest; ~6-8), at the spray dust per
-- cell and sparks (particles), one shock ring, a hit star, the armor glow (particles); the callout's
-- ring. Poses: PoseAnimator; hit feel: HitFeel; callout: UltimateCallout; sounds: Sfx.

local UltimateKit = require(script.Parent.Parent.UltimateKit)
local HitFeel = require(script.Parent.Parent.HitFeel)
local PoseAnimator = require(script.Parent.Parent.PoseAnimator)
local Sfx = require(script.Parent.Parent.Sfx)
local UltimateCallout = require(script.Parent.Parent.UltimateCallout)
local UnitView = require(script.Parent.Parent.UnitView)
local VfxRecipe = require(script.Parent.Parent.VfxRecipe)

local Kit = UltimateKit
local rgb = Color3.fromRGB

-- The anticipation's segments in real seconds at full length, in order up to the hit (0.93 s in
-- all), and how far each may shrink when the window is short (`least`), in the order they give way
-- (the stillness first, then the wind-up, then the boulder).
local SEGMENTS = {
	boulder = 0.28, -- windup start -> the boulder grown at his side
	wind = 0.35, -- crushed, then turned far away, shivering
	still = 0.12, -- stillness
	load = 0.12, -- the load dip
	snap = 0.06, -- the throw's snap, ending on the hit
}
local LEAST = { still = 0.05, wind = 0.12, boulder = 0.14 }
local SHRINK_ORDER = { "still", "wind", "boulder" }
local ORDER = { "boulder", "wind", "still", "load", "snap" }
local SNAPS = { load = true, snap = true } -- never shrink
local FULL = 0
for _, name in ORDER do
	FULL += SEGMENTS[name]
end

-- After the hit (design seconds = real seconds: never compressed).
local AFTER = {
	finisher = 0,
	follow = 0.06, -- the follow-through pose reached
	followEnd = 0.35, -- the follow-through held until here
	stand = 0.6, -- standing tall
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
		windup = design(real.boulder),
		wind = design(real.wind),
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

local STONE = rgb(140, 126, 110)
local EARTH = rgb(200, 160, 90)
local DUST = UltimateKit.DUST
local CALLOUT = EARTH
local SPARKS = ColorSequence.new(rgb(255, 240, 210), EARTH)
local STEP = 0.45 -- studs (normal size) he lunges into the throw (`lunge`)
local UNIT_HEIGHT = VfxRecipe.UNIT_HEIGHT

-- The poses (PoseAnimator channels). A store model takes only the whole-body channels (the crouch
-- as a dip, lean, twist, rise, lunge); the rest are named so a held pose holds still. About twice a
-- realistic throw.
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

local CRUSH = pose({ crouch = 0.25, lean = 8, twist = 12 })
local WIND = pose({ crouch = 0.35, lean = -12, twist = -62 })
local LOAD = pose({ crouch = 0.45, lean = -15, twist = -72 })
local THROW = pose({ crouch = 0.1, lean = 18, twist = 46 })
local FOLLOW = pose({ crouch = 0.15, lean = 14, twist = 38 })
local STAND = pose({ lean = -6, rise = 0.1 })

-- The keys for a plan (planOf) and a lunge of `step` studs (normal size).
local function keyframes(T: Plan, step: number): { PoseAnimator.Keyframe }
	return {
		{ at = T.windup, pose = with(pose({}), { lunge = 0 }) },
		{ at = T.wind, ease = "quadOut", pose = CRUSH },
		-- The wind-up, held shivering, then in stillness.
		{
			at = T.wind + 0.12,
			ease = "quadOut",
			hold = math.max(0, T.still - T.wind - 0.12),
			shiver = 1.2,
			pose = WIND,
		},
		{ at = T.still, ease = "hold", hold = T.load - T.still, pose = WIND },
		{ at = T.snap, ease = "quadOut", pose = LOAD },
		-- The throw (a snap) on the hit, a lunge into it; the follow-through held.
		{ at = T.finisher, ease = "snap", pose = THROW },
		{ at = T.snap, pose = { lunge = 0 } },
		{ at = T.finisher, ease = "snap", pose = { lunge = step } },
		{ at = T.follow, ease = "quadOut", hold = T.followEnd - T.follow, pose = FOLLOW },
		{ at = T.followEnd, ease = "hold", pose = { lunge = step } },
		-- Standing tall, back to where he stands; then idle.
		{ at = T.stand, ease = "inOut", hold = 0.1, pose = STAND },
		{ at = T.stand, ease = "inOut", pose = { lunge = 0 } },
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

-- Beside him, at his throwing side.
local function side(run): Vector3
	local forward = run:forward()
	return run:chest() + Vector3.new(-forward.Z, 0, forward.X) * run.view.part.Size.X * 0.7
end

-- The cone's cells as world points, and the one nearest him.
local function cells(run, area: any?): ({ Vector3 }, Vector3?)
	local points = {}
	local origin = run:ground()
	local nearest, best = nil, math.huge
	for _, cell in (area and area.cells) or {} do
		local at = run.context.toWorld(cell[1], cell[2])
		table.insert(points, at)
		local d = (at - origin).Magnitude
		if d < best then
			nearest, best = at, d
		end
	end
	return points, nearest
end

-- How near `at` is to him (1 next to him, down to 0.3 far away): nearer rocks are bigger.
local function nearness(run, at: Vector3): number
	return math.clamp(1 - (at - run:ground()).Magnitude / (UNIT_HEIGHT * 2.6), 0.3, 1)
end

-- The fragments: thrown at the snap from his side, one over each cell of the cone (two on the
-- nearest), arcing and landing on the hit (t = 0).
local function throw(run, plan: Plan)
	local area = run:find("Area")
	local points, nearest = cells(run, area)
	local from = side(run)
	local s = run:scale()
	for _, at in points do
		local near = nearness(run, at)
		local view = VfxRecipe.viewScale(at)
		for k = 1, (if run.reduced or at ~= nearest then 1 else 2) do
			local offset = Vector3.new((math.random() - 0.5) * 1.6, 0, (math.random() - 0.5) * 1.6)
			local spin = math.random() * 5
			Kit.block(run, plan.snap, 0.05, STONE, function()
				local u = math.clamp((run:designTime() - plan.snap) / math.max(-plan.snap, 1e-3), 0, 1)
				local p = from:Lerp(at + offset + Vector3.new(0, 0.4, 0), u)
					+ Vector3.new(0, math.sin(u * math.pi) * 1.2, 0)
				return CFrame.new(p) * CFrame.Angles(spin * u, spin, 0)
			end, function()
				return Vector3.one * (0.35 + 0.6 * near) * (if k == 1 then 1 else 0.7) * s * view
			end, function()
				return 0
			end, Enum.Material.Slate)
		end
	end
	Sfx.play("whooshHeavy", { pitch = 1.1 })
end

local finisher: (any, any?) -> () -- below

def.beats = {
	{
		at = planOf(1).windup, -- every plan starts its windup at the same design time (-FULL)
		run = function(run)
			local plan = planFor(run)
			local s = run:scale()
			run:face(run:target())
			UltimateCallout.mark(run.view, CALLOUT, run:span(plan.windup, plan.finisher - plan.windup))
			-- The boulder growing at his side, then crushed.
			local view = VfxRecipe.viewScale(side(run))
			Kit.block(run, plan.windup, plan.wind + 0.05, STONE, function(u)
				return CFrame.new(side(run)) * CFrame.Angles(u, u * 2, 0)
			end, function(u)
				local grow = Kit.easeOut(math.min(1, u * 2.5))
				return Vector3.one * 1.6 * grow * (1 - 0.5 * Kit.easeIn(math.max(0, u - 0.7) / 0.3)) * s * view
			end, function(u)
				return if u > 0.9 then (u - 0.9) * 10 else 0
			end, Enum.Material.Slate)
			run:at(plan.wind, function()
				local at = side(run)
				local ground = at - Vector3.new(0, run.view.part.Size.Y * 0.5, 0)
				VfxRecipe.kitDust(ground, UNIT_HEIGHT * 0.55 * s * VfxRecipe.viewScale(ground), 2, 0.6)
				VfxRecipe.debris(
					at - Vector3.new(0, 0.5, 0),
					if run.reduced then 2 else 3,
					0.3 * s,
					DUST:Lerp(STONE, 0.6),
					1.5
				)
				Sfx.play("groundSlam", { volume = 0.6 })
			end)
			run:at(plan.snap, function()
				throw(run, plan)
			end)
			-- The spray waits for the real Area event; should it never come, it still plays.
			run:at(plan.finisher + 0.05, function()
				if not run.memo.finished then
					run.memo.finished = true
					finisher(run, run:find("Area"))
				end
			end)
		end,
	},
}

-- The cast itself: no generic burst (the throw is the release).
function def.release(_run): boolean
	return true
end

-- The spray on the real hit: dust where each fragment lands (bigger nearer him), one shock ring and a
-- hit star on the nearest, sparks on the near cells; hit-stop on the bodies (0.07 s); the clatter, the
-- shake, the punch-in; the main target knocked 2.5 studs and launched 0.8, the rest 1.5.
finisher = function(run, area: any?)
	local s = run:scale()
	local points, nearest = cells(run, area)
	for _, at in points do
		local near = nearness(run, at)
		local view = VfxRecipe.viewScale(at)
		VfxRecipe.kitDust(
			at,
			(0.35 + 0.35 * near) * UNIT_HEIGHT * s * view,
			if at == nearest and not run.reduced then 2 else 1,
			0.6
		)
		if near > 0.6 then
			VfxRecipe.sparks(at + Vector3.new(0, 0.5, 0), 0.5 * near * view, 10, SPARKS, Vector3.yAxis, view)
		end
	end
	if nearest then
		local view = VfxRecipe.viewScale(nearest)
		VfxRecipe.meshRing(nearest, UNIT_HEIGHT * 0.6 * s * view, EARTH, 0.35, 0.3)
		VfxRecipe.kitHitStar(nearest + Vector3.new(0, UNIT_HEIGHT * 0.3, 0), UNIT_HEIGHT * 0.7 * view, EARTH, view)
	end
	local main = run:target()
	local targets = run:targets()
	local held = { run.view }
	for _, target in targets do
		table.insert(held, target)
	end
	HitFeel.hitStop(held, 0.07, { caster = run.view })
	for _, target in targets do
		HitFeel.react(target, run:chest(), if target == main then { final = true } else { knock = 1.5, tilt = 18 })
	end
	HitFeel.cameraShake(0.2, 0.3)
	HitFeel.punchIn(1)
	Sfx.play("rockDebris")
	Sfx.play("impactHeavy", { volume = 0.6 })
end

function def.event(run, event): boolean
	local kind = event.kind
	if kind == "Area" and event.cells then
		if not run.memo.finished then
			run.memo.finished = true
			finisher(run, event)
		end
		return true
	elseif kind == "Buff" and event.target == run.unitIndex then
		-- His armor hardening: an earthen glow flaring off him as he stands tall (no ring: one at his
		-- feet would fall on the callout's).
		run:at(AFTER.stand, function()
			VfxRecipe.aura(run, run.view, VfxRecipe.energy(EARTH), 0.9, AFTER.stand, 0.35)
		end)
		return true
	elseif kind == "Damage" and event.target and not event.dot then
		return true -- the spray draws every hit
	end
	return false
end

return def
