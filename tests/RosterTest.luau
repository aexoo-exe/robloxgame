-- Roster v1.1 against docs/design/revamp-roster.md (Block 2) and the structural rules of
-- docs/design/revamp-structure.md (Block 1). Characters are named by internal id only.

local Abilities = require("../src/shared/Abilities")
local Battle = require("../src/shared/Battle")
local CombatConfig = require("../src/shared/CombatConfig")
local CombatSim = require("../src/shared/CombatSim")
local Forms = require("../src/shared/Forms")
local HexGrid = require("../src/shared/HexGrid")
local UnitConfig = require("../src/shared/UnitConfig")

local function expectEqual(actual, expected, label)
	assert(actual == expected, string.format("%s: expected %s, got %s", label, tostring(expected), tostring(actual)))
end

-- Block 2: cost, HP (before the global multiplier), AD, armor, MR, attack speed, range, move,
-- starting mana, max mana. AP is 100 for everyone. Move is the speed a character starts the fight
-- with: for the riders (spurshot, orbit_breaker) that is their base 1.0 plus the Mounted form's
-- bonus (FormConfig.mount.mountedMoveSpeedBonus).
local SPEC = {
	flashline = { 1, 560, 63, 20, 20, 0.78, 1, 1.1, 20, 90 },
	cinder_arc = { 1, 650, 57, 28, 25, 0.70, 1, 1.0, 30, 90 },
	wolfstep = { 1, 590, 62, 22, 20, 0.77, 1, 1.1, 20, 80 },
	spurshot = { 1, 650, 56, 18, 18, 0.76, 2, 1.2, 0, 80 },
	ripcord_frenzy = { 1, 700, 58, 28, 24, 0.72, 1, 1.0, 30, 90 },
	null_edge = { 1, 680, 61, 30, 35, 0.68, 1, 1.0, 30, 90 },
	bitter_vapor = { 1, 580, 43, 20, 30, 0.62, 3, 1.0, 40, 100 },
	iron_rush = { 1, 750, 48, 40, 35, 0.56, 1, 0.9, 40, 100 },
	blooming_aid = { 1, 600, 46, 22, 28, 0.65, 2, 1.0, 40, 100 },

	redline_cut = { 2, 690, 68, 27, 25, 0.83, 1, 1.1, 20, 80 },
	flare_kick = { 2, 760, 69, 30, 27, 0.78, 1, 1.1, 15, 50 },
	burst_vector = { 2, 650, 67, 22, 24, 0.78, 4, 1.0, 20, 80 },
	skybreaker = { 2, 820, 66, 35, 30, 0.70, 1, 1.0, 30, 90 },
	crimson_hunger = { 2, 720, 70, 26, 27, 0.82, 1, 1.1, 20, 80 },
	orbit_breaker = { 2, 660, 68, 23, 25, 0.82, 3, 1.2, 20, 90 },
	marsh_fortress = { 2, 900, 52, 45, 42, 0.58, 1, 0.9, 40, 110 },
	shade_pack = { 2, 650, 50, 23, 30, 0.67, 3, 1.0, 30, 100 },
	field_medic = { 2, 640, 46, 24, 32, 0.68, 3, 1.0, 40, 110 },

	volt_spear = { 3, 790, 79, 28, 30, 0.88, 1, 1.1, 20, 90 },
	thunder_nest = { 3, 770, 78, 26, 27, 0.90, 1, 1.2, 20, 90 },
	threefold_crash = { 3, 900, 80, 38, 32, 0.78, 1, 1.0, 30, 100 },
	titanheart = { 3, 1050, 65, 50, 45, 0.62, 1, 0.9, 40, 110 },
	snapfire = { 3, 740, 57, 24, 32, 0.70, 4, 1.0, 20, 90 },
	mirror_script = { 3, 780, 72, 30, 34, 0.82, 2, 1.1, 30, 100 },
	clockbreaker = { 3, 930, 79, 40, 36, 0.72, 1, 1.0, 30, 100 },
	skyboulder = { 3, 1050, 64, 50, 35, 0.72, 2, 0.9, 30, 100 },
	horizon_cut = { 3, 820, 80, 32, 30, 0.84, 3, 1.0, 20, 90 },
	zero_field = { 3, 760, 52, 27, 35, 0.68, 3, 1.0, 40, 110 },

	reelbreaker = { 4, 1050, 88, 45, 40, 0.72, 2, 1.0, 40, 130 },
	elastic_wardrum = { 4, 1200, 84, 55, 50, 0.80, 1, 1.0, 40, 110 },
	starless_burst = { 4, 830, 67, 28, 48, 0.80, 4, 1.0, 20, 160 },
	echo_legion = { 4, 1050, 82, 42, 42, 0.82, 2, 1.1, 30, 110 },
	night_command = { 4, 900, 89, 32, 34, 0.94, 1, 1.1, 30, 100 },
	frozen_moment = { 4, 950, 88, 38, 38, 0.86, 1, 1.0, 40, 110 },
	cyclone_edge = { 4, 860, 90, 30, 30, 0.95, 1, 1.2, 20, 90 },
	night_parade = { 4, 900, 68, 32, 42, 0.75, 3, 1.0, 30, 110 },
	restoration_strike = { 4, 1200, 78, 58, 45, 0.72, 1, 1.0, 40, 120 },

	severing_temple = { 5, 1100, 98, 45, 48, 0.88, 2, 1.1, 30, 110 },
	ascending_core = { 5, 1250, 94, 55, 50, 0.88, 2, 1.1, 30, 100 },
	final_argument = { 5, 1350, 100, 65, 60, 0.75, 1, 1.0, 0, 150 },
	infinite_collapse = { 5, 1050, 78, 42, 65, 0.82, 4, 1.0, 40, 120 },
	boiling_crown = { 5, 1400, 72, 70, 65, 0.65, 1, 0.8, 50, 130 },
}
local FIELDS = {
	"cost",
	"health",
	"attackDamage",
	"armor",
	"magicResist",
	"attacksPerSecond",
	"range",
	"moveSpeed",
	"startingMana",
	"maxMana",
}

