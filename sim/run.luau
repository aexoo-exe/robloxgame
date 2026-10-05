-- Headless match simulation: plays full 8-bot matches with the real pure modules (Match, Pairing,
-- PlayerState, Shop, CombatSim) and reports pacing. No Roblox Studio needed.
--   lune run sim/run.luau [matches=200] [players=8]
-- Match time is estimated from the configured phase timers: Preparation + Combat (the round's
-- longest fight + padding) + Results per round. Lobby and final-placement screens are excluded.

local process = require("@lune/process")

local Bot = require("./Bot")
local BoardConfig = require("../src/shared/BoardConfig")
local CombatConfig = require("../src/shared/CombatConfig")
local CombatSim = require("../src/shared/CombatSim")
local Match = require("../src/shared/Match")
local MatchConfig = require("../src/shared/MatchConfig")
local PlayerState = require("../src/shared/PlayerState")
local UnitConfig = require("../src/shared/UnitConfig")

local MATCHES = tonumber(process.args[1]) or 200
local PLAYERS = tonumber(process.args[2]) or 8

local function runFight(fight, boards, seed)
	local sideB = if fight.b then boards[fight.b] elseif fight.ghostOf then boards[fight.ghostOf] else {}
	return CombatSim.run({
		boards = { boards[fight.a], sideB },
		columns = BoardConfig.columns,
		rows = BoardConfig.rows,
		unitTypes = UnitConfig,
		ticksPerSecond = CombatConfig.ticksPerSecond,
		maxTicks = MatchConfig.combatMaxDuration * CombatConfig.ticksPerSecond,
		timeoutDrawMargin = CombatConfig.timeoutDrawMargin,
		seed = seed,
	})
end

-- Per-fight length and per-character (1-star) damage, casts, dashes that moved the caster, and
-- seconds survived (until death or the end of the fight), across every simulated fight.
local fightLength = { count = 0, sum = 0, shortest = math.huge, longest = 0 }
local unitStats = {}

local function recordFight(result)
	local seconds = result.endTick / result.ticksPerSecond
	fightLength.count += 1
	fightLength.sum += seconds
	fightLength.shortest = math.min(fightLength.shortest, seconds)
	fightLength.longest = math.max(fightLength.longest, seconds)

	local oneStar = {}
	local deathTick = {}
	for _, unit in result.units do
		if unit.starLevel == 1 then
			oneStar[unit.index] = unit.unitType
			local stats = unitStats[unit.unitType]
				or { fights = 0, damage = 0, casts = 0, dashes = 0, aliveSeconds = 0, fightSeconds = 0 }
			stats.fights += 1
			stats.fightSeconds += seconds
			unitStats[unit.unitType] = stats
		end
	end
	for _, event in result.events do
		local unitType = oneStar[event.unit]
		if unitType then
			if event.kind == "Attack" or event.kind == "Damage" then
				unitStats[unitType].damage += event.damage
			elseif event.kind == "Cast" then
				unitStats[unitType].casts += 1
			elseif event.kind == "Dash" then
				unitStats[unitType].dashes += 1
			elseif event.kind == "Death" then
				deathTick[event.unit] = event.tick
			end
		end
	end
	for index, unitType in oneStar do
		unitStats[unitType].aliveSeconds += (deathTick[index] or result.endTick) / result.ticksPerSecond
	end
end

-- How often the winner's final board fields 2-star and 3-star units, by cost tier.
local winnerStars = { boards = 0, twoStar = {}, threeStar = {} }

local function recordWinnerBoard(board)
	winnerStars.boards += 1
	local seen2, seen3 = {}, {}
	for _, unit in board do
		local cost = UnitConfig[unit.unitType].cost
		if unit.starLevel == 2 then
			seen2[cost] = true
		elseif unit.starLevel == 3 then
			seen3[cost] = true
		end
	end
	for cost = 1, 5 do
		winnerStars.twoStar[cost] = (winnerStars.twoStar[cost] or 0) + (if seen2[cost] then 1 else 0)
		winnerStars.threeStar[cost] = (winnerStars.threeStar[cost] or 0) + (if seen3[cost] then 1 else 0)
	end
end

