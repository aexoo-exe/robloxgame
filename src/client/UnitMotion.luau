-- Combat motion: the pose layers a unit adds on top of idling or walking (UnitView.update) for
-- attacks, getting hit, casting, being stunned, dying and cheering, and which attack style each
-- unit uses. Pure pose math on Figure.Pose tables; every number is in AnimationConfig. Works for
-- every figure kind: block-built looks and catalog avatars move their arms, legs and body; store
-- models (no limbs) still lunge, lean, turn, dip and fall. Presentation only.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AnimationConfig = require(Shared:WaitForChild("AnimationConfig"))
local UnitConfig = require(Shared:WaitForChild("UnitConfig"))

local UnitMotion = {}

export type Style = typeof(AnimationConfig.styles.blade)

local rad = math.rad
local STYLES = AnimationConfig.styles
local OVERLAP = AnimationConfig.overlap

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end
local function easeOut(t: number): number
	return 1 - (1 - t) * (1 - t)
end
local function easeIn(t: number): number
	return t * t
end
local function smooth(t: number): number
	return t * t * (3 - 2 * t)
end

-- A recovery curve from 1 at `u` = 0 to 0 at 1: back to rest by AnimationConfig.overlap.settleAt,
-- then a small overshoot past rest (`settle`) that eases back in. Smooth throughout.
function UnitMotion.settle(u: number): number
	u = math.clamp(u, 0, 1)
	local at = OVERLAP.settleAt
	local back = 1 - smooth(math.min(1, u / at))
	if u > at then
		local wave = math.sin(math.pi * (u - at) / (1 - at))
		back -= OVERLAP.settle * wave * wave
	end
	return back
end

-- `progress` moved ahead (`by` > 0) or behind (`by` < 0) by up to `by`, easing to no offset at the
-- start and the end, so a leading or trailing part starts and settles at its own moment without a
-- jump (overlapping action).
local function offsetProgress(progress: number, by: number): number
	return math.clamp(progress + by * math.sin(math.pi * progress), 0, 1)
end

-- A channel's value at `progress` (0-1) through a motion: from rest, eased out into the wind-up key,
-- snapping into the strike key (AnimationConfig.overlap.snapPower), eased out into the
-- follow-through key, then back to rest with a small overshoot that settles (UnitMotion.settle).
function UnitMotion.keyed(progress: number, timing, keys: { number }?): number
	if not keys then
		return 0
	end
	local a, s, f = timing.windup, timing.strike, timing.follow
	if progress < a then
		return keys[1] * easeOut(progress / a)
	elseif progress < s then
		return lerp(keys[1], keys[2], ((progress - a) / (s - a)) ^ OVERLAP.snapPower)
	elseif progress < f then
		return lerp(keys[2], keys[3], easeOut((progress - s) / (f - s)))
	end
	return keys[3] * UnitMotion.settle((progress - f) / (1 - f))
end

function UnitMotion.style(name: string): Style
	return STYLES[name] or STYLES[AnimationConfig.defaultMelee]
end

-- The attack style of a unit: see AnimationConfig (formStyles, unitStyles, weaponStyles,
-- meleeClasses, rangedClasses). `look` is its Figure look; `range` its current range in hexes;
-- `formName` its current form, if any.
function UnitMotion.styleFor(unitType: string?, range: number, look: any?, formName: string?): string
	local ranged = range > 1
	if formName and AnimationConfig.formStyles[formName] then
		return AnimationConfig.formStyles[formName]
	end
	if unitType and AnimationConfig.unitStyles[unitType] then
		return AnimationConfig.unitStyles[unitType]
	end
	if look and look.attackPose == "point" and ranged then
		return "point"
	end
	if look and look.style == "boss" and not ranged then
		return "heavy"
	end
	if not ranged and look then
		local weapons = look.avatarWeapons or (look.unitLook and look.unitLook.weapons)
		for _, weapon in weapons or {} do
			local style = AnimationConfig.weaponStyles[weapon.kind]
			if style and not weapon.anchor then
				return style
			end
		end
	end
	local character = if unitType then UnitConfig[unitType] else nil
	local class = character and character.classes and character.classes[1]
	if class then
		local style = if ranged then AnimationConfig.rangedClasses[class] else AnimationConfig.meleeClasses[class]
		if style then
			return style
		end
	end
	return if ranged then AnimationConfig.defaultRanged else AnimationConfig.defaultMelee
