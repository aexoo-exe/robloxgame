-- The match intro (Phase.Intro, MatchConfig.introDuration seconds before round 1): a banner naming
-- the player's starting unit ("Your starting unit: <name>") with a countdown ("Match starts in N"),
-- and the unit outlined on the board (BoardController.setSpotlight). The starting units are
-- whatever the server put on the board for the match start. Presentation only.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Phase = require(Shared:WaitForChild("Phase"))
local SkinConfig = require(Shared:WaitForChild("SkinConfig"))
local UITheme = require(Shared:WaitForChild("UITheme"))

local BoardController = require(script.Parent.BoardController)
local UI = require(script.Parent.UI)

local MatchIntro = {}

local COLORS = UITheme.colors
local FONTS = UITheme.fonts
local SIZES = UITheme.sizes

function MatchIntro.start()
	local matchState = ReplicatedStorage:WaitForChild("MatchState")
	local _, root = UI.screen("MatchIntro", 8)

	local panel = UI.panel(root, UDim2.fromOffset(0, 0))
	panel.AutomaticSize = Enum.AutomaticSize.XY
	panel.AnchorPoint = Vector2.new(0.5, 0)
	panel.Position = UDim2.new(0.5, 0, 0, SIZES.topBarHeight + 18)
	panel.Visible = false
	local content = Instance.new("Frame")
	content.BackgroundTransparency = 1
	content.AutomaticSize = Enum.AutomaticSize.XY
	UI.padding(content, 12)
	UI.list(content, 6, Enum.HorizontalAlignment.Center)
	content.Parent = panel
	local title = UI.text(content, "", SIZES.textHuge - 8, FONTS.display, COLORS.gold)
	title.LayoutOrder = 1
	local countdown = UI.text(content, "", SIZES.textLarge, FONTS.display)
	countdown.LayoutOrder = 2

	local units = {}
	local shown = false
	local shownSeconds = -1

	local function refreshUnits()
		local ids, names = {}, {}
		for _, unit in units do
			table.insert(ids, unit.id)
			local skin = SkinConfig[unit.unitType]
			table.insert(names, if skin then skin.name else unit.unitType)
		end
		title.Text = (if #names > 1 then "Your starting units: " else "Your starting unit: ") .. table.concat(names, ", ")
		BoardController.setSpotlight(if shown then ids else {})
	end

	BoardController.onUnitsChanged(function(newUnits)
		units = newUnits
		if shown then
			refreshUnits()
		end
	end)

	RunService.RenderStepped:Connect(function()
		local intro = matchState:GetAttribute("Phase") == Phase.Intro
		if intro ~= shown then
			shown = intro
			panel.Visible = intro
			refreshUnits()
			if intro then
				UI.pop(panel, 1.1)
			end
		end
		if intro then
			local endsAt = matchState:GetAttribute("PhaseEndsAt") or 0
			local seconds = math.max(0, math.ceil(endsAt - workspace:GetServerTimeNow()))
			if seconds ~= shownSeconds then
				shownSeconds = seconds
				countdown.Text = string.format("Match starts in %d", seconds)
				UI.pop(countdown)
			end
		end
	end)
end

return MatchIntro
