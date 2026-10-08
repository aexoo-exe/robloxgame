-- Builds the local arena from a board skin (BoardSkinConfig): a hex tile per field cell, a bench
-- slot per bench position on its own tray, the platform under them, the floor and backdrop around
-- them, and this client's lighting and sky. Also shows placement feedback (Arena.setHighlight,
-- Arena.setDropZones).
-- Cells are in view coordinates: the local player's half is always rows 1..BoardConfig.rows,
-- nearest the camera. Each tile top carries Column and Row attributes and each bench slot a Slot
-- attribute, so clicks can be mapped back to board positions; no other arena part can be clicked.
-- The layout (RenderConfig: hex size, gaps, bench distance) does not depend on the skin.

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BoardConfig = require(Shared:WaitForChild("BoardConfig"))
local BoardSkinConfig = require(Shared:WaitForChild("BoardSkinConfig"))
local HexGrid = require(Shared:WaitForChild("HexGrid"))
local RenderConfig = require(Shared:WaitForChild("RenderConfig"))

local Arena = {}

-- A place on the field or bench, in view coordinates: { column, row } or { slot }.
export type Target = { column: number?, row: number?, slot: number? }

local FIELD_ROWS = BoardConfig.rows * 2
local CELL_WIDTH = math.sqrt(3) * RenderConfig.hexRadius -- distance between cell centers in a row
local ROW_SPACING = 1.5 * RenderConfig.hexRadius
local BASE_Y = RenderConfig.arenaCenter.Y
local SURFACE_Y = BASE_Y + RenderConfig.cellThickness
local FLAT = CFrame.Angles(0, 0, math.pi / 2) -- stands a cylinder's axis (X) upright

-- Folder holding every arena part. Unit views are parented here too, so clicks can hit them.
Arena.folder = nil :: Folder?

local raycastParams = RaycastParams.new()
raycastParams.FilterType = Enum.RaycastFilterType.Include

-- Clickable tile tops and bench slots by key, with the colors placement feedback paints over.
type Tile = { parts: { BasePart }, color: Color3, material: Enum.Material, dropZone: boolean, bench: boolean }
local tiles: { [string]: Tile } = {}
local highlightKey: string? = nil
local highlightValid = false
local dropZonesShown = false
local dropZonesBenchOnly = false
local localSkin = BoardSkinConfig.default

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

-- The point on the tile surface's height under a screen position, or nil if the view ray never
-- reaches it.
function Arena.groundPoint(screenPosition: Vector2): Vector3?
	local camera = workspace.CurrentCamera
	local ray = camera:ScreenPointToRay(screenPosition.X, screenPosition.Y)
	if math.abs(ray.Direction.Y) < 1e-4 then
		return nil
	end
	local distance = (SURFACE_Y - ray.Origin.Y) / ray.Direction.Y
	return if distance > 0 then ray.Origin + ray.Direction * distance else nil
end

local function material(name: string): Enum.Material
	return (Enum.Material :: any)[name]
end

local function createPart(parent: Instance, size: Vector3, cframe: CFrame, color: Color3, materialName: string?): Part
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false -- only tile tops and bench slots take clicks
	part.CanTouch = false
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	part.Material = material(materialName or "SmoothPlastic")
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	return part
end

-- A slab from height `bottom` to `top` covering a box in X/Z centered on `center`.
local function slab(
	parent: Instance,
	center: Vector3,
	sizeX: number,
	sizeZ: number,
	bottom: number,
	top: number,
	color: Color3,
	materialName: string?
): Part
	return createPart(
		parent,
		Vector3.new(sizeX, top - bottom, sizeZ),
		CFrame.new(center.X, (bottom + top) / 2, center.Z),
		color,
		materialName
	)
end

