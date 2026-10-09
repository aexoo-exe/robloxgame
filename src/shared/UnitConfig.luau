-- Roster v1.1: 42 characters (9/9/10/9/5 by cost) with stats and abilities exactly as in
-- docs/design/revamp-roster.md (Block 2). Each character's key is a neutral internal id taken from
-- its ability; ability names are the same ids. Everything players see (names, ability names,
-- colors) lives in SkinConfig, never here.
--
-- Fields:
--   cost              gold price and shop tier (1-5)
--   origin, classes   trait membership (docs/design/revamp-structure.md); data only
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
--
-- Abilities resolve every selector once, before any effect. Where Block 2 says a dash gives a
-- "new CURRENT_TARGET", the dash sets the retarget flag and the cast's later effects name the
-- dash's own selector, so they hit the same enemy.

local FormConfig = if script then require(script.Parent.FormConfig) else require("./FormConfig")

local function freezeAll(value)
	if type(value) == "table" then
		for _, child in value do
			freezeAll(child)
		end
		table.freeze(value)
	end
	return value
end

-- A character: cost, origin, classes, health, AD, armor, MR, attack speed, range, move speed,
-- starting mana, max mana, and the ability's effects (its name is the character's id).
local function unit(cost, origin, classes, health, ad, armor, mr, as, range, move, startMana, maxMana)
	return function(id, effects)
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
			ability = { name = id, effects = effects },
		}
	end
end

local roster = {}

local function add(id, make, effects)
	roster[id] = make(id, effects)
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

-- Damage over time centered on `center` within `radius`, ticking every second.
local function dot(center, radius, damageType, amount, duration)
	return {
		type = "DAMAGE_OVER_TIME",
		center = center,
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

-- Rider mounts: the rider starts each fight Mounted, on a horse with its own health pool that takes
-- every hit, and drops to Dismounted when the horse's pool runs out. The mounted speed bonus is the
-- riders' former extra move speed (Block 2 lists them at 1.2; their base is now 1.0). With
-- FormConfig.mount.remountEnabled, Dismounted gets a takedown trigger back to Mounted.
local function mountedForms(id: string)
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
			trigger = if mount.remountEnabled
				then {
					type = "TAKEDOWN",
					to = "Mounted",
					healthPercent = mount.remountHorseHealthPercent,
					maxUses = mount.remountsPerFight,
				}
				else nil,
		},
	}
end

-- 1-cost --------------------------------------------------------------------------------------

add("flashline", unit(1, "Hunters", { "Blade", "Assassin" }, 560, 63, 20, 20, 0.78, 1, 1.1, 20, 90), {
	dash("FARTHEST_ENEMY", 4, true),
	damage("FARTHEST_ENEMY", "PHYSICAL", { 140, 225, 360 }),
})
add("cinder_arc", unit(1, "Hunters", { "Blade" }, 650, 57, 28, 25, 0.70, 1, 1.0, 30, 90), {
	damage("CURRENT_TARGET", "PHYSICAL", { 105, 170, 270 }),
	area("CURRENT_TARGET", 1, "MAGIC", { 65, 105, 170 }),
	buffPercent("SELF", "AttackSpeed", { 18, 28, 42 }, 5),
})
add("wolfstep", unit(1, "Corps", { "Blade" }, 590, 62, 22, 20, 0.77, 1, 1.1, 20, 80), {
	dash("HIGHEST_AD_ENEMY", 3, true),
	damage("HIGHEST_AD_ENEMY", "PHYSICAL", { 135, 215, 345 }),
})
add("spurshot", unit(1, "Spirit", { "Marksman", "Brawler" }, 650, 56, 18, 18, 0.76, 2, 1.0, 20, 80), {
	damage("FARTHEST_ENEMY", "PHYSICAL", { 140, 225, 360 }),
	buffPercent("SELF", "AttackSpeed", { 15, 25, 40 }, 4),
})
roster.spurshot.forms = mountedForms("spurshot")
add("ripcord_frenzy", unit(1, "Cursed", { "Brawler" }, 700, 58, 28, 24, 0.72, 1, 1.0, 30, 90), {
	buffPercent("SELF", "AttackSpeed", { 25, 40, 60 }, 5),
	heal("SELF", { 80, 130, 210 }),
})
add("null_edge", unit(1, "Arcane", { "Blade" }, 680, 61, 30, 35, 0.68, 1, 1.0, 30, 90), {
	damage("CURRENT_TARGET", "PHYSICAL", { 130, 210, 335 }),
	buffFlat("SELF", "MR", { 25, 40, 65 }, 5),
})
add("bitter_vapor", unit(1, "Arcane", { "Support" }, 580, 43, 20, 30, 0.62, 3, 1.0, 40, 100), {
	dot("CURRENT_TARGET", 1, "MAGIC", { 22, 35, 56 }, 4),
	heal("LOWEST_HP_ALLY", { 70, 110, 175 }),
})
add("iron_rush", unit(1, "Titans", { "Guardian" }, 750, 48, 40, 35, 0.56, 1, 0.9, 40, 100), {
	buffFlat("SELF", "Armor", { 30, 45, 70 }, 5),
	dash("HIGHEST_AD_ENEMY", 2, true),
	damage("HIGHEST_AD_ENEMY", "PHYSICAL", { 85, 135, 215 }),
	stun("HIGHEST_AD_ENEMY", { 0.75, 1, 1.5 }),
})
add("blooming_aid", unit(1, "Shinobi", { "Support" }, 600, 46, 22, 28, 0.65, 2, 1.0, 40, 100), {
	heal("LOWEST_HP_ALLY", { 120, 190, 305 }),
})

