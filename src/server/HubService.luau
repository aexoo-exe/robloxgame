-- The hub: the area players spawn into and walk around between matches (built by HubBuilder from
-- HubConfig), with two pads, each with one display board showing its status:
--   * Play: standing on it queues the player; stepping off leaves the queue. A match starts
--     HubConfig.queue.countdownSeconds after the queue reaches playersToStartCountdown, or at once
--     with playersToStartAtOnce queued. The queued count and the timer show on the pad's display.
--   * Practice: standing on it starts a solo practice match at once.
-- One match runs per server (RoundService). While it runs both displays show "Match in progress"
-- and nobody queues. Players in the hub who fall or slip outside it are sent back to the spawn.
--
-- Match participants' avatars are parked out of sight (HubConfig.parkPosition) and anchored for
-- the whole match, and are sent back to the hub when the match ends, or earlier when a knocked-out
-- player asks to leave (RequestLeaveMatch). A participant who rejoins mid-match is parked again.
--
-- Public state, replicated to every client (server-to-client only):
--   Player attribute InMatch   boolean  true while the player is in the running match (clients show
--                                       the board camera and match HUD), false in the hub
--   Player attribute Queued    boolean  standing on the Play pad
--   ReplicatedStorage.HubState attributes
--     Queued       number  players queued on the Play pad
--     StartsAt     number  workspace:GetServerTimeNow() when the queued match starts (0 if no timer)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local HubConfig = require(ReplicatedStorage.Shared.HubConfig)
local RemoteNames = require(ReplicatedStorage.Shared.RemoteNames)

local HubBuilder = require(script.Parent.HubBuilder)
local Remotes = require(script.Parent.Remotes)
local RoundService = require(script.Parent.RoundService)

local HubService = {}

local QUEUE = HubConfig.queue

local hubState: Folder
local pads: { play: HubBuilder.Pad, practice: HubBuilder.Pad }
local leaderboards: { [string]: HubBuilder.Board } = {}
local inMatch: { [number]: boolean } = {} -- UserIds whose avatar belongs to the running match
local queuedSince: { [number]: number } = {} -- UserId -> os.clock() when they stepped on the pad
local countdownEndsAt: number? = nil -- server time

local function rootOf(player: Player): BasePart?
	local character = player.Character
	return character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

-- True if the player's avatar stands on (or just above) the pad.
local function isOnPad(player: Player, which: HubBuilder.Pad): boolean
	local character = player.Character
	local root = rootOf(player)
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not root or not humanoid or humanoid.Health <= 0 then
		return false
	end
	local position = root.Position
	local height = position.Y - which.top
	if height < 0 or height > HubConfig.standHeight then
		return false
	end
	if which.kind == "rect" then
		return position.X >= which.min.X
			and position.X <= which.max.X
			and position.Z >= which.min.Z
			and position.Z <= which.max.Z
	end
	local flat = Vector3.new(position.X - which.center.X, 0, position.Z - which.center.Z)
	return flat.Magnitude <= which.radius
end

-- Lights the first `count` marked spots of a pad, one per queued player.
local function lightSpots(which: HubBuilder.Pad, count: number)
	for index, spot in which.spots do
		local lit = index <= count
		local color = if lit then which.color else HubConfig.colors.spotOff
		if spot.Color ~= color then
			spot.Color = color
			spot.Material = if lit then Enum.Material.Neon else Enum.Material.Metal -- unlit as built
		end
	end
end

-- Anchors the avatar out of sight for the match.
local function park(player: Player, index: number)
	local character = player.Character
	local root = character and character:WaitForChild("HumanoidRootPart", 5) :: BasePart?
	if not character or not root or not inMatch[player.UserId] then
		return
	end
	root.Anchored = true
	character:PivotTo(CFrame.new(HubConfig.parkPosition + Vector3.new(index * 4, 0, 0)))
end

-- Sends the avatar back to the hub's spawn, free to move, facing the pads.
local function toSpawn(player: Player)
	local character = player.Character
	local root = rootOf(player)
	if not character or not root then
		return
	end
	local spread = Vector3.new(math.random(-3, 3), 0, math.random(-2, 2))
	character:PivotTo(CFrame.new(HubBuilder.spawnPosition() + spread))
	root.AssemblyLinearVelocity = Vector3.zero
	root.Anchored = false
end

