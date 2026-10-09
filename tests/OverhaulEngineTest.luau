-- Engine pieces added for Overhaul 1 (docs/design/overhaul-1.md), with custom unit types: hex
-- lines and cones, debuffs, area shapes, knockback, bounces, delayed hits, damage when a stun ends,
-- conditions and bonuses, the new selectors, summons that last and feed mana, recall, form
-- triggers and form splash and range, auras, instant casts, self-stuns, attack stacks and pool
-- heals. Units are moved to exact cells after the battle is created, as in AbilityTest.

local Abilities = require("../src/shared/Abilities")
local Battle = require("../src/shared/Battle")
local CombatSim = require("../src/shared/CombatSim")
local Forms = require("../src/shared/Forms")
local HexGrid = require("../src/shared/HexGrid")

local Effect = Abilities.Effect
local Selector = Abilities.Selector

local function expectEqual(actual, expected, label)
	assert(actual == expected, string.format("%s: expected %s, got %s", label, tostring(expected), tostring(actual)))
end

local function near(actual: number, expected: number, label: string)
	assert(math.abs(actual - expected) < 1e-6, string.format("%s: expected %s, got %s", label, expected, actual))
end

-- A sturdy unit that does nothing unless overridden.
local function unitType(overrides)
	local stats = {
		health = 1000,
		attackDamage = 0,
		attacksPerSecond = 1,
		range = 1,
		moveSpeed = 0.001,
		armor = 0,
		magicResist = 0,
	}
	for key, value in overrides or {} do
		stats[key] = value
	end
	return stats
end

-- Creates a battle from `layout`: a list of { unitType name, side, field column, field row }.
-- Returns the battle and its units in layout order, at exact (unscaled) health.
local function newBattle(unitTypes, layout, seed: number?)
	local boards = { {}, {} }
	for i, entry in layout do
		table.insert(boards[entry[2]], { id = tostring(i), unitType = entry[1], column = i, row = 1 })
	end
	local battle = Battle.new({
		boards = boards,
		columns = 7,
		rows = 4,
		unitTypes = unitTypes,
		ticksPerSecond = 20,
		maxTicks = 1000,
		seed = seed or 1,
		critChance = 0,
	})
	local units = {}
	for i in layout do
		for _, unit in battle.units do
			if unit.id == tostring(i) then
				units[i] = unit
			end
		end
	end
	table.clear(battle.occupied)
	for i, entry in layout do
		units[i].column, units[i].row = entry[3], entry[4]
		battle.occupied[Battle.cellKey(battle, entry[3], entry[4])] = units[i]
		units[i].maxHealth = unitTypes[entry[1]].health
		units[i].baseMaxHealth = units[i].maxHealth
		units[i].health = units[i].maxHealth
	end
	return battle, units
end

local function castWith(battle, caster, effects, options)
	local ability = { name = "Test", effects = effects }
	for key, value in options or {} do
		ability[key] = value
	end
	local ok, reason = Abilities.validate(ability)
	assert(ok, "test ability invalid: " .. tostring(reason))
	caster.ability = ability
	Abilities.cast(battle, caster)
end

local function eventsOfKind(battle, kind)
	local found = {}
	for _, event in battle.events do
		if event.kind == kind then
			table.insert(found, event)
		end
	end
	return found
end

local function damageTo(battle, unit): number
	local total = 0
	for _, event in battle.events do
		if (event.kind == "Damage" or event.kind == "Attack") and event.target == unit.index then
			total += event.damage
		end
	end
	return total
end

local function steps(battle, count: number)
	for _ = 1, count do
		CombatSim.step(battle)
	end
end

local function trueHit(target, amount, extra)
	local effect = { type = Effect.Damage, target = target, damageType = "TRUE", amount = amount }
	for key, value in extra or {} do
		effect[key] = value
	end
	return effect
end

local tests = {}

