-- Hand-made signature effects that override parts of a unit's generated ability effect
-- (AbilityFx). AbilityFxConfig.signatures maps a unit id to a `kind` here plus that kind's
-- settings. A kind may define any of these hooks; each returns true when it has drawn that part
-- itself (the generated version is then skipped):
--   windup(spec, view, startAt, releaseAt, style)   the cast's wind-up
--   release(spec, view, style)                       the moment of the cast
--   strike(spec, source, target, style)              each single-target ability hit
-- and `windup` in its settings sets the wind-up's length. Add a kind to add a signature (pass 3).
-- Presentation only.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AbilityFxConfig = require(Shared:WaitForChild("AbilityFxConfig"))
local AnimationConfig = require(Shared:WaitForChild("AnimationConfig"))
local RenderConfig = require(Shared:WaitForChild("RenderConfig"))

local FxKit = require(script.Parent.FxKit)
local ImpactEffects = require(script.Parent.ImpactEffects)
local UnitView = require(script.Parent.UnitView)

local AbilitySignatures = {}

-- A unit's ability style (AbilityFx.Style).
export type Style = { element: string, def: any, primary: Color3, secondary: Color3 }
export type Kind = {
	windup: ((any, UnitView.UnitView, number, number, Style) -> boolean)?,
	release: ((any, UnitView.UnitView, Style) -> boolean)?,
	strike: ((any, UnitView.UnitView?, UnitView.UnitView, Style) -> boolean)?,
}

local HEX = math.sqrt(3) * RenderConfig.hexRadius
local WHITE = Color3.new(1, 1, 1)
local DUST = Color3.fromRGB(200, 188, 168)

local function ground(view: UnitView.UnitView): Vector3
	return view.part.Position - Vector3.new(0, view.part.Size.Y / 2, 0)
end
local function chest(view: UnitView.UnitView): Vector3
	return view.part.Position + Vector3.new(0, view.part.Size.Y * 0.1, 0)
end

local kinds: { [string]: Kind } = {}

-- THE punch: a slow, heavy wind-up with energy gathering at the drawn-back fist and a beat of
-- stillness; then one punch that blasts a zone in front of him.
kinds.punch = {
	windup = function(spec, view, startAt, releaseAt, style)
		UnitView.castWindup(view, startAt, releaseAt, style.primary, "punch", spec.orbSize)
		return true
	end,
	release = function(_spec, view, style)
		UnitView.cast(view, style.primary, "punch", AnimationConfig.signaturePoses.punch.release)
		local hand = view.figure.anchors.rightHand
		ImpactEffects.ball(if hand then hand.Position else chest(view), WHITE, 1.6, 0.12)
		return true
	end,
	strike = function(spec, source, target, style)
		local scale = UnitView.effectScale(source or target)
		local direction = if source then target.part.Position - source.part.Position else Vector3.zAxis
		direction = Vector3.new(direction.X, 0, direction.Z)
		direction = if direction.Magnitude > 1e-3 then direction.Unit else Vector3.zAxis
		local point = chest(target) - direction * target.part.Size.X * 0.3
		local floor = ground(target)
		-- The impact flash and the blast of air past the target, along the punch.
		ImpactEffects.ball(point, WHITE, spec.flashSize * scale, 0.2)
		ImpactEffects.ball(point, style.primary, spec.flashSize * 1.4 * scale, 0.3)
		FxKit.pressureCone(point, direction, spec.coneLength * HEX, math.rad(spec.coneHalfAngle), style.primary, 0.5)
		FxKit.pressureCone(
			point,
			direction,
			spec.coneLength * HEX * 0.7,
			math.rad(spec.coneHalfAngle) * 0.6,
			WHITE,
			0.35,
			0.03
		)
		ImpactEffects.burst("shock", point, direction, {
			color = WHITE,
			count = 3,
			size = 1.4 * scale,
			speed = { 6, 10 },
			lifetime = { 0.25, 0.35 },
			spread = 5,
			transparency = 0.2,
		})
		ImpactEffects.burst("spark", point, direction, {
			color = style.primary,
			color2 = style.secondary,
			count = 26 * scale,
			size = 0.32 * scale,
			speed = { 18, 32 },
			lifetime = { 0.2, 0.4 },
			spread = spec.coneHalfAngle,
		})
		-- The ground cracks under the target and dust blows out.
		FxKit.mark(floor, DUST, style.secondary, spec.crackSize / 2 * scale, "crack", 1.8)
		FxKit.ring(floor, style.primary, spec.crackSize * 1.3 * scale, 0.45)
		FxKit.ring(floor, WHITE, spec.crackSize * 0.8 * scale, 0.3, 0.05)
		ImpactEffects.burst("puff", floor + Vector3.new(0, 0.4, 0), nil, {
			color = DUST,
			count = spec.dustCount * scale,
			size = 1.1 * scale,
			speed = { 6, 12 },
			lifetime = { 0.5, 0.9 },
			transparency = 0.3,
		})
		ImpactEffects.shake(spec.shake)
		UnitView.hitStop(target, spec.hitStop, true, true)
		if source then
			UnitView.hitStop(source, spec.hitStop, false, true)
		end
		return true
	end,
}

-- The signature of a unit type, if it has one: its settings and its kind.
function AbilitySignatures.of(unitType: string?): (any?, Kind?)
	local spec = if unitType then AbilityFxConfig.signatures[unitType] else nil
	if not spec then
		return nil, nil
	end
	return spec, kinds[spec.kind]
end

-- The longest signature wind-up (for looking ahead in the event list).
function AbilitySignatures.maxWindup(): number
	local most = 0
	for _, spec in AbilityFxConfig.signatures do
		most = math.max(most, spec.windup or 0)
	end
	return most
end

return AbilitySignatures
