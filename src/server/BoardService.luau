-- Owns each participating player's board and handles placement requests.
-- The first MatchConfig.maxPlayers players get a board; anyone else only watches.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Board = require(ReplicatedStorage.Shared.Board)
local BoardConfig = require(ReplicatedStorage.Shared.BoardConfig)
local MatchConfig = require(ReplicatedStorage.Shared.MatchConfig)
local RemoteNames = require(ReplicatedStorage.Shared.RemoteNames)

local Remotes = require(script.Parent.Remotes)

local BoardService = {}

export type Participant = {
	player: Player,
	units: { Board.BoardUnit }, -- units placed on the board, in the player's own coordinates
}

local participants: { Player } = {}
local boards: { [Player]: Board.Board } = {}
local placementOpen = false -- true only during Preparation
local boardUpdated: RemoteEvent

local function createStartingBoard(): Board.Board
	local board = Board.new(BoardConfig.columns, BoardConfig.rows, BoardConfig.benchSlots)
	for i, unitType in BoardConfig.startingUnits do
		Board.addUnit(board, tostring(i), unitType)
	end
	return board
end

local function sendBoard(player: Player)
	boardUpdated:FireClient(player, Board.getUnits(boards[player]))
end

local function fillParticipants()
	for _, player in Players:GetPlayers() do
		if #participants >= MatchConfig.maxPlayers then
			return
		end
		if not boards[player] then
			table.insert(participants, player)
			boards[player] = createStartingBoard()
			sendBoard(player)
		end
	end
end

local function onPlayerRemoving(player: Player)
	boards[player] = nil
	local index = table.find(participants, player)
	if index then
		table.remove(participants, index)
	end
end

-- Arguments come from the client and are untrusted. Board.moveUnit checks ownership, bounds and
-- emptiness; this checks the phase. Invalid requests are ignored.
local function onMoveRequested(player: Player, unitId: any, target: any)
	if not placementOpen then
		return
	end
	local board = boards[player]
	if board and Board.moveUnit(board, unitId, target) then
		sendBoard(player)
	end
end

-- Resets every participant to the starting units on the bench and opens placement.
function BoardService.beginPreparation()
	for _, player in participants do
		boards[player] = createStartingBoard()
		sendBoard(player)
	end
	fillParticipants()
	placementOpen = true
end

-- Closes placement and returns each participant's placed units, in join order.
function BoardService.lockBoards(): { Participant }
	placementOpen = false
	local result = {}
	for _, player in participants do
		table.insert(result, { player = player, units = Board.getPlacedUnits(boards[player]) })
	end
	return result
end

function BoardService.start()
	boardUpdated = Remotes.create(RemoteNames.BoardUpdated)
	Remotes.create(RemoteNames.RequestMoveUnit).OnServerEvent:Connect(onMoveRequested)

	Players.PlayerAdded:Connect(fillParticipants)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	fillParticipants()
end

return BoardService
