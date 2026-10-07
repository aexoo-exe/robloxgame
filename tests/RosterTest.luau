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
	spurshot = { 1, 550, 64, 18, 18, 0.76, 3, 1.2, 20, 80 },
	ripcord_frenzy = { 1, 700, 58, 28, 24, 0.72, 1, 1.0, 30, 90 },
	null_edge = { 1, 680, 61, 30, 35, 0.68, 1, 1.0, 30, 90 },
	bitter_vapor = { 1, 580, 43, 20, 30, 0.62, 3, 1.0, 40, 100 },
	iron_rush = { 1, 750, 48, 40, 35, 0.56, 1, 0.9, 40, 100 },
	blooming_aid = { 1, 600, 46, 22, 28, 0.65, 2, 1.0, 40, 100 },

	redline_cut = { 2, 690, 68, 27, 25, 0.83, 1, 1.1, 20, 80 },
	flare_kick = { 2, 760, 69, 30, 27, 0.78, 1, 1.1, 30, 90 },
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
	skyboulder = { 3, 900, 76, 38, 35, 0.72, 4, 0.9, 30, 100 },
	horizon_cut = { 3, 820, 80, 32, 30, 0.84, 3, 1.0, 20, 90 },
	zero_field = { 3, 760, 52, 27, 35, 0.68, 3, 1.0, 40, 110 },

	reelbreaker = { 4, 1050, 88, 45, 40, 0.72, 2, 1.0, 40, 130 },
	elastic_wardrum = { 4, 1200, 84, 55, 50, 0.80, 1, 1.0, 40, 110 },
	starless_burst = { 4, 830, 67, 28, 48, 0.80, 4, 1.0, 20, 100 },
	echo_legion = { 4, 1050, 82, 42, 42, 0.82, 2, 1.1, 30, 110 },
	night_command = { 4, 900, 89, 32, 34, 0.94, 1, 1.1, 30, 100 },
	frozen_moment = { 4, 950, 88, 38, 38, 0.86, 1, 1.0, 40, 110 },
	cyclone_edge = { 4, 860, 90, 30, 30, 0.95, 1, 1.2, 20, 90 },
	night_parade = { 4, 900, 68, 32, 42, 0.75, 3, 1.0, 30, 110 },
	restoration_strike = { 4, 1100, 78, 48, 45, 0.72, 1, 1.0, 40, 120 },

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

-- Block 2: origin and classes.
local TRAITS = {
	flashline = { "Hunters", "Blade", "Assassin" },
	cinder_arc = { "Hunters", "Blade" },
	wolfstep = { "Corps", "Blade" },
	spurshot = { "Spirit", "Marksman" },
	ripcord_frenzy = { "Cursed", "Brawler" },
	null_edge = { "Arcane", "Blade" },
	bitter_vapor = { "Arcane", "Support" },
	iron_rush = { "Titans", "Guardian" },
	blooming_aid = { "Shinobi", "Support" },
	redline_cut = { "Corps", "Blade" },
	flare_kick = { "Crew", "Brawler" },
	burst_vector = { "Heroes", "Caster", "Marksman" },
	skybreaker = { "Heroes", "Brawler" },
	crimson_hunger = { "Cursed", "Assassin" },
	orbit_breaker = { "Spirit", "Marksman" },
	marsh_fortress = { "Shinobi", "Guardian" },
	shade_pack = { "Cursed", "Caster" },
	field_medic = { "Crew", "Support" },
	volt_spear = { "Shinobi", "Blade", "Assassin" },
	thunder_nest = { "Hunters", "Assassin" },
	threefold_crash = { "Crew", "Blade" },
	titanheart = { "Titans", "Guardian" },
	snapfire = { "Arcane", "Caster" },
	mirror_script = { "Shinobi", "Assassin", "Caster" },
	clockbreaker = { "Spirit", "Brawler" },
	skyboulder = { "Titans", "Marksman" },
	horizon_cut = { "Hunters", "Blade", "Marksman" },
	zero_field = { "Heroes", "Support" },
	reelbreaker = { "Hunters", "Brawler" },
	elastic_wardrum = { "Crew", "Brawler", "Guardian" },
	starless_burst = { "Arcane", "Caster", "Marksman" },
	echo_legion = { "Shinobi", "Brawler", "Caster" },
	night_command = { "Hunters", "Assassin" },
	frozen_moment = { "Spirit", "Assassin" },
	cyclone_edge = { "Corps", "Blade", "Assassin" },
	night_parade = { "Cursed", "Caster" },
	restoration_strike = { "Spirit", "Support", "Brawler" },
	severing_temple = { "Cursed", "Caster", "Blade" },
	ascending_core = { "Heroes", "Brawler", "Caster" },
	final_argument = { "Heroes", "Brawler" },
	infinite_collapse = { "Cursed", "Caster" },
	boiling_crown = { "Titans", "Guardian", "Caster" },
}

