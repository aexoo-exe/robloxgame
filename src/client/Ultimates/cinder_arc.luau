-- cinder_arc (Tier 1): a three-strike spiral of fire, the last one the real hit. The real cast cuts
-- his target, splashes magic over everything within 1 hex of it and speeds up his attacks, all at
-- the Cast event (t = 0). Everything before 0 is anticipation (compressed when the real window is
-- short); the finisher lands exactly on the real hit. Sword in the right hand. Every movement is
-- the figure's pose offset (UnitView): his real position never changes.
--   -1.30  he coils: a deep crouch, torso twisted ~95 degrees back, blade far behind the right hip,
--          weight on the back leg; heat gathers on the blade (embers, motes, a small flame)
--   -1.05  set: held, shivering with tension, until -0.85
--   -0.85  STRIKE 1 (contact -0.79): a 0.06 s snap through a full-body horizontal spin slash as he
--          dashes ~65% of the way to his target (dust and embers streak at his feet); the target
--          flashes, slides 1 stud and staggers; held through the follow-through to -0.61
--   -0.61  STRIKE 2 (contact -0.55): a 0.06 s rising backhand diagonal, still spinning, a little
--          air; the target hit again; held (with a shiver) to -0.18
--   -0.18  a 0.12 s load dip, the blade low
--    0     STRIKE 3, the finisher, on the real hit: a 0.06 s rising cut into a high leaping pose
--          (one swoosh wipes in along it); hit-stop on the bodies; the fire bloom lands behind the
--          target; a boom, a stronger shake, a punch-in; every target knocked back, the main one
--          2.5 studs and launched 0.8 up; he hops (apex +0.14) and lands (+0.32); embers drift
--   +0.62  recovered to idle where he stands, then slides back to his cell by +0.92
-- Layers (tier 1, within its 14): slash trails on the blade (BladeTrail: Roblox Trails between a
-- hilt and a tip attachment on the hand anchor, so they follow every offset), fire flipbook flames,
-- one fire bloom (fx_fire_burst), one swoosh on the finisher (fx_swoosh_ribbon), a dust burst at
-- the dash, small hit stars, embers and motes. Poses: PoseAnimator; hit feel: HitFeel; sounds: Sfx
-- (SfxConfig names windup, whoosh, hitImpact, fireBurst, finisherBoom).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RenderConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("RenderConfig"))

local BladeTrail = require(script.Parent.Parent.BladeTrail)
local HitFeel = require(script.Parent.Parent.HitFeel)
local ImpactEffects = require(script.Parent.Parent.ImpactEffects)
local PoseAnimator = require(script.Parent.Parent.PoseAnimator)
local Sfx = require(script.Parent.Parent.Sfx)
local UltimateKit = require(script.Parent.Parent.UltimateKit)
local UnitView = require(script.Parent.Parent.UnitView)
local VfxRecipe = require(script.Parent.Parent.VfxRecipe)

local Kit = UltimateKit
local rgb = Color3.fromRGB

-- The beats (design seconds; 0 is the real hit). Each strike: a 0.06 s snap into its contact, then
-- its follow-through held.
local T = {
	windup = -1.3,
	set = -1.05,
	setEnd = -0.85, -- strike 1's snap starts
	dash = -0.88, -- the dash starts (just before the snap) ...
	dashEnd = -0.76, -- ... and arrives (eased)
	strike1 = -0.79,
	follow1 = -0.76,
	hold1End = -0.61, -- strike 2's snap starts
	strike2 = -0.55,
	follow2 = -0.52,
	hold2End = -0.18, -- the load dip starts
	load = -0.06, -- the finisher's snap starts
	finisher = 0,
	apex = 0.14, -- the hop's top
	land = 0.32,
	rest = 0.62, -- recovered (where he stands)
	home = 0.92, -- slid back to his cell
}
local DASH_SHARE = 0.65 -- of the way to his target
local DASH_MAX = 6 -- studs (normal size): never further, however far the target

-- Each strike: its contact time; its trail's window (on just before the snap, off after the
-- follow-through), colors (head to tail: yellow -> orange -> crimson over the three, saturated so
-- the tint shows) and life (seconds at 1x); the color of its hit star / swoosh; and, if the blade's
-- real arc cannot be read, its swing plane's tilt from level (degrees).
local function trail(points: { { any } }): ColorSequence
	local keys = {}
	for _, point in points do
		table.insert(keys, ColorSequenceKeypoint.new(point[1], point[2]))
	end
	return ColorSequence.new(keys)
