-- One player's board and bench, and the placement rules for moving units between them.
-- Board cells use the player's own coordinates (row 1 = back row, `rows` = front row).
-- Pure Luau: no Roblox APIs, so it runs in Lune tests.
--
-- A unit is either on the bench (`slot` set) or on the board (`column` and `row` set).

local Board = {}

export type BoardUnit = {
	id: string,
	unitType: string,
	starLevel: number, -- always 1 until star upgrades exist
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

-- A place on the board: a bench slot ({ slot = n }) or a board cell ({ column = c, row = r }).
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

-- Checks a target that may come from a client. Returns a clean copy, or nil if it is malformed or
-- out of bounds.
local function validTarget(board: Board, target: any): Target?
	if type(target) ~= "table" then
		return nil
	end
	if target.slot ~= nil then
		local slot = target.slot
		if isInteger(slot) and slot >= 1 and slot <= board.benchSlots then
			return { slot = slot }
		end
		return nil
	end
	local column, row = target.column, target.row
	if not isInteger(column) or not isInteger(row) then
		return nil
	end
	if column < 1 or column > board.columns or row < 1 or row > board.rows then
		return nil
	end
	return { column = column, row = row }
end

local function occupantAt(board: Board, place: Target): string?
	if place.slot then
		return board.bench[place.slot]
	end
	return board.cells[cellIndex(board, place.column :: number, place.row :: number)]
end

local function placeOf(unit: BoardUnit): Target
	if unit.slot then
		return { slot = unit.slot }
	end
	return { column = unit.column, row = unit.row }
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

local function putAt(board: Board, unit: BoardUnit, place: Target)
	if place.slot then
		board.bench[place.slot] = unit.id
		unit.slot = place.slot
	else
		local column, row = place.column :: number, place.row :: number
		board.cells[cellIndex(board, column, row)] = unit.id
		unit.column = column
		unit.row = row
	end
end

function Board.countPlaced(board: Board): number
	local count = 0
	for _ in board.cells do
		count += 1
	end
	return count
end

function Board.hasBenchSpace(board: Board): boolean
	for slot = 1, board.benchSlots do
		if board.bench[slot] == nil then
			return true
		end
	end
	return false
end

-- Adds a 1-star unit to the first free bench slot. Returns false if the bench is full or the id is
-- taken.
function Board.addUnit(board: Board, id: string, unitType: string): boolean
	if board.units[id] then
		return false
	end
	for slot = 1, board.benchSlots do
		if board.bench[slot] == nil then
			board.units[id] = { id = id, unitType = unitType, starLevel = 1, slot = slot }
			board.bench[slot] = id
			return true
		end
	end
	return false
end

-- Removes a unit from the board or bench. `unitId` may come from a client. Returns a copy of the
-- removed unit, or nil if this board has no such unit.
function Board.removeUnit(board: Board, unitId: any): BoardUnit?
	if type(unitId) ~= "string" then
		return nil
	end
	local unit = board.units[unitId]
	if not unit then
		return nil
	end
	local removed = table.clone(unit)
	removeFromCurrentPlace(board, unit)
	board.units[unitId] = nil
	return removed
end

-- Moves a unit to a bench slot or board cell. If the target is occupied, the two units swap places.
-- `unitId` and `target` may come straight from a client, so both are validated: the unit must belong
-- to this board and the target must be in bounds. When `maxPlaced` is given, a move that would put
-- more than that many units on the board is refused (swaps never change the count).
-- Returns true if the move happened.
function Board.moveUnit(board: Board, unitId: any, target: any, maxPlaced: number?): boolean
	if type(unitId) ~= "string" then
		return false
	end
	local unit = board.units[unitId]
	local place = validTarget(board, target)
	if not unit or not place then
		return false
	end

	local occupantId = occupantAt(board, place)
	if occupantId == unitId then
		return false
	end
	local addsToBoard = unit.slot ~= nil and place.slot == nil and occupantId == nil
	if addsToBoard and maxPlaced and Board.countPlaced(board) >= maxPlaced then
		return false
	end

	local from = placeOf(unit)
	local occupant = if occupantId then board.units[occupantId] else nil
	removeFromCurrentPlace(board, unit)
	if occupant then
		removeFromCurrentPlace(board, occupant)
	end
	putAt(board, unit, place)
	if occupant then
		putAt(board, occupant, from)
	end
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
