local Battle = require("../src/shared/Battle")
local Board = require("../src/shared/Board")
local BoardConfig = require("../src/shared/BoardConfig")
local CombatConfig = require("../src/shared/CombatConfig")
local CombatSim = require("../src/shared/CombatSim")
local Match = require("../src/shared/Match")
local MatchConfig = require("../src/shared/MatchConfig")
local PlayerState = require("../src/shared/PlayerState")
local StarLevel = require("../src/shared/StarLevel")
local UnitConfig = require("../src/shared/UnitConfig")

local function expectEqual(actual, expected, label)
	assert(actual == expected, string.format("%s: expected %s, got %s", label, tostring(expected), tostring(actual)))
end

local function newPlayer(gold)
	local state = PlayerState.new(1)
	state.gold = gold
	return state
end

-- Buys `count` copies of `unitType` through the shop.
local function buy(state, unitType, count)
	for i = 1, count or 1 do
		state.shop[1] = unitType
		local bought, reason = PlayerState.buyUnit(state, 1)
		assert(bought, string.format("buying %s #%d refused: %s", unitType, i, tostring(reason)))
	end
end

local function unitsOf(state, unitType)
	local result = {}
	for _, unit in Board.getUnits(state.board) do
		if unit.unitType == unitType then
			table.insert(result, unit)
		end
	end
	return result
end

local tests = {}

