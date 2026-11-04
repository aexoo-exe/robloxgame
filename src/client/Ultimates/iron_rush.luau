-- iron_rush (Tier 1): the unstoppable armored charge. The real cast hardens his armor (a Buff on
-- him), dashes him to his target (Dash: his view slides there over ~0.15 s), hits and stuns it
-- (Damage, Stun) and shoves it back a hex (Knockback), all at the Cast event (t = 0). Everything
-- before 0 is anticipation; the charge starts on the real cast and the ram lands as he arrives
-- (+0.12), the moment the hit can be seen. He is a store model: no limbs to pose, only his whole body
-- (Figure: a crouch is a dip, plus lean, twist, rise), so the shoulder-down charge is his whole body.
-- His real position only changes by the real dash.
-- Designed timeline (real seconds at full length; SEGMENTS):
--   -0.68  his plates flash gold as the armor hardens (a gold aura), steam venting off them; the
--          callout (a gold outline on him, a small ground ring)
--   -0.48  set: the shoulder lowered, a dusty stomp; a shiver, until -0.28
--   -0.28  stillness, until -0.18
--   -0.18  a 0.12 s load dip: lower, the shoulder further down
--   -0.06  the charge's 0.06 s snap
--    0     THE CHARGE, on the real cast: thrown forward, shoulder first, as the real dash carries
--          him in
--   +0.12  THE RAM as he arrives: a gold hit star, gold sparks along the charge, dust bursting up,
--          one gold shock ring; hit-stop on the bodies; the crunch, a shake, the punch-in; the target
--          staggered (the real knockback shoves it a hex, scraping a groove; the stun stars are the
--          real ones)
--   +0.18  the follow-through, held to +0.4; recovered by +0.6, idle by +0.85
-- When the real window before the cast is shorter (Cinematic run.k < 1, at least the tier's 0.6),
-- the anticipation is laid out again for it (planOf): the stillness gives first, then the set, then
-- the hardening, and only past that does everything but the load and the snap shrink evenly. The
-- load, the snap and everything after the cast never shrink.
-- Readable from the match camera (ViewScale: 1 at close cameras, up to 1.8 there): the dust, the hit
-- star, the sparks, the ring and the scrape grow with it.
-- Layers (tier 1, within its 14; peak ~7 at the ram, estimated): the gold aura and steam (particles),
-- the stomp's dust, at the ram a hit star, sparks and dust (particles) and one shock ring, the scrape
-- (1); the callout's ring. Poses: PoseAnimator; hit feel: HitFeel; callout: UltimateCallout; sounds:
-- Sfx.

local UltimateKit = require(script.Parent.Parent.UltimateKit)
local HitFeel = require(script.Parent.Parent.HitFeel)
local PoseAnimator = require(script.Parent.Parent.PoseAnimator)
local Sfx = require(script.Parent.Parent.Sfx)
local UltimateCallout = require(script.Parent.Parent.UltimateCallout)
local VfxRecipe = require(script.Parent.Parent.VfxRecipe)

local Kit = UltimateKit
local rgb = Color3.fromRGB

-- The anticipation's segments in real seconds at full length, in order up to the cast (0.68 s in
-- all), and how far each may shrink when the window is short (`least`), in the order they give way
-- (the stillness first, then the set, then the hardening).
local SEGMENTS = {
	harden = 0.2, -- windup start -> the plates flashing
	set = 0.2, -- the shoulder lowered, the stomp, shivering
	still = 0.1, -- stillness
	load = 0.12, -- the load dip
	snap = 0.06, -- the charge's snap, ending on the cast
}
local LEAST = { still = 0.04, set = 0.08, harden = 0.1 }
local SHRINK_ORDER = { "still", "set", "harden" }
local ORDER = { "harden", "set", "still", "load", "snap" }
local SNAPS = { load = true, snap = true } -- never shrink
local FULL = 0
for _, name in ORDER do
	FULL += SEGMENTS[name]
end

