-- Shows the local player's own board and bench outside of combat, and turns input into placement
-- requests. A unit can be moved two ways:
--   * Drag it (mouse or touch) onto a cell in your half, a bench slot, or another unit (to swap the
--     two). While dragging, every place it may go is tinted, and the place under the pointer is
--     highlighted green (valid) or red (invalid: the enemy half, or an empty cell when the board
--     already holds as many units as your level).
--   * Click it to select it, then click a cell, a bench slot or another unit. Click the selected
--     unit again to deselect it. With a mouse, the place under the pointer is highlighted the same
--     way while a unit is selected.
-- The client never changes board state itself; it only asks the server and redraws when the server
-- sends BoardUpdated. A dropped unit waits where it was dropped; if the server sends nothing back
-- (a refused request), the board is redrawn from the last snapshot shortly after.

local GuiService = game:GetService("GuiService")
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

local DRAG_THRESHOLD = 8 -- pixels the pointer must move before a press becomes a drag
local DRAG_LIFT = 1 -- studs a dragged unit floats above the board
local REVERT_AFTER = 0.6 -- seconds to wait for the server's answer to a drop

local matchState: Instance
local requestMoveUnit: RemoteEvent
local units = {} -- latest BoardUpdated snapshot
local views: { [string]: UnitView.UnitView } = {}
local selectedId: string? = nil
local unitsChangedCallbacks: { ({ any }) -> () } = {}
local playerLevel: number? = nil -- the board's unit cap, from PlayerStateUpdated

-- A press on a unit: it becomes a drag once the pointer moves far enough, otherwise a click.
local press: { unitId: string, start: Vector2, input: InputObject }? = nil
local dragging = false
local pointer = Vector2.zero
local revertAt: number? = nil

local function currentPhase(): string?
	return matchState:GetAttribute("Phase")
end

local function unitById(unitId: string)
	for _, unit in units do
		if unit.id == unitId then
			return unit
		end
	end
	return nil
end

local function placeOf(unit): Arena.Target
	return if unit.slot then { slot = unit.slot } else { column = unit.column, row = unit.row }
end

local function positionOf(target: Arena.Target): Vector3
	return if target.slot then Arena.benchPosition(target.slot) else Arena.cellPosition(target.column, target.row)
end

local function samePlace(a: Arena.Target, b: Arena.Target): boolean
	return a.slot == b.slot and a.column == b.column and a.row == b.row
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

local function cancelDrag()
	press = nil
	dragging = false
	Arena.setDropZones(false)
	Arena.setHighlight(nil)
end

