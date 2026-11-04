-- frozen_moment (Tier 4): everything stops, and all the knives land at once. The real cast stuns
-- every enemy within 2 hexes of him at the Cast event (AreaStun, then a Stun on each); when the stun
-- ends (d = 1 / 1.5 / 2 s by star level) each of them takes a knife (a Damage event marked stunEnd)
-- and he heals for part of it (Heal). Everything before 0 is anticipation; the knives land on the
-- first real stun-end hit (the finisher).
-- Designed timeline (real seconds at full length; SEGMENTS; d = the real stun):
--   -0.98  his arms flung wide, chest out; a small gold sphere around him, a clock under him, its
--          hands ticking; the callout (a gold outline on him, a ground ring)
--   -0.68  set: held wide, shivering, the clock ticking, until -0.33
--   -0.33  stillness, until -0.18
--   -0.18  a 0.12 s load: the arms drawn in, lower
--   -0.06  the 0.06 s snap: arms thrown wide, ending on the cast
--    0     TIME STOPS, on the real cast: the sphere snaps out over the area, the clock grows over it
--          and its hands stop, the colour drains (the dim) until d; a gold glint on each frozen enemy
--   +0.12  he moves freely: four flicks (+0.12, +0.28, +0.44, +0.60), alternating hands; a knife
--          appears in the air in front of each frozen enemy, pointed at it
--   d-0.30 stillness, his hand raised, until d-0.12
--   d-0.12 a 0.06 s load, then the 0.06 s snap (d-0.06): the flick that sends every knife in
--    d     THE KNIVES LAND, on the first real stun-end hit: a steel hit star and sparks on each,
--          hit-stop on the bodies, a shake, the punch-in; the colour back; the healed motes drift
--          into him on the real Heal
--   d+0.12 the hand at his face, held to d+0.5; recovered by d+0.75, idle by d+1.0
-- When the real window before the cast is shorter (Cinematic run.k < 1, at least the tier's 0.6),
-- the anticipation is laid out again for it (planOf): the stillness gives first, then the set, then
-- the fling, and only past that does everything but the load and the snap shrink evenly. The load,
-- the snap and everything after the cast never shrink.
-- Readable from the match camera (ViewScale: 1 at close cameras, up to 1.8 there): the knives, the
-- glints, the hit stars and the sparks grow with it; the clock is the area's size.
-- Layers (tier 4, within its 34; peak ~19 at the knives with 4 frozen, 3 + 3 per frozen + 4,
-- estimated): the clock (3: the face, two hands), the sphere (1), one knife per frozen enemy (1
-- each), at the hit a hit star and sparks on each (particles), the healed motes once (4; a Heal comes
-- with every knife); the callout's ring. The dim is a camera cue.
-- Poses: PoseAnimator; hit feel: HitFeel; callout: UltimateCallout; sounds: Sfx.

local HitFeel = require(script.Parent.Parent.HitFeel)
local PoseAnimator = require(script.Parent.Parent.PoseAnimator)
local Sfx = require(script.Parent.Parent.Sfx)
local UltimateCallout = require(script.Parent.Parent.UltimateCallout)
local UltimateKit = require(script.Parent.Parent.UltimateKit)
local VfxRecipe = require(script.Parent.Parent.VfxRecipe)

local Kit = UltimateKit
local rgb = Color3.fromRGB

-- The anticipation's segments in real seconds at full length, in order up to the cast (0.98 s in
-- all), and how far each may shrink when the window is short (`least`), in the order they give way
-- (the stillness first, then the set, then the fling).
local SEGMENTS = {
	fling = 0.3, -- windup start -> arms flung wide, the sphere and the clock
	set = 0.35, -- held wide, shivering, the clock ticking
	still = 0.15, -- stillness
	load = 0.12, -- arms drawn in
	snap = 0.06, -- arms thrown wide, ending on the cast
}
local LEAST = { still = 0.05, set = 0.12, fling = 0.15 }
local SHRINK_ORDER = { "still", "set", "fling" }
local ORDER = { "fling", "set", "still", "load", "snap" }
local SNAPS = { load = true, snap = true } -- never shrink
local FULL = 0
for _, name in ORDER do
	FULL += SEGMENTS[name]
