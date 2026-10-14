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

-- A channel's value at `progress` (0-1) through a motion: from rest, eased out into the wind-up key,
-- accelerating into the strike key, eased out into the follow-through key, then smoothly back to
-- rest (AnimationConfig.styles).
function UnitMotion.keyed(progress: number, timing, keys: { number }?): number
	if not keys then
		return 0
	end
	local a, s, f = timing.windup, timing.strike, timing.follow
	if progress < a then
		return keys[1] * easeOut(progress / a)
	elseif progress < s then
		return lerp(keys[1], keys[2], easeIn((progress - a) / (s - a)))
	elseif progress < f then
		return lerp(keys[2], keys[3], easeOut((progress - s) / (f - s)))
	end
	return keys[3] * (1 - smooth(math.clamp((progress - f) / (1 - f), 0, 1)))
end

function UnitMotion.style(name: string): Style
	return STYLES[name] or STYLES[AnimationConfig.defaultMelee]
end

-- The attack style of a unit: see AnimationConfig (unitStyles, weaponStyles, meleeClasses,
-- rangedClasses). `look` is its Figure look; `range` its current range in hexes.
function UnitMotion.styleFor(unitType: string?, range: number, look: any?): string
	local ranged = range > 1
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
function UnitMotion.attack(pose, style: Style, progress: number, arm: number): number
	local timing = style.timing
	local main = rad(UnitMotion.keyed(progress, timing, style.arm))
	local off = if style.bothArms then main else rad(UnitMotion.keyed(progress, timing, style.offArm))
	if arm == 1 then
		pose.leftArm += main
		pose.rightArm += off
	else
		pose.rightArm += main
		pose.leftArm += off
	end
	pose.lean += rad(UnitMotion.keyed(progress, timing, style.lean))
	-- Positive twist brings the right shoulder forward; a left-hand attack mirrors it.
	local twist = rad(UnitMotion.keyed(progress, timing, style.twist))
	pose.twist = (pose.twist or 0) + (if arm == 1 then -twist else twist)
	pose.crouch = (pose.crouch or 0) + UnitMotion.keyed(progress, timing, style.crouch)
	return UnitMotion.keyed(progress, timing, style.lunge)
end

-- Getting hit at `progress` (0-1): the squash and lean back. Returns the knock-back share (snaps to
-- 1 just after the hit, eases back to 0).
function UnitMotion.hit(pose, progress: number): number
	local config = AnimationConfig.hit
	local snap = math.min(1, progress * 8) -- reaches full squash almost at once
	local recover = 1 - smooth(progress)
	local amount = snap * recover
	pose.crouch = (pose.crouch or 0) + config.squash * amount
	pose.lean += rad(config.lean) * amount
	local flail = rad(config.armFlail) * amount
	pose.leftArm += flail
	pose.rightArm += flail
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
-- settles back to rest.
function UnitMotion.castRelease(pose, progress: number)
	local config = AnimationConfig.cast
	local hold = if progress < 0.25 then 1 else 1 - smooth((progress - 0.25) / 0.75)
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
		else 1 - smooth((progress - config.hold) / (1 - config.hold))
	pose.rightArm += rad(config.releaseArm) * out
	pose.leftArm += rad(config.releaseOffArm) * out
	pose.twist = (pose.twist or 0) + rad(config.releaseTwist) * out
	pose.lean += rad(config.releaseLean) * out
	pose.crouch = (pose.crouch or 0) + config.releaseCrouch * out
	return config.lunge * out
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
