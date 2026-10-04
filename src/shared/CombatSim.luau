-- Deterministic combat simulation. Takes two boards and a seed, advances in fixed ticks, and
-- returns the units' starting state, a list of events, and the winner.
-- Pure Luau: no Roblox APIs, no task library, no wall-clock time. The same input always gives
-- the same output.
--
-- Field coordinates: side 1 keeps its own board coordinates (rows 1..rows). Side 2's board is
-- rotated half a turn into rows rows+1..rows*2, so both sides face each other.
--
-- The fight ends when one side has no units left. If both sides still have units at maxTicks, the
-- side with the higher remaining health percentage (sum of current health / sum of max health over
-- every unit that entered combat) wins; within `timeoutDrawMargin` of each other it is a draw.
--
-- Per tick, each living unit (in a seeded random order):
--   1. Keeps its target if it is alive and in range, otherwise targets the nearest enemy.
--   2. Attacks if the target is in range and its attack cooldown is ready.
--   3. Otherwise steps one cell along a shortest path of free cells toward a cell in range,
--      once its move cooldown is ready. Units never share a cell.

local HexGrid = if script then require(script.Parent.HexGrid) else require("./HexGrid")
local SeededRandom = if script then require(script.Parent.SeededRandom) else require("./SeededRandom")
local StarLevel = if script then require(script.Parent.StarLevel) else require("./StarLevel")

local CombatSim = {}

export type UnitStats = {
	health: number,
	attackDamage: number,
	attacksPerSecond: number,
	range: number,
	moveSpeed: number,
}

-- A unit placed on a board, in that board's own coordinates.
export type PlacedUnit = {
	id: string,
	unitType: string,
	starLevel: number?, -- 1 if omitted
	column: number,
	row: number,
}

export type Params = {
	boards: { { PlacedUnit } }, -- exactly two: side 1 and side 2
	columns: number,
	rows: number, -- rows per side; the field has rows * 2
	unitTypes: { [string]: UnitStats },
	ticksPerSecond: number,
	maxTicks: number,
	timeoutDrawMargin: number?, -- see the header; 0 if omitted
	seed: number,
}

-- Starting state of a unit, in field coordinates. `index` identifies the unit in events.
export type UnitSummary = {
	index: number,
	side: number,
	id: string,
	unitType: string,
	starLevel: number,
	column: number,
	row: number,
	maxHealth: number,
}

-- kind "Move":   unit moved to column, row
-- kind "Attack": unit hit target for damage, leaving it at health
-- kind "Death":  unit died
export type Event = {
	tick: number,
	kind: string,
	unit: number,
	column: number?,
	row: number?,
	target: number?,
	damage: number?,
	health: number?,
}

export type Result = {
	winner: number?, -- 1 or 2, or nil for a draw
	timedOut: boolean, -- true if the fight reached maxTicks
	survivors: { number }, -- living units per side at the end
	healthPercent: { number }, -- remaining health fraction (0-1) per side at the end
	endTick: number,
	ticksPerSecond: number,
	seed: number,
	units: { UnitSummary },
	events: { Event },
}

