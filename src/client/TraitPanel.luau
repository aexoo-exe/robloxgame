-- Placeholder trait panel in the top-left corner. During Preparation it lists the traits of the
-- units the player has placed on the board (bench units do not count), updating as units move.
-- During Combat and Results it shows the traits the server used for the fight: the player's own
-- column and an opponent column. Each row shows the trait's count against its next breakpoint (or
-- its top breakpoint once reached); active traits are highlighted. Presentation only.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Phase = require(Shared:WaitForChild("Phase"))
local RemoteNames = require(Shared:WaitForChild("RemoteNames"))
local RenderConfig = require(Shared:WaitForChild("RenderConfig"))
local Traits = require(Shared:WaitForChild("Traits"))

local BoardController = require(script.Parent.BoardController)

local TraitPanel = {}

local COLUMN_WIDTH = 170
local ROW_HEIGHT = 20
local TOP = 64 -- below Roblox's top bar buttons

type Column = { frame: Frame, list: Frame }

local function newColumn(parent: Instance, x: number, title: string): Column
	local frame = Instance.new("Frame")
	frame.Position = UDim2.fromOffset(x, TOP)
	frame.Size = UDim2.fromOffset(COLUMN_WIDTH, 0)
	frame.AutomaticSize = Enum.AutomaticSize.Y
	frame.BackgroundColor3 = Color3.new(0, 0, 0)
	frame.BackgroundTransparency = 0.35
	frame.Parent = parent

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 6)
	padding.PaddingBottom = UDim.new(0, 6)
	padding.PaddingLeft = UDim.new(0, 6)
	padding.PaddingRight = UDim.new(0, 6)
	padding.Parent = frame

	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 3)
	layout.Parent = frame

	local heading = Instance.new("TextLabel")
	heading.LayoutOrder = 0
	heading.Size = UDim2.new(1, 0, 0, 18)
	heading.BackgroundTransparency = 1
	heading.Text = title
	heading.TextColor3 = Color3.new(1, 1, 1)
	heading.Font = Enum.Font.GothamBold
	heading.TextSize = 14
	heading.TextXAlignment = Enum.TextXAlignment.Left
	heading.Parent = frame

	local list = Instance.new("Frame")
	list.LayoutOrder = 1
	list.Size = UDim2.fromScale(1, 0)
	list.AutomaticSize = Enum.AutomaticSize.Y
	list.BackgroundTransparency = 1
	list.Parent = frame
	local listLayout = Instance.new("UIListLayout")
	listLayout.SortOrder = Enum.SortOrder.LayoutOrder
	listLayout.Padding = UDim.new(0, 2)
	listLayout.Parent = list

	return { frame = frame, list = list }
end

local function render(column: Column, summary: { Traits.TraitState })
	column.list:ClearAllChildren()
	local listLayout = Instance.new("UIListLayout")
	listLayout.SortOrder = Enum.SortOrder.LayoutOrder
	listLayout.Padding = UDim.new(0, 2)
	listLayout.Parent = column.list

	if #summary == 0 then
		local empty = Instance.new("TextLabel")
		empty.Size = UDim2.new(1, 0, 0, ROW_HEIGHT)
		empty.BackgroundTransparency = 1
		empty.Text = "No traits yet"
		empty.TextColor3 = RenderConfig.traitInactiveTextColor
		empty.Font = Enum.Font.Gotham
		empty.TextSize = 13
		empty.TextXAlignment = Enum.TextXAlignment.Left
		empty.Parent = column.list
		return
	end

	for order, state in summary do
		local row = Instance.new("TextLabel")
		row.LayoutOrder = order
		row.Size = UDim2.new(1, 0, 0, ROW_HEIGHT)
		row.BorderSizePixel = 0
		row.BackgroundColor3 = if state.active then RenderConfig.traitActiveColor else RenderConfig.traitInactiveColor
		row.TextColor3 = if state.active then RenderConfig.traitActiveTextColor else RenderConfig.traitInactiveTextColor
		row.Font = if state.active then Enum.Font.GothamBold else Enum.Font.Gotham
		row.TextSize = 13
		row.TextXAlignment = Enum.TextXAlignment.Left
		-- Count against the next breakpoint, or against the top one once it is reached.
		local target = state.nextCount or state.reached
		row.Text = string.format("  %s  %d / %d", state.name, state.count, target)
		row.Parent = column.list
	end
end

-- Traits of the placed units in a BoardUpdated snapshot (bench units have no column).
local function boardSummary(units: { any }): { Traits.TraitState }
	local placed = {}
	for _, unit in units do
		if unit.column then
			table.insert(placed, unit)
		end
	end
	return Traits.summary(placed)
end

function TraitPanel.start()
	local matchState = ReplicatedStorage:WaitForChild("MatchState")
	local remotes = ReplicatedStorage:WaitForChild("Remotes")

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "TraitPanel"
	screenGui.ResetOnSpawn = false
	local own = newColumn(screenGui, 8, "Your traits")
	local opponent = newColumn(screenGui, 8 + COLUMN_WIDTH + 6, "Opponent traits")
	opponent.frame.Visible = false

	local latestUnits = {}
	local inFight = false

	local function showBoard()
		inFight = false
		opponent.frame.Visible = false
		render(own, boardSummary(latestUnits))
	end

	BoardController.onUnitsChanged(function(units)
		latestUnits = units
		if not inFight then
			render(own, boardSummary(units))
		end
	end)

	remotes:WaitForChild(RemoteNames.CombatStarted).OnClientEvent:Connect(function(payload)
		if not payload.traits then
			return
		end
		inFight = true
		-- Same side choice as the combat playback: spectators see side 1 as their own.
		local localSide = if payload.sideUserIds[2] == Players.LocalPlayer.UserId then 2 else 1
		render(own, payload.traits[localSide])
		render(opponent, payload.traits[3 - localSide])
		opponent.frame.Visible = true
	end)

	matchState:GetAttributeChangedSignal("Phase"):Connect(function()
		local phase = matchState:GetAttribute("Phase")
		if phase == Phase.Preparation or phase == Phase.Waiting then
			showBoard()
		end
	end)

	showBoard()
	screenGui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
end

return TraitPanel