end

-- After the cast, before the stun ends (design seconds = real seconds: never compressed).
local FLICKS = { 0.12, 0.28, 0.44, 0.6 } -- the knife flicks, alternating hands (right first)
local GROW = 0.25 -- the sphere and the clock spreading over the area

-- Around the stun's end (d), never compressed.
local RESUME = {
	still = -0.3, -- stillness, the hand raised
	load = -0.12, -- the load
	snap = -0.06, -- the flick sending the knives
	finisher = 0, -- the knives land (the real stun-end hit)
	follow = 0.12, -- the hand at his face
	followEnd = 0.5, -- held until here
	recover = 0.75, -- recovered
	rest = 1.0, -- back to idle
}

export type Plan = { [string]: number }

-- The anticipation for an anticipation speed `k` (Cinematic run.k), as design times: the real time
-- available is k x FULL; the segments give way in SHRINK_ORDER down to LEAST, then all but the load
-- and the snap shrink evenly; each real time is divided by k so Cinematic's own compression (t x k)
-- lands it there. The beats after the cast hang off the real stun (`d`).
local plans: { [string]: Plan } = {}
local function planOf(k: number, d: number): Plan
	k = math.clamp(math.floor(k * 100 + 0.5) / 100, 0.05, 1)
	d = math.max(1, math.floor(d * 100 + 0.5) / 100) -- the stun is 1 s at least (the flicks fit)
	local key = k .. ":" .. d
	local cached = plans[key]
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
		windup = design(real.fling),
		set = design(real.set),
		still = design(real.still),
		load = design(real.load),
		snap = design(real.snap),
		stop = 0,
		d = d,
	}
	for name, value in RESUME do
		plan["resume" .. name] = d + value
	end
	plans[key] = plan
	return plan
end

local GOLD = rgb(240, 200, 95)
local STEEL = rgb(215, 222, 232)
local MOTES = rgb(140, 230, 160)
local CLOCK = rgb(250, 230, 170)
local CALLOUT = GOLD
local SPARKS = VfxRecipe.colors({ { 0, Color3.new(1, 1, 1) }, { 0.4, STEEL }, { 1, GOLD } })
local UNIT_HEIGHT = VfxRecipe.UNIT_HEIGHT
local TICK = 0.25 -- design seconds between the clock's ticks before time stops

-- The poses (PoseAnimator channels): every channel named, so a held pose holds still. About twice a
-- realistic stance. Arms spread with a small forward raise and a big Out (Figure: Out turns about the
-- front axis after the forward raise).
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

local WIDE = pose({
	crouch = 0.05,
	lean = -12,
	rightArm = 12,
	rightArmOut = 85,
	leftArm = 12,
	leftArmOut = 85,
	headPitch = -10,
})
local DRAWN = pose({
	crouch = 0.14,
	lean = -2,
	rightArm = 20,
	rightArmOut = 50,
	leftArm = 20,
	leftArmOut = 50,
	headPitch = 6,
})
local STOP = with(WIDE, { crouch = 0, lean = -16, rise = 0.12, rightArmOut = 100, leftArmOut = 100, headPitch = -14 })
local READY = pose({ crouch = 0.06, lean = 2, rightArm = 40, rightArmOut = 25, leftArm = 40, leftArmOut = 25 })
local FLICK_RIGHT =
	pose({ crouch = 0.1, lean = 14, twist = 38, rightArm = 105, rightArmOut = 10, leftArm = 25, leftArmOut = 35 })
local FLICK_LEFT =
	pose({ crouch = 0.1, lean = 14, twist = -38, leftArm = 105, leftArmOut = 10, rightArm = 25, rightArmOut = 35 })
local RAISED = pose({ lean = -4, rightArm = 125, rightArmOut = 20, leftArm = 10, leftArmOut = 15, headPitch = -4 })
local RAISED_LOAD = with(RAISED, { crouch = 0.08, rightArm = 140, twist = 8 })
local SEND =
	pose({ crouch = 0.06, lean = 15, twist = -36, rightArm = 95, rightArmOut = 40, leftArm = 10, leftArmOut = 15 })
