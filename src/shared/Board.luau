-- One player's board and bench, and the placement rules for moving units between them.
-- Board cells use the player's own coordinates (row 1 = back row, `rows` = front row).
-- Pure Luau: no Roblox APIs, so it runs in Lune tests.
--
-- A unit is either on the bench (`slot` set) or on the board (`column` and `row` set).

local Board = {}

export type BoardUnit = {
	id: string,
	unitType: string,
	slot: number?,
	column: number?,
	row: number?,
}

export type Board = {
	columns: number,
	rows: number,
	benchSlots: number,
	units: { [string]: BoardUnit },
	cells: { [number]: string },
	bench: { [number]: string },
}

-- A move target: a bench slot ({ slot = n }) or a board cell ({ column = c, row = r }).
export type Target = {
	slot: number?,
	column: number?,
	row: number?,
}

function Board.new(columns: number, rows: number, benchSlots: number): Board
	return {
		columns = columns,
		rows = rows,
		benchSlots = benchSlots,
		units = {},
		cells = {},
		bench = {},
	}
end

local function cellIndex(board: Board, column: number, row: number): number
	return (row - 1) * board.columns + column
end

-- True for whole numbers only. Rejects non-numbers and NaN; infinities fail the bounds checks.
local function isInteger(value: any): boolean
	return type(value) == "number" and value == math.floor(value)
end

local function removeFromCurrentPlace(board: Board, unit: BoardUnit)
	if unit.slot then
		board.bench[unit.slot] = nil
		unit.slot = nil
	elseif unit.column and unit.row then
		board.cells[cellIndex(board, unit.column, unit.row)] = nil
		unit.column = nil
		unit.row = nil
	end
end

-- Adds a unit to the first free bench slot. Returns false if the bench is full or the id is taken.
function Board.addUnit(board: Board, id: string, unitType: string): boolean
	if board.units[id] then
		return false
	end
	for slot = 1, board.benchSlots do
		if board.bench[slot] == nil then
			board.units[id] = { id = id, unitType = unitType, slot = slot }
			board.bench[slot] = id
			return true
		end
	end
	return false
end

-- Moves a unit to a bench slot or board cell. `unitId` and `target` may come straight from a client,
-- so both are validated: the unit must belong to this board, and the target must be in bounds and
-- empty. Returns true if the move happened.
function Board.moveUnit(board: Board, unitId: any, target: any): boolean
	if type(unitId) ~= "string" or type(target) ~= "table" then
		return false
	end
	local unit = board.units[unitId]
	if not unit then
		return false
	end

	if target.slot ~= nil then
		local slot = target.slot
		if not isInteger(slot) or slot < 1 or slot > board.benchSlots or board.bench[slot] ~= nil then
			return false
		end
		removeFromCurrentPlace(board, unit)
		board.bench[slot] = unitId
		unit.slot = slot
		return true
	end

	local column, row = target.column, target.row
	if not isInteger(column) or not isInteger(row) then
		return false
	end
	if column < 1 or column > board.columns or row < 1 or row > board.rows then
		return false
	end
	local index = cellIndex(board, column, row)
	if board.cells[index] ~= nil then
		return false
	end
	removeFromCurrentPlace(board, unit)
	board.cells[index] = unitId
	unit.column = column
	unit.row = row
	return true
end

-- Returns copies of all units, sorted by id so the order is deterministic.
function Board.getUnits(board: Board): { BoardUnit }
	local result = {}
	for _, unit in board.units do
		table.insert(result, table.clone(unit))
	end
	table.sort(result, function(a, b)
		return a.id < b.id
	end)
	return result
end

-- Returns copies of the units placed on the board (not the bench), sorted by id.
function Board.getPlacedUnits(board: Board): { BoardUnit }
	local result = {}
	for _, unit in Board.getUnits(board) do
		if unit.column then
			table.insert(result, unit)
		end
	end
	return result
end

return Board
