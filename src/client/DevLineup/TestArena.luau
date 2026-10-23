-- Key 3's test arenas (T) and their fixed cameras (C), and the field preview's framing. Studio only
-- (see DevLineup).

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BoardConfig = require(Shared:WaitForChild("BoardConfig"))
local RenderConfig = require(Shared:WaitForChild("RenderConfig"))

local Config = require(script.Parent.Config)
local State = require(script.Parent.State)

local Arena = require(script.Parent.Parent.Arena)
local CharacterLook = require(script.Parent.Parent.CharacterLook)

local TestArena = {}

local FIELD_ORIGIN, FIELD_UNIT = Config.FIELD_ORIGIN, Config.FIELD_UNIT
local GRAY_CENTER, GRAY_SIZE, GRAY_HEIGHT = Config.GRAY_CENTER, Config.GRAY_SIZE, Config.GRAY_HEIGHT
local GRAY_FLOOR, GRAY_BACKDROP = Config.GRAY_FLOOR, Config.GRAY_BACKDROP
local HEIGHT = Config.HEIGHT

-- Undoes what the shown arena changed outside the stage (lighting, the real board's parent).
function TestArena.leave()
	local restore = State.arenaRestore
	State.arenaRestore = nil
	if restore then
		restore()
	end
end

local function slab(parent: Instance, size: Vector3, at: Vector3, color: Color3)
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false -- the backdrop never shades the stage
	part.Size = size
	part.CFrame = CFrame.new(at)
	part.Color = color
	part.Material = Enum.Material.SmoothPlastic
	part.Reflectance = 0
	part.Parent = parent
end

-- Neutral lighting for the gray arena: GRAY_LIGHTING, without atmosphere or color grading (bloom
-- stays, as effects are drawn for it). Returns what puts the hub's lighting back.
local function neutralLighting(): () -> ()
	local saved: { [string]: any } = {}
	for name, value in Config.GRAY_LIGHTING do
		saved[name] = (Lighting :: any)[name];
		(Lighting :: any)[name] = value
	end
	local removed, disabled = {}, {}
	for _, child in Lighting:GetChildren() do
		if child:IsA("Atmosphere") then
			table.insert(removed, child)
			child.Parent = nil
		elseif child:IsA("PostEffect") and not child:IsA("BloomEffect") and child.Enabled then
			table.insert(disabled, child)
			child.Enabled = false
		end
	end
	return function()
		for name, value in saved do
			(Lighting :: any)[name] = value
		end
		for _, child in removed do
			child.Parent = Lighting
		end
		for _, effect in disabled do
			effect.Enabled = true
		end
	end
end

-- Builds the field preview's ground for `arenaMode` in `parent` and returns the offset from the real
-- arena cells to the field's (CombatPlayback.preview).
--   off     a small floor above the lineup (FIELD_ORIGIN)
--   gray    a mid-gray matte floor in a closed box of plain backdrop, far above the hub, in
--           neutral lighting (no hub props in sight)
--   bright  the real arena board, in place, in the hub's own lighting
function TestArena.build(parent: Instance): Vector3
	if State.arenaMode == "bright" then
		local board = Arena.folder
		if board and board.Parent == nil then -- hidden outside a match
			board.Parent = workspace
			State.arenaRestore = function()
				board.Parent = nil
			end
		end
		return Vector3.zero
	elseif State.arenaMode == "gray" then
		local offset = GRAY_CENTER - RenderConfig.arenaCenter
		local floorTop = Arena.cellPosition(1, 1).Y + offset.Y
		local x, z, half = GRAY_CENTER.X, GRAY_CENTER.Z, GRAY_SIZE / 2
		slab(parent, Vector3.new(GRAY_SIZE, 1, GRAY_SIZE), Vector3.new(x, floorTop - 0.5, z), GRAY_FLOOR)
		local wallY = floorTop + GRAY_HEIGHT / 2
		slab(parent, Vector3.new(GRAY_SIZE, GRAY_HEIGHT, 1), Vector3.new(x, wallY, z - half), GRAY_BACKDROP)
		slab(parent, Vector3.new(GRAY_SIZE, GRAY_HEIGHT, 1), Vector3.new(x, wallY, z + half), GRAY_BACKDROP)
		slab(parent, Vector3.new(1, GRAY_HEIGHT, GRAY_SIZE), Vector3.new(x - half, wallY, z), GRAY_BACKDROP)
		slab(parent, Vector3.new(1, GRAY_HEIGHT, GRAY_SIZE), Vector3.new(x + half, wallY, z), GRAY_BACKDROP)
		slab(parent, Vector3.new(GRAY_SIZE, 1, GRAY_SIZE), Vector3.new(x, floorTop + GRAY_HEIGHT, z), GRAY_BACKDROP)
		State.arenaRestore = neutralLighting()
		return offset
	end
	local offset = FIELD_ORIGIN - Arena.cellPosition(FIELD_UNIT[1], FIELD_UNIT[2])
	local floor = Instance.new("Part")
	floor.Anchored = true
	floor.CanCollide = false
	floor.CanQuery = false
	floor.Size = Vector3.new(44, 1, 44)
	floor.CFrame = CFrame.new(Arena.cellPosition(4, BoardConfig.rows + 1) + offset - Vector3.new(0, 0.5, 0))
	floor.Color = Color3.fromRGB(64, 68, 76)
	floor.Material = Enum.Material.SmoothPlastic
	floor.Parent = parent
	return offset
end

-- The arena's fixed cameras (arenaCamera), from the field's cells only, so every cast of every unit
-- is framed the same:
--   gameplay  the match camera's angle and distance (Arena.boardCamera)
--   close     a 3/4 view from behind the caster's side, the caster and the dummy in front of it
--             together filling CLOSE_FILL of the frame height (sized to the caster's height)
--   wide      high and to the side over the whole field: the full area of an ultimate
--   slice     (K and S on the slice unit set it, not C) an orbit the user aims (sliceView): locked
--             on the focus, the midpoint of the caster and the target in front of it at chest
--             height (raised or lowered by `height`), from `distance` studs at `yaw` degrees
--             around it (0: square from the side, perpendicular to the caster -> target line, on
--             the -X side the other arena cameras use) and `pitch` degrees above level
function TestArena.framing(s: State.Stage, offset: Vector3): CFrame
	local arenaCamera = State.arenaCamera
	if arenaCamera == "gameplay" then
		return Arena.boardCamera() + offset
	end
	local caster = Arena.cellPosition(FIELD_UNIT[1], FIELD_UNIT[2]) + offset
	if arenaCamera == "slice" then
		local sliceView = State.sliceView
		local target = Arena.cellPosition(FIELD_UNIT[1], BoardConfig.rows + 1) + offset
		local height = HEIGHT * CharacterLook.of(s.unitType).scale * RenderConfig.starSizeScale[s.starLevel]
		local focusPoint = caster:Lerp(target, 0.5) + Vector3.new(0, height * 0.6 + sliceView.height, 0)
		local along = Vector3.new(target.X - caster.X, 0, target.Z - caster.Z)
		along = if along.Magnitude > 1e-3 then along.Unit else Vector3.zAxis
		local side = along:Cross(Vector3.yAxis)
		side = if side.X > 0 then -side.Unit else side.Unit
		local around = CFrame.fromAxisAngle(Vector3.yAxis, math.rad(sliceView.yaw)) * side
		local pitch = math.rad(sliceView.pitch)
		local direction = around * math.cos(pitch) + Vector3.yAxis * math.sin(pitch)
		return CFrame.lookAt(focusPoint + direction * sliceView.distance, focusPoint)
	end
	if arenaCamera == "close" then
		local target = Arena.cellPosition(FIELD_UNIT[1], BoardConfig.rows + 1) + offset
		local height = HEIGHT * CharacterLook.of(s.unitType).scale * RenderConfig.starSizeScale[s.starLevel]
		local between = caster:Lerp(target, 0.5) + Vector3.new(0, height * 0.5, 0)
		-- What must fill the frame: the caster's height, plus the rise of the target behind it.
		local shown = height + 1.5
		local fov = math.rad(workspace.CurrentCamera.FieldOfView)
		local distance = math.max(shown / (Config.CLOSE_FILL * 2 * math.tan(fov / 2)), 8)
		return CFrame.lookAt(between + Vector3.new(-13, 10, 17).Unit * distance, between)
	end
	local center = RenderConfig.arenaCenter + offset
	center = Vector3.new(center.X, caster.Y, center.Z)
	return CFrame.lookAt(center + Vector3.new(-30, 44, 46), center)
end

-- The field preview's camera: from behind the unit's side, closer than the board camera (camera
-- mode "board": at the board camera's own angle and distance).
function TestArena.fieldFraming(focusPoint: Vector3): CFrame
	if State.cameraMode == "board" then
		return CFrame.lookAt(focusPoint + RenderConfig.cameraOffset, focusPoint)
	elseif State.cameraMode == "close" then
		-- Close on the unit, looking past it toward the dummies (an ultimate close-up).
		local unitAt = FIELD_ORIGIN + Vector3.new(0, 2, 0)
		return CFrame.lookAt(unitAt + Vector3.new(-7, 4, 9), unitAt:Lerp(focusPoint, 0.4))
	end
	return CFrame.lookAt(focusPoint + Vector3.new(0, 11, 15), focusPoint)
end

return TestArena