local FACE = pose({
	lean = -8,
	twist = -10,
	rightArm = 135,
	rightArmOut = -25,
	leftArm = -8,
	leftArmOut = 12,
	headPitch = -8,
	headYaw = -10,
})
local RECOVER = pose({ crouch = 0.03, lean = -2, rightArm = 20, rightArmOut = 5 })

-- The keys for a plan (planOf).
local function keyframes(T: Plan): { PoseAnimator.Keyframe }
	local keys: { PoseAnimator.Keyframe } = {
		{ at = T.windup, pose = pose({}) },
		-- Arms flung wide, held shivering, then in stillness.
		{ at = T.set, ease = "quadOut", pose = WIDE },
		{
			at = T.set + 0.08,
			ease = "quadOut",
			hold = math.max(0, T.still - T.set - 0.08),
			shiver = 1.2,
			pose = with(WIDE, { crouch = 0.07 }),
		},
		{ at = T.still, ease = "hold", hold = T.load - T.still, pose = with(WIDE, { crouch = 0.07 }) },
		{ at = T.snap, ease = "quadOut", pose = DRAWN },
		-- Time stops (a snap on the cast), held a beat.
		{ at = T.stop, ease = "snap", hold = FLICKS[1] - 0.1, pose = STOP },
	}
	-- The flicks: a snap out to each, a settle back to ready between them.
	for i, at in FLICKS do
		table.insert(keys, { at = at, ease = "snap", pose = if i % 2 == 1 then FLICK_RIGHT else FLICK_LEFT })
		local settle = at + 0.1
		if i < #FLICKS then
			table.insert(keys, { at = settle, ease = "quadOut", pose = READY })
		elseif settle < T.resumestill - 0.2 then
			-- Held ready (stillness, not a drift), then 0.12 s into the raised hand.
			table.insert(keys, { at = settle, ease = "quadOut", hold = T.resumestill - 0.12 - settle, pose = READY })
		end
	end
	for _, key in
		{
			-- Stillness, the hand raised; the load; the flick sending the knives (a snap) landing on
			-- the hit; the hand at his face, held; recovered; idle.
			{
				at = T.resumestill,
				ease = "quadOut",
				hold = T.resumeload - T.resumestill,
				shiver = 0.5,
				pose = RAISED,
			},
			{ at = T.resumesnap, ease = "quadOut", pose = RAISED_LOAD },
			{ at = T.resumefinisher, ease = "snap", pose = SEND },
			{ at = T.resumefollow, ease = "quadOut", hold = T.resumefollowEnd - T.resumefollow, pose = FACE },
			{ at = T.resumerecover, ease = "inOut", hold = 0.08, pose = RECOVER },
			{ at = T.resumerest, ease = "inOut", pose = pose({}) },
		}
	do
		table.insert(keys, key)
	end
	return keys
end

local def = {}

-- How long the freeze lasts: the cast's real stun.
local function freezeOf(run): number
	local stun = run:find("Stun")
	return if stun and stun.duration then stun.duration else 1
end

-- This run's plan (by its anticipation speed and its stun), kept on the run for the beats.
local function planFor(run): Plan
	local plan = run.memo.plan
	if not plan then
		plan = planOf(run.k or 1, freezeOf(run))
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