function CombatSim.run(params: Params): Result
	local columns = params.columns
	local fieldRows = params.rows * 2
	local rng = SeededRandom.new(params.seed)

	local units = {}
	local summaries = {}
	local occupied = {} -- [cell key] = unit

	local function cellKey(column: number, row: number): number
		return (row - 1) * columns + column
	end

	for side = 1, 2 do
		for _, placed in params.boards[side] do
			local column, row = placed.column, placed.row
			if side == 2 then
				column, row = HexGrid.rotateHalfTurn(column, row, columns, fieldRows)
			end
			-- Star scaling is applied here, once, as the unit enters combat.
			local starLevel = placed.starLevel or 1
			local stats = StarLevel.scaleStats(params.unitTypes[placed.unitType], starLevel)
			local unit = {
				index = #units + 1,
				side = side,
				stats = stats,
				column = column,
				row = row,
				health = stats.health,
				target = nil,
				attackInterval = math.max(1, math.round(params.ticksPerSecond / stats.attacksPerSecond)),
				moveInterval = math.max(1, math.round(params.ticksPerSecond / stats.moveSpeed)),
				attackCooldown = 0,
				moveCooldown = 0,
			}
			table.insert(units, unit)
			occupied[cellKey(column, row)] = unit
			table.insert(summaries, {
				index = unit.index,
				side = side,
				id = placed.id,
				unitType = placed.unitType,
				starLevel = starLevel,
				column = column,
				row = row,
				maxHealth = stats.health,
			})
		end
	end

	local events = {}
	local tick = 0

	local function distanceBetween(a, b): number
		return HexGrid.distance(a.column, a.row, b.column, b.row)
	end

	local function sideAlive(side: number): boolean
		for _, unit in units do
			if unit.side == side and unit.health > 0 then
				return true
			end
		end
		return false
	end

	local function findNearestEnemy(unit)
		local best = {}
		local bestDistance = math.huge
		for _, other in units do
			if other.side ~= unit.side and other.health > 0 then
				local distance = distanceBetween(unit, other)
				if distance < bestDistance then
					best = { other }
					bestDistance = distance
				elseif distance == bestDistance then
					table.insert(best, other)
				end
			end
		end
		if #best == 0 then
			return nil
		end
		return best[SeededRandom.nextInt(rng, #best)]
	end

	local function isFreeCell(column: number, row: number): boolean
		return column >= 1
			and column <= columns
			and row >= 1
			and row <= fieldRows
			and occupied[cellKey(column, row)] == nil
	end

	-- Breadth-first search over free cells for the shortest path to any cell within attack range
	-- of the target. Returns the first step of that path, or nil if no such path exists.
	local function findStep(unit, target): (number?, number?)
		local range = unit.stats.range
		local visited = { [cellKey(unit.column, unit.row)] = true }
		local queue = {}
		for _, neighbor in HexGrid.neighbors(unit.column, unit.row) do
			local column, row = neighbor[1], neighbor[2]
			if isFreeCell(column, row) then
				visited[cellKey(column, row)] = true
				table.insert(queue, { column = column, row = row, firstColumn = column, firstRow = row })
			end
		end

		local head = 1
		while head <= #queue do
			local node = queue[head]
			head += 1
			if HexGrid.distance(node.column, node.row, target.column, target.row) <= range then
				return node.firstColumn, node.firstRow
			end
			for _, neighbor in HexGrid.neighbors(node.column, node.row) do
				local column, row = neighbor[1], neighbor[2]
				if isFreeCell(column, row) and not visited[cellKey(column, row)] then
					visited[cellKey(column, row)] = true
					table.insert(
						queue,
						{ column = column, row = row, firstColumn = node.firstColumn, firstRow = node.firstRow }
					)
				end
			end
		end
		return nil, nil
	end

	local function act(unit)
		unit.attackCooldown -= 1
		unit.moveCooldown -= 1

		local target = unit.target
		if target == nil or target.health <= 0 or distanceBetween(unit, target) > unit.stats.range then
			target = findNearestEnemy(unit)
			unit.target = target
		end
		if target == nil then
			return
		end

		if distanceBetween(unit, target) <= unit.stats.range then
			if unit.attackCooldown <= 0 then
				local damage = unit.stats.attackDamage
				target.health = math.max(0, target.health - damage)
				unit.attackCooldown = unit.attackInterval
				table.insert(events, {
					tick = tick,
					kind = "Attack",
					unit = unit.index,
					target = target.index,
					damage = damage,
					health = target.health,
				})
				if target.health == 0 then
					occupied[cellKey(target.column, target.row)] = nil
					table.insert(events, { tick = tick, kind = "Death", unit = target.index })
				end
			end
		elseif unit.moveCooldown <= 0 then
			local column, row = findStep(unit, target)
			if column and row then
				occupied[cellKey(unit.column, unit.row)] = nil
				occupied[cellKey(column, row)] = unit
				unit.column = column
				unit.row = row
				unit.moveCooldown = unit.moveInterval
				table.insert(events, { tick = tick, kind = "Move", unit = unit.index, column = column, row = row })
			end
		end
	end

	while tick < params.maxTicks and sideAlive(1) and sideAlive(2) do
		tick += 1
		local order = {}
		for _, unit in units do
			if unit.health > 0 then
				table.insert(order, unit)
			end
		end
		SeededRandom.shuffle(rng, order)
		for _, unit in order do
			if unit.health > 0 then
				act(unit)
			end
		end
	end

	local survivors = { 0, 0 }
	local currentHealth = { 0, 0 }
	local maxHealth = { 0, 0 }
	for _, unit in units do
		currentHealth[unit.side] += unit.health
		maxHealth[unit.side] += unit.stats.health
		if unit.health > 0 then
			survivors[unit.side] += 1
		end
	end
	local healthPercent = {
		if maxHealth[1] > 0 then currentHealth[1] / maxHealth[1] else 0,
		if maxHealth[2] > 0 then currentHealth[2] / maxHealth[2] else 0,
	}

	local winner = nil
	local timedOut = survivors[1] > 0 and survivors[2] > 0
	if timedOut then
		local margin = params.timeoutDrawMargin or 0
		if healthPercent[1] - healthPercent[2] > margin then
			winner = 1
		elseif healthPercent[2] - healthPercent[1] > margin then
			winner = 2
		end
	elseif survivors[1] > 0 then
		winner = 1
	elseif survivors[2] > 0 then
		winner = 2
	end

	return {
		winner = winner,
		timedOut = timedOut,
		survivors = survivors,
		healthPercent = healthPercent,
		endTick = tick,
		ticksPerSecond = params.ticksPerSecond,
		seed = params.seed,
		units = summaries,
		events = events,
	}
end

return CombatSim
