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

-- Converts axial coordinates back to offset coordinates (the inverse of toAxial).
local function fromAxial(q: number, r: number): (number, number)
	return q + (r - r % 2) // 2 + 1, r + 1
end

-- Rounds fractional cube coordinates to the nearest hex (x + y + z = 0).
local function cubeRound(x: number, y: number, z: number): (number, number)
	local rx, ry, rz = math.round(x), math.round(y), math.round(z)
	local dx, dy, dz = math.abs(rx - x), math.abs(ry - y), math.abs(rz - z)
	if dx > dy and dx > dz then
		rx = -ry - rz
	elseif dy > dz then
		ry = -rx - rz
	else
		rz = -rx - ry
	end
	return rx, rz
end

-- Rotates a cell half a turn around the center of a columns x rows grid. When `rows` is even this
-- is an exact point reflection of the hex layout, so distances and adjacency are preserved.
function HexGrid.rotateHalfTurn(column: number, row: number, columns: number, rows: number): (number, number)
	return columns + 1 - column, rows + 1 - row
end

-- The center of a cell on a flat plane, one unit between neighboring centers: x along columns
-- (shifted rows half a cell to the right), y along rows. For directions and angles.
function HexGrid.point(column: number, row: number): (number, number)
	local shift = if HexGrid.isShiftedRow(row) then 0.5 else 0
	return column + shift, row * math.sqrt(3) / 2
end

-- The cells on the straight line from one cell through another, without the starting cell: the
-- cells up to the second one, then `beyond` more cells past it in the same direction. No bounds
-- checks (cells past the board edge are included; callers drop them). Empty if the two cells are
-- the same.
function HexGrid.line(
	fromColumn: number,
	fromRow: number,
	throughColumn: number,
	throughRow: number,
	beyond: number?
): { { number } }
	local steps = HexGrid.distance(fromColumn, fromRow, throughColumn, throughRow)
	local cells = {}
	if steps == 0 then
		return cells
	end
	local q1, r1 = toAxial(fromColumn, fromRow)
	local q2, r2 = toAxial(throughColumn, throughRow)
	-- A tiny nudge keeps points that fall exactly between two hexes on one side, consistently.
	local x1, z1 = q1 + 1e-6, r1 + 2e-6
	local dx, dz = (q2 - q1) / steps, (r2 - r1) / steps
	for i = 1, steps + (beyond or 0) do
		local x, z = x1 + dx * i, z1 + dz * i
		local q, r = cubeRound(x, -x - z, z)
		local column, row = fromAxial(q, r)
		table.insert(cells, { column, row })
	end
	return cells
end

-- True if the cell lies within `halfAngle` degrees of the direction from `origin` toward
-- `toward` (the cone's axis). The origin cell itself is never inside.
function HexGrid.inCone(
	originColumn: number,
	originRow: number,
	towardColumn: number,
	towardRow: number,
	column: number,
	row: number,
	halfAngle: number
): boolean
	local ox, oy = HexGrid.point(originColumn, originRow)
	local ax, ay = HexGrid.point(towardColumn, towardRow)
	local cx, cy = HexGrid.point(column, row)
	ax, ay, cx, cy = ax - ox, ay - oy, cx - ox, cy - oy
	local axisLength, cellLength = math.sqrt(ax * ax + ay * ay), math.sqrt(cx * cx + cy * cy)
	if axisLength < 1e-9 or cellLength < 1e-9 then
		return false
	end
	local cosine = (ax * cx + ay * cy) / (axisLength * cellLength)
	-- The small allowance includes cells exactly on the cone's edges.
	return cosine >= math.cos(math.rad(halfAngle)) - 1e-9
end

return HexGrid
