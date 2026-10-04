local Board = require("../src/shared/Board")
local BoardConfig = require("../src/shared/BoardConfig")
local CombatSim = require("../src/shared/CombatSim")
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
		buy(state, "Archer1") -- slot 1
		buy(state, "Tank1", 2) -- slots 2, 3
		assert(PlayerState.moveUnit(state, "2", { slot = 5 })) -- Tank1 copies now in slots 3 and 5
		buy(state, "Tank1") -- lands in free slot 2 and completes the set
		local tanks = unitsOf(state, "Tank1")
		expectEqual(#tanks, 1, "Tank1 units after merge")
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
		buy(state, "Tank1", 2)
		assert(PlayerState.moveUnit(state, "2", { column = 3, row = 4 }))
		buy(state, "Tank1")
		local tanks = unitsOf(state, "Tank1")
		expectEqual(#tanks, 1, "Tank1 units after merge")
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
		buy(state, "Tank2", 8)
		local tanks = unitsOf(state, "Tank2")
		expectEqual(#tanks, 4, "after 8 copies: two 2-stars and two 1-stars")
		buy(state, "Tank2")
		tanks = unitsOf(state, "Tank2")
		expectEqual(#tanks, 1, "Tank2 units after the ninth copy")
		expectEqual(tanks[1].starLevel, 3, "chained star level")
		expectEqual(state.gold, 100 - 9 * 2, "gold after nine 2-cost buys")
	end,
})

table.insert(tests, {
	name = "different star levels and 3-stars do not merge",
	run = function()
		local board = Board.new(7, 4, 9)
		Board.addUnit(board, "a", "Tank1")
		Board.addUnit(board, "b", "Tank1")
		Board.addUnit(board, "c", "Tank1")
		board.units.c.starLevel = 2
		expectEqual(#Board.mergeUnits(board), 0, "1-star + 1-star + 2-star merged")

		local maxed = Board.new(7, 4, 9)
		for _, id in { "x", "y", "z" } do
			Board.addUnit(maxed, id, "Tank1")
			maxed.units[id].starLevel = 3
		end
		expectEqual(#Board.mergeUnits(maxed), 0, "three 3-stars merged")
	end,
})

table.insert(tests, {
	name = "a full bench allows a purchase that completes a merge, and only that",
	run = function()
		local state = newPlayer(100)
		buy(state, "Tank1", 2)
		for _, unitType in { "Archer1", "Tank2", "Striker2", "Tank3", "Archer3", "Tank4", "Striker4" } do
			buy(state, unitType)
		end
		assert(not Board.hasBenchSpace(state.board), "bench should be full")

		state.shop[1] = "Tank5"
		local bought, reason = PlayerState.buyUnit(state, 1)
		assert(not bought and reason == PlayerState.Refusal.BenchFull, "non-merging buy allowed on a full bench")

		local gold = state.gold
		buy(state, "Tank1")
		local tanks = unitsOf(state, "Tank1")
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
		expectEqual(PlayerState.sellValue("Tank3", 1), 3, "1-star 3-cost")
		expectEqual(PlayerState.sellValue("Tank3", 2), 9, "2-star 3-cost")
		expectEqual(PlayerState.sellValue("Tank3", 3), 27, "3-star 3-cost")

		local state = newPlayer(20)
		buy(state, "Archer3", 3)
		expectEqual(state.gold, 11, "gold after buying three 3-costs")
		local archer = unitsOf(state, "Archer3")[1]
		assert(PlayerState.sellUnit(state, archer.id), "sell refused")
		expectEqual(state.gold, 20, "selling a 2-star refunds all three copies")
	end,
})

table.insert(tests, {
	name = "stat scaling: health x1.8 / x3.24 and attack damage x1.5 / x2.25; nothing else",
	run = function()
		local base = UnitConfig.Tank1 -- 700 health, 45 attack damage
		local two = StarLevel.scaleStats(base, 2)
		local three = StarLevel.scaleStats(base, 3)
		expectEqual(StarLevel.scaleStats(base, 1).health, 700, "1-star health")
		expectEqual(two.health, 1260, "2-star health")
		expectEqual(three.health, 2268, "3-star health")
		expectEqual(two.attackDamage, 68, "2-star attack damage (67.5 rounded)")
		expectEqual(three.attackDamage, 101, "3-star attack damage (101.25 rounded)")
		for _, stat in { "attacksPerSecond", "range", "moveSpeed", "cost", "role" } do
			expectEqual(three[stat], base[stat], "3-star " .. stat)
		end
		expectEqual(base.health, 700, "base stats were changed")
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
				{ { id = "a", unitType = "Tank1", starLevel = 2, column = 4, row = 4 } },
				{ { id = "b", unitType = "Tank1", column = 4, row = 4 } },
			},
			columns = 7,
			rows = 4,
			unitTypes = UnitConfig,
			ticksPerSecond = 20,
			maxTicks = 900,
			seed = 1,
			critChance = 0, -- exact damage
		})
		expectEqual(result.units[1].maxHealth, 1260, "2-star max health")
		expectEqual(result.units[1].starLevel, 2, "2-star summary")
		expectEqual(result.units[2].maxHealth, 700, "1-star max health (star level omitted)")
		for _, event in result.events do
			if event.kind == "Attack" then
				local expected = if event.unit == 1 then 68 else 45
				expectEqual(event.damage, expected, "damage by unit " .. event.unit)
			end
		end
		expectEqual(result.winner, 1, "the 2-star should win")
	end,
})

return tests
