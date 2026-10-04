-- Runs a round's fight with CombatSim and sends it to every client for playback.
-- Side 1 is the first participant. Side 2 is the second participant, or, when only one player is
-- present, the enemy board for this round from CombatConfig.enemyBoardsByRound.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BoardConfig = require(ReplicatedStorage.Shared.BoardConfig)
local CombatConfig = require(ReplicatedStorage.Shared.CombatConfig)
local CombatSim = require(ReplicatedStorage.Shared.CombatSim)
local Economy = require(ReplicatedStorage.Shared.Economy)
local MatchConfig = require(ReplicatedStorage.Shared.MatchConfig)
local RemoteNames = require(ReplicatedStorage.Shared.RemoteNames)
local UnitConfig = require(ReplicatedStorage.Shared.UnitConfig)

local Remotes = require(script.Parent.Remotes)

local CombatService = {}

local combatStarted: RemoteEvent
local seedRandom = Random.new()

type Side = { name: string, userId: number, units: { any }, player: Player? }

local function enemySide(round: number): Side
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
	return { name = "Enemy", userId = 0, units = units }
end

-- Runs the fight for the participants from PlayerService.lockBoards() and broadcasts it.
-- Returns how long the Combat phase should last (seconds), a short result text, and each
-- participating player's outcome (Economy.Outcome).
function CombatService.run(
	participants: { { player: Player, units: { any } } },
	round: number
): (number, string, { [Player]: string })
	local sides: { Side } = {}
	for i = 1, 2 do
		local participant = participants[i]
		if participant then
			sides[i] = {
				name = participant.player.Name,
				userId = participant.player.UserId,
				units = participant.units,
				player = participant.player,
			}
		end
	end
	sides[1] = sides[1] or { name = "Nobody", userId = 0, units = {} }
	sides[2] = sides[2] or enemySide(round)

	local seed = seedRandom:NextInteger(1, 2 ^ 31 - 2)
	local result = CombatSim.run({
		boards = { sides[1].units, sides[2].units },
		columns = BoardConfig.columns,
		rows = BoardConfig.rows,
		unitTypes = UnitConfig,
		ticksPerSecond = CombatConfig.ticksPerSecond,
		maxTicks = MatchConfig.combatMaxDuration * CombatConfig.ticksPerSecond,
		seed = seed,
	})

	combatStarted:FireAllClients({
		startsAt = workspace:GetServerTimeNow(),
		sideUserIds = { sides[1].userId, sides[2].userId },
		result = result,
	})

	local resultText = if result.winner then sides[result.winner].name .. " wins" else "Draw"
	print(
		string.format(
			"[CombatService] %s vs %s, seed %d: %s after %d ticks",
			sides[1].name,
			sides[2].name,
			seed,
			resultText,
			result.endTick
		)
	)

	local outcomes = {}
	for index, side in sides do
		if side.player then
			outcomes[side.player] = if result.winner == nil
				then Economy.Outcome.Draw
				elseif result.winner == index then Economy.Outcome.Win
				else Economy.Outcome.Loss
		end
	end

	return result.endTick / result.ticksPerSecond + CombatConfig.endPadding, resultText, outcomes
end

function CombatService.start()
	combatStarted = Remotes.create(RemoteNames.CombatStarted)
end

return CombatService