table.insert(tests, {
	name = "three 1-star bench copies merge into one 2-star in the lowest-numbered slot",
	run = function()
		local state = newPlayer(10)
		buy(state, "Mira") -- slot 1
		buy(state, "Kaien", 2) -- slots 2, 3
		assert(PlayerState.moveUnit(state, "2", { slot = 5 })) -- Kaien copies now in slots 3 and 5
		buy(state, "Kaien") -- lands in free slot 2 and completes the set
		local tanks = unitsOf(state, "Kaien")
		expectEqual(#tanks, 1, "Kaien units after merge")
		expectEqual(tanks[1].starLevel, 2, "merged star level")
		expectEqual(tanks[1].slot, 2, "merged unit takes the lowest-numbered bench slot")
		expectEqual(#Board.getUnits(state.board), 2, "units after merge")
		expectEqual(state.gold, 6, "gold after four 1-cost buys")
	end,
})

table.insert(tests, {
	name = "a board copy keeps its cell when merging with bench copies",
	run = function()
		local state = newPlayer(10)
		buy(state, "Kaien", 2)
		assert(PlayerState.moveUnit(state, "2", { column = 3, row = 4 }))
		buy(state, "Kaien")
		local tanks = unitsOf(state, "Kaien")
		expectEqual(#tanks, 1, "Kaien units after merge")
		assert(tanks[1].starLevel == 2 and tanks[1].column == 3 and tanks[1].row == 4, "merged unit not on the board")
		expectEqual(Board.countPlaced(state.board), 1, "units on the board")
		for slot = 1, BoardConfig.benchSlots do
			assert(state.board.bench[slot] == nil, "bench copy was not removed")
		end
	end,
})

table.insert(tests, {
	name = "merges chain: the ninth copy turns three 2-stars into a 3-star",
	run = function()
		local state = newPlayer(100)
		buy(state, "Rook", 8)
		local tanks = unitsOf(state, "Rook")
		expectEqual(#tanks, 4, "after 8 copies: two 2-stars and two 1-stars")
		buy(state, "Rook")
		tanks = unitsOf(state, "Rook")
		expectEqual(#tanks, 1, "Rook units after the ninth copy")
		expectEqual(tanks[1].starLevel, 3, "chained star level")
		expectEqual(state.gold, 100 - 9 * 2, "gold after nine 2-cost buys")
	end,
})

table.insert(tests, {
	name = "different star levels and 3-stars do not merge",
	run = function()
		local board = Board.new(7, 4, 9)
		Board.addUnit(board, "a", "Kaien")
		Board.addUnit(board, "b", "Kaien")
		Board.addUnit(board, "c", "Kaien")
		board.units.c.starLevel = 2
		expectEqual(#Board.mergeUnits(board), 0, "1-star + 1-star + 2-star merged")

		local maxed = Board.new(7, 4, 9)
		for _, id in { "x", "y", "z" } do
			Board.addUnit(maxed, id, "Kaien")
			maxed.units[id].starLevel = 3
		end
		expectEqual(#Board.mergeUnits(maxed), 0, "three 3-stars merged")
	end,
})

table.insert(tests, {
	name = "a full bench allows a purchase that completes a merge, and only that",
	run = function()
		local state = newPlayer(100)
		buy(state, "Kaien", 2)
		for _, unitType in { "Mira", "Rook", "Sena", "Dax", "Veyra", "Orin", "Nyra" } do
			buy(state, unitType)
		end
		assert(not Board.hasBenchSpace(state.board), "bench should be full")

		state.shop[1] = "Kairo"
		local bought, reason = PlayerState.buyUnit(state, 1)
		assert(not bought and reason == PlayerState.Refusal.BenchFull, "non-merging buy allowed on a full bench")

		local gold = state.gold
		buy(state, "Kaien")
		local tanks = unitsOf(state, "Kaien")
		assert(#tanks == 1 and tanks[1].starLevel == 2 and tanks[1].slot == 1, "full-bench merge")
		expectEqual(state.gold, gold - 1, "gold after the merging buy")
		assert(Board.hasBenchSpace(state.board), "merge did not free bench slots")
		for _, unit in Board.getUnits(state.board) do
			assert(unit.slot or unit.column, "a unit was left without a place")
		end
	end,
})

table.insert(tests, {
	name = "sell value is the total gold spent: cost x1, x3, x9",
	run = function()
		expectEqual(PlayerState.sellValue("Dax", 1), 3, "1-star 3-cost")
		expectEqual(PlayerState.sellValue("Dax", 2), 9, "2-star 3-cost")
		expectEqual(PlayerState.sellValue("Dax", 3), 27, "3-star 3-cost")

		local state = newPlayer(20)
		buy(state, "Veyra", 3)
		expectEqual(state.gold, 11, "gold after buying three 3-costs")
		local archer = unitsOf(state, "Veyra")[1]
		assert(PlayerState.sellUnit(state, archer.id), "sell refused")
		expectEqual(state.gold, 20, "selling a 2-star refunds all three copies")
	end,
})

table.insert(tests, {
	name = "stat scaling: health x1.15 x (1 / 1.8 / 3.24) and attack damage x1.5 / x2.25; nothing else",
	run = function()
		local base = UnitConfig.Kaien -- 720 health, 48 attack damage
		local two = StarLevel.scaleStats(base, 2)
		local three = StarLevel.scaleStats(base, 3)
		expectEqual(StarLevel.scaleStats(base, 1).health, 828, "1-star health (720 x 1.15)")
		expectEqual(two.health, 1490, "2-star health (1490.4 rounded)")
		expectEqual(three.health, 2683, "3-star health (2682.72 rounded)")
		expectEqual(two.attackDamage, 72, "2-star attack damage")
		expectEqual(three.attackDamage, 108, "3-star attack damage")
		for _, stat in
			{ "attacksPerSecond", "range", "moveSpeed", "cost", "armor", "magicResist", "abilityPower", "maxMana" }
		do
			expectEqual(three[stat], base[stat], "3-star " .. stat)
		end
		assert(three.ability == base.ability, "the ability table should not change with star level")
		expectEqual(base.health, 720, "base stats were changed")
	end,
})

table.insert(tests, {
	name = "every unit enters combat with 1.15x its base health; base data and player health are unchanged",
	run = function()
		expectEqual(CombatConfig.globalHealthMultiplier, 1.15, "global health multiplier")
		local board = {}
		local names = {}
		for name in UnitConfig do
			table.insert(names, name)
		end
		table.sort(names)
		for i, name in names do
			table.insert(board, { id = name, unitType = name, column = (i - 1) % 7 + 1, row = (i - 1) // 7 + 1 })
		end
		local battle = Battle.new({
			boards = { board, {} },
			columns = 7,
			rows = 4,
			unitTypes = UnitConfig,
			ticksPerSecond = 20,
			maxTicks = 1,
			seed = 1,
		})
		for _, unit in battle.units do
			local expected = math.round(UnitConfig[unit.unitType].health * 1.15)
			expectEqual(unit.maxHealth, expected, unit.unitType .. " combat health")
			expectEqual(unit.health, expected, unit.unitType .. " starting health")
			expectEqual(
				unit.stats.attackDamage,
				UnitConfig[unit.unitType].attackDamage,
				unit.unitType .. " attack damage"
			)
		end
		expectEqual(UnitConfig.Orin.health, 1180, "UnitConfig keeps the design docs' base health")
		local match = Match.new({ 1, 2 }, 1)
		expectEqual(match.players[1].health, MatchConfig.startingHealth, "player health")
	end,
})

table.insert(tests, {
	name = "copies per star level are 1, 3 and 9",
	run = function()
		expectEqual(StarLevel.copiesIn(1), 1, "1-star")
		expectEqual(StarLevel.copiesIn(2), 3, "2-star")
		expectEqual(StarLevel.copiesIn(3), 9, "3-star")
	end,
})

table.insert(tests, {
	name = "combat applies star scaling to health and damage",
	run = function()
		local result = CombatSim.run({
			boards = {
				{ { id = "a", unitType = "Kaien", starLevel = 2, column = 4, row = 4 } },
				{ { id = "b", unitType = "Kaien", column = 4, row = 4 } },
			},
			columns = 7,
			rows = 4,
			unitTypes = UnitConfig,
			ticksPerSecond = 20,
			maxTicks = 900,
			seed = 1,
			critChance = 0, -- exact damage
		})
		expectEqual(result.units[1].maxHealth, 1490, "2-star max health (720 x 1.8 x 1.15)")
		expectEqual(result.units[1].starLevel, 2, "2-star summary")
		expectEqual(result.units[2].maxHealth, 828, "1-star max health (star level omitted; 720 x 1.15)")
		-- Kaien has 40 armor: 72 x 100/140 = 51.4 -> 51, and 48 x 100/140 = 34.3 -> 34.
		for _, event in result.events do
			if event.kind == "Attack" then
				local expected = if event.unit == 1 then 51 else 34
				expectEqual(event.damage, expected, "damage by unit " .. event.unit)
			end
		end
		expectEqual(result.winner, 1, "the 2-star should win")
	end,
})

return tests
