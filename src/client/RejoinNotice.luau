-- Rejoining a running match: the client asks the server for its match state once everything has
-- started (RequestMatchSync: board, shop and, during Combat, this round's fight, which plays from
-- the current moment). If the player is back in a match already under way, a short banner says so
-- and when the current phase ends. Presentation only.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Phase = require(Shared:WaitForChild("Phase"))
local RemoteNames = require(Shared:WaitForChild("RemoteNames"))
local UITheme = require(Shared:WaitForChild("UITheme"))

local UI = require(script.Parent.UI)

local RejoinNotice = {}

local SHOW_SECONDS = 5
-- How long after the client starts the server may take to set InMatch for a rejoining player.
local WAIT_FOR_MATCH_SECONDS = 4

-- "You're back! The fight ends in 12s" and the like, for the current phase.
local function message(matchState: Instance): string
	local phase = matchState:GetAttribute("Phase")
	local left = math.max(0, math.ceil((matchState:GetAttribute("PhaseEndsAt") or 0) - workspace:GetServerTimeNow()))
	if phase == Phase.Combat then
		return string.format("You're back! This fight ends in %ds", left)
	elseif phase == Phase.Preparation then
		return string.format("You're back! Plan your board: %ds left", left)
	end
	return string.format("You're back! The next round starts in %ds", left)
end

function RejoinNotice.start()
	local localPlayer = Players.LocalPlayer
	local matchState = ReplicatedStorage:WaitForChild("MatchState")
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	remotes:WaitForChild(RemoteNames.RequestMatchSync):FireServer()

	local _, root = UI.screen("RejoinNotice", 10)
	local banner = UI.panel(root, UDim2.fromOffset(0, 0), false)
	banner.AutomaticSize = Enum.AutomaticSize.XY
	banner.AnchorPoint = Vector2.new(0.5, 0)
	banner.Position = UDim2.new(0.5, 0, 0, UITheme.sizes.topBarHeight + 60)
	banner.BackgroundColor3 = UITheme.colors.buy
	banner.Visible = false
	local label = UI.text(banner, "", UITheme.sizes.textLarge, UITheme.fonts.display)
	UI.padding(banner, 10)

	task.spawn(function()
		local waitUntil = os.clock() + WAIT_FOR_MATCH_SECONDS
		while localPlayer:GetAttribute("InMatch") ~= true and os.clock() < waitUntil do
			task.wait(0.25)
		end
		local round = matchState:GetAttribute("Round") or 0
		if localPlayer:GetAttribute("InMatch") ~= true or round < 1 then
			return
		end
		banner.Visible = true
		UI.pop(banner, 1.1)
		local hideAt = os.clock() + SHOW_SECONDS
		while os.clock() < hideAt do
			label.Text = message(matchState)
			task.wait(0.25)
		end
		banner.Visible = false
	end)
end

return RejoinNotice