-- A pointy-top hexagon from height `bottom` to `top`, built from three rectangles rotated 60
-- degrees apart.
local function hexagon(
	parent: Instance,
	center: Vector3,
	radius: number,
	bottom: number,
	top: number,
	color: Color3,
	materialName: string
): { Part }
	local parts = {}
	for i = 0, 2 do
		table.insert(
			parts,
			createPart(
				parent,
				Vector3.new(math.sqrt(3) * radius, top - bottom, radius),
				CFrame.new(center.X, (bottom + top) / 2, center.Z) * CFrame.Angles(0, math.rad(60 * i), 0),
				color,
				materialName
			)
		)
	end
	return parts
end

local function registerTile(key: string, parts: { BasePart }, dropZone: boolean, bench: boolean)
	tiles[key] = {
		parts = parts,
		color = parts[1].Color,
		material = parts[1].Material,
		dropZone = dropZone,
		bench = bench,
	}
end

local function tileKey(target: Target): string
	return if target.slot then "s" .. target.slot else "c" .. target.column .. "," .. target.row
end

-- One field cell from `skin`. `own` picks the local player's colors.
local function createHexCell(parent: Instance, column: number, row: number, skin, own: boolean)
	local style = skin.tiles
	local colors = if own then style.own else style.enemy
	local platformTop = BASE_Y + skin.platform.height
	local center = Arena.cellPosition(column, row)

	local model = Instance.new("Model")
	model.Name = string.format("Cell_%d_%d", column, row)
	if style.style == "beveled" then
		-- The rim fills the whole cell, so neighboring rims meet without overlapping.
		hexagon(
			model,
			center,
			RenderConfig.hexRadius,
			platformTop,
			platformTop + style.rimHeight,
			colors.rim,
			style.material
		)
	end
	local top = hexagon(
		model,
		center,
		RenderConfig.hexRadius - RenderConfig.cellGap,
		math.min(platformTop, SURFACE_Y - RenderConfig.cellThickness),
		SURFACE_Y,
		colors.top,
		style.material
	)
	for _, part in top do
		part.CanQuery = true
		part:SetAttribute("Column", column)
		part:SetAttribute("Row", row)
	end
	registerTile(tileKey({ column = column, row = row }), top, own, false)
	model.Parent = parent
end

-- The bench: a tray with a raised lip, and a square slot with a rim per bench position.
local function createBench(parent: Instance, skin)
	local bench = skin.bench
	local platformTop = BASE_Y + skin.platform.height
	local slotSize = CELL_WIDTH - 2 * RenderConfig.cellGap
	local first, last = Arena.benchPosition(1), Arena.benchPosition(BoardConfig.benchSlots)
	local center = (first + last) / 2
	local trayX = last.X - first.X + slotSize + 1.2
	local trayZ = slotSize + 1.2
	local trayTop = platformTop + 0.05

	local folder = Instance.new("Folder")
	folder.Name = "Bench"
	slab(folder, center, trayX, trayZ, platformTop - 0.1, trayTop, bench.tray, bench.material)
	-- The lip runs around the tray, so the bench reads as separate from the field.
	local lipTop = platformTop + bench.lipHeight
	local lip = 0.3
	for _, side in { -1, 1 } do
		local z = center + Vector3.new(0, 0, side * (trayZ - lip) / 2)
		slab(folder, z, trayX, lip, trayTop, lipTop, bench.lip, bench.material)
		local x = center + Vector3.new(side * (trayX - lip) / 2, 0, 0)
		slab(folder, x, lip, trayZ, trayTop, lipTop, bench.lip, bench.material)
	end

	for slot = 1, BoardConfig.benchSlots do
		local position = Arena.benchPosition(slot)
		slab(folder, position, slotSize + 0.3, slotSize + 0.3, trayTop, trayTop + 0.08, bench.slotRim)
		local part = slab(folder, position, slotSize, slotSize, trayTop, SURFACE_Y, bench.slot)
		part.Name = "BenchSlot_" .. slot
		part.CanQuery = true
		part:SetAttribute("Slot", slot)
		registerTile(tileKey({ slot = slot }), { part }, true, true)
	end
	folder.Parent = parent
end

