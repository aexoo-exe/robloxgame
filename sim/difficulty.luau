-- Bot difficulty check: plays 6-player matches (the server fills Play-pad matches to
-- MatchConfig.botFillTo) where seat 1 is the new-player stand-in (Bot.newPlayerPolicy) and the other
-- seats are bots of one difficulty, and reports how often the new player places in the top 4.
-- Target for easy bots: about 40-60%. Prints summaries only.
--   lune run sim/difficulty.luau [matches=60] [easy|normal|both|mixed]
-- "mixed" seats 3 easy and 2 normal bots with the new player, to compare easy and normal directly.
-- The match is played like sim/run.luau and the server (Match, PlayerState, CombatSim, traits, PvE).

local process = require("@lune/process")

local Board = require("../src/shared/Board")
local BoardConfig = require("../src/shared/BoardConfig")
local Bot = require("../src/shared/Bot")
local CombatConfig = require("../src/shared/CombatConfig")
local CombatSim = require("../src/shared/CombatSim")
local Items = require("../src/shared/Items")
local Match = require("../src/shared/Match")
local MatchConfig = require("../src/shared/MatchConfig")
local PlayerState = require("../src/shared/PlayerState")
local Pve = require("../src/shared/Pve")
local Traits = require("../src/shared/Traits")
local UnitConfig = require("../src/shared/UnitConfig")
local UnitPool = require("../src/shared/UnitPool")

local MATCHES = tonumber(process.args[1]) or 60
local MODE = process.args[2] or "both"
local PLAYERS = 6

local function policyFor(mode: string, seat: number)
	if seat == 1 then
		return Bot.newPlayerPolicy
	end
	if mode == "mixed" then
		return if seat <= 4 then Bot.easyPolicies[seat % #Bot.easyPolicies + 1] else Bot.policies[seat]
	elseif mode == "easy" then
		return Bot.easyPolicies[seat % #Bot.easyPolicies + 1]
	end
	return if seat == 3 then Bot.traitPolicy else Bot.policies[(seat - 1) % #Bot.policies + 1]
end

local function runFight(fight, boards, seed, match)
	local sideB
	if fight.pve then
		sideB = Pve.enemyBoard(match.theme, match.round)
	else
		sideB = if fight.b then boards[fight.b] elseif fight.ghostOf then boards[fight.ghostOf] else {}
	end
	local startBonuses, traitSetups = Traits.combatParams(boards[fight.a], sideB, fight.pve ~= nil)
	return CombatSim.run({
		startBonuses = startBonuses,
		traits = traitSetups,
		boards = { boards[fight.a], sideB },
		columns = BoardConfig.columns,
		rows = BoardConfig.rows,
		unitTypes = if fight.pve then Pve.unitTypes(match.theme) else UnitConfig,
		ticksPerSecond = CombatConfig.ticksPerSecond,
		maxTicks = MatchConfig.combatMaxDuration * CombatConfig.ticksPerSecond,
		timeoutDrawMargin = CombatConfig.timeoutDrawMargin,
		seed = seed,
	})
end

-- Plays one match; returns placements by seat and the number of rounds.
local function playMatch(mode: string, matchIndex: number): ({ [number]: number }, number)
	local ids, states, policies, memories = {}, {}, {}, {}
	local pool = UnitPool.new()
	for seat = 1, PLAYERS do
		ids[seat] = seat
		states[seat] = PlayerState.new(matchIndex * 1000 + seat, pool)
		PlayerState.grantStartingUnits(states[seat])
		policies[seat] = policyFor(mode, seat)
		memories[seat] = Bot.newMemory(matchIndex * 7 + seat)
	end
	local match = Match.new(ids, matchIndex)
	while not match.finished do
		local round = match.round + 1
		local boards = {}
		for _, id in Match.activeIds(match) do
			if Pve.preparationDuration(round) > 0 then
				PlayerState.startPreparation(states[id])
				boards[id] = Bot.prepare(states[id], policies[id], memories[id])
			else
				boards[id] = Board.getPlacedUnits(states[id].board)
			end
		end
		local results = {}
		for index, fight in Match.startRound(match) do
			local result = runFight(fight, boards, matchIndex * 100000 + match.round * 100 + index, match)
			table.insert(results, {
				fight = fight,
				winner = result.winner,
				survivors = result.survivors,
				healthPercent = result.healthPercent,
				traitGold = { result.traitResults[1].gold, result.traitResults[2].gold },
			})
		end
		local summary = Match.applyResults(match, results)
		for id, outcome in summary.outcomes do
			PlayerState.recordCombat(states[id], outcome)
		end
		for id, gold in summary.traitGold do
			PlayerState.grantGold(states[id], gold)
		end
		for id, reward in summary.pve do
			PlayerState.recordPve(states[id], reward.gold)
		end
		for _, id in summary.eliminated do
			PlayerState.releaseAll(states[id])
		end
		local offerSize = Items.offerSize(match.round)
		if offerSize > 0 and not match.finished then
			for _, id in Match.activeIds(match) do
				PlayerState.offerItems(states[id], offerSize)
			end
		end
		assert(match.round < 200, "match did not end")
	end
	local placements = {}
	for id, player in match.players do
		placements[id] = player.placement or PLAYERS
	end
	return placements, match.round
end

local function report(mode: string)
	local top4, placementSum, rounds = 0, 0, 0
	local bySeat = {}
	for matchIndex = 1, MATCHES do
		local placements, matchRounds = playMatch(mode, matchIndex)
		rounds += matchRounds
		if placements[1] <= 4 then
			top4 += 1
		end
		placementSum += placements[1]
		for seat = 2, PLAYERS do
			local name = policyFor(mode, seat).name
			local entry = bySeat[name] or { count = 0, sum = 0 }
			entry.count += 1
			entry.sum += placements[seat]
			bySeat[name] = entry
		end
	end
	print(
		string.format(
			"%-6s new player: top 4 in %d%% (%d/%d), average place %.2f; %.1f rounds per match",
			mode,
			math.round(top4 / MATCHES * 100),
			top4,
			MATCHES,
			placementSum / MATCHES,
			rounds / MATCHES
		)
	)
	local names = {}
	for name in bySeat do
		table.insert(names, name)
	end
	table.sort(names)
	for _, name in names do
		print(string.format("         %-12s average place %.2f", name, bySeat[name].sum / bySeat[name].count))
	end
end

for _, mode in { "easy", "normal", "mixed" } do
	if MODE == mode or (MODE == "both" and mode ~= "mixed") then
		report(mode)
	end
end
