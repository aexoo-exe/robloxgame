-- Engine tests with custom unit types: effects, selectors, stacking rules, cast timing, mana and
-- crits. Units are moved to exact cells with Battle.relocate after the battle is created.

local Abilities = require("../src/shared/Abilities")
local Battle = require("../src/shared/Battle")
local CombatConfig = require("../src/shared/CombatConfig")
local CombatMath = require("../src/shared/CombatMath")
local CombatSim = require("../src/shared/CombatSim")

local Effect = Abilities.Effect
local Selector = Abilities.Selector
local DamageType = CombatMath.DamageType
local CAST_TICKS = math.round(CombatConfig.castTime * 20)

local function expectEqual(actual, expected, label)
	assert(actual == expected, string.format("%s: expected %s, got %s", label, tostring(expected), tostring(actual)))
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
-- Returns the battle and its units in layout order.
local function newBattle(unitTypes, layout, options)
	options = options or {}
	local boards = { {}, {} }
	for i, entry in layout do
		-- Start everyone in a spare cell; they are moved to their real cells below.
		table.insert(boards[entry[2]], { id = tostring(i), unitType = entry[1], column = i, row = 1 })
	end
	local battle = Battle.new({
		boards = boards,
		columns = 7,
		rows = 4,
		unitTypes = unitTypes,
		ticksPerSecond = 20,
		maxTicks = 1000,
		seed = options.seed or 1,
		critChance = options.critChance or 0,
	})
	local units = {}
	for i in layout do
		for _, unit in battle.units do
			if unit.id == tostring(i) then
				units[i] = unit
			end
		end
	end
	-- Clear every cell first so relocations cannot collide with starting cells.
	table.clear(battle.occupied)
	for i, entry in layout do
		assert(units[i], "test setup: unit " .. i .. " missing")
		units[i].column, units[i].row = entry[3], entry[4]
		battle.occupied[Battle.cellKey(battle, entry[3], entry[4])] = units[i]
		-- These engine tests work with exact health numbers, so they undo the global health multiplier
		-- (CombatConfig.globalHealthMultiplier, tested in StarTest).
		units[i].maxHealth = unitTypes[entry[1]].health
		units[i].health = units[i].maxHealth
	end
	return battle, units
end

local function castWith(battle, caster, effects, starLevel)
	caster.ability = { name = "Test", effects = effects }
	caster.starLevel = starLevel or 1
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

local tests = {}

