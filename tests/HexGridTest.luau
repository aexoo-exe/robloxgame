local HexGrid = require("../src/shared/HexGrid")

local COLUMNS = 7
local FIELD_ROWS = 8

local tests = {}

table.insert(tests, {
	name = "every neighbor is at distance 1 and neighbors are distinct",
	run = function()
		for row = 1, FIELD_ROWS do
			for column = 1, COLUMNS do
				local seen = {}
				for _, neighbor in HexGrid.neighbors(column, row) do
					local key = neighbor[1] .. "," .. neighbor[2]
					assert(not seen[key], "duplicate neighbor " .. key)
					seen[key] = true
					local distance = HexGrid.distance(column, row, neighbor[1], neighbor[2])
					assert(distance == 1, string.format("(%d,%d) -> %s has distance %d", column, row, key, distance))
				end
			end
		end
	end,
})

table.insert(tests, {
	name = "distance matches known values",
	run = function()
		local cases = {
			{ 1, 1, 1, 1, 0 },
			{ 1, 1, 7, 1, 6 },
			-- Moving straight "up" an odd-r grid zig-zags, so 7 rows up from column 1 costs 7.
			{ 1, 1, 1, 8, 7 },
			-- Row 2 is shifted right, so (1, 2) touches both (1, 1) and (2, 1).
			{ 1, 2, 1, 1, 1 },
			{ 1, 2, 2, 1, 1 },
			{ 3, 1, 1, 2, 2 },
		}
		for _, case in cases do
			local distance = HexGrid.distance(case[1], case[2], case[3], case[4])
			assert(
				distance == case[5],
				string.format(
					"(%d,%d)-(%d,%d): expected %d, got %d",
					case[1],
					case[2],
					case[3],
					case[4],
					case[5],
					distance
				)
			)
		end
	end,
})

table.insert(tests, {
	name = "half-turn rotation of an even-row field preserves distances",
	run = function()
		for row1 = 1, FIELD_ROWS do
			for column1 = 1, COLUMNS do
				for row2 = 1, FIELD_ROWS do
					for column2 = 1, COLUMNS do
						local rc1, rr1 = HexGrid.rotateHalfTurn(column1, row1, COLUMNS, FIELD_ROWS)
						local rc2, rr2 = HexGrid.rotateHalfTurn(column2, row2, COLUMNS, FIELD_ROWS)
						assert(
							HexGrid.distance(column1, row1, column2, row2) == HexGrid.distance(rc1, rr1, rc2, rr2),
							"rotation changed a distance"
						)
					end
				end
			end
		end
	end,
})

return tests
