-- Headless match simulation: plays full 8-bot matches with the real pure modules (Match, Pairing,
-- PlayerState, Shop, CombatSim) and reports pacing. No Roblox Studio needed.
--   lune run sim/run.luau [matches=200] [players=8]
-- Match time is estimated from the configured phase timers: Preparation (per round, see
-- Pve.preparationDuration) + Combat (the round's longest fight played back with fast-forward,
-- Playback, + padding) + Results per round.
-- Lobby and final-placement screens are excluded.
-- PvE rounds (creeps and bosses) are played like the server plays them: starting units at match
-- start, no Preparation in round 1, PvE rewards paid at Results.
-- Traits and bonds work as on the server (Traits.combatParams: combat-start bonuses and TraitCombat
-- effects; Crew takedown gold paid after PvP fights). The report adds bond use, fight-time trait
-- effects, Crew gold, and (Mechanics) form changes for every unit with forms and the Overhaul 1
-- pieces (areas by shape, bounces, knockbacks, debuffs, executes, ...). PvE fights are left out of the
-- per-character, mechanics and timeout reports (those measure the roster against itself) and are
-- reported in their own section.

local process = require("@lune/process")

local Bot = require("./Bot")
local Mechanics = require("./Mechanics")
local Battle = require("../src/shared/Battle")
local Board = require("../src/shared/Board")
local BoardConfig = require("../src/shared/BoardConfig")
local CombatConfig = require("../src/shared/CombatConfig")
local CombatSim = require("../src/shared/CombatSim")
local Match = require("../src/shared/Match")
local MatchConfig = require("../src/shared/MatchConfig")
local Playback = require("../src/shared/Playback")
local PlayerState = require("../src/shared/PlayerState")
local Pve = require("../src/shared/Pve")
local SeededRandom = require("../src/shared/SeededRandom")
local TraitConfig = require("../src/shared/TraitConfig")
local Traits = require("../src/shared/Traits")
local UnitConfig = require("../src/shared/UnitConfig")
local UnitPool = require("../src/shared/UnitPool")

local MATCHES = tonumber(process.args[1]) or 200
local PLAYERS = tonumber(process.args[2]) or 8
-- "notraits" as the third argument runs the same matches with trait bonuses switched off.
local TRAITS_ON = process.args[3] ~= "notraits"

-- The enemy side of a fight: another bot, a ghost, or the match theme's creeps or boss.
local function enemyBoard(fight, boards, match)
	if fight.pve then
		return Pve.enemyBoard(match.theme, match.round)
	end
	return if fight.b then boards[fight.b] elseif fight.ghostOf then boards[fight.ghostOf] else {}
end