end

-- How long an attack motion lasts for a unit whose next attack comes `interval` seconds later.
function UnitMotion.duration(style: Style, interval: number?): number
	local duration = style.duration
	if interval and interval > 0 then
		duration = math.min(duration, interval * AnimationConfig.maxIntervalShare)
	end
	return math.max(duration, AnimationConfig.minDuration)
end

-- Seconds from the start of the motion to the strike (the hit lands, or the shot leaves).
function UnitMotion.strikeAfter(style: Style, duration: number): number
	return style.timing.strike * duration
end

-- The longest strike lead any style can have (for looking ahead in the event list).
function UnitMotion.maxStrikeLead(): number
	local most = 0
	for _, style in STYLES do
		most = math.max(most, style.duration * style.timing.strike)
	end
	return most
end

-- Adds an attack at `progress` (0-1) to `pose`. `arm` is the attacking arm (1 left, 2 right).
-- Returns how far the body moves toward the target, in studs at normal size.
-- The attacking arm runs on the style's timing (the strike lands at `timing.strike`); the body
-- leads it, the off arm and the head trail it (AnimationConfig.overlap). The arm swings on an arc
-- (`armOut`), and the weight rocks back, then drops and shifts onto the planted leg (the one
-- opposite the attacking arm) with the legs split.
function UnitMotion.attack(pose, style: Style, progress: number, arm: number): number
	local timing = style.timing
	local body = offsetProgress(progress, OVERLAP.bodyLead)
	local trailing = offsetProgress(progress, -OVERLAP.offArmLag)
	local head = offsetProgress(progress, -OVERLAP.headLag)
	local main = rad(UnitMotion.keyed(progress, timing, style.arm))
	local off = if style.bothArms then main else rad(UnitMotion.keyed(trailing, timing, style.offArm))
	local mainOut = rad(UnitMotion.keyed(progress, timing, style.armOut))
	local offOut = if style.bothArms then mainOut else rad(UnitMotion.keyed(trailing, timing, style.offArmOut))
	if arm == 1 then
		pose.leftArm += main
		pose.rightArm += off
		pose.leftArmOut = (pose.leftArmOut or 0) + mainOut
		pose.rightArmOut = (pose.rightArmOut or 0) + offOut
	else
		pose.rightArm += main
		pose.leftArm += off
		pose.rightArmOut = (pose.rightArmOut or 0) + mainOut
		pose.leftArmOut = (pose.leftArmOut or 0) + offOut
	end
	local lean = UnitMotion.keyed(body, timing, style.lean)
	pose.lean += rad(lean)
	-- Positive twist brings the right shoulder forward; a left-hand attack mirrors it.
	local side = if arm == 1 then -1 else 1
	local twist = rad(UnitMotion.keyed(body, timing, style.twist)) * side
	pose.twist = (pose.twist or 0) + twist
	pose.crouch = (pose.crouch or 0) + UnitMotion.keyed(body, timing, style.crouch)

	-- Weight: onto the planted leg (opposite the attacking arm), the front leg forward and the back
	-- leg back, the upper body rolling over it.
	local weight = UnitMotion.keyed(body, timing, (style :: any).weight or OVERLAP.weight)
	pose.shift = (pose.shift or 0) - side * OVERLAP.strikeShift * weight
	pose.roll = (pose.roll or 0) - side * rad(OVERLAP.strikeRoll) * weight
	local stance = rad(OVERLAP.strikeStance) * math.max(0, weight)
	if arm == 1 then
		pose.rightLeg += stance
		pose.leftLeg -= stance * OVERLAP.backLegShare
	else
		pose.leftLeg += stance
		pose.rightLeg -= stance * OVERLAP.backLegShare
	end

	-- The head: turned against the twist to keep the eyes on the target, and a beat behind the body
	-- (it trails the lean and the twist, then catches up).
	local headLean = UnitMotion.keyed(head, timing, style.lean)
	local headTwist = rad(UnitMotion.keyed(head, timing, style.twist)) * side
	pose.headPitch = (pose.headPitch or 0) + rad(headLean - lean)
	pose.headYaw = (pose.headYaw or 0) - twist * OVERLAP.headCounter + (headTwist - twist)
	return UnitMotion.keyed(body, timing, style.lunge)
