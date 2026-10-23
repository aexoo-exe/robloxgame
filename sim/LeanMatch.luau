-- One headless match, played like the server plays it (Match, PlayerState, CombatSim, traits, PvE,
-- items) with a bot policy per seat, without sim/run.luau's reports. Used by sim/difficulty.luau and
-- by the playtest report test, which reads its match log (MatchLog, the same record shape the
-- server saves).
--
-- Sim match logs log every seat (`includeBots`), and some numbers are approximations of the server's:
-- goldSpent is the net gold a Preparation used (spending minus selling), units bought are the new
-- units on the bench after it, rerolls come from the bot's reroll gold, and XP bought is not counted.

local Board = require("../src/shared/Board")
local BoardConfig = require("../src/shared/BoardConfig")
local Bot = require("../src/shared/Bot")
local CombatConfig = require("../src/shared/CombatConfig")
local CombatSim = require("../src/shared/CombatSim")
local Items = require("../src/shared/Items")
local Match = require("../src/shared/Match")
local MatchConfig = require("../src/shared/MatchConfig")
local MatchLog = require("../src/shared/MatchLog")
local PlayerState = require("../src/shared/PlayerState")
local Pve = require("../src/shared/Pve")
local ShopConfig = require("../src/shared/ShopConfig")
local Traits = require("../src/shared/Traits")
local UnitConfig = require("../src/shared/UnitConfig")
local UnitPool = require("../src/shared/UnitPool")

local LeanMatch = {}

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

-- Active traits of a board as "Trait:level".
local function activeTraits(units: { any }): { string }
	local list = {}
	for _, state in Traits.summary(units) do
		if state.active then
			table.insert(list, string.format("%s:%d", state.name, state.level))
		end
	end
	return list
end

-- Plays one match. `opts`: players (seats), policyFor(seat) -> Bot policy, matchIndex (seed),
-- log (true: also build a MatchLog record), botDifficulty (recorded in the log only).
-- Returns placements by seat, the rounds played, and the record (or nil).
function LeanMatch.play(opts: { [string]: any }): ({ [number]: number }, number, any?)
	local players: number = opts.players
	local matchIndex: number = opts.matchIndex
	local ids, states, policies, memories = {}, {}, {}, {}
	local pool = UnitPool.new()
	local log = if opts.log then MatchLog.new("sim-" .. matchIndex, 0) else nil
	for seat = 1, players do
		ids[seat] = seat
		states[seat] = PlayerState.new(matchIndex * 1000 + seat, pool)
		PlayerState.grantStartingUnits(states[seat])
		policies[seat] = opts.policyFor(seat)
		memories[seat] = Bot.newMemory(matchIndex * 7 + seat)
		if log then
			MatchLog.addPlayer(log, seat, true)
		end
	end
	local match = Match.new(ids, matchIndex)
	local seconds = 0
	while not match.finished do
		local round = match.round + 1
		local boards = {}
		local preparation = Pve.preparationDuration(round)
		for _, id in Match.activeIds(match) do
			if preparation > 0 then
				local state, memory = states[id], memories[id]
				PlayerState.startPreparation(state)
				local goldBefore, rerollGoldBefore = state.gold, memory.rerollGold
				local before = {}
				for unitId in state.board.units do
					before[unitId] = true
				end
				boards[id] = Bot.prepare(state, policies[id], memory)
				if log then
					for unitId, unit in state.board.units do
						if not before[unitId] then
							MatchLog.bought(log, id, unit.unitType, 0)
						end
					end
					for _ = 1, (memory.rerollGold - rerollGoldBefore) // ShopConfig.rerollCost do
						MatchLog.spent(log, id, "reroll", 0)
					end
					MatchLog.spent(log, id, "gold", math.max(0, goldBefore - state.gold))
				end
			else
				boards[id] = Board.getPlacedUnits(states[id].board)
			end
			if log then
				MatchLog.combat(log, id, round, states[id].level, boards[id], activeTraits(boards[id]))
			end
		end
		local results = {}
		local longest = 0
		for index, fight in Match.startRound(match) do
			local result = runFight(fight, boards, matchIndex * 100000 + match.round * 100 + index, match)
			longest = math.max(longest, result.endTick)
			table.insert(results, {
				fight = fight,
				winner = result.winner,
				survivors = result.survivors,
				healthPercent = result.healthPercent,
				traitGold = { result.traitResults[1].gold, result.traitResults[2].gold },
			})
		end
		seconds += preparation + longest / CombatConfig.ticksPerSecond + MatchConfig.resultsDuration
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
		placements[id] = player.placement or players
		if log then
			MatchLog.placed(log, id, placements[id])
		end
	end
	local record = nil
	if log then
		record = MatchLog.finish(log, {
			endedAt = math.floor(seconds),
			rounds = match.round,
			practice = false,
			botDifficulty = opts.botDifficulty,
		}, true)
	end
	return placements, match.round, record
end

return LeanMatch
