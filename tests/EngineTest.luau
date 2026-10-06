-- Engine v2 building blocks (docs/design/revamp-structure.md): AREA_STUN, SUMMON, PULL,
-- DAMAGE_OVER_TIME, COPY, the ALL_ALLIES and LOWEST_HP_OTHER_ALLY selectors, stacking buffs and
-- max health bonuses. All abilities here are test-only data on test-only unit types.

local Abilities = require("../src/shared/Abilities")
local Battle = require("../src/shared/Battle")
local CombatConfig = require("../src/shared/CombatConfig")
local CombatSim = require("../src/shared/CombatSim")
local HexGrid = require("../src/shared/HexGrid")

local function expectEqual(actual, expected, label)
	assert(actual == expected, string.format("%s: expected %s, got %s", label, tostring(expected), tostring(actual)))
end

local function near(actual: number, expected: number, label: string)
	assert(math.abs(actual - expected) < 1e-6, string.format("%s: expected %s, got %s", label, expected, actual))
end

-- A sturdy test unit type that does nothing unless overridden.
local function unitType(overrides)
	local stats = {
		cost = 1,
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

local DEFAULT_TYPES = {
	Plain = unitType(),
	Hitter = unitType({ attackDamage = 100 }),
	Strong = unitType({ attackDamage = 200 }),
}

-- Creates a battle from `layout`: a list of { unit type name, side, field column, field row }, using
-- `unitTypes` (DEFAULT_TYPES if nil). Health is reset to the unit type's listed value so numbers are
-- exact (the global health multiplier is tested elsewhere). Returns the battle and its units in
-- layout order.
local function newBattle(layout, unitTypes, seed: number?)
	unitTypes = unitTypes or DEFAULT_TYPES
	local boards = { {}, {} }
	for i, entry in layout do
		table.insert(boards[entry[2]], { id = tostring(i), unitType = entry[1], column = i % 7 + 1, row = 1 })
	end
	local battle = Battle.new({
		boards = boards,
		columns = 7,
		rows = 4,
		unitTypes = unitTypes,
		ticksPerSecond = 20,
		maxTicks = 2000,
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
		local unit = units[i]
		unit.column, unit.row = entry[3], entry[4]
		battle.occupied[Battle.cellKey(battle, entry[3], entry[4])] = unit
		unit.maxHealth = unitTypes[entry[1]].health
		unit.baseMaxHealth = unit.maxHealth
		unit.health = unit.maxHealth
	end
	return battle, units
end

local function castWith(battle, caster, effects, starLevel: number?)
	caster.ability = { name = "Test", effects = effects }
	caster.starLevel = starLevel or 1
	local ok, reason = Abilities.validate(caster.ability)
	assert(ok, "test ability invalid: " .. tostring(reason))
	Abilities.cast(battle, caster)
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

local function steps(battle, count: number)
	for _ = 1, count do
		CombatSim.step(battle)
	end
end

local tests = {}

-- AREA_STUN ------------------------------------------------------------------------------------

table.insert(tests, {
	name = "AREA_STUN stuns every living enemy within the radius when it resolves, and no one else",
	run = function()
		local around = HexGrid.neighbors(4, 4) -- (5,4) (5,3) (4,3) (3,4) (4,5) (5,5)
		local battle, units = newBattle({
			{ "Plain", 1, 4, 4 }, -- caster
			{ "Plain", 1, around[3][1], around[3][2] }, -- ally next to the center
			{ "Plain", 2, around[5][1], around[5][2] }, -- enemy, distance 1
			{ "Plain", 2, around[6][1], around[6][2] }, -- enemy, distance 1
			{ "Plain", 2, 4, 7 }, -- enemy, distance 3
		})
		castWith(battle, units[1], {
			{ type = "AREA_STUN", center = "SELF", radius = 1, duration = { 1.5, 1.5, 1.5 } },
		})
		local stunned = {}
		for _, event in eventsOf(battle, "Stun") do
			stunned[event.target] = true
		end
		assert(stunned[units[3].index] and stunned[units[4].index], "enemies in the radius were not stunned")
		assert(not stunned[units[2].index], "an ally was stunned")
		assert(not stunned[units[5].index], "an enemy outside the radius was stunned")
		local pulse = eventsOf(battle, "AreaStun")[1]
		assert(pulse and pulse.column == 4 and pulse.row == 4 and pulse.radius == 1, "no AreaStun event at the center")
		expectEqual(units[3].stunnedUntilTick, 30, "stun end (1.5s at 20 ticks per second)")

		-- An enemy that walks in afterwards is not affected.
		Battle.relocate(battle, units[5], 5, 4)
		expectEqual(units[5].stunnedUntilTick, 0, "a later entrant was stunned")
	end,
})

table.insert(tests, {
	name = "stun durations do not add: the later end wins",
	run = function()
		local battle, units = newBattle({ { "Plain", 1, 4, 4 }, { "Plain", 2, 4, 5 } })
		Battle.stun(battle, units[1], units[2], 2)
		castWith(battle, units[1], { { type = "AREA_STUN", center = "SELF", radius = 1, duration = 1 } })
		expectEqual(units[2].stunnedUntilTick, 40, "a shorter stun must not extend or add")
		battle.tick = 30
		castWith(battle, units[1], { { type = "STUN", target = "NEAREST_ENEMY", duration = 1 } })
		expectEqual(units[2].stunnedUntilTick, 50, "a stun ending later replaces the end")
	end,
})

table.insert(tests, {
	name = "validation: stuns and area stuns over 2s fail, area stun radius must be 1 or 2",
	run = function()
		expectEqual(CombatConfig.maxStunSeconds, 2, "stun limit")
		local function valid(effect)
			return (Abilities.validate({ name = "T", effects = { effect } }))
		end
		assert(valid({ type = "STUN", target = "NEAREST_ENEMY", duration = 2 }), "2.0s stun should be valid")
		assert(not valid({ type = "STUN", target = "NEAREST_ENEMY", duration = 2.01 }), "2.01s stun accepted")
		assert(
			valid({ type = "AREA_STUN", center = "SELF", radius = 2, duration = { 1, 1.5, 2 } }),
			"radius 2 rejected"
		)
		assert(
			not valid({ type = "AREA_STUN", center = "SELF", radius = 1, duration = { 1, 2, 2.5 } }),
			"2.5s area stun accepted"
		)
		assert(not valid({ type = "AREA_STUN", center = "SELF", radius = 3, duration = 1 }), "radius 3 accepted")
	end,
})

-- SUMMON ---------------------------------------------------------------------------------------

local SUMMON = {
	type = "SUMMON",
	count = { 2, 2, 3 },
	duration = { 8, 9, 10 },
	healthPercent = { 30, 35, 40 },
	attackDamagePercent = { 50, 55, 60 },
	armorPercent = 50,
	magicResistPercent = 50,
	attackSpeedPercent = 90,
	range = 1,
	moveSpeed = 1.1,
}

table.insert(tests, {
	name = "SUMMON places summons on the nearest free cells with stats taken from the caster",
	run = function()
		local types = { Caster = unitType({ attackDamage = 80, armor = 40, magicResist = 20, attacksPerSecond = 0.8 }) }
		local battle, units = newBattle({ { "Caster", 1, 4, 4 }, { "Caster", 1, 4, 3 } }, types)
		local caster = units[1]
		castWith(battle, caster, { SUMMON }, 1)
		local summons = eventsOf(battle, "Summon")
		expectEqual(#summons, 2, "summons made")
		for _, event in summons do
			local summon = battle.units[event.summon]
			assert(summon.summoned and summon.summoner == caster, "not marked as a summon of the caster")
			expectEqual(HexGrid.distance(4, 4, summon.column, summon.row), 1, "summon placed next to the caster")
			expectEqual(summon.maxHealth, 300, "30% of 1000 health")
			near(summon.stats.attackDamage, 40, "50% of 80 AD")
			near(summon.stats.armor, 20, "50% of 40 armor")
			near(summon.stats.magicResist, 10, "50% of 20 MR")
			near(summon.stats.attacksPerSecond, 0.72, "90% of 0.8 attack speed")
			expectEqual(summon.stats.range, 1, "range")
			expectEqual(summon.maxMana, nil, "summons never gain mana")
			expectEqual(summon.ability, nil, "summons never cast")
			expectEqual(summon.expiresTick, 160, "8 seconds")
		end
		-- Nearest free cells, ties in field order (row, then column): (4,3) holds the ally, so the
		-- first is (5,3), then (3,4).
		local first = battle.units[summons[1].summon]
		local second = battle.units[summons[2].summon]
		expectEqual(first.column .. "," .. first.row, "5,3", "first summon cell")
		expectEqual(second.column .. "," .. second.row, "3,4", "second summon cell")
		-- 3-star makes three.
		local battle3, units3 = newBattle({ { "Caster", 1, 4, 4 } }, types)
		castWith(battle3, units3[1], { SUMMON }, 3)
		expectEqual(#eventsOf(battle3, "Summon"), 3, "3-star summon count")
	end,
})

table.insert(tests, {
	name = "SUMMON respects the cap of 12 living entities per side and skips summons it cannot place",
	run = function()
		local layout = {}
		for i = 1, 11 do
			table.insert(layout, { "Plain", 1, (i - 1) % 7 + 1, (i - 1) // 7 + 1 })
		end
		local battle, units = newBattle(layout)
		castWith(battle, units[1], { SUMMON }, 3)
		expectEqual(#eventsOf(battle, "Summon"), 1, "only one summon fits under the cap of 12")
		expectEqual(Battle.livingCount(battle, 1), 12, "living entities on side 1")

		-- With every cell taken, nothing is placed and nothing errors.
		local full, fullUnits = newBattle({ { "Plain", 1, 4, 4 } })
		local blocker = { dead = false }
		for row = 1, full.fieldRows do
			for column = 1, full.columns do
				if not (column == 4 and row == 4) then
					full.occupied[Battle.cellKey(full, column, row)] = blocker
				end
			end
		end
		castWith(full, fullUnits[1], { SUMMON }, 1)
		expectEqual(#eventsOf(full, "Summon"), 0, "summons with no free cell")
	end,
})

table.insert(tests, {
	name = "summons expire, never count as survivors or timeout health, and do not keep a side alive",
	run = function()
		local types = { Caster = unitType({ attackDamage = 0 }), Wall = unitType({ health = 100000 }) }
		local battle, units = newBattle({ { "Caster", 1, 1, 1 }, { "Wall", 2, 7, 8 } }, types)
		castWith(battle, units[1], { SUMMON }, 1)
		local summon = battle.units[eventsOf(battle, "Summon")[1].summon]
		battle.tick = summon.expiresTick - 1
		Battle.expire(battle)
		assert(not summon.dead, "summon expired early")
		battle.tick = summon.expiresTick
		Battle.expire(battle)
		assert(summon.dead, "summon did not expire")
		assert(#eventsOf(battle, "SummonEnd") >= 1, "no SummonEnd event")
		assert(Battle.isFree(battle, summon.column, summon.row), "expired summon kept its cell")

		-- A side whose only living units are summons has lost.
		local result = CombatSim.run({
			boards = { { { id = "a", unitType = "Caster", column = 1, row = 1 } }, {} },
			columns = 7,
			rows = 4,
			unitTypes = types,
			ticksPerSecond = 20,
			maxTicks = 10,
			seed = 1,
		})
		expectEqual(result.survivors[1], 1, "survivors with no fight")

		-- Summons are left out of survivors: kill the board unit, leave its summons alive.
		local fight, fightUnits = newBattle({ { "Caster", 1, 1, 1 }, { "Wall", 2, 7, 8 } }, types)
		castWith(fight, fightUnits[1], { SUMMON }, 1)
		Battle.damage(fight, fightUnits[2], fightUnits[1], 1e9, "TRUE", "Damage")
		local summonsAlive = 0
		for _, unit in fight.units do
			if unit.summoned and not unit.dead then
				summonsAlive += 1
			end
		end
		expectEqual(summonsAlive, 2, "summons outlive their summoner")
		CombatSim.step(fight)
		local living = 0
		for _, unit in fight.units do
			if unit.side == 1 and not unit.dead and not unit.summoned then
				living += 1
			end
		end
		expectEqual(living, 0, "test setup: side 1 has no board units left")
	end,
})

table.insert(tests, {
	name = "a fight ends when a side has only summons left, and summons count for no survivors",
	run = function()
		-- Side 1: a summoner that casts at once. Side 2: a strong hitter right next to it.
		local types = {
			Summoner = unitType({ health = 2000, maxMana = 1, startingMana = 1 }),
			Killer = unitType({ attackDamage = 400, range = 8 }),
		}
		types.Summoner.ability = { name = "Pack", effects = { SUMMON } }
		local result = CombatSim.run({
			boards = {
				{ { id = "s", unitType = "Summoner", column = 4, row = 4 } },
				{ { id = "k", unitType = "Killer", column = 4, row = 4 } },
			},
			columns = 7,
			rows = 4,
			unitTypes = types,
			ticksPerSecond = 20,
			maxTicks = 1000,
			seed = 3,
		})
		assert(#eventsOf({ events = result.events }, "Summon") > 0, "test setup: no summons were made")
		expectEqual(result.winner, 2, "side 1 lost once its board unit died")
		expectEqual(result.survivors[1], 0, "summons are not survivors")
		assert(result.endTick < 1000, "the fight should end when the summoner dies")
	end,
})

-- PULL -----------------------------------------------------------------------------------------

table.insert(tests, {
	name = "PULL moves the enemy next to the caster, nearest its old cell, and makes it the target",
	run = function()
		local battle, units = newBattle({ { "Plain", 1, 4, 4 }, { "Plain", 2, 4, 8 }, { "Plain", 2, 4, 5 } })
		local caster, far = units[1], units[2]
		caster.target = units[3]
		-- Selectors resolve once per cast, so the damage names the same selector as the pull.
		castWith(battle, caster, {
			{ type = "PULL", target = "FARTHEST_ENEMY" },
			{ type = "DAMAGE", target = "FARTHEST_ENEMY", damageType = "TRUE", amount = 100 },
		})
		expectEqual(HexGrid.distance(4, 4, far.column, far.row), 1, "pulled next to the caster")
		-- Free cells next to (4,4): the one nearest (4,8) is (5,5)... compute the expected one.
		local best, bestDistance = nil, math.huge
		for _, cell in HexGrid.neighbors(4, 4) do
			if not (cell[1] == 4 and cell[2] == 5) then
				local distance = HexGrid.distance(4, 8, cell[1], cell[2])
				if distance < bestDistance then
					best, bestDistance = cell, distance
				end
			end
		end
		local pull = eventsOf(battle, "Pull")[1]
		assert(pull and pull.target == far.index, "no Pull event")
		assert(HexGrid.distance(best[1], best[2], 4, 8) == HexGrid.distance(pull.column, pull.row, 4, 8), "not nearest")
		assert(caster.target == far, "the pulled enemy should be the current target")
		local damage = eventsOf(battle, "Damage")[1]
		expectEqual(damage.target, far.index, "the following effect hit the pulled enemy")
		-- From the next cast on, CURRENT_TARGET is the pulled enemy.
		castWith(battle, caster, { { type = "STUN", target = "CURRENT_TARGET", duration = 1 } })
		expectEqual(eventsOf(battle, "Stun")[1].target, far.index, "the next cast's CURRENT_TARGET")
	end,
})

table.insert(tests, {
	name = "a PULL that cannot move still makes later effects resolve on the selected enemy",
	run = function()
		local layout = { { "Plain", 1, 4, 4 }, { "Plain", 2, 4, 8 } }
		for _, cell in HexGrid.neighbors(4, 4) do
			table.insert(layout, { "Plain", 1, cell[1], cell[2] })
		end
		local battle, units = newBattle(layout)
		local caster, far = units[1], units[2]
		castWith(battle, caster, {
			{ type = "PULL", target = "FARTHEST_ENEMY" },
			{ type = "DAMAGE", target = "FARTHEST_ENEMY", damageType = "TRUE", amount = 100 },
			{ type = "STUN", target = "FARTHEST_ENEMY", duration = 1 },
		})
		expectEqual(#eventsOf(battle, "Pull"), 0, "nothing should move")
		expectEqual(far.column .. "," .. far.row, "4,8", "the enemy stayed put")
		expectEqual(eventsOf(battle, "Damage")[1].target, far.index, "the damage still resolved")
		expectEqual(eventsOf(battle, "Stun")[1].target, far.index, "the stun still resolved")
		assert(caster.target == far, "the failed pull still set the current target")
	end,
})

-- DAMAGE_OVER_TIME -----------------------------------------------------------------------------

table.insert(tests, {
	name = "DAMAGE_OVER_TIME ticks after one interval with normal mitigation, for its duration",
	run = function()
		local types = { Plain = unitType(), Tough = unitType({ magicResist = 100 }) }
		local battle, units = newBattle({ { "Plain", 1, 4, 4 }, { "Tough", 2, 4, 8 } }, types)
		castWith(battle, units[1], {
			{
				type = "DAMAGE_OVER_TIME",
				target = "NEAREST_ENEMY",
				damageType = "MAGIC",
				amount = 40,
				interval = 1,
				duration = 4,
			},
		})
		local ticks = {}
		for _ = 1, 120 do
			CombatSim.step(battle)
		end
		for _, event in eventsOf(battle, "Damage") do
			if event.dot then
				table.insert(ticks, event)
			end
		end
		expectEqual(#ticks, 4, "4 ticks over 4 seconds")
		expectEqual(ticks[1].tick, 20, "first tick one interval after the cast")
		expectEqual(ticks[4].tick, 80, "last tick at the end of the duration")
		expectEqual(ticks[1].damage, 20, "40 magic vs 100 MR = 20")
		expectEqual(ticks[1].damageType, "MAGIC", "tick damage type")
	end,
})

table.insert(tests, {
	name = "DAMAGE_OVER_TIME gives the victim at most 10 mana per application",
	run = function()
		local types = { Plain = unitType(), Victim = unitType({ health = 100, maxMana = 1000 }) }
		local battle, units = newBattle({ { "Plain", 1, 4, 4 }, { "Victim", 2, 4, 8 } }, types)
		units[2].health = 100000 -- lots of health, but mana is computed from the 100 max health
		castWith(battle, units[1], {
			{
				type = "DAMAGE_OVER_TIME",
				target = "NEAREST_ENEMY",
				damageType = "TRUE",
				amount = 10,
				interval = 0.5,
				duration = 4,
			},
		})
		steps(battle, 100)
		-- Each tick is 10% of max health (50 mana uncapped); the whole application gives 10.
		expectEqual(units[2].mana, CombatConfig.dotManaCap, "mana gained over the whole application")
	end,
})

table.insert(tests, {
	name = "DAMAGE_OVER_TIME from different casters stacks; the same caster and ability refreshes",
	run = function()
		local battle, units = newBattle({ { "Plain", 1, 4, 4 }, { "Plain", 1, 3, 4 }, { "Plain", 2, 4, 8 } })
		local victim = units[3]
		local dot = function(amount)
			return {
				{
					type = "DAMAGE_OVER_TIME",
					target = "NEAREST_ENEMY",
					damageType = "TRUE",
					amount = amount,
					interval = 1,
					duration = 2,
				},
			}
		end
		castWith(battle, units[1], dot(10))
		castWith(battle, units[2], dot(10))
		expectEqual(#battle.dots, 2, "two casters stack")

		-- Same caster and ability, 1 second in: refreshes the end, keeps the stronger tick (30 > 10).
		steps(battle, 20) -- tick 20: first ticks of both
		castWith(battle, units[1], dot(30))
		expectEqual(#battle.dots, 2, "a re-application refreshes instead of adding")
		local mine
		for _, each in battle.dots do
			if each.source == units[1] then
				mine = each
			end
		end
		expectEqual(mine.amount, 30, "the stronger tick is kept")
		expectEqual(mine.endTick, 20 + 40, "duration restarted from the refresh")
		castWith(battle, units[1], dot(5))
		expectEqual(mine.amount, 30, "a weaker re-application does not lower the tick")
		local _ = victim
	end,
})

table.insert(tests, {
	name = "DAMAGE_OVER_TIME with a radius applies to every enemy in it",
	run = function()
		local around = HexGrid.neighbors(4, 4)
		local battle, units = newBattle({
			{ "Plain", 1, 4, 4 },
			{ "Plain", 2, around[5][1], around[5][2] },
			{ "Plain", 2, around[6][1], around[6][2] },
			{ "Plain", 2, 4, 8 },
		})
		castWith(battle, units[1], {
			{
				type = "DAMAGE_OVER_TIME",
				center = "SELF",
				radius = 1,
				damageType = "TRUE",
				amount = 10,
				interval = 1,
				duration = 2,
			},
		})
		expectEqual(#battle.dots, 2, "both enemies in the radius")
		for _, each in battle.dots do
			assert(each.target ~= units[4], "an enemy outside the radius got the DOT")
		end
	end,
})

-- COPY -----------------------------------------------------------------------------------------

table.insert(tests, {
	name = "COPY casts the target's ability as the caster, scaled by the copied unit's cost",
	run = function()
		expectEqual(table.concat(CombatConfig.copyPowerByCost, ","), "0.8,0.8,0.8,0.6,0.45", "power by cost")
		for cost, power in { 0.80, 0.80, 0.80, 0.60, 0.45 } do
			local types = {
				Copier = unitType({ cost = 3 }),
				Source = unitType({ cost = cost }),
				Plain = unitType(),
			}
			types.Source.ability = {
				name = "Smash",
				effects = {
					{ type = "DAMAGE", target = "NEAREST_ENEMY", damageType = "TRUE", amount = { 100, 200, 400 } },
					{ type = "STUN", target = "NEAREST_ENEMY", duration = 1.5 },
				},
			}
			local battle, units =
				newBattle({ { "Copier", 1, 4, 4 }, { "Source", 2, 4, 6 }, { "Plain", 2, 4, 5 } }, types)
			castWith(battle, units[1], { { type = "COPY", target = "FARTHEST_ENEMY" } }, 2)
			local copy = eventsOf(battle, "Copy")[1]
			assert(copy and copy.ability == "Smash" and copy.target == units[2].index, "no Copy event")
			local damage = eventsOf(battle, "Damage")[1]
			expectEqual(damage.unit, units[1].index, "the copier deals the damage")
			expectEqual(damage.target, units[3].index, "selectors resolve from the copier")
			expectEqual(damage.damage, math.round(200 * power), cost .. "-cost copy at the copier's 2-star value")
			expectEqual(eventsOf(battle, "Stun")[1].duration, 1.5, "stun duration is not scaled")
		end
	end,
})

table.insert(tests, {
	name = "COPY of a summon does nothing; a copied SUMMON uses the copier's stats, unscaled count",
	run = function()
		local types = {
			Copier = unitType({ cost = 3, attackDamage = 100 }),
			Summoner = unitType({ cost = 5, attackDamage = 10 }),
		}
		types.Summoner.ability = { name = "Pack", effects = { SUMMON } }
		local battle, units = newBattle({ { "Copier", 1, 4, 4 }, { "Summoner", 2, 4, 8 } }, types)
		-- The summoner summons; then the copier copies one of its summons (nothing to copy).
		battle.units[2].ability = types.Summoner.ability
		Abilities.cast(battle, units[2])
		local enemySummon = battle.units[eventsOf(battle, "Summon")[1].summon]
		units[1].target = enemySummon
		local before = #battle.events
		castWith(battle, units[1], { { type = "COPY", target = "CURRENT_TARGET" } })
		for i = before + 1, #battle.events do
			assert(battle.events[i].kind == "Cast", "copying a summon produced " .. battle.events[i].kind)
		end

		-- Copying the summoner: 2 summons (count unscaled), stats from the copier.
		units[1].target = units[2]
		castWith(battle, units[1], { { type = "COPY", target = "CURRENT_TARGET" } })
		local mine = {}
		for _, event in eventsOf(battle, "Summon") do
			if event.unit == units[1].index then
				table.insert(mine, battle.units[event.summon])
			end
		end
		expectEqual(#mine, 2, "copied summon count is not scaled")
		near(mine[1].stats.attackDamage, 50, "50% of the copier's 100 AD")
		expectEqual(mine[1].summoner, units[1], "summons belong to the copier")
	end,
})

table.insert(tests, {
	name = "copying a COPY ignores the nested COPY and resolves the other effects",
	run = function()
		local types = {
			Copier = unitType({ cost = 3 }),
			Mimic = unitType({ cost = 2 }),
			Plain = unitType({ cost = 1 }),
		}
		types.Mimic.ability = {
			name = "Mimicry",
			effects = {
				{ type = "COPY", target = "NEAREST_ENEMY" },
				{ type = "DAMAGE", target = "NEAREST_ENEMY", damageType = "TRUE", amount = 100 },
			},
		}
		local battle, units = newBattle({ { "Copier", 1, 4, 4 }, { "Mimic", 2, 4, 5 } }, types)
		castWith(battle, units[1], { { type = "COPY", target = "NEAREST_ENEMY" } })
		expectEqual(#eventsOf(battle, "Copy"), 1, "only the outer copy happens")
		local damage = eventsOf(battle, "Damage")
		expectEqual(#damage, 1, "the copied DAMAGE resolves")
		expectEqual(damage[1].damage, 80, "at 0.8 for a 2-cost")
	end,
})

-- Selectors ------------------------------------------------------------------------------------

table.insert(tests, {
	name = "ALL_ALLIES reaches every living deployed ally, the caster included, but no summons",
	run = function()
		local battle, units = newBattle({
			{ "Plain", 1, 4, 4 },
			{ "Plain", 1, 3, 4 },
			{ "Plain", 1, 2, 4 },
			{ "Plain", 2, 4, 8 },
		})
		castWith(battle, units[1], { SUMMON })
		for _, unit in battle.units do
			unit.health = unit.maxHealth // 2
		end
		units[3].dead = true
		castWith(battle, units[1], { { type = "HEAL", target = "ALL_ALLIES", amount = 50 } })
		local healed = {}
		for _, event in eventsOf(battle, "Heal") do
			healed[event.target] = true
		end
		assert(healed[units[1].index] and healed[units[2].index], "living allies and the caster are healed")
		assert(not healed[units[3].index], "a dead ally was healed")
		assert(not healed[units[4].index], "an enemy was healed")
		for _, unit in battle.units do
			if unit.summoned then
				assert(not healed[unit.index], "a summon was healed")
			end
		end
		local ok = Abilities.validate({
			name = "X",
			effects = { { type = "DAMAGE", target = "ALL_ALLIES", damageType = "TRUE", amount = 1 } },
		})
		assert(not ok, "ALL_ALLIES should only work with HEAL, SHIELD and BUFF")
	end,
})

table.insert(tests, {
	name = "LOWEST_HP_OTHER_ALLY skips the caster and summons, and picks no one when alone",
	run = function()
		local battle, units =
			newBattle({ { "Plain", 1, 4, 4 }, { "Plain", 1, 3, 4 }, { "Plain", 1, 2, 4 }, { "Plain", 2, 4, 8 } })
		units[1].health = 10 -- the caster is the most hurt, but is skipped
		units[2].health = 500
		units[3].health = 900
		castWith(battle, units[1], { { type = "HEAL", target = "LOWEST_HP_OTHER_ALLY", amount = 50 } })
		expectEqual(eventsOf(battle, "Heal")[1].target, units[2].index, "most hurt other ally")

		local alone, aloneUnits = newBattle({ { "Plain", 1, 4, 4 }, { "Plain", 2, 4, 8 } })
		castWith(alone, aloneUnits[1], { SUMMON })
		castWith(alone, aloneUnits[1], { { type = "HEAL", target = "LOWEST_HP_OTHER_ALLY", amount = 50 } })
		expectEqual(#eventsOf(alone, "Heal"), 0, "no other deployed ally, no heal (summons do not count)")
	end,
})

-- Buff stacking and max health -----------------------------------------------------------------

table.insert(tests, {
	name = "a stacking BUFF adds a stack per cast up to its maximum, then only refreshes",
	run = function()
		local battle, units = newBattle({ { "Hitter", 1, 4, 4 }, { "Plain", 2, 4, 8 } })
		local caster = units[1]
		local stacking = {
			{
				type = "BUFF",
				target = "SELF",
				stat = "AD",
				percent = 10,
				duration = 8,
				stackPerCast = true,
				maxStacks = 3,
			},
		}
		for cast = 1, 4 do
			battle.tick = cast * 20
			castWith(battle, caster, stacking)
			local expectedStacks = math.min(cast, 3)
			near(Battle.stat(battle, caster, "AD"), 100 * (1 + 0.10 * expectedStacks), "AD after cast " .. cast)
		end
		local buff = caster.buffs[caster.index .. ":AD"]
		expectEqual(buff.stacks, 3, "stacks at the cap")
		expectEqual(buff.endsTick, 80 + 160, "the cast at the cap refreshed the duration")

		-- Without stackPerCast, recasting replaces (today's behavior).
		local plain, plainUnits = newBattle({ { "Hitter", 1, 4, 4 }, { "Plain", 2, 4, 8 } })
		for _ = 1, 3 do
			castWith(
				plain,
				plainUnits[1],
				{ { type = "BUFF", target = "SELF", stat = "AD", percent = 10, duration = 8 } }
			)
		end
		near(Battle.stat(plain, plainUnits[1], "AD"), 110, "non-stacking buffs refresh")
	end,
})

table.insert(tests, {
	name = "MaxHealth bonuses raise max and current health together; expiry caps current health",
	run = function()
		local battle, units = newBattle({ { "Plain", 1, 4, 4 }, { "Plain", 2, 4, 8 } })
		local unit = units[1]
		unit.health = 600
		castWith(battle, unit, { { type = "BUFF", target = "SELF", stat = "MaxHealth", percent = 20, duration = 1 } })
		expectEqual(unit.maxHealth, 1200, "max health +20%")
		expectEqual(unit.health, 800, "current health rises by the same 200")
		local event = eventsOf(battle, "MaxHealth")[1]
		assert(event and event.maxHealth == 1200 and event.health == 800, "no MaxHealth event")

		unit.health = 1150
		steps(battle, 25) -- the buff expires
		expectEqual(unit.maxHealth, 1000, "max health back to base")
		expectEqual(unit.health, 1000, "current health capped at the new max")

		-- As a combat-start (trait) bonus: permanent, applied before the fight.
		local start, startUnits = newBattle({ { "Plain", 1, 4, 4 } })
		Battle.applyStartBonus(
			start,
			startUnits[1],
			{ stats = { MaxHealth = { flat = 0, percent = 15 } }, shields = {} }
		)
		expectEqual(startUnits[1].maxHealth, 1150, "trait max health +15%")
		expectEqual(startUnits[1].health, 1150, "starts at full health")
		start.tick = 100000
		Battle.expire(start)
		expectEqual(startUnits[1].maxHealth, 1150, "trait bonus never expires")
	end,
})

return tests
