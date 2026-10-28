-- starless_burst (Tier 4): precise, clean, overwhelming magic, white and pale blue (never fiery). The
-- real cast fires a line from her through her target and 3 hexes past it (Area with shape LINE and
-- its cells, a Damage per enemy on it), 25% stronger for every earlier cast this fight, and shields
-- her (Shield), all at the Cast event (t = 0). Everything before 0 is anticipation; the beam fires
-- exactly on the real Area event. Staff in the right hand (LookKit `staff`: it runs up the hand's
-- +Y, so the arm forward keeps it upright and the arm back tips its head forward). Every movement is
-- the figure's pose offset (UnitView): her real position never changes.
-- Designed timeline (real seconds at full length; SEGMENTS):
--   -0.98  calm: the staff lifted upright before her, the left palm opening toward the target; the
--          callout (a pale-blue outline on her, a small ground ring)
--   -0.70  set: a pale magic circle opens in front of her ring by ring (2 rings, one more for each
--          earlier cast, at most 4), each wiping open with a soft click, two glyphs riding each; light
--          gathers at the staff's head (motes drawn in, a small growing orb); a faint shiver
--   -0.38  dead stillness: the circle holds, nothing moves, until -0.18
--   -0.18  a 0.12 s load dip: the staff drawn back
--   -0.06  the thrust's 0.06 s snap
--    0     THE BEAM, on the real hit: the staff thrust at the target (its head forward); one clean,
--          thin white beam from the circle's center along the real line (a pale glow around a white
--          core, thinning out by +0.32), a bright groove under it; on each enemy a small pale hit
--          star and sparks; hit-stop on the bodies; a clean release, a shake, the punch-in; the main
--          target knocked 2.5 studs and launched 0.8, the rest 1.5; the circle closes by +0.25
--   +0.06  the follow-through, held to +0.35
--   +0.60  the staff lowered upright again, expressionless; idle by +0.95
--   shield the game's shield bubble is hers (nothing added on top)
-- When the real window before the cast is shorter (Cinematic run.k < 1, at least the tier's 0.6),
-- the anticipation is laid out again for it (planOf): the stillness gives first, then the set, then
-- the coil, and only past that does everything but the load and the snap shrink evenly. The load,
-- the snap and everything after the hit never shrink.
-- Readable from the match camera (ViewScale: 1 at close cameras, up to 1.8 there): the circle, the
-- orb, the beam, the groove, the hit stars and the sparks grow with it.
-- Layers (tier 4, within its 34; peak ~17 in the set, ~12 at the beam, estimated): up to 4 ring
-- planes and 8 glyphs (4 rings / 4 glyphs when reduced), the orb (core + halo), ~4 motes in flight,
-- at the beam the beam (core + glow), the groove, a hit star and sparks per enemy, a light (not when
-- reduced); the callout's ring. Camera: a short push at the beam (tier 4 allows it). Poses:
-- PoseAnimator; hit feel: HitFeel; callout: UltimateCallout; sounds: Sfx.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RenderConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("RenderConfig"))

local FxKit = require(script.Parent.Parent.FxKit)
local HitFeel = require(script.Parent.Parent.HitFeel)
local ImpactEffects = require(script.Parent.Parent.ImpactEffects)
local PoseAnimator = require(script.Parent.Parent.PoseAnimator)
local Sfx = require(script.Parent.Parent.Sfx)
local UltimateCallout = require(script.Parent.Parent.UltimateCallout)
local UltimateKit = require(script.Parent.Parent.UltimateKit)
local VfxRecipe = require(script.Parent.Parent.VfxRecipe)

local Kit = UltimateKit
local rgb = Color3.fromRGB