-- The platform under field and bench with a trim around it, the strip between the halves, and
-- the floor that covers the baseplate.
local function createGround(parent: Instance, skin)
	local platform = skin.platform
	local platformTop = BASE_Y + platform.height
	local halfX = math.max(
		(BoardConfig.columns / 2 + 0.25) * CELL_WIDTH,
		Arena.benchPosition(BoardConfig.benchSlots).X - RenderConfig.arenaCenter.X + CELL_WIDTH / 2
	) + platform.margin
	local front = Arena.benchPosition(1).Z + CELL_WIDTH / 2 + 0.6 + platform.margin
	local back = Arena.cellPosition(1, FIELD_ROWS).Z - RenderConfig.hexRadius - platform.margin
	local center = Vector3.new(RenderConfig.arenaCenter.X, 0, (front + back) / 2)
	local depth = front - back

	local folder = Instance.new("Folder")
	folder.Name = "Ground"
	slab(folder, center, halfX * 2, depth, platformTop - 1, platformTop, platform.color, platform.material)
	local trimTop = platformTop + platform.trimHeight
	local w = platform.trimWidth
	for _, side in { -1, 1 } do
		local alongX = center + Vector3.new(0, 0, side * (depth + w) / 2)
		slab(folder, alongX, halfX * 2 + 2 * w, w, platformTop - 1, trimTop, platform.trim, platform.material)
		local alongZ = center + Vector3.new(side * (halfX + w / 2), 0, 0)
		slab(folder, alongZ, w, depth, platformTop - 1, trimTop, platform.trim, platform.material)
	end

	local divider = skin.divider
	local rimTop = platformTop + (if skin.tiles.style == "beveled" then skin.tiles.rimHeight else 0)
	local between = (Arena.cellPosition(1, BoardConfig.rows).Z + Arena.cellPosition(1, BoardConfig.rows + 1).Z) / 2
	slab(
		folder,
		Vector3.new(RenderConfig.arenaCenter.X, 0, between),
		(BoardConfig.columns + 0.5) * CELL_WIDTH,
		divider.width,
		rimTop,
		rimTop + 0.02,
		divider.color,
		divider.material
	)

	local floor = skin.floor
	slab(
		folder,
		RenderConfig.arenaCenter,
		floor.size,
		floor.size,
		BASE_Y + floor.height - 1,
		BASE_Y + floor.height,
		floor.color,
		floor.material
	)
	folder.Parent = parent
end

-- A ring of walls with pillars behind the field, open toward the camera (+Z).
local function createBackdrop(parent: Instance, skin)
	local backdrop = skin.backdrop
	local floorTop = BASE_Y + skin.floor.height
	local center = RenderConfig.arenaCenter
	local arc = math.rad(backdrop.arc)
	local step = arc / backdrop.segments
	local function pointAt(angle: number): Vector3
		-- Angle 0 is straight behind the field (-Z).
		return Vector3.new(
			center.X + backdrop.radius * math.sin(angle),
			floorTop,
			center.Z - backdrop.radius * math.cos(angle)
		)
	end
	local function facingCenter(position: Vector3, height: number): CFrame
		local at = position + Vector3.new(0, height / 2, 0)
		return CFrame.lookAt(at, Vector3.new(center.X, at.Y, center.Z))
	end

	local folder = Instance.new("Folder")
	folder.Name = "Backdrop"
	local wallLength = 2 * backdrop.radius * math.sin(step / 2) + 0.5
	for i = 1, backdrop.segments do
		local position = pointAt(-arc / 2 + (i - 0.5) * step)
		createPart(
			folder,
			Vector3.new(wallLength, backdrop.wallHeight, backdrop.wallThickness),
			facingCenter(position, backdrop.wallHeight),
			backdrop.wall,
			backdrop.material
		)
	end
	for i = 0, backdrop.segments do
		local position = pointAt(-arc / 2 + i * step)
		local size = backdrop.pillarSize
		createPart(
			folder,
			Vector3.new(size, backdrop.pillarHeight, size),
			facingCenter(position, backdrop.pillarHeight),
			backdrop.pillar,
			backdrop.material
		)
		local cap = createPart(
			folder,
			Vector3.new(0.5, size * 0.9, size * 0.9),
			CFrame.new(position + Vector3.new(0, backdrop.pillarHeight + 0.25, 0)) * FLAT,
			backdrop.cap,
			"Neon"
		)
		cap.Shape = Enum.PartType.Cylinder
		cap.CastShadow = false
	end
	folder.Parent = parent