end

-- Getting hit at `progress` (0-1): the head snaps back first, then the body squashes and leans
-- back (AnimationConfig.hit). `side` (1 or -1) tips the head to one side. Returns the knock-back
-- share (snaps to 1 just after the hit, eases back to 0).
function UnitMotion.hit(pose, progress: number, side: number?): number
	local config = AnimationConfig.hit
	local recover = 1 - smooth(progress)
	local amount = math.min(1, progress * 8) * recover -- the knock: full almost at once
	local body = math.min(1, math.max(0, progress - config.bodyDelay) * 8) * recover
	pose.crouch = (pose.crouch or 0) + config.squash * body
	pose.lean += rad(config.lean) * body
	local flail = rad(config.armFlail) * body
	pose.leftArm += flail
	pose.rightArm += flail
	local snap = math.min(1, progress * config.headSnap) * UnitMotion.settle(progress)
	pose.headPitch = (pose.headPitch or 0) + rad(config.headLean) * snap
	pose.headRoll = (pose.headRoll or 0) + rad(config.headRoll) * (side or 1) * snap
	return amount
end

-- The cast wind-up, `progress` 0-1: arms rise, the body crouches and leans back a little.
function UnitMotion.castWindup(pose, progress: number)
	local config = AnimationConfig.cast
	local k = easeOut(progress)
	local up = rad(config.windupArms)
	pose.leftArm += (up - pose.leftArm) * k
	pose.rightArm += (up - pose.rightArm) * k
	pose.crouch = (pose.crouch or 0) + config.windupCrouch * k
	pose.lean += rad(config.windupLean) * k
end

-- The release after a cast, `progress` 0-1: arms thrust up, the body springs up and forward, then
-- settles back to rest (the arms dip just past it first: UnitMotion.settle).
function UnitMotion.castRelease(pose, progress: number)
	local config = AnimationConfig.cast
	local hold = if progress < 0.25 then 1 else UnitMotion.settle((progress - 0.25) / 0.75)
	local up = rad(config.releaseArms)
	pose.leftArm += (up - pose.leftArm) * hold
	pose.rightArm += (up - pose.rightArm) * hold
	pose.lean += rad(config.releaseLean) * math.sin(math.pi * progress)
end

-- The signature punch's wind-up (AnimationConfig.signaturePoses.punch), `progress` 0-1: the right
-- fist draws back and the body coils until `stillFrom`, then holds with a faint tremble.
function UnitMotion.punchWindup(pose, progress: number, now: number)
	local config = AnimationConfig.signaturePoses.punch
	local k = smooth(math.min(1, progress / config.stillFrom))
	pose.rightArm += rad(config.windupArm) * k
	pose.leftArm += rad(config.windupOffArm) * k
	pose.twist = (pose.twist or 0) + rad(config.windupTwist) * k
	pose.lean += rad(config.windupLean) * k
	pose.crouch = (pose.crouch or 0) + config.windupCrouch * k
	pose.bob = 0
	if progress > config.stillFrom then
		pose.tilt = (pose.tilt or 0) + config.tremble * math.sin(now * 55)
	end
end