-- Block 2 origin (faction) and classes, with the Overhaul 1 changes.
local TRAITS = {
	flashline = { "Hunters", "Blade", "Assassin" },
	cinder_arc = { "Hunters", "Blade" },
	wolfstep = { "Corps", "Blade" },
	spurshot = { "Spirit", "Marksman", "Brawler" },
	ripcord_frenzy = { "Cursed", "Brawler" },
	null_edge = { "Arcane", "Blade" },
	bitter_vapor = { "Arcane", "Support" },
	iron_rush = { "Titans", "Guardian" },
	blooming_aid = { "Shinobi", "Support" },
	redline_cut = { "Corps", "Blade", "Guardian" },
	flare_kick = { "Crew", "Brawler", "Assassin" },
	burst_vector = { "Heroes", "Caster", "Marksman" },
	skybreaker = { "Heroes", "Brawler" },
	crimson_hunger = { "Cursed", "Assassin" },
	orbit_breaker = { "Spirit", "Marksman" },
	marsh_fortress = { "Shinobi", "Guardian" },
	shade_pack = { "Cursed", "Caster" },
	field_medic = { "Crew", "Support", "Brawler" },
	volt_spear = { "Shinobi", "Blade", "Assassin" },
	thunder_nest = { "Hunters", "Assassin" },
	threefold_crash = { "Crew", "Blade" },
	titanheart = { "Titans", "Guardian", "Brawler" },
	snapfire = { "Corps", "Caster" },
	mirror_script = { "Shinobi", "Assassin", "Caster" },
	clockbreaker = { "Spirit", "Brawler" },
	skyboulder = { "Titans", "Guardian" },
	horizon_cut = { "Hunters", "Blade", "Marksman" },
	zero_field = { "Heroes", "Support" },
	reelbreaker = { "Hunters", "Brawler" },
	elastic_wardrum = { "Crew", "Brawler", "Guardian" },
	starless_burst = { "Arcane", "Caster", "Marksman" },
	echo_legion = { "Shinobi", "Caster" },
	night_command = { "Arcane", "Assassin" },
	frozen_moment = { "Spirit", "Assassin", "Marksman" },
	cyclone_edge = { "Corps", "Blade", "Assassin" },
	night_parade = { "Cursed", "Caster" },
	restoration_strike = { "Spirit", "Support", "Guardian" },
	severing_temple = { "Cursed", "Caster", "Blade" },
	ascending_core = { "Heroes", "Brawler", "Caster" },
	final_argument = { "Heroes", "Brawler" },
	infinite_collapse = { "Cursed", "Caster" },
	boiling_crown = { "Titans", "Guardian", "Caster" },
}

