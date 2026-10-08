-- Shows the local player's own board and bench outside of combat, and turns clicks into
-- placement requests. Click a unit to select it, then click a cell in your half, a bench slot, or
-- another unit (to swap the two) to ask the server to move it there. Click the selected unit again
-- to deselect it. The client never changes board state itself; it only redraws when the server
-- sends BoardUpdated.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BoardConfig = require(Shared:WaitForChild("BoardConfig"))
local Phase = require(Shared:WaitForChild("Phase"))
local RemoteNames = require(Shared:WaitForChild("RemoteNames"))
local UnitConfig = require(Shared:WaitForChild("UnitConfig"))

local Arena = require(script.Parent.Arena)
local CharacterLook = require(script.Parent.CharacterLook)
local TraitIcon = require(script.Parent.TraitIcon)
local UnitView = require(script.Parent.UnitView)

local BoardController = {}

local matchState: Instance
local requestMoveUnit: RemoteEvent
local units = {} -- latest BoardUpdated snapshot
local views: { [string]: UnitView.UnitView } = {}
local selectedId: string? = nil
local unitsChangedCallbacks: { ({ any }) -> () } = {}

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
		local stats = UnitConfig[unit.unitType]
		local look = CharacterLook.of(unit.unitType)
		local view = UnitView.new(look.name, unit.starLevel, look.color, position, Arena.folder, {
			maxHealth = stats.health,
			mana = stats.startingMana,
			maxMana = stats.maxMana,
			traits = TraitIcon.traitsOf(stats),
			look = look.figure,
		})
		view.part:SetAttribute("UnitId", unit.id)
		view.part:SetAttribute("UnitType", unit.unitType) -- for the hover tooltip
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
	if unitId and (selectedId == nil or unitId == selectedId) then
		selectUnit(if unitId == selectedId then nil else unitId)
		return
	end
	if not selectedId then
		return
	end

	-- Clicking another unit targets its place, which the server turns into a swap.
	if unitId then
		for _, unit in units do
			if unit.id == unitId then
				local target = if unit.slot then { slot = unit.slot } else { column = unit.column, row = unit.row }
				requestMoveUnit:FireServer(selectedId, target)
			end
		end
		selectUnit(nil)
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

-- The selected unit's id, used by the sell button.
function BoardController.getSelectedUnitId(): string?
	return selectedId
end

-- Calls `callback(units)` with the latest snapshot whenever the server sends BoardUpdated.
function BoardController.onUnitsChanged(callback: ({ any }) -> ())
	table.insert(unitsChangedCallbacks, callback)
	callback(units)
end

function BoardController.start()
	matchState = ReplicatedStorage:WaitForChild("MatchState")
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	requestMoveUnit = remotes:WaitForChild(RemoteNames.RequestMoveUnit)

	remotes:WaitForChild(RemoteNames.BoardUpdated).OnClientEvent:Connect(function(newUnits)
		units = newUnits
		render()
		for _, callback in unitsChangedCallbacks do
			callback(units)
		end
	end)
	matchState:GetAttributeChangedSignal("Phase"):Connect(render)

	-- Idle animations for the units on the board and bench.
	local lastFrame = os.clock()
	RunService.RenderStepped:Connect(function()
		local now = os.clock()
		local dt = now - lastFrame
		lastFrame = now
		for _, view in views do
			UnitView.update(view, now, dt)
		end
	end)

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