-- 2-cost --------------------------------------------------------------------------------------

add("redline_cut", unit(2, "Corps", { "Blade", "Guardian" }, 690, 68, 27, 25, 0.83, 1, 1.1, 20, 80), {
	dash("HIGHEST_AD_ENEMY", 3, true),
	damage("HIGHEST_AD_ENEMY", "PHYSICAL", { 215, 345, 550 }),
	buffPercent("SELF", "AttackSpeed", { 20, 32, 50 }, 4),
})
add("flare_kick", unit(2, "Crew", { "Brawler", "Assassin" }, 760, 69, 30, 27, 0.78, 1, 1.1, 30, 90), {
	damage("CURRENT_TARGET", "PHYSICAL", { 150, 240, 385 }),
	area("CURRENT_TARGET", 1, "MAGIC", { 75, 120, 190 }),
})
add("burst_vector", unit(2, "Heroes", { "Caster", "Marksman" }, 650, 67, 22, 24, 0.78, 4, 1.0, 20, 80), {
	area("CURRENT_TARGET", 1, "MAGIC", { 210, 335, 535 }),
	buffPercent("SELF", "AD", { 10, 15, 25 }, 4),
})
add("skybreaker", unit(2, "Heroes", { "Brawler" }, 820, 66, 35, 30, 0.70, 1, 1.0, 30, 90), {
	dash("HIGHEST_AD_ENEMY", 3, false),
	area("HIGHEST_AD_ENEMY", 1, "PHYSICAL", { 210, 335, 535 }),
})
add("crimson_hunger", unit(2, "Cursed", { "Assassin" }, 720, 70, 26, 27, 0.82, 1, 1.1, 20, 80), {
	damage("CURRENT_TARGET", "PHYSICAL", { 220, 350, 560 }),
	heal("SELF", { 90, 145, 230 }),
})
add("orbit_breaker", unit(2, "Spirit", { "Marksman" }, 660, 68, 23, 25, 0.82, 3, 1.0, 20, 90), {
	damage("CURRENT_TARGET", "PHYSICAL", { 220, 350, 560 }),
	stun("CURRENT_TARGET", { 1, 1.5, 2 }),
})
roster.orbit_breaker.forms = mountedForms("orbit_breaker")
add("marsh_fortress", unit(2, "Shinobi", { "Guardian" }, 900, 52, 45, 42, 0.58, 1, 0.9, 40, 110), {
	shield("SELF", { 280, 450, 720 }, 6),
	area("SELF", 1, "PHYSICAL", { 85, 135, 215 }),
})
add("shade_pack", unit(2, "Cursed", { "Caster" }, 650, 50, 23, 30, 0.67, 3, 1.0, 30, 100), {
	summon({ 2, 2, 3 }, { 8, 9, 10 }, { 30, 35, 40 }, { 45, 50, 55 }, 50, 90, 1, 1.1),
})
add("field_medic", unit(2, "Crew", { "Support", "Brawler" }, 640, 46, 24, 32, 0.68, 3, 1.0, 40, 110), {
	heal("ALL_ALLIES", { 45, 70, 110 }),
	shield("LOWEST_HP_ALLY", { 150, 240, 385 }, 5),
})

-- 3-cost --------------------------------------------------------------------------------------