-- Abilities, written the way abilityText (below) describes the data: Block 2 for the 12 unchanged
-- characters, docs/design/overhaul-1.md for the 30 reworked ones. Where a dash gives a "new
-- CURRENT_TARGET" ("retarget"), the cast's later effects name the dash's selector, because
-- selectors resolve once per cast.
local ABILITIES = {
	flashline = "DASH FARTHEST_ENEMY 4 retarget; DAMAGE FARTHEST_ENEMY PHYSICAL 140/225/360",
	cinder_arc = "DAMAGE CURRENT_TARGET PHYSICAL 105/170/270; AREA_DAMAGE CURRENT_TARGET r1 MAGIC 65/105/170; BUFF SELF AttackSpeed +18/28/42% 5s",
	wolfstep = "DASH HIGHEST_AD_ENEMY 3 retarget; DAMAGE HIGHEST_AD_ENEMY PHYSICAL 135/215/345",
	spurshot = "DAMAGE CURRENT_TARGET PHYSICAL 120/190/305 bonus STACKS 15%; DEBUFF CURRENT_TARGET SLOW -25/30/35% 2s; HEAL SELF 80/130/210 pool",
	ripcord_frenzy = "[formOnly]",
	null_edge = "DAMAGE CURRENT_TARGET PHYSICAL 130/210/335; BUFF SELF MR +25/40/65 5s",
	bitter_vapor = "DAMAGE_OVER_TIME CURRENT_TARGET r1 MAGIC POISON 22/35/56 every 1s 4s weaken 20/25/30%; HEAL LOWEST_HP_ALLY 70/110/175",
	iron_rush = "BUFF SELF Armor +30/45/70 5s; DASH CURRENT_TARGET 2; DAMAGE CURRENT_TARGET PHYSICAL 85/135/215; STUN CURRENT_TARGET 0.75/1/1.5s; KNOCKBACK CURRENT_TARGET",
	blooming_aid = "HEAL LOWEST_HP_ALLY 120/190/305 if ALLY_BELOW 70; DAMAGE CURRENT_TARGET PHYSICAL 150/240/385 unless ALLY_BELOW 70",

	redline_cut = "DASH ATTACKER_OF_LOWEST_ALLY 3 retarget; DAMAGE ATTACKER_OF_LOWEST_ALLY PHYSICAL 215/345/550; BUFF SELF AttackSpeed +20/32/50% 4s",
	flare_kick = "DASH LOWEST_HP_ENEMY_NEARBY 2 retarget; DAMAGE LOWEST_HP_ENEMY_NEARBY PHYSICAL 110/175/280 [cast 0s, reset, nearby 2]",
	burst_vector = "AREA_DAMAGE CURRENT_TARGET r1 MAGIC 210/335/535; BUFF SELF AD +10/15/25% 4s",
	skybreaker = "DAMAGE CURRENT_TARGET PHYSICAL 210/335/535; AREA_DAMAGE CURRENT_TARGET LINE len2 past PHYSICAL 105/170/270",
	crimson_hunger = "DAMAGE CURRENT_TARGET PHYSICAL 200/320/510 bonus MISSING_HEALTH 100%; HEAL SELF 250/400/640 if KILLED",
	orbit_breaker = "DAMAGE CURRENT_TARGET PHYSICAL 220/350/560; STUN CURRENT_TARGET 1/1.5/2s; BOUNCE CURRENT_TARGET PHYSICAL x2 100/160/250",
	marsh_fortress = "AREA_DAMAGE SELF r1 PHYSICAL 110/175/280 heal/hit 60/95/150",
	shade_pack = "SUMMON x2/2/3 lasting hp 30/35/40% ad 45/50/55% armor 50% mr 50% as 90% range 1 move 1.1 mana/hit 4",
	field_medic = "HEAL ALL_ALLIES 45/70/110",

	volt_spear = "DASH CURRENT_TARGET 2; DAMAGE CURRENT_TARGET MAGIC 300/480/770; STUN CURRENT_TARGET 0.75/1.25/1.75s; DAMAGE_OVER_TIME CURRENT_TARGET MAGIC BURN 30/48/76 every 1s 3s",
	thunder_nest = "DASH HIGHEST_AD_ENEMY 3; AREA_DAMAGE SELF r1 MAGIC 250/400/640; AREA_STUN SELF r1 1/1.5/2s",
	threefold_crash = "DAMAGE CURRENT_TARGET PHYSICAL 120/190/305; DAMAGE CURRENT_TARGET PHYSICAL 120/190/305 @0.25s; AREA_DAMAGE SELF r1 PHYSICAL 140/225/360 @0.5s; STUN CURRENT_TARGET 0.75/1.25/1.75s @0.5s",
	titanheart = "DAMAGE CURRENT_TARGET PHYSICAL 250/400/640",
	snapfire = "AREA_DAMAGE CURRENT_TARGET r1 MAGIC 270/430/690 bonus TARGET_STATUS:BURN 30%; DAMAGE_OVER_TIME CURRENT_TARGET r1 MAGIC BURN 20/32/52 every 1s 3s",
	mirror_script = "COPY LAST_CASTER_ENEMY if ENEMY_HAS_CAST; DAMAGE CURRENT_TARGET MAGIC 250/400/640 unless ENEMY_HAS_CAST",
	clockbreaker = "DAMAGE CURRENT_TARGET PHYSICAL 45/70/115; DAMAGE CURRENT_TARGET PHYSICAL 45/70/115 @0.25s; DAMAGE CURRENT_TARGET PHYSICAL 45/70/115 @0.5s; DAMAGE CURRENT_TARGET PHYSICAL 45/70/115 @0.75s; DAMAGE CURRENT_TARGET PHYSICAL 200/320/510 @1s; STUN CURRENT_TARGET 1/1.5/2s @1s [cast 1s]",
	skyboulder = "AREA_DAMAGE CURRENT_TARGET CONE r2 falloff 40% PHYSICAL 300/480/770; BUFF SELF Armor +30/45/70 5s",
	horizon_cut = "DAMAGE FARTHEST_ENEMY MAGIC 330/525/840",
	zero_field = "AREA_STUN CURRENT_TARGET r1 0.75/1/1.25s onEnd MAGIC 150/240/385; BUFF ALL_ALLIES AttackSpeed +12/20/32% 5s",

	reelbreaker = "PULL FARTHEST_ENEMY; DAMAGE FARTHEST_ENEMY PHYSICAL 390/625/1000",
	elastic_wardrum = "[formOnly]",
	starless_burst = "AREA_DAMAGE LARGEST_CLUSTER r2 MAGIC 600/960/1540 [selfstun 2s, cluster 2]",
	echo_legion = "AREA_DAMAGE CURRENT_TARGET r2 MAGIC 110/175/280 @0.25s fixed; AREA_DAMAGE CURRENT_TARGET r2 MAGIC 110/175/280 @0.5s fixed; AREA_DAMAGE CURRENT_TARGET r2 MAGIC 110/175/280 @0.75s fixed; AREA_DAMAGE CURRENT_TARGET r2 MAGIC 110/175/280 @1s fixed",
	night_command = "SUMMON x2/3/3 9/10/12s hp 30/35/40% ad 50/55/65% armor 55% mr 55% as 95% range 1 move 1.1",
	frozen_moment = "AREA_STUN SELF r2 1/1.5/2s onEnd PHYSICAL 180/290/460 lifesteal 40%",
	cyclone_edge = "DASH HIGHEST_AD_ENEMY 4 retarget; AREA_DAMAGE HIGHEST_AD_ENEMY r1 PHYSICAL 330/525/840; BUFF SELF AttackSpeed +35/55/80% 4s [onKill 4s x2: DASH NEAREST_ENEMY 4 retarget, AREA_DAMAGE NEAREST_ENEMY r1 PHYSICAL 330/525/840]",
	night_parade = "SUMMON x1 lasting hp 35/40/45% ad 40/50/60% armor 45% mr 45% as 85% range 1 move 1 unless CAST_CYCLE 3/3; RECALL if CAST_CYCLE 3/3; AREA_DAMAGE CURRENT_TARGET LINE MAGIC 120/190/305 bonus RECALLED 100% if CAST_CYCLE 3/3",
	restoration_strike = "SHIELD SELF 250/400/640 4s; HEAL LOWEST_HP_OTHER_ALLIES x2 300/480/770; DAMAGE CURRENT_TARGET PHYSICAL 200/320/510",

	severing_temple = "AREA_DAMAGE CURRENT_TARGET r2 PHYSICAL 450/720/1150; DAMAGE_OVER_TIME CURRENT_TARGET r2 MAGIC 35/55/90 every 1s 4s",
	ascending_core = "BUFF SELF AD +10/15/22% permanent stacks 3; BUFF SELF AP +12/18/27 permanent stacks 3; BUFF SELF AttackSpeed +10/15/22% permanent stacks 3; AREA_DAMAGE CURRENT_TARGET r1 MAGIC 400/640/1025",
	final_argument = "DAMAGE CURRENT_TARGET TRUE 900/1500/3000",
	infinite_collapse = "AREA_STUN HIGHEST_AD_ENEMY r2 1.5/2/2s; SHIELD SELF 350/560/895 5s; AREA_DAMAGE HIGHEST_AD_ENEMY r2 MAGIC 450/720/1150",
	boiling_crown = "AREA_DAMAGE SELF r2 MAGIC 220/350/560",
}

