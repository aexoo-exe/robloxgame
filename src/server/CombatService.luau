-- Runs every fight of a round with CombatSim and sends each fight only to the players in it.
-- Side 1 is `fight.a`. Side 2 is `fight.b`, a ghost (a copy of `fight.ghostOf`'s board), or in a
-- practice match the scripted enemy board for the round (CombatConfig.enemyBoardsByRound).
-- Traits apply to every side the same way, ghosts and practice enemies included; each fight's
-- payload carries both sides' trait summaries (Traits.summary) for display.
-- Spectators and eliminated players receive no fight.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BoardConfig = require(ReplicatedStorage.Shared.BoardConfig)
local CombatConfig = require(ReplicatedStorage.Shared.CombatConfig)
local CombatSim = require(ReplicatedStorage.Shared.CombatSim)
local MatchConfig = require(ReplicatedStorage.Shared.MatchConfig)
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
-- `names` maps UserId to display name. Returns how long the Combat phase should last (the longest
-- fight plus padding), the fight results for Match.applyResults, and each fighting player's
-- opponent name.
function CombatService.runRound(
	fights: { any },
	boards: { [number]: { any } },
	round: number,
	names: { [number]: string }
): (number, { any }, { [number]: string })
	local startsAt = workspace:GetServerTimeNow()
	local results = {}
	local opponents = {}
	local longestTicks = 0

	for _, fight in fights do
		local sideB, sideBUserId, opponentName
		if fight.b then
			sideB, sideBUserId, opponentName = boards[fight.b], fight.b, names[fight.b]
		elseif fight.ghostOf then
			sideB, sideBUserId, opponentName = boards[fight.ghostOf], 0, "Ghost of " .. names[fight.ghostOf]
		else
			sideB, sideBUserId, opponentName = practiceEnemyBoard(round), 0, "Practice enemy"
		end

		local seed = seedRandom:NextInteger(1, 2 ^ 31 - 2)
		local sides = { boards[fight.a] or {}, sideB or {} }
		local result = CombatSim.run({
			boards = sides,
			columns = BoardConfig.columns,
			rows = BoardConfig.rows,
			unitTypes = UnitConfig,
			ticksPerSecond = CombatConfig.ticksPerSecond,
			maxTicks = MatchConfig.combatMaxDuration * CombatConfig.ticksPerSecond,
			timeoutDrawMargin = CombatConfig.timeoutDrawMargin,
			seed = seed,
			startBonuses = { Traits.bonuses(sides[1]), Traits.bonuses(sides[2]) },
		})
		longestTicks = math.max(longestTicks, result.endTick)
		table.insert(results, { fight = fight, winner = result.winner, survivors = result.survivors })

		local sideUserIds = { fight.a, sideBUserId }
		local traits = { Traits.summary(sides[1]), Traits.summary(sides[2]) }
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

	return longestTicks / CombatConfig.ticksPerSecond + CombatConfig.endPadding, results, opponents
end

function CombatService.start()
	combatStarted = Remotes.create(RemoteNames.CombatStarted)
end

return CombatService