end
local YELLOW, ORANGE, CRIMSON = rgb(255, 215, 70), rgb(255, 125, 25), rgb(210, 35, 20)
local STRIKES = {
	{
		at = T.strike1,
		on = T.setEnd - 0.01,
		off = T.follow1 + 0.08,
		trail = trail({ { 0, YELLOW }, { 1, ORANGE } }),
		life = 0.2,
		color = YELLOW,
		tilt = 12,
	},
	{
		at = T.strike2,
		on = T.hold1End - 0.01,
		off = T.follow2 + 0.08,
		trail = trail({ { 0, ORANGE }, { 1, CRIMSON } }),
		life = 0.2,
		color = ORANGE,
		tilt = 40,
	},
	{
		at = T.finisher,
		on = T.load - 0.01,
		off = T.apex,
		trail = trail({ { 0, YELLOW }, { 0.4, ORANGE }, { 1, CRIMSON } }),
		life = 0.25,
		color = CRIMSON,
		tilt = 70,
	},
}
local HEAT = rgb(255, 170, 60)
-- The windup's blade flame: re-emitted at the tip at these times, each living 0.07-0.08 s, so the
-- last is gone by -0.88, the dash's start (one long flame hung in the air where he stood).
local WINDUP_FLAMES = { -1.05, -1.0, -0.96 }
-- The finisher's light: a short, tight warm flash at the target's chest (the recipe's light, range
-- 1.5x the area and brightness 3.6, washed the floor orange across the frame).
local FINISH_LIGHT = { brightness = 1.8, range = 1.5, seconds = 0.25 } -- range in unit heights
local DASH_DUST = 0.4 -- seconds the dash's dust burst lives (its flipbook's own 0.8 s lingered)
local SAMPLE = 0.035 -- design seconds before a contact the blade is sampled (its arc's direction)
local BLADE = 0.55 -- the sword's reach past the hand, in unit heights
local UNIT_HEIGHT = RenderConfig.unitSize.Y

-- The poses (PoseAnimator channels), about twice a realistic swing: big, readable anime poses.
-- Every body pose names every body channel, so a held pose holds the whole body still (a channel a
-- key leaves out would drift on toward its next key). `lunge` (the dash) and the finisher's hop
-- (`rise`, and the legs and lean that go with it) run on keys of their own.
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
local function without(base: { [string]: number }, channels: { string }): { [string]: number }
	local out = table.clone(base)
	for _, channel in channels do
		out[channel] = nil
	end
	return out
end

-- The coil: deep crouch, torso twisted far back, blade far behind the right hip, weight on the back
-- leg, eyes on the target.
local COIL = pose({
	crouch = 0.75,
	lean = 32,
	twist = -95,
	tilt = -10,
	spin = -20,
	rightArm = -45,
	rightArmOut = 80,
	leftArm = 55,
	leftArmOut = -35,
	leftLeg = 55,
	rightLeg = -50,
	headYaw = 70,
	headPitch = 10,
})
-- Strike 1: a full-body horizontal spin slash, leaning hard into it, arm straight across.
local STRIKE1 = pose({
	crouch = 0.5,
	lean = 40,
	twist = 85,
	tilt = 8,
	spin = 140,
	rightArm = 95,
	rightArmOut = -80,
	leftArm = -30,
	leftArmOut = 70,
	leftLeg = 60,
	rightLeg = -55,
	headYaw = -40,
})
local FOLLOW1 = with(STRIKE1, { twist = 95, rightArmOut = -100, spin = 160, lean = 36 })
-- Strike 2: a rising backhand diagonal, still turning, off the ground a little.
local STRIKE2 = pose({
	crouch = 0.3,
	lean = 15,
	twist = -60,
	tilt = -14,
	spin = 290,
	rise = 0.6,
	rightArm = 160,
	rightArmOut = 85,
	leftArm = 50,
	leftArmOut = -50,
	leftLeg = 25,
	rightLeg = -30,
	headYaw = 30,
	headPitch = -12,
})
local FOLLOW2 = with(STRIKE2, { rightArm = 170, rightArmOut = 100, spin = 305, twist = -70, rise = 0.3 })
-- The load: a dip, the blade low, coiled for the last one.
local LOAD = pose({
	crouch = 0.8,
	lean = 35,
	twist = -85,
	spin = 330,
	rightArm = 30,
	rightArmOut = 50,
	leftArm = 20,
	leftArmOut = -20,
	leftLeg = 45,
	rightLeg = -45,
	headPitch = 6,
})
-- Strike 3, the finisher: a rising cut into a high leaping pose, knee up.
local FINISH = pose({
	lean = -22,
	twist = 30,
	spin = 360,
	rise = 1.4,
	rightArm = 180,
	leftArm = 95,
	leftArmOut = 75,
	leftLeg = 70,
	rightLeg = -35,
	headPitch = -22,
})
local HOP = { "rise", "crouch", "leftLeg", "lean" } -- the finisher's channels its hop drives

-- `dash`: studs (normal size) the dash carries him toward his target (`lunge`).
local function keyframes(dash: number): { PoseAnimator.Keyframe }
	return {
		{ at = T.windup, pose = with(pose({}), { lunge = 0 }) },
		-- The coil, held with a shiver until strike 1's snap.
		{ at = T.set, ease = "quadOut", hold = T.setEnd - T.set, shiver = 2.2, pose = COIL },
		-- The dash: from where he stands, eased, arriving just after strike 1's contact.
		{ at = T.dash, pose = { lunge = 0 } },
		{ at = T.dashEnd, ease = "expoOut", pose = { lunge = dash } },
		-- Strike 1 (a 0.06 s snap), its follow-through held to strike 2's snap.
		{ at = T.strike1, ease = "snap", pose = STRIKE1 },
		{ at = T.follow1, ease = "quadOut", hold = T.hold1End - T.follow1, pose = FOLLOW1 },
		-- Strike 2 (a 0.06 s snap), its follow-through held (shivering) to the load dip.
		{ at = T.strike2, ease = "snap", pose = STRIKE2 },
		{ at = T.follow2, ease = "quadOut", hold = T.hold2End - T.follow2, shiver = 1.2, pose = FOLLOW2 },
		-- The load dip (0.12 s).
		{ at = T.load, ease = "quadOut", pose = LOAD },
		-- The finisher (a 0.06 s snap): the high pose held to the landing; the hop on its own keys.
		{ at = T.finisher, ease = "snap", hold = T.land - T.finisher, pose = without(FINISH, HOP) },
		{
			at = T.finisher,
			ease = "snap",
			pose = { rise = FINISH.rise, crouch = 0, leftLeg = FINISH.leftLeg, lean = FINISH.lean },
		},
		{ at = T.apex, ease = "quadOut", pose = { rise = 1.9 } },
		{ at = T.land, ease = "quadIn", pose = { rise = 0, crouch = 0.4, leftLeg = 30, lean = -6 } },
		-- One whole turn is facing front again: drop it to 0 at once (no unwinding spin).
		{ at = T.land + 0.001, ease = "hold", pose = { spin = 0 } },
		-- Recover to idle where he stands ("back": a ~10% settle).
		{ at = T.rest, ease = "back", pose = pose({}) },
		-- Then slide back to his cell.
		{ at = T.rest + 0.001, pose = { lunge = dash } },
		{ at = T.home, ease = "inOut", pose = { lunge = 0 } },
	}
end

local def = {}

-- The dash for this cast: DASH_SHARE of the way to the target (none without one), in studs at
-- normal size (UnitView scales the lunge by the unit's size).
local function dashOf(run): number
	local target = run:target()
	if not target or not target.part then
		return 0
	end
	local from, to = run.view.part.Position, target.part.Position
	local flat = Vector3.new(to.X - from.X, 0, to.Z - from.Z).Magnitude
	return math.min(flat * DASH_SHARE / math.max(UnitView.sizeFactor(run.view), 0.1), DASH_MAX)
end

-- Tracks by dash length (rounded to a tenth of a stud), built once each.
local tracks: { [number]: any } = {}
function def.poseFor(run)
	local dash = math.floor(dashOf(run) * 10 + 0.5) / 10
	local track = tracks[dash]
	if not track then
		track = PoseAnimator.track(keyframes(dash))
		tracks[dash] = track
	end
	return track
end

local function hand(run): Vector3
	return run:hand("right")
end

-- The blade's tip now: its trail attachment (on the real blade line), else past the hand along the arm.
local function tip(run): Vector3
	local blade = run.memo.blade
	if blade then
		return blade:tip()
	end
	local h = hand(run)
	local arm = h - run:chest()
	local along = if arm.Magnitude > 1e-3 then arm.Unit else run:forward()
	return h + along * UNIT_HEIGHT * BLADE * 0.6 * run:scale()
end

-- The blade's trails (BladeTrail): one per cut, each with its own colors, made at the windup. The
-- carrier follows the hand anchor, which UnitView places with every pose offset (the dash, the
-- hop), so the ribbon stays on the blade as he travels.
local function attachBlade(run)
	if run.memo.blade then
		return
	end
	local blade = BladeTrail.attach(run.view, { hand = "right", from = 0.2, to = 0.66 })
	for index, spec in STRIKES do
		blade:add("cut" .. index, { colors = spec.trail, lifetime = spec.life })
	end
	run.memo.blade = blade
	-- Gone once every cut has faded.
	run:at(T.home + 0.2, function()
		blade:destroy()
		run.memo.blade = nil
	end)
end

-- A cut's trail on from just before its strike to the end of its follow-through, with embers flung
-- off the tip along the arc as the blade moves.
local function cut(run, index: number)
	local spec = STRIKES[index]
	run:at(spec.on, function()
		local blade = run.memo.blade
		if blade then
			blade:enable("cut" .. index)
		end
	end)
	local step = 0.04
	local t = spec.on + step
	while t < spec.off do
		run:at(t, function()
			if not run.reduced then
				VfxRecipe.embers(run, tip(run), run:scale(), nil, 3)
			end
		end)
		t += step
	end
	run:at(spec.off, function()
		local blade = run.memo.blade
		if blade then
			blade:disable("cut" .. index)
		end
	end)
end

-- The dash's streak at his feet: a dust burst where he pushes off, embers along the way.
local function dashStreak(run)
	local s = run:scale()
	VfxRecipe.kitDust(run:ground(), UNIT_HEIGHT * 0.5 * s, 1, DASH_DUST)
	local t = T.dash + 0.03
	while t < T.dashEnd do
		run:at(t, function()
			VfxRecipe.embers(run, run:ground() + Vector3.new(0, 0.3, 0), s, nil, 4)
		end)
		t += 0.03
	end
end

-- The swing plane's normal at a strike: from the blade's real motion (the hand a moment ago and
-- now, about the chest), or the strike's fallback tilt when that cannot be read.
local function swingNormal(run, strike, before: Vector3?): Vector3
	local now = hand(run)
	local pivot = run:chest()
	if before then
		local motion = now - before
		local arm = now - pivot
		local normal = arm:Cross(motion)
		if motion.Magnitude > 0.05 and normal.Magnitude > 1e-3 then
			return normal.Unit
		end
	end
	return (CFrame.fromAxisAngle(run:forward(), math.rad(strike.tilt)) * Vector3.yAxis).Unit
end

-- One strike at its contact (its trail is already drawing the arc: cut): flames off the blade tip,
-- the whoosh; the finisher also wipes in one swoosh along its arc (in over 0.08 s, out over 0.2 s);
-- strikes 1-2 hit the target (a small hit star, its reaction: a flash, a 1 stud slide and a
-- stagger; a short hit-stop and shake).
local function strike(run, index: number)
	local s = run:scale()
	local spec = STRIKES[index]
	local pivot = run:chest()
	if index == #STRIKES then
		local reach = (hand(run) - pivot).Magnitude + UNIT_HEIGHT * BLADE * s
		VfxRecipe.kitSwoosh(
			pivot,
			reach * 1.6,
			spec.color,
			swingNormal(run, spec, run.memo["sample" .. index]),
			0,
			0.28,
			0.08
		)
	end
	-- Flames off the blade tip (one emit of two), embers flung off it.
	VfxRecipe.flames(tip(run), 2, (1.1 + 0.15 * index) * s)
	VfxRecipe.embers(run, tip(run), s, nil, 6)
	Sfx.play("whoosh", { pitch = 1 + 0.06 * (index - 1) })
	if index >= #STRIKES then
		return -- the finisher's hit is the real one (def.event, Area)
	end
	local target = run:target()
	if not target or not target.part.Parent then
		return
	end
	local at = target.part.Position + Vector3.new(0, target.part.Size.Y * 0.1, 0)
	VfxRecipe.kitHitStar(at, target.part.Size.Y * 0.8, spec.color)
	VfxRecipe.sparks(at, 0.4, 10, nil, run:forward())
	HitFeel.react(target, pivot)
	HitFeel.hitStop({ run.view, target }, if index == 1 then 0.05 else 0.06, { caster = run.view })
	HitFeel.cameraShake(if index == 1 then 0.12 else 0.15, 0.18)
	Sfx.play("hitImpact", { volume = 0.8 })
end

local finisher: (any) -> () -- below

def.beats = {
	{
		at = T.windup,
		run = function(run)
			run:face(run:target())
			local s = run:scale()
			Sfx.play("windup")
			attachBlade(run)
			-- Heat gathering on the blade: motes drawn in, embers glowing off it, a small flame.
			Kit.converge(run, T.windup + 0.05, T.set + 0.05, function()
				return tip(run)
			end, HEAT, 1.4 * s, if run.reduced then 5 else 10)
			VfxRecipe.embers(run, hand(run), s, nil, 8)
			-- A small flame licking the blade through the set: short flames re-emitted at the tip as
			-- it moves (a particle stays where it was emitted), the last gone before the dash.
			for _, at in WINDUP_FLAMES do
				run:at(at, function()
					VfxRecipe.flames(tip(run), 1, 0.7 * s, nil, { 0.07, 0.08 })
				end)
			end
			run:at(T.dash, dashStreak)
			-- Each strike: its trail on through the cut, the blade sampled just before contact (the
			-- finisher's swoosh plane), then the strike itself.
			for index, spec in STRIKES do
				cut(run, index)
				run:at(spec.at - SAMPLE, function()
					run.memo["sample" .. index] = hand(run)
				end)
				if index < #STRIKES then
					run:at(spec.at, function()
						strike(run, index)
					end)
				end
			end
			-- The finisher waits for the real Area event; should it never come, it still plays.
			run:at(T.finisher + 0.05, function()
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

-- The finisher on the real hit: the strike, hit-stop (bodies and impact sparks only, 0.07 s), the
-- fire bloom landing on it on the target (half the old size, just behind the target as the camera
-- sees it and drawn behind what is in front of it, so the caster stays visible; faded by 0.42 s),
-- the boom, a stronger shake, the punch-in, every target knocked back (the main one 2.5 studs and
-- launched 0.8 up; the rest 1.5 studs), embers drifting after.
finisher = function(run)
	local center, radius = run:area()
	local s = run:scale()
	local main = run:target()
	local targets = run:targets()
	local held = { run.view }
	for _, view in targets do
		table.insert(held, view)
	end
	strike(run, #STRIKES)
	HitFeel.hitStop(held, 0.07, { caster = run.view })
	local bloomAt = if main then main.part.Position - Vector3.new(0, main.part.Size.Y / 2, 0) else center
	local camera = workspace.CurrentCamera
	if camera then
		local away = bloomAt - camera.CFrame.Position
		away = Vector3.new(away.X, 0, away.Z)
		if away.Magnitude > 1e-3 then
			bloomAt += away.Unit * 0.6
		end
	end
	VfxRecipe.kitFireBurst(bloomAt, radius * 0.75, nil, { lifetime = 0.42, zOffset = -1.5 })
	VfxRecipe.sparks(center + Vector3.new(0, 1.2, 0), 0.8, nil, VfxRecipe.themes.fire.spark)
	if not run.reduced then
		local lightAt = (if main then main.part.Position else center + Vector3.new(0, UNIT_HEIGHT * 0.6, 0))
		ImpactEffects.light(
			lightAt,
			VfxRecipe.themes.fire.light,
			FINISH_LIGHT.brightness,
			FINISH_LIGHT.range * UNIT_HEIGHT,
			FINISH_LIGHT.seconds
		)
	end
	for _, view in targets do
		HitFeel.react(view, run:chest(), if view == main then { final = true } else { knock = 1.5, tilt = 18 })
	end
	HitFeel.cameraShake(0.3, 0.35)
	HitFeel.punchIn(1)
	Sfx.play("finisherBoom")
	Sfx.play("fireBurst")
	-- Embers drifting up off the splash after.
	for i = 0, 2 do
		run:at(0.12 + 0.25 * i, function()
			VfxRecipe.embers(run, VfxRecipe.within(center, radius * 0.6) + Vector3.new(0, 0.4, 0), s, nil, 8)
		end)
	end
end

function def.event(run, event): boolean
	local kind = event.kind
	if kind == "Area" then
		if not run.memo.finished then
			run.memo.finished = true
			finisher(run)
		end
		return true
	elseif kind == "Buff" and event.target == run.unitIndex then
		-- The attack speed: embers off the blade once he is home.
		run:at(T.home, function()
			VfxRecipe.embers(run, tip(run), run:scale(), nil, 8)
		end)
		return true
	elseif kind == "Damage" and event.target and not event.dot then
		return true -- the strikes and the finisher draw the hits
	end
	return false
end

return def