local function runFight(fight, boards, seed, match)
	local sideB = enemyBoard(fight, boards, match)
	local startBonuses, traitSetups = Traits.combatParams(boards[fight.a], sideB, fight.pve ~= nil)
	return CombatSim.run({
		startBonuses = if TRAITS_ON then startBonuses else nil,
		traits = if TRAITS_ON then traitSetups else nil,
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
	local summonerOf = {} -- summon index -> summoner index
	for _, unit in result.units do
		if unit.starLevel == 1 then
			oneStar[unit.index] = unit.unitType
			local stats = unitStats[unit.unitType]
				or {
					fights = 0,
					damage = 0,
					summonDamage = 0,
					dotDamage = 0,
					casts = 0,
					dashes = 0,
					aliveSeconds = 0,
					fightSeconds = 0,
				}
			stats.fights += 1
			stats.fightSeconds += seconds
			unitStats[unit.unitType] = stats
		end
	end
	for _, event in result.events do
		if event.kind == "Summon" then
			summonerOf[event.summon] = event.unit
		end
		-- Damage by a summon is credited to its summoner (and also counted separately).
		local summoner = summonerOf[event.unit]
		if summoner and (event.kind == "Attack" or event.kind == "Damage") then
			local summonerType = oneStar[summoner]
			if summonerType then
				unitStats[summonerType].damage += event.damage
				unitStats[summonerType].summonDamage += event.damage
			end
		end
		local unitType = oneStar[event.unit]
		if unitType then
			if event.kind == "Attack" or event.kind == "Damage" then
				unitStats[unitType].damage += event.damage
				if event.dot then
					unitStats[unitType].dotDamage += event.damage
				end
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

-- Support characters (class Support), every star level, PvP fights only: per fight they appeared
-- in, healing and shielding given (trait shields excluded), casts and seconds alive.
local supportStats = {}

local function isSupportClass(unitType: string): boolean
	return table.find(UnitConfig[unitType].classes, "Support") ~= nil
end

local function recordSupport(result)
	local tps = result.ticksPerSecond
	local fightSeconds = result.endTick / tps
	local tracked = {} -- unit index -> unit type
	for _, unit in result.units do
		if isSupportClass(unit.unitType) then
			tracked[unit.index] = unit.unitType
			local entry = supportStats[unit.unitType]
				or { fights = 0, heal = 0, shield = 0, casts = 0, aliveSeconds = 0, fightSeconds = 0 }
			entry.fights += 1
			entry.fightSeconds += fightSeconds
			supportStats[unit.unitType] = entry
		end
	end
	local deathTick = {}
	for _, event in result.events do
		local unitType = tracked[event.unit]
		if unitType then
			local entry = supportStats[unitType]
			if event.kind == "Heal" then
				entry.heal += event.amount
			elseif event.kind == "Shield" and not event.source then
				entry.shield += event.shield
			elseif event.kind == "Cast" then
				entry.casts += 1
			elseif event.kind == "Death" then
				deathTick[event.unit] = event.tick
			end
		end
	end
	for index, unitType in tracked do
		supportStats[unitType].aliveSeconds += (deathTick[index] or result.endTick) / tps
	end
end

-- Gold per player per match, summed over every player of every match: earned by source and spent
-- by use. Spending is measured by wrapping the PlayerState actions the bots call (their behavior is
-- unchanged); each action's gold change is booked to the acting player's ledger.
local goldTotals = {
	players = 0,
	starting = 0,
	base = 0,
	interest = 0,
	streak = 0,
	win = 0,
	pve = 0,
	sales = 0,
	units = 0,
	rerolls = 0,
	xp = 0,
	crew = 0, -- Crew takedown gold after PvP fights (TraitCombat)
}
local ledgers = setmetatable({}, { __mode = "k" }) -- PlayerState -> this match's ledger

local function bookGold(action: string, key: string, sign: number)
	local original = PlayerState[action]
	PlayerState[action] = function(state, ...)
		local before = state.gold
		local accepted, reason = original(state, ...)
		local ledger = ledgers[state]
		if ledger then
			ledger[key] += sign * (state.gold - before)
		end
		return accepted, reason
	end
end
bookGold("buyUnit", "units", -1)
bookGold("reroll", "rerolls", -1)
bookGold("buyXp", "xp", -1)
bookGold("sellUnit", "sales", 1)

-- PvE rounds, by round number: fights, fights won, gold paid, and for boss rounds the summed share
-- of boss health removed and kills. `goldByPlayer` sums each player's PvE gold per match.
local pveRounds = {}
local pveGold = { sum = 0, players = 0 }

local function recordPveFight(round: number, kind: string, winner: number?, reward, seconds: number)
	local entry = pveRounds[round]
		or { kind = kind, fights = 0, won = 0, gold = 0, share = 0, kills = 0, killSeconds = 0 }
	entry.fights += 1
	entry.won += if winner == 1 then 1 else 0
	entry.gold += reward.gold
	entry.share += reward.share or 0
	if reward.bossKilled then
		entry.kills += 1
		entry.killSeconds += seconds
	end
	pveRounds[round] = entry
end

-- Boss calibration: each board that fights a boss also fights a copy of that boss that cannot die,
-- until the board is wiped or the combat timer runs out. Per boss round: the damage each board
-- dealt to the boss, the fight lengths, and the boss's combat health.
-- The undying boss keeps its real max health (so it gains mana from hits exactly as in the real
-- fight); its health is restored after every hit, by wrapping Battle.damage for these fights only.
-- Seeds come from their own generator, so match results are unaffected.
local bossCalibration = {}

local function calibrateBoss(board, match, seed: number)
	local original = Battle.damage
	Battle.damage = function(battle, source, target, ...)
		local final, manaGained = original(battle, source, target, ...)
		if target.side == 2 and not target.summoned and not target.dead then
			target.health = target.maxHealth
		end
		return final, manaGained
	end
	local bossBoard = Pve.enemyBoard(match.theme, match.round)
	local startBonuses, traitSetups = Traits.combatParams(board, bossBoard, true)
	local ok, result = pcall(CombatSim.run, {
		boards = { board, bossBoard },
		columns = BoardConfig.columns,
		rows = BoardConfig.rows,
		unitTypes = Pve.unitTypes(match.theme),
		ticksPerSecond = CombatConfig.ticksPerSecond,
		maxTicks = MatchConfig.combatMaxDuration * CombatConfig.ticksPerSecond,
		timeoutDrawMargin = CombatConfig.timeoutDrawMargin,
		seed = seed,
		startBonuses = if TRAITS_ON then startBonuses else nil,
		traits = if TRAITS_ON then traitSetups else nil,
	})
	Battle.damage = original
	assert(ok, result)

	local boss = nil
	for _, unit in result.units do
		if unit.side == 2 then
			boss = unit
		end
	end
	local dealt = 0
	for _, event in result.events do
		if (event.kind == "Attack" or event.kind == "Damage") and event.target == boss.index then
			dealt += event.damage
		end
	end
	local entry = bossCalibration[match.round] or { damages = {}, seconds = 0, bossHealth = boss.maxHealth }
	table.insert(entry.damages, dealt)
	entry.seconds += result.endTick / result.ticksPerSecond
	bossCalibration[match.round] = entry
end

-- Trait use in each match's final five rounds: boards (one per player per round) with each
-- "Trait level" active, and the final placements of players who had it at least once.
local traitUse = { boards = 0, active = {}, placementSum = {}, players = {} }

-- Bonds in each match's final five rounds: boards with each bond active, and the final placements
-- of players who had it at least once.
local bondUse = { boards = 0, active = {}, placementSum = {}, players = {} }

-- Fight-time trait effects (TraitCombat results), PvP fights only: per trait, the sides that had it
-- active and what it did there.
local traitEffects = {
	Hunters = { sides = 0, marks = 0 },
	Shinobi = { sides = 0, vanishes = 0 },
	Assassin = { sides = 0, executes = 0 },
	Heroes = { sides = 0, meterFills = 0 },
	Crew = { sides = 0, crewTakedowns = 0, gold = 0 },
}

local function recordTraitEffects(result, sides)
	for side, board in sides do
		local outcome = result.traitResults[side]
		for _, state in Traits.summary(board) do
			local entry = traitEffects[state.name]
			if entry and state.active then
				entry.sides += 1
				for key in entry do
					if key ~= "sides" then
						entry[key] += outcome[key]
					end
				end
			end
		end
	end
end

-- Rerolling bots by the cost they chase: seats, how many made a 3-star of that cost, the round
-- they first did, and final placements split by whether they did.
local committed = {}
for cost = 1, 5 do
	committed[cost] = { bots = 0, completed = 0, roundSum = 0, placementDone = 0, placementFailed = 0 }
end

-- Rerolling bots while rolling (Bot.luau header), by strategy name: summed memory.stats, the bots
-- that rolled at all with their level and round at the first roll, and for each target unfinished
-- at the end (or at elimination) the copies left in the pool.
local rollDiag = {}

local function rollDiagFor(name: string)
	local entry = rollDiag[name]
	if not entry then
		entry = {
			bots = 0,
			offersSeen = 0,
			offersBought = 0,
			refusedBenchFull = 0,
			refusedGold = 0,
			nonTargetGold = 0,
			switches = 0,
			targetCopiesSold = 0,
			rolled = 0,
			startLevelSum = 0,
			startRoundSum = 0,
			unfinished = 0,
			poolLeftSum = 0,
		}
		rollDiag[name] = entry
	end
	return entry
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

	local hadBond = {}
	for round = math.max(1, finalRound - 4), finalRound do
		for id, board in roundBoards[round] or {} do
			bondUse.boards += 1
			for _, bond in Traits.bonds(board) do
				bondUse.active[bond.id] = (bondUse.active[bond.id] or 0) + 1
				hadBond[bond.id] = hadBond[bond.id] or {}
				hadBond[bond.id][id] = true
			end
		end
	end
	for bondId, ids in hadBond do
		for id in ids do
			bondUse.players[bondId] = (bondUse.players[bondId] or 0) + 1
			bondUse.placementSum[bondId] = (bondUse.placementSum[bondId] or 0) + placements[id]
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

-- Records the copies a rerolling bot holds of each target it has not finished, and the copies of it
-- left in the pool (call before an eliminated player's units go back to the pool).
local function recordFailedTargets(state, policy, memory)
	if not policy.rerollCost then
		return
	end
	local diag = rollDiagFor(policy.name)
	for _, unitType in memory.targets do
		if not memory.completed[unitType] then
			table.insert(threeStars.failedCopies[policy.rerollCost], (Bot.copiesHeld(state, unitType)))
			diag.unfinished += 1
			diag.poolLeftSum += UnitPool.remaining(state.pool, unitType)
		end
	end
end

local function playMatch(matchIndex: number)
	local ids = {}
	local states = {}
	local policies = {}
	local memories = {}
	local pool = UnitPool.new()
	local goldFromPve = {}
	for i = 1, PLAYERS do
		ids[i] = i
		states[i] = PlayerState.new(matchIndex * 1000 + i, pool)
		ledgers[states[i]] = {
			starting = states[i].gold,
			base = 0,
			interest = 0,
			streak = 0,
			win = 0,
			pve = 0,
			sales = 0,
			units = 0,
			rerolls = 0,
			xp = 0,
			crew = 0,
		}
		PlayerState.grantStartingUnits(states[i])
		policies[i] = policyFor(i, matchIndex)
		memories[i] = Bot.newMemory()
		goldFromPve[i] = 0
	end
	local match = Match.new(ids, matchIndex)
	local calibrationRng = SeededRandom.new(matchIndex * 7919 + 17) -- boss calibration fights only
	local stats = { seconds = 0, fights = 0, timeouts = 0, longestFight = 0 }
	local lastBoards = {}
	local tierEmptied = {}
	local seenThreeStar = {} -- unit ids already counted
	local matchHasThreeStar = {}
	local roundBoards = {}
	local completedRound = {} -- rerolling bots: round of their first 3-star at their cost
	local rollStartRound = {} -- rerolling bots: round of their first roll at the roll level

	while not match.finished do
		local boards = {}
		local round = match.round + 1
		local preparation = Pve.preparationDuration(round)
		roundBoards[round] = boards
		for _, id in Match.activeIds(match) do
			if preparation > 0 then
				local income = PlayerState.startPreparation(states[id])
				if income then
					local ledger = ledgers[states[id]]
					ledger.base += income.base
					ledger.interest += income.interest
					ledger.streak += income.streak
					ledger.win += income.win
				end
				boards[id] = Bot.prepare(states[id], policies[id], memories[id])
				if memories[id].stats.rollStartLevel and not rollStartRound[id] then
					rollStartRound[id] = round
				end
			else
				-- No Preparation (round 1): the units already on the board fight.
				boards[id] = Board.getPlacedUnits(states[id].board)
			end
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
		local fightSeconds = {} -- by player (side 1) id
		local longestTicks = 0
		for index, fight in fights do
			local result = runFight(fight, boards, matchIndex * 100000 + match.round * 100 + index, match)
			if fight.pve == Pve.Kind.Boss then
				calibrateBoss(boards[fight.a], match, SeededRandom.nextInt(calibrationRng, 2 ^ 31 - 2))
			end
			fightSeconds[fight.a] = result.endTick / result.ticksPerSecond
			if not fight.pve then
				recordFight(result)
				recordSupport(result)
				Mechanics.record(result)
				recordTraitEffects(result, { boards[fight.a], enemyBoard(fight, boards, match) })
				recordTimeoutData({ boards[fight.a], enemyBoard(fight, boards, match) }, result.timedOut)
				stats.fights += 1
				if result.timedOut then
					stats.timeouts += 1
				end
			end
			longestTicks = math.max(longestTicks, result.endTick)
			table.insert(results, {
				fight = fight,
				winner = result.winner,
				survivors = result.survivors,
				healthPercent = result.healthPercent,
				traitGold = { result.traitResults[1].gold, result.traitResults[2].gold },
			})
		end
		local combatSeconds = longestTicks / CombatConfig.ticksPerSecond
		stats.longestFight = math.max(stats.longestFight, combatSeconds)
		-- The Combat phase lasts the longest fight's playback time, with fast-forward (Playback).
		stats.seconds += preparation + Playback.realSeconds(combatSeconds) + CombatConfig.endPadding + MatchConfig.resultsDuration

		local summary = Match.applyResults(match, results)
		for id, outcome in summary.outcomes do
			PlayerState.recordCombat(states[id], outcome)
		end
		-- Crew takedown gold, paid after PvP fights as the server does (RoundService).
		for id, gold in summary.traitGold do
			PlayerState.grantGold(states[id], gold)
			ledgers[states[id]].crew += gold
		end
		for _, result in results do
			local reward = summary.pve[result.fight.a]
			if reward then
				PlayerState.recordPve(states[result.fight.a], reward.gold)
				goldFromPve[result.fight.a] += reward.gold
				ledgers[states[result.fight.a]].pve += reward.gold
				recordPveFight(match.round, result.fight.pve, result.winner, reward, fightSeconds[result.fight.a])
			end
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
	for id in match.players do
		if policies[id].rerollCost then
			local diag = rollDiagFor(policies[id].name)
			local rollStats = memories[id].stats
			diag.bots += 1
			diag.offersSeen += rollStats.offersSeen
			diag.offersBought += rollStats.offersBought
			diag.refusedBenchFull += rollStats.refusedBenchFull
			diag.refusedGold += rollStats.refusedGold
			diag.nonTargetGold += rollStats.nonTargetGold
			diag.switches += rollStats.switches
			diag.targetCopiesSold += rollStats.targetCopiesSold
			if rollStats.rollStartLevel then
				diag.rolled += 1
				diag.startLevelSum += rollStats.rollStartLevel
				diag.startRoundSum += rollStartRound[id]
			end
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
	for _, gold in goldFromPve do
		pveGold.sum += gold
		pveGold.players += 1
	end
	for _, state in states do
		goldTotals.players += 1
		for key, amount in ledgers[state] do
			goldTotals[key] += amount
		end
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
		"PvP fights hitting the %ds cap: %d of %d (%.1f%%); longest round's combat %.1fs",
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
print("Bonds in the final five rounds: share of boards with the bond active, average final placement")
print("of players who had it (players)")
local BondConfig = require("../src/shared/BondConfig")
for _, bond in BondConfig do
	local players = bondUse.players[bond.id] or 0
	print(
		string.format(
			"  %-12s (%s + %s) %.1f%%, %s (%d)",
			bond.id,
			bond.units[1],
			bond.units[2],
			(bondUse.active[bond.id] or 0) / math.max(1, bondUse.boards) * 100,
			if players > 0 then string.format("%.2f", bondUse.placementSum[bond.id] / players) else "-",
			players
		)
	)
end
print("Fight-time trait effects (PvP fights), per side with the trait active:")
for _, name in { "Hunters", "Shinobi", "Assassin", "Heroes", "Crew" } do
	local entry = traitEffects[name]
	local parts = {}
	for key, value in entry do
		if key ~= "sides" then
			table.insert(parts, string.format("%s %.2f", key, if entry.sides > 0 then value / entry.sides else 0))
		end
	end
	table.sort(parts)
	print(string.format("  %-9s %s  [%d sides]", name, table.concat(parts, ", "), entry.sides))
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
	-- Every character seen in a timed-out fight, most over-represented first.
	print("  characters in timed-out fights: share of those fights, x vs their share of all fights (count)")
	for _, name in names do
		print(
			string.format(
				"    %-18s %5.1f%%  x%.2f  (%d)",
				name,
				timeouts.units[name] / timeouts.fights * 100,
				ratio(name),
				timeouts.units[name]
			)
		)
	end
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
-- Rerolling bots while rolling (at the roll level with a locked target), per bot per match.
print("Rerolling bots while rolling (per bot per match; rolling = at the roll level with a locked target):")
local rollNames = {}
for name in rollDiag do
	table.insert(rollNames, name)
end
table.sort(rollNames)
for _, name in rollNames do
	local diag = rollDiag[name]
	if diag.bots > 0 then
		print(
			string.format(
				"  %s: rolled in %.0f%% of seats, first roll at level %s in round %s  [%d seats]",
				name,
				diag.rolled / diag.bots * 100,
				if diag.rolled > 0 then string.format("%.1f", diag.startLevelSum / diag.rolled) else "-",
				if diag.rolled > 0 then string.format("%.1f", diag.startRoundSum / diag.rolled) else "-",
				diag.bots
			)
		)
		print(
			string.format(
				"    target offers: %.1f seen, %.1f bought, refused %.2f (bench full) + %.2f (not enough gold)",
				diag.offersSeen / diag.bots,
				diag.offersBought / diag.bots,
				diag.refusedBenchFull / diag.bots,
				diag.refusedGold / diag.bots
			)
		)
		print(
			string.format(
				"    non-target gold %.1f, target switches %.2f, target copies sold %.2f",
				diag.nonTargetGold / diag.bots,
				diag.switches / diag.bots,
				diag.targetCopiesSold / diag.bots
			)
		)
		print(
			string.format(
				"    unfinished targets at the end: %d, %s pool copies left on average",
				diag.unfinished,
				if diag.unfinished > 0 then string.format("%.1f", diag.poolLeftSum / diag.unfinished) else "-"
			)
		)
	end
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
-- (docs/design/world-and-traits.md, Base stat bands). Characters with the Guardian or Support
-- class use the tank/support band; everyone else uses the carry band.
local SUPPORT_CLASSES = { Guardian = true, Support = true }
local function isSupport(unit): boolean
	for _, class in unit.classes do
		if SUPPORT_CLASSES[class] then
			return true
		end
	end
	return false
end
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
	local bucket = if isSupport(unit) then "support" else "carry"
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
	-- Parts of the damage above: from its summons, and from damage over time.
	if stats.summonDamage > 0 then
		dashLine ..= string.format(", %.0f of it by summons", stats.summonDamage / stats.fights)
	end
	if stats.dotDamage > 0 then
		dashLine ..= string.format(", %.0f of it over time", stats.dotDamage / stats.fights)
	end
	print(
		string.format(
			"  %-18s (%d %-7s) %5.0f damage [%d-%d %s], %4.2f casts, %4.1fs alive (%.0f%%)%s  [%d fights]",
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
Mechanics.report()

-- PvE rounds: per round, how often players won and the gold paid; for boss rounds the average share
-- of boss health removed and the kill rate.
print(
	string.format(
		"PvE rounds (theme fights; not in the character or timeout numbers above): %.1f PvE gold per player per match",
		if pveGold.players > 0 then pveGold.sum / pveGold.players else 0
	)
)
local pveRoundNumbers = {}
for round in pveRounds do
	table.insert(pveRoundNumbers, round)
end
table.sort(pveRoundNumbers)
for _, round in pveRoundNumbers do
	local entry = pveRounds[round]
	local line = string.format(
		"  round %2d %-5s won %5.1f%%, %.2f gold per fight",
		round,
		entry.kind,
		entry.won / entry.fights * 100,
		entry.gold / entry.fights
	)
	if entry.kind == Pve.Kind.Boss then
		line ..= string.format(
			", boss health removed %.0f%% on average, kill rate %.1f%%, average time to kill %s",
			entry.share / entry.fights * 100,
			entry.kills / entry.fights * 100,
			if entry.kills > 0 then string.format("%.1fs", entry.killSeconds / entry.kills) else "-"
		)
	end
	print(line .. string.format("  [%d fights]", entry.fights))
end

-- Gold per player per match, by source and by use.
local function perPlayer(key: string): number
	return if goldTotals.players > 0 then goldTotals[key] / goldTotals.players else 0
end
local earned = perPlayer("base")
	+ perPlayer("interest")
	+ perPlayer("streak")
	+ perPlayer("win")
	+ perPlayer("pve")
	+ perPlayer("crew")
local spent = perPlayer("units") + perPlayer("rerolls") + perPlayer("xp")
print(string.format("Gold per player per match (starting gold %.0f not included):", perPlayer("starting")))
print(
	string.format(
		"  earned %.1f: base income %.1f, interest %.1f, streaks %.1f, win bonus %.1f, PvE %.1f, Crew takedowns %.1f",
		earned,
		perPlayer("base"),
		perPlayer("interest"),
		perPlayer("streak"),
		perPlayer("win"),
		perPlayer("pve"),
		perPlayer("crew")
	)
)
print(
	string.format(
		"  spent %.1f: units %.1f, rerolls %.1f, XP %.1f; refunded by selling %.1f",
		spent,
		perPlayer("units"),
		perPlayer("rerolls"),
		perPlayer("xp"),
		perPlayer("sales")
	)
)

-- Support characters, all star levels, PvP fights.
print("Support characters (class Support, all star levels, PvP fights), per fight they appeared in:")
print("  healing given, shielding given (trait shields excluded), casts, seconds alive (share of the fight)")
local supportNames = {}
for name in supportStats do
	table.insert(supportNames, name)
end
table.sort(supportNames, function(a, b)
	return UnitConfig[a].cost < UnitConfig[b].cost or (UnitConfig[a].cost == UnitConfig[b].cost and a < b)
end)
for _, name in supportNames do
	local entry = supportStats[name]
	print(
		string.format(
			"  %-18s (%dc) heal %5.0f, shield %5.0f, %4.2f casts, %4.1fs alive (%.0f%%)  [%d fights]",
			name,
			UnitConfig[name].cost,
			entry.heal / entry.fights,
			entry.shield / entry.fights,
			entry.casts / entry.fights,
			entry.aliveSeconds / entry.fights,
			entry.aliveSeconds / entry.fightSeconds * 100,
			entry.fights
		)
	)
end

-- Boss calibration (see calibrateBoss): damage boards deal to a boss that cannot die.
local function percentile(sorted: { number }, p: number): number
	if #sorted == 0 then
		return 0
	end
	-- Nearest rank.
	return sorted[math.clamp(math.ceil(p / 100 * #sorted), 1, #sorted)]
end
print("Boss calibration (each boss-round board against an undying copy of the boss, until wiped or 50s):")
print("  damage dealt to the boss per board: average, median, 25th-75th percentile; average fight length;")
print("  boss combat health (current) and the combat health at which the median board removes 60%")
print("  (boss health in PveThemeConfig is combat health; the roster health dial does not apply to it)")
local calibrationRounds = {}
for round in bossCalibration do
	table.insert(calibrationRounds, round)
end
table.sort(calibrationRounds)
for _, round in calibrationRounds do
	local entry = bossCalibration[round]
	local sorted = table.clone(entry.damages)
	table.sort(sorted)
	local sum = 0
	for _, damage in sorted do
		sum += damage
	end
	local median = percentile(sorted, 50)
	print(
		string.format(
			"  round %2d: average %.0f, median %.0f, p25 %.0f, p75 %.0f; %.1fs average; boss health %d now, %.0f for 60%%  [%d boards]",
			round,
			sum / #sorted,
			median,
			percentile(sorted, 25),
			percentile(sorted, 75),
			entry.seconds / #sorted,
			entry.bossHealth,
			median / 0.6,
			#sorted
		)
	)
end
