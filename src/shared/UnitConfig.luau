-- Roster v1.1: 42 characters (9/9/10/9/5 by cost) with stats from docs/design/revamp-roster.md
-- (Block 2, roster block updated for Overhaul 1) and abilities from Block 2, except the 30 reworked
-- in Overhaul 1 (docs/design/overhaul-1.md). Each character's key is a neutral internal id taken
-- from its ability; ability names are the same ids (form abilities add a suffix). Everything
-- players see (names, ability names, colors) lives in SkinConfig, never here.
--
-- Fields:
--   cost              gold price and shop tier (1-5)
--   origin, classes   trait membership (the origin is the faction); data only
--   health            base health, before CombatConfig.globalHealthMultiplier
--   attackDamage, abilityPower, armor, magicResist
--   attacksPerSecond  attack rate
--   range             attack range in hexes (1 = melee)
--   moveSpeed         movement scalar (x CombatConfig.baseMoveSpeed hexes per second)
--   startingMana, maxMana
--   ability           data for the generic interpreter in Abilities.luau; per-star values are
--                     { 1-star, 2-star, 3-star }
--   forms             optional ordered list of forms (transformations); the unit starts each fight
--                     in the first. See Forms.luau and docs/forms.md. Their numbers live in
--                     FormConfig.
--   aura, attackStacks  optional passives (Abilities.validateUnit)
--
-- Abilities resolve every selector once, before any effect. Where an ability dashes to an enemy
-- and then hits "it", the dash sets the retarget flag and the later effects name the dash's own
-- selector, so they hit the same enemy. The new Overhaul 1 amounts are placeholders chosen to keep
-- each character near its old output for its cost; they are listed in docs/design/overhaul-1.md.

local AbilityConfig = if script then require(script.Parent.AbilityConfig) else require("./AbilityConfig")
local FormConfig = if script then require(script.Parent.FormConfig) else require("./FormConfig")

-- Freezes a table and every table inside it. Tables that are already frozen (shared between
-- entries, or frozen by another config module) are left as they are.
local function freezeAll(value)
	if type(value) == "table" and not table.isfrozen(value) then
		for _, child in value do
			freezeAll(child)
		end
		table.freeze(value)
	end
	return value
end

-- A character: cost, origin, classes, health, AD, armor, MR, attack speed, range, move speed,
-- starting mana, max mana, and the ability's effects (its name is the character's id). `options`
-- adds ability-level options (castTime, selfStun, ...).
local function unit(cost, origin, classes, health, ad, armor, mr, as, range, move, startMana, maxMana)
	return function(id, effects, options)
		local ability = { name = id, effects = effects }
		for key, value in options or {} do
			ability[key] = value
		end
		return {
			cost = cost,
			origin = origin,
			classes = classes,
			health = health,
			attackDamage = ad,
			abilityPower = 100,
			armor = armor,
			magicResist = mr,
			attacksPerSecond = as,
			range = range,
			moveSpeed = move,
			startingMana = startMana,
			maxMana = maxMana,
			ability = ability,
		}
	end
end

local roster = {}

local function add(id, make, effects, options)
	roster[id] = make(id, effects, options)
end