end

-- Lighting, atmosphere, sky and color correction, on this client only. Replaces any sky,
-- atmosphere or color correction already in Lighting.
local function applyLighting(skin)
	for property, value in skin.lighting do
		(Lighting :: any)[property] = value
	end
	for _, child in Lighting:GetChildren() do
		if child:IsA("Sky") or child:IsA("Atmosphere") or child:IsA("ColorCorrectionEffect") then
			child:Destroy()
		end
	end
	local function add(className: string, properties)
		local instance = Instance.new(className)
		for property, value in properties do
			(instance :: any)[property] = value
		end
		instance.Parent = Lighting
	end
	add("Atmosphere", skin.atmosphere)
	add("Sky", skin.sky)
	add("ColorCorrectionEffect", skin.colorCorrection)
end

-- Repaints one tile from the feedback state: the highlight wins, then the drop-zone tint.
local function paint(key: string)
	local tile = tiles[key]
	if not tile then
		return
	end
	local highlight = localSkin.highlight
	local color, materialValue = tile.color, tile.material
	if key == highlightKey then
		color = if highlightValid then highlight.valid else highlight.invalid
		materialValue = material(highlight.material)
	elseif dropZonesShown and tile.dropZone and (tile.bench or not dropZonesBenchOnly) then
		color = tile.color:Lerp(highlight.dropZone, highlight.dropZoneBlend)
	end
	for _, part in tile.parts do
		part.Color = color
		part.Material = materialValue
	end
end

-- Highlights one tile or bench slot as a valid or invalid place to put a unit; nil clears it.
function Arena.setHighlight(target: Target?, valid: boolean?)
	local key = if target then tileKey(target) else nil
	if key == highlightKey and (valid or false) == highlightValid then
		return
	end
	local previous = highlightKey
	highlightKey, highlightValid = key, valid or false
	if previous then
		paint(previous)
	end
	if key then
		paint(key)
	end
end

-- Tints every place a unit may be put while dragging: the local player's half and the bench, or
-- only the bench with `benchOnly` (while the board is locked during combat).
function Arena.setDropZones(shown: boolean, benchOnly: boolean?)
	local only = shown and benchOnly == true
	if shown == dropZonesShown and only == dropZonesBenchOnly then
		return
	end
	dropZonesShown = shown
	dropZonesBenchOnly = only
	for key, tile in tiles do
		if tile.dropZone then
			paint(key)
		end
	end
end

-- Camera framing. The camera looks along RenderConfig.cameraOffset; its distance and sideways
-- shift are fitted so the field and bench (with standing units) fill the part of the screen the
-- HUD leaves free (Arena.setViewInsets), on any screen shape.
local focus = RenderConfig.arenaCenter
local cameraCFrame = CFrame.lookAt(focus + RenderConfig.cameraOffset, focus)
local viewInsets = { top = 0, bottom = 0, left = 0, right = 0 } -- pixels from each screen edge

-- Points that must stay in view: the corners of the field and the bench ends, at the tile surface
-- and at a standing unit's head height.
local function framePoints(): { Vector3 }
	local corners = {
		Arena.cellPosition(1, 1),
		Arena.cellPosition(BoardConfig.columns, 1),
		Arena.cellPosition(1, FIELD_ROWS),
		Arena.cellPosition(BoardConfig.columns, FIELD_ROWS),
		Arena.benchPosition(1),
		Arena.benchPosition(BoardConfig.benchSlots),
	}
	local reach = RenderConfig.hexRadius
	local head = Vector3.new(0, RenderConfig.unitSize.Y + 1, 0)
	local points = {}
	for _, corner in corners do
		for _, offset in { Vector3.new(-reach, 0, -reach), Vector3.new(reach, 0, reach) } do
			table.insert(points, corner + offset)
			table.insert(points, corner + offset + head)
		end
	end
	return points
