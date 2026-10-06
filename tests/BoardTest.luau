local Board = require("../src/shared/Board")
local BoardConfig = require("../src/shared/BoardConfig")
local CombatConfig = require("../src/shared/CombatConfig")
local UnitConfig = require("../src/shared/UnitConfig")

-- A 7x4 board with a 9-slot bench holding units "a" (slot 1) and "b" (slot 2).
local function newBoard()
	local board = Board.new(7, 4, 9)
	assert(Board.addUnit(board, "a", "cinder_arc"))
	assert(Board.addUnit(board, "b", "spurshot"))
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
		assert(not Board.addUnit(board, "a", "cinder_arc"), "duplicate id accepted")
	end,
})

table.insert(tests, {
	name = "bench rejects units when full",
	run = function()
		local board = Board.new(7, 4, 2)
		assert(Board.addUnit(board, "a", "cinder_arc"))
		assert(Board.addUnit(board, "b", "cinder_arc"))
		assert(not Board.addUnit(board, "c", "cinder_arc"), "added a unit to a full bench")
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
	name = "moving onto an occupied place swaps the two units",
	run = function()
		local board = newBoard()

		-- Bench <-> bench
		assert(Board.moveUnit(board, "a", { slot = 2 }), "bench swap refused")
		assert(findUnit(board, "a").slot == 2 and findUnit(board, "b").slot == 1, "bench swap")

		-- Bench <-> board
		assert(Board.moveUnit(board, "a", { column = 2, row = 2 }))
		assert(Board.moveUnit(board, "b", { column = 2, row = 2 }), "bench -> occupied cell refused")
		local a, b = findUnit(board, "a"), findUnit(board, "b")
		assert(b.column == 2 and b.row == 2 and a.slot == 1 and a.column == nil, "bench/board swap")

		-- Board <-> board
		assert(Board.moveUnit(board, "a", { column = 5, row = 3 }))
		assert(Board.moveUnit(board, "a", { column = 2, row = 2 }), "cell swap refused")
		a, b = findUnit(board, "a"), findUnit(board, "b")
		assert(a.column == 2 and a.row == 2 and b.column == 5 and b.row == 3, "cell swap")

		-- Board -> occupied bench slot
		assert(Board.addUnit(board, "c", "cinder_arc"))
		local cSlot = findUnit(board, "c").slot
		assert(Board.moveUnit(board, "a", { slot = cSlot }), "board -> occupied slot refused")
		local c = findUnit(board, "c")
		assert(findUnit(board, "a").slot == cSlot and c.column == 2 and c.row == 2, "board/bench swap")

		assert(not Board.moveUnit(board, "a", { slot = cSlot }), "moved onto its own place")
		assert(Board.countPlaced(board) == 2, "swaps changed the number of placed units")
	end,
})

table.insert(tests, {
	name = "unit cap refuses extra units on the board but allows swaps",
	run = function()
		local board = newBoard()
		assert(Board.addUnit(board, "c", "cinder_arc"))
		assert(Board.moveUnit(board, "a", { column = 1, row = 1 }, 2))
		assert(Board.moveUnit(board, "b", { column = 2, row = 1 }, 2))
		assert(not Board.moveUnit(board, "c", { column = 3, row = 1 }, 2), "placed a third unit at cap 2")
		assert(findUnit(board, "c").slot ~= nil, "refused move changed state")
		assert(Board.moveUnit(board, "c", { column = 1, row = 1 }, 2), "bench/board swap refused at cap")
		assert(Board.moveUnit(board, "c", { column = 4, row = 4 }, 2), "board -> board move refused at cap")
		assert(Board.countPlaced(board) == 2, "expected 2 placed units")
		assert(Board.moveUnit(board, "a", { column = 3, row = 1 }, 3), "move refused under a higher cap")
	end,
})

table.insert(tests, {
	name = "units start at 1 star, and removing frees their place",
	run = function()
		local board = newBoard()
		assert(findUnit(board, "a").starLevel == 1, "new unit is not 1-star")
		assert(Board.moveUnit(board, "a", { column = 3, row = 3 }))
		local removed = Board.removeUnit(board, "a")
		assert(removed and removed.unitType == "cinder_arc", "removeUnit did not return the unit")
		assert(findUnit(board, "a") == nil and Board.countPlaced(board) == 0, "unit still on the board")
		assert(Board.moveUnit(board, "b", { column = 3, row = 3 }), "cell was not freed")
		assert(Board.removeUnit(board, "a") == nil, "removed a unit twice")
		assert(Board.removeUnit(board, 5) == nil, "accepted a non-string id")

		local full = Board.new(7, 4, 1)
		assert(Board.hasBenchSpace(full), "empty bench has no space")
		assert(Board.addUnit(full, "x", "cinder_arc"))
		assert(not Board.hasBenchSpace(full), "full bench has space")
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
	name = "config: every enemy board is valid",
	run = function()
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
