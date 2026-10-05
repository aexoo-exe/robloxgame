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
local TraitConfig = require("../src/shared/TraitConfig")
local Traits = require("../src/shared/Traits")
local UnitConfig = require("../src/shared/UnitConfig")
local UnitPool = require("../src/shared/UnitPool")

local MATCHES = tonumber(process.args[1]) or 200
local PLAYERS = tonumber(process.args[2]) or 8
-- "notraits" as the third argument runs the same matches with trait bonuses switched off.
local TRAITS_ON = process.args[3] ~= "notraits"

local function runFight(fight, boards, seed)
	local sideB = if fight.b then boards[fight.b] elseif fight.ghostOf then boards[fight.ghostOf] else {}
	return CombatSim.run({
		startBonuses = if TRAITS_ON then { Traits.bonuses(boards[fight.a]), Traits.bonuses(sideB) } else nil,
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
local fightLength = { count = 0, sum = 0, shortest = math.huge, longest = 0, buckets = { 0, 0, 0, 0 } }
local unitStats = {}

-- Fight length buckets: under 15s, 15-25s, 25-38s, over 38s.
local BUCKET_LIMITS = { 15, 25, 38 }
local BUCKET_NAMES = { "<15s", "15-25s", "25-38s", ">38s" }

local function recordFight(result)
	local seconds = result.endTick / result.ticksPerSecond
	fightLength.count += 1
	fightLength.sum += seconds
	fightLength.shortest = math.min(fightLength.shortest, seconds)
	fightLength.longest = math.max(fightLength.longest, seconds)
	local bucket = #BUCKET_LIMITS + 1
	for i, limit in BUCKET_LIMITS do
		if seconds < limit then
			bucket = i
			break
		end
	end
	fightLength.buckets[bucket] += 1

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

-- Shared pool use: shop rolls that hit an empty tier, and matches in which each tier was empty at
-- the end of some bot's Preparation.
local poolStats = { dryRolls = 0, matchesTierEmpty = { 0, 0, 0, 0, 0 } }

-- 3-star access by cost (1-5): matches with at least one, first round and level per 3-star, total
-- 3-stars, and copies a rerolling bot held of a target it never finished.
local threeStars = {
	matches = { 0, 0, 0, 0, 0 },
	firstRoundSum = { 0, 0, 0, 0, 0 },
	count = { 0, 0, 0, 0, 0 },
	levelSum = { 0, 0, 0, 0, 0 },
	failedCopies = { {}, {}, {}, {}, {} },
}

-- Results by strategy group ("standard" or a rerolling policy's name).
local groups = {}

-- Trait use in each match's final five rounds: boards (one per player per round) with each
-- "Trait level" active, and the final placements of players who had it at least once.
local traitUse = { boards = 0, active = {}, placementSum = {}, players = {} }

-- Rerolling bots by the cost they chase: seats, how many made a 3-star of that cost, the round
-- they first did, and final placements split by whether they did.
local committed = {}
for cost = 1, 5 do
	committed[cost] = { bots = 0, completed = 0, roundSum = 0, placementDone = 0, placementFailed = 0 }
end

-- Top-four boards (final board of each player placing 1-4), by their set of active trait
-- breakpoints.
local compositions = { boards = 0, counts = {} }

-- Active trait breakpoints of a board as a sorted, readable key.
local function traitKey(board): string
	local active = {}
	for _, state in Traits.summary(board) do
		if state.active then
			table.insert(active, state.name .. " " .. state.reached)
		end
	end
	table.sort(active)
	return if #active > 0 then table.concat(active, ", ") else "(no active traits)"
end

-- Timed-out fights: characters present (once per fight), against their presence in all fights,
-- and the active trait sets of both sides.
local timeouts = { fights = 0, allFights = 0, units = {}, unitsAll = {}, traitSets = {} }

local function recordTimeoutData(sides, timedOut: boolean)
	timeouts.allFights += 1
	local present = {}
	for _, board in sides do
		for _, unit in board do
			present[unit.unitType] = true
		end
	end
	for unitType in present do
		timeouts.unitsAll[unitType] = (timeouts.unitsAll[unitType] or 0) + 1
		if timedOut then
			timeouts.units[unitType] = (timeouts.units[unitType] or 0) + 1
		end
	end
	if timedOut then
		timeouts.fights += 1
		for _, board in sides do
			local key = traitKey(board)
			timeouts.traitSets[key] = (timeouts.traitSets[key] or 0) + 1
		end
	end
end

local function recordTraitUse(roundBoards, finalRound: number, placements)
	local had = {}
	for round = math.max(1, finalRound - 4), finalRound do
		for id, board in roundBoards[round] or {} do
			traitUse.boards += 1
			for _, state in Traits.summary(board) do
				if state.active then
					local key = state.name .. " " .. state.reached
					traitUse.active[key] = (traitUse.active[key] or 0) + 1
					had[key] = had[key] or {}
					had[key][id] = true
				end
			end
		end
	end
	for key, ids in had do
		for id in ids do
			traitUse.players[key] = (traitUse.players[key] or 0) + 1
			traitUse.placementSum[key] = (traitUse.placementSum[key] or 0) + placements[id]
		end
	end
end

local function groupOf(policy): string
	return if policy.rerollCost then policy.name else "standard"
end

-- Seat i's strategy: with 8 players, seats 1-4 are standard (cycled), 5-6 reroll 1-cost, 7 reroll
-- 2-cost and 8 reroll 3-cost. Other player counts use standard bots only.
local function policyFor(seat: number, matchIndex: number)
	if PLAYERS == 8 and seat >= 5 then
		return Bot.rerollPolicies[if seat <= 6 then 1 elseif seat == 7 then 2 else 3]
	end
	return Bot.policies[(seat + matchIndex) % #Bot.policies + 1]
end

-- Records the copies a rerolling bot holds of each target it has not finished.
local function recordFailedTargets(state, policy, memory)
	if not policy.rerollCost then
		return
	end
	for _, unitType in memory.targets do
		if not memory.completed[unitType] then
			table.insert(threeStars.failedCopies[policy.rerollCost], (Bot.copiesHeld(state, unitType)))
		end
	end
end

local function playMatch(matchIndex: number)
	local ids = {}
	local states = {}
	local policies = {}
	local memories = {}
	local pool = UnitPool.new()
	for i = 1, PLAYERS do
		ids[i] = i
		states[i] = PlayerState.new(matchIndex * 1000 + i, pool)
		policies[i] = policyFor(i, matchIndex)
		memories[i] = Bot.newMemory()
	end
	local match = Match.new(ids, matchIndex)
	local stats = { seconds = 0, fights = 0, timeouts = 0, longestFight = 0 }
	local lastBoards = {}
	local tierEmptied = {}
	local seenThreeStar = {} -- unit ids already counted
	local matchHasThreeStar = {}
	local roundBoards = {}
	local completedRound = {} -- rerolling bots: round of their first 3-star at their cost

	while not match.finished do
		local boards = {}
		roundBoards[match.round + 1] = boards
		for _, id in Match.activeIds(match) do
			PlayerState.startPreparation(states[id])
			boards[id] = Bot.prepare(states[id], policies[id], memories[id])
			lastBoards[id] = boards[id]
			for cost = 1, 5 do
				if UnitPool.tierRemaining(pool, cost) == 0 then
					tierEmptied[cost] = true
				end
			end
			for _, unit in states[id].board.units do
				local key = id .. ":" .. unit.id
				if unit.starLevel == 3 and not seenThreeStar[key] then
					seenThreeStar[key] = true
					local cost = UnitConfig[unit.unitType].cost
					if policies[id].rerollCost == cost and not completedRound[id] then
						completedRound[id] = match.round + 1
					end
					threeStars.count[cost] += 1
					threeStars.levelSum[cost] += states[id].level
					if not matchHasThreeStar[cost] then
						matchHasThreeStar[cost] = true
						threeStars.matches[cost] += 1
						threeStars.firstRoundSum[cost] += match.round + 1
					end
				end
			end
		end

		local fights = Match.startRound(match)
		local results = {}
		local longestTicks = 0
		for index, fight in fights do
			local result = runFight(fight, boards, matchIndex * 100000 + match.round * 100 + index)
			recordFight(result)
			local sideB = if fight.b then boards[fight.b] elseif fight.ghostOf then boards[fight.ghostOf] else {}
			recordTimeoutData({ boards[fight.a], sideB }, result.timedOut)
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
		for _, id in summary.eliminated do
			recordFailedTargets(states[id], policies[id], memories[id])
			PlayerState.releaseAll(states[id])
		end
		assert(match.round < 200, "match did not end")
	end
	recordWinnerBoard(lastBoards[match.winner])
	for _, id in Match.activeIds(match) do
		recordFailedTargets(states[id], policies[id], memories[id])
	end
	local placements = {}
	for id, player in match.players do
		placements[id] = player.placement
	end
	recordTraitUse(roundBoards, match.round, placements)
	for id, placement in placements do
		local cost = policies[id].rerollCost
		if cost then
			local entry = committed[cost]
			entry.bots += 1
			if completedRound[id] then
				entry.completed += 1
				entry.roundSum += completedRound[id]
				entry.placementDone += placement
			else
				entry.placementFailed += placement
			end
		end
		if placement <= 4 then
			compositions.boards += 1
			local key = traitKey(lastBoards[id])
			compositions.counts[key] = (compositions.counts[key] or 0) + 1
		end
	end
	for id, player in match.players do
		local name = groupOf(policies[id])
		local group = groups[name] or { seats = 0, placementSum = 0, wins = 0, rerollGold = 0 }
		group.seats += 1
		group.placementSum += player.placement
		group.wins += if player.placement == 1 then 1 else 0
		group.rerollGold += memories[id].rerollGold
		groups[name] = group
	end
	poolStats.dryRolls += pool.dryRolls
	for cost = 1, 5 do
		if tierEmptied[cost] then
			poolStats.matchesTierEmpty[cost] += 1
		end
	end

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

print(string.format("%d matches, %d players each, traits %s", MATCHES, PLAYERS, if TRAITS_ON then "on" else "off"))
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
local bucketLine = {}
for i, name in BUCKET_NAMES do
	table.insert(bucketLine, string.format("%s %.1f%%", name, fightLength.buckets[i] / fightLength.count * 100))
end
print("Fight length distribution: " .. table.concat(bucketLine, ", "))
print("Winner's final board, share of matches with at least one unit of that tier at:")
local starLine2, starLine3 = {}, {}
for cost = 1, 5 do
	table.insert(starLine2, string.format("%dc %.0f%%", cost, winnerStars.twoStar[cost] / winnerStars.boards * 100))
	table.insert(starLine3, string.format("%dc %.0f%%", cost, winnerStars.threeStar[cost] / winnerStars.boards * 100))
end
print("  2-star: " .. table.concat(starLine2, ", "))
print("  3-star: " .. table.concat(starLine3, ", "))
print("3-star access by cost (any player in the match):")
for cost = 1, 5 do
	local made = threeStars.count[cost]
	local failed = threeStars.failedCopies[cost]
	local failedSum = 0
	for _, copies in failed do
		failedSum += copies
	end
	print(
		string.format(
			"  %dc: in %.0f%% of matches, first in round %s, %.2f per match, completed at level %s; unfinished reroll targets: %d, holding %s copies on average",
			cost,
			threeStars.matches[cost] / MATCHES * 100,
			if threeStars.matches[cost] > 0
				then string.format("%.1f", threeStars.firstRoundSum[cost] / threeStars.matches[cost])
				else "-",
			made / MATCHES,
			if made > 0 then string.format("%.1f", threeStars.levelSum[cost] / made) else "-",
			#failed,
			if #failed > 0 then string.format("%.1f", failedSum / #failed) else "-"
		)
	)
end
print("Traits in the final five rounds: share of boards with the breakpoint active, average final")
print("placement of players who had it (players)")
local traitNames = {}
for name in TraitConfig do
	table.insert(traitNames, name)
end
table.sort(traitNames, function(a, b)
	if TraitConfig[a].kind ~= TraitConfig[b].kind then
		return TraitConfig[a].kind == "origin"
	end
	return a < b
end)
for _, name in traitNames do
	local parts = {}
	for _, breakpoint in TraitConfig[name].breakpoints do
		local key = name .. " " .. breakpoint.count
		local players = traitUse.players[key] or 0
		table.insert(
			parts,
			string.format(
				"%d: %.1f%%, %s (%d)",
				breakpoint.count,
				(traitUse.active[key] or 0) / traitUse.boards * 100,
				if players > 0 then string.format("%.2f", traitUse.placementSum[key] / players) else "-",
				players
			)
		)
	end
	print(string.format("  %-10s %s", name, table.concat(parts, " | ")))
end
print("Rerolling bots by the cost they chase (completed = made at least one 3-star of that cost):")
for cost = 1, 5 do
	local entry = committed[cost]
	if entry.bots > 0 then
		local failed = entry.bots - entry.completed
		print(
			string.format(
				"  %dc: completed %.1f%% of %d bots, first 3-star in round %s; placement %s when completed, %s when not",
				cost,
				entry.completed / entry.bots * 100,
				entry.bots,
				if entry.completed > 0 then string.format("%.1f", entry.roundSum / entry.completed) else "-",
				if entry.completed > 0 then string.format("%.2f", entry.placementDone / entry.completed) else "-",
				if failed > 0 then string.format("%.2f", entry.placementFailed / failed) else "-"
			)
		)
	end
end

local function printTop(title: string, counts, total: number, limit: number)
	local keys = {}
	for key in counts do
		table.insert(keys, key)
	end
	table.sort(keys, function(a, b)
		return counts[a] > counts[b] or (counts[a] == counts[b] and a < b)
	end)
	print(string.format("%s (%d different):", title, #keys))
	for i = 1, math.min(limit, #keys) do
		print(string.format("  %5.1f%%  %s", counts[keys[i]] / total * 100, keys[i]))
	end
end
printTop("Top-four boards by active trait set", compositions.counts, compositions.boards, 10)

local timeoutRate = timeouts.fights / timeouts.allFights
print(string.format("Timed-out fights: %d of %d (%.1f%%)", timeouts.fights, timeouts.allFights, timeoutRate * 100))
if timeouts.fights > 0 then
	-- Characters by how much more often they appear in timed-out fights than in fights overall.
	local names = {}
	for name in timeouts.units do
		table.insert(names, name)
	end
	local function ratio(name)
		return (timeouts.units[name] / timeouts.fights) / (timeouts.unitsAll[name] / timeouts.allFights)
	end
	table.sort(names, function(a, b)
		return ratio(a) > ratio(b)
	end)
	local line = {}
	for i = 1, math.min(8, #names) do
		local name = names[i]
		table.insert(
			line,
			string.format("%s %.0f%% (x%.1f)", name, timeouts.units[name] / timeouts.fights * 100, ratio(name))
		)
	end
	print("  characters in timed-out fights (share of those fights, x vs all fights): " .. table.concat(line, ", "))
	printTop("  trait sets of sides in timed-out fights", timeouts.traitSets, timeouts.fights * 2, 8)
end
print("Results by strategy: average placement, win rate, gold spent rerolling per bot per match")
local groupNames = {}
for name in groups do
	table.insert(groupNames, name)
end
table.sort(groupNames)
for _, name in groupNames do
	local group = groups[name]
	print(
		string.format(
			"  %-10s placement %.2f, wins %.1f%%, reroll gold %.0f  [%d seats]",
			name,
			group.placementSum / group.seats,
			group.wins / group.seats * 100,
			group.rerollGold / group.seats,
			group.seats
		)
	)
end
local emptyLine = {}
for cost = 1, 5 do
	table.insert(emptyLine, string.format("%dc %.0f%%", cost, poolStats.matchesTierEmpty[cost] / MATCHES * 100))
end
print(
	string.format(
		"Shared pool: %.1f shop rolls per match hit an empty tier; matches where a tier ran empty: %s",
		poolStats.dryRolls / MATCHES,
		table.concat(emptyLine, ", ")
	)
)

-- Diagnostic 1-star damage per fight by cost, for tanks/supports and for carries
-- (docs/design/world-and-traits.md, Base stat bands). Roles not listed here count as carries.
local SUPPORT_ROLES = { Frontline = true, Support = true, Tank = true, ["Main Tank"] = true }
local BANDS = {
	{ support = { 250, 600 }, carry = { 700, 1000 } },
	{ support = { 350, 750 }, carry = { 750, 1150 } },
	{ support = { 450, 900 }, carry = { 1100, 1600 } },
	{ support = { 500, 1100 }, carry = { 1600, 2200 } },
	{ support = { 700, 1400 }, carry = { 2200, 3200 } },
}

print("1-star characters (per fight they appeared in): average damage dealt against the diagnostic band,")
print("casts, seconds survived (share of the fight), and for dashers how often a cast's dash moved them")
local names = {}
for name in unitStats do
	table.insert(names, name)
end
table.sort(names, function(a, b)
	return UnitConfig[a].cost < UnitConfig[b].cost or (UnitConfig[a].cost == UnitConfig[b].cost and a < b)
end)
local outliers = {}
for _, name in names do
	local stats = unitStats[name]
	local unit = UnitConfig[name]
	local bucket = if SUPPORT_ROLES[unit.role] then "support" else "carry"
	local band = BANDS[unit.cost][bucket]
	local damage = stats.damage / stats.fights
	local verdict = "in"
	if damage < band[1] then
		verdict = string.format("LOW %d%%", math.round((damage / band[1] - 1) * 100))
		table.insert(outliers, { name = name, off = 1 - damage / band[1], verdict = verdict })
	elseif damage > band[2] then
		verdict = string.format("HIGH +%d%%", math.round((damage / band[2] - 1) * 100))
		table.insert(outliers, { name = name, off = damage / band[2] - 1, verdict = verdict })
	end
	local dashLine = ""
	for _, effect in unit.ability.effects do
		if effect.type == "DASH" and stats.casts > 0 then
			dashLine = string.format(", dash moved %.0f%% of casts", stats.dashes / stats.casts * 100)
		end
	end
	print(
		string.format(
			"  %-7s (%d %-7s) %5.0f damage [%d-%d %s], %4.2f casts, %4.1fs alive (%.0f%%)%s  [%d fights]",
			name,
			unit.cost,
			bucket,
			damage,
			band[1],
			band[2],
			verdict,
			stats.casts / stats.fights,
			stats.aliveSeconds / stats.fights,
			stats.aliveSeconds / stats.fightSeconds * 100,
			dashLine,
			stats.fights
		)
	)
end
table.sort(outliers, function(a, b)
	return a.off > b.off
end)
local worst = {}
for i = 1, math.min(5, #outliers) do
	table.insert(worst, outliers[i].name .. " " .. outliers[i].verdict)
end
print(string.format("Outside the band: %d of %d. Worst: %s", #outliers, #names, table.concat(worst, ", ")))