-- Abilities of forms that replace the character's own ("id/form name").
local FORM_ABILITIES = {
	["spurshot/Dismounted"] = "DAMAGE CURRENT_TARGET PHYSICAL 120/190/305 bonus STACKS 15%; DEBUFF CURRENT_TARGET SLOW -25/30/35% 2s; HEAL SELF 50/80/130",
	["ripcord_frenzy/Chainsaw"] = "HEAL SELF 100/160/255",
	["orbit_breaker/Dismounted"] = "DAMAGE CURRENT_TARGET PHYSICAL 220/350/560; STUN CURRENT_TARGET 1/1.5/2s; BOUNCE CURRENT_TARGET PHYSICAL x1 100/160/250",
	["shade_pack/Pack Out"] = "AREA_DAMAGE CURRENT_TARGET r1 MAGIC 180/290/460; AREA_STUN CURRENT_TARGET r1 0.75/1/1.25s; SUMMON x2/2/3 lasting hp 30/35/40% ad 45/50/55% armor 50% mr 50% as 90% range 1 move 1.1 mana/hit 4 refill",
	["field_medic/Bruiser"] = "DAMAGE CURRENT_TARGET PHYSICAL 200/320/510",
	["elastic_wardrum/Gear 2"] = "[formOnly]",
	["elastic_wardrum/Gear 3"] = "SHIELD SELF 400/640/1025 4s; AREA_DAMAGE SELF r1 PHYSICAL 200/320/510",
	["ascending_core/Core II"] = "BUFF SELF AD +10/15/22% permanent stacks 3; BUFF SELF AP +12/18/27 permanent stacks 3; BUFF SELF AttackSpeed +10/15/22% permanent stacks 3; AREA_DAMAGE CURRENT_TARGET r1 MAGIC 400/640/1025",
	["ascending_core/Core III"] = "BUFF SELF AD +10/15/22% permanent stacks 3; BUFF SELF AP +12/18/27 permanent stacks 3; BUFF SELF AttackSpeed +10/15/22% permanent stacks 3; AREA_DAMAGE CURRENT_TARGET LINE MAGIC 450/720/1150",
}