-- The anticipation's segments in real seconds at full length, in order up to the hit (0.98 s in
-- all), and how far each may shrink when the window is short (`least`), in the order they give way
-- (the stillness first, then the set, then the coil).
local SEGMENTS = {
	coil = 0.28, -- windup start -> the staff upright, the palm open
	set = 0.32, -- the circle opening ring by ring, light gathering
	still = 0.2, -- dead stillness
	load = 0.12, -- the load dip
	snap = 0.06, -- the thrust's snap, ending on the hit
}
local LEAST = { still = 0.08, set = 0.12, coil = 0.14 }
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
	closed = 0.25, -- the circle closed
	beamEnd = 0.32,
	followEnd = 0.35, -- the follow-through held until here
	lower = 0.6, -- the staff lowered upright
	rest = 0.95, -- back to idle
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
local PALE = rgb(150, 205, 255)
local SOFT = rgb(205, 230, 255)
local CALLOUT = PALE
local SPARKS = ColorSequence.new(WHITE, PALE)
local RINGS = { base = 2, most = 4 } -- 2, one more per earlier cast this fight
local GLYPHS = { full = 2, reduced = 1 } -- per ring
local BEAM_WIDTH = 0.16 -- the white core, in unit heights: thin, not fat
local CAST_LIGHT = { brightness = 1.8, range = 1.2, seconds = 0.2 } -- range in unit heights
local UNIT_HEIGHT = RenderConfig.unitSize.Y
local STAFF_HEAD = 0.045 + 0.95 * 0.75 + 0.1 -- the staff's orb up the hand's +Y, in figure heights (LookKit)

-- The poses (PoseAnimator channels), about twice a realistic gesture: big, readable anime poses.
-- Every body pose names every body channel, so a held pose holds the whole body still.
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

-- Calm: the staff lifted upright before her (a small forward raise keeps it upright), the left palm
-- reaching toward the target where the circle will open.
local CALM = pose({
	lean = -4,
	twist = -10,
	tilt = 4,
	rightArm = 22,
	rightArmOut = 8,
	leftArm = 85,
	leftArmOut = 8,
	leftLeg = 10,
	rightLeg = -8,
	headPitch = -4,
})
-- The set: the palm pushed out further, the stance wider, still calm.
local SET = with(CALM, { leftArm = 92, lean = -6, leftLeg = 18, rightLeg = -14, crouch = 0.12 })
-- The load: the staff drawn back (more forward raise leans it back), the knees giving.
local LOAD = with(SET, { rightArm = 48, crouch = 0.25, lean = -10, twist = -18 })
-- The thrust: the arm swung back tips the staff's head forward at the target; the right shoulder
-- driving through, the left hand pulled back.
local THRUST = pose({
	crouch = 0.32,
	lean = 16,
	twist = 28,
	tilt = -4,
	rightArm = -58,
	rightArmOut = 6,
	leftArm = 20,
	leftArmOut = 30,
	leftLeg = 34,
	rightLeg = -30,
	headPitch = 6,
})
local FOLLOW = with(THRUST, { rightArm = -64, lean = 18, twist = 32 })
-- Lowered: the staff upright at her side again, expressionless.
local LOWER = pose({ rightArm = 8, leftArm = 4, headPitch = 4 })

