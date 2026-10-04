-- Hex grid math for pointy-top hexes in "odd-r" offset coordinates: hexes form rows, and every
-- even-numbered row (2, 4, ...) is shifted half a cell to the right. Columns and rows are 1-based.
-- Pure Luau: no Roblox APIs, so it runs in Lune tests.

local HexGrid = {}

-- Neighbor offsets as { columnDelta, rowDelta }.
local ODD_ROW_DIRECTIONS = { { 1, 0 }, { 0, -1 }, { -1, -1 }, { -1, 0 }, { -1, 1 }, { 0, 1 } }
local EVEN_ROW_DIRECTIONS = { { 1, 0 }, { 1, -1 }, { 0, -1 }, { -1, 0 }, { 0, 1 }, { 1, 1 } }

function HexGrid.isShiftedRow(row: number): boolean
	return row % 2 == 0
end

-- Converts offset coordinates to axial coordinates (q, r).
local function toAxial(column: number, row: number): (number, number)
	local column0 = column - 1
	local row0 = row - 1
	return column0 - (row0 - row0 % 2) // 2, row0
end

function HexGrid.distance(column1: number, row1: number, column2: number, row2: number): number
	local q1, r1 = toAxial(column1, row1)
	local q2, r2 = toAxial(column2, row2)
	local dq = q1 - q2
	local dr = r1 - r2
	return (math.abs(dq) + math.abs(dr) + math.abs(dq + dr)) // 2
end

-- Returns the six neighboring cells as { column, row } pairs, without bounds checks.
function HexGrid.neighbors(column: number, row: number): { { number } }
	local directions = if HexGrid.isShiftedRow(row) then EVEN_ROW_DIRECTIONS else ODD_ROW_DIRECTIONS
	local result = table.create(6)
	for _, direction in directions do
		table.insert(result, { column + direction[1], row + direction[2] })
	end
	return result
end

-- Rotates a cell half a turn around the center of a columns x rows grid. When `rows` is even this
-- is an exact point reflection of the hex layout, so distances and adjacency are preserved.
function HexGrid.rotateHalfTurn(column: number, row: number, columns: number, rows: number): (number, number)
	return columns + 1 - column, rows + 1 - row
end

return HexGrid
