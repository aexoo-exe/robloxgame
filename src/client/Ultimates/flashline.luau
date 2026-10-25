-- flashline (Tier 1): the thunderclap quick-draw. The real cast dashes him next to the farthest enemy
-- (Dash event; UnitView.dashTo slides his view there in 0.15 s) and cuts it (Damage), both at the
-- Cast tick (t = 0). Everything before 0 is anticipation; the draw lands on the real hit. His katana
-- is out only for casts and attacks (UnitAvatarConfig `drawn`), right hand. Every movement is the
-- figure's pose offset (UnitView): his real position only changes by the real dash.
-- Designed timeline (real seconds at full length; SEGMENTS):
--   -0.93  he coils into the quick-draw stance: a deep crouch, weight forward on the front leg, the
--          right hand across his body on the hilt at the left hip, the left hand on the sheath,
--          eyes on the target; gold crackle crawls over him; the callout (a gold outline, a ring)
--   -0.65  set: held, shivering with the charge, to -0.40
--   -0.40  dead stillness: the crackle stops, nothing moves, until -0.18
--   -0.18  a 0.12 s load dip, lower still
--   -0.06  the draw's 0.06 s snap
--    0     THE DRAW, on the real hit: an explosive extended cut, arm swept wide; he dashes THROUGH
--          the target (the real slide to its side, then `lunge` carries him past it to the mirrored
--          point by +0.12); crisp gold lightning bolts along the whole path, a gold trail on the
--          blade, the thunder crack
--   +0.06  a low follow-through, his back to the target, held still to +0.40
--   +0.16  the delayed cut: a split second after he is past, the target flashes (gold hit star, a
--          short bolt across it, sparks, a light), hit-stop on its body, the shake and punch-in, and
--          it is knocked back 2.5 studs and launched 0.8
--   +0.40  a slow sheathe, the blade brought back across to the left hip, until the click at +0.85
--   +1.12  recovered to idle where he stands (past the target), then slides home (to his real cell
--          beside it) by +1.45
-- When the real window before the cast is shorter (Cinematic run.k < 1, at least the tier's 0.6),
-- the anticipation is laid out again for it (planOf): the stillness gives first, then the set, then
-- the coil, and only past that does everything shrink evenly. The snap and everything after the
-- hit never shrink.
-- Readable from the match camera (ViewScale: 1 at close cameras, up to 1.8 there): the trail, the
-- crackle, the hit star, the cut bolt and the sparks grow with it. The dash bolts span the real path
-- (their size is the path's length), so they read at any distance as they are.
-- Layers (tier 1, within its 14; peak ~6 at +0.16, estimated): gold crackle on his body (coil and
-- set only), 3 gold lightning bolts along the dash (fx_lightning; 2 when reduced), one blade trail
-- (BladeTrail), at the cut a gold hit star, one short bolt, sparks and a light (not when reduced),
-- the callout's ring. Poses: PoseAnimator; hit feel: HitFeel; callout: UltimateCallout; sounds: Sfx.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RenderConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("RenderConfig"))

local BladeTrail = require(script.Parent.Parent.BladeTrail)
local HitFeel = require(script.Parent.Parent.HitFeel)
local ImpactEffects = require(script.Parent.Parent.ImpactEffects)
local PoseAnimator = require(script.Parent.Parent.PoseAnimator)
local Sfx = require(script.Parent.Parent.Sfx)
local UltimateCallout = require(script.Parent.Parent.UltimateCallout)
local UnitView = require(script.Parent.Parent.UnitView)
local VfxRecipe = require(script.Parent.Parent.VfxRecipe)

local rgb = Color3.fromRGB

-- The anticipation's segments in real seconds at full length, in order up to the hit (0.93 s in
-- all), and how far each may shrink when the window is short (`least`), in the order they give way
-- (the stillness first, then the set, then the coil).
local SEGMENTS = {
	coil = 0.28, -- windup start -> the quick-draw stance reached
	set = 0.25, -- the stance held, shivering
	still = 0.22, -- held in dead stillness
	load = 0.12, -- the load dip
	snap = 0.06, -- the draw's snap, ending on the hit
}
local LEAST = { still = 0.1, set = 0.08, coil = 0.12 }
local SHRINK_ORDER = { "still", "set", "coil" }
local ORDER = { "coil", "set", "still", "load", "snap" }
local FULL = 0
for _, name in ORDER do
	FULL += SEGMENTS[name]
end

-- After the hit (design seconds = real seconds: never compressed).
local AFTER = {
	finisher = 0,
	through = 0.12, -- past the target (the lunge's end)
	follow = 0.06, -- the follow-through pose reached
	cut = 0.16, -- the delayed cut on the target
	trailOff = 0.22, -- the blade trail stops drawing
	followEnd = 0.4, -- the follow-through held still until here
	click = 0.85, -- the blade home in the sheath
	rest = 1.12, -- recovered (where he stands)
	home = 1.45, -- slid back to his real cell
}

export type Plan = { [string]: number }

-- The beats for an anticipation speed `k` (Cinematic run.k), as design times: the real time
-- available is k x FULL; the segments give way in SHRINK_ORDER down to LEAST, then all shrink
-- evenly; each real time is divided by k so Cinematic's own compression (t x k) lands it there.
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
		-- Past the floors everything before the snap shrinks evenly (never the snap).
		local total = 0
		for _, name in ORDER do
			if name ~= "snap" then
				total += lengths[name]
			end
		end
		local even = (total - deficit) / total
		for _, name in ORDER do
			if name ~= "snap" then
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

local GOLD = rgb(255, 205, 70)
local GOLD_DEEP = rgb(235, 150, 30)
local CALLOUT = GOLD
local TRAIL = ColorSequence.new({
	ColorSequenceKeypoint.new(0, rgb(255, 240, 170)),
	ColorSequenceKeypoint.new(0.4, GOLD),
	ColorSequenceKeypoint.new(1, GOLD_DEEP),
})
local TRAIL_LIFE = 0.22
-- life 0.13 (x0.8-1.2 in kitBolts): crisp, and gone before the delayed cut (+0.16) adds its layers.
local DASH_BOLTS = { full = 3, reduced = 2, life = 0.13 }
local THROUGH_MAX = 7 -- studs (normal size) he may carry past his real cell
-- The cut's light: a short, tight gold flash at the target's chest.
local CUT_LIGHT = { brightness = 1.8, range = 1.5, seconds = 0.25 } -- range in unit heights
local UNIT_HEIGHT = RenderConfig.unitSize.Y

-- The poses (PoseAnimator channels), about twice a realistic iai draw: big, readable anime poses.
-- Every body pose names every body channel, so a held pose holds the whole body still. `lunge` (the
-- carry through the target and the slide home) runs on keys of its own.
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

-- The quick-draw stance: deep crouch, weight forward on the front leg, the right hand across the body
-- on the hilt at the left hip, the left hand on the sheath, eyes on the target.
local STANCE = pose({
	crouch = 0.85,
	lean = 38,
	twist = 35,
	tilt = 6,
	rightArm = 40,
	rightArmOut = -70,
	leftArm = 25,
	leftArmOut = -20,
	leftLeg = 65,
	rightLeg = -55,
	headYaw = -25,
	headPitch = 12,
})
-- The load: lower still, coiled tighter.
local LOAD = with(STANCE, { crouch = 1.0, lean = 46, twist = 42, rightArmOut = -78 })
-- The draw: an explosive extended cut, the arm swept wide to the right, a long stride.
local DRAW = pose({
	crouch = 0.55,
	lean = 50,
	twist = -60,
	tilt = -8,
	rightArm = 95,
	rightArmOut = 110,
	leftArm = -35,
	leftArmOut = 45,
	leftLeg = 80,
	rightLeg = -75,
	headYaw = 30,
	headPitch = 8,
})
-- The follow-through: held low, the blade out to the side, his back to the target.
local FOLLOW = pose({
	crouch = 0.9,
	lean = 40,
	twist = -75,
	tilt = -6,
	rightArm = 70,
	rightArmOut = 130,
	leftArm = -20,
	leftArmOut = 50,
	leftLeg = 75,
	rightLeg = -70,
	headYaw = 20,
	headPitch = 15,
})
-- The sheathe: the blade brought back across to the left hip, rising a little.
local SHEATHE = pose({
	crouch = 0.6,
	lean = 20,
	twist = 30,
	rightArm = 35,
	rightArmOut = -60,
	leftArm = 25,
	leftArmOut = -20,
	leftLeg = 45,
	rightLeg = -40,
	headYaw = -10,
	headPitch = 5,
})
-- The click: the last push of the blade home.
local CLICK = with(SHEATHE, { rightArmOut = -72, crouch = 0.55 })

-- The keys for a plan (planOf) and a carry of `through` studs (normal size) past his real cell.
local function keyframes(T: Plan, through: number): { PoseAnimator.Keyframe }
	return {
		{ at = T.windup, pose = with(pose({}), { lunge = 0 }) },
		-- The stance, held with a shiver, then in dead stillness, to the load dip.
		{ at = T.set, ease = "quadOut", hold = T.still - T.set, shiver = 2, pose = STANCE },
		{ at = T.still, ease = "hold", hold = T.load - T.still, pose = STANCE },
		{ at = T.snap, ease = "quadOut", pose = LOAD },
		-- The draw (a snap) on the hit; the carry through the target on its own keys.
		{ at = T.finisher, ease = "snap", pose = DRAW },
		{ at = T.finisher, pose = { lunge = 0 } },
		{ at = T.through, ease = "expoOut", pose = { lunge = through } },
		-- The follow-through, held still.
		{ at = T.follow, ease = "quadOut", hold = T.followEnd - T.follow, pose = FOLLOW },
		-- The slow sheathe, then the click.
		{ at = T.click - 0.05, ease = "inOut", pose = SHEATHE },
		{ at = T.click, ease = "snap", pose = CLICK },
		-- Recover to idle where he stands ("back": a ~10% settle), then slide home.
		{ at = T.rest, ease = "back", pose = pose({}) },
		{ at = T.rest + 0.001, pose = { lunge = through } },
		{ at = T.home, ease = "inOut", pose = { lunge = 0 } },
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

-- Where the real dash ends (the cast's Dash event), else where he stands.
local function dashEnd(run): Vector3
	local dash = run:find("Dash")
	if dash and dash.column then
		return run.context.toWorld(dash.column, dash.row)
	end
	return run:ground()
end

-- How far past his real cell the carry goes: to the point mirrored across the target, in studs at
-- normal size (UnitView scales the lunge by the unit's size), at most THROUGH_MAX.
local function throughOf(run): number
	local target = run:target()
	if not target or not target.part then
		return 0
	end
	local from, to = dashEnd(run), target.part.Position
	local flat = Vector3.new(to.X - from.X, 0, to.Z - from.Z).Magnitude
	return math.min(flat * 2 / math.max(UnitView.sizeFactor(run.view), 0.1), THROUGH_MAX)
end

-- Tracks by plan and carry length (rounded to a tenth of a stud), built once each.
local tracks: { [Plan]: { [number]: any } } = {}
function def.poseFor(run)
	local plan = planFor(run)
	local through = math.floor(throughOf(run) * 10 + 0.5) / 10
	local byThrough = tracks[plan]
	if not byThrough then
		byThrough = {}
		tracks[plan] = byThrough
	end
	local track = byThrough[through]
	if not track then
		track = PoseAnimator.track(keyframes(plan, through))
		byThrough[through] = track
	end
	return track
end

-- The blade's trail (BladeTrail), made at the windup; it follows every pose offset (the carry) and
-- scales with the camera distance (ViewScale). Gone once it has faded.
local function attachBlade(run)
	if run.memo.blade then
		return
	end
	local blade = BladeTrail.attach(run.view, { hand = "right", from = 0.2, to = 0.66, viewScale = true })
	blade:add("draw", { colors = TRAIL, lifetime = TRAIL_LIFE })
	run.memo.blade = blade
	run:at(planFor(run).home + 0.2, function()
		blade:destroy()
		run.memo.blade = nil
	end)
end

local function setTrail(run, on: boolean)
	local blade = run.memo.blade
	if blade then
		if on then
			blade:enable("draw")
		else
			blade:disable("draw")
		end
	end
end

local finisher: (any) -> () -- below

def.beats = {
	{
		at = planOf(1).windup, -- every plan starts its windup at the same design time (-FULL)
		run = function(run)
			local plan = planFor(run)
			run:face(run:target())
			Sfx.play("energyCharge")
			attachBlade(run)
			-- The callout: a gold outline on him through the windup to the draw, a small ground ring.
			UltimateCallout.mark(run.view, CALLOUT, run:span(plan.windup, plan.finisher - plan.windup))
			-- Gold crackle crawling over him through the coil and the set; it stops for the stillness.
			local scale = VfxRecipe.viewScale(run:chest())
			VfxRecipe.kitCrackleAura(run, run.view, GOLD, plan.windup + 0.04, plan.still - plan.windup - 0.04, 1, scale)
			-- Where he stands before the dash: the bolts start here.
			run:at(plan.load, function()
				run.memo.from = run:chest()
			end)
			-- The trail draws through the draw and the carry.
			run:at(plan.snap - 0.01, function()
				setTrail(run, true)
			end)
			run:at(plan.trailOff, function()
				setTrail(run, false)
			end)
			-- The draw waits for the real hit (Damage); should it never come, it still plays.
			run:at(plan.finisher + 0.05, function()
				if not run.memo.finished then
					run.memo.finished = true
					finisher(run)
				end
			end)
		end,
	},
}

function def.release(_run): boolean
	return true
end

-- The delayed cut on the target, a split second after he is past: the gold hit star, one short bolt
-- across it, sparks, a light; hit-stop on its body only (0.06 s); knocked back 2.5 studs and
-- launched 0.8; the shake and the punch-in.
local function cut(run, target)
	if not target or not target.part.Parent then
		return
	end
	local at = target.part.Position + Vector3.new(0, target.part.Size.Y * 0.1, 0)
	local view = VfxRecipe.viewScale(at)
	local forward = run:forward()
	VfxRecipe.kitHitStar(at, target.part.Size.Y * 0.9 * view, GOLD, view)
	VfxRecipe.kitBolts(at - forward * 1.4 * view, at + forward * 1.4 * view, GOLD, 1, 0.18)
	VfxRecipe.sparks(at, 0.5 * view, 10, nil, forward, view)
	if not run.reduced then
		ImpactEffects.light(at, GOLD, CUT_LIGHT.brightness, CUT_LIGHT.range * UNIT_HEIGHT, CUT_LIGHT.seconds)
	end
	HitFeel.hitStop({ target }, 0.06, { caster = run.view })
	HitFeel.react(target, run.memo.from or run:chest(), { final = true })
	HitFeel.cameraShake(0.3, 0.35)
	HitFeel.punchIn(1)
	Sfx.play("impactLight", { volume = 0.8 })
end

-- The draw on the real hit: the thunder crack, gold lightning bolts along the whole path (from
-- where he stood, through the target, to where the carry ends), then the delayed cut.
finisher = function(run)
	local target = run:target()
	local from = run.memo.from or run:chest()
	local to = from + run:forward() * UNIT_HEIGHT
	if target and target.part.Parent then
		local center = target.part.Position
		local away = Vector3.new(center.X - from.X, 0, center.Z - from.Z)
		local past = if away.Magnitude > 1e-3 then away.Unit else run:forward()
		local beyond = (center - dashEnd(run)) * Vector3.new(1, 0, 1)
		to = center + past * beyond.Magnitude + Vector3.new(0, from.Y - center.Y, 0)
	end
	VfxRecipe.kitBolts(from, to, GOLD, if run.reduced then DASH_BOLTS.reduced else DASH_BOLTS.full, DASH_BOLTS.life)
	Sfx.play("lightningCrack")
	run:at(AFTER.cut, function()
		cut(run, target)
	end)
	run:at(AFTER.click, function()
		Sfx.play("sheathe")
	end)
end

function def.event(run, event): boolean
	local kind = event.kind
	if kind == "Dash" then
		return true -- the bolts are the dash (finisher): no afterimages
	elseif kind == "Damage" and event.target and not event.dot then
		if not run.memo.finished then
			run.memo.finished = true
			finisher(run)
		end
		return true -- the delayed cut draws the hit
	end
	return false
end

return def
