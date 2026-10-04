-- Shows the local player's own board and bench outside of combat, and turns clicks into
-- placement requests. Click a unit to select it, then click a cell in your half or a bench slot
-- to ask the server to move it there. The client never changes board state itself; it only
-- redraws when the server sends BoardUpdated.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BoardConfig = require(Shared:WaitForChild("BoardConfig"))
local Phase = require(Shared:WaitForChild("Phase"))
local RemoteNames = require(Shared:WaitForChild("RemoteNames"))
local RenderConfig = require(Shared:WaitForChild("RenderConfig"))

local Arena = require(script.Parent.Arena)
local UnitView = require(script.Parent.UnitView)

local BoardController = {}

local matchState: Instance
local requestMoveUnit: RemoteEvent
local units = {} -- latest BoardUpdated snapshot
local views: { [string]: UnitView.UnitView } = {}
local selectedId: string? = nil

local function currentPhase(): string?
	return matchState:GetAttribute("Phase")
end

local function selectUnit(unitId: string?)
	if selectedId and views[selectedId] then
		UnitView.setSelected(views[selectedId], false)
	end
	selectedId = if unitId and views[unitId] then unitId else nil
	if selectedId then
		UnitView.setSelected(views[selectedId], true)
	end
end

local function render()
	for _, view in views do
		UnitView.destroy(view)
	end
	table.clear(views)
	selectedId = nil

	-- The combat playback owns the field during Combat and Results.
	local phase = currentPhase()
	if phase ~= Phase.Waiting and phase ~= Phase.Preparation then
		return
	end

	for _, unit in units do
		local position = if unit.slot then Arena.benchPosition(unit.slot) else Arena.cellPosition(unit.column, unit.row)
		local view = UnitView.new(unit.unitType, RenderConfig.ownUnitColor, position, Arena.folder)
		view.part:SetAttribute("UnitId", unit.id)
		views[unit.id] = view
	end
end

local function onClick(screenPosition: Vector2)
	if currentPhase() ~= Phase.Preparation then
		return
	end
	local hit = Arena.raycast(screenPosition)
	if not hit then
		selectUnit(nil)
		return
	end

	local part = hit.Instance
	local unitId = part:GetAttribute("UnitId")
	if unitId then
		selectUnit(unitId)
		return
	end
	if not selectedId then
		return
	end

	local slot = part:GetAttribute("Slot")
	local column, row = part:GetAttribute("Column"), part:GetAttribute("Row")
	if slot then
		requestMoveUnit:FireServer(selectedId, { slot = slot })
	elseif column and row and row <= BoardConfig.rows then
		requestMoveUnit:FireServer(selectedId, { column = column, row = row })
	end
	selectUnit(nil)
end

function BoardController.start()
	matchState = ReplicatedStorage:WaitForChild("MatchState")
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	requestMoveUnit = remotes:WaitForChild(RemoteNames.RequestMoveUnit)

	remotes:WaitForChild(RemoteNames.BoardUpdated).OnClientEvent:Connect(function(newUnits)
		units = newUnits
		render()
	end)
	matchState:GetAttributeChangedSignal("Phase"):Connect(render)

	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed then
			return
		end
		if
			input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
		then
			onClick(Vector2.new(input.Position.X, input.Position.Y))
		end
	end)

	render()
end

return BoardController