-- The keys for a plan (planOf).
local function keyframes(T: Plan): { PoseAnimator.Keyframe }
	return {
		{ at = T.windup, pose = pose({}) },
		-- Calm, then the set held with a faint shiver, then in dead stillness.
		{ at = T.set, ease = "quadOut", pose = CALM },
		{ at = T.set + 0.1, ease = "quadOut", hold = math.max(0, T.still - T.set - 0.1), shiver = 0.8, pose = SET },
		{ at = T.still, ease = "hold", hold = T.load - T.still, pose = SET },
		-- The load dip.
		{ at = T.snap, ease = "quadOut", pose = LOAD },
		-- The thrust (a snap) on the hit; the follow-through held.
		{ at = T.finisher, ease = "snap", pose = THRUST },
		{ at = T.follow, ease = "quadOut", hold = T.followEnd - T.follow, pose = FOLLOW },
		-- The staff lowered, then idle.
		{ at = T.lower, ease = "inOut", hold = 0.15, pose = LOWER },
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

-- How many times she cast before this one in the fight (one more ring each time).
local function earlierCasts(run): number
	local count = 0
	local events = run.context.events
	for i = 1, (run.castIndex or 1) - 1 do
		local event = events[i]
		if event.kind == "Cast" and event.unit == run.unitIndex then
			count += 1
		end
	end
	return count
end

-- The staff's head now (its orb), else just past her right hand.
local function staffHead(run): Vector3
	local figure = run.view.figure
	local anchor = figure and figure.anchors and figure.anchors.rightHand
	if anchor and not figure.isModel then
		return (anchor * CFrame.new(0, run.view.part.Size.Y * STAFF_HEAD, 0)).Position
	end
	return run:hand("right")
end

-- The circle's frame: in front of her chest, facing her target.
local function circleFrame(run): CFrame
	local target = run:target()
	local chest = run:chest()
	local aim = if target then target.part.Position else chest + run:forward() * 10
	aim = Vector3.new(aim.X, chest.Y, aim.Z)
	local along = aim - chest
	along = if along.Magnitude > 1e-3 then along.Unit else run:forward()
	local at = chest + along * 1.8
	return CFrame.lookAt(at, at + along)
end

-- The magic circle: `rings` thin ring planes facing the target, opening one after another across
-- the set (each wiping open over 0.08 s with a soft click), glyphs riding each, all closing by
-- AFTER.closed.
local function openCircle(run, plan: Plan, rings: number)
	local s = run:scale()
	local view = VfxRecipe.viewScale(circleFrame(run).Position)
	local span = math.max(plan.still - plan.set - 0.05, 0.05)
	for i = 1, rings do
		local open = plan.set + (i - 1) / rings * span
		local diameter = (1.0 + i * 0.6) * s * view
		local color = if i % 2 == 0 then PALE else WHITE
		local spin = (if i % 2 == 0 then -1 else 1) * (1.6 + i * 0.3)
		local depth = -i * 0.04
		local function sizeAt(): number
			local t = run:designTime()
			local opening = Kit.easeOut((t - open) / 0.08)
			local closing = if t > 0 then 1 - Kit.easeIn(t / plan.closed) else 1
			return diameter * opening * closing
		end
		local ring = FxKit.textured("ring", color, "plane")
		Kit.live(run, open, plan.closed, "Block", color, function(part, _u)
			local d = math.max(0.05, sizeAt())
			part.Size = Vector3.new(d, d, 0.04)
			part.CFrame = circleFrame(run) * CFrame.new(0, 0, depth)
			part.Transparency = if ring then 0.1 else 0.7
		end, nil, ring)
		for g = 1, (if run.reduced then GLYPHS.reduced else GLYPHS.full) do
			Kit.block(run, open, plan.closed, SOFT, function()
				local angle = run:now() * spin + g * math.pi
				local r = sizeAt() / 2
				return circleFrame(run)
					* CFrame.new(math.cos(angle) * r, math.sin(angle) * r, depth - 0.02)
					* CFrame.Angles(0, 0, angle)
			end, function()
				return Vector3.new(0.2, 0.07, 0.03) * s * view
			end, function()
				return if sizeAt() < 0.1 then 1 else 0.1
			end, Enum.Material.Neon)
		end
		run:at(open, function()
			Sfx.play("magicChime", { pitch = 1.3 + 0.12 * i, volume = 0.35 })
		end)
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
			UltimateCallout.mark(run.view, CALLOUT, run:span(plan.windup, plan.finisher - plan.windup))
			openCircle(run, plan, math.min(RINGS.base + earlierCasts(run), RINGS.most))
			-- Light gathers at the staff's head through the set and holds in the stillness.
			run:at(plan.set, function()
				local view = VfxRecipe.viewScale(staffHead(run))
				Kit.orb(run, plan.set, plan.finisher, WHITE, function()
					return staffHead(run)
				end, function(u)
					return (0.15 + 0.35 * Kit.easeOut(u * 1.5)) * s * view
				end)
				Kit.converge(run, plan.set, plan.still, function()
					return staffHead(run)
				end, SOFT, 1.8 * s, if run.reduced then 4 else 8)
				Sfx.play("energyCharge", { pitch = 1.2, volume = 0.6 })
			end)
			-- The beam waits for the real Area event; should it never come, it still plays.
			run:at(plan.finisher + 0.05, function()
				if not run.memo.finished then
					run.memo.finished = true
					finisher(run, run:find("Area"))
				end
			end)
		end,
	},
}

