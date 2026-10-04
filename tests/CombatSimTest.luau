local BoardConfig = require("../src/shared/BoardConfig")
local CombatConfig = require("../src/shared/CombatConfig")
local CombatSim = require("../src/shared/CombatSim")
local HexGrid = require("../src/shared/HexGrid")
local MatchConfig = require("../src/shared/MatchConfig")
local UnitConfig = require("../src/shared/UnitConfig")

local COLUMNS = BoardConfig.columns
local ROWS = BoardConfig.rows

local function placed(id, unitType, column, row)
	return { id = id, unitType = unitType, column = column, row = row }
end

-- The real starting units spread across the front two rows, as a player might place them.
local function playerBoard()
	return {
		placed("1", "Guardian", 4, 4),
		placed("2", "Brawler", 3, 4),
		placed("3", "Brawler", 5, 4),
		placed("4", "Archer", 4, 2),
		placed("5", "Striker", 6, 3),
	}
end

local function presetEnemyBoard()
	local board = {}
	for i, placement in CombatConfig.presetEnemyBoard do
		table.insert(board, placed("E" .. i, placement.unitType, placement.column, placement.row))
	end
	return board
end

local function params(boardA, boardB, seed, overrides)
	local result = {
		boards = { boardA, boardB },
		columns = COLUMNS,
		rows = ROWS,
		unitTypes = UnitConfig,
		ticksPerSecond = CombatConfig.ticksPerSecond,
		maxTicks = MatchConfig.combatMaxDuration * CombatConfig.ticksPerSecond,
		seed = seed,
	}
	for key, value in overrides or {} do
		result[key] = value
	end
	return result
end

local function deepEqual(a, b): boolean
	if type(a) ~= "table" or type(b) ~= "table" then
		return a == b
	end
	for key, value in a do
		if not deepEqual(value, b[key]) then
			return false
		end
	end
	for key in b do
		if a[key] == nil then
			return false
		end
	end
	return true
end

local tests = {}

table.insert(tests, {
	name = "same seed gives the same result",
	run = function()
		for seed = 1, 5 do
			local first = CombatSim.run(params(playerBoard(), presetEnemyBoard(), seed))
			local second = CombatSim.run(params(playerBoard(), presetEnemyBoard(), seed))
			assert(deepEqual(first, second), "results differ for seed " .. seed)
			assert(#first.events > 0, "no events were produced")
		end
	end,
})

table.insert(tests, {
	name = "a clearly stronger team wins on either side",
	run = function()
		local weak = { placed("w", "Archer", 4, 1) }
		for seed = 1, 10 do
			local asSide1 = CombatSim.run(params(playerBoard(), weak, seed))
			assert(asSide1.winner == 1, "stronger side 1 did not win with seed " .. seed)
			local asSide2 = CombatSim.run(params(weak, playerBoard(), seed))
			assert(asSide2.winner == 2, "stronger side 2 did not win with seed " .. seed)
		end
	end,
})

table.insert(tests, {
	name = "timeout gives a draw",
	run = function()
		local unkillable = { Wall = { health = 1e9, attackDamage = 1, attacksPerSecond = 1, range = 1, moveSpeed = 1 } }
		local result = CombatSim.run(params({ placed("a", "Wall", 4, 4) }, { placed("b", "Wall", 4, 4) }, 1, {
			unitTypes = unkillable,
			maxTicks = 200,
		}))
		assert(result.winner == nil, "expected a draw")
		assert(result.endTick == 200, "expected the fight to run to the time limit, ended at " .. result.endTick)
	end,
})

table.insert(tests, {
	name = "a side with no units loses immediately; two empty sides draw",
	run = function()
		local result = CombatSim.run(params(playerBoard(), {}, 1))
		assert(result.winner == 1 and result.endTick == 0, "empty side 2 should lose at tick 0")
		local empty = CombatSim.run(params({}, {}, 1))
		assert(empty.winner == nil and empty.endTick == 0, "two empty sides should draw at tick 0")
	end,
})

table.insert(tests, {
	name = "side 2 is rotated into the far half of the field",
	run = function()
		local result = CombatSim.run(params({ placed("a", "Archer", 1, 1) }, { placed("b", "Archer", 1, 1) }, 1))
		local a, b = result.units[1], result.units[2]
		assert(a.side == 1 and a.column == 1 and a.row == 1, "side 1 unit moved during setup")
		assert(b.side == 2 and b.column == COLUMNS and b.row == ROWS * 2, "side 2 unit was not rotated")
	end,
})

table.insert(tests, {
	name = "units never share a cell, move one cell at a time, and attack only in range",
	run = function()
		for seed = 1, 10 do
			local result = CombatSim.run(params(playerBoard(), presetEnemyBoard(), seed))
			local positions = {}
			local alive = {}
			local ranges = {}
			for _, unit in result.units do
				positions[unit.index] = { unit.column, unit.row }
				alive[unit.index] = true
				ranges[unit.index] = UnitConfig[unit.unitType].range
			end
			for _, event in result.events do
				if event.kind == "Move" then
					local from = positions[event.unit]
					assert(
						HexGrid.distance(from[1], from[2], event.column, event.row) == 1,
						"unit moved more than one cell"
					)
					for index, position in positions do
						assert(
							not (alive[index] and position[1] == event.column and position[2] == event.row),
							"two units shared a cell"
						)
					end
					positions[event.unit] = { event.column, event.row }
				elseif event.kind == "Attack" then
					local from, to = positions[event.unit], positions[event.target]
					assert(alive[event.unit] and alive[event.target], "a dead unit attacked or was attacked")
					assert(
						HexGrid.distance(from[1], from[2], to[1], to[2]) <= ranges[event.unit],
						"attacked out of range"
					)
				elseif event.kind == "Death" then
					alive[event.unit] = nil
				end
			end
			assert(result.winner ~= nil, "the preset fight should not time out (seed " .. seed .. ")")
		end
	end,
})

return tests
