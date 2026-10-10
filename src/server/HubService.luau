-- The hub: the area players spawn into and walk around between matches, built from placeholder
-- parts (HubConfig), with two pads and a sign for each:
--   * Play: standing on it queues the player; stepping off leaves the queue. A match starts
--     HubConfig.queue.countdownSeconds after the queue reaches playersToStartCountdown, or at once
--     with playersToStartAtOnce queued. The queued count and the timer show above the pad.
--   * Practice: standing on it starts a solo practice match at once.
-- One match runs per server (RoundService). While it runs both pads show "Match in progress" and
-- nobody queues.
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

local Remotes = require(script.Parent.Remotes)
local RoundService = require(script.Parent.RoundService)

local HubService = {}

local QUEUE = HubConfig.queue

type Pad = { part: Part, label: TextLabel, sub: TextLabel }

local hubState: Folder
local pads: { [string]: Pad } = {}
local inMatch: { [number]: boolean } = {} -- UserIds whose avatar belongs to the running match
local queuedSince: { [number]: number } = {} -- UserId -> os.clock() when they stepped on the pad
local countdownEndsAt: number? = nil -- server time

local function hubPosition(offset: Vector3): Vector3
	return HubConfig.center + offset
end

local function part(parent: Instance, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material?): Part
	local instance = Instance.new("Part")
	instance.Anchored = true
	instance.Size = size
	instance.CFrame = cframe
	instance.Color = color
	instance.Material = material or Enum.Material.SmoothPlastic
	instance.TopSurface = Enum.SurfaceType.Smooth
	instance.BottomSurface = Enum.SurfaceType.Smooth
	instance.Parent = parent
	return instance
end

-- A text label filling a GUI, white with a dark outline.
local function textLabel(parent: Instance, text: string, position: UDim2, size: UDim2, color: Color3?): TextLabel
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Position = position
	label.Size = size
	label.Text = text
	label.TextColor3 = color or Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0.3
	label.TextScaled = true
	label.TextWrapped = true
	label.Font = Enum.Font.GothamBlack
	label.Parent = parent
	return label
end

-- A standing sign facing the spawn (+Z) with a title and a body text.
local function sign(parent: Instance, position: Vector3, title: string, body: string, color: Color3)
	local board = part(parent, Vector3.new(14, 8, 0.6), CFrame.new(position + Vector3.new(0, 5.5, 0)), HubConfig.signColor)
	board.Name = "Sign"
	part(parent, Vector3.new(0.6, 2, 0.6), CFrame.new(position + Vector3.new(-5, 1, 0)), HubConfig.wallColor)
	part(parent, Vector3.new(0.6, 2, 0.6), CFrame.new(position + Vector3.new(5, 1, 0)), HubConfig.wallColor)
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Back -- the face toward +Z
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.Parent = board
	local stripe = Instance.new("Frame")
	stripe.Size = UDim2.new(1, 0, 0.06, 0)
	stripe.BackgroundColor3 = color
	stripe.BorderSizePixel = 0
	stripe.Parent = gui
	textLabel(gui, title, UDim2.fromScale(0.05, 0.1), UDim2.fromScale(0.9, 0.26), color)
	local text = textLabel(gui, body, UDim2.fromScale(0.07, 0.42), UDim2.fromScale(0.86, 0.5))
	text.Font = Enum.Font.GothamBold
end

-- A pad: a flat slab with a bright rim, and a floating label above it.
local function pad(parent: Instance, name: string, config): Pad
	local center = hubPosition(config.offset)
	local size = config.size
	part(parent, Vector3.new(size + 1, 0.5, size + 1), CFrame.new(center + Vector3.new(0, 0.75, 0)), config.color, Enum.Material.Neon)
	local top = part(
		parent,
		Vector3.new(size, 0.6, size),
		CFrame.new(center + Vector3.new(0, 0.85, 0)),
		config.color:Lerp(Color3.new(0, 0, 0), 0.45),
		Enum.Material.Metal
	)
	top.Name = name .. "Pad"

	local anchor = part(parent, Vector3.new(1, 1, 1), CFrame.new(center + Vector3.new(0, 9, 0)), config.color)
	anchor.Transparency = 1
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.fromScale(14, 4)
	billboard.LightInfluence = 0
	billboard.MaxDistance = 150
	billboard.Parent = anchor
	local label = textLabel(billboard, "", UDim2.fromScale(0, 0), UDim2.fromScale(1, 0.55), config.color)
	local sub = textLabel(billboard, "", UDim2.fromScale(0, 0.58), UDim2.fromScale(1, 0.42))
	return { part = top, label = label, sub = sub }
end

