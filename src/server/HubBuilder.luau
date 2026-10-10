-- Builds the hub from parts (layout, colors and sizes in HubConfig): a floating sky island with a
-- stone plaza, a stone rim, an invisible barrier and ceiling, a spawn marker under a torii gate,
-- lanterns, origin banners, cherry trees, a sword-in-the-stone centerpiece, and the two pads. Each
-- pad is raised and glowing with a light column over it, and has one display board beside it
-- (title, live status line, one line of instructions) facing the spawn. No other text floats in
-- the hub, so nothing overlaps. About 150 parts. Server only; HubService runs the pads.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local HubConfig = require(ReplicatedStorage.Shared.HubConfig)
local TraitIconConfig = require(ReplicatedStorage.Shared.TraitIconConfig)

local HubBuilder = {}

-- A built pad: where to stand (HubService.isOnPad) and the status line to update.
export type Pad = { center: Vector3, radius: number, top: number, status: TextLabel }

local COLORS = HubConfig.colors
local CENTER = HubConfig.center
local FLOOR = CENTER.Y + 1 -- the plaza's walking height
local UPRIGHT = CFrame.Angles(0, 0, math.pi / 2) -- stands a cylinder's axis (X) upright

local function at(offset: Vector3, height: number?): Vector3
	return Vector3.new(CENTER.X + offset.X, FLOOR + (height or 0), CENTER.Z + offset.Z)
end

-- A point on a circle around the center: angle 0 toward -Z, increasing toward +X.
local function around(angle: number, radius: number): Vector3
	local a = math.rad(angle)
	return Vector3.new(radius * math.sin(a), 0, -radius * math.cos(a))
end

local function part(
	parent: Instance,
	size: Vector3,
	cframe: CFrame,
	color: Color3,
	material: Enum.Material?,
	shape: Enum.PartType?
): Part
	local instance = Instance.new("Part")
	instance.Anchored = true
	instance.Size = size
	instance.CFrame = cframe
	instance.Color = color
	instance.Material = material or Enum.Material.SmoothPlastic
	instance.TopSurface = Enum.SurfaceType.Smooth
	instance.BottomSurface = Enum.SurfaceType.Smooth
	if shape then
		instance.Shape = shape
	end
	instance.Parent = parent
	return instance
end

-- A flat upright disc (a cylinder) whose top is `top` studs above the floor.
local function disc(parent: Instance, offset: Vector3, diameter: number, thickness: number, top: number, color: Color3, material: Enum.Material?): Part
	return part(
		parent,
		Vector3.new(thickness, diameter, diameter),
		CFrame.new(at(offset, top - thickness / 2)) * UPRIGHT,
		color,
		material,
		Enum.PartType.Cylinder
	)
end

-- A part that only lights or decorates: no collisions, no clicks, no touches.
local function ghost(instance: BasePart): BasePart
	instance.CanCollide = false
	instance.CanQuery = false
	instance.CanTouch = false
	instance.CastShadow = false
	return instance
end

local function light(parent: Instance, color: Color3, range: number, brightness: number)
	local pointLight = Instance.new("PointLight")
	pointLight.Color = color
	pointLight.Range = range
	pointLight.Brightness = brightness
	pointLight.Shadows = false
	pointLight.Parent = parent
end

local function label(parent: Instance, text: string, top: number, height: number, color: Color3, font: Enum.Font): TextLabel
	local textLabel = Instance.new("TextLabel")
	textLabel.BackgroundTransparency = 1
	textLabel.Position = UDim2.fromScale(0.05, top)
	textLabel.Size = UDim2.fromScale(0.9, height)
	textLabel.Text = text
	textLabel.TextColor3 = color
	textLabel.TextStrokeTransparency = 0.4
	textLabel.TextScaled = true
	textLabel.TextWrapped = true
	textLabel.Font = font
	textLabel.Parent = parent
	return textLabel
end