-- Block 2 abilities, written the way abilityText (below) describes the data. Where a dash gives a
-- "new CURRENT_TARGET" ("retarget"), the cast's later effects name the dash's selector, because
-- selectors resolve once per cast.
local ABILITIES = {
	flashline = "DASH FARTHEST_ENEMY 4 retarget; DAMAGE FARTHEST_ENEMY PHYSICAL 140/225/360",
	cinder_arc = "DAMAGE CURRENT_TARGET PHYSICAL 105/170/270; AREA_DAMAGE CURRENT_TARGET r1 MAGIC 65/105/170; BUFF SELF AttackSpeed +18/28/42% 5s",
	wolfstep = "DASH HIGHEST_AD_ENEMY 3 retarget; DAMAGE HIGHEST_AD_ENEMY PHYSICAL 135/215/345",
	spurshot = "DAMAGE FARTHEST_ENEMY PHYSICAL 140/225/360; BUFF SELF AttackSpeed +15/25/40% 4s",
	ripcord_frenzy = "BUFF SELF AttackSpeed +25/40/60% 5s; HEAL SELF 80/130/210",
	null_edge = "DAMAGE CURRENT_TARGET PHYSICAL 130/210/335; BUFF SELF MR +25/40/65 5s",
	bitter_vapor = "DAMAGE_OVER_TIME CURRENT_TARGET r1 MAGIC 22/35/56 every 1s 4s; HEAL LOWEST_HP_ALLY 70/110/175",
	iron_rush = "BUFF SELF Armor +30/45/70 5s; DASH HIGHEST_AD_ENEMY 2 retarget; DAMAGE HIGHEST_AD_ENEMY PHYSICAL 85/135/215; STUN HIGHEST_AD_ENEMY 0.75/1/1.5s",
	blooming_aid = "HEAL LOWEST_HP_ALLY 120/190/305",

	redline_cut = "DASH HIGHEST_AD_ENEMY 3 retarget; DAMAGE HIGHEST_AD_ENEMY PHYSICAL 215/345/550; BUFF SELF AttackSpeed +20/32/50% 4s",
	flare_kick = "DAMAGE CURRENT_TARGET PHYSICAL 150/240/385; AREA_DAMAGE CURRENT_TARGET r1 MAGIC 75/120/190",
	burst_vector = "AREA_DAMAGE CURRENT_TARGET r1 MAGIC 210/335/535; BUFF SELF AD +10/15/25% 4s",
	skybreaker = "DASH HIGHEST_AD_ENEMY 3; AREA_DAMAGE HIGHEST_AD_ENEMY r1 PHYSICAL 210/335/535",
	crimson_hunger = "DAMAGE CURRENT_TARGET PHYSICAL 220/350/560; HEAL SELF 90/145/230",
	orbit_breaker = "DAMAGE CURRENT_TARGET PHYSICAL 220/350/560; STUN CURRENT_TARGET 1/1.5/2s",
	marsh_fortress = "SHIELD SELF 280/450/720 6s; AREA_DAMAGE SELF r1 PHYSICAL 85/135/215",
	shade_pack = "SUMMON x2/2/3 8/9/10s hp 30/35/40% ad 45/50/55% armor 50% mr 50% as 90% range 1 move 1.1",
	field_medic = "HEAL ALL_ALLIES 45/70/110; SHIELD LOWEST_HP_ALLY 150/240/385 5s",

	volt_spear = "DASH FARTHEST_ENEMY 4 retarget; DAMAGE FARTHEST_ENEMY MAGIC 300/480/770; STUN FARTHEST_ENEMY 0.75/1.25/1.75s",
	thunder_nest = "DASH HIGHEST_AD_ENEMY 3; AREA_DAMAGE SELF r1 MAGIC 250/400/640; AREA_STUN SELF r1 1/1.5/2s",
	threefold_crash = "DASH HIGHEST_AD_ENEMY 3; AREA_DAMAGE HIGHEST_AD_ENEMY r1 PHYSICAL 280/450/720; STUN HIGHEST_AD_ENEMY 0.75/1.25/1.75s",
	titanheart = "SHIELD SELF 360/575/920 6s; BUFF SELF Armor +30/45/70 6s; BUFF SELF AD +15/25/40% 6s",
	snapfire = "AREA_DAMAGE HIGHEST_AD_ENEMY r1 MAGIC 300/480/770",
	mirror_script = "COPY HIGHEST_AD_ENEMY",
	clockbreaker = "AREA_STUN SELF r1 1/1.5/2s; DAMAGE CURRENT_TARGET PHYSICAL 300/480/770",
	skyboulder = "AREA_DAMAGE FARTHEST_ENEMY r1 PHYSICAL 300/480/770",
	horizon_cut = "DAMAGE FARTHEST_ENEMY MAGIC 330/525/840",
	zero_field = "AREA_STUN SELF r2 0.75/1.25/1.75s; BUFF ALL_ALLIES AttackSpeed +12/20/32% 5s",

	reelbreaker = "PULL FARTHEST_ENEMY; DAMAGE FARTHEST_ENEMY PHYSICAL 390/625/1000",
	elastic_wardrum = "SHIELD SELF 400/640/1025 6s; BUFF SELF AD +20/32/50% 6s; BUFF SELF AttackSpeed +20/32/50% 6s",
	starless_burst = "AREA_DAMAGE HIGHEST_AD_ENEMY r1 MAGIC 350/560/895; SHIELD SELF 250/400/640 5s",
	echo_legion = "SUMMON x2/2/3 8/9/10s hp 25/30/35% ad 35/40/45% armor 40% mr 40% as 100% range 1 move 1.1; AREA_DAMAGE CURRENT_TARGET r1 MAGIC 270/430/690",
	night_command = "SUMMON x2/3/3 9/10/12s hp 30/35/40% ad 50/55/65% armor 55% mr 55% as 95% range 1 move 1.1",
	frozen_moment = "AREA_STUN SELF r1 1/1.5/2s; DAMAGE CURRENT_TARGET PHYSICAL 320/510/815; HEAL SELF 180/290/465",
	cyclone_edge = "DASH HIGHEST_AD_ENEMY 4 retarget; AREA_DAMAGE HIGHEST_AD_ENEMY r1 PHYSICAL 330/525/840; BUFF SELF AttackSpeed +35/55/80% 4s",
	night_parade = "AREA_DAMAGE CURRENT_TARGET r1 MAGIC 220/350/560; SUMMON x2/2/3 9/10/12s hp 35/40/45% ad 40/50/60% armor 45% mr 45% as 85% range 1 move 1",
	restoration_strike = "HEAL LOWEST_HP_OTHER_ALLY 450/720/1150; DAMAGE CURRENT_TARGET PHYSICAL 200/320/510",

	severing_temple = "AREA_DAMAGE CURRENT_TARGET r2 PHYSICAL 450/720/1150; DAMAGE_OVER_TIME CURRENT_TARGET r2 MAGIC 35/55/90 every 1s 4s",
	ascending_core = "BUFF SELF AD +10/15/22% 8s stacks 3; BUFF SELF AP +12/18/27 8s stacks 3; BUFF SELF AttackSpeed +10/15/22% 8s stacks 3; AREA_DAMAGE CURRENT_TARGET r1 MAGIC 400/640/1025",
	final_argument = "DAMAGE CURRENT_TARGET TRUE 900/1500/3000",
	infinite_collapse = "AREA_STUN HIGHEST_AD_ENEMY r2 1.5/2/2s; SHIELD SELF 350/560/895 5s; AREA_DAMAGE HIGHEST_AD_ENEMY r2 MAGIC 450/720/1150",
	boiling_crown = "AREA_DAMAGE SELF r1 MAGIC 170/270/430; DAMAGE_OVER_TIME SELF r1 MAGIC 30/48/76 every 1s 4s; BUFF SELF Armor +30/45/70 6s; BUFF SELF MR +30/45/70 6s",
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

-- Describes an ability's effects in the spec strings' format.
local function abilityText(ability): string
	local effects = {}
	for _, effect in ability.effects do
		local parts = { effect.type }
		if effect.target or effect.center then
			table.insert(parts, effect.target or effect.center)
		end
		if effect.type == "SUMMON" then
			table.insert(parts, "x" .. perStar(effect.count))
			table.insert(parts, perStar(effect.duration) .. "s")
			table.insert(parts, "hp " .. perStar(effect.healthPercent) .. "%")
			table.insert(parts, "ad " .. perStar(effect.attackDamagePercent) .. "%")
			table.insert(parts, "armor " .. perStar(effect.armorPercent) .. "%")
			table.insert(parts, "mr " .. perStar(effect.magicResistPercent) .. "%")
			table.insert(parts, "as " .. perStar(effect.attackSpeedPercent) .. "%")
			table.insert(parts, "range " .. perStar(effect.range))
			table.insert(parts, "move " .. perStar(effect.moveSpeed))
		else
			if effect.radius then
				table.insert(parts, "r" .. perStar(effect.radius))
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
			if effect.amount then
				table.insert(parts, perStar(effect.amount))
			end
			if effect.flat then
				table.insert(parts, "+" .. perStar(effect.flat))
			end
			if effect.percent then
				table.insert(parts, "+" .. perStar(effect.percent) .. "%")
			end
			if effect.interval then
				table.insert(parts, "every " .. perStar(effect.interval) .. "s")
			end
			if effect.duration then
				table.insert(parts, perStar(effect.duration) .. "s")
			end
			if effect.stackPerCast then
				table.insert(parts, "stacks " .. perStar(effect.maxStacks))
			end
		end
		table.insert(effects, table.concat(parts, " "))
	end
	return table.concat(effects, "; ")
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

-- The event each effect type produces.
local EVENT_FOR_EFFECT = {
	DAMAGE = "Damage",
	AREA_DAMAGE = "Damage",
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
	name = "every ability matches Block 2",
	run = function()
		for id, unit in UnitConfig do
			local text = abilityText(unit.ability)
			assert(
				text == ABILITIES[id],
				string.format("%s:\n  data: %s\n  spec: %s", id, text, tostring(ABILITIES[id]))
			)
		end
	end,
})

