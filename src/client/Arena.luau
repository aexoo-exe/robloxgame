-- Builds the local, placeholder arena: a hex cell per field cell and a slot per bench position.
-- Cells are in view coordinates: the local player's half is always rows 1..BoardConfig.rows,
-- nearest the camera. Each cell part carries Column and Row attributes; each bench part a Slot
-- attribute, so clicks can be mapped back to board positions.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BoardConfig = require(Shared:WaitForChild("BoardConfig"))
local HexGrid = require(Shared:WaitForChild("HexGrid"))
local RenderConfig = require(Shared:WaitForChild("RenderConfig"))

local Arena = {}

local FIELD_ROWS = BoardConfig.rows * 2
local CELL_WIDTH = math.sqrt(3) * RenderConfig.hexRadius -- distance between cell centers in a row
local ROW_SPACING = 1.5 * RenderConfig.hexRadius
local SURFACE_Y = RenderConfig.arenaCenter.Y + RenderConfig.cellThickness

-- Folder holding every arena part. Unit views are parented here too, so clicks can hit them.
Arena.folder = nil :: Folder?

local raycastParams = RaycastParams.new()
raycastParams.FilterType = Enum.RaycastFilterType.Include

-- Top-center of a field cell in view coordinates.
function Arena.cellPosition(column: number, row: number): Vector3
	local shift = if HexGrid.isShiftedRow(row) then 0.5 else 0
	local x = (column - 1 + shift - (BoardConfig.columns - 0.5) / 2) * CELL_WIDTH
	local z = ((FIELD_ROWS + 1) / 2 - row) * ROW_SPACING
	return Vector3.new(RenderConfig.arenaCenter.X + x, SURFACE_Y, RenderConfig.arenaCenter.Z + z)
end

-- Top-center of a bench slot.
function Arena.benchPosition(slot: number): Vector3
	local x = (slot - (BoardConfig.benchSlots + 1) / 2) * CELL_WIDTH
	local z = Arena.cellPosition(1, 1).Z - RenderConfig.arenaCenter.Z + RenderConfig.benchDistance
	return Vector3.new(RenderConfig.arenaCenter.X + x, SURFACE_Y, RenderConfig.arenaCenter.Z + z)
end

-- Returns what is under a screen position (InputObject.Position), limited to arena parts.
function Arena.raycast(screenPosition: Vector2): RaycastResult?
	local camera = workspace.CurrentCamera
	local ray = camera:ScreenPointToRay(screenPosition.X, screenPosition.Y)
	return workspace:Raycast(ray.Origin, ray.Direction * 1000, raycastParams)
end

local function createPart(parent: Instance, size: Vector3, cframe: CFrame, color: Color3): Part
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	part.Material = Enum.Material.SmoothPlastic
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	return part
end

-- A pointy-top hexagon built from three rectangles rotated 60 degrees apart.
local function createHexCell(parent: Instance, column: number, row: number)
	local radius = RenderConfig.hexRadius - RenderConfig.cellGap
	local center = Arena.cellPosition(column, row) - Vector3.new(0, RenderConfig.cellThickness / 2, 0)
	local color = if row <= BoardConfig.rows then RenderConfig.ownCellColor else RenderConfig.enemyCellColor

	local model = Instance.new("Model")
	model.Name = string.format("Cell_%d_%d", column, row)
	for i = 0, 2 do
		local part = createPart(
			model,
			Vector3.new(math.sqrt(3) * radius, RenderConfig.cellThickness, radius),
			CFrame.new(center) * CFrame.Angles(0, math.rad(60 * i), 0),
			color
		)
		part:SetAttribute("Column", column)
		part:SetAttribute("Row", row)
	end
	model.Parent = parent
end

local function createBenchSlot(parent: Instance, slot: number)
	local size = CELL_WIDTH - 2 * RenderConfig.cellGap
	local center = Arena.benchPosition(slot) - Vector3.new(0, RenderConfig.cellThickness / 2, 0)
	local part = createPart(
		parent,
		Vector3.new(size, RenderConfig.cellThickness, size),
		CFrame.new(center),
		RenderConfig.benchSlotColor
	)
	part.Name = "BenchSlot_" .. slot
	part:SetAttribute("Slot", slot)
end

-- Keeps the camera fixed on the arena. Re-applied every frame so the default camera scripts
-- cannot take it back (for example when the character respawns).
local function lockCamera()
	local focus = RenderConfig.arenaCenter
	local cameraCFrame = CFrame.lookAt(focus + RenderConfig.cameraOffset, focus)
	RunService:BindToRenderStep("ArenaCamera", Enum.RenderPriority.Camera.Value + 1, function()
		local camera = workspace.CurrentCamera
		if camera.CameraType ~= Enum.CameraType.Scriptable then
			camera.CameraType = Enum.CameraType.Scriptable
		end
		camera.CFrame = cameraCFrame
	end)
end

function Arena.start()
	local folder = Instance.new("Folder")
	folder.Name = "Arena"
	for row = 1, FIELD_ROWS do
		for column = 1, BoardConfig.columns do
			createHexCell(folder, column, row)
		end
	end
	for slot = 1, BoardConfig.benchSlots do
		createBenchSlot(folder, slot)
	end
	folder.Parent = workspace

	Arena.folder = folder
	raycastParams.FilterDescendantsInstances = { folder }
	lockCamera()
end

return Arena
