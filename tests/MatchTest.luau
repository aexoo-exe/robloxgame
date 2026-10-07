local Economy = require("../src/shared/Economy")
local Match = require("../src/shared/Match")
local MatchConfig = require("../src/shared/MatchConfig")
local Pve = require("../src/shared/Pve")

local function expectEqual(actual, expected, label)
	assert(actual == expected, string.format("%s: expected %s, got %s", label, tostring(expected), tostring(actual)))
end

-- A match that has played its opening PvE rounds (every player wins them), so its next round is
-- the first PvP round. PvE rounds use neither the pairing generator nor the pairing history, so
-- that round pairs players exactly as round 1 did before PvE rounds existed. It is still stage 1.
local function newPvpMatch(ids: { number }, seed: number)
	local match = Match.new(ids, seed)
	while Pve.isPve(match.round + 1) do
		local results = {}
		for _, fight in Match.startRound(match) do
			table.insert(results, { fight = fight, winner = 1, survivors = { 1, 0 }, healthPercent = { 1, 0 } })
		end
		Match.applyResults(match, results)
	end
	return match
end

-- Results where `a` wins every fight, leaving `survivors` units alive.
local function aWinsAll(fights, survivors)
	local results = {}
	for _, fight in fights do
		table.insert(results, { fight = fight, winner = 1, survivors = { survivors, 0 } })
	end
	return results
end

local function findFight(fights, id)
	for _, fight in fights do
		if fight.a == id or fight.b == id then
			return fight
		end
	end
	return nil
end

local tests = {}

table.insert(tests, {
	name = "players start with 100 HP; losers take stage damage + surviving enemies; draws and wins cost nothing",
	run = function()
		local match = newPvpMatch({ 1, 2, 3, 4 }, 1)
		expectEqual(match.players[1].health, MatchConfig.startingHealth, "starting HP")
		local fights = Match.startRound(match)
		local results = {
			{ fight = fights[1], winner = 1, survivors = { 3, 0 } },
			{ fight = fights[2], winner = nil, survivors = { 2, 2 } },
		}
		local summary = Match.applyResults(match, results)
		local loser = fights[1].b
		expectEqual(match.players[loser].health, 100 - (2 + 3), "stage 1 loss with 3 enemy survivors")
		expectEqual(summary.damage[loser], 5, "reported damage")
		expectEqual(summary.outcomes[fights[1].a], Economy.Outcome.Win, "winner outcome")
		expectEqual(summary.outcomes[loser], Economy.Outcome.Loss, "loser outcome")
		for _, id in { fights[1].a, fights[2].a, fights[2].b } do
			expectEqual(match.players[id].health, 100, "HP of a winner or drawing player")
		end
		expectEqual(summary.outcomes[fights[2].a], Economy.Outcome.Draw, "draw outcome")
	end,
})

table.insert(tests, {
	name = "ghost battles hurt only the real player; the ghost's source is unaffected",
	run = function()
		local match = newPvpMatch({ 1, 2, 3 }, 2)
		local fights = Match.startRound(match)
		local ghostFight
		for _, fight in fights do
			if fight.ghostOf then
				ghostFight = fight
			end
		end
		assert(ghostFight, "3 players should have a ghost fight")
		local results = {}
		for _, fight in fights do
			-- Every real pair draws; the ghost wins with 2 survivors.
			local winner = if fight.ghostOf then 2 else nil
			table.insert(results, { fight = fight, winner = winner, survivors = { 1, 2 } })
		end
		local summary = Match.applyResults(match, results)
		expectEqual(match.players[ghostFight.a].health, 100 - (2 + 2), "ghost battle loser")
		expectEqual(summary.outcomes[ghostFight.a], Economy.Outcome.Loss, "ghost battle counts for the real player")
		expectEqual(match.players[ghostFight.ghostOf].health, 100, "ghost source HP")
		expectEqual(summary.outcomes[ghostFight.ghostOf], Economy.Outcome.Draw, "source's outcome is its own fight")

		-- The real player beating a ghost does not hurt the source either (its own fight is a draw).
		local again = Match.startRound(match)
		local healthBefore = {}
		for id, player in match.players do
			healthBefore[id] = player.health
		end
		local secondResults = {}
		local secondGhost
		for _, fight in again do
			if fight.ghostOf then
				secondGhost = fight
			end
			local winner = if fight.ghostOf then 1 else nil
			table.insert(secondResults, { fight = fight, winner = winner, survivors = { 3, 0 } })
		end
		Match.applyResults(match, secondResults)
		for id, player in match.players do
			expectEqual(player.health, healthBefore[id], "HP of player " .. id .. " after a won ghost battle")
		end
		assert(secondGhost.a ~= ghostFight.a, "the same player got a ghost twice in a row")
	end,
})

