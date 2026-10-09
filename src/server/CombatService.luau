-- Runs every fight of a round with CombatSim and sends each fight only to the players in it.
-- Side 1 is `fight.a`. Side 2 is `fight.b`, a ghost (a copy of `fight.ghostOf`'s board), or in a
-- practice match the scripted enemy board for the round (CombatConfig.enemyBoardsByRound). In a
-- PvE round (`fight.pve`) side 2 is the match theme's creeps or boss (Pve.enemyBoard), simulated
-- with the theme's unit types added to UnitConfig.
-- Traits and bonds apply to every side the same way, ghosts and practice enemies included
-- (Traits.combatParams: combat-start bonuses and TraitCombat effects); each fight's payload carries
-- both sides' trait summaries (Traits.summary) for display. Each result carries both sides' Crew
-- gold (traitGold), which Match.applyResults pays to real players after PvP fights.
-- Spectators and eliminated players receive no fight.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BoardConfig = require(ReplicatedStorage.Shared.BoardConfig)
local CombatConfig = require(ReplicatedStorage.Shared.CombatConfig)
local CombatSim = require(ReplicatedStorage.Shared.CombatSim)
local MatchConfig = require(ReplicatedStorage.Shared.MatchConfig)
local Playback = require(ReplicatedStorage.Shared.Playback)
local Pve = require(ReplicatedStorage.Shared.Pve)
local PveConfig = require(ReplicatedStorage.Shared.PveConfig)
local RemoteNames = require(ReplicatedStorage.Shared.RemoteNames)
local Traits = require(ReplicatedStorage.Shared.Traits)
local UnitConfig = require(ReplicatedStorage.Shared.UnitConfig)

local Remotes = require(script.Parent.Remotes)

local CombatService = {}

local combatStarted: RemoteEvent
local seedRandom = Random.new()

local function practiceEnemyBoard(round: number): { any }
	local boards = CombatConfig.enemyBoardsByRound
	local units = {}
	for i, placement in boards[math.clamp(round, 1, #boards)] do
		table.insert(units, {
			id = "E" .. i,
			unitType = placement.unitType,
			starLevel = placement.starLevel,
			column = placement.column,
			row = placement.row,
		})
	end
	return units
end

local function send(userId: number, payload)
	local player = Players:GetPlayerByUserId(userId)
	if player then
		combatStarted:FireClient(player, payload)
	end
end

-- Runs the round's fights (from Match.startRound) between the boards from PlayerService.lockBoards.
-- `names` maps UserId to display name; `theme` is the match's PvE theme. Returns how long the
-- Combat phase should last (the longest fight's playback time with fast-forward, Playback, plus
-- padding), the fight results for Match.applyResults, and each fighting player's opponent name.
function CombatService.runRound(
	fights: { any },
	boards: { [number]: { any } },
	round: number,
	names: { [number]: string },
	theme: string
): (number, { any }, { [number]: string })
	local startsAt = workspace:GetServerTimeNow()
	local results = {}
	local opponents = {}
	local longestTicks = 0

	for _, fight in fights do
		local sideB, sideBUserId, opponentName
		local unitTypes = UnitConfig
		if fight.pve then
			-- PvE: the match theme's creeps or boss. They have no traits.
			sideB, sideBUserId, opponentName = Pve.enemyBoard(theme, round), 0, PveConfig.opponentNames[fight.pve]
			unitTypes = Pve.unitTypes(theme)
		elseif fight.b then
			sideB, sideBUserId, opponentName = boards[fight.b], fight.b, names[fight.b]
		elseif fight.ghostOf then
			sideB, sideBUserId, opponentName = boards[fight.ghostOf], 0, "Ghost of " .. names[fight.ghostOf]
		else
			sideB, sideBUserId, opponentName = practiceEnemyBoard(round), 0, "Practice enemy"
		end

		local seed = seedRandom:NextInteger(1, 2 ^ 31 - 2)
		local sides = { boards[fight.a] or {}, sideB or {} }
		local startBonuses, traitSetups = Traits.combatParams(sides[1], sides[2], fight.pve ~= nil)
		local result = CombatSim.run({
			boards = sides,
			columns = BoardConfig.columns,
			rows = BoardConfig.rows,
			unitTypes = unitTypes,
			ticksPerSecond = CombatConfig.ticksPerSecond,
			maxTicks = MatchConfig.combatMaxDuration * CombatConfig.ticksPerSecond,
			timeoutDrawMargin = CombatConfig.timeoutDrawMargin,
			seed = seed,
			startBonuses = startBonuses,
			traits = traitSetups,
		})
		longestTicks = math.max(longestTicks, result.endTick)
		table.insert(results, {
			fight = fight,
			winner = result.winner,
			survivors = result.survivors,
			healthPercent = result.healthPercent,
			traitGold = { result.traitResults[1].gold, result.traitResults[2].gold },
		})

		local sideUserIds = { fight.a, sideBUserId }
		local traits = { Traits.summary(sides[1]), if fight.pve then {} else Traits.summary(sides[2]) }
		opponents[fight.a] = opponentName
		send(fight.a, {
			startsAt = startsAt,
			sideUserIds = sideUserIds,
			opponentName = opponentName,
			result = result,
			traits = traits,
		})
		if fight.b then
			opponents[fight.b] = names[fight.a]
			send(fight.b, {
				startsAt = startsAt,
				sideUserIds = sideUserIds,
				opponentName = names[fight.a],
				result = result,
				traits = traits,
			})
		end

		print(
			string.format(
				"[CombatService] round %d: %s vs %s, seed %d: winner side %s after %d ticks%s",
				round,
				names[fight.a],
				opponentName,
				seed,
				tostring(result.winner),
				result.endTick,
				if result.timedOut then " (time limit)" else ""
			)
		)
	end

	-- Clients play long fights faster (Playback), so the phase ends when the sped-up playback does.
	local playbackSeconds = Playback.realSeconds(longestTicks / CombatConfig.ticksPerSecond)
	return playbackSeconds + CombatConfig.endPadding, results, opponents
end

function CombatService.start()
	combatStarted = Remotes.create(RemoteNames.CombatStarted)
end

return CombatService
