local Pairing = require("../src/shared/Pairing")
local SeededRandom = require("../src/shared/SeededRandom")

local function ids(count)
	local list = {}
	for i = 1, count do
		table.insert(list, i * 10)
	end
	return list
end

-- Plays `rounds` rounds of pairing for `count` players and calls check(fights, history, round)
-- before each round is recorded.
local function playRounds(count, rounds, seed, check)
	local players = ids(count)
	local history = Pairing.newHistory()
	local rng = SeededRandom.new(seed)
	for round = 1, rounds do
		local fights = Pairing.pair(players, history, rng)
		check(fights, history, round, players)
		Pairing.recordRound(history, fights)
	end
end

local tests = {}

table.insert(tests, {
	name = "2-8 players: everyone fights exactly once; odd counts get exactly one valid ghost",
	run = function()
		for count = 2, 8 do
			playRounds(count, 20, count, function(fights, _, round, players)
				local seen = {}
				local ghosts = 0
				for _, fight in fights do
					for _, id in { fight.a, fight.b } do
						assert(not seen[id], string.format("%d players, round %d: %d fights twice", count, round, id))
						seen[id] = true
					end
					if fight.ghostOf then
						ghosts += 1
						assert(fight.b == nil, "a ghost fight also has a real opponent")
						assert(fight.ghostOf ~= fight.a, "a player fought their own ghost")
						assert(table.find(players, fight.ghostOf), "ghost source is not an active player")
					else
						assert(fight.b, "fight without an opponent")
					end
				end
				for _, id in players do
					assert(seen[id], string.format("%d players, round %d: %d has no fight", count, round, id))
				end
				assert(ghosts == count % 2, string.format("%d players: expected %d ghost fights", count, count % 2))
			end)
		end
	end,
})

table.insert(tests, {
	name = "no immediate rematches for 3+ players; 2 players must rematch",
	run = function()
		for count = 3, 8 do
			for seed = 1, 5 do
				playRounds(count, 30, seed, function(fights, history)
					for _, fight in fights do
						if fight.b then
							local last = history[fight.a] and history[fight.a].recent[1]
							assert(last ~= fight.b, string.format("%d players: immediate rematch", count))
						end
					end
				end)
			end
		end
		playRounds(2, 5, 1, function(fights)
			assert(#fights == 1 and fights[1].b ~= nil, "2 players should always fight each other")
		end)
	end,
})

table.insert(tests, {
	name = "6 and 8 players avoid opponents from the last 2 rounds",
	run = function()
		for _, count in { 6, 8 } do
			for seed = 1, 5 do
				playRounds(count, 30, seed, function(fights, history)
					for _, fight in fights do
						local recent = history[fight.a] and history[fight.a].recent or {}
						assert(
							recent[1] ~= fight.b and recent[2] ~= fight.b,
							string.format("%d players: repeated an opponent from the last 2 rounds", count)
						)
					end
				end)
			end
		end
	end,
})

table.insert(tests, {
	name = "the 2-round preference is relaxed when it cannot be met",
	run = function()
		-- 4 players have three possible pairings:
		--   10-20 & 30-40: both are rematches from last round
		--   10-30 & 20-40: 10 fought 30 two rounds ago
		--   10-40 & 20-30: 40 fought 10 two rounds ago
		-- No pairing avoids the last 2 rounds, so the rule relaxes, but never into a rematch.
		local history = {
			[10] = { recent = { 20, 30 }, hadGhost = false },
			[20] = { recent = { 10, 40 }, hadGhost = false },
			[30] = { recent = { 40, 10 }, hadGhost = false },
			[40] = { recent = { 30, 10 }, hadGhost = false },
		}
		for seed = 1, 20 do
			local fights = Pairing.pair({ 10, 20, 30, 40 }, history, SeededRandom.new(seed))
			assert(#fights == 2, "expected two fights")
			for _, fight in fights do
				local rematch = history[fight.a].recent[1] == fight.b or history[fight.b].recent[1] == fight.a
				assert(not rematch, "made an avoidable immediate rematch")
			end
		end
	end,
})

table.insert(tests, {
	name = "ghosts: never twice in a row and never the last opponent's board, for 3-7 players",
	run = function()
		for _, count in { 3, 5, 7 } do
			for seed = 1, 5 do
				playRounds(count, 30, seed, function(fights, history)
					for _, fight in fights do
						if fight.ghostOf then
							local entry = history[fight.a]
							assert(
								not (entry and entry.hadGhost),
								string.format("%d players: ghost twice in a row", count)
							)
							assert(
								not (entry and entry.recent[1] == fight.ghostOf),
								string.format("%d players: ghost of last opponent", count)
							)
						end
					end
				end)
			end
		end
	end,
})

table.insert(tests, {
	name = "pairings are randomized among valid options and seeded",
	run = function()
		local seen = {}
		local distinct = 0
		for seed = 1, 20 do
			local fights = Pairing.pair(ids(8), Pairing.newHistory(), SeededRandom.new(seed))
			local opponent = fights[1].b
			if not seen[opponent] then
				seen[opponent] = true
				distinct += 1
			end
		end
		assert(distinct >= 3, "first-round opponents barely vary across seeds")

		local a = Pairing.pair(ids(7), Pairing.newHistory(), SeededRandom.new(5))
		local b = Pairing.pair(ids(7), Pairing.newHistory(), SeededRandom.new(5))
		for i, fight in a do
			assert(fight.a == b[i].a and fight.b == b[i].b and fight.ghostOf == b[i].ghostOf, "same seed differs")
		end
	end,
})

return tests
