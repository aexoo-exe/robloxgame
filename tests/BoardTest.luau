local Board = require("../src/shared/Board")
local BoardConfig = require("../src/shared/BoardConfig")
local CombatConfig = require("../src/shared/CombatConfig")
local UnitConfig = require("../src/shared/UnitConfig")

-- A 7x4 board with a 9-slot bench holding units "a" (slot 1) and "b" (slot 2).
local function newBoard()
	local board = Board.new(7, 4, 9)
	assert(Board.addUnit(board, "a", "Tank1"))
	assert(Board.addUnit(board, "b", "Archer1"))
	return board
end

local function findUnit(board, id)
	for _, unit in Board.getUnits(board) do
		if unit.id == id then
			return unit
		end
	end
	return nil
end

local tests = {}

table.insert(tests, {
	name = "new units go to the first free bench slots",
	run = function()
		local board = newBoard()
		assert(findUnit(board, "a").slot == 1, "unit a is not in slot 1")
		assert(findUnit(board, "b").slot == 2, "unit b is not in slot 2")
		assert(not Board.addUnit(board, "a", "Tank1"), "duplicate id accepted")
	end,
})

table.insert(tests, {
	name = "bench rejects units when full",
	run = function()
		local board = Board.new(7, 4, 2)
		assert(Board.addUnit(board, "a", "Tank1"))
		assert(Board.addUnit(board, "b", "Tank1"))
		assert(not Board.addUnit(board, "c", "Tank1"), "added a unit to a full bench")
	end,
})

table.insert(tests, {
	name = "moves between bench and board, and between cells",
	run = function()
		local board = newBoard()
		assert(Board.moveUnit(board, "a", { column = 4, row = 4 }), "bench -> board")
		local a = findUnit(board, "a")
		assert(a.column == 4 and a.row == 4 and a.slot == nil, "unit a is not at (4, 4)")

		assert(Board.moveUnit(board, "a", { column = 1, row = 1 }), "board -> board")
		assert(Board.moveUnit(board, "b", { column = 4, row = 4 }), "old cell was not freed")

		assert(Board.moveUnit(board, "a", { slot = 9 }), "board -> bench")
		a = findUnit(board, "a")
		assert(a.slot == 9 and a.column == nil and a.row == nil, "unit a is not in slot 9")
		assert(Board.moveUnit(board, "b", { column = 1, row = 1 }), "cell was not freed by bench move")

		assert(Board.moveUnit(board, "a", { slot = 1 }), "bench -> bench")
		assert(#Board.getPlacedUnits(board) == 1, "expected exactly one placed unit")
	end,
})

table.insert(tests, {
	name = "rejects occupied cells and slots",
	run = function()
		local board = newBoard()
		assert(Board.moveUnit(board, "a", { column = 2, row = 2 }))
		assert(not Board.moveUnit(board, "b", { column = 2, row = 2 }), "moved onto an occupied cell")
		assert(not Board.moveUnit(board, "a", { column = 2, row = 2 }), "moved onto its own cell")
		assert(Board.moveUnit(board, "a", { slot = 5 }))
		assert(not Board.moveUnit(board, "b", { slot = 5 }), "moved onto an occupied slot")
		assert(findUnit(board, "b").slot == 2, "rejected move changed state")
	end,
})

table.insert(tests, {
	name = "rejects cells outside the player's own half",
	run = function()
		local board = newBoard()
		for _, target in
			{
				{ column = 1, row = 5 }, -- enemy half
				{ column = 0, row = 1 },
				{ column = 8, row = 1 },
				{ column = 1, row = 0 },
				{ slot = 0 },
				{ slot = 10 },
			}
		do
			assert(not Board.moveUnit(board, "a", target), "accepted an out-of-bounds target")
		end
		assert(findUnit(board, "a").slot == 1, "unit a is not in slot 1")
	end,
})

table.insert(tests, {
	name = "rejects units the player does not own and malformed requests",
	run = function()
		local board = newBoard()
		assert(not Board.moveUnit(board, "z", { column = 1, row = 1 }), "moved an unknown unit")
		assert(not Board.moveUnit(board, 1, { column = 1, row = 1 }), "accepted a non-string id")
		assert(not Board.moveUnit(board, "a", nil), "accepted a nil target")
		assert(not Board.moveUnit(board, "a", "1,1"), "accepted a string target")
		assert(not Board.moveUnit(board, "a", { column = 1.5, row = 1 }), "accepted a fractional column")
		assert(not Board.moveUnit(board, "a", { column = 0 / 0, row = 1 }), "accepted NaN")
		assert(not Board.moveUnit(board, "a", { column = math.huge, row = 1 }), "accepted infinity")
		assert(not Board.moveUnit(board, "a", { column = "1", row = "1" }), "accepted string coordinates")
		assert(not Board.moveUnit(board, "a", {}), "accepted an empty target")
	end,
})

table.insert(tests, {
	name = "config: starting units and every enemy board are valid",
	run = function()
		assert(#BoardConfig.startingUnits <= BoardConfig.benchSlots, "starting units do not fit on the bench")
		for _, unitType in BoardConfig.startingUnits do
			assert(UnitConfig[unitType], "unknown starting unit " .. unitType)
		end

		assert(#CombatConfig.enemyBoardsByRound > 0, "no enemy boards")
		for round, placements in CombatConfig.enemyBoardsByRound do
			local enemy = Board.new(BoardConfig.columns, BoardConfig.rows, 0)
			for i, placement in placements do
				assert(UnitConfig[placement.unitType], "unknown enemy unit " .. placement.unitType)
				local id = "E" .. i
				enemy.units[id] = { id = id, unitType = placement.unitType }
				assert(
					Board.moveUnit(enemy, id, { column = placement.column, row = placement.row }),
					string.format("round %d enemy unit %d is out of bounds or overlaps another", round, i)
				)
			end
		end
	end,
})

return tests