add("volt_spear", unit(3, "Shinobi", { "Blade", "Assassin" }, 790, 79, 28, 30, 0.88, 1, 1.1, 20, 90), {
	dash("FARTHEST_ENEMY", 4, true),
	damage("FARTHEST_ENEMY", "MAGIC", { 300, 480, 770 }),
	stun("FARTHEST_ENEMY", { 0.75, 1.25, 1.75 }),
})
add("thunder_nest", unit(3, "Hunters", { "Assassin" }, 770, 78, 26, 27, 0.90, 1, 1.2, 20, 90), {
	dash("HIGHEST_AD_ENEMY", 3, false),
	area("SELF", 1, "MAGIC", { 250, 400, 640 }),
	areaStun("SELF", 1, { 1, 1.5, 2 }),
})
add("threefold_crash", unit(3, "Crew", { "Blade" }, 900, 80, 38, 32, 0.78, 1, 1.0, 30, 100), {
	dash("HIGHEST_AD_ENEMY", 3, false),
	area("HIGHEST_AD_ENEMY", 1, "PHYSICAL", { 280, 450, 720 }),
	stun("HIGHEST_AD_ENEMY", { 0.75, 1.25, 1.75 }),
})
add("titanheart", unit(3, "Titans", { "Guardian", "Brawler" }, 1050, 65, 50, 45, 0.62, 1, 0.9, 40, 110), {
	shield("SELF", { 360, 575, 920 }, 6),
	buffFlat("SELF", "Armor", { 30, 45, 70 }, 6),
	buffPercent("SELF", "AD", { 15, 25, 40 }, 6),
})
add("snapfire", unit(3, "Corps", { "Caster" }, 740, 57, 24, 32, 0.70, 4, 1.0, 20, 90), {
	area("HIGHEST_AD_ENEMY", 1, "MAGIC", { 300, 480, 770 }),
})
add("mirror_script", unit(3, "Shinobi", { "Assassin", "Caster" }, 780, 72, 30, 34, 0.82, 2, 1.1, 30, 100), {
	{ type = "COPY", target = "HIGHEST_AD_ENEMY" },
})
add("clockbreaker", unit(3, "Spirit", { "Brawler" }, 930, 79, 40, 36, 0.72, 1, 1.0, 30, 100), {
	areaStun("SELF", 1, { 1, 1.5, 2 }),
	damage("CURRENT_TARGET", "PHYSICAL", { 300, 480, 770 }),
})
add("skyboulder", unit(3, "Titans", { "Guardian" }, 1050, 64, 50, 35, 0.72, 2, 0.9, 30, 100), {
	area("FARTHEST_ENEMY", 1, "PHYSICAL", { 300, 480, 770 }),
})
add("horizon_cut", unit(3, "Hunters", { "Blade", "Marksman" }, 820, 80, 32, 30, 0.84, 3, 1.0, 20, 90), {
	damage("FARTHEST_ENEMY", "MAGIC", { 330, 525, 840 }),
})
add("zero_field", unit(3, "Heroes", { "Support" }, 760, 52, 27, 35, 0.68, 3, 1.0, 40, 110), {
	areaStun("SELF", 2, { 0.75, 1.25, 1.75 }),
	buffPercent("ALL_ALLIES", "AttackSpeed", { 12, 20, 32 }, 5),
})

-- 4-cost --------------------------------------------------------------------------------------