-- The island: a grass disc with rock tapering away underneath, the stone plaza on top, a ring
-- pattern, and the gold inlay around the centerpiece.
local function island(folder: Instance)
	local radius = HubConfig.islandRadius
	disc(folder, Vector3.zero, radius * 2, 3, 0, COLORS.grass, Enum.Material.Grass)
	local rocks = {
		{ 0.95, 6, COLORS.rock },
		{ 0.78, 7, COLORS.rockDark },
		{ 0.55, 8, COLORS.rock },
		{ 0.3, 8, COLORS.rockDark },
		{ 0.1, 6, COLORS.rock },
	}
	local bottom = -3
	for _, rock in rocks do
		disc(folder, Vector3.zero, radius * 2 * rock[1], rock[2], bottom, rock[3], Enum.Material.Rock)
		bottom -= rock[2]
	end
	local plaza = HubConfig.plazaRadius
	disc(folder, Vector3.zero, plaza * 2, 0.5, 0.04, COLORS.plaza, Enum.Material.Slate)
	disc(folder, Vector3.zero, (plaza - 5) * 2, 0.4, 0.06, COLORS.rim, Enum.Material.Slate)
	disc(folder, Vector3.zero, (plaza - 6.5) * 2, 0.4, 0.07, COLORS.plaza, Enum.Material.Slate)
	local inlay = HubConfig.centerpieceOffset
	disc(folder, inlay, 16, 0.3, 0.1, COLORS.inlay, Enum.Material.Marble)
	disc(folder, inlay, 14.6, 0.3, 0.12, COLORS.inlayInner, Enum.Material.Slate)
end

-- A stone curb around the plaza, and the invisible barrier and ceiling that keep players in.
local function boundary(folder: Instance)
	local rimRadius = HubConfig.rimRadius
	local segments = 16
	local length = 2 * rimRadius * math.sin(math.pi / segments) + 0.6
	for i = 1, segments do
		local angle = (i - 0.5) * 360 / segments
		local position = at(around(angle, rimRadius), 0.7)
		part(
			folder,
			Vector3.new(length, 1.4, 1.2),
			CFrame.lookAt(position, position + around(angle, 1)),
			COLORS.rim,
			Enum.Material.Slate
		)
	end

	local barrier = Instance.new("Folder")
	barrier.Name = "Barrier"
	local wallRadius = HubConfig.barrierRadius + 1
	local walls = 24
	local wallLength = 2 * wallRadius * math.sin(math.pi / walls) + 1
	local height = HubConfig.barrierHeight + 6
	for i = 1, walls do
		local angle = (i - 0.5) * 360 / walls
		local position = at(around(angle, wallRadius), height / 2 - 6)
		local wall = part(
			barrier,
			Vector3.new(wallLength, height, 2),
			CFrame.lookAt(position, position + around(angle, 1)),
			COLORS.rim
		)
		wall.Transparency = 1
		wall.CastShadow = false
		wall.CanTouch = false
	end
	local ceiling = disc(
		barrier,
		Vector3.zero,
		(wallRadius + 2) * 2,
		1,
		HubConfig.barrierHeight + 1,
		COLORS.rim
	)
	ceiling.Transparency = 1
	ceiling.CastShadow = false
	ceiling.CanTouch = false
	barrier.Parent = folder
end

-- The spawn: an invisible SpawnLocation over a round marker (a glowing ring, a white stone and a
-- gold crest with four points).
local function spawnMarker(folder: Instance)
	local offset = HubConfig.spawnOffset
	local spawn = Instance.new("SpawnLocation")
	spawn.Anchored = true
	spawn.Neutral = true
	spawn.Duration = 0 -- no spawn force field
	spawn.Size = Vector3.new(6, 0.2, 6)
	spawn.CFrame = CFrame.new(at(offset, 0.4)) -- faces -Z, toward the pads
	spawn.Transparency = 1
	spawn.CanCollide = false
	spawn.CanTouch = false
	spawn.Parent = folder

	local ring = disc(folder, offset, 10.6, 0.3, 0.14, COLORS.spawnGlow, Enum.Material.Neon)
	light(ring, COLORS.spawnGlow, 12, 1)
	disc(folder, offset, 9.4, 0.3, 0.2, COLORS.spawnStone, Enum.Material.Marble)
	disc(folder, offset, 3.4, 0.2, 0.26, COLORS.guard, Enum.Material.Metal)
	for i = 0, 3 do
		local position = at(offset + around(i * 90, 3.2), 0.24)
		part(folder, Vector3.new(1, 0.12, 1), CFrame.new(position) * CFrame.Angles(0, math.rad(45), 0), COLORS.guard, Enum.Material.Metal)
	end
end