local function setInMatch(player: Player, value: boolean)
	if value then
		inMatch[player.UserId] = true
	else
		inMatch[player.UserId] = nil
	end
	player:SetAttribute("InMatch", value)
	if value then
		player:SetAttribute("Queued", false)
		task.spawn(park, player, #Players:GetPlayers())
	else
		toSpawn(player)
	end
end

local function startMatch(players: { Player }, isPractice: boolean?)
	local participants = RoundService.startMatch(players, isPractice)
	if not participants then
		return
	end
	table.clear(queuedSince)
	countdownEndsAt = nil
	for _, userId in participants do
		local player = Players:GetPlayerByUserId(userId)
		if player then
			setInMatch(player, true)
		end
	end
end

local function setStatus(which: HubBuilder.Pad, text: string)
	if which.status.Text ~= text then
		which.status.Text = text
	end
end

-- Players in the hub who fell or got outside it go back to the spawn.
local function rescue()
	for _, player in Players:GetPlayers() do
		local root = rootOf(player)
		if root and not inMatch[player.UserId] and not root.Anchored and HubBuilder.isOutside(root.Position) then
			toSpawn(player)
		end
	end
end

-- One check of the pads: who is queued, whether the countdown runs, and starting matches.
local function poll()
	rescue()
	local now = workspace:GetServerTimeNow()
	if RoundService.isRunning() then
		for _, player in Players:GetPlayers() do
			if player:GetAttribute("Queued") then
				player:SetAttribute("Queued", false)
			end
		end
		table.clear(queuedSince)
		countdownEndsAt = nil
		hubState:SetAttribute("Queued", 0)
		hubState:SetAttribute("StartsAt", 0)
		setStatus(pads.play, "MATCH IN PROGRESS")
		setStatus(pads.practice, "MATCH IN PROGRESS")
		lightSpots(pads.play, 0)
		return
	end

	-- Practice: the first player found on the pad starts at once.
	for _, player in Players:GetPlayers() do
		if not inMatch[player.UserId] and isOnPad(player, pads.practice) then
			startMatch({ player }, true)
			return
		end
	end

	-- The queue, oldest first.
	local queued = {}
	for _, player in Players:GetPlayers() do
		local on = not inMatch[player.UserId] and isOnPad(player, pads.play)
		if on and not queuedSince[player.UserId] then
			queuedSince[player.UserId] = os.clock()
		elseif not on then
			queuedSince[player.UserId] = nil
		end
		if player:GetAttribute("Queued") ~= on then
			player:SetAttribute("Queued", on)
		end
		if on then
			table.insert(queued, player)
		end
	end
	table.sort(queued, function(a, b)
		return queuedSince[a.UserId] < queuedSince[b.UserId]
	end)

	if #queued >= QUEUE.playersToStartAtOnce then
		startMatch(queued)
		return
	end
	if #queued >= QUEUE.playersToStartCountdown then
		countdownEndsAt = countdownEndsAt or now + QUEUE.countdownSeconds
		if now >= countdownEndsAt :: number then
			startMatch(queued)
			return
		end
	else
		countdownEndsAt = nil
	end

	hubState:SetAttribute("Queued", #queued)
	hubState:SetAttribute("StartsAt", countdownEndsAt or 0)
	lightSpots(pads.play, #queued)
	local count = string.format("%d/%d queued", #queued, QUEUE.playersToStartAtOnce)
	if countdownEndsAt then
		setStatus(pads.play, string.format("%s  ·  starts in %d", count, math.max(0, math.ceil(countdownEndsAt - now))))
	else
		local missing = QUEUE.playersToStartCountdown - #queued
		setStatus(pads.play, string.format("%s  ·  need %d more", count, missing))
	end
	setStatus(pads.practice, "Ready  ·  starts as you enter")
end

-- Shows a hall of fame leaderboard (HubConfig.hall.boards id): rows of { name, value }, best first.
-- Nothing calls this yet (player stats are not saved), so every board shows its placeholder; a
-- stats service can call it whenever its numbers change.
function HubService.setLeaderboard(boardId: string, rows: { { name: string, value: string } })
	local board = leaderboards[boardId]
	if board then
		HubBuilder.setLeaderboard(board, rows)
	end
end

function HubService.start()
	hubState = Instance.new("Folder")
	hubState.Name = "HubState"
	hubState:SetAttribute("Queued", 0)
	hubState:SetAttribute("StartsAt", 0)
	hubState.Parent = ReplicatedStorage
	pads, leaderboards = HubBuilder.build()

	local function onPlayer(player: Player)
		-- A participant who rejoins the running match goes straight back to it.
		player:SetAttribute("InMatch", inMatch[player.UserId] == true)
		player:SetAttribute("Queued", false)
		player.CharacterAdded:Connect(function()
			if inMatch[player.UserId] then
				park(player, 1)
			end
		end)
		if player.Character and inMatch[player.UserId] then
			task.spawn(park, player, 1)
		end
	end
	Players.PlayerAdded:Connect(onPlayer)
	for _, player in Players:GetPlayers() do
		onPlayer(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		queuedSince[player.UserId] = nil
	end)

	-- Knocked out (or the match is decided): back to the hub now.
	Remotes.create(RemoteNames.RequestLeaveMatch).OnServerEvent:Connect(function(player: Player)
		if inMatch[player.UserId] and RoundService.canLeave(player.UserId) then
			setInMatch(player, false)
		end
	end)

	-- A practice match can be left at any time: it ends and the player is back in the hub at once.
	-- RoundService refuses this for player matches.
	Remotes.create(RemoteNames.RequestLeavePractice).OnServerEvent:Connect(function(player: Player)
		if inMatch[player.UserId] and RoundService.leavePractice(player.UserId) then
			setInMatch(player, false)
		end
	end)

	RoundService.onMatchEnded(function(participants)
		for _, userId in participants do
			local player = Players:GetPlayerByUserId(userId)
			if player and inMatch[userId] then
				setInMatch(player, false)
			end
			inMatch[userId] = nil
		end
	end)

	task.spawn(function()
		while true do
			local ok, err = pcall(poll)
			if not ok then
				warn("[HubService] " .. tostring(err))
			end
			task.wait(HubConfig.pollInterval)
		end
	end)
end

return HubService