table.insert(tests, {
	name = "only the two riders have forms, and every form list is valid",
	run = function()
		local withForms = {}
		for id, unit in UnitConfig do
			local ok, reason = Forms.validate(unit.forms)
			assert(ok, id .. ": " .. tostring(reason))
			if unit.forms then
				withForms[id] = true
				for _, form in unit.forms do
					if form.ability then
						local abilityOk, abilityReason = Abilities.validate(form.ability)
						assert(abilityOk, id .. " form " .. form.name .. ": " .. tostring(abilityReason))
					end
				end
			end
		end
		expectEqual(sortedKeys(withForms), "orbit_breaker,spurshot", "units with forms")
	end,
})

table.insert(tests, {
	name = "every ability is valid data, with no exceptions",
	run = function()
		for id, unit in UnitConfig do
			local ok, reason = Abilities.validate(unit.ability)
			assert(ok, id .. ": " .. tostring(reason))
		end
	end,
})

table.insert(tests, {
	name = "structure: exactly the six listed characters use FARTHEST_ENEMY",
	run = function()
		local users = {}
		for _, each in allEffects() do
			if each.effect.target == "FARTHEST_ENEMY" or each.effect.center == "FARTHEST_ENEMY" then
				users[each.id] = true
			end
		end
		expectEqual(
			sortedKeys(users),
			"flashline,horizon_cut,reelbreaker,skyboulder,spurshot,volt_spear",
			"FARTHEST_ENEMY users"
		)
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
		expectEqual(sortedKeys(radiusTwo), "infinite_collapse,zero_field", "radius-2 area stuns")
		expectEqual(radiusTwo.zero_field, "SELF", "the defensive radius-2 stun is self-centered")
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
			"cyclone_edge,flashline,iron_rush,redline_cut,volt_spear,wolfstep",
			"retargeting dashes"
		)
		expectEqual(sortedKeys(plain), "skybreaker,threefold_crash,thunder_nest", "plain dashes")
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
					assert(
						seen[kind],
						string.format(
							"%s %d-star effect %d (%s) produced no %s event",
							id,
							starLevel,
							index,
							effect.type,
							kind
						)
					)
				end
			end
		end
	end,
})

-- Runs `id` against an adjacent cinder_arc and a back-row spurshot (the farthest enemy and the one
-- with the highest AD), with full mana and cinder_arc as its target, for `ticks` ticks.
local function diveBattle(id: string, seed: number, ticks: number)
	local battle = Battle.new({
		boards = {
			{ { id = "diver", unitType = id, column = 4, row = 4 } },
			{
				{ id = "near", unitType = "cinder_arc", column = 4, row = 4 },
				{ id = "far", unitType = "spurshot", column = 4, row = 1 },
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
		-- iron_rush dashes only 2 hexes, so it lands short of an enemy 4 hexes away.
		for _, id in { "cyclone_edge", "flashline", "redline_cut", "volt_spear", "wolfstep" } do
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