-- A torii gate behind the spawn, with a plaque reading "dojo".
local function torii(folder: Instance)
	local offset = HubConfig.toriiOffset
	for _, side in { -1, 1 } do
		local pillar = offset + Vector3.new(side * 6, 0, 0)
		part(folder, Vector3.new(12.6, 1.3, 1.3), CFrame.new(at(pillar, 6.3)) * UPRIGHT, COLORS.torii, Enum.Material.Wood, Enum.PartType.Cylinder)
		part(folder, Vector3.new(2, 0.8, 2), CFrame.new(at(pillar, 0.4)), COLORS.toriiTop, Enum.Material.Slate)
	end
	part(folder, Vector3.new(18, 0.9, 1.8), CFrame.new(at(offset, 13.1)), COLORS.toriiTop, Enum.Material.Wood)
	part(folder, Vector3.new(16.2, 0.8, 1.4), CFrame.new(at(offset, 12.3)), COLORS.torii, Enum.Material.Wood)
	part(folder, Vector3.new(14.4, 0.7, 0.9), CFrame.new(at(offset, 10)), COLORS.torii, Enum.Material.Wood)
	local plaque = part(folder, Vector3.new(2.2, 1.6, 0.3), CFrame.new(at(offset, 11.15)), COLORS.toriiTop, Enum.Material.Wood)
	for _, face in { Enum.NormalId.Front, Enum.NormalId.Back } do
		local gui = Instance.new("SurfaceGui")
		gui.Face = face
		gui.LightInfluence = 0
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 50
		gui.Parent = plaque
		label(gui, "道場", 0.08, 0.84, COLORS.guard, Enum.Font.GothamBlack)
	end
end

-- Stone lanterns (toro) around the plaza, each with a warm light.
local function lanterns(folder: Instance)
	for _, angle in HubConfig.lanternAngles do
		local offset = around(angle, HubConfig.lanternRadius)
		local facing = CFrame.Angles(0, math.rad(-angle), 0)
		part(folder, Vector3.new(2.4, 0.7, 2.4), CFrame.new(at(offset, 0.35)) * facing, COLORS.lanternStone, Enum.Material.Slate)
		part(folder, Vector3.new(2.8, 1, 1), CFrame.new(at(offset, 2.1)) * UPRIGHT, COLORS.lanternStone, Enum.Material.Slate, Enum.PartType.Cylinder)
		local lamp = part(folder, Vector3.new(1.7, 1.5, 1.7), CFrame.new(at(offset, 4.25)) * facing, COLORS.lanternLight, Enum.Material.Neon)
		light(lamp, COLORS.lanternLight, 16, 1.4)
		part(
			folder,
			Vector3.new(2.9, 0.6, 2.9),
			CFrame.new(at(offset, 5.3)) * facing * CFrame.Angles(0, math.rad(45), 0),
			COLORS.lanternStone,
			Enum.Material.Slate
		)
	end
end

-- A banner per origin trait around the rim: a pole and a cloth in the trait's color with its
-- symbol letters and name, facing the plaza.
local function banners(folder: Instance)
	for _, banner in HubConfig.banners do
		local trait = TraitIconConfig[banner.trait]
		if not trait then
			continue
		end
		local color = Color3.fromRGB(trait.color[1], trait.color[2], trait.color[3])
		local base = around(banner.angle, HubConfig.bannerRadius)
		part(folder, Vector3.new(13, 0.45, 0.45), CFrame.new(at(base, 6.5)) * UPRIGHT, COLORS.toriiTop, Enum.Material.Wood, Enum.PartType.Cylinder)
		local clothCenter = at(base + around(banner.angle, -0.5), 8.6)
		local cloth = part(
			folder,
			Vector3.new(3.2, 6.6, 0.12),
			CFrame.lookAt(clothCenter, Vector3.new(CENTER.X, clothCenter.Y, CENTER.Z)),
			color,
			Enum.Material.Fabric
		)
		ghost(cloth)
		local gui = Instance.new("SurfaceGui")
		gui.Face = Enum.NormalId.Front
		gui.LightInfluence = 0.3
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 30
		gui.Parent = cloth
		local emblem = Instance.new("Frame")
		emblem.AnchorPoint = Vector2.new(0.5, 0)
		emblem.Position = UDim2.fromScale(0.5, 0.12)
		emblem.Size = UDim2.fromScale(0.8, 0.8 * 3.2 / 6.6)
		emblem.BackgroundColor3 = Color3.new(1, 1, 1)
		emblem.BackgroundTransparency = 0.1
		local round = Instance.new("UICorner")
		round.CornerRadius = UDim.new(0.5, 0)
		round.Parent = emblem
		emblem.Parent = gui
		local letters = label(emblem, trait.letters, 0.15, 0.7, color, Enum.Font.GothamBlack)
		letters.TextStrokeTransparency = 1
		label(gui, string.upper(trait.name), 0.62, 0.12, Color3.new(1, 1, 1), Enum.Font.GothamBold)
		-- A gold tassel strip along the bottom.
		local fringe = Instance.new("Frame")
		fringe.Position = UDim2.fromScale(0, 0.94)
		fringe.Size = UDim2.fromScale(1, 0.06)
		fringe.BackgroundColor3 = COLORS.guard
		fringe.BorderSizePixel = 0
		fringe.Parent = gui
	end