-- After the cast (design seconds = real seconds: never compressed).
local AFTER = {
	finisher = 0, -- the charge (the real dash)
	arrive = 0.12, -- he arrives: the ram
	follow = 0.18, -- the follow-through pose reached
	followEnd = 0.4, -- the follow-through held until here
	recover = 0.6, -- recovered
	rest = 0.85, -- back to idle
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
		windup = design(real.harden),
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

local GOLD = rgb(240, 200, 110)
local STEAM = rgb(240, 238, 232)
local SCRAPE = rgb(80, 70, 60)
local CALLOUT = GOLD
local SPARKS = VfxRecipe.colors({ { 0, Color3.new(1, 1, 1) }, { 0.3, GOLD }, { 1, rgb(230, 120, 40) } })
local UNIT_HEIGHT = VfxRecipe.UNIT_HEIGHT

-- The poses (PoseAnimator channels). A store model takes only the whole-body channels (the crouch
-- as a dip, lean, twist, rise); the rest are named so a held pose holds still. About twice a
-- realistic charge.
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

local HARDEN = pose({ crouch = 0.15, lean = -8 })
local SHOULDER = pose({ crouch = 0.35, lean = 20, twist = -22 })
local LOAD = pose({ crouch = 0.45, lean = 26, twist = -28 })
local CHARGE = pose({ crouch = 0.25, lean = 32, twist = -26 })
local RAM = pose({ crouch = 0.2, lean = 36, twist = -32, rise = 0.15 })
local FOLLOW = pose({ crouch = 0.15, lean = 24, twist = -20 })
local RECOVER = pose({ crouch = 0.05, lean = -3 })

-- The keys for a plan (planOf).
local function keyframes(T: Plan): { PoseAnimator.Keyframe }
	return {
		{ at = T.windup, pose = pose({}) },
		{ at = T.set, ease = "quadOut", pose = HARDEN },
		-- The shoulder lowered, held shivering, then in stillness.
		{
			at = T.set + 0.08,
			ease = "quadOut",
			hold = math.max(0, T.still - T.set - 0.08),
			shiver = 1.4,
			pose = SHOULDER,
		},
		{ at = T.still, ease = "hold", hold = T.load - T.still, pose = SHOULDER },
		{ at = T.snap, ease = "quadOut", pose = LOAD },
		-- The charge (a snap) on the cast, the ram (a snap) as he arrives; the follow-through held.
		{ at = T.finisher, ease = "snap", pose = CHARGE },
		{ at = T.arrive, ease = "snap", pose = RAM },
		{ at = T.follow, ease = "quadOut", hold = T.followEnd - T.follow, pose = FOLLOW },
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

local ram: (any, any?) -> () -- below

def.beats = {
	{
		at = planOf(1).windup, -- every plan starts its windup at the same design time (-FULL)
		run = function(run)
			local plan = planFor(run)
			run:face(run:target())
			UltimateCallout.mark(run.view, CALLOUT, run:span(plan.windup, plan.finisher - plan.windup))
			-- The armor hardening: a gold aura flaring off the plates (no see-through shell), steam
			-- venting off them.
			VfxRecipe.aura(run, run.view, VfxRecipe.energy(GOLD), 1.4, plan.windup, plan.still - plan.windup)
			local top = run:chest() + Vector3.new(0, run.view.part.Size.Y * 0.2, 0)
			VfxRecipe.steamColumn(
				top,
				0.6 * run:scale() * VfxRecipe.viewScale(top),
				VfxRecipe.colors({ { 0, STEAM }, { 1, STEAM:Lerp(rgb(160, 160, 165), 0.6) } })
			)
			Sfx.play("windGust", { pitch = 0.7, volume = 0.4 })
			-- The stomp: one dust burst at his feet.
			run:at(plan.set + 0.06, function()
				local ground = run:ground()
				VfxRecipe.kitDust(ground, UNIT_HEIGHT * 0.5 * VfxRecipe.viewScale(ground), 1, 0.5)
				Sfx.play("groundSlam", { volume = 0.6 })
			end)
			-- The ram waits for the real hit; should it never come, it still plays.
			run:at(plan.finisher + 0.05, function()
				if not run.memo.rammed then
					run.memo.rammed = true
					ram(run, run:target())
				end
			end)
		end,
	},
}

-- The cast itself: no generic burst (the charge is the release).
function def.release(_run): boolean
	return true
end

-- The ram as he arrives (AFTER.arrive): a gold hit star, gold sparks along the charge, dust, one gold
-- shock ring; hit-stop on the bodies (0.06 s); the crunch, the shake, the punch-in; the target
-- staggered (the real knockback shoves it).
ram = function(run, target: any?)
	run:at(AFTER.arrive, function()
		local s = run:scale()
		local hit = if target and target.part.Parent
			then target.part.Position
			else run:chest() + run:forward() * UNIT_HEIGHT
		local view = VfxRecipe.viewScale(hit)
		local floor = Vector3.new(hit.X, run:ground().Y, hit.Z)
		VfxRecipe.kitHitStar(hit, UNIT_HEIGHT * 0.8 * view, GOLD, view)
		VfxRecipe.sparks(hit, 0.6 * view, 14, SPARKS, run:forward(), view)
		VfxRecipe.kitDust(floor, UNIT_HEIGHT * 0.55 * s * view, if run.reduced then 1 else 2, 0.5)
		VfxRecipe.meshRing(floor, UNIT_HEIGHT * 0.5 * s * view, GOLD, 0.3, 0.3)
		local held = { run.view }
		if target then
			table.insert(held, target)
		end
		HitFeel.hitStop(held, 0.06, { caster = run.view })
		if target then
			HitFeel.react(target, run:chest(), { knock = 1, tilt = 15 })
		end
		HitFeel.cameraShake(0.08, 0.2)
		HitFeel.punchIn(1)
		Sfx.play("impactHeavy", { volume = 0.8 })
	end)
end

function def.event(run, event): boolean
	local kind = event.kind
	if kind == "Damage" and event.target and not event.dot then
		if not run.memo.rammed then
			run.memo.rammed = true
			ram(run, run.context.views[event.target])
		end
		return true
	elseif kind == "Knockback" and event.target then
		-- The shove: a scrape from where it stood to its new cell.
		local view = run.context.views[event.target]
		if view then
			local from = view.part.Position - Vector3.new(0, view.part.Size.Y / 2, 0)
			local scale = VfxRecipe.viewScale(from)
			Kit.groove(
				run,
				AFTER.arrive,
				AFTER.arrive + 0.5,
				SCRAPE,
				from,
				run.context.toWorld(event.column, event.row),
				0.5 * scale
			)
		end
		return true
	elseif kind == "Buff" and event.target == run.unitIndex then
		return true -- the gold aura was the armor
	elseif kind == "Dash" then
		return true -- the charge is the dash (no afterimages)
	end
	return false
end

return def
