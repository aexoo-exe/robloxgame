-- What each combat moment looks like: attacks (motion, projectile), hits (flash, knock, sparks,
-- numbers, shake, hit-stop), casts (wind-up, release burst, a touch on every target), heals,
-- shields, stuns, deaths and the victory cheer. CombatPlayback calls these as it plays the
-- server's events; the dev lineup preview (DevLineup) calls the same ones on demand. Presentation
-- only: it never changes what happens in a fight or when. Every number is in AnimationConfig.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AnimationConfig = require(Shared:WaitForChild("AnimationConfig"))
local Pve = require(Shared:WaitForChild("Pve"))
local UnitConfig = require(Shared:WaitForChild("UnitConfig"))

local CombatEffects = require(script.Parent.CombatEffects)
local ImpactEffects = require(script.Parent.ImpactEffects)
local UnitMotion = require(script.Parent.UnitMotion)
local UnitView = require(script.Parent.UnitView)

local CombatFx = {}

local COLORS = AnimationConfig.factionColors
local IMPACT = AnimationConfig.impact
local DUST = Color3.fromRGB(190, 180, 165)

-- The faction color of a unit type (AnimationConfig.factionColors): its origin's, or the creep,
-- boss or summon color.
function CombatFx.factionColor(unitType: string?): Color3
	local character = if unitType then UnitConfig[unitType] else nil
	if character then
		return COLORS[character.origin] or COLORS.summon
	end
	local pve = if unitType then Pve.pveUnitType(unitType) else nil
	if pve then
		return if pve.kind == "boss" then COLORS.boss else COLORS.creep
	end
	return COLORS.summon
end

-- One attack's motion: its style, how long it lasts and when its strike comes.
export type Plan = {
	style: string,
	duration: number,
	strikeAfter: number, -- from the start of the motion to the strike (the shot leaves, for ranged)
	ranged: boolean,
}

-- The motion for an attack in style `styleName` by a unit whose next attack comes `interval`
-- seconds later (nil: unknown), so the motion fits between its attacks.
function CombatFx.plan(styleName: string, interval: number?, ranged: boolean): Plan
	local style = UnitMotion.style(styleName)
	local duration = UnitMotion.duration(style, interval)
	return {
		style = styleName,
		duration = duration,
		strikeAfter = UnitMotion.strikeAfter(style, duration),
		ranged = ranged,
	}
end

-- How long before the hit lands the attack's motion starts.
function CombatFx.leadTime(plan: Plan): number
	return plan.strikeAfter + (if plan.ranged then AnimationConfig.projectiles.flightTime else 0)
end

-- The longest any attack or cast starts before its moment, for looking ahead in the event list.
function CombatFx.maxLead(): number
	return math.max(UnitMotion.maxStrikeLead() + AnimationConfig.projectiles.flightTime, AnimationConfig.cast.windup)
end

