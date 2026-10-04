-- Owns each participating player's PlayerState (gold, XP, level, shop, board) and handles their
-- requests. The first MatchConfig.maxPlayers players take part; anyone else only watches.
-- Each player's state is sent only to that player.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Board = require(ReplicatedStorage.Shared.Board)
local MatchConfig = require(ReplicatedStorage.Shared.MatchConfig)
local PlayerState = require(ReplicatedStorage.Shared.PlayerState)
local RemoteNames = require(ReplicatedStorage.Shared.RemoteNames)

local Remotes = require(script.Parent.Remotes)

local PlayerService = {}

export type Participant = {
	player: Player,
	units: { Board.BoardUnit }, -- units placed on the board, in the player's own coordinates
}

local participants: { Player } = {}
local states: { [Player]: PlayerState.PlayerState } = {}
local preparationOpen = false
local boardUpdated: RemoteEvent
local playerStateUpdated: RemoteEvent
local requestRefused: RemoteEvent
local seedRandom = Random.new()

local function sendState(player: Player)
	local state = states[player]
	if state then
		boardUpdated:FireClient(player, Board.getUnits(state.board))
		playerStateUpdated:FireClient(player, PlayerState.getView(state))
	end
end

local function fillParticipants()
	for _, player in Players:GetPlayers() do
		if #participants >= MatchConfig.maxPlayers then
			return
		end
		if not states[player] then
			table.insert(participants, player)
			states[player] = PlayerState.new(seedRandom:NextInteger(1, 2 ^ 31 - 2))
			sendState(player)
		end
	end
end

local function onPlayerRemoving(player: Player)
	states[player] = nil
	local index = table.find(participants, player)
	if index then
		table.remove(participants, index)
	end
end

-- Connects a request remote to a PlayerState action. Arguments come from the client and are
-- untrusted; the action validates them. Requests outside Preparation or from players without a
-- board are ignored. When the action refuses a request with a reason, the player is told why.
local function connectRequest(remoteName: string, action: (PlayerState.PlayerState, ...any) -> (boolean, string?))
	Remotes.create(remoteName).OnServerEvent:Connect(function(player: Player, ...)
		if not preparationOpen then
			return
		end
		local state = states[player]
		if not state then
			return
		end
		local accepted, reason = action(state, ...)
		if accepted then
			sendState(player)
		elseif reason then
			requestRefused:FireClient(player, reason)
		end
	end)
end

-- Pays round income, rolls fresh shops and opens requests.
function PlayerService.beginPreparation()
	for _, player in participants do
		local state = states[player]
		local income = PlayerState.startPreparation(state)
		if income then
			print(
				string.format(
					"[PlayerService] %s +%d gold (base %d, interest %d, streak %d, win %d); level %d, %d XP",
					player.Name,
					income.total,
					income.base,
					income.interest,
					income.streak,
					income.win,
					state.level,
					state.xp
				)
			)
		end
		sendState(player)
	end
	fillParticipants()
	preparationOpen = true
end

-- Closes requests and returns each participant's placed units, in join order. Boards are not
-- changed by combat, so units are back where the player placed them next round.
function PlayerService.lockBoards(): { Participant }
	preparationOpen = false
	local result = {}
	for _, player in participants do
		table.insert(result, { player = player, units = Board.getPlacedUnits(states[player].board) })
	end
	return result
end

-- Records each player's fight outcome (Economy.Outcome) for streaks and next round's income.
function PlayerService.recordCombat(outcomes: { [Player]: string })
	for player, outcome in outcomes do
		local state = states[player]
		if state then
			PlayerState.recordCombat(state, outcome)
		end
	end
end

function PlayerService.start()
	boardUpdated = Remotes.create(RemoteNames.BoardUpdated)
	playerStateUpdated = Remotes.create(RemoteNames.PlayerStateUpdated)
	requestRefused = Remotes.create(RemoteNames.RequestRefused)
	connectRequest(RemoteNames.RequestMoveUnit, PlayerState.moveUnit)
	connectRequest(RemoteNames.RequestBuyUnit, PlayerState.buyUnit)
	connectRequest(RemoteNames.RequestSellUnit, PlayerState.sellUnit)
	connectRequest(RemoteNames.RequestReroll, PlayerState.reroll)
	connectRequest(RemoteNames.RequestBuyXp, PlayerState.buyXp)

	Players.PlayerAdded:Connect(fillParticipants)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	fillParticipants()
end

return PlayerService