-- The signature punch's release, `progress` 0-1: the fist snaps straight out, holds, recovers.
-- Returns the step in toward the target, studs at normal size.
function UnitMotion.punchRelease(pose, progress: number): number
	local config = AnimationConfig.signaturePoses.punch
	local snap = math.min(1, progress / config.snap)
	local out = if progress < config.hold
		then easeOut(snap)
		else UnitMotion.settle((progress - config.hold) / (1 - config.hold))
	pose.rightArm += rad(config.releaseArm) * out
	pose.leftArm += rad(config.releaseOffArm) * out
	pose.twist = (pose.twist or 0) + rad(config.releaseTwist) * out
	pose.lean += rad(config.releaseLean) * out
	pose.crouch = (pose.crouch or 0) + config.releaseCrouch * out
	return config.lunge * out
end

-- Ultimate pose keys ----------------------------------------------------------------------------
-- A track is { [channel] = { { t, value, ease? }, ... } }, keys in design seconds (relative to the
-- release) and in order; each key's `ease` shapes the way into it: "linear", "in", "out", "inOut"
-- (default), "snap" (slow, then violent: a release), "back" (overshoots, then settles), "hold"
-- (jumps at the key), "quadIn", "quadOut", "expoIn", "expoOut", "backOut" (a bigger overshoot).
-- Channels, so each body part can run on its own timing:
--   leftArm, rightArm          degrees raised forward from the resting angle (set, not added)
--   leftArmOut, rightArmOut    degrees raised out to the side
--   lean, twist, tilt, fall    degrees (twist positive: the right shoulder forward)
--   spin                       degrees, the whole body about the vertical (a spinning attack)
--   leftLeg, rightLeg          degrees forward
--   crouch                     hips dropped, a fraction of leg length
--   tremble                    degrees of a fast sideways shiver (held tension)
--   lunge, rise                studs (normal size) forward along the facing, and up
--   headPitch, headYaw, headRoll  degrees, the head on the neck (pitch positive: a nod forward)
-- A track holds the figure calm (no idle bob) while it plays.

local EASES: { [string]: (number) -> number } = {
	linear = function(t)
		return t
	end,
	["in"] = easeIn,
	out = easeOut,
	inOut = smooth,
	snap = function(t)
		return t * t * t
	end,
	back = function(t)
		local s = 1.7
		t -= 1
		return 1 + t * t * ((s + 1) * t + s)
	end,
	hold = function(t)
		return if t < 1 then 0 else 1
	end,
	-- Named curves for keyframed poses (PoseAnimator): quadratic and exponential in / out, and a
	-- stronger overshoot.
	quadIn = function(t)
		return t * t
	end,
	quadOut = function(t)
		return 1 - (1 - t) * (1 - t)
	end,
	expoIn = function(t)
		return if t <= 0 then 0 else 2 ^ (10 * (t - 1))
	end,
	expoOut = function(t)
		return if t >= 1 then 1 else 1 - 2 ^ (-10 * t)
	end,
	backOut = function(t)
		local s = 2.4
		t -= 1
		return 1 + t * t * ((s + 1) * t + s)
	end,
}
UnitMotion.EASES = EASES