export type AttackOptions = {
	color: Color3?, -- the projectile's color (ranged)
	tongue: boolean?, -- a stretching tongue instead of a projectile ball (RenderConfig.tongueAttacks)
	noMotion: boolean?, -- no attack motion (a cast's wind-up has taken over); a projectile still flies
}

-- Starts an attack by `attacker` on `target` that lands at `landsAt` (the views' clock): the motion
-- strikes as it lands (melee), or fires so its projectile lands then (ranged).
function CombatFx.attack(
	attacker: UnitView.UnitView,
	target: UnitView.UnitView,
	landsAt: number,
	plan: Plan,
	options: AttackOptions?
)
	local settings: AttackOptions = options or {}
	local launchAt = landsAt - (if plan.ranged then AnimationConfig.projectiles.flightTime else 0)
	if not settings.noMotion then
		UnitView.attack(attacker, target, launchAt - plan.strikeAfter, plan.duration, plan.style)
	end
	if plan.ranged then
		CombatEffects.projectile(attacker, target, landsAt, settings.color or AnimationConfig.projectiles.ownColor, {
			launchAt = launchAt,
			origin = function()
				return UnitView.launchPoint(attacker)
			end,
			look = UnitMotion.style(plan.style).projectile or "shot",
			tongue = settings.tongue,
			scale = UnitView.effectScale(attacker),
		})
	end
end

export type Hit = {
	damage: number,
	damageType: string?, -- CombatMath.DamageType (default physical)
	crit: boolean?,
	ability: boolean?, -- a hit from an ability: bigger burst, shake, a ring in `abilityColor`
	abilityColor: Color3?,
	execute: boolean?,
	shieldBroken: boolean?, -- the hit broke the target's shield
	slam: boolean?, -- a heavy attack's landing: a dust ring
}

-- Shows a hit on `target` from `source` (nil: no attacker to knock away from): the flash, knock and
-- squash, the floating number, sparks in the damage type's color and a flash ball, and for big
-- hits camera shake and hit-stop. Effects grow with the source's star level.
function CombatFx.hit(target: UnitView.UnitView, source: UnitView.UnitView?, hit: Hit)
	local direction = if source then target.part.Position - source.part.Position else nil
	if direction then
		direction = Vector3.new(direction.X, 0, direction.Z)
		if direction.Magnitude < 1e-3 then
			direction = nil
		end
	end
	UnitView.flash(target, hit.crit, direction)
	UnitView.damageNumber(target, hit.damage, hit.damageType, hit.crit, hit.ability)

	local scale = UnitView.effectScale(source or target)
	local colors = IMPACT[hit.damageType or "PHYSICAL"] or IMPACT.PHYSICAL
	local away = if direction then direction.Unit else nil
	local size = target.part.Size
	local point = target.part.Position + Vector3.new(0, size.Y * 0.1, 0)
	if away then
		point -= away * size.X * 0.3 -- the side facing the attacker
	end
	local count = if hit.crit then IMPACT.critSparks elseif hit.ability then IMPACT.abilitySparks else IMPACT.sparks
	ImpactEffects.burst("spark", point, away, {
		color = colors.color,
		count = count * scale,
		size = IMPACT.sparkSize * scale,
		speed = IMPACT.sparkSpeed,
		lifetime = IMPACT.sparkLifetime,
		spread = IMPACT.spread,
	})
	local ball = if hit.crit then IMPACT.critBall elseif hit.ability then IMPACT.abilityBall else IMPACT.ballSize
	ImpactEffects.ball(point, colors.core, ball * scale, IMPACT.ballDuration)

	if hit.ability then
		local color = hit.abilityColor or COLORS.summon
		local feet = target.part.Position - Vector3.new(0, size.Y / 2, 0)
		ImpactEffects.ring(feet, color, AnimationConfig.cast.targetRing * scale)
		ImpactEffects.burst("spark", point, nil, {
			color = color,
			count = AnimationConfig.cast.targetSparks * scale,
			size = IMPACT.sparkSize * scale,
			speed = IMPACT.sparkSpeed,
			lifetime = IMPACT.sparkLifetime,
		})
	end
	if hit.slam then
		local feet = target.part.Position - Vector3.new(0, size.Y / 2, 0)
		ImpactEffects.ring(feet, DUST, 3.4 * scale, 0.3)
		ImpactEffects.burst("puff", feet, nil, {
			color = DUST,
			count = 5 * scale,
			size = 0.5 * scale,
			speed = { 3, 6 },
			lifetime = { 0.25, 0.45 },
			transparency = 0.35,
		})
	end
	if hit.shieldBroken then
		ImpactEffects.burst("spark", target.part.Position, nil, {
			color = IMPACT.shieldBreak,
			count = IMPACT.shieldBreakSparks * scale,
			size = IMPACT.sparkSize * 1.4 * scale,
			speed = { 6, 12 },
			lifetime = { 0.2, 0.4 },
		})
	end

	local stop = AnimationConfig.hitStop
	local big = hit.crit == true or hit.execute == true or hit.damage >= stop.bigShare * math.max(target.maxHealth, 1)
	local shake = AnimationConfig.shake
	local kick = 0
	if hit.crit then
		kick = math.max(kick, shake.crit)
	end
	if hit.ability then
		kick = math.max(kick, shake.ability)
	end
	if big and (hit.crit or hit.ability or hit.execute) then
		kick = math.max(kick, shake.big)
	end
	if hit.slam then
		kick = math.max(kick, shake.slam)
	end
	if kick > 0 then
		ImpactEffects.shake(kick)
	end
	if big then
		local seconds = if hit.crit and hit.damage < stop.bigShare * target.maxHealth
			then stop.duration
			else stop.bigDuration
		UnitView.hitStop(target, seconds, true)
		if source then
			UnitView.hitStop(source, seconds)
		end
	end
end

-- A damage-over-time tick: only its small number.
function CombatFx.dot(target: UnitView.UnitView, damage: number, damageType: string?)
	UnitView.dotNumber(target, damage, damageType)
end

-- A cast wind-up from `startAt` to `releaseAt` in the caster's faction `color`.
function CombatFx.castWindup(view: UnitView.UnitView, startAt: number, releaseAt: number, color: Color3)
	UnitView.castWindup(view, startAt, releaseAt, color)
end

-- The cast's release: the pose, the flash in `color`, and a burst at the caster (a ring, a flash ball
-- and sparks all around).
function CombatFx.castRelease(view: UnitView.UnitView, color: Color3)
	UnitView.cast(view, color)
	local config = AnimationConfig.cast
	local scale = UnitView.effectScale(view)
	local size = view.part.Size
	local chest = view.part.Position + Vector3.new(0, size.Y * 0.15, 0)
	ImpactEffects.ring(view.part.Position - Vector3.new(0, size.Y / 2, 0), color, config.burstRing * scale, 0.4)
	ImpactEffects.ball(chest, color, config.burstBall * scale, 0.2)
	ImpactEffects.burst("spark", chest, nil, {
		color = color,
		count = config.burstSparks * scale,
		size = IMPACT.sparkSize * 1.2 * scale,
		speed = { 8, 15 },
		lifetime = { 0.2, 0.35 },
	})
end

-- An ability reaching a target without damage (a stun, a buff, a heal, a shield): a small ring and
-- sparkles in the caster's color.
function CombatFx.abilityTouch(target: UnitView.UnitView, color: Color3, scale: number?)
	local config = AnimationConfig.cast
	local size = target.part.Size
	local s = scale or 1
	ImpactEffects.ring(target.part.Position - Vector3.new(0, size.Y / 2, 0), color, config.targetRing * s)
	ImpactEffects.burst("mote", target.part.Position, nil, {
		color = color,
		count = config.targetSparks * s,
		size = IMPACT.sparkSize * s,
		speed = { 2, 4 },
		lifetime = { 0.3, 0.5 },
	})
end

-- A heal: the number, green motes rising and a soft ring at the feet.
function CombatFx.heal(target: UnitView.UnitView, amount: number)
	local config = AnimationConfig.heal
	UnitView.healNumber(target, amount)
	local size = target.part.Size
	local scale = UnitView.effectScale(target)
	ImpactEffects.ring(target.part.Position - Vector3.new(0, size.Y / 2, 0), config.color, config.ring * scale)
	ImpactEffects.burst("mote", target.part.Position - Vector3.new(0, size.Y * 0.2, 0), Vector3.yAxis, {
		color = config.color,
		count = config.motes * scale,
		size = 0.3 * scale,
		speed = config.moteSpeed,
		lifetime = { 0.45, 0.7 },
		spread = 35,
	})
end

-- A new shield: the bubble pops in with a ring at the feet.
function CombatFx.shield(target: UnitView.UnitView)
	local config = AnimationConfig.shield
	UnitView.shieldPop(target)
	local size = target.part.Size
	ImpactEffects.ring(
		target.part.Position - Vector3.new(0, size.Y / 2, 0),
		config.color,
		config.ring * UnitView.effectScale(target)
	)
end

-- A stun: the held pose and halo with stars (UnitView.stun), and a small flash of yellow over the
-- head when fresh.
function CombatFx.stun(target: UnitView.UnitView, seconds: number, fresh: boolean)
	UnitView.stun(target, seconds)
	if fresh and seconds > 0 then
		local head = target.part.Position + Vector3.new(0, target.part.Size.Y * 0.5, 0)
		ImpactEffects.burst("spark", head, nil, {
			color = Color3.fromRGB(255, 230, 60),
			count = 6,
			size = IMPACT.sparkSize,
			speed = { 3, 6 },
			lifetime = { 0.2, 0.35 },
		})
	end
end

-- A death: the stagger (away from `killer`, if known), crumple, fade and puff.
function CombatFx.death(view: UnitView.UnitView, killer: UnitView.UnitView?)
	local direction = if killer then view.part.Position - killer.part.Position else nil
	UnitView.kill(view, direction)
end

-- The victory cheer for `views` (the winning side's survivors), starting at `startAt`.
function CombatFx.victory(views: { UnitView.UnitView }, startAt: number)
	for i, view in views do
		-- A little out of step, so they do not hop as one.
		UnitView.cheer(view, startAt + (i % 3) * 0.06)
	end
end

return CombatFx