-- Formats a number the way the spec strings write it: 1, 0.75, 2.25.
local function number(value: number): string
	if value == math.floor(value) then
		return string.format("%d", value)
	end
	return string.format("%g", value)
end

-- A per-star value as "a/b/c", or a constant on its own.
local function perStar(value: any): string
	if type(value) ~= "table" then
		return number(value)
	end
	local parts = {}
	for _, each in value do
		table.insert(parts, number(each))
	end
	return table.concat(parts, "/")
end

-- Describes one effect in the spec strings' format.
local function effectText(effect): string
	local parts = { effect.type }
	if effect.target or effect.center then
		table.insert(parts, effect.target or effect.center)
	end
	if effect.type == "SUMMON" then
		table.insert(parts, "x" .. perStar(effect.count))
		table.insert(parts, if effect.permanent then "lasting" else perStar(effect.duration) .. "s")
		table.insert(parts, "hp " .. perStar(effect.healthPercent) .. "%")
		table.insert(parts, "ad " .. perStar(effect.attackDamagePercent) .. "%")
		table.insert(parts, "armor " .. perStar(effect.armorPercent) .. "%")
		table.insert(parts, "mr " .. perStar(effect.magicResistPercent) .. "%")
		table.insert(parts, "as " .. perStar(effect.attackSpeedPercent) .. "%")
		table.insert(parts, "range " .. perStar(effect.range))
		table.insert(parts, "move " .. perStar(effect.moveSpeed))
		if effect.manaPerHit then
			table.insert(parts, "mana/hit " .. perStar(effect.manaPerHit))
		end
		if effect.refill then
			table.insert(parts, "refill")
		end
	else
		if effect.shape then
			table.insert(parts, effect.shape)
		end
		if effect.radius then
			table.insert(parts, "r" .. perStar(effect.radius))
		end
		if effect.length then
			table.insert(parts, "len" .. perStar(effect.length))
		end
		if effect.startAfterTarget then
			table.insert(parts, "past")
		end
		if effect.falloff then
			table.insert(parts, "falloff " .. perStar(effect.falloff) .. "%")
		end
		if effect.damageType then
			table.insert(parts, effect.damageType)
		end
		if effect.distance then
			table.insert(parts, perStar(effect.distance))
		end
		if effect.setsCurrentTarget then
			table.insert(parts, "retarget")
		end
		if effect.stat then
			table.insert(parts, effect.stat)
		end
		if effect.status then
			table.insert(parts, effect.status)
		end
		if effect.count then
			table.insert(parts, "x" .. perStar(effect.count))
		end
		if effect.amount then
			table.insert(parts, perStar(effect.amount))
		end
		if effect.flat then
			table.insert(parts, "+" .. perStar(effect.flat))
		end
		if effect.percent then
			table.insert(parts, (if effect.type == "DEBUFF" then "-" else "+") .. perStar(effect.percent) .. "%")
		end
		if effect.interval then
			table.insert(parts, "every " .. perStar(effect.interval) .. "s")
		end
		if effect.duration then
			table.insert(parts, perStar(effect.duration) .. "s")
		end
		if effect.permanent then
			table.insert(parts, "permanent")
		end
		if effect.stackPerCast then
			table.insert(parts, "stacks " .. perStar(effect.maxStacks))
		end
		if effect.pool then
			table.insert(parts, "pool")
		end
		if effect.healPerHit then
			table.insert(parts, "heal/hit " .. perStar(effect.healPerHit))
		end
		if effect.healPercentOfDamage then
			table.insert(parts, "lifesteal " .. perStar(effect.healPercentOfDamage) .. "%")
		end
		if effect.weakenPercent then
			table.insert(parts, "weaken " .. perStar(effect.weakenPercent) .. "%")
		end
		local onEnd = effect.damageOnEnd
		if onEnd then
			local text = "onEnd " .. onEnd.damageType .. " " .. perStar(onEnd.amount)
			if onEnd.healPercentOfDamage then
				text ..= " lifesteal " .. perStar(onEnd.healPercentOfDamage) .. "%"
			end
			table.insert(parts, text)
		end
	end
	local bonus = effect.bonus
	if bonus then
		local kind = bonus.type .. (if bonus.status then ":" .. bonus.status else "")
		table.insert(parts, "bonus " .. kind .. " " .. perStar(bonus.percent) .. "%")
	end
	local condition = effect.condition
	if condition then
		local text = (if condition.negate then "unless " else "if ") .. condition.type
		if condition.healthPercent then
			text ..= " " .. number(condition.healthPercent)
		end
		if condition.atLeast then
			text ..= " " .. number(condition.atLeast)
		end
		if condition.every then
			text ..= " " .. number(condition.at) .. "/" .. number(condition.every)
		end
		table.insert(parts, text)
	end
	if effect.delay then
		table.insert(parts, "@" .. perStar(effect.delay) .. "s")
	end
	if effect.fixedCenter then
		table.insert(parts, "fixed")
	end
	return table.concat(parts, " ")