end

-- Cherry trees with falling petals.
local function trees(folder: Instance)
	for _, tree in HubConfig.trees do
		local offset = around(tree.angle, tree.radius)
		part(
			folder,
			Vector3.new(7.5, 1.3, 1.3),
			CFrame.new(at(offset, 3.6)) * CFrame.Angles(math.rad(6), 0, 0) * UPRIGHT,
			COLORS.trunk,
			Enum.Material.Wood,
			Enum.PartType.Cylinder
		)
		local canopy = {
			{ Vector3.new(0, 0, 0), 8.5, 8.2 },
			{ Vector3.new(2.6, 0, 1.2), 6, 7.2 },
			{ Vector3.new(-2.4, 0, -1), 5.6, 7.6 },
		}
		for index, ball in canopy do
			local position = at(offset + ball[1], ball[3])
			local leaves = part(folder, Vector3.one * ball[2], CFrame.new(position), COLORS.blossom, Enum.Material.SmoothPlastic, Enum.PartType.Ball)
			leaves.CastShadow = index == 1
			if index == 1 then
				local petals = Instance.new("ParticleEmitter")
				petals.Color = ColorSequence.new(COLORS.blossom)
				petals.Size = NumberSequence.new(0.3)
				petals.Rate = 3
				petals.Lifetime = NumberRange.new(6, 9)
				petals.Speed = NumberRange.new(0.5, 1.5)
				petals.SpreadAngle = Vector2.new(180, 180)
				petals.Acceleration = Vector3.new(0.6, -0.8, 0.3)
				petals.RotSpeed = NumberRange.new(-60, 60)
				petals.Rotation = NumberRange.new(0, 360)
				petals.LightEmission = 0.2
				petals.Parent = leaves
			end
		end
	end
end

-- A giant sword planted in a stone pedestal, ringed with light.
local function centerpiece(folder: Instance)
	local offset = HubConfig.centerpieceOffset
	local glow = disc(folder, offset, 10.8, 0.3, 0.16, COLORS.centerpieceGlow, Enum.Material.Neon)
	ghost(glow)
	disc(folder, offset, 9, 1.4, 1.4, COLORS.rockDark, Enum.Material.Slate)
	disc(folder, offset, 6, 1.2, 2.6, COLORS.lanternStone, Enum.Material.Slate)
	-- The sword, tilted a little, built around the point where it enters the stone.
	local pivot = CFrame.new(at(offset, 2.6)) * CFrame.Angles(math.rad(4), math.rad(30), math.rad(7))
	local blade = part(folder, Vector3.new(0.35, 11, 1.4), pivot * CFrame.new(0, 4.7, 0), COLORS.blade, Enum.Material.Metal)
	light(blade, COLORS.centerpieceGlow, 18, 1.2)
	part(folder, Vector3.new(0.15, 10.4, 0.25), pivot * CFrame.new(0, 4.6, 0.62), COLORS.guard, Enum.Material.Neon)
	part(folder, Vector3.new(0.4, 3.4, 3.4), pivot * CFrame.new(0, 10.4, 0) * UPRIGHT, COLORS.guard, Enum.Material.Metal, Enum.PartType.Cylinder)
	part(folder, Vector3.new(0.85, 3.6, 0.85), pivot * CFrame.new(0, 12.4, 0), COLORS.hilt, Enum.Material.Fabric)
	part(folder, Vector3.new(1, 1, 1), pivot * CFrame.new(0, 14.5, 0), COLORS.guard, Enum.Material.Metal, Enum.PartType.Ball)
end

-- A path of pale stone from the spawn to a pad.
local function path(folder: Instance, to: Vector3)
	local from = at(HubConfig.spawnOffset, 0)
	local goal = at(to, 0)
	local length = (goal - from).Magnitude
	local middle = (from + goal) / 2
	part(
		folder,
		Vector3.new(5, 0.3, length),
		CFrame.lookAt(middle, goal) - Vector3.new(0, 0.05, 0),
		COLORS.path,
		Enum.Material.Pavement
	)
end