-- An ability for a form (its name is the character's id and a suffix).
local function formAbility(id: string, suffix: string, effects, options)
	local ability = { name = id .. "_" .. suffix, effects = effects }
	for key, value in options or {} do
		ability[key] = value
	end
	return ability
end

-- A form ability that only fires the form's ON_CAST trigger.
local function transformOnly(id: string, suffix: string)
	return { name = id .. "_" .. suffix, effects = {}, formOnly = true }
end

-- Adds `extra` fields (delay, condition, bonus, ...) to an effect.
local function with(effect, extra)
	for key, value in extra do
		effect[key] = value
	end
	return effect
end

local function dash(target, distance, retarget)
	return {
		type = "DASH",
		target = target,
		distance = distance,
		mode = "OFFENSIVE",
		setsCurrentTarget = if retarget then true else nil,
	}
end

local function damage(target, damageType, amount)
	return { type = "DAMAGE", target = target, damageType = damageType, amount = amount }
end

local function area(center, radius, damageType, amount)
	return { type = "AREA_DAMAGE", center = center, radius = radius, damageType = damageType, amount = amount }
end

-- A line from the caster through `center`, `length` hexes past it (nil: to the board edge).
local function line(center, damageType, amount, length, afterTarget)
	return {
		type = "AREA_DAMAGE",
		center = center,
		shape = "LINE",
		length = length,
		startAfterTarget = if afterTarget then true else nil,
		damageType = damageType,
		amount = amount,
	}
end

-- A cone from the caster toward `center`, `radius` hexes long, `falloff` percent weaker per hex.
local function cone(center, radius, damageType, amount, falloff)
	return {
		type = "AREA_DAMAGE",
		center = center,
		shape = "CONE",
		radius = radius,
		falloff = falloff,
		damageType = damageType,
		amount = amount,
	}
end

local function buffPercent(target, stat, percent, duration)
	return { type = "BUFF", target = target, stat = stat, percent = percent, duration = duration }
end

local function buffFlat(target, stat, flat, duration)
	return { type = "BUFF", target = target, stat = stat, flat = flat, duration = duration }
end

local function heal(target, amount)
	return { type = "HEAL", target = target, amount = amount }
end

local function shield(target, amount, duration)
	return { type = "SHIELD", target = target, amount = amount, duration = duration }
end

local function stun(target, duration)
	return { type = "STUN", target = target, duration = duration }
end

local function areaStun(center, radius, duration)
	return { type = "AREA_STUN", center = center, radius = radius, duration = duration }
end

local function debuff(target, status, percent, duration)
	return { type = "DEBUFF", target = target, status = status, percent = percent, duration = duration }
end

local function bounce(target, count, damageType, amount)
	return { type = "BOUNCE", target = target, count = count, damageType = damageType, amount = amount }
end

-- Damage over time centered on `center` within `radius` (nil: the target only), ticking every second.
local function dot(center, radius, damageType, amount, duration)
	return {
		type = "DAMAGE_OVER_TIME",
		center = if radius then center else nil,
		target = if radius then nil else center,
		radius = radius,
		damageType = damageType,
		amount = amount,
		interval = 1,
		duration = duration,
	}
end

local function summon(count, duration, health, ad, resist, attackSpeed, range, move)
	return {
		type = "SUMMON",
		count = count,
		duration = duration,
		healthPercent = health,
		attackDamagePercent = ad,
		armorPercent = resist,
		magicResistPercent = resist,
		attackSpeedPercent = attackSpeed,
		range = range,
		moveSpeed = move,
	}
end

-- A summon that lasts until killed or recalled (no duration).
local function lastingSummon(count, health, ad, resist, attackSpeed, range, move)
	local effect = summon(count, nil, health, ad, resist, attackSpeed, range, move)
	effect.permanent = true
	return effect
end

-- Rider mounts: the rider starts each fight Mounted, on a horse with its own health pool that takes
-- every hit, and drops to Dismounted when the horse's pool runs out. The mounted speed bonus is the
-- riders' former extra move speed (Block 2 lists them at 1.2; their base is now 1.0). With
-- FormConfig.mount.remountEnabled, Dismounted gets a takedown trigger back to Mounted; without it the
-- trigger is there but only fires for riders with the remount flag (the riders' bond).
local function mountedForms(id: string, dismountedAbility)
	local mount = FormConfig.mount
	return {
		{
			name = "Mounted",
			health = mount.horseHealth[id],
			stats = {
				MoveSpeed = { flat = mount.mountedMoveSpeedBonus },
				AD = { flat = mount.mountedBonusDamage },
			},
			trigger = { type = "FORM_HEALTH_DEPLETED" },
		},
		{
			name = "Dismounted",
			ability = dismountedAbility,
			trigger = {
				type = "TAKEDOWN",
				to = "Mounted",
				healthPercent = mount.remountHorseHealthPercent,
				maxUses = mount.remountsPerFight,
				unlockedBy = if mount.remountEnabled then nil else mount.remountFlag,
			},
		},
	}
end

-- 1-cost --------------------------------------------------------------------------------------

add("flashline", unit(1, "Hunters", { "Blade", "Assassin" }, 560, 81, 20, 20, 0.78, 1, 1.1, 20, 90), {
	dash("FARTHEST_ENEMY", 4, true),
	damage("FARTHEST_ENEMY", "PHYSICAL", { 350, 565, 900 }),
})
add("cinder_arc", unit(1, "Hunters", { "Blade" }, 650, 57, 28, 25, 0.70, 1, 1.0, 30, 90), {
	damage("CURRENT_TARGET", "PHYSICAL", { 165, 265, 425 }),
	area("CURRENT_TARGET", 1, "MAGIC", { 100, 165, 265 }),
	buffPercent("SELF", "AttackSpeed", { 18, 28, 42 }, 5),
})
add("wolfstep", unit(1, "Corps", { "Blade" }, 590, 72, 22, 20, 0.77, 1, 1.1, 20, 80), {
	dash("HIGHEST_AD_ENEMY", 3, true),
	damage("HIGHEST_AD_ENEMY", "PHYSICAL", { 340, 540, 865 }),
})
-- Spin stacks: basic attacks on one target build up to 4; at 4 he fires (the mana bar shows the
-- stacks). The shot grows 15% per stack, slows, and heals the horse (a smaller self-heal on foot).
local function spurshotShot(heals)
	local effects = {
		with(damage("CURRENT_TARGET", "PHYSICAL", { 120, 190, 305 }), { bonus = { type = "STACKS", percent = 15 } }),
		debuff("CURRENT_TARGET", "SLOW", { 25, 30, 35 }, 2),
	}
	table.insert(effects, heals)
	return effects
end
add(
	"spurshot",
	unit(1, "Spirit", { "Marksman", "Brawler" }, 650, 56, 18, 18, 0.76, 2, 1.0, 0, 80),
	spurshotShot(with(heal("SELF", { 80, 130, 210 }), { pool = true }))
)
roster.spurshot.attackStacks = { max = 4, castAtMax = true }
roster.spurshot.forms =
	mountedForms("spurshot", formAbility("spurshot", "dismounted", spurshotShot(heal("SELF", { 50, 80, 130 }))))
-- First cast: the chainsaw form for the rest of the fight (faster attacks that splash); in it, a
-- self-heal.
add("ripcord_frenzy", unit(1, "Cursed", { "Brawler" }, 700, 70, 28, 24, 0.72, 1, 1.0, 30, 90), {}, { formOnly = true })
roster.ripcord_frenzy.forms = {
	{ name = "Unarmed", trigger = { type = "ON_CAST" } },
	{
		name = "Chainsaw",
		stats = { AttackSpeed = { percent = FormConfig.ripcordFrenzy.chainsawAttackSpeedPercent } },
		splash = { percent = FormConfig.ripcordFrenzy.chainsawSplashPercent },
		ability = formAbility("ripcord_frenzy", "chainsaw", { heal("SELF", { 100, 160, 255 }) }),
	},
}
add("null_edge", unit(1, "Arcane", { "Blade" }, 680, 64, 30, 35, 0.68, 1, 1.0, 30, 90), {
	damage("CURRENT_TARGET", "PHYSICAL", { 325, 525, 840 }),
	buffFlat("SELF", "MR", { 25, 40, 65 }, 5),
})
-- Poisoned enemies also deal less damage while the poison lasts.
add("bitter_vapor", unit(1, "Arcane", { "Support" }, 580, 43, 20, 30, 0.62, 3, 1.0, 40, 100), {
	with(dot("CURRENT_TARGET", 1, "MAGIC", { 22, 35, 56 }, 4), { status = "POISON", weakenPercent = { 20, 25, 30 } }),
	heal("LOWEST_HP_ALLY", { 70, 110, 175 }),
})
-- Charges his current target (moving only as needed), stuns it and knocks it back a hex.
add("iron_rush", unit(1, "Titans", { "Guardian" }, 750, 48, 40, 35, 0.56, 1, 0.9, 40, 100), {
	buffFlat("SELF", "Armor", { 30, 45, 70 }, 5),
	dash("CURRENT_TARGET", 2),
	damage("CURRENT_TARGET", "PHYSICAL", { 85, 135, 215 }),
	stun("CURRENT_TARGET", { 0.75, 1, 1.5 }),
	{ type = "KNOCKBACK", target = "CURRENT_TARGET" },
})
-- Heals the lowest-health ally if anyone is low; otherwise hits her current target.
local bloomingLow = { type = "ALLY_BELOW", healthPercent = AbilityConfig.bloomingAidHealBelowPercent }
add("blooming_aid", unit(1, "Shinobi", { "Support" }, 600, 46, 22, 28, 0.65, 2, 1.0, 40, 100), {
	with(heal("LOWEST_HP_ALLY", { 120, 190, 305 }), { condition = bloomingLow }),
	with(damage("CURRENT_TARGET", "PHYSICAL", { 150, 240, 385 }), {
		condition = { type = "ALLY_BELOW", healthPercent = bloomingLow.healthPercent, negate = true },
	}),
})

-- 2-cost --------------------------------------------------------------------------------------

-- Dashes to the enemy attacking her lowest-health ally (fallback: her current target).
add("redline_cut", unit(2, "Corps", { "Blade", "Guardian" }, 690, 68, 27, 25, 0.83, 1, 1.1, 20, 80), {
	dash("ATTACKER_OF_LOWEST_ALLY", 3, true),
	damage("ATTACKER_OF_LOWEST_ALLY", "PHYSICAL", { 215, 345, 550 }),
	buffPercent("SELF", "AttackSpeed", { 20, 32, 50 }, 4),
})
-- Short mana bar; an instant dash-strike on the lowest-health enemy within 2 hexes.
add("flare_kick", unit(2, "Crew", { "Brawler", "Assassin" }, 760, 69, 30, 27, 0.78, 1, 1.1, 15, 50), {
	dash("LOWEST_HP_ENEMY_NEARBY", AbilityConfig.flareKickRange, true),
	damage("LOWEST_HP_ENEMY_NEARBY", "PHYSICAL", { 110, 175, 280 }),
}, { castTime = 0, resetAttackTimer = true, nearbyRange = AbilityConfig.flareKickRange })
add("burst_vector", unit(2, "Heroes", { "Caster", "Marksman" }, 650, 52, 22, 24, 0.78, 4, 1.0, 20, 80), {
	area("CURRENT_TARGET", 1, "MAGIC", { 80, 130, 205 }),
	buffPercent("SELF", "AD", { 10, 15, 25 }, 4),
})
-- A heavy hit, and a line of half damage through the enemies behind the target.
add("skybreaker", unit(2, "Heroes", { "Brawler" }, 820, 66, 35, 30, 0.70, 1, 1.0, 30, 90), {
	damage("CURRENT_TARGET", "PHYSICAL", { 210, 335, 535 }),
	line("CURRENT_TARGET", "PHYSICAL", { 105, 170, 270 }, 2, true),
})
-- Stronger the more health he is missing; a big heal only if it kills.
add("crimson_hunger", unit(2, "Cursed", { "Assassin" }, 720, 70, 26, 27, 0.82, 1, 1.1, 20, 80), {
	with(
		damage("CURRENT_TARGET", "PHYSICAL", { 200, 320, 510 }),
		{ bonus = { type = "MISSING_HEALTH", percent = 100 } }
	),
	with(heal("SELF", { 250, 400, 640 }), { condition = { type = "KILLED" } }),
})
-- Damage and stun, then a bounce to the nearest other enemy (two bounces while mounted).
local function orbitBreakerEffects(bounces)
	return {
		damage("CURRENT_TARGET", "PHYSICAL", { 85, 140, 225 }),
		stun("CURRENT_TARGET", { 1, 1.5, 2 }),
		bounce("CURRENT_TARGET", bounces, "PHYSICAL", { 40, 65, 100 }),
	}
end
add("orbit_breaker", unit(2, "Spirit", { "Marksman" }, 660, 54, 23, 25, 0.82, 3, 1.0, 20, 90), orbitBreakerEffects(2))
roster.orbit_breaker.forms =
	mountedForms("orbit_breaker", formAbility("orbit_breaker", "dismounted", orbitBreakerEffects(1)))
-- A slam around himself that heals him per enemy hit.
add("marsh_fortress", unit(2, "Shinobi", { "Guardian" }, 900, 52, 45, 42, 0.58, 1, 0.9, 40, 110), {
	with(area("SELF", 1, "PHYSICAL", { 110, 175, 280 }), { healPerHit = { 60, 95, 150 } }),
})
-- First cast: two wolves that stay until killed and feed him mana. Later casts: an area hit and
-- stun on his current target, and dead wolves come back (AbilityConfig.shadePackResummon).
local function shadeWolves(refill)
	local wolves = lastingSummon({ 2, 2, 3 }, { 30, 35, 40 }, { 45, 50, 55 }, 50, 90, 1, 1.1)
	wolves.manaPerHit = AbilityConfig.shadePackManaPerHit
	wolves.refill = if refill then true else nil
	return wolves
end
local packEffects = {
	area("CURRENT_TARGET", 1, "MAGIC", { 180, 290, 460 }),
	areaStun("CURRENT_TARGET", 1, { 0.75, 1, 1.25 }),
}
if AbilityConfig.shadePackResummon then
	table.insert(packEffects, shadeWolves(true))
end
add("shade_pack", unit(2, "Cursed", { "Caster" }, 650, 50, 23, 30, 0.67, 3, 1.0, 30, 100), { shadeWolves(false) })
roster.shade_pack.forms = {
	{ name = "Lurking", trigger = { type = "ON_CAST" } },
	{ name = "Pack Out", ability = formAbility("shade_pack", "pack", packEffects) },
}
-- Heals every ally. Below half health (once per fight) a melee bruiser form with a heavy hit.
add("field_medic", unit(2, "Crew", { "Support", "Brawler" }, 640, 46, 24, 32, 0.68, 3, 1.0, 40, 110), {
	heal("ALL_ALLIES", { 45, 70, 110 }),
})
roster.field_medic.forms = {
	{
		name = "Medic",
		trigger = { type = "HEALTH_BELOW", belowPercent = FormConfig.fieldMedic.bruiserBelowPercent, maxUses = 1 },
	},
	{
		name = "Bruiser",
		range = FormConfig.fieldMedic.bruiserRange,
		stats = {
			AD = { flat = FormConfig.fieldMedic.bruiserAttackDamageFlat },
			AttackSpeed = { percent = FormConfig.fieldMedic.bruiserAttackSpeedPercent },
			Armor = { flat = FormConfig.fieldMedic.bruiserArmorFlat },
		},
		ability = formAbility("field_medic", "bruiser", { damage("CURRENT_TARGET", "PHYSICAL", { 200, 320, 510 }) }),
	},
}

-- 3-cost --------------------------------------------------------------------------------------

-- Lunges at his current target (moving only as needed), stuns it, then burns it.
add("volt_spear", unit(3, "Shinobi", { "Blade", "Assassin" }, 790, 79, 28, 30, 0.88, 1, 1.1, 20, 90), {
	dash("CURRENT_TARGET", 2),
	damage("CURRENT_TARGET", "MAGIC", { 300, 480, 770 }),
	stun("CURRENT_TARGET", { 0.75, 1.25, 1.75 }),
	with(dot("CURRENT_TARGET", nil, "MAGIC", { 30, 48, 76 }, 3), { status = "BURN" }),
})
add("thunder_nest", unit(3, "Hunters", { "Assassin" }, 770, 78, 26, 27, 0.90, 1, 1.2, 20, 90), {
	dash("HIGHEST_AD_ENEMY", 3, false),
	area("SELF", 1, "MAGIC", { 250, 400, 640 }),
	areaStun("SELF", 1, { 1, 1.5, 2 }),
})
-- Two hits on his current target, then a slam around himself that also stuns the target.
add("threefold_crash", unit(3, "Crew", { "Blade" }, 900, 80, 38, 32, 0.78, 1, 1.0, 30, 100), {
	damage("CURRENT_TARGET", "PHYSICAL", { 120, 190, 305 }),
	with(damage("CURRENT_TARGET", "PHYSICAL", { 120, 190, 305 }), { delay = 0.25 }),
	with(area("SELF", 1, "PHYSICAL", { 140, 225, 360 }), { delay = 0.5 }),
	with(stun("CURRENT_TARGET", { 0.75, 1.25, 1.75 }), { delay = 0.5 }),
})
-- A smaller human; below half health (once per fight) a titan with its own health pool, more AD
-- and splash, back to human when the pool is empty. Both forms cast a heavy hit.
add("titanheart", unit(3, "Titans", { "Guardian", "Brawler" }, 1050, 65, 50, 45, 0.62, 1, 0.9, 40, 180), {
	damage("CURRENT_TARGET", "PHYSICAL", { 215, 345, 555 }),
})
local titan = FormConfig.titanheart
roster.titanheart.forms = {
	{
		name = "Human",
		stats = {
			AD = { percent = titan.humanAttackDamagePercent },
			Armor = { flat = titan.humanArmorFlat },
			MR = { flat = titan.humanMagicResistFlat },
		},
		trigger = { type = "HEALTH_BELOW", belowPercent = titan.titanBelowPercent, maxUses = 1 },
	},
	{
		name = "Titan",
		health = titan.titanHealth,
		stats = { AD = { percent = titan.titanAttackDamagePercent }, Armor = { flat = titan.titanArmorFlat } },
		splash = { percent = titan.titanSplashPercent },
		trigger = { type = "FORM_HEALTH_DEPLETED", to = "Human" },
	},
}
-- A blast around his current target that burns; enemies already burning take more.
add("snapfire", unit(3, "Corps", { "Caster" }, 740, 57, 24, 32, 0.70, 4, 1.0, 20, 90), {
	with(
		area("CURRENT_TARGET", 1, "MAGIC", { 270, 430, 690 }),
		{ bonus = { type = "TARGET_STATUS", status = "BURN", percent = 30 } }
	),
	with(dot("CURRENT_TARGET", 1, "MAGIC", { 20, 32, 52 }, 3), { status = "BURN" }),
})
-- Copies the enemy that cast most recently; if none has, a magic hit on his current target.
add("mirror_script", unit(3, "Shinobi", { "Assassin", "Caster" }, 780, 72, 30, 34, 0.82, 2, 1.1, 30, 100), {
	{ type = "COPY", target = "LAST_CASTER_ENEMY", condition = { type = "ENEMY_HAS_CAST" } },
	with(
		damage("CURRENT_TARGET", "MAGIC", { 250, 400, 640 }),
		{ condition = { type = "ENEMY_HAS_CAST", negate = true } }
	),
})
-- Four quick hits over about a second, then a heavy hit that stuns his target.
add("clockbreaker", unit(3, "Spirit", { "Brawler" }, 930, 79, 40, 36, 0.72, 1, 1.0, 30, 100), {
	damage("CURRENT_TARGET", "PHYSICAL", { 85, 130, 215 }),
	with(damage("CURRENT_TARGET", "PHYSICAL", { 85, 130, 215 }), { delay = 0.25 }),
	with(damage("CURRENT_TARGET", "PHYSICAL", { 85, 130, 215 }), { delay = 0.5 }),
	with(damage("CURRENT_TARGET", "PHYSICAL", { 85, 130, 215 }), { delay = 0.75 }),
	with(damage("CURRENT_TARGET", "PHYSICAL", { 375, 600, 960 }), { delay = 1 }),
	with(stun("CURRENT_TARGET", { 1, 1.5, 2 }), { delay = 1 }),
}, { castTime = 1 })
-- A cone toward his current target, strongest next to him, then armor.
add("skyboulder", unit(3, "Titans", { "Guardian" }, 1050, 64, 50, 35, 0.72, 2, 0.9, 30, 100), {
	cone("CURRENT_TARGET", 2, "PHYSICAL", { 145, 235, 375 }, 40),
	buffFlat("SELF", "Armor", { 30, 45, 70 }, 5),
})
add("horizon_cut", unit(3, "Hunters", { "Blade", "Marksman" }, 820, 80, 32, 30, 0.84, 3, 1.0, 20, 90), {
	damage("FARTHEST_ENEMY", "MAGIC", { 330, 525, 840 }),
})
-- Holds the enemies around her current target and hurts them when the hold ends; allies attack
-- faster.
add("zero_field", unit(3, "Heroes", { "Support" }, 760, 52, 27, 35, 0.68, 3, 1.0, 40, 110), {
	with(
		areaStun("CURRENT_TARGET", 1, { 0.75, 1, 1.25 }),
		{ damageOnEnd = { damageType = "MAGIC", amount = { 150, 240, 385 } } }
	),
	buffPercent("ALL_ALLIES", "AttackSpeed", { 12, 20, 32 }, 5),
})

-- 4-cost --------------------------------------------------------------------------------------

add("reelbreaker", unit(4, "Hunters", { "Brawler" }, 1050, 88, 45, 40, 0.72, 2, 1.0, 40, 130), {
	{ type = "PULL", target = "FARTHEST_ENEMY" },
	damage("FARTHEST_ENEMY", "PHYSICAL", { 830, 1330, 2130 }),
})
-- Each cast moves him up a gear for the rest of the fight: gear 2 attacks faster, gear 3 also
-- splashes, and from the third cast on each cast shields him and slams around him.
add(
	"elastic_wardrum",
	unit(4, "Crew", { "Brawler", "Guardian" }, 1200, 84, 55, 50, 0.80, 1, 1.0, 40, 110),
	{},
	{ formOnly = true }
)
local gears = FormConfig.elasticWardrum
roster.elastic_wardrum.forms = {
	{ name = "Gear 1", trigger = { type = "ON_CAST" } },
	{
		name = "Gear 2",
		stats = { AttackSpeed = { percent = gears.attackSpeedPercent } },
		ability = transformOnly("elastic_wardrum", "gear2"),
		trigger = { type = "ON_CAST" },
	},
	{
		name = "Gear 3",
		stats = { AttackSpeed = { percent = gears.attackSpeedPercent } },
		splash = { percent = gears.splashPercent },
		ability = formAbility("elastic_wardrum", "gear3", {
			shield("SELF", { 400, 640, 1025 }, 4),
			area("SELF", 1, "PHYSICAL", { 200, 320, 510 }),
		}),
	},
}
-- A much longer mana bar: one huge blast on the largest enemy cluster, then she cannot act.
add(
	"starless_burst",
	unit(4, "Arcane", { "Caster", "Marksman" }, 830, 67, 28, 48, 0.80, 4, 1.0, 20, 160),
	{ area("LARGEST_CLUSTER", 2, "MAGIC", { 370, 595, 955 }) },
	{ selfStun = 2, clusterRadius = AbilityConfig.starlessBurstClusterRadius }
)
-- A projectile at his current target that becomes a radius-2 area hitting four times over about a
-- second (clones are drawn around him while he casts; RenderConfig.castClones).
local echoHit = function(delay)
	return with(area("CURRENT_TARGET", 2, "MAGIC", { 74, 117, 188 }), { delay = delay, fixedCenter = true })
end
add("echo_legion", unit(4, "Shinobi", { "Caster" }, 1050, 82, 42, 42, 0.82, 2, 1.1, 30, 110), {
	echoHit(0.25),
	echoHit(0.5),
	echoHit(0.75),
	echoHit(1),
})
add("night_command", unit(4, "Arcane", { "Assassin" }, 900, 89, 32, 34, 0.94, 1, 1.1, 30, 100), {
	summon({ 2, 3, 3 }, { 15, 17, 20 }, { 50, 55, 65 }, { 75, 85, 100 }, 55, 95, 1, 1.1),
})
-- A radius-2 stun around himself; each stunned enemy takes a knife when its stun ends, and he heals
-- for part of that damage.
add("frozen_moment", unit(4, "Spirit", { "Assassin", "Marksman" }, 950, 88, 38, 38, 0.86, 1, 1.0, 40, 110), {
	with(areaStun("SELF", 2, { 1, 1.5, 2 }), {
		damageOnEnd = { damageType = "PHYSICAL", amount = { 180, 290, 460 }, healPercentOfDamage = 40 },
	}),
})
-- As before; when his target dies while the attack speed buff lasts, he dashes to the nearest enemy
-- and repeats the area hit (AbilityConfig.cycloneEdgeRepeats per cast).
add("cyclone_edge", unit(4, "Corps", { "Blade", "Assassin" }, 860, 90, 30, 30, 0.95, 1, 1.2, 20, 90), {
	dash("HIGHEST_AD_ENEMY", 4, true),
	area("HIGHEST_AD_ENEMY", 1, "PHYSICAL", { 330, 525, 840 }),
	buffPercent("SELF", "AttackSpeed", { 35, 55, 80 }, 4),
}, {
	onTargetKilled = {
		window = 4,
		maxRepeats = AbilityConfig.cycloneEdgeRepeats,
		effects = {
			dash("NEAREST_ENEMY", 4, true),
			area("NEAREST_ENEMY", 1, "PHYSICAL", { 330, 525, 840 }),
		},
	},
})
-- A cast counter (AbilityConfig.nightParadeCycle = 2): cast 1 summons two curses that stay until
-- killed; cast 2 recalls every living curse (even none) and fires a line through his current target
-- with its base damage plus a bonus per curse recalled; then the count starts over. A short mana bar
-- (40) makes him cast about every 5 seconds.
local function paradeCast(fires: boolean)
	return {
		type = "CAST_CYCLE",
		every = AbilityConfig.nightParadeCycle,
		at = AbilityConfig.nightParadeCycle,
		negate = not fires,
	}
end
add("night_parade", unit(4, "Cursed", { "Caster" }, 900, 68, 32, 42, 0.75, 3, 1.0, 30, 40), {
	with(lastingSummon(2, { 60, 70, 80 }, { 80, 100, 120 }, 45, 100, 1, 1.0), { condition = paradeCast(false) }),
	{ type = "RECALL", condition = paradeCast(true) },
	with(line("CURRENT_TARGET", "MAGIC", { 70, 110, 180 }), {
		condition = paradeCast(true),
		bonus = { type = "RECALLED", percent = 100 },
	}),
})
-- Shields himself, heals his two lowest-health other allies (never himself), then hits.
add("restoration_strike", unit(4, "Spirit", { "Support", "Guardian" }, 1200, 78, 58, 45, 0.72, 1, 1.0, 40, 120), {
	shield("SELF", { 250, 400, 640 }, 4),
	{ type = "HEAL", target = "LOWEST_HP_OTHER_ALLIES", count = 2, amount = { 300, 480, 770 } },
	damage("CURRENT_TARGET", "PHYSICAL", { 200, 320, 510 }),
})

-- 5-cost --------------------------------------------------------------------------------------

add("severing_temple", unit(5, "Cursed", { "Caster", "Blade" }, 1100, 74, 45, 48, 0.88, 2, 1.1, 30, 110), {
	area("CURRENT_TARGET", 2, "PHYSICAL", { 340, 545, 875 }),
	-- "Enemies initially hit": the same center and radius, applied right after the hit.
	dot("CURRENT_TARGET", 2, "MAGIC", { 27, 42, 68 }, 4),
})
-- Stacks that never expire, and three forms: each cast moves him up one (with a bigger look); in
-- the third his ability is a beam from him through his current target to the board's edge.
local function coreStacks()
	local function stack(stat, kind, values)
		return {
			type = "BUFF",
			target = "SELF",
			stat = stat,
			[kind] = values,
			permanent = true,
			stackPerCast = true,
			maxStacks = 3,
		}
	end
	return {
		stack("AD", "percent", { 10, 15, 22 }),
		stack("AP", "flat", { 12, 18, 27 }),
		stack("AttackSpeed", "percent", { 10, 15, 22 }),
	}
end
local function coreAbility(finisher)
	local effects = coreStacks()
	table.insert(effects, finisher)
	return effects
end
add(
	"ascending_core",
	unit(5, "Heroes", { "Brawler", "Caster" }, 1250, 94, 55, 50, 0.88, 2, 1.1, 30, 100),
	coreAbility(area("CURRENT_TARGET", 1, "MAGIC", { 400, 640, 1025 }))
)
roster.ascending_core.forms = {
	{ name = "Core I", trigger = { type = "ON_CAST" } },
	{
		name = "Core II",
		ability = formAbility(
			"ascending_core",
			"core2",
			coreAbility(area("CURRENT_TARGET", 1, "MAGIC", { 400, 640, 1025 }))
		),
		trigger = { type = "ON_CAST" },
	},
	{
		name = "Core III",
		ability = formAbility(
			"ascending_core",
			"beam",
			coreAbility(line("CURRENT_TARGET", "MAGIC", { 450, 720, 1150 }))
		),
	},
}
add("final_argument", unit(5, "Heroes", { "Brawler" }, 1350, 100, 65, 60, 0.75, 1, 1.0, 0, 150), {
	damage("CURRENT_TARGET", "TRUE", { 1465, 2445, 4890 }),
})
add("infinite_collapse", unit(5, "Cursed", { "Caster" }, 1050, 78, 42, 65, 0.82, 4, 1.0, 40, 120), {
	areaStun("HIGHEST_AD_ENEMY", 2, { 1.5, 2, 2 }),
	shield("SELF", { 350, 560, 895 }, 5),
	-- "Same center": Block 2 gives no radius for the damage, so it uses the stun's radius 2.
	area("HIGHEST_AD_ENEMY", 2, "MAGIC", { 350, 560, 895 }),
})
-- A passive aura: enemies next to him take magic damage every second all fight, and he gains armor
-- and magic resist per enemy inside. His ability is a radius-2 blast around himself.
add("boiling_crown", unit(5, "Titans", { "Guardian", "Caster" }, 1400, 72, 70, 65, 0.65, 1, 0.8, 50, 130), {
	area("SELF", 2, "MAGIC", { 120, 190, 300 }),
})
roster.boiling_crown.aura = {
	radius = 1,
	interval = 1,
	damageType = "MAGIC",
	amount = { 7, 11, 18 },
	buffs = {
		{ stat = "Armor", flatPerEnemy = { 8, 12, 18 } },
		{ stat = "MR", flatPerEnemy = { 8, 12, 18 } },
	},
}

return freezeAll(roster)
