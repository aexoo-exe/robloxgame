-- Forms (transformations) and the rider mounts built on them. Rule-override cases use test-only
-- unit types; the rider checks use the real riders from UnitConfig. Characters are named by
-- internal id only.

local Abilities = require("../src/shared/Abilities")
local Battle = require("../src/shared/Battle")
local CombatMath = require("../src/shared/CombatMath")
local CombatSim = require("../src/shared/CombatSim")
local FormConfig = require("../src/shared/FormConfig")
local Forms = require("../src/shared/Forms")
local StarLevel = require("../src/shared/StarLevel")
local UnitConfig = require("../src/shared/UnitConfig")

local function expectEqual(actual, expected, label)
	assert(actual == expected, string.format("%s: expected %s, got %s", label, tostring(expected), tostring(actual)))
end

local function near(actual: number, expected: number, label: string)
	assert(math.abs(actual - expected) < 1e-9, string.format("%s: expected %s, got %s", label, expected, actual))
end

local POOL = 200 -- test form pool before scaling
local SCALED_POOL = StarLevel.scaleHealth(POOL, 1) -- 232

-- A sturdy test unit type that does nothing unless overridden.
local function unitType(overrides)
	local stats = {
		cost = 1,
		health = 1000,
		attackDamage = 0,
		attacksPerSecond = 1,
		range = 1,
		moveSpeed = 1,
		armor = 0,
		magicResist = 0,
		startingMana = 0,
		maxMana = 100,
	}
	for key, value in overrides or {} do
		stats[key] = value
	end
	return stats
end

-- A two-form test unit: "Big" with a pool of POOL and `rules`, then "Small". `small` adds fields to
-- the second form.
local function formType(rules, small)
	local second = { name = "Small" }
	for key, value in small or {} do
		second[key] = value
	end
	return unitType({
		forms = {
			{
				name = "Big",
				health = POOL,
				stats = { MoveSpeed = { flat = 0.5 }, AD = { flat = 10 } },
				rules = rules,
				trigger = { type = "FORM_HEALTH_DEPLETED" },
			},
			second,
		},
	})
end

-- A battle of `types` (unit type names, side 1 first) on a 7x4 board, units spread out so nobody
-- is in range of anyone. Returns the battle and its units in order.
local function newBattle(unitTypes, sides: { { string } }, starLevel: number?)
	local boards = { {}, {} }
	for side, names in sides do
		for i, name in names do
			table.insert(boards[side], {
				id = side .. ":" .. i,
				unitType = name,
				starLevel = starLevel,
				column = i * 2 - 1,
				row = 1,
			})
		end
	end
	local battle = Battle.new({
		boards = boards,
		columns = 7,
		rows = 4,
		unitTypes = unitTypes,
		ticksPerSecond = 20,
		maxTicks = 2000,
		seed = 1,
		critChance = 0,
	})
	return battle, battle.units
end

local function eventsOf(battle, kind: string)
	local result = {}
	for _, event in battle.events do
		if event.kind == kind then
			table.insert(result, event)
		end
	end
	return result
end