-- A channel's value at design time `t`: the first key's before it, the last key's after it.
function UnitMotion.keyValue(keys: { any }, t: number): number
	if #keys == 0 then
		return 0
	end
	if t <= keys[1][1] then
		return keys[1][2]
	end
	for i = 2, #keys do
		local key = keys[i]
		if t < key[1] then
			local previous = keys[i - 1]
			local span = key[1] - previous[1]
			local u = if span > 0 then (t - previous[1]) / span else 1
			local ease = EASES[key[3] or "inOut"] or smooth
			return previous[2] + (key[2] - previous[2]) * ease(u)
		end
	end
	return keys[#keys][2]
end

local DEGREE_CHANNELS = {
	"leftArmOut",
	"rightArmOut",
	"lean",
	"twist",
	"tilt",
	"fall",
	"leftLeg",
	"rightLeg",
	"spin",
	"headPitch",
	"headYaw",
	"headRoll",
}

-- Applies `track` at design time `t` with weight `w` (0-1) onto `pose`; `rest` is the figure's
-- resting arm angles (radians). Returns the step forward and the rise, studs at normal size.
function UnitMotion.ultimatePose(pose, track, t: number, w: number, rest: { number }, now: number): (number, number)
	local function value(channel: string): number?
		local keys = track[channel]
		return if keys then UnitMotion.keyValue(keys, t) else nil
	end
	local left, right = value("leftArm"), value("rightArm")
	if left then
		pose.leftArm = lerp(pose.leftArm, rest[1] + rad(left), w)
	end
	if right then
		pose.rightArm = lerp(pose.rightArm, rest[2] + rad(right), w)
	end
	for _, channel in DEGREE_CHANNELS do
		local degrees = value(channel)
		if degrees then
			pose[channel] = (pose[channel] or 0) + rad(degrees) * w
		end
	end
	local crouch = value("crouch")
	if crouch then
		pose.crouch = (pose.crouch or 0) + crouch * w
	end
	local tremble = value("tremble")
	if tremble and tremble ~= 0 then
		pose.tilt = (pose.tilt or 0) + rad(tremble) * w * math.sin(now * 55)
	end
	pose.bob *= 1 - w
	return (value("lunge") or 0) * w, (value("rise") or 0) * w
end

-- Held while stunned: droop forward, arms hang, a slow sideways sway.
function UnitMotion.stunned(pose, now: number, phase: number)
	local config = AnimationConfig.stun
	pose.bob = 0
	pose.leftArm *= config.arms
	pose.rightArm *= config.arms
	pose.lean += rad(config.lean)
	pose.tilt = (pose.tilt or 0) + rad(config.sway) * math.sin((now * config.swayRate + phase) * 2 * math.pi)
end

-- Dying at `progress` (0-1 of AnimationConfig.death.duration): a stagger back, then a crumple
-- (falls back, hips drop, arms go limp). Returns the step back (studs at normal size) and how far
-- the body has sunk (studs).
function UnitMotion.death(pose, progress: number): (number, number)
	local config = AnimationConfig.death
	local stagger = math.clamp(progress / config.staggerEnd, 0, 1)
	local crumple = math.clamp((progress - config.staggerEnd) / (config.crumpleEnd - config.staggerEnd), 0, 1)
	local staggerShape = math.sin(math.pi * stagger) * (1 - crumple)
	pose.lean += rad(config.staggerLean) * staggerShape
	pose.tilt = (pose.tilt or 0) + rad(config.staggerTilt) * staggerShape
	local fallen = easeIn(crumple)
	pose.fall += rad(config.fall) * fallen
	pose.crouch = (pose.crouch or 0) + config.crouch * fallen
	local limp = math.max(easeOut(stagger) * 0.4, fallen)
	pose.leftArm = lerp(pose.leftArm + rad(30) * staggerShape, 0, limp)
	pose.rightArm = lerp(pose.rightArm + rad(30) * staggerShape, 0, limp)
	pose.bob = 0
	local sink = config.sink * math.clamp((progress - config.crumpleEnd) / (1 - config.crumpleEnd), 0, 1)
	return config.staggerStep * easeOut(stagger), sink
end

-- A victory cheer at `progress` (0-1): hops with both arms up. Returns the hop height in studs at
-- normal size.
function UnitMotion.victory(pose, progress: number): number
	local config = AnimationConfig.victory
	local raise = math.min(1, progress * 5) * (1 - smooth(math.clamp((progress - 0.8) / 0.2, 0, 1)))
	local up = rad(config.arms)
	pose.leftArm += (up - pose.leftArm) * raise
	pose.rightArm += (up - pose.rightArm) * raise
	local hop = math.abs(math.sin(progress * config.hops * math.pi))
	-- Crouch into each hop and land soft.
	pose.crouch = (pose.crouch or 0) + 0.12 * (1 - hop) * raise
	return config.hopHeight * hop * raise
end

return UnitMotion