table.insert(tests, {
	name = "cast timing: full mana casts, mana resets to 0, no attacks during the 0.75s cast time",
	run = function()
		local types = {
			Caster = unitType({
				attackDamage = 10,
				startingMana = 50,
				maxMana = 50,
				ability = {
					name = "Guard",
					effects = { { type = Effect.Shield, target = Selector.Self, amount = 10, duration = 1 } },
				},
			}),
			Dummy = unitType({ health = 100000 }),
		}
		local battle, units = newBattle(types, { { "Caster", 1, 4, 4 }, { "Dummy", 2, 4, 5 } })
		assert(Battle.distance(units[1], units[2]) == 1, "test setup: units should be adjacent")
		local result = { firstAttackTick = nil }
		for _ = 1, 40 do
			CombatSim.step(battle)
		end
		local casts = eventsOfKind(battle, "Cast")
		expectEqual(#casts, 1, "casts")
		expectEqual(casts[1].tick, 1, "cast tick")
		for _, event in eventsOfKind(battle, "Attack") do
			if event.unit == units[1].index and result.firstAttackTick == nil then
				result.firstAttackTick = event.tick
			end
		end
		expectEqual(result.firstAttackTick, 1 + CAST_TICKS, "first attack after the cast time")
		-- Mana reset to 0 at the cast; each completed attack since then gave 10.
		local attacks = 0
		for _, event in eventsOfKind(battle, "Attack") do
			if event.unit == units[1].index then
				attacks += 1
			end
		end
		expectEqual(units[1].mana, attacks * CombatConfig.manaPerAttack, "mana after casting and attacking")
	end,
})

table.insert(tests, {
	name = "mana: +10 per attack, 5 per 1% health lost capped at 10, never above max, none from shields",
	run = function()
		local types = {
			A = unitType({ maxMana = 25 }),
			B = unitType({ maxMana = 100 }),
		}
		local battle, units = newBattle(types, { { "A", 1, 4, 4 }, { "B", 2, 4, 5 } })
		local a, b = units[1], units[2]
		Battle.damage(battle, a, b, 10, DamageType.True, "Attack")
		expectEqual(a.mana, 10, "attacker mana after one attack")
		expectEqual(b.mana, 5, "1% of max health lost gives 5")
		Battle.damage(battle, a, b, 300, DamageType.True, "Attack")
		expectEqual(b.mana, 15, "30% lost is capped at 10 more")
		Battle.damage(battle, a, b, 10, DamageType.True, "Attack")
		expectEqual(a.mana, 25, "attacker mana capped at max")

		Battle.shield(battle, b, b, 100, 5)
		local before = b.mana
		Battle.damage(battle, a, b, 60, DamageType.True, "Damage")
		expectEqual(b.shield, 40, "shield absorbed the hit")
		expectEqual(b.mana, before, "no mana from damage a shield absorbed")
		expectEqual(b.health, 1000 - 320, "health untouched by the absorbed hit")
	end,
})

table.insert(tests, {
	name = "DAMAGE: magic scales with AP and uses magic resist; physical ignores AP",
	run = function()
		local types = {
			Caster = unitType({ abilityPower = 150 }),
			Target = unitType({ armor = 100, magicResist = 50 }),
		}
		local battle, units = newBattle(types, { { "Caster", 1, 4, 4 }, { "Target", 2, 4, 5 } })
		units[1].target = units[2]
		castWith(battle, units[1], {
			{ type = Effect.Damage, target = Selector.CurrentTarget, damageType = DamageType.Magic, amount = 200 },
			{ type = Effect.Damage, target = Selector.CurrentTarget, damageType = DamageType.Physical, amount = 200 },
		})
		local hits = eventsOfKind(battle, "Damage")
		expectEqual(hits[1].damage, 200, "200 magic x 150 AP vs 50 MR")
		expectEqual(hits[2].damage, 100, "200 physical (no AP) vs 100 armor")
	end,
})

table.insert(tests, {
	name = "AREA_DAMAGE hits every enemy within the radius of the center, including the center",
	run = function()
		local types = { Caster = unitType(), Dummy = unitType() }
		local battle, units = newBattle(types, {
			{ "Caster", 1, 4, 4 },
			{ "Dummy", 2, 4, 5 }, -- center
			{ "Dummy", 2, 4, 6 }, -- 1 from center
			{ "Dummy", 2, 4, 7 }, -- 2 from center
		})
		assert(Battle.distance(units[2], units[3]) == 1, "test setup: second dummy 1 from center")
		assert(Battle.distance(units[2], units[4]) == 2, "test setup: third dummy 2 from center")
		units[1].target = units[2]
		castWith(battle, units[1], {
			{
				type = Effect.AreaDamage,
				center = Selector.CurrentTarget,
				radius = 1,
				damageType = DamageType.True,
				amount = 100,
			},
		})
		local hit = {}
		for _, event in eventsOfKind(battle, "Damage") do
			hit[event.target] = true
		end
		assert(hit[units[2].index] and hit[units[3].index], "center and adjacent enemy should be hit")
		assert(not hit[units[4].index], "enemy 2 hexes away should not be hit")
		assert(not hit[units[1].index], "caster should not be hit")
	end,
})

table.insert(tests, {
	name = "HEAL scales with AP and caps at max health",
	run = function()
		local types = { Healer = unitType({ abilityPower = 200 }), Enemy = unitType() }
		local battle, units = newBattle(types, { { "Healer", 1, 4, 4 }, { "Healer", 1, 3, 4 }, { "Enemy", 2, 4, 6 } })
		units[2].health = 600
		castWith(battle, units[1], { { type = Effect.Heal, target = Selector.LowestHpAlly, amount = 100 } })
		expectEqual(units[2].health, 800, "100 heal at 200 AP")
		castWith(battle, units[1], { { type = Effect.Heal, target = Selector.LowestHpAlly, amount = 500 } })
		expectEqual(units[2].health, 1000, "capped at max health")
		local heals = eventsOfKind(battle, "Heal")
		expectEqual(heals[2].amount, 200, "reported heal is what was restored")
	end,
})

table.insert(tests, {
	name = "SHIELD: absorbs before health, scales with AP, keeps the larger shield, expires",
	run = function()
		local types = { Caster = unitType({ abilityPower = 150 }), Enemy = unitType() }
		local battle, units = newBattle(types, { { "Caster", 1, 4, 4 }, { "Enemy", 2, 4, 5 } })
		local caster = units[1]
		castWith(battle, caster, { { type = Effect.Shield, target = Selector.Self, amount = 200, duration = 5 } })
		expectEqual(caster.shield, 300, "200 shield at 150 AP")
		Battle.shield(battle, caster, caster, 250, 5)
		expectEqual(caster.shield, 300, "a smaller shield does not replace a larger one")
		Battle.shield(battle, caster, caster, 400, 2)
		expectEqual(caster.shield, 400, "a larger shield replaces the smaller one")
		Battle.damage(battle, units[2], caster, 150, DamageType.True, "Damage")
		expectEqual(caster.shield, 250, "damage consumed shield first")
		expectEqual(caster.health, 1000, "health untouched while the shield lasts")
		battle.tick += 40
		Battle.expire(battle)
		expectEqual(caster.shield, 0, "shield expired after its duration")
		expectEqual(#eventsOfKind(battle, "ShieldEnd"), 1, "expiry event")
	end,
})

table.insert(tests, {
	name = "STUN: the target cannot act for the duration but still gains mana",
	run = function()
		local types = {
			Stunner = unitType(), -- no mana, so it casts only when the test says so
			Hitter = unitType({ attackDamage = 5, maxMana = 100 }),
		}
		local battle, units = newBattle(types, { { "Stunner", 1, 4, 4 }, { "Hitter", 2, 4, 5 } })
		local hitter = units[2]
		units[1].target = hitter
		castWith(battle, units[1], { { type = Effect.Stun, target = Selector.CurrentTarget, duration = 1 } })
		local stunEndsTick = hitter.stunnedUntilTick
		expectEqual(stunEndsTick, 20, "1 second stun")
		local manaBefore = hitter.mana
		Battle.damage(battle, units[1], hitter, 20, DamageType.True, "Damage")
		assert(hitter.mana > manaBefore, "stunned unit should still gain mana")
		for _ = 1, 40 do
			CombatSim.step(battle)
		end
		local attackTicks = {}
		for _, event in eventsOfKind(battle, "Attack") do
			if event.unit == hitter.index then
				table.insert(attackTicks, event.tick)
			end
		end
		assert(#attackTicks > 0, "the hitter should attack after the stun")
		assert(attackTicks[1] >= stunEndsTick, "attacked while stunned at tick " .. attackTicks[1])
	end,
})

table.insert(tests, {
	name = "BUFF: percent and flat changes, same source refreshes, different sources stack, expiry",
	run = function()
		local types = { A = unitType({ armor = 20 }), B = unitType() }
		local battle, units = newBattle(types, { { "A", 1, 4, 4 }, { "A", 1, 3, 4 }, { "B", 2, 4, 6 } })
		local a, other = units[1], units[2]
		Battle.buff(battle, a, a, "AttackSpeed", 0, 100, 4)
		expectEqual(Battle.stat(battle, a, "AttackSpeed"), 2, "+100% attack speed")
		Battle.buff(battle, a, a, "AttackSpeed", 0, 100, 4)
		expectEqual(Battle.stat(battle, a, "AttackSpeed"), 2, "same source refreshes, not stacks")
		Battle.buff(battle, other, a, "AttackSpeed", 0, 50, 4)
		expectEqual(Battle.stat(battle, a, "AttackSpeed"), 2.5, "different sources stack")
		Battle.buff(battle, a, a, "Armor", 30, 0, 6)
		expectEqual(Battle.stat(battle, a, "Armor"), 50, "+30 flat armor")
		Battle.damage(battle, units[3], a, 150, DamageType.Physical, "Damage")
		expectEqual(a.health, 900, "150 physical vs 50 armor")
		battle.tick += 130 -- past both the 4s and 6s buffs
		Battle.expire(battle)
		expectEqual(Battle.stat(battle, a, "AttackSpeed"), 1, "attack speed after expiry")
		expectEqual(Battle.stat(battle, a, "Armor"), 20, "armor after expiry")
	end,
})

table.insert(tests, {
	name = "BUFF on attack speed shortens the attack interval in combat",
	run = function()
		local types = {
			Fast = unitType({
				attackDamage = 1,
				-- Full mana to cast once at the start, and a pool too large to refill during the test.
				startingMana = 1000,
				maxMana = 1000,
				ability = {
					name = "Haste",
					effects = {
						{
							type = Effect.Buff,
							target = Selector.Self,
							stat = "AttackSpeed",
							percent = 100,
							duration = 10,
						},
					},
				},
			}),
			Dummy = unitType({ health = 100000 }),
		}
		local battle, units = newBattle(types, { { "Fast", 1, 4, 4 }, { "Dummy", 2, 4, 5 } })
		for _ = 1, 80 do
			CombatSim.step(battle)
		end
		local ticks = {}
		for _, event in eventsOfKind(battle, "Attack") do
			if event.unit == units[1].index then
				table.insert(ticks, event.tick)
			end
		end
		assert(#ticks >= 3, "expected several attacks")
		expectEqual(ticks[2] - ticks[1], 10, "2 attacks per second is a 10-tick interval")
	end,
})

table.insert(tests, {
	name = "DASH: offensive lands next to the target, falls back to getting closer, defensive retreats",
	run = function()
		local types = { Dasher = unitType(), Enemy = unitType() }
		local function dash(distance, mode, casterCell, enemyCell)
			local battle, units = newBattle(
				types,
				{ { "Dasher", 1, casterCell[1], casterCell[2] }, { "Enemy", 2, enemyCell[1], enemyCell[2] } }
			)
			units[1].target = units[2]
			local start = { units[1].column, units[1].row }
			local before = Battle.distance(units[1], units[2])
			castWith(battle, units[1], {
				{ type = Effect.Dash, target = Selector.CurrentTarget, distance = distance, mode = mode },
			})
			local moved = math.abs(units[1].column - start[1]) + math.abs(units[1].row - start[2]) > 0
			return before, Battle.distance(units[1], units[2]), moved, battle
		end

		local before, after = dash(3, nil, { 4, 1 }, { 4, 5 })
		expectEqual(before, 4, "test setup distance")
		expectEqual(after, 1, "offensive dash lands adjacent")

		before, after = dash(1, nil, { 4, 1 }, { 4, 5 })
		expectEqual(after, before - 1, "out of reach: moves 1 hex closer")

		local _, stayed, moved = dash(2, nil, { 4, 4 }, { 4, 5 })
		assert(not moved and stayed == 1, "already adjacent: no dash")

		before, after = dash(2, Abilities.DashMode.Defensive, { 4, 4 }, { 4, 5 })
		assert(after > before, "defensive dash should increase distance from the enemy")
	end,
})

table.insert(tests, {
	name = "selectors: SELF, CURRENT_TARGET, LOWEST_HP_ALLY, NEAREST, FARTHEST, HIGHEST_AD",
	run = function()
		local types = {
			Caster = unitType(),
			Low = unitType({ attackDamage = 10 }),
			High = unitType({ attackDamage = 50 }),
			Mid = unitType({ attackDamage = 20 }),
		}
		local function targetOf(selector, prepare)
			local battle, units = newBattle(types, {
				{ "Caster", 1, 4, 4 },
				{ "Caster", 1, 3, 4 }, -- ally
				{ "Low", 2, 4, 5 }, -- nearest enemy
				{ "High", 2, 4, 6 }, -- highest AD
				{ "Mid", 2, 4, 8 }, -- farthest enemy
			})
			if prepare then
				prepare(units)
			end
			castWith(
				battle,
				units[1],
				{ { type = Effect.Damage, target = selector, damageType = DamageType.True, amount = 1 } }
			)
			local hit = eventsOfKind(battle, "Damage")[1]
			for i, unit in units do
				if unit.index == hit.target then
					return i
				end
			end
			return nil
		end

		expectEqual(targetOf(Selector.Self), 1, "SELF")
		expectEqual(targetOf(Selector.NearestEnemy), 3, "NEAREST_ENEMY")
		expectEqual(targetOf(Selector.FarthestEnemy), 5, "FARTHEST_ENEMY")
		expectEqual(targetOf(Selector.HighestAdEnemy), 4, "HIGHEST_AD_ENEMY")
		expectEqual(targetOf(Selector.CurrentTarget), 3, "CURRENT_TARGET without a target picks the nearest")
		expectEqual(
			targetOf(Selector.CurrentTarget, function(units)
				units[1].target = units[5]
			end),
			5,
			"CURRENT_TARGET keeps the caster's target"
		)
		expectEqual(
			targetOf(Selector.LowestHpAlly, function(units)
				units[2].health = 500
			end),
			2,
			"LOWEST_HP_ALLY picks the lowest health percentage"
		)
		expectEqual(
			targetOf(Selector.LowestHpAlly, function(units)
				units[1].health = 300
			end),
			1,
			"LOWEST_HP_ALLY can pick the caster"
		)
	end,
})

table.insert(tests, {
	name = "a selector is resolved once per cast, so effects naming it share one target",
	run = function()
		local types = { Caster = unitType(), Dummy = unitType() }
		for seed = 1, 20 do
			-- Two enemies tie for farthest, so the choice is random; both effects must agree.
			local battle, units = newBattle(types, {
				{ "Caster", 1, 4, 4 },
				{ "Dummy", 2, 3, 8 },
				{ "Dummy", 2, 5, 8 },
			}, { seed = seed })
			castWith(battle, units[1], {
				{ type = Effect.Damage, target = Selector.FarthestEnemy, damageType = DamageType.True, amount = 1 },
				{ type = Effect.Stun, target = Selector.FarthestEnemy, duration = 1 },
			})
			local damaged = eventsOfKind(battle, "Damage")[1].target
			local stunned = eventsOfKind(battle, "Stun")[1].target
			expectEqual(stunned, damaged, "stun target (seed " .. seed .. ")")
		end
	end,
})

table.insert(tests, {
	name = "crits: 140% raw damage, flagged on the event, rolled per attack from the seed",
	run = function()
		local types = { Hitter = unitType({ attackDamage = 50 }), Dummy = unitType({ health = 1000000 }) }
		local function attacks(critChance, seed)
			local battle = newBattle(types, { { "Hitter", 1, 4, 4 }, { "Dummy", 2, 4, 5 } }, {
				critChance = critChance,
				seed = seed,
			})
			for _ = 1, 400 * 20 do
				CombatSim.step(battle)
			end
			local list = {}
			for _, event in eventsOfKind(battle, "Attack") do
				if event.damage > 0 then
					table.insert(list, event)
				end
			end
			return list
		end
		for _, event in attacks(1, 1) do
			assert(event.crit and event.damage == 70, "a crit should deal 70")
		end
		for _, event in attacks(0, 1) do
			assert(not event.crit and event.damage == 50, "no crits at 0% chance")
		end
		local crits, total = 0, 0
		for _, event in attacks(0.25, 3) do
			total += 1
			if event.crit then
				crits += 1
			end
		end
		local rate = crits / total
		assert(rate > 0.2 and rate < 0.3, string.format("crit rate %.3f should be near 0.25", rate))
	end,
})

table.insert(tests, {
	name = "validate rejects unknown effects, selectors, stats and missing star values",
	run = function()
		local good =
			{ name = "Ok", effects = { { type = Effect.Stun, target = Selector.Self, duration = { 1, 1.5, 2 } } } }
		assert(Abilities.validate(good), "a valid ability was rejected")
		local bad = {
			{ name = "A", effects = { { type = "LIFESTEAL", target = Selector.Self } } },
			{ name = "B", effects = { { type = Effect.Stun, target = "RANDOM_ENEMY", duration = 1 } } },
			{
				name = "C",
				effects = { { type = Effect.Buff, target = Selector.Self, stat = "Crit", percent = 10, duration = 1 } },
			},
			{ name = "D", effects = { { type = Effect.Stun, target = Selector.Self, duration = { 1, 2 } } } },
			{ name = "E", effects = {} },
			-- Stuns longer than CombatConfig.maxStunSeconds (2.0s) fail validation.
			{ name = "F", effects = { { type = Effect.Stun, target = Selector.Self, duration = { 1, 2, 2.5 } } } },
		}
		for _, ability in bad do
			assert(not Abilities.validate(ability), ability.name .. " should be rejected")
		end
	end,
})

return tests
