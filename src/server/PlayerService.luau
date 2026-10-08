-- Owns each match participant's PlayerState (gold, XP, level, shop, board), keyed by UserId so it
-- survives the player leaving, and handles their requests. Each player's state is sent only to
-- that player. A disconnected participant's board and bench stay frozen while their income and
-- shop refresh continue; when they rejoin, their state is sent again and they can act.
-- Every participant's shop draws from one shared UnitPool per match.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Board = require(ReplicatedStorage.Shared.Board)
local PlayerState = require(ReplicatedStorage.Shared.PlayerState)
local RemoteNames = require(ReplicatedStorage.Shared.RemoteNames)
local UnitPool = require(ReplicatedStorage.Shared.UnitPool)

local Remotes = require(script.Parent.Remotes)

local PlayerService = {}

local states: { [number]: PlayerState.PlayerState } = {} -- current match participants
local eliminated: { [number]: boolean } = {}
local preparationOpen = false
local boardUpdated: RemoteEvent
local playerStateUpdated: RemoteEvent
local requestRefused: RemoteEvent
local seedRandom = Random.new()

local function sendState(userId: number)
	local state = states[userId]
	local player = Players:GetPlayerByUserId(userId)
	if state and player then
		boardUpdated:FireClient(player, Board.getUnits(state.board))
		playerStateUpdated:FireClient(player, PlayerState.getView(state))
	end
end

-- Connects a request remote to a PlayerState action. Arguments come from the client and are
-- untrusted; the action validates them. Requests outside Preparation, from spectators, or from
-- eliminated players are ignored. When the action refuses a request with a reason, the player is
-- told why.
local function connectRequest(remoteName: string, action: (PlayerState.PlayerState, ...any) -> (boolean, string?))
	Remotes.create(remoteName).OnServerEvent:Connect(function(player: Player, ...)
		local state = states[player.UserId]
		if not preparationOpen or not state or eliminated[player.UserId] then
			return
		end
		local accepted, reason = action(state, ...)
		if accepted then
			sendState(player.UserId)
		elseif reason then
			requestRefused:FireClient(player, reason)
		end
	end)
end

-- Gives every participant a fresh starting state, drawing from a new shared pool, and their
-- starting units (PveConfig.startingUnits), placed on the board for the round-1 creep fight.
function PlayerService.startMatch(userIds: { number })
	table.clear(states)
	table.clear(eliminated)
	local pool = UnitPool.new()
	for _, userId in userIds do
		local state = PlayerState.new(seedRandom:NextInteger(1, 2 ^ 31 - 2), pool)
		states[userId] = state
		local granted = PlayerState.grantStartingUnits(state)
		print(string.format("[PlayerService] %d starts with %s", userId, table.concat(granted, ", ")))
		sendState(userId)
	end
end

-- Clears all match state. Clients get an empty board.
function PlayerService.endMatch()
	preparationOpen = false
	for userId in states do
		local player = Players:GetPlayerByUserId(userId)
		if player then
			boardUpdated:FireClient(player, {})
		end
	end
	table.clear(states)
	table.clear(eliminated)
end

-- Stops an eliminated player from acting and returns all their units and shop copies to the pool.
-- They are left with an empty board and shop until the match ends.
function PlayerService.eliminate(userId: number)
	eliminated[userId] = true
	local state = states[userId]
	if state then
		PlayerState.releaseAll(state)
		sendState(userId)
	end
end

-- Pays round income, rolls fresh shops for active participants (connected or not) and opens
-- requests.
function PlayerService.beginPreparation()
	for userId, state in states do
		if not eliminated[userId] then
			local income = PlayerState.startPreparation(state)
			if income then
				print(
					string.format(
						"[PlayerService] %d +%d gold (base %d, interest %d, streak %d, win %d); level %d, %d XP",
						userId,
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
			sendState(userId)
		end
	end
	preparationOpen = true
end

-- Closes requests and returns each active participant's placed units, by UserId. Boards are not
-- changed by combat, so units are back where the player placed them next round.
function PlayerService.lockBoards(): { [number]: { Board.BoardUnit } }
	preparationOpen = false
	local boards = {}
	for userId, state in states do
		if not eliminated[userId] then
			boards[userId] = Board.getPlacedUnits(state.board)
		end
	end
	return boards
end

-- Records each player's fight outcome (Economy.Outcome) for streaks and next round's income.
function PlayerService.recordOutcomes(outcomes: { [number]: string })
	for userId, outcome in outcomes do
		local state = states[userId]
		if state then
			PlayerState.recordCombat(state, outcome)
		end
	end
end

-- Pays each player the gold their PvE fight earned (Pve.Reward, from Match.applyResults) and
-- marks the fight for next round's income. Streaks are left alone.
function PlayerService.recordPve(rewards: { [number]: any })
	for userId, reward in rewards do
		local state = states[userId]
		if state then
			PlayerState.recordPve(state, reward.gold)
			sendState(userId)
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

	-- A participant who rejoins gets their state back and can act again.
	Players.PlayerAdded:Connect(function(player)
		sendState(player.UserId)
	end)
end

return PlayerService