end

local function fitCamera()
	local camera = workspace.CurrentCamera
	local viewport = camera.ViewportSize
	if viewport.X <= 0 or viewport.Y <= 0 then
		return
	end
	local tanY = math.tan(math.rad(camera.FieldOfView) / 2)
	local tanX = tanY * viewport.X / viewport.Y
	-- The free area in normalized screen coordinates (-1 to 1, up is positive).
	local left = -1 + 2 * viewInsets.left / viewport.X
	local right = 1 - 2 * viewInsets.right / viewport.X
	local top = 1 - 2 * viewInsets.top / viewport.Y
	local bottom = -1 + 2 * viewInsets.bottom / viewport.Y
	if right - left < 0.2 or top - bottom < 0.2 then
		return
	end

	local points = framePoints()
	local direction = RenderConfig.cameraOffset.Unit
	local distance = RenderConfig.cameraOffset.Magnitude
	local shiftX, shiftY = 0, 0
	local fitted = cameraCFrame
	-- Projection is close to linear in 1 / distance, so a few rounds of zooming and re-centering
	-- settle the framing.
	for _ = 1, 8 do
		local look = CFrame.lookAt(focus + direction * distance, focus)
		fitted = look + look.RightVector * shiftX + look.UpVector * shiftY
		local minX, maxX, minY, maxY = math.huge, -math.huge, math.huge, -math.huge
		for _, point in points do
			local relative = fitted:PointToObjectSpace(point)
			local depth = math.max(-relative.Z, 0.1)
			local x, y = relative.X / (depth * tanX), relative.Y / (depth * tanY)
			minX, maxX = math.min(minX, x), math.max(maxX, x)
			minY, maxY = math.min(minY, y), math.max(maxY, y)
		end
		local zoom = math.max((maxX - minX) / (right - left), (maxY - minY) / (top - bottom))
		shiftX += ((minX + maxX) / 2 - (left + right) / 2) * distance * tanX
		shiftY += ((minY + maxY) / 2 - (top + bottom) / 2) * distance * tanY
		distance = math.clamp(distance * zoom, 20, 250)
	end
	cameraCFrame = fitted
end

-- Tells the arena how much of each screen edge (pixels) the HUD covers, and refits the camera.
function Arena.setViewInsets(insets: { top: number, bottom: number, left: number, right: number })
	viewInsets = insets
	fitCamera()
end

-- Keeps the camera on the arena. Re-applied every frame so the default camera scripts cannot take
-- it back (for example when the character respawns).
local function lockCamera()
	local camera = workspace.CurrentCamera
	camera:GetPropertyChangedSignal("ViewportSize"):Connect(fitCamera)
	fitCamera()
	RunService:BindToRenderStep("ArenaCamera", Enum.RenderPriority.Camera.Value + 1, function()
		local current = workspace.CurrentCamera
		if current.CameraType ~= Enum.CameraType.Scriptable then
			current.CameraType = Enum.CameraType.Scriptable
		end
		current.CFrame = cameraCFrame
	end)
end

function Arena.start()
	-- Each half is built from its own skin, so a player's half could later use their own skin. For
	-- now both halves and the surroundings use the default skin.
	local ownSkin = BoardSkinConfig.default
	local enemySkin = BoardSkinConfig.default
	localSkin = ownSkin

	local folder = Instance.new("Folder")
	folder.Name = "Arena"
	for row = 1, FIELD_ROWS do
		local own = row <= BoardConfig.rows
		for column = 1, BoardConfig.columns do
			createHexCell(folder, column, row, if own then ownSkin else enemySkin, own)
		end
	end
	createBench(folder, ownSkin)
	createGround(folder, ownSkin)
	createBackdrop(folder, ownSkin)
	applyLighting(ownSkin)
	folder.Parent = workspace

	Arena.folder = folder
	raycastParams.FilterDescendantsInstances = { folder }
	lockCamera()
end

return Arena