-- The cast itself: no generic burst at her hands (the beam is the release).
function def.release(_run): boolean
	return true
end

-- Where the line ends: past the farthest of its cells (from the circle's center), else 3 hexes past
-- the target.
local function lineEnd(run, start: Vector3, event): Vector3
	local far, distance = nil, -1
	for _, cell in (event and event.cells) or {} do
		local at = run.context.toWorld(cell[1], cell[2])
		local d = (Vector3.new(at.X, start.Y, at.Z) - start).Magnitude
		if d > distance then
			far, distance = at, d
		end
	end
	if not far then
		local target = run:target()
		far = if target then target.part.Position else start + run:forward() * 12
	end
	local flat = Vector3.new(far.X, start.Y, far.Z)
	local along = flat - start
	along = if along.Magnitude > 1e-3 then along.Unit else run:forward()
	return flat + along * 1.7
end

-- The beam on the real hit: one thin white beam from the circle along the real line (a pale glow
-- around a white core, thinning out), a bright groove under it, a small hit star and sparks on each
-- enemy, a light at the circle; hit-stop on the bodies (0.07 s); a clean release, the shake, the
-- punch-in and a short push; the main target knocked 2.5 studs and launched 0.8, the rest 1.5.
finisher = function(run, event: any?)
	local start = circleFrame(run).Position
	local finish = lineEnd(run, start, event)
	local view = VfxRecipe.viewScale(start)
	local s = run:scale()
	Kit.beam(run, 0, AFTER.beamEnd, WHITE, PALE, function()
		return start
	end, function()
		return finish
	end, function(u)
		return BEAM_WIDTH * UNIT_HEIGHT * s * view * (1 - 0.85 * Kit.easeIn(u))
	end)
	local ground = run:ground()
	Kit.groove(run, 0, 0.8, PALE, ground, Vector3.new(finish.X, ground.Y, finish.Z), 0.3 * view)
	if not run.reduced then
		ImpactEffects.light(start, SOFT, CAST_LIGHT.brightness, CAST_LIGHT.range * UNIT_HEIGHT, CAST_LIGHT.seconds)
	end
	local main = run:target()
	local targets = run:targets()
	local held = { run.view }
	for _, target in targets do
		table.insert(held, target)
		local at = target.part.Position
		local hitView = VfxRecipe.viewScale(at)
		VfxRecipe.kitHitStar(at, UNIT_HEIGHT * 0.6 * hitView, PALE, hitView)
		VfxRecipe.sparks(at, 0.5 * hitView, 10, SPARKS, (finish - start).Unit, hitView)
	end
	HitFeel.hitStop(held, 0.07, { caster = run.view })
	for _, target in targets do
		HitFeel.react(target, start, if target == main then { final = true } else { knock = 1.5, tilt = 18 })
	end
	HitFeel.cameraShake(0.25, 0.3)
	HitFeel.punchIn(1)
	run:camera(0, 0.4, { key = "push", push = 1.4, focus = start, rise = 0.04, fall = 0.3 })
	Sfx.play("energyRelease", { pitch = 1.15 })
end

function def.event(run, event): boolean
	local kind = event.kind
	if kind == "Area" and event.shape == "LINE" then
		if not run.memo.finished then
			run.memo.finished = true
			finisher(run, event)
		end
		return true
	elseif kind == "Shield" and event.target == run.unitIndex then
		return false -- the shield bubble (CombatPlayback) is hers: nothing on top of it
	elseif kind == "Damage" and event.target and not event.dot then
		return true -- the beam draws every hit
	end
	return false
end

return def