local function build()
	local folder = Instance.new("Folder")
	folder.Name = "Hub"
	local center = HubConfig.center
	local size = HubConfig.floorSize
	part(folder, Vector3.new(size.X, 1, size.Y), CFrame.new(center + Vector3.new(0, 0.5, 0)), HubConfig.floorColor, Enum.Material.Slate).Name =
		"Floor"
	-- Low walls on three sides; the spawn side (+Z) has a wall too, so nobody walks off the hub.
	local height = HubConfig.wallHeight
	for _, side in { -1, 1 } do
		part(
			folder,
			Vector3.new(size.X + 2, height, 1),
			CFrame.new(center + Vector3.new(0, 1 + height / 2, side * (size.Y / 2 + 0.5))),
			HubConfig.wallColor
		)
		part(
			folder,
			Vector3.new(1, height, size.Y),
			CFrame.new(center + Vector3.new(side * (size.X / 2 + 0.5), 1 + height / 2, 0)),
			HubConfig.wallColor
		)
	end

	local spawn = Instance.new("SpawnLocation")
	spawn.Anchored = true
	spawn.Neutral = true
	spawn.Duration = 0 -- no spawn force field
	spawn.Size = Vector3.new(8, 0.4, 8)
	spawn.CFrame = CFrame.new(hubPosition(HubConfig.spawnOffset) + Vector3.new(0, 1.2, 0))
	spawn.Color = HubConfig.wallColor
	spawn.Material = Enum.Material.SmoothPlastic
	spawn.Parent = folder

	local play = HubConfig.pads.play
	local practice = HubConfig.pads.practice
	pads.play = pad(folder, "Play", play)
	pads.practice = pad(folder, "Practice", practice)
	sign(
		folder,
		hubPosition(play.offset + Vector3.new(0, 1, -(play.size / 2 + 3))),
		"PLAY",
		string.format(
			"Stand on this pad to queue. A match starts %d seconds after a second player joins, or at once with %d. Step off to leave the queue.",
			QUEUE.countdownSeconds,
			QUEUE.playersToStartAtOnce
		),
		play.color
	)
	sign(
		folder,
		hubPosition(practice.offset + Vector3.new(0, 1, -(practice.size / 2 + 3))),
		"PRACTICE",
		"Stand on this pad to start a solo practice match right away, against creeps and practice boards.",
		practice.color
	)
	folder.Parent = workspace
end

-- True if the player's avatar stands on (or just above) the pad.
local function isOnPad(player: Player, padPart: Part): boolean
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not root or not humanoid or humanoid.Health <= 0 then
		return false
	end
	local relative = padPart.CFrame:PointToObjectSpace(root.Position)
	local half = padPart.Size / 2
	return math.abs(relative.X) <= half.X
		and math.abs(relative.Z) <= half.Z
		and relative.Y >= 0
		and relative.Y <= half.Y + HubConfig.standHeight
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

-- Sends the avatar back to the hub's spawn, free to move.
local function unpark(player: Player)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not character or not root then
		return
	end
	local spread = Vector3.new(math.random(-6, 6), 4, math.random(-3, 3))
	character:PivotTo(CFrame.new(hubPosition(HubConfig.spawnOffset) + spread))
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
		unpark(player)
	end
end

local function startMatch(players: { Player })
	local participants = RoundService.startMatch(players)
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

local function setPadText(which: Pad, label: string, sub: string)
	if which.label.Text ~= label then
		which.label.Text = label
	end
	if which.sub.Text ~= sub then
		which.sub.Text = sub
	end
end

-- One check of the pads: who is queued, whether the countdown runs, and starting matches.
local function poll()
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
		setPadText(pads.play, "MATCH IN PROGRESS", "Queue opens when it ends")
		setPadText(pads.practice, "MATCH IN PROGRESS", "Practice opens when it ends")
		return
	end

	-- Practice: the first player found on the pad starts at once.
	for _, player in Players:GetPlayers() do
		if not inMatch[player.UserId] and isOnPad(player, pads.practice.part) then
			startMatch({ player })
			return
		end
	end

	-- The queue, oldest first.
	local queued = {}
	for _, player in Players:GetPlayers() do
		local on = not inMatch[player.UserId] and isOnPad(player, pads.play.part)
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
	local sub
	if countdownEndsAt then
		sub = string.format("Match starts in %d", math.max(0, math.ceil(countdownEndsAt - now)))
	else
		local missing = QUEUE.playersToStartCountdown - #queued
		sub = string.format("Waiting for %d more player%s", missing, if missing == 1 then "" else "s")
	end
	setPadText(pads.play, string.format("PLAY  %d/%d queued", #queued, QUEUE.playersToStartAtOnce), sub)
	setPadText(pads.practice, "PRACTICE", "Solo match, starts at once")
end

function HubService.start()
	hubState = Instance.new("Folder")
	hubState.Name = "HubState"
	hubState:SetAttribute("Queued", 0)
	hubState:SetAttribute("StartsAt", 0)
	hubState.Parent = ReplicatedStorage
	build()

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
