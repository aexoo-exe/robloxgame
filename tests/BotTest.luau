local Board = require("../src/shared/Board")
local Bot = require("../src/shared/Bot")
local Match = require("../src/shared/Match")
local PlayerState = require("../src/shared/PlayerState")

local function expectEqual(actual, expected, label)
	assert(actual == expected, string.format("%s: expected %s, got %s", label, tostring(expected), tostring(actual)))
end

local tests = {}

table.insert(tests, {
	name = "server bots: the chosen units end on their cells, within the level cap",
	run = function()
		local state = PlayerState.new(7)
		state.gold = 60
		local memory = Bot.newMemory()
		for _ = 1, 3 do
			local placed = Bot.prepare(state, Bot.policies[1], memory)
			local done = Bot.applyPlacement(state, placed)
			expectEqual(done, #placed, "chosen units on their cells")
			expectEqual(Board.countPlaced(state.board), #placed, "units on the board")
			assert(#placed <= state.level, "more units placed than the level allows")
			for _, unit in placed do
				local real = state.board.units[unit.id]
				assert(real and real.column == unit.column and real.row == unit.row, "unit not on its cell")
			end
			state.gold += 20
		end
	end,
})

table.insert(tests, {
	name = "server bots: units already on the board that are not chosen go back to the bench",
	run = function()
		local state = PlayerState.new(3)
		state.gold = 10
		state.shop = { "cinder_arc", "spurshot", "cinder_arc", "snapfire", "final_argument" }
		assert(PlayerState.buyUnit(state, 1), "buy refused")
		assert(PlayerState.buyUnit(state, 2), "buy refused")
		local units = Board.getUnits(state.board)
		assert(PlayerState.moveUnit(state, units[1].id, { column = 1, row = 1 }), "move refused")
		assert(PlayerState.moveUnit(state, units[2].id, { column = 2, row = 1 }), "move refused")
		-- Field only the second unit, on another cell.
		local done = Bot.applyPlacement(state, { { id = units[2].id, column = 4, row = 4 } })
		expectEqual(done, 1, "chosen units on their cells")
		expectEqual(Board.countPlaced(state.board), 1, "units on the board")
		assert(state.board.units[units[1].id].slot ~= nil, "the unit not chosen is not on the bench")
	end,
})

table.insert(tests, {
	name = "Match.finishNow places the players still in by HP and ends the match",
	run = function()
		local match = Match.new({ 1, -1001, -1002, -1003 }, 5)
		match.players[1].eliminated = true
		match.players[1].placement = 4
		match.players[-1001].health = 40
		match.players[-1002].health = 70
		match.players[-1003].health = 55
		local order = Match.finishNow(match)
		expectEqual(order[1], -1002, "first")
		expectEqual(match.players[-1002].placement, 1, "winner placement")
		expectEqual(match.players[-1003].placement, 2, "second placement")
		expectEqual(match.players[-1001].placement, 3, "third placement")
		expectEqual(match.players[1].placement, 4, "eliminated placement kept")
		expectEqual(match.winner, -1002, "winner")
		assert(match.finished, "match not finished")
	end,
})

return tests
