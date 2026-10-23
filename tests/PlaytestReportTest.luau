-- The match log (MatchLog) and the playtest report (scripts/lib/playtest-data) on sim data: one lean
-- sim match (sim/LeanMatch) produces a record in the server's shape, and the report runs on it.

local Bot = require("../src/shared/Bot")
local LeanMatch = require("../sim/LeanMatch")
local MatchLog = require("../src/shared/MatchLog")
local PlaytestData = require("../scripts/lib/playtest-data")

local function expectEqual(actual, expected, label)
	assert(actual == expected, string.format("%s: expected %s, got %s", label, tostring(expected), tostring(actual)))
end

local tests = {}

table.insert(tests, {
	name = "MatchLog: a record keeps humans only, with snapshots every 5 rounds and unit totals",
	run = function()
		local log = MatchLog.new("m1", 100)
		MatchLog.addPlayer(log, 7)
		MatchLog.addPlayer(log, -1001, true)
		MatchLog.bought(log, 7, "cinder_arc", 1)
		MatchLog.spent(log, 7, "reroll", 2)
		MatchLog.spent(log, 7, "xp", 4)
		for round = 1, 10 do
			MatchLog.combat(log, 7, round, 3, { { unitType = "cinder_arc", starLevel = 2 } }, { "Hunters:1" })
		end
		MatchLog.placed(log, 7, 3)
		MatchLog.quit(log, 7, 9, "Combat")
		local record = MatchLog.finish(log, { endedAt = 400, rounds = 10, botDifficulty = "easy" })
		expectEqual(record.durationSeconds, 300, "duration")
		expectEqual(record.humans, 1, "humans")
		expectEqual(record.bots, 1, "bots")
		expectEqual(#record.players, 1, "logged players")
		local player = record.players[1]
		expectEqual(player.goldSpent, 7, "gold spent")
		expectEqual(player.rerolls, 1, "rerolls")
		expectEqual(player.xpBought, 1, "xp bought")
		expectEqual(#player.snapshots, 2, "snapshots (rounds 5 and 10)")
		expectEqual(player.finalBoard[1], "cinder_arc:2", "final board")
		expectEqual(player.quit.phase, "Combat", "quit phase")
		local totals = MatchLog.unitTotals(record)
		expectEqual(totals.cinder_arc.picked, 1, "picked")
		expectEqual(totals.cinder_arc.top4, 1, "top 4")
	end,
})

table.insert(tests, {
	name = "playtest report: runs on a sim match log and lists units, traits and boards",
	run = function()
		local _, rounds, record = LeanMatch.play({
			players = 4,
			matchIndex = 3,
			log = true,
			botDifficulty = "normal",
			policyFor = function(seat)
				return Bot.policies[seat]
			end,
		})
		assert(record, "no record")
		expectEqual(record.v, MatchLog.VERSION, "record version")
		expectEqual(record.rounds, rounds, "rounds")
		expectEqual(#record.players, 4, "logged seats")
		local placements = {}
		for _, player in record.players do
			assert(player.placement >= 1 and player.placement <= 4, "placement out of range")
			placements[player.placement] = true
			assert(#player.fielded > 0, "a seat fielded nothing")
		end
		expectEqual(placements[1], true, "a winner")

		local funnel = { joined = 10, intro_finished = 8, queued = 6, first_match_started = 6 }
		local summary = PlaytestData.summarize({ record }, funnel)
		expectEqual(summary.matches, 1, "matches")
		expectEqual(summary.players, 4, "players")
		expectEqual(summary.funnel[2].count, 8, "funnel step 2")
		assert(math.abs(summary.funnel[2].drop - 0.2) < 1e-9, "funnel drop")
		assert(#summary.units > 0, "no unit rows")
		for _, unit in summary.units do
			assert(unit.pickRate >= 0 and unit.pickRate <= 1, "pick rate out of range")
			assert(unit.top4Rate == nil or (unit.top4Rate >= 0 and unit.top4Rate <= 1), "top 4 rate out of range")
		end
		assert(#summary.boards > 0, "no final boards")
		local text = PlaytestData.format(summary)
		assert(string.find(text, "New-player funnel", 1, true), "report text")
		local csv = PlaytestData.csv(summary, { record })
		assert(string.find(csv["players.csv"], "sim-3", 1, true), "players.csv rows")
	end,
})

return tests