end

-- Describes an ability's effects, then its ability-level options in brackets.
local function abilityText(ability): string
	local effects = {}
	for _, effect in ability.effects do
		table.insert(effects, effectText(effect))
	end
	local options = {}
	if ability.castTime then
		table.insert(options, "cast " .. number(ability.castTime) .. "s")
	end
	if ability.resetAttackTimer then
		table.insert(options, "reset")
	end
	if ability.selfStun then
		table.insert(options, "selfstun " .. perStar(ability.selfStun) .. "s")
	end
	if ability.nearbyRange then
		table.insert(options, "nearby " .. number(ability.nearbyRange))
	end
	if ability.clusterRadius then
		table.insert(options, "cluster " .. number(ability.clusterRadius))
	end
	if ability.formOnly then
		table.insert(options, "formOnly")
	end
	local followUp = ability.onTargetKilled
	if followUp then
		local repeated = {}
		for _, effect in followUp.effects do
			table.insert(repeated, effectText(effect))
		end
		table.insert(
			options,
			string.format(
				"onKill %ss x%d: %s",
				perStar(followUp.window),
				followUp.maxRepeats,
				table.concat(repeated, ", ")
			)
		)
	end
	local text = table.concat(effects, "; ")
	if #options > 0 then
		text = (if text ~= "" then text .. " " else "") .. "[" .. table.concat(options, ", ") .. "]"
	end
	return text
end

-- Every effect of every character, with its character's id.
local function allEffects()
	local result = {}
	for id, unit in UnitConfig do
		for _, effect in unit.ability.effects do
			table.insert(result, { id = id, effect = effect })
		end
	end
	return result
end

local function sortedKeys(set): string
	local list = {}
	for key in set do
		table.insert(list, key)
	end
	table.sort(list)
	return table.concat(list, ",")
end

-- The event each effect type produces. KNOCKBACK (needs a free hex behind its target) and RECALL
-- (needs summons) may produce none in a single cast, so they are not checked.
local EVENT_FOR_EFFECT = {
	DAMAGE = "Damage",
	AREA_DAMAGE = "Area",
	DEBUFF = "Buff",
	BOUNCE = "Bounce",
	HEAL = "Heal",
	SHIELD = "Shield",
	STUN = "Stun",
	BUFF = "Buff",
	DASH = "Dash",
	AREA_STUN = "AreaStun",
	SUMMON = "Summon",
	PULL = "Pull",
	DAMAGE_OVER_TIME = "Dot",
	COPY = "Copy",
}

local tests = {}

table.insert(tests, {
	name = "the roster is exactly the 42 characters of Block 2, split 9/9/10/9/5 by cost, with their stats",
	run = function()
		local count, perCost = 0, {}
		for id, unit in UnitConfig do
			count += 1
			perCost[unit.cost] = (perCost[unit.cost] or 0) + 1
			local spec = SPEC[id]
			assert(spec, "unexpected unit " .. id)
			for i, field in FIELDS do
				local value = unit[field]
				if field == "moveSpeed" and unit.forms then
					value = Forms.baseStat(unit, unit.forms[1], "MoveSpeed", "moveSpeed")
				end
				expectEqual(value, spec[i], id .. " " .. field)
			end
			expectEqual(unit.abilityPower, 100, id .. " abilityPower")
			expectEqual(unit.ability.name, id, id .. " ability name is its id")
		end
		expectEqual(count, 42, "characters")
		for cost, expected in { 9, 9, 10, 9, 5 } do
			expectEqual(perCost[cost], expected, cost .. "-cost characters")
		end
	end,
})