-- The clock under him from the windup until just after time resumes: small under him first, its
-- hands ticking; on the cast it spreads over the area and the hands stop.
local function clock(run, plan: Plan)
	local _, radius = run:area()
	local ground = run:ground()
	local small = UNIT_HEIGHT * 0.8
	local function across(): number
		local t = run:designTime()
		local grown = Kit.smooth((t - plan.stop) / GROW)
		return (small + (radius * 2 - small) * grown) * Kit.smooth((t - plan.windup) / 0.15)
	end
	local function fade(): number
		local t = run:designTime()
		return Kit.smooth((t - plan.resumefinisher) / 0.2)
	end
	local to = plan.resumefinisher + 0.2
	Kit.pool(run, plan.windup, to, GOLD:Lerp(Color3.new(0, 0, 0), 0.35), ground, function()
		return across()
	end, function()
		return 0.5 + 0.5 * fade()
	end, Enum.Material.SmoothPlastic)
	-- The hands: they tick (a step every TICK) until time stops, then hold still.
	for _, hand in { { length = 0.42, turns = 1 }, { length = 0.3, turns = 1 / 12 } } do
		Kit.live(run, plan.windup, to, "Block", CLOCK, function(part, _u)
			local t = math.min(run:designTime(), plan.stop)
			local ticks = math.floor((t - plan.windup) / TICK)
			local angle = ticks * hand.turns * math.pi / 6
			local length = math.max(0.05, across() * hand.length)
			local along = Vector3.new(math.sin(angle), 0, -math.cos(angle))
			part.Size = Vector3.new(math.max(0.05, across() * 0.025), 0.08, length)
			part.CFrame = CFrame.lookAt(
				ground + Vector3.new(0, 0.15, 0) + along * length / 2,
				ground + Vector3.new(0, 0.15, 0) + along * length
			)
			part.Transparency = 0.15 + 0.85 * fade()
		end, Enum.Material.SmoothPlastic)
	end
end

-- A knife for a frozen enemy: it appears at `from` in the air in front of the enemy, pointed at it,
-- bobbing, then flies into it over the send's snap and is gone on the hit.
local function knife(run, plan: Plan, view: any, from: number)
	local part = view.part
	local toward = run.view.part.Position - part.Position
	toward = Vector3.new(toward.X, 0, toward.Z)
	toward = if toward.Magnitude > 1e-3 then toward.Unit else Vector3.zAxis
	local slot = math.random() * 6
	local scale = VfxRecipe.viewScale(part.Position)
	local hover = part.Position + toward * 2.2 + Vector3.new(0, 0.6, 0)
	run.memo.knives[view] = hover
	Kit.live(run, from, plan.resumefinisher + 0.02, "Block", STEEL, function(blade, u)
		local t = run:designTime()
		local aim = if part.Parent then part.Position + Vector3.new(0, 0.3, 0) else hover - toward
		local flight = Kit.smooth((t - plan.resumesnap) / (plan.resumefinisher - plan.resumesnap))
		local bob = Vector3.new(0, math.sin(run:now() * 5 + slot) * 0.08 * (1 - flight), 0)
		local at = hover:Lerp(aim, flight) + bob
		blade.Size = Vector3.new(0.09, 0.24, 1.2) * scale
		blade.CFrame = CFrame.lookAt(at, aim + (aim - hover) * 0.01)
		blade.Transparency = if u < 0.05 then 1 - u * 20 else 0
	end, Enum.Material.Metal)
end

local finisher: (any, Plan) -> () -- below

def.beats = {
	{
		at = planOf(1, 1).windup, -- every plan starts its windup at the same design time (-FULL)
		run = function(run)
			local plan = planFor(run)
			run.memo.knives = run.memo.knives or {}
			run.memo.frozen = run.memo.frozen or {}
			run:face(run:target())
			UltimateCallout.mark(run.view, CALLOUT, run:span(plan.windup, -plan.windup))
			-- The small gold sphere around him until time stops, then snapping out over the area.
			local _, radius = run:area()
			local chest = run:chest()
			Kit.shell(run, plan.windup, plan.stop, GOLD, chest, function(u)
				return UNIT_HEIGHT * (0.9 + 0.4 * u)
			end, function(u)
				return 0.85 - 0.15 * u
			end)
			Kit.shell(run, plan.stop, plan.stop + 0.3, GOLD, chest, function(u)
				return UNIT_HEIGHT * 1.3 + (radius * 2.2 - UNIT_HEIGHT * 1.3) * Kit.easeOut(u)
			end, function(u)
				return 0.6 + 0.4 * u
			end)
			clock(run, plan)
			-- The clock's ticks.
			local t = plan.windup + TICK
			while t < plan.stop - 0.05 do
				run:at(t, function()
					Sfx.play("magicChime", { pitch = 1.8, volume = 0.3 })
				end)
				t += TICK
			end
			-- Time stops: the dim (the colour drained) until the knives land; the whoosh into silence.
			run:camera(plan.stop, plan.resumefinisher, { key = "dim", dim = 0.3, rise = 0.12, fall = 0.15 })
			run:at(plan.stop, function()
				Sfx.play("windGust", { pitch = 0.6, volume = 0.6 })
			end)
			-- The flicks' whooshes; the send.
			for _, at in FLICKS do
				run:at(at, function()
					Sfx.play("slashMetal", { pitch = 1.3, volume = 0.35 })
				end)
			end
			run:at(plan.resumesnap, function()
				Sfx.play("whooshLight", { pitch = 1.2 })
			end)
			-- The knives wait for the real stun-end hit; should it never come, they still land.
			run:at(plan.resumefinisher + 0.05, function()
				if not run.memo.finished then
					run.memo.finished = true
					finisher(run, plan)
				end
			end)
		end,
	},
}