table.insert(tests, {
	name = "simultaneous eliminations are placed by tie-break and the last player wins",
	run = function()
		local match = newPvpMatch({ 1, 2, 3, 4 }, 3)
		match.players[1].health = 3
		match.players[2].health = 9
		local fights = Match.startRound(match)
		-- Players 1 and 2 both lose with 8 enemy survivors (2 + 8 = 10 damage): 1 ends at -7, 2 at -1.
		local results = {}
		for _, fight in fights do
			local loserIsA = fight.a == 1 or fight.a == 2
			local loserIsB = fight.b == 1 or fight.b == 2
			assert(not (loserIsA and loserIsB), "seed paired the two low players together; pick another seed")
			local winner = if loserIsA then 2 elseif loserIsB then 1 else 1
			table.insert(results, { fight = fight, winner = winner, survivors = { 8, 8 } })
		end
		local summary = Match.applyResults(match, results)
		expectEqual(#summary.eliminated, 2, "eliminated count")
		expectEqual(summary.eliminated[1], 2, "-1 HP ranks above -7 HP")
		expectEqual(match.players[2].placement, 3, "better eliminated player")
		expectEqual(match.players[1].placement, 4, "worse eliminated player")
		assert(not match.finished, "match should continue with 2 players")

		-- Eliminated players are no longer paired.
		local next = Match.startRound(match)
		expectEqual(#next, 1, "fights with 2 players left")
		assert(findFight(next, 1) == nil and findFight(next, 2) == nil, "an eliminated player was paired")

		match.players[next[1].b].health = 1
		Match.applyResults(match, aWinsAll(next, 1))
		assert(match.finished, "match should end with one player left")
		expectEqual(match.winner, next[1].a, "winner")
		expectEqual(match.players[next[1].a].placement, 1, "winner placement")
		expectEqual(match.players[next[1].b].placement, 2, "runner-up placement")
	end,
})

table.insert(tests, {
	name = "if the last players are eliminated together, the best of them wins",
	run = function()
		local match = newPvpMatch({ 1, 2 }, 4)
		match.players[1].health = 1
		match.players[2].health = 1
		match.players[2].connected = false
		match.players[2].missedRounds = MatchConfig.leaverGraceRounds - 1
		local fights = Match.startRound(match)
		-- Player 2 has been gone long enough to drop to 0; player 1 loses and also drops to 0 or below.
		local winnerSide = if fights[1].a == 2 then 1 else 2
		Match.applyResults(match, { { fight = fights[1], winner = winnerSide, survivors = { 0, 0 } } })
		assert(match.finished, "match should end")
		expectEqual(match.winner, 2, "the leaver at 0 HP beats the player at -1 HP")
		expectEqual(match.players[2].placement, 1, "winner placement")
		expectEqual(match.players[1].placement, 2, "second placement")
	end,
})

table.insert(tests, {
	name = "leavers: HP drops to 0 after 2 complete missed rounds; reconnecting in time resets it",
	run = function()
		local match = newPvpMatch({ 1, 2, 3, 4 }, 5)
		local function playDrawnRound()
			local fights = Match.startRound(match)
			local results = {}
			for _, fight in fights do
				table.insert(results, { fight = fight, winner = nil, survivors = { 1, 1 } })
			end
			return Match.applyResults(match, results)
		end

		-- Leaves during the first PvP round: that round does not count.
		Match.startRound(match)
		Match.setConnected(match, 4, false)
		Match.applyResults(match, {})
		expectEqual(match.players[4].health, 100, "after the round they left in")
		playDrawnRound() -- round 2: first complete missed round
		expectEqual(match.players[4].health, 100, "after 1 missed round")
		assert(not match.players[4].eliminated, "eliminated too early")
		local summary = playDrawnRound() -- round 3: second complete missed round
		assert(match.players[4].eliminated, "leaver should be eliminated after 2 missed rounds")
		expectEqual(match.players[4].health, 0, "leaver HP")
		expectEqual(summary.eliminated[1], 4, "eliminated list")
		expectEqual(match.players[4].placement, 4, "leaver placement")

		-- Player 3 leaves for one round and comes back during the next: no penalty.
		Match.setConnected(match, 3, false)
		playDrawnRound()
		Match.startRound(match)
		Match.setConnected(match, 3, true)
		Match.applyResults(match, {})
		playDrawnRound()
		assert(not match.players[3].eliminated, "reconnected player was eliminated")
		expectEqual(match.players[3].missedRounds, 0, "missed rounds after reconnecting")
	end,
})

table.insert(tests, {
	name = "a disconnected player stays pairable and takes normal damage during the grace period",
	run = function()
		local match = newPvpMatch({ 1, 2 }, 6)
		Match.setConnected(match, 2, false)
		local fights = Match.startRound(match)
		assert(findFight(fights, 2), "disconnected player was not paired")
		local side = if fights[1].a == 2 then 2 else 1
		Match.applyResults(match, { { fight = fights[1], winner = side, survivors = { 3, 3 } } })
		expectEqual(match.players[2].health, 95, "disconnected player takes 2 + 3 damage")
	end,
})

table.insert(tests, {
	name = "practice match: one player fights the scripted enemy and the match ends when they fall",
	run = function()
		local match = newPvpMatch({ 7 }, 7)
		assert(match.practice, "single participant should be a practice match")
		local fights = Match.startRound(match)
		assert(#fights == 1 and fights[1].a == 7 and fights[1].b == nil and fights[1].ghostOf == nil, "practice fight")
		Match.applyResults(match, { { fight = fights[1], winner = 2, survivors = { 0, 4 } } })
		expectEqual(match.players[7].health, 94, "practice loss: 2 + 4")
		assert(not match.finished, "practice match ended early")
		match.players[7].health = 1
		Match.startRound(match)
		Match.applyResults(match, { { fight = fights[1], winner = 2, survivors = { 0, 1 } } })
		assert(match.finished and match.players[7].eliminated, "practice match should end on elimination")
		expectEqual(match.players[7].placement, 1, "practice placement")
	end,
})

return tests