add("reelbreaker", unit(4, "Hunters", { "Brawler" }, 1050, 88, 45, 40, 0.72, 2, 1.0, 40, 130), {
	{ type = "PULL", target = "FARTHEST_ENEMY" },
	damage("FARTHEST_ENEMY", "PHYSICAL", { 390, 625, 1000 }),
})
add("elastic_wardrum", unit(4, "Crew", { "Brawler", "Guardian" }, 1200, 84, 55, 50, 0.80, 1, 1.0, 40, 110), {
	shield("SELF", { 400, 640, 1025 }, 6),
	buffPercent("SELF", "AD", { 20, 32, 50 }, 6),
	buffPercent("SELF", "AttackSpeed", { 20, 32, 50 }, 6),
})
add("starless_burst", unit(4, "Arcane", { "Caster", "Marksman" }, 830, 67, 28, 48, 0.80, 4, 1.0, 20, 100), {
	area("HIGHEST_AD_ENEMY", 1, "MAGIC", { 350, 560, 895 }),
	shield("SELF", { 250, 400, 640 }, 5),
})
add("echo_legion", unit(4, "Shinobi", { "Caster" }, 1050, 82, 42, 42, 0.82, 2, 1.1, 30, 110), {
	summon({ 2, 2, 3 }, { 8, 9, 10 }, { 25, 30, 35 }, { 35, 40, 45 }, 40, 100, 1, 1.1),
	area("CURRENT_TARGET", 1, "MAGIC", { 270, 430, 690 }),
})
add("night_command", unit(4, "Arcane", { "Assassin" }, 900, 89, 32, 34, 0.94, 1, 1.1, 30, 100), {
	summon({ 2, 3, 3 }, { 9, 10, 12 }, { 30, 35, 40 }, { 50, 55, 65 }, 55, 95, 1, 1.1),
})
add("frozen_moment", unit(4, "Spirit", { "Assassin", "Marksman" }, 950, 88, 38, 38, 0.86, 1, 1.0, 40, 110), {
	areaStun("SELF", 1, { 1, 1.5, 2 }),
	damage("CURRENT_TARGET", "PHYSICAL", { 320, 510, 815 }),
	heal("SELF", { 180, 290, 465 }),
})
add("cyclone_edge", unit(4, "Corps", { "Blade", "Assassin" }, 860, 90, 30, 30, 0.95, 1, 1.2, 20, 90), {
	dash("HIGHEST_AD_ENEMY", 4, true),
	area("HIGHEST_AD_ENEMY", 1, "PHYSICAL", { 330, 525, 840 }),
	buffPercent("SELF", "AttackSpeed", { 35, 55, 80 }, 4),
})
add("night_parade", unit(4, "Cursed", { "Caster" }, 900, 68, 32, 42, 0.75, 3, 1.0, 30, 110), {
	area("CURRENT_TARGET", 1, "MAGIC", { 220, 350, 560 }),
	summon({ 2, 2, 3 }, { 9, 10, 12 }, { 35, 40, 45 }, { 40, 50, 60 }, 45, 85, 1, 1.0),
})
add("restoration_strike", unit(4, "Spirit", { "Support", "Guardian" }, 1200, 78, 58, 45, 0.72, 1, 1.0, 40, 120), {
	heal("LOWEST_HP_OTHER_ALLY", { 450, 720, 1150 }),
	damage("CURRENT_TARGET", "PHYSICAL", { 200, 320, 510 }),
})

-- 5-cost --------------------------------------------------------------------------------------

add("severing_temple", unit(5, "Cursed", { "Caster", "Blade" }, 1100, 98, 45, 48, 0.88, 2, 1.1, 30, 110), {
	area("CURRENT_TARGET", 2, "PHYSICAL", { 450, 720, 1150 }),
	-- "Enemies initially hit": the same center and radius, applied right after the hit.
	dot("CURRENT_TARGET", 2, "MAGIC", { 35, 55, 90 }, 4),
})
add("ascending_core", unit(5, "Heroes", { "Brawler", "Caster" }, 1250, 94, 55, 50, 0.88, 2, 1.1, 30, 100), {
	{
		type = "BUFF",
		target = "SELF",
		stat = "AD",
		percent = { 10, 15, 22 },
		duration = 8,
		stackPerCast = true,
		maxStacks = 3,
	},
	{
		type = "BUFF",
		target = "SELF",
		stat = "AP",
		flat = { 12, 18, 27 },
		duration = 8,
		stackPerCast = true,
		maxStacks = 3,
	},
	{
		type = "BUFF",
		target = "SELF",
		stat = "AttackSpeed",
		percent = { 10, 15, 22 },
		duration = 8,
		stackPerCast = true,
		maxStacks = 3,
	},
	area("CURRENT_TARGET", 1, "MAGIC", { 400, 640, 1025 }),
})
add("final_argument", unit(5, "Heroes", { "Brawler" }, 1350, 100, 65, 60, 0.75, 1, 1.0, 0, 150), {
	damage("CURRENT_TARGET", "TRUE", { 900, 1500, 3000 }),
})
add("infinite_collapse", unit(5, "Cursed", { "Caster" }, 1050, 78, 42, 65, 0.82, 4, 1.0, 40, 120), {
	areaStun("HIGHEST_AD_ENEMY", 2, { 1.5, 2, 2 }),
	shield("SELF", { 350, 560, 895 }, 5),
	-- "Same center": Block 2 gives no radius for the damage, so it uses the stun's radius 2.
	area("HIGHEST_AD_ENEMY", 2, "MAGIC", { 450, 720, 1150 }),
})
add("boiling_crown", unit(5, "Titans", { "Guardian", "Caster" }, 1400, 72, 70, 65, 0.65, 1, 0.8, 50, 130), {
	area("SELF", 1, "MAGIC", { 170, 270, 430 }),
	dot("SELF", 1, "MAGIC", { 30, 48, 76 }, 4),
	buffFlat("SELF", "Armor", { 30, 45, 70 }, 6),
	buffFlat("SELF", "MR", { 30, 45, 70 }, 6),
})

return freezeAll(roster)