table.insert(tests, {
	name = "hex lines run through the second cell and beyond; cones cover a 60-degree wedge",
	run = function()
		local line = HexGrid.line(4, 4, 4, 6, 2)
		expectEqual(#line, 4, "two cells to the target, two beyond")
		expectEqual(line[2][1] .. "," .. line[2][2], "4,6", "the line passes through the target cell")
		for i, cell in line do
			expectEqual(HexGrid.distance(4, 4, cell[1], cell[2]), i, "line cell " .. i .. " distance")
		end
		-- (4,5) and (5,5) are the two neighbors of (4,4) on the far side, 30 degrees off the axis to (4,6).
		assert(HexGrid.inCone(4, 4, 4, 6, 4, 5, 30), "edge cell in the cone")
		assert(HexGrid.inCone(4, 4, 4, 6, 5, 5, 30), "other edge cell in the cone")
		assert(not HexGrid.inCone(4, 4, 4, 6, 3, 4, 30), "a cell to the side is outside")
		assert(not HexGrid.inCone(4, 4, 4, 6, 4, 4, 30), "the origin is outside")
	end,
})

table.insert(tests, {
	name = "debuffs: SLOW lowers attack and move speed, WEAKEN lowers damage dealt, both show as statuses",
	run = function()
		local types = { A = unitType({ moveSpeed = 1 }), B = unitType() }
		local battle, units = newBattle(types, { { "A", 1, 4, 4 }, { "B", 2, 4, 5 } })
		local a, b = units[1], units[2]
		Battle.debuff(battle, b, a, Battle.Status.Slow, 50, 2)
		near(Battle.stat(battle, a, "AttackSpeed"), 0.5, "slowed attack speed")
		near(Battle.stat(battle, a, "MoveSpeed"), 0.5, "slowed move speed")
		assert(Battle.hasStatus(battle, a, Battle.Status.Slow), "slowed status")
		Battle.debuff(battle, b, a, Battle.Status.Weaken, 40, 2)
		Battle.damage(battle, a, b, 100, "TRUE", "Damage")
		expectEqual(b.health, 1000 - 60, "weakened hit")
		battle.tick += 41
		Battle.expire(battle)
		assert(not Battle.hasStatus(battle, a, Battle.Status.Slow), "slow expired")
		near(Battle.stat(battle, a, "AttackSpeed"), 1, "attack speed after the slow")
	end,
})

table.insert(tests, {
	name = "multiplier stats: DamageTaken and MagicDamageTaken scale hits; HealPower scales heals",
	run = function()
		local types = { A = unitType(), B = unitType() }
		local battle, units = newBattle(types, { { "A", 1, 4, 4 }, { "A", 1, 3, 4 }, { "B", 2, 4, 5 } })
		local a, ally, b = units[1], units[2], units[3]
		Battle.buff(battle, a, b, "DamageTaken", 0, -50, 5)
		Battle.damage(battle, a, b, 100, "TRUE", "Damage")
		expectEqual(b.health, 950, "half damage taken")
		Battle.buff(battle, a, b, "MagicDamageTaken", 0, -50, 5)
		Battle.damage(battle, a, b, 100, "MAGIC", "Damage")
		expectEqual(b.health, 925, "magic: half of half")
		ally.health = 500
		Battle.buff(battle, a, a, "HealPower", 0, 50, 5)
		castWith(battle, a, { { type = Effect.Heal, target = Selector.LowestHpOtherAlly, amount = 100 } })
		expectEqual(ally.health, 650, "heal x1.5 HealPower")
	end,
})

table.insert(tests, {
	name = "LINE areas hit only the cells past the target with startAfterTarget; every area emits an Area event",
	run = function()
		local types = { Caster = unitType(), Dummy = unitType() }
		local line = HexGrid.line(4, 4, 4, 6, 3)
		local behind = line[3]
		local battle, units = newBattle(types, {
			{ "Caster", 1, 4, 4 },
			{ "Dummy", 2, 4, 6 }, -- the target
			{ "Dummy", 2, behind[1], behind[2] }, -- behind it, on the line
			{ "Dummy", 2, 1, 8 }, -- off the line
		})
		units[1].target = units[2]
		castWith(battle, units[1], {
			{
				type = Effect.AreaDamage,
				center = Selector.CurrentTarget,
				shape = "LINE",
				startAfterTarget = true,
				damageType = "TRUE",
				amount = 100,
			},
		})
		expectEqual(damageTo(battle, units[2]), 0, "the target itself")
		expectEqual(damageTo(battle, units[3]), 100, "the enemy behind it")
		expectEqual(damageTo(battle, units[4]), 0, "the enemy off the line")
		local area = eventsOfKind(battle, "Area")[1]
		assert(area and area.shape == "LINE" and #area.cells > 0, "an Area event with the line's cells")
		for _, event in eventsOfKind(battle, "Damage") do
			assert(event.area, "area hits are tagged")
			expectEqual(event.damageType, "TRUE", "damage events carry their type")
		end
	end,
})

table.insert(tests, {
	name = "CONE areas hit toward the target, weaker with distance, and miss the sides",
	run = function()
		local types = { Caster = unitType(), Dummy = unitType() }
		local battle, units = newBattle(types, {
			{ "Caster", 1, 4, 4 },
			{ "Dummy", 2, 4, 6 }, -- 2 away, on the axis (the target)
			{ "Dummy", 2, 4, 5 }, -- 1 away, on the cone's edge
			{ "Dummy", 2, 3, 4 }, -- 1 away, to the side
		})
		units[1].target = units[2]
		castWith(battle, units[1], {
			{
				type = Effect.AreaDamage,
				center = Selector.CurrentTarget,
				shape = "CONE",
				radius = 2,
				falloff = 50,
				damageType = "TRUE",
				amount = 100,
			},
		})
		expectEqual(damageTo(battle, units[3]), 100, "full damage 1 hex away")
		expectEqual(damageTo(battle, units[2]), 50, "half damage 2 hexes away")
		expectEqual(damageTo(battle, units[4]), 0, "outside the cone")
	end,
})

table.insert(tests, {
	name = "KNOCKBACK pushes the target one hex farther away when the hex is free",
	run = function()
		local types = { Caster = unitType(), Dummy = unitType() }
		local battle, units = newBattle(types, { { "Caster", 1, 4, 4 }, { "Dummy", 2, 4, 5 } })
		local start = { units[2].column, units[2].row }
		castWith(battle, units[1], { { type = Effect.Knockback, target = Selector.NearestEnemy } })
		expectEqual(Battle.distance(units[1], units[2]), 2, "one hex farther")
		expectEqual(HexGrid.distance(start[1], start[2], units[2].column, units[2].row), 1, "moved one hex")
		expectEqual(#eventsOfKind(battle, "Knockback"), 1, "Knockback event")

		-- Blocked: every hex one step farther away is taken.
		local layout = { { "Caster", 1, 4, 4 }, { "Dummy", 2, 4, 5 } }
		for _, cell in HexGrid.neighbors(4, 5) do
			if HexGrid.distance(4, 4, cell[1], cell[2]) == 2 then
				table.insert(layout, { "Dummy", 2, cell[1], cell[2] })
			end
		end
		local blocked, more = newBattle(types, layout)
		castWith(blocked, more[1], { { type = Effect.Knockback, target = Selector.CurrentTarget } })
		expectEqual(#eventsOfKind(blocked, "Knockback"), 0, "no knockback into an occupied hex")
	end,
})

table.insert(tests, {
	name = "BOUNCE hits the nearest other enemy, never the first target twice",
	run = function()
		local types = { Caster = unitType(), Dummy = unitType() }
		local battle, units = newBattle(types, {
			{ "Caster", 1, 4, 1 },
			{ "Dummy", 2, 4, 5 },
			{ "Dummy", 2, 4, 7 },
			{ "Dummy", 2, 1, 8 },
		})
		units[1].target = units[2]
		castWith(battle, units[1], {
			trueHit(Selector.CurrentTarget, 100),
			{ type = Effect.Bounce, target = Selector.CurrentTarget, count = 1, damageType = "TRUE", amount = 40 },
		})
		expectEqual(damageTo(battle, units[2]), 100, "first target hit once")
		expectEqual(damageTo(battle, units[3]), 40, "nearest other enemy bounced to")
		expectEqual(damageTo(battle, units[4]), 0, "one bounce only")
		expectEqual(eventsOfKind(battle, "Bounce")[1].from, units[2].index, "bounce from the first target")
	end,
})

table.insert(tests, {
	name = "delayed effects land later on the chosen target, and are dropped if the caster dies",
	run = function()
		local types = { Caster = unitType(), Dummy = unitType() }
		local battle, units = newBattle(types, { { "Caster", 1, 4, 1 }, { "Dummy", 2, 4, 8 } })
		units[1].target = units[2]
		castWith(battle, units[1], { trueHit(Selector.CurrentTarget, 100, { delay = 0.5 }) })
		expectEqual(units[2].health, 1000, "nothing at once")
		steps(battle, 9)
		expectEqual(units[2].health, 1000, "not before 0.5s")
		steps(battle, 1)
		expectEqual(units[2].health, 900, "lands at 0.5s")

		local second, more = newBattle(types, { { "Caster", 1, 4, 1 }, { "Dummy", 2, 4, 8 } })
		more[1].target = more[2]
		castWith(second, more[1], { trueHit(Selector.CurrentTarget, 100, { delay = 0.5 }) })
		Battle.damage(second, more[2], more[1], 1e6, "TRUE", "Damage")
		steps(second, 12)
		expectEqual(more[2].health, 1000, "dropped after the caster died")
	end,
})

table.insert(tests, {
	name = "AREA_STUN damageOnEnd: each stunned enemy is hit when its stun ends, and lifesteal heals",
	run = function()
		local types = { Caster = unitType(), Dummy = unitType() }
		local battle, units = newBattle(types, { { "Caster", 1, 4, 4 }, { "Dummy", 2, 4, 5 }, { "Dummy", 2, 1, 8 } })
		units[1].health = 500
		castWith(battle, units[1], {
			{
				type = Effect.AreaStun,
				center = Selector.Self,
				radius = 1,
				duration = 1,
				damageOnEnd = { damageType = "TRUE", amount = 100, healPercentOfDamage = 50 },
			},
		})
		steps(battle, 19)
		expectEqual(units[2].health, 1000, "not while stunned")
		steps(battle, 1)
		expectEqual(units[2].health, 900, "hit as the stun ends")
		expectEqual(units[3].health, 1000, "unstunned enemies are not hit")
		expectEqual(units[1].health, 550, "healed half the damage")
	end,
})

table.insert(tests, {
	name = "conditions: KILLED, ALLY_BELOW with negate, SUMMONS_ALIVE and ENEMY_HAS_CAST",
	run = function()
		local types = { Caster = unitType(), Dummy = unitType() }
		local battle, units = newBattle(types, { { "Caster", 1, 4, 4 }, { "Dummy", 2, 4, 5 } })
		units[1].health = 500
		units[2].health = 50
		local killHeal = { type = Effect.Heal, target = Selector.Self, amount = 30, condition = { type = "KILLED" } }
		castWith(battle, units[1], { trueHit(Selector.NearestEnemy, 100), killHeal })
		expectEqual(units[1].health, 530, "heals after a kill")
		local spared, more = newBattle(types, { { "Caster", 1, 4, 4 }, { "Dummy", 2, 4, 5 } })
		more[1].health = 500
		castWith(spared, more[1], { trueHit(Selector.NearestEnemy, 100), killHeal })
		expectEqual(more[1].health, 500, "no heal without a kill")

		-- Heal when an ally is low; otherwise hit. Checked once at cast start, so the heal cannot
		-- also unlock the hit.
		local aid = {
			{
				type = Effect.Heal,
				target = Selector.LowestHpAlly,
				amount = 600,
				condition = { type = "ALLY_BELOW", healthPercent = 60 },
			},
			trueHit(
				Selector.NearestEnemy,
				100,
				{ condition = { type = "ALLY_BELOW", healthPercent = 60, negate = true } }
			),
		}
		local low, lowUnits = newBattle(types, { { "Caster", 1, 4, 4 }, { "Caster", 1, 3, 4 }, { "Dummy", 2, 4, 5 } })
		lowUnits[2].health = 300
		castWith(low, lowUnits[1], aid)
		expectEqual(lowUnits[2].health, 900, "healed the low ally")
		expectEqual(lowUnits[3].health, 1000, "no hit when someone was low")
		local fine, fineUnits = newBattle(types, { { "Caster", 1, 4, 4 }, { "Caster", 1, 3, 4 }, { "Dummy", 2, 4, 5 } })
		castWith(fine, fineUnits[1], aid)
		expectEqual(fineUnits[3].health, 900, "hit when nobody was low")

		local noCast, castUnits = newBattle(types, { { "Caster", 1, 4, 4 }, { "Dummy", 2, 4, 5 } })
		local ifCast = { trueHit(Selector.NearestEnemy, 10, { condition = { type = "ENEMY_HAS_CAST" } }) }
		castWith(noCast, castUnits[1], ifCast)
		expectEqual(castUnits[2].health, 1000, "no enemy has cast")
		castUnits[2].lastCastTick = 0
		castWith(noCast, castUnits[1], ifCast)
		expectEqual(castUnits[2].health, 990, "an enemy has cast")
	end,
})

table.insert(tests, {
	name = "bonuses: missing health and target status scale damage",
	run = function()
		local types = { Caster = unitType(), Dummy = unitType() }
		-- (4,5) and (5,5) are both next to (4,4).
		local battle, units = newBattle(types, { { "Caster", 1, 4, 4 }, { "Dummy", 2, 4, 5 }, { "Dummy", 2, 5, 5 } })
		units[1].health = 500 -- half missing
		castWith(battle, units[1], {
			trueHit(Selector.NearestEnemy, 100, { bonus = { type = "MISSING_HEALTH", percent = 100 } }),
		})
		local first = eventsOfKind(battle, "Damage")[1]
		expectEqual(first.damage, 150, "+100% at full missing health, so +50% at half")

		local burning, more = newBattle(types, { { "Caster", 1, 4, 4 }, { "Dummy", 2, 4, 5 }, { "Dummy", 2, 5, 5 } })
		Battle.damageOverTime(burning, more[1], more[2], "burn", 1, "TRUE", 1, 5, Battle.Status.Burn)
		castWith(burning, more[1], {
			{
				type = Effect.AreaDamage,
				center = Selector.Self,
				radius = 1,
				damageType = "TRUE",
				amount = 100,
				bonus = { type = "TARGET_STATUS", status = "BURN", percent = 50 },
			},
		})
		expectEqual(damageTo(burning, more[2]), 150, "burning enemy takes the bonus")
		expectEqual(damageTo(burning, more[3]), 100, "other enemy does not")
	end,
})

table.insert(tests, {
	name = "selectors: lowest-health allies, attacker of the lowest ally, nearby lowest, cluster, last caster",
	run = function()
		local types = { Caster = unitType(), Dummy = unitType() }
		local battle, units = newBattle(types, {
			{ "Caster", 1, 4, 4 }, -- 1 caster
			{ "Caster", 1, 3, 4 }, -- 2 ally, 90%
			{ "Caster", 1, 5, 4 }, -- 3 ally, 30%
			{ "Caster", 1, 6, 4 }, -- 4 ally, 60%
			{ "Dummy", 2, 3, 5 }, -- 5 attacks ally 2
			{ "Dummy", 2, 5, 5 }, -- 6 attacks ally 3
			{ "Dummy", 2, 1, 8 }, -- 7 alone, far
		})
		units[2].health, units[3].health, units[4].health = 900, 300, 600
		units[5].target, units[6].target = units[2], units[3]
		castWith(battle, units[1], {
			{ type = Effect.Heal, target = Selector.LowestHpOtherAllies, count = 2, amount = 50 },
		})
		local healed = {}
		for _, event in eventsOfKind(battle, "Heal") do
			healed[event.target] = true
		end
		assert(
			healed[units[3].index] and healed[units[4].index] and not healed[units[2].index],
			"the two lowest other allies"
		)

		castWith(battle, units[1], { trueHit(Selector.AttackerOfLowestAlly, 1) })
		expectEqual(eventsOfKind(battle, "Damage")[1].target, units[6].index, "the enemy attacking the lowest ally")

		units[7].health = 100
		castWith(battle, units[1], { trueHit(Selector.LowestHpEnemyNearby, 1) }, { nearbyRange = 2 })
		local hits = eventsOfKind(battle, "Damage")
		assert(hits[#hits].target ~= units[7].index, "the far low enemy is out of range")

		castWith(battle, units[1], { trueHit(Selector.LargestCluster, 1) }, { clusterRadius = 2 })
		hits = eventsOfKind(battle, "Damage")
		assert(hits[#hits].target == units[5].index or hits[#hits].target == units[6].index, "a clustered enemy")

		castWith(battle, units[1], { trueHit(Selector.LastCasterEnemy, 1) })
		expectEqual(#eventsOfKind(battle, "Damage"), #hits, "no enemy has cast: no target")
		units[7].lastCastTick = 5
		castWith(battle, units[1], { trueHit(Selector.LastCasterEnemy, 1) })
		hits = eventsOfKind(battle, "Damage")
		expectEqual(hits[#hits].target, units[7].index, "the enemy that cast")
	end,
})

table.insert(tests, {
	name = "summons: permanent ones never expire, feed their summoner mana, refill and can be recalled",
	run = function()
		local types = { Caster = unitType({ maxMana = 100 }), Dummy = unitType() }
		local battle, units = newBattle(types, { { "Caster", 1, 4, 2 }, { "Dummy", 2, 1, 8 } })
		local summon = {
			type = Effect.Summon,
			permanent = true,
			count = 2,
			healthPercent = 10,
			attackDamagePercent = 10,
			armorPercent = 10,
			magicResistPercent = 10,
			attackSpeedPercent = 100,
			range = 1,
			moveSpeed = 1,
			manaPerHit = 5,
			refill = true,
		}
		castWith(battle, units[1], { summon })
		local made = Battle.summonsOf(battle, units[1])
		expectEqual(#made, 2, "two summons")
		expectEqual(made[1].expiresTick, nil, "no expiry")
		local before = units[1].mana
		Battle.damage(battle, made[1], units[2], 1, "TRUE", "Attack")
		expectEqual(units[1].mana, before + 5, "summoner mana from a summon hit")
		Battle.damage(battle, units[2], made[1], 1e6, "TRUE", "Damage")
		expectEqual(#Battle.summonsOf(battle, units[1]), 1, "one died")
		castWith(battle, units[1], { summon })
		expectEqual(#Battle.summonsOf(battle, units[1]), 2, "refilled to two, not three")
		castWith(battle, units[1], {
			{ type = Effect.Recall },
			trueHit(Selector.NearestEnemy, 10, { bonus = { type = "RECALLED", percent = 100 } }),
		})
		expectEqual(#Battle.summonsOf(battle, units[1]), 0, "recalled")
		local hits = eventsOfKind(battle, "Damage")
		expectEqual(hits[#hits].damage, 30, "+100% per recalled summon")
	end,
})

table.insert(tests, {
	name = "forms: ON_CAST and HEALTH_BELOW triggers, form range and attack splash",
	run = function()
		local hitAbility = { name = "Hit", effects = { trueHit(Selector.CurrentTarget, 1) } }
		local shifter = unitType({
			forms = {
				{
					name = "Calm",
					ability = { name = "Change", effects = {}, formOnly = true },
					trigger = { type = "ON_CAST" },
				},
				{ name = "Wild", ability = hitAbility, range = 2, splash = { percent = 50 } },
			},
		})
		local hurt = unitType({
			forms = {
				{ name = "Steady", trigger = { type = "HEALTH_BELOW", belowPercent = 50, maxUses = 1 } },
				{ name = "Frantic" },
			},
		})
		assert(Forms.validate(shifter.forms), "shifter forms")
		assert(Forms.validate(hurt.forms), "hurt forms")
		local types = { Shifter = shifter, Hurt = hurt, Dummy = unitType() }
		local battle, units = newBattle(types, {
			{ "Shifter", 1, 4, 4 },
			{ "Hurt", 1, 2, 2 },
			{ "Dummy", 2, 4, 5 },
			{ "Dummy", 2, 5, 5 },
		})
		local unit = units[1]
		Abilities.cast(battle, unit)
		expectEqual(unit.form.name, "Wild", "ON_CAST moved it on")
		expectEqual(Battle.range(unit), 2, "the form's range")

		Battle.damage(battle, units[3], units[2], 400, "TRUE", "Damage")
		expectEqual(units[2].form.name, "Steady", "above half")
		Battle.damage(battle, units[3], units[2], 200, "TRUE", "Damage")
		expectEqual(units[2].form.name, "Frantic", "below half")

		-- Splash: the attack on one dummy also hits the adjacent other dummy for half.
		unit.stats = table.clone(unit.stats)
		unit.stats.attackDamage = 100
		unit.target = units[3]
		unit.attackCooldown = 0
		unit.castEndsTick = 0
		CombatSim.step(battle)
		local splashed = false
		for _, event in eventsOfKind(battle, "Damage") do
			if event.splash and event.target == units[4].index then
				splashed = event.damage == 50
			end
		end
		assert(splashed, "the adjacent enemy took half the attack as splash")
	end,
})

table.insert(tests, {
	name = "auras pulse every interval and buff the unit per enemy inside",
	run = function()
		local types = {
			Crown = unitType({
				armor = 10,
				aura = {
					radius = 1,
					interval = 1,
					damageType = "TRUE",
					amount = 10,
					buffs = { { stat = "Armor", flatPerEnemy = 5 } },
				},
			}),
			Dummy = unitType(),
		}
		assert(Abilities.validateUnit(types.Crown), "valid aura")
		local battle, units = newBattle(types, { { "Crown", 1, 4, 4 }, { "Dummy", 2, 4, 5 }, { "Dummy", 2, 1, 8 } })
		steps(battle, 19)
		expectEqual(units[2].health, 1000, "no pulse before 1s")
		steps(battle, 1)
		expectEqual(units[2].health, 990, "one pulse at 1s")
		expectEqual(units[3].health, 1000, "the far enemy is outside")
		near(Battle.stat(battle, units[1], "Armor"), 15, "+5 armor for the one enemy inside")
		steps(battle, 20)
		expectEqual(units[2].health, 980, "a second pulse")
	end,
})

table.insert(tests, {
	name = "instant casts reset the attack timer; self-stuns stop the caster",
	run = function()
		local types = { Caster = unitType({ maxMana = 10 }), Dummy = unitType() }
		local battle, units = newBattle(types, { { "Caster", 1, 4, 4 }, { "Dummy", 2, 4, 5 } })
		local caster = units[1]
		caster.attackCooldown = 15
		castWith(battle, caster, { trueHit(Selector.NearestEnemy, 1) }, { castTime = 0, resetAttackTimer = true })
		expectEqual(caster.castEndsTick, battle.tick, "no cast time")
		expectEqual(caster.attackCooldown, 0, "attack ready")
		castWith(battle, caster, { trueHit(Selector.NearestEnemy, 1) }, { selfStun = 1 })
		expectEqual(caster.stunnedUntilTick, battle.tick + 20, "stunned for 1s after casting")
	end,
})

table.insert(tests, {
	name = "attack stacks build on one target, reset on a new one, and cast at full stacks",
	run = function()
		local stacker = unitType({
			attackDamage = 1,
			maxMana = 90,
			attackStacks = { max = 3, castAtMax = true },
			ability = { name = "Shot", effects = { trueHit(Selector.CurrentTarget, 1) } },
		})
		assert(Abilities.validateUnit(stacker), "valid stacks")
		local types = { Stacker = stacker, Dummy = unitType() }
		local battle, units = newBattle(types, { { "Stacker", 1, 4, 4 }, { "Dummy", 2, 4, 5 } })
		local unit = units[1]
		steps(battle, 1)
		expectEqual(unit.stacks, 1, "one stack")
		expectEqual(unit.mana, 30, "mana shows the stacks")
		steps(battle, 40)
		expectEqual(#eventsOfKind(battle, "Cast"), 0, "not cast before full stacks")
		expectEqual(unit.stacks, 3, "three stacks")
		steps(battle, 1)
		expectEqual(#eventsOfKind(battle, "Cast"), 1, "cast at full stacks")
		expectEqual(unit.stacks, 0, "stacks spent")
	end,
})

table.insert(tests, {
	name = "HEAL pool = true restores a form's health pool",
	run = function()
		local types = {
			Rider = unitType({
				forms = { { name = "On", health = 200, trigger = { type = "FORM_HEALTH_DEPLETED" } }, { name = "Off" } },
			}),
			Dummy = unitType(),
		}
		local battle, units = newBattle(types, { { "Rider", 1, 4, 4 }, { "Dummy", 2, 4, 5 } })
		local rider = units[1]
		local full = rider.formHealth
		Battle.damage(battle, units[2], rider, 100, "TRUE", "Damage")
		castWith(battle, rider, { { type = Effect.Heal, target = Selector.Self, amount = 60, pool = true } })
		expectEqual(rider.formHealth, full - 40, "pool healed by 60")
	end,
})

table.insert(tests, {
	name = "validate rejects bad Overhaul 1 data",
	run = function()
		local bad = {
			{
				name = "shape",
				effects = { { type = "AREA_DAMAGE", center = "SELF", shape = "STAR", damageType = "TRUE", amount = 1 } },
			},
			{ name = "condition", effects = { trueHit("SELF", 1, { condition = { type = "MAYBE" } }) } },
			{ name = "nearby", effects = { trueHit("LOWEST_HP_ENEMY_NEARBY", 1) } },
			{ name = "formOnly", formOnly = true, effects = { trueHit("SELF", 1) } },
			{ name = "selfStun", selfStun = 3, effects = { trueHit("SELF", 1) } },
			{
				name = "debuff",
				effects = { { type = "DEBUFF", target = "SELF", status = "SLEEP", percent = 10, duration = 1 } },
			},
			{ name = "recall", effects = { { type = "RECALL", target = "SELF" } } },
			{ name = "count", effects = { { type = "HEAL", target = "LOWEST_HP_ALLIES", amount = 1 } } },
		}
		for _, ability in bad do
			assert(not Abilities.validate(ability), ability.name .. " should be rejected")
		end
		assert(Abilities.validate({ name = "only", formOnly = true, effects = {} }), "a formOnly ability")
		assert(
			not Forms.validate({ { name = "A", trigger = { type = "HEALTH_BELOW" } }, { name = "B" } }),
			"no belowPercent"
		)
		assert(not Abilities.validateUnit({ attackStacks = { max = 0 } }), "zero max stacks")
	end,
})

return tests