-- A raised glowing pad with a light column over it, and its display board.
local function pad(folder: Instance, name: string, config): Pad
	local offset = config.offset
	local size = config.size
	local top = HubConfig.padHeight
	local dark = config.color:Lerp(Color3.new(0, 0, 0), 0.55)
	disc(folder, offset, size + 3, 0.6, 0.6, COLORS.rockDark, Enum.Material.Slate)
	disc(folder, offset, size + 1.4, 0.3, 0.9, config.color, Enum.Material.Neon)
	local surface = disc(folder, offset, size, top - 0.6, top, dark, Enum.Material.Glass)
	surface.Name = name .. "Pad"
	light(surface, config.color, 22, 2.5)
	disc(folder, offset, size - 2.6, 0.1, top + 0.03, config.color, Enum.Material.Neon)
	disc(folder, offset, size - 3.4, 0.1, top + 0.05, dark, Enum.Material.Glass)
	local beam = disc(folder, offset, 4, HubConfig.beamHeight, top + HubConfig.beamHeight, config.color, Enum.Material.Neon)
	beam.Transparency = 0.82
	ghost(beam)

	-- The display: a dark board on two posts with a glowing cap, angled toward the spawn. Title,
	-- status and instructions each own a band of the board, so their text can never overlap.
	local boardSize = HubConfig.displaySize
	local base = at(config.displayOffset, 0)
	local spawn = at(HubConfig.spawnOffset, 0)
	local facing = CFrame.lookAt(base, Vector3.new(spawn.X, base.Y, spawn.Z))
	local lift = 2.6 -- the board's bottom edge above the floor
	local boardCFrame = facing + Vector3.new(0, lift + boardSize.Y / 2, 0)
	local board = part(folder, Vector3.new(boardSize.X, boardSize.Y, 0.8), boardCFrame, COLORS.displayBoard, Enum.Material.SmoothPlastic)
	board.Name = name .. "Display"
	for _, side in { -1, 1 } do
		part(
			folder,
			Vector3.new(0.9, lift + boardSize.Y + 0.4, 0.9),
			facing * CFrame.new(side * (boardSize.X / 2 + 0.45), (lift + boardSize.Y + 0.4) / 2, 0),
			COLORS.displayFrame,
			Enum.Material.Slate
		)
	end
	part(folder, Vector3.new(boardSize.X + 1.8, 0.5, 1.1), facing * CFrame.new(0, lift + boardSize.Y + 0.45, 0), config.color, Enum.Material.Neon)

	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front -- the face toward the spawn
	gui.LightInfluence = 0
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.Parent = board
	local stripe = Instance.new("Frame")
	stripe.Size = UDim2.fromScale(1, 0.05)
	stripe.BackgroundColor3 = config.color
	stripe.BorderSizePixel = 0
	stripe.Parent = gui
	label(gui, config.title, 0.09, 0.32, config.color, Enum.Font.GothamBlack)
	local divider = Instance.new("Frame")
	divider.Position = UDim2.fromScale(0.15, 0.445)
	divider.Size = UDim2.fromScale(0.7, 0.012)
	divider.BackgroundColor3 = config.color
	divider.BackgroundTransparency = 0.4
	divider.BorderSizePixel = 0
	divider.Parent = gui
	local status = label(gui, "", 0.5, 0.2, Color3.new(1, 1, 1), Enum.Font.GothamBold)
	label(gui, config.hint, 0.76, 0.17, Color3.fromRGB(200, 200, 215), Enum.Font.GothamMedium)

	return { center = at(offset, top), radius = size / 2, top = FLOOR + top, status = status }
end

-- Builds the whole hub into workspace.Hub and returns the two pads.
function HubBuilder.build(): { play: Pad, practice: Pad }
	local folder = Instance.new("Folder")
	folder.Name = "Hub"
	island(folder)
	boundary(folder)
	spawnMarker(folder)
	torii(folder)
	lanterns(folder)
	banners(folder)
	trees(folder)
	centerpiece(folder)
	local padConfigs = HubConfig.pads
	path(folder, padConfigs.play.offset)
	path(folder, padConfigs.practice.offset)
	local pads = {
		play = pad(folder, "Play", padConfigs.play),
		practice = pad(folder, "Practice", padConfigs.practice),
	}
	folder.Parent = workspace
	return pads
end

-- The hub's spawn point (for sending players back), a little above the marker.
function HubBuilder.spawnPosition(): Vector3
	return at(HubConfig.spawnOffset, 3)
end

-- True if `position` is under the island's floor by more than HubConfig.fallDepth, or outside the
-- island: the player fell or slipped out.
function HubBuilder.isOutside(position: Vector3): boolean
	local flat = Vector3.new(position.X - CENTER.X, 0, position.Z - CENTER.Z)
	return position.Y < FLOOR - HubConfig.fallDepth or flat.Magnitude > HubConfig.islandRadius + HubConfig.outsideMargin
end

return HubBuilder