local function playMatch(matchIndex: number)
	local ids = {}
	local states = {}
	local policies = {}
	for i = 1, PLAYERS do
		ids[i] = i
		states[i] = PlayerState.new(matchIndex * 1000 + i)
		policies[i] = Bot.policies[(i + matchIndex) % #Bot.policies + 1]
	end
	local match = Match.new(ids, matchIndex)
	local stats = { seconds = 0, fights = 0, timeouts = 0, longestFight = 0 }
	local lastBoards = {}

	while not match.finished do
		local boards = {}
		for _, id in Match.activeIds(match) do
			PlayerState.startPreparation(states[id])
			boards[id] = Bot.prepare(states[id], policies[id])
			lastBoards[id] = boards[id]
		end

		local fights = Match.startRound(match)
		local results = {}
		local longestTicks = 0
		for index, fight in fights do
			local result = runFight(fight, boards, matchIndex * 100000 + match.round * 100 + index)
			recordFight(result)
			longestTicks = math.max(longestTicks, result.endTick)
			stats.fights += 1
			if result.timedOut then
				stats.timeouts += 1
			end
			table.insert(results, { fight = fight, winner = result.winner, survivors = result.survivors })
		end
		local combatSeconds = longestTicks / CombatConfig.ticksPerSecond
		stats.longestFight = math.max(stats.longestFight, combatSeconds)
		stats.seconds += MatchConfig.preparationDuration + combatSeconds + CombatConfig.endPadding + MatchConfig.resultsDuration

		local summary = Match.applyResults(match, results)
		for id, outcome in summary.outcomes do
			PlayerState.recordCombat(states[id], outcome)
		end
		assert(match.round < 200, "match did not end")
	end
	recordWinnerBoard(lastBoards[match.winner])

	return {
		rounds = match.round,
		seconds = stats.seconds,
		winnerLevel = states[match.winner].level,
		winnerPolicy = policies[match.winner].name,
		fights = stats.fights,
		timeouts = stats.timeouts,
		longestFight = stats.longestFight,
	}
end

local totals = { rounds = 0, seconds = 0, fights = 0, timeouts = 0, winnerLevel = 0 }
local maxRounds, minRounds, maxSeconds, longestFight = 0, math.huge, 0, 0
local winnerLevels, policyWins, roundCounts = {}, {}, {}
for matchIndex = 1, MATCHES do
	local result = playMatch(matchIndex)
	totals.rounds += result.rounds
	totals.seconds += result.seconds
	totals.fights += result.fights
	totals.timeouts += result.timeouts
	totals.winnerLevel += result.winnerLevel
	maxRounds = math.max(maxRounds, result.rounds)
	minRounds = math.min(minRounds, result.rounds)
	maxSeconds = math.max(maxSeconds, result.seconds)
	longestFight = math.max(longestFight, result.longestFight)
	winnerLevels[result.winnerLevel] = (winnerLevels[result.winnerLevel] or 0) + 1
	policyWins[result.winnerPolicy] = (policyWins[result.winnerPolicy] or 0) + 1
	roundCounts[result.rounds] = (roundCounts[result.rounds] or 0) + 1
end

print(string.format("%d matches, %d players each", MATCHES, PLAYERS))
print(
	string.format("Final round: average %.1f, shortest %d, longest %d", totals.rounds / MATCHES, minRounds, maxRounds)
)
print(
	string.format(
		"Match length: average %.1f min, longest %.1f min (timers only; no lobby or end screen)",
		totals.seconds / MATCHES / 60,
		maxSeconds / 60
	)
)
print(string.format("Winner level: average %.1f", totals.winnerLevel / MATCHES))
local levelLine = {}
for level = 2, 10 do
	if winnerLevels[level] then
		table.insert(levelLine, string.format("L%d: %d", level, winnerLevels[level]))
	end
end
print("  " .. table.concat(levelLine, ", "))
print(
	string.format(
		"Fights hitting the %ds cap: %d of %d (%.1f%%); longest round's combat %.1fs",
		MatchConfig.combatMaxDuration,
		totals.timeouts,
		totals.fights,
		totals.timeouts / totals.fights * 100,
		longestFight
	)
)
local roundLine = {}
for rounds = minRounds, maxRounds do
	if roundCounts[rounds] then
		table.insert(roundLine, string.format("%d: %d", rounds, roundCounts[rounds]))
	end
end
print("Final round distribution: " .. table.concat(roundLine, ", "))
local policyLine = {}
for name, wins in policyWins do
	table.insert(policyLine, string.format("%s %d", name, wins))
end
table.sort(policyLine)
print("Wins by bot strategy: " .. table.concat(policyLine, ", "))
print(
	string.format(
		"Fight length: average %.1fs, shortest %.1fs, longest %.1fs over %d fights",
		fightLength.sum / fightLength.count,
		fightLength.shortest,
		fightLength.longest,
		fightLength.count
	)
)
print("Winner's final board, share of matches with at least one unit of that tier at:")
local starLine2, starLine3 = {}, {}
for cost = 1, 5 do
	table.insert(starLine2, string.format("%dc %.0f%%", cost, winnerStars.twoStar[cost] / winnerStars.boards * 100))
	table.insert(starLine3, string.format("%dc %.0f%%", cost, winnerStars.threeStar[cost] / winnerStars.boards * 100))
end
print("  2-star: " .. table.concat(starLine2, ", "))
print("  3-star: " .. table.concat(starLine3, ", "))
print("1-star characters (per fight they appeared in): average damage dealt, casts, seconds survived")
print("(share of the fight), and for dashers how often a cast's dash moved them")
local names = {}
for name in unitStats do
	table.insert(names, name)
end
table.sort(names, function(a, b)
	return UnitConfig[a].cost < UnitConfig[b].cost or (UnitConfig[a].cost == UnitConfig[b].cost and a < b)
end)
for _, name in names do
	local stats = unitStats[name]
	local dashLine = ""
	for _, effect in UnitConfig[name].ability.effects do
		if effect.type == "DASH" and stats.casts > 0 then
			dashLine = string.format(", dash moved %.0f%% of casts", stats.dashes / stats.casts * 100)
		end
	end
	print(
		string.format(
			"  %-7s (%d) %6.0f damage, %4.2f casts, %4.1fs alive (%.0f%%)%s  [%d fights]",
			name,
			UnitConfig[name].cost,
			stats.damage / stats.fights,
			stats.casts / stats.fights,
			stats.aliveSeconds / stats.fights,
			stats.aliveSeconds / stats.fightSeconds * 100,
			dashLine,
			stats.fights
		)
	)
end