local function render()
	cancelDrag()
	revertAt = nil
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
		local stats = UnitConfig[unit.unitType]
		local look = CharacterLook.of(unit.unitType)
		local view = UnitView.new(look.name, unit.starLevel, look.color, positionOf(placeOf(unit)), Arena.folder, {
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

-- The place under a screen position for the unit `unitId`, and whether it may go there: a cell in
-- the local player's half, a bench slot, or another unit's place (a swap). A bench unit may not
-- move onto an empty cell when the board already holds as many units as the player's level (the
-- server enforces this too). Returns nil when the pointer is over no place.
local function placementAt(screenPosition: Vector2, unitId: string): (Arena.Target?, boolean)
	local hit = Arena.raycast(screenPosition)
	if not hit then
		return nil, false
	end
	local part = hit.Instance
	local otherId = part:GetAttribute("UnitId")
	if otherId then
		local other = if otherId ~= unitId then unitById(otherId) else nil
		return if other then placeOf(other) else nil, other ~= nil
	end
	local slot = part:GetAttribute("Slot")
	if slot then
		return { slot = slot }, true
	end
	local column, row = part:GetAttribute("Column"), part:GetAttribute("Row")
	if not column or not row then
		return nil, false
	end
	local target = { column = column, row = row }
	if row > BoardConfig.rows then
		return target, false
	end
	local placed = 0
	for _, unit in units do
		if unit.column == column and unit.row == row then
			return target, true -- occupied: a swap keeps the board's count
		end
		if unit.column then
			placed += 1
		end
	end
	local moving = unitById(unitId)
	if moving and moving.slot and playerLevel and placed >= playerLevel then
		return target, false
	end
	return target, true
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
		local unit = unitById(unitId)
		if unit then
			requestMoveUnit:FireServer(selectedId, placeOf(unit))
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

local function startDrag()
	local view = if press then views[press.unitId] else nil
	if not press or not view then
		cancelDrag()
		return
	end
	dragging = true
	selectUnit(press.unitId)
	view.part.CanQuery = false -- so the pointer finds the place under the unit, not the unit
	Arena.setDropZones(true)
end

-- Ends a drag at `screenPosition`: asks the server to move the unit if the place is valid, and
-- leaves the unit there until it answers; otherwise puts the unit back.
local function drop(screenPosition: Vector2)
	local unitId = (press :: any).unitId
	local view = views[unitId]
	local target, valid = placementAt(screenPosition, unitId)
	cancelDrag()
	selectUnit(nil)
	local unit = unitById(unitId)
	if not view or not unit then
		return
	end
	view.part.CanQuery = true
	local from = placeOf(unit)
	if target and valid and not samePlace(target, from) then
		requestMoveUnit:FireServer(unitId, target)
		UnitView.moveTo(view, positionOf(target))
		revertAt = os.clock() + REVERT_AFTER
	else
		UnitView.moveTo(view, positionOf(from))
	end
end

local function isPress(input: InputObject): boolean
	return input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch
end

-- True if `input` is the pointer of the current press: the mouse, or the same finger.
local function followsPress(input: InputObject): boolean
	if not press then
		return false
	end
	if press.input.UserInputType == Enum.UserInputType.Touch then
		return input == press.input
	end
	return input.UserInputType == Enum.UserInputType.MouseMovement
		or input.UserInputType == Enum.UserInputType.MouseButton1
end

local function onFrame(now: number, dt: number)
	if revertAt and now >= revertAt then
		render() -- the server did not answer the drop
	end

	if dragging and press then
		local view = views[press.unitId]
		local ground = Arena.groundPoint(pointer)
		if view and ground then
			UnitView.moveTo(view, ground + Vector3.new(0, DRAG_LIFT, 0))
		end
		Arena.setHighlight(placementAt(pointer, press.unitId))
	elseif selectedId and UserInputService.MouseEnabled and currentPhase() == Phase.Preparation then
		local mouse = UserInputService:GetMouseLocation() - GuiService:GetGuiInset()
		Arena.setHighlight(placementAt(mouse, selectedId))
	else
		Arena.setHighlight(nil)
	end

	-- Idle animations for the units on the board and bench.
	for _, view in views do
		UnitView.update(view, now, dt)
	end
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
	remotes:WaitForChild(RemoteNames.PlayerStateUpdated).OnClientEvent:Connect(function(view)
		playerLevel = view.level
	end)
	matchState:GetAttributeChangedSignal("Phase"):Connect(render)

	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed or not isPress(input) or currentPhase() ~= Phase.Preparation then
			return
		end
		local position = Vector2.new(input.Position.X, input.Position.Y)
		pointer = position
		-- A press on a unit (with nothing else selected) may become a drag; decide on release.
		local hit = Arena.raycast(position)
		local unitId = if hit then hit.Instance:GetAttribute("UnitId") else nil
		if unitId and (selectedId == nil or unitId == selectedId) and not press then
			press = { unitId = unitId, start = position, input = input }
			return
		end
		onClick(position)
	end)
	UserInputService.InputChanged:Connect(function(input)
		if not followsPress(input) then
			return
		end
		pointer = Vector2.new(input.Position.X, input.Position.Y)
		if press and not dragging and (pointer - press.start).Magnitude >= DRAG_THRESHOLD then
			startDrag()
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if not press or not isPress(input) or not followsPress(input) then
			return
		end
		if dragging then
			drop(Vector2.new(input.Position.X, input.Position.Y))
		else
			local start = press.start
			press = nil
			onClick(start)
		end
	end)

	local lastFrame = os.clock()
	RunService.RenderStepped:Connect(function()
		local now = os.clock()
		onFrame(now, now - lastFrame)
		lastFrame = now
	end)

	render()
end

return BoardController