-- The cast itself: no generic burst (the sphere and the clock are the release).
function def.release(_run): boolean
	return true
end

-- One knife's hit on `view`: a steel hit star and sparks; the reaction (`main` takes the finisher's).
local function knifeHit(run, view: any, main: boolean)
	local at = view.part.Position
	local scale = VfxRecipe.viewScale(at)
	VfxRecipe.kitHitStar(at, UNIT_HEIGHT * 0.6 * scale, STEEL, scale)
	VfxRecipe.sparks(at, 0.5 * scale, 10, SPARKS, at - run:chest(), scale)
	HitFeel.react(view, run:chest(), if main then { final = true } else { knock = 1.5, tilt = 18 })
end

-- The knives land (the first real stun-end hit): every frozen enemy is hit at once; hit-stop on the
-- bodies (0.07 s), the shake, the punch-in.
finisher = function(run, _plan: Plan)
	local held = { run.view }
	local main = run:target()
	for view in run.memo.frozen do
		if view.part.Parent then
			knifeHit(run, view, view == main or main == nil)
			table.insert(held, view)
		end
	end
	run.memo.landed = true
	HitFeel.hitStop(held, 0.07, { caster = run.view })
	HitFeel.cameraShake(0.28, 0.3)
	HitFeel.punchIn(1)
	Sfx.play("impactHeavy")
	Sfx.play("slashMetal", { pitch = 0.9 })
end

function def.event(run, event): boolean
	local kind = event.kind
	if kind == "AreaStun" then
		return true -- the sphere and the clock are the area
	elseif kind == "Stun" and event.target then
		-- Frozen: a gold glint on it, and its knife at the next flick.
		local view = run.context.views[event.target]
		if view then
			local plan = planFor(run)
			local at = view.part.Position
			local scale = VfxRecipe.viewScale(at)
			VfxRecipe.kitHitStar(at, UNIT_HEIGHT * 0.4 * scale, GOLD, scale)
			run.memo.slots = (run.memo.slots or 0) + 1
			run.memo.frozen = run.memo.frozen or {}
			run.memo.knives = run.memo.knives or {}
			run.memo.frozen[view] = true
			local flick = FLICKS[(run.memo.slots - 1) % #FLICKS + 1]
			knife(run, plan, view, flick + 0.04)
		end
		return false -- the stun halo still shows
	elseif kind == "Damage" and event.stunEnd and event.target then
		local view = run.context.views[event.target]
		if not run.memo.finished then
			run.memo.finished = true
			if view and run.memo.frozen then
				run.memo.frozen[view] = true
			end
			finisher(run, planFor(run))
		elseif view and not (run.memo.frozen and run.memo.frozen[view]) then
			-- A stun-end hit on one the knives missed (not frozen when they landed): its own hit.
			knifeHit(run, view, false)
		end
		return true
	elseif kind == "Heal" and event.target == run.unitIndex then
		-- Green motes drift back into him, once (a Heal comes with every knife).
		if run.memo.healed then
			return true
		end
		run.memo.healed = true
		local now = run:designTime()
		Kit.converge(run, now, now + 0.4, function()
			return run:chest()
		end, MOTES, 3.5, if run.reduced then 2 else 4, false, 0.35)
		Sfx.play("healTwinkle", { volume = 0.5 })
		return true
	end
	return false
end

return def
