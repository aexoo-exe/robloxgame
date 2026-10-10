-- The hub's on-screen hint, top center, shown while the player is not in a match: how to use the
-- pads, the queue (count and countdown) while they stand on the Play pad, or "Match in progress"
-- while a match they are not in is running. Reads the server-owned HubState and MatchState
-- attributes and the player's Queued attribute (HubService). Presentation only.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local HubConfig = require(Shared:WaitForChild("HubConfig"))
local Phase = require(Shared:WaitForChild("Phase"))
local UITheme = require(Shared:WaitForChild("UITheme"))

local UI = require(script.Parent.UI)

local HubHud = {}

local COLORS = UITheme.colors
local FONTS = UITheme.fonts
local SIZES = UITheme.sizes
local REFRESH_SECONDS = 0.2

local root: Frame? = nil

function HubHud.setShown(shown: boolean)
	if root then
		root.Visible = shown
	end
end

function HubHud.start()
	local matchState = ReplicatedStorage:WaitForChild("MatchState")
	local hubState = ReplicatedStorage:WaitForChild("HubState")
	local player = Players.LocalPlayer
	local _, screenRoot = UI.screen("HubHud", 5, true)
	root = screenRoot

	local panel = UI.panel(screenRoot, UDim2.fromOffset(0, 0))
	panel.AutomaticSize = Enum.AutomaticSize.XY
	panel.AnchorPoint = Vector2.new(0.5, 0)
	panel.Position = UDim2.new(0.5, 0, 0, 10)
	local content = Instance.new("Frame")
	content.BackgroundTransparency = 1
	content.AutomaticSize = Enum.AutomaticSize.XY
	UI.padding(content, 10)
	UI.list(content, 4, Enum.HorizontalAlignment.Center)
	content.Parent = panel
	local title = UI.text(content, "", SIZES.textLarge, FONTS.display, COLORS.gold)
	title.LayoutOrder = 1
	local line = UI.text(content, "", SIZES.text, FONTS.body)
	line.LayoutOrder = 2

	local function refresh()
		local queue = HubConfig.queue
		if matchState:GetAttribute("Phase") ~= Phase.Waiting then
			title.Text = "MATCH IN PROGRESS"
			line.Text = "You can queue again when it ends."
		elseif player:GetAttribute("Queued") then
			local queued = hubState:GetAttribute("Queued") or 0
			local startsAt = hubState:GetAttribute("StartsAt") or 0
			title.Text = string.format("QUEUED  %d/%d", queued, queue.playersToStartAtOnce)
			if startsAt > 0 then
				local seconds = math.max(0, math.ceil(startsAt - workspace:GetServerTimeNow()))
				line.Text = string.format("Match starts in %d", seconds)
			else
				local missing = math.max(0, queue.playersToStartCountdown - queued)
				line.Text = string.format("Waiting for %d more player%s. Step off to leave.", missing, if missing == 1 then "" else "s")
			end
		else
			title.Text = "HUB"
			line.Text = "Stand on PLAY to queue, or on PRACTICE for a solo match."
		end
	end

	task.spawn(function()
		while true do
			refresh()
			task.wait(REFRESH_SECONDS)
		end
	end)
end

return HubHud