local function lastEvent(battle)
	return battle.events[#battle.events]
end

local tests = {}

-- Data --------------------------------------------------------------------------------------------

table.insert(tests, {
	name = "Forms.validate accepts no forms and the riders, and rejects broken form lists",
	run = function()
		assert(Forms.validate(nil), "no forms is valid")
		assert(Forms.validate(UnitConfig.spurshot.forms), "spurshot forms")
		local trigger = { type = "FORM_HEALTH_DEPLETED" }
		local function remountTo(extra)
			local back = { type = "TAKEDOWN", to = "A" }
			for key, value in extra do
				back[key] = value
			end
			return { { name = "A", health = 10 }, { name = "B", trigger = back } }
		end
		local broken = {
			{ "empty list", {} },
			{ "unknown trigger", { { name = "A", health = 10, trigger = { type = "NOPE" } }, { name = "B" } } },
			{ "pool trigger without a pool", { { name = "A", trigger = trigger }, { name = "B" } } },
			{ "no form to move to", { { name = "A", health = 10, trigger = trigger } } },
			{ "unknown destination", { { name = "A", health = 10, trigger = { type = "TAKEDOWN", to = "Z" } } } },
			{ "duplicate names", { { name = "A" }, { name = "A" } } },
			{ "unknown stat", { { name = "A", stats = { MaxHealth = { flat = 5 } } } } },
			{ "stat without values", { { name = "A", stats = { AD = {} } } } },
			{ "unknown rule", { { name = "A", rules = { nope = true } } } },
			{ "healthPercent above 100", remountTo({ healthPercent = 150 }) },
			{ "maxUses not whole", remountTo({ maxUses = 1.5 }) },
		}
		assert(Forms.validate(remountTo({ healthPercent = 50, maxUses = 1 })), "a valid remount")
		for _, case in broken do
			local ok = Forms.validate(case[2])
			assert(not ok, case[1] .. " should be rejected")
		end
	end,
})

table.insert(tests, {
	name = "the riders' forms are built from FormConfig: horse pool, speed, bonus damage, remount switch",
	run = function()
		local mount = FormConfig.mount
		for _, id in { "spurshot", "orbit_breaker" } do
			local forms = UnitConfig[id].forms
			expectEqual(#forms, 2, id .. " form count")
			local mounted, dismounted = forms[1], forms[2]
			expectEqual(mounted.name, "Mounted", id .. " starting form")
			expectEqual(dismounted.name, "Dismounted", id .. " second form")
			expectEqual(mounted.health, mount.horseHealth[id], id .. " horse pool")
			expectEqual(mounted.stats.MoveSpeed.flat, mount.mountedMoveSpeedBonus, id .. " mounted speed")
			expectEqual(mounted.stats.AD.flat, mount.mountedBonusDamage, id .. " mounted bonus damage")
			expectEqual(mounted.trigger.type, "FORM_HEALTH_DEPLETED", id .. " dismount trigger")
			expectEqual(dismounted.health, nil, id .. " dismounted has no pool")
			expectEqual(dismounted.trigger.type, "TAKEDOWN", id .. " remount trigger")
			expectEqual(dismounted.trigger.to, "Mounted", id .. " remounts")
			expectEqual(dismounted.trigger.healthPercent, mount.remountHorseHealthPercent, id .. " remount pool")
			expectEqual(dismounted.trigger.maxUses, mount.remountsPerFight, id .. " remounts per fight")
			-- With remounting off, only riders with the remount flag (their bond) can remount.
			expectEqual(
				dismounted.trigger.unlockedBy,
				if mount.remountEnabled then nil else mount.remountFlag,
				id .. " remount needs the flag while remounting is off"
			)
			expectEqual(UnitConfig[id].moveSpeed, 1.0, id .. " base move speed")
		end
	end,
})

-- Riders ------------------------------------------------------------------------------------------

table.insert(tests, {
	name = "riders start mounted: a full star-scaled horse pool, the speed bonus, and the bonus damage",
	run = function()
		for starLevel = 1, 3 do
			local riders = { "spurshot", "orbit_breaker" }
			local battle, units = newBattle(UnitConfig, { riders, { "cinder_arc" } }, starLevel)
			for i, id in riders do
				local rider = units[i]
				local label = string.format("%s %d-star", id, starLevel)
				expectEqual(rider.form.name, "Mounted", label .. " form")
				local pool = StarLevel.scaleHealth(FormConfig.mount.horseHealth[id], starLevel)
				expectEqual(rider.maxFormHealth, pool, label .. " horse pool")
				expectEqual(rider.formHealth, pool, label .. " horse pool is full")
				local mountedSpeed = 1.0 + FormConfig.mount.mountedMoveSpeedBonus
				near(Battle.stat(battle, rider, "MoveSpeed"), mountedSpeed, label .. " speed")
				near(
					Battle.stat(battle, rider, "AD"),
					rider.stats.attackDamage + FormConfig.mount.mountedBonusDamage,
					label .. " attack damage"
				)
			end
			local other = units[3]
			expectEqual(other.form, nil, "units without forms have no form")
			expectEqual(other.formHealth, nil, "units without forms have no pool")
		end
	end,
})

table.insert(tests, {
	name = "mounted, hits go to the horse; the breaking hit's leftover is discarded; the rider dismounts at full HP",
	run = function()
		local battle, units = newBattle(UnitConfig, { { "spurshot" }, { "cinder_arc" } })
		local rider, enemy = units[1], units[2]
		local pool = rider.formHealth

		Battle.damage(battle, enemy, rider, 100, "TRUE", "Damage")
		expectEqual(rider.health, rider.maxHealth, "rider health untouched while mounted")
		expectEqual(rider.formHealth, pool - 100, "horse took the hit")
		expectEqual(lastEvent(battle).formHealth, pool - 100, "the hit's event carries the horse pool")

		Battle.damage(battle, enemy, rider, 100000, "TRUE", "Damage")
		expectEqual(rider.health, rider.maxHealth, "leftover damage does not carry into the rider")
		assert(not rider.dead, "the rider survives the breaking hit")
		expectEqual(rider.form.name, "Dismounted", "dismounted")
		expectEqual(rider.formHealth, nil, "no pool once dismounted")
		local form = lastEvent(battle)
		expectEqual(form.kind, "Form", "the Form event follows the breaking hit")
		expectEqual(form.form, "Dismounted", "Form event names the new form")
		expectEqual(form.health, rider.maxHealth, "Form event: rider at full health")
		near(Battle.stat(battle, rider, "MoveSpeed"), 1.0, "the speed bonus is gone")

		Battle.damage(battle, enemy, rider, 100, "TRUE", "Damage")
		expectEqual(rider.health, rider.maxHealth - 100, "dismounted, hits reach the rider")
		expectEqual(#eventsOf(battle, "Form"), 1, "one form change")
	end,
})

table.insert(tests, {
	name = "riders dismount in real fights, and only riders ever change form",
	run = function()
		for seed = 1, 5 do
			local result = CombatSim.run({
				boards = {
					{
						{ id = "a", unitType = "spurshot", column = 3, row = 1 },
						{ id = "b", unitType = "orbit_breaker", column = 5, row = 1 },
					},
					{
						{ id = "c", unitType = "reelbreaker", column = 3, row = 4, starLevel = 2 },
						{ id = "d", unitType = "cyclone_edge", column = 5, row = 4, starLevel = 2 },
					},
				},
				columns = 7,
				rows = 4,
				unitTypes = UnitConfig,
				ticksPerSecond = 20,
				maxTicks = 20 * 50,
				seed = seed,
			})
			local riders = {}
			for _, unit in result.units do
				if unit.unitType == "spurshot" or unit.unitType == "orbit_breaker" then
					riders[unit.index] = true
					expectEqual(unit.form, "Mounted", "summary: starting form")
					assert(unit.formHealth and unit.formHealth == unit.maxFormHealth, "summary: full horse pool")
				else
					expectEqual(unit.form, nil, "summary: no form for " .. unit.unitType)
				end
			end
			local dismounts = 0
			for _, event in result.events do
				if event.kind == "Form" then
					assert(riders[event.unit], "only riders change form")
					dismounts += 1
				elseif (event.kind == "Attack" or event.kind == "Damage") and not riders[event.target] then
					expectEqual(event.formHealth, nil, "no pool on hits to units without forms")
				end
			end
			assert(dismounts > 0, "seed " .. seed .. ": the 2-star enemies should knock a rider off its horse")
		end
	end,
})

-- Rules -------------------------------------------------------------------------------------------

table.insert(tests, {
	name = "shields absorb before the form pool by default; with the rule off the pool goes first",
	run = function()
		local types = { Default = formType(nil), PoolFirst = formType({ shieldsAbsorbBeforeFormHealth = false }) }
		types.Hitter = unitType()

		local battle, units = newBattle(types, { { "Default", "PoolFirst" }, { "Hitter" } })
		local default, poolFirst, hitter = units[1], units[2], units[3]
		for _, unit in { default, poolFirst } do
			Battle.shield(battle, hitter, unit, 50, 10)
			Battle.damage(battle, hitter, unit, 80, "TRUE", "Damage")
		end
		expectEqual(default.shield, 0, "default: shield used up")
		expectEqual(default.formHealth, SCALED_POOL - 30, "default: pool takes the rest")
		expectEqual(poolFirst.shield, 50, "pool first: shield untouched")
		expectEqual(poolFirst.formHealth, SCALED_POOL - 80, "pool first: pool takes the whole hit")
		expectEqual(default.health, default.maxHealth, "health untouched")
	end,
})

table.insert(tests, {
	name = "heals go to the unit only by default; with the rule on, extra healing refills the pool",
	run = function()
		local types = { Default = formType(nil), Refill = formType({ healingRestoresFormHealth = true }) }
		types.Hitter = unitType()
		local battle, units = newBattle(types, { { "Default", "Refill" }, { "Hitter" } })
		local default, refill, hitter = units[1], units[2], units[3]
		for _, unit in { default, refill } do
			Battle.damage(battle, hitter, unit, 100, "TRUE", "Damage")
			Battle.heal(battle, hitter, unit, 60)
		end
		expectEqual(default.formHealth, SCALED_POOL - 100, "default: the pool is not healed")
		expectEqual(refill.formHealth, SCALED_POOL - 40, "rule on: the pool is healed")
		expectEqual(lastEvent(battle).amount, 60, "rule on: the heal event counts the pool healing")
	end,
})

table.insert(tests, {
	name = "damage over time ticks against the pool by default; with the rule off it hits health",
	run = function()
		local types = { Default = formType(nil), Through = formType({ damageOverTimeHitsFormHealth = false }) }
		types.Hitter = unitType()
		local battle, units = newBattle(types, { { "Default", "Through" }, { "Hitter" } })
		local default, through, hitter = units[1], units[2], units[3]
		for _, unit in { default, through } do
			Battle.damageOverTime(battle, hitter, unit, "test", 30, "TRUE", 1, 3)
		end
		battle.tick += 20
		Battle.tickDots(battle)
		expectEqual(default.formHealth, SCALED_POOL - 30, "default: the tick hits the pool")
		expectEqual(default.health, default.maxHealth, "default: health untouched")
		expectEqual(through.formHealth, SCALED_POOL, "rule off: the pool is untouched")
		expectEqual(through.health, through.maxHealth - 30, "rule off: the tick hits health")
	end,
})

table.insert(tests, {
	name = "stuns and damage over time carry through a form change by default; with the rule off they end",
	run = function()
		local types = { Default = formType(nil), Cleansed = formType({ statusEffectsCarryThrough = false }) }
		types.Hitter = unitType()
		local battle, units = newBattle(types, { { "Default", "Cleansed" }, { "Hitter" } })
		local default, cleansed, hitter = units[1], units[2], units[3]
		for _, unit in { default, cleansed } do
			Battle.stun(battle, hitter, unit, 2)
			Battle.damageOverTime(battle, hitter, unit, "test", 30, "TRUE", 1, 3)
			Battle.damage(battle, hitter, unit, 100000, "TRUE", "Damage")
			expectEqual(unit.form.name, "Small", "the pool broke")
		end
		assert(battle.tick < default.stunnedUntilTick, "default: still stunned")
		assert(battle.tick >= cleansed.stunnedUntilTick, "rule off: the stun ended")
		local forms = eventsOf(battle, "Form")
		expectEqual(forms[1].cleansed, nil, "default: nothing cleansed")
		expectEqual(forms[2].cleansed, true, "rule off: the Form event says it cleansed")

		battle.tick += 20
		Battle.tickDots(battle)
		expectEqual(default.health, default.maxHealth - 30, "default: damage over time keeps ticking")
		expectEqual(cleansed.health, cleansed.maxHealth, "rule off: damage over time ended")
	end,
})

table.insert(tests, {
	name = "pool damage gives mana as if health had been lost by default; with the rule off it gives none",
	run = function()
		local types = { Default = formType(nil), NoMana = formType({ formHealthDamageGivesMana = false }) }
		types.Hitter = unitType()
		local battle, units = newBattle(types, { { "Default", "NoMana" }, { "Hitter" } })
		local default, noMana, hitter = units[1], units[2], units[3]
		for _, unit in { default, noMana } do
			Battle.damage(battle, hitter, unit, 15, "TRUE", "Damage")
		end
		near(default.mana, CombatMath.manaFromDamage(15, default.maxHealth), "default: mana from pool damage")
		expectEqual(noMana.mana, 0, "rule off: no mana")
	end,
})

table.insert(tests, {
	name = "a form's stat changes apply only while in that form",
	run = function()
		local types = { Shifter = formType(nil), Hitter = unitType() }
		local battle, units = newBattle(types, { { "Shifter" }, { "Hitter" } })
		local shifter, hitter = units[1], units[2]
		near(Battle.stat(battle, shifter, "MoveSpeed"), 1.5, "Big: +0.5 move speed")
		near(Battle.stat(battle, shifter, "AD"), 10, "Big: +10 attack damage")
		Battle.buff(battle, hitter, shifter, "AD", 5, 100, 10)
		near(Battle.stat(battle, shifter, "AD"), 30, "Big: form change and buffs add up: (0 + 5 + 10) x 2")
		Battle.damage(battle, hitter, shifter, 100000, "TRUE", "Damage")
		near(Battle.stat(battle, shifter, "MoveSpeed"), 1, "Small: base move speed")
		near(Battle.stat(battle, shifter, "AD"), 10, "Small: only the buff: (0 + 5) x 2")
	end,
})

table.insert(tests, {
	name = "a form's ability replaces the unit's own while in that form",
	run = function()
		local function hit(amount: number)
			return { { type = "DAMAGE", target = "CURRENT_TARGET", damageType = "TRUE", amount = amount } }
		end
		local own = { name = "Own", effects = hit(1) }
		local other = { name = "Other", effects = hit(7) }
		assert(Abilities.validate(own) and Abilities.validate(other), "test abilities")
		local shifter = formType(nil, { ability = other })
		shifter.ability = own
		local types = { Shifter = shifter, Hitter = unitType() }
		expectEqual(Forms.abilityNamed(shifter, "Other"), other, "Forms.abilityNamed finds a form's ability")
		expectEqual(Forms.abilityNamed(shifter, "Own"), own, "Forms.abilityNamed finds the unit's ability")

		local battle, units = newBattle(types, { { "Shifter" }, { "Hitter" } })
		local unit, hitter = units[1], units[2]
		expectEqual(unit.ability, own, "starting form has no override")
		Battle.damage(battle, hitter, unit, 100000, "TRUE", "Damage")
		expectEqual(unit.ability, other, "the second form's ability")
		unit.target = hitter
		Abilities.cast(battle, unit)
		local cast = eventsOf(battle, "Cast")[1]
		expectEqual(cast.ability, "Other", "the cast uses the form's ability")
		expectEqual(hitter.health, hitter.maxHealth - 7, "the form ability's damage")
	end,
})

table.insert(tests, {
	name = "remount (takedown trigger): once per fight, after killing an enemy board unit, with the pool at 50%",
	run = function()
		local rider = formType(nil, { trigger = { type = "TAKEDOWN", to = "Big", healthPercent = 50, maxUses = 1 } })
		local types = { Rider = rider, Plain = unitType() }
		local battle, units = newBattle(types, { { "Rider" }, { "Plain", "Plain", "Plain" } })
		local unit, first, second, third = units[1], units[2], units[3], units[4]

		Battle.damage(battle, first, unit, 100000, "TRUE", "Damage")
		expectEqual(unit.form.name, "Small", "dismounted")

		-- A summon kill is not a takedown.
		local summon = Battle.summon(battle, first, {
			health = 10,
			attackDamage = 0,
			armor = 0,
			magicResist = 0,
			attacksPerSecond = 1,
			range = 1,
			moveSpeed = 1,
			duration = 10,
		})
		assert(summon, "test setup: summon placed")
		Battle.damage(battle, unit, summon, 100000, "TRUE", "Damage")
		expectEqual(unit.form.name, "Small", "killing a summon does not remount")

		Battle.damage(battle, unit, first, 100000, "TRUE", "Damage")
		expectEqual(unit.form.name, "Big", "remounted after the takedown")
		expectEqual(unit.formHealth, math.round(SCALED_POOL * 0.5), "remounted with half the pool")
		local form = lastEvent(battle)
		expectEqual(form.kind, "Form", "the Form event follows the Death event")
		expectEqual(form.formHealth, unit.formHealth, "the Form event carries the new pool")

		Battle.damage(battle, second, unit, 100000, "TRUE", "Damage")
		expectEqual(unit.form.name, "Small", "dismounted again")
		Battle.damage(battle, unit, third, 100000, "TRUE", "Damage")
		expectEqual(unit.form.name, "Small", "no second remount")
		expectEqual(#eventsOf(battle, "Form"), 3, "dismount, remount, dismount")
	end,
})

table.insert(tests, {
	name = "a rider remount from config: FormConfig values build the same trigger the engine uses",
	run = function()
		-- The real riders with remounting switched on, built the way UnitConfig builds them.
		local mount = FormConfig.mount
		local types = table.clone(UnitConfig)
		local rider = table.clone(UnitConfig.spurshot)
		rider.forms = {
			UnitConfig.spurshot.forms[1],
			{
				name = "Dismounted",
				trigger = {
					type = "TAKEDOWN",
					to = "Mounted",
					healthPercent = mount.remountHorseHealthPercent,
					maxUses = mount.remountsPerFight,
				},
			},
		}
		assert(Forms.validate(rider.forms), "remount forms are valid")
		types.spurshot = rider
		local battle, units = newBattle(types, { { "spurshot" }, { "cinder_arc" } })
		local unit, enemy = units[1], units[2]
		local full = unit.maxFormHealth
		Battle.damage(battle, enemy, unit, 100000, "TRUE", "Damage")
		Battle.damage(battle, unit, enemy, 100000, "TRUE", "Damage")
		expectEqual(unit.form.name, "Mounted", "remounted")
		expectEqual(
			unit.formHealth,
			math.max(1, math.round(full * mount.remountHorseHealthPercent / 100)),
			"remount horse pool"
		)
	end,
})

return tests