table.insert(tests, {
	name = "every character has exactly one origin and one or two classes, as in Block 2",
	run = function()
		for id, unit in UnitConfig do
			local spec = TRAITS[id]
			expectEqual(unit.origin, spec[1], id .. " origin")
			assert(#unit.classes >= 1 and #unit.classes <= 2, id .. " needs one or two classes")
			expectEqual(table.concat(unit.classes, "/"), table.concat(spec, "/", 2), id .. " classes")
		end
	end,
})

table.insert(tests, {
	name = "every ability matches Block 2 or its Overhaul 1 rework, and so does every form ability",
	run = function()
		for id, unit in UnitConfig do
			local text = abilityText(unit.ability)
			assert(
				text == ABILITIES[id],
				string.format("%s:\n  data: %s\n  spec: %s", id, text, tostring(ABILITIES[id]))
			)
		end
		local seen = {}
		for id, unit in UnitConfig do
			for _, form in unit.forms or {} do
				if form.ability then
					local key = id .. "/" .. form.name
					seen[key] = true
					local text = abilityText(form.ability)
					assert(
						text == FORM_ABILITIES[key],
						string.format("%s:\n  data: %s\n  spec: %s", key, text, tostring(FORM_ABILITIES[key]))
					)
				end
			end
		end
		for key in FORM_ABILITIES do
			assert(seen[key], key .. " has no form ability")
		end
	end,
})

table.insert(tests, {
	name = "exactly the characters with transformations have forms, and every form list is valid",
	run = function()
		local withForms = {}
		local formNames = {}
		for id, unit in UnitConfig do
			local ok, reason = Forms.validate(unit.forms)
			assert(ok, id .. ": " .. tostring(reason))
			if unit.forms then
				withForms[id] = true
				for _, form in unit.forms do
					-- Form looks are keyed by form name, so names may only repeat for the two riders.
					local owner = formNames[form.name]
					assert(
						owner == nil
							or (UnitConfig[owner].forms[1].name == "Mounted" and unit.forms[1].name == "Mounted"),
						form.name .. " is used by " .. tostring(owner) .. " and " .. id
					)
					formNames[form.name] = id
					if form.ability then
						local abilityOk, abilityReason = Abilities.validate(form.ability)
						assert(abilityOk, id .. " form " .. form.name .. ": " .. tostring(abilityReason))
					end
				end
			end
		end
		expectEqual(
			sortedKeys(withForms),
			"ascending_core,elastic_wardrum,field_medic,orbit_breaker,ripcord_frenzy,shade_pack,spurshot,titanheart",
			"units with forms"
		)
	end,
})

table.insert(tests, {
	name = "every ability and passive (aura, attack stacks) is valid data, with no exceptions",
	run = function()
		for id, unit in UnitConfig do
			local ok, reason = Abilities.validate(unit.ability)
			assert(ok, id .. ": " .. tostring(reason))
			ok, reason = Abilities.validateUnit(unit)
			assert(ok, id .. " passives: " .. tostring(reason))
		end
	end,
})

table.insert(tests, {
	name = "structure: exactly the three listed characters use FARTHEST_ENEMY",
	run = function()
		local users = {}
		for _, each in allEffects() do
			if each.effect.target == "FARTHEST_ENEMY" or each.effect.center == "FARTHEST_ENEMY" then
				users[each.id] = true
			end
		end
		expectEqual(sortedKeys(users), "flashline,horizon_cut,reelbreaker", "FARTHEST_ENEMY users")
	end,
})

table.insert(tests, {
	name = "structure: only the two permitted abilities use a radius-2 area stun; no stun exceeds 2.0s",
	run = function()
		local radiusTwo = {}
		for _, each in allEffects() do
			local effect = each.effect
			if effect.type == "AREA_STUN" then
				for star = 1, 3 do
					local radius = if type(effect.radius) == "table" then effect.radius[star] else effect.radius
					if radius > 1 then
						radiusTwo[each.id] = effect.center
					end
				end
			end
			if effect.type == "STUN" or effect.type == "AREA_STUN" then
				for star = 1, 3 do
					local duration = if type(effect.duration) == "table" then effect.duration[star] else effect.duration
					assert(
						duration <= CombatConfig.maxStunSeconds,
						string.format("%s %d-star stun of %gs", each.id, star, duration)
					)
				end
			end
		end
		-- Overhaul 1: zero_field's stun is now radius 1 on her target; frozen_moment's is radius 2.
		expectEqual(sortedKeys(radiusTwo), "frozen_moment,infinite_collapse", "radius-2 area stuns")
		expectEqual(radiusTwo.frozen_moment, "SELF", "the close-range radius-2 stun is self-centered")
	end,
})

table.insert(tests, {
	name = "structure: the retarget flag is set exactly on dashes Block 2 gives a new CURRENT_TARGET",
	run = function()
		local retargeting, plain = {}, {}
		for _, each in allEffects() do
			if each.effect.type == "DASH" then
				if each.effect.setsCurrentTarget then
					retargeting[each.id] = true
				else
					plain[each.id] = true
				end
			end
		end
		expectEqual(
			sortedKeys(retargeting),
			"cyclone_edge,flare_kick,flashline,redline_cut,wolfstep",
			"retargeting dashes"
		)
		-- Dashes at CURRENT_TARGET need no retarget flag.
		expectEqual(sortedKeys(plain), "iron_rush,thunder_nest,volt_spear", "plain dashes")
	end,
})

table.insert(tests, {
	name = "every ability runs through the interpreter at 1, 2 and 3 stars and applies each effect",
	run = function()
		-- Two layouts, so every effect has a fitting situation: the caster at the back facing
		-- enemies 3+ hexes away (dashes and pulls have somewhere to go), and the caster at the front
		-- with an enemy next to it (self-centered areas have someone to hit). Each has a hurt ally.
		local layouts = { { caster = { 4, 2 }, ally = { 3, 2 } }, { caster = { 4, 4 }, ally = { 3, 4 } } }
		for id, unit in UnitConfig do
			for starLevel = 1, 3 do
				local seen = {}
				for _, layout in layouts do
					local battle = Battle.new({
						boards = {
							{
								{
									id = "caster",
									unitType = id,
									starLevel = starLevel,
									column = layout.caster[1],
									row = layout.caster[2],
								},
								{
									id = "ally",
									unitType = "elastic_wardrum",
									column = layout.ally[1],
									row = layout.ally[2],
								},
							},
							{
								{ id = "e1", unitType = "cinder_arc", column = 4, row = 4 },
								{ id = "e2", unitType = "starless_burst", column = 3, row = 1 },
								{ id = "e3", unitType = "flare_kick", column = 5, row = 3 },
							},
						},
						columns = 7,
						rows = 4,
						unitTypes = UnitConfig,
						ticksPerSecond = 20,
						maxTicks = 1000,
						seed = starLevel,
					})
					local caster, ally = battle.units[1], battle.units[2]
					ally.health = ally.maxHealth // 2
					caster.target = battle.units[3]
					-- Sturdy enemies, so a big first hit cannot leave later effects without a target.
					for _, enemy in battle.units do
						if enemy.side == 2 then
							enemy.maxHealth, enemy.baseMaxHealth, enemy.health = 1e6, 1e6, 1e6
						end
					end

					local ok, err = pcall(Abilities.cast, battle, caster)
					assert(ok, string.format("%s %d-star cast failed: %s", id, starLevel, tostring(err)))
					assert(caster.mana == 0, id .. ": mana should be 0 after casting")
					for _, event in battle.events do
						seen[event.kind] = true
					end
				end
				assert(seen.Cast, id .. ": no Cast event")
				for index, effect in unit.ability.effects do
					local kind = EVENT_FOR_EFFECT[effect.type]
					-- Conditional and delayed effects need a situation (a kill, a low ally, time) that a
					-- single cast does not give; OverhaulEngineTest covers them.
					local checked = kind ~= nil and effect.condition == nil and effect.delay == nil
					assert(
						not checked or seen[kind],
						string.format(
							"%s %d-star effect %d (%s) produced no %s event",
							id,
							starLevel,
							index,
							effect.type,
							tostring(kind)
						)
					)
				end
			end
		end
	end,
})

-- Runs `id` against an adjacent cinder_arc and a back-row horizon_cut (the farthest enemy and the
-- one with the highest AD), with full mana and cinder_arc as its target, for `ticks` ticks.
local function diveBattle(id: string, seed: number, ticks: number)
	local battle = Battle.new({
		boards = {
			{ { id = "diver", unitType = id, column = 4, row = 4 } },
			{
				{ id = "near", unitType = "cinder_arc", column = 4, row = 4 },
				{ id = "far", unitType = "horizon_cut", column = 4, row = 1 },
			},
		},
		columns = 7,
		rows = 4,
		unitTypes = UnitConfig,
		ticksPerSecond = 20,
		maxTicks = 1000,
		seed = seed,
	})
	local diver, near, far = battle.units[1], battle.units[2], battle.units[3]
	assert(Battle.distance(diver, near) == 1, "test setup: near starts adjacent")
	assert(Battle.distance(diver, far) == 4, "test setup: far starts 4 hexes away")
	diver.mana = diver.maxMana
	diver.target = near
	for _ = 1, ticks do
		CombatSim.step(battle)
	end
	return battle, diver, near, far
end

table.insert(tests, {
	name = "retargeting dashers that reach the far enemy hit it and keep attacking it",
	run = function()
		-- Overhaul 1: redline_cut dashes to the enemy attacking her lowest ally, flare_kick to the
		-- lowest-health enemy within 2 hexes; iron_rush and volt_spear charge their current target.
		for _, id in { "cyclone_edge", "flashline", "wolfstep" } do
			for seed = 1, 5 do
				local battle, diver, near, far = diveBattle(id, seed, 80)
				local dashed, abilityHit, attacksOnFar, attacksOnNear, casts = false, false, 0, 0, 0
				for _, event in battle.events do
					if event.kind == "Death" and event.unit == far.index then
						break
					end
					if event.kind == "Cast" and event.unit == diver.index then
						casts += 1
						if casts > 1 then
							break
						end
					end
					if event.unit == diver.index then
						if event.kind == "Dash" then
							dashed = true
						elseif event.kind == "Damage" and event.target == far.index then
							abilityHit = true
						elseif event.kind == "Attack" and event.target == far.index then
							attacksOnFar += 1
						elseif event.kind == "Attack" and event.target == near.index then
							attacksOnNear += 1
						end
					end
				end
				local label = string.format("%s (seed %d)", id, seed)
				assert(dashed, label .. " did not dash")
				assert(abilityHit, label .. ": the ability did not hit the far enemy")
				assert(attacksOnFar > 0 and attacksOnNear == 0, label .. " should attack the far enemy after the dive")
			end
		end
	end,
})

table.insert(tests, {
	name = "reelbreaker pulls the farthest enemy next to it and hits it",
	run = function()
		local battle, puller, _, far = diveBattle("reelbreaker", 1, 1)
		local pulled = false
		for _, event in battle.events do
			if event.kind == "Pull" and event.unit == puller.index then
				pulled = event.target == far.index
			end
		end
		assert(pulled, "no pull of the farthest enemy")
		expectEqual(HexGrid.distance(puller.column, puller.row, far.column, far.row), 1, "pulled adjacent")
		assert(puller.target == far, "the pulled enemy is the new current target")
	end,
})

return tests
