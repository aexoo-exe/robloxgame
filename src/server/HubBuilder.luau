-- Builds the hub, the "Sky Dojo", from parts (layout, colors and sizes in HubConfig):
--   * the main island: an arrival terrace with the spawn under a torii gate, a grand stair, the
--     avenue with the roster gallery's plinths grouped under faction banners, the central plaza
--     with the sword centerpiece ringed by the nine faction banners, and the arena gate whose
--     platform is the Play pad (8 spots that light up as players queue)
--   * a walled training yard off the plaza whose floor is the Practice pad, with training dummies
--   * the item shrine (a pavilion with the 15 items' pedestals) and the hall of fame (leaderboard
--     boards on the terrace)
--   * two outer islands joined by bridges (a lookout and a cherry garden) and a jumping route of
--     stepping stones from the lookout to a hidden islet
--   * a waterfall off the main island, lanterns, trees with falling petals
--   * an invisible box around everything (walls and a ceiling; transparent, so the camera never
--     snaps against it)
-- Statues, item icons, the cloud sea and the bobbing rocks are added on each client (HubScenery):
-- plinths and pedestals carry UnitType / ItemId attributes for it. Server only; HubService runs
-- the pads and the leaderboards. Prints the part count when built.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local HubConfig = require(Shared.HubConfig)
local ItemConfig = require(Shared.ItemConfig)
local ItemSkinConfig = require(Shared.ItemSkinConfig)
local SkinConfig = require(Shared.SkinConfig)
local TraitIconConfig = require(Shared.TraitIconConfig)
local UnitConfig = require(Shared.UnitConfig)

local HubBuilder = {}

-- A built pad: where to stand (HubService) and what to update.
export type Pad = {
	kind: string, -- "circle" or "rect"
	center: Vector3, -- circle: world center of its top
	radius: number,
	min: Vector3, -- rect: world corners (X and Z used)
	max: Vector3,
	top: number, -- world height of the pad's surface
	status: TextLabel, -- the display's live status line
	spots: { BasePart }, -- marked spots that light up as players queue (Play only)
	color: Color3,
}

-- A leaderboard board: rows go in `list`; `placeholder` shows while there are none.
export type Board = { list: Frame, placeholder: TextLabel }

local COLORS = HubConfig.colors
local CENTER = HubConfig.center
local UPRIGHT = CFrame.Angles(0, 0, math.pi / 2) -- stands a cylinder's axis (X) upright

local partCount = 0

-- World position of a hub-relative position.
local function at(offset: Vector3, lift: number?): Vector3
	return CENTER + offset + Vector3.new(0, lift or 0, 0)
end

-- A point on a circle around `origin` (hub-relative): angle 0 toward -Z, 90 toward +X.
local function around(origin: Vector3, angle: number, radius: number): Vector3
	local a = math.rad(angle)
	return origin + Vector3.new(radius * math.sin(a), 0, -radius * math.cos(a))
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
	partCount += 1
	return instance
end

-- A part that only decorates or glows: no collisions, clicks, touches or shadow.
local function ghost(instance: BasePart): BasePart
	instance.CanCollide = false
	instance.CanQuery = false
	instance.CanTouch = false
	instance.CastShadow = false
	return instance
end

-- A flat disc (an upright cylinder) centered on hub-relative `position`, whose top is at
-- position.Y.
local function disc(parent: Instance, position: Vector3, diameter: number, thickness: number, color: Color3, material: Enum.Material?): Part
	return part(
		parent,
		Vector3.new(thickness, diameter, diameter),
		CFrame.new(at(position, -thickness / 2)) * UPRIGHT,
		color,
		material,
		Enum.PartType.Cylinder
	)
end

-- A box over a hub-relative rectangle whose top is at `top`.
local function slab(parent: Instance, x: { number }, z: { number }, top: number, thickness: number, color: Color3, material: Enum.Material?): Part
	local position = Vector3.new((x[1] + x[2]) / 2, top - thickness / 2, (z[1] + z[2]) / 2)
	return part(parent, Vector3.new(x[2] - x[1], thickness, z[2] - z[1]), CFrame.new(at(position)), color, material)
end

-- Uneven rock layers: the same seed every build, so the hub always looks the same.
local shapeRandom = Random.new(11)

local function jitter(amount: number): number
	return shapeRandom:NextNumber(-amount, amount)
end

-- Rock tapering inward under a rectangle in uneven layers, each a little off-center and of its own
-- proportions (`top` is the rock's top).
local function rockUnderRect(parent: Instance, x: { number }, z: { number }, top: number)
	local layers = {
		{ 0.97, 5, COLORS.rock },
		{ 0.84, 7, COLORS.rockDark },
		{ 0.66, 9, COLORS.rock },
		{ 0.44, 10, COLORS.rockDark },
		{ 0.22, 8, COLORS.rock },
	}
	local midX, midZ = (x[1] + x[2]) / 2, (z[1] + z[2]) / 2
	local halfX, halfZ = (x[2] - x[1]) / 2, (z[2] - z[1]) / 2
	for index, layer in layers do
		local scaleX = layer[1] * (1 + jitter(0.06))
		local scaleZ = layer[1] * (1 + jitter(0.06))
		local shift = if index == 1 then 0 else 1
		local centerX = midX + jitter(halfX * 0.12) * shift
		local centerZ = midZ + jitter(halfZ * 0.12) * shift
		local material = if index % 2 == 0 then Enum.Material.Slate else Enum.Material.Rock
		slab(parent, { centerX - halfX * scaleX, centerX + halfX * scaleX }, { centerZ - halfZ * scaleZ, centerZ + halfZ * scaleZ }, top, layer[2], layer[3], material)
		top -= layer[2]
	end
end

-- The same under a disc.
local function rockUnderDisc(parent: Instance, position: Vector3, radius: number, top: number, layers: number?)
	local shapes = {
		{ 0.94, 6, COLORS.rock },
		{ 0.72, 8, COLORS.rockDark },
		{ 0.48, 9, COLORS.rock },
		{ 0.24, 7, COLORS.rockDark },
	}
	for i = 1, layers or #shapes do
		local layer = shapes[i]
		local shift = if i == 1 then 0 else radius * 0.12
		local center = Vector3.new(position.X + jitter(shift), top, position.Z + jitter(shift))
		disc(parent, center, radius * 2 * layer[1] * (1 + jitter(0.05)), layer[2], layer[3], if i % 2 == 0 then Enum.Material.Slate else Enum.Material.Rock)
		top -= layer[2]
	end
end

-- A grass lip just below a rectangle's floor, sticking out past its edges: a green rim from above
-- and a green band from the side, like the small islands.
local function grassLipRect(parent: Instance, x: { number }, z: { number }, top: number)
	slab(parent, { x[1] - 1.5, x[2] + 1.5 }, { z[1] - 1.5, z[2] + 1.5 }, top - 0.1, 2.5, COLORS.grass, Enum.Material.Grass)
end

local function grassLipDisc(parent: Instance, position: Vector3, radius: number, top: number)
	disc(parent, Vector3.new(position.X, top - 0.1, position.Z), radius * 2 + 3, 2.5, COLORS.grass, Enum.Material.Grass)
end

local function light(parent: Instance, color: Color3, range: number, brightness: number)
	local pointLight = Instance.new("PointLight")
	pointLight.Color = color
	pointLight.Range = range
	pointLight.Brightness = brightness
	pointLight.Shadows = false
	pointLight.Parent = parent
end

local function surface(target: BasePart, face: Enum.NormalId, pixelsPerStud: number): SurfaceGui
	local gui = Instance.new("SurfaceGui")
	gui.Face = face
	gui.LightInfluence = 0
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = pixelsPerStud
	gui.Parent = target
	return gui
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

local function traitColor(traitId: string): Color3
	local trait = TraitIconConfig[traitId]
	local rgb = if trait then trait.color else { 200, 200, 200 }
	return Color3.fromRGB(rgb[1], rgb[2], rgb[3])
end

-- Faces `cframe`'s front (-Z) from `from` toward `toward`, level (both hub-relative).
local function facing(from: Vector3, toward: Vector3): CFrame
	local origin = at(from)
	local target = at(toward)
	return CFrame.lookAt(origin, Vector3.new(target.X, origin.Y, target.Z))
end

-- Pieces -----------------------------------------------------------------------------------------

-- A low stone curb from `from` to `to` (hub-relative, y = the floor it stands on).
local function curb(parent: Instance, from: Vector3, to: Vector3)
	local length = (Vector3.new(to.X, 0, to.Z) - Vector3.new(from.X, 0, from.Z)).Magnitude
	local middle = (from + to) / 2
	local cframe = CFrame.lookAt(at(middle, 0.7), at(Vector3.new(to.X, middle.Y, to.Z), 0.7))
	part(parent, Vector3.new(1.2, 1.4, length + 1), cframe, COLORS.curb, Enum.Material.Slate)
	-- A red wooden rail along the top, the hub's accent color.
	part(parent, Vector3.new(1.4, 0.3, length + 1.2), cframe * CFrame.new(0, 0.85, 0), COLORS.rail, Enum.Material.Wood)
end

-- Curbs around a disc island, leaving gaps at `openings` (angles).
local function ringCurb(parent: Instance, position: Vector3, radius: number, openings: { number })
	local segments = 10
	for i = 1, segments do
		local a, b = (i - 1) * 360 / segments, i * 360 / segments
		local middle = (a + b) / 2
		local open = false
		for _, opening in openings do
			local difference = math.abs((middle - opening + 180) % 360 - 180)
			if difference < 30 then
				open = true
			end
		end
		if not open then
			curb(parent, around(position, a, radius - 0.6), around(position, b, radius - 0.6))
		end
	end
end

-- A glowing pool of light on the floor: a translucent disc just above it.
local function lightPool(parent: Instance, position: Vector3, diameter: number, color: Color3)
	local pool = disc(parent, position + Vector3.new(0, 0.13, 0), diameter, 0.05, color, Enum.Material.Neon)
	pool.Transparency = HubConfig.lightPools.transparency
	ghost(pool)
end

-- A banner: a pole with a cloth in the faction's color showing its symbol letters and name in
-- large letters, facing `toward`. `scale` 1 is the plaza banner; `widthScale` widens the cloth.
local function banner(parent: Instance, base: Vector3, toward: Vector3, traitId: string, scale: number, widthScale: number?)
	local trait = TraitIconConfig[traitId]
	if not trait then
		return
	end
	local color = traitColor(traitId)
	local poleHeight = 14 * scale
	part(parent, Vector3.new(poleHeight, 0.45, 0.45), CFrame.new(at(base, poleHeight / 2)) * UPRIGHT, COLORS.dark, Enum.Material.Wood, Enum.PartType.Cylinder)
	local clothSize = Vector2.new(3.4 * (widthScale or 1), 7) * scale
	local frame = facing(base, toward)
	local cloth = part(
		parent,
		Vector3.new(clothSize.X, clothSize.Y, 0.12),
		frame * CFrame.new(0, poleHeight - 0.4 - clothSize.Y / 2, -0.4),
		color,
		Enum.Material.Fabric
	)
	ghost(cloth)
	cloth:SetAttribute("Sway", true) -- HubScenery sways it gently around its top edge
	local gui = surface(cloth, Enum.NormalId.Front, 30)
	gui.LightInfluence = 0.3
	local emblem = Instance.new("Frame")
	emblem.AnchorPoint = Vector2.new(0.5, 0)
	emblem.Position = UDim2.fromScale(0.5, 0.08)
	local emblemWidth = math.min(0.8, 0.42 * clothSize.Y / clothSize.X) -- never taller than 42% of the cloth
	emblem.Size = UDim2.fromScale(emblemWidth, emblemWidth * clothSize.X / clothSize.Y)
	emblem.BackgroundColor3 = Color3.new(1, 1, 1)
	emblem.BackgroundTransparency = 0.1
	local round = Instance.new("UICorner")
	round.CornerRadius = UDim.new(0.5, 0)
	round.Parent = emblem
	emblem.Parent = gui
	label(emblem, trait.letters, 0.15, 0.7, color, Enum.Font.GothamBlack).TextStrokeTransparency = 1
	local name = label(gui, string.upper(trait.name), 0.56, 0.3, Color3.new(1, 1, 1), Enum.Font.GothamBlack)
	name.TextStrokeTransparency = 0
	name.TextStrokeColor3 = COLORS.dark
	local fringe = Instance.new("Frame")
	fringe.Position = UDim2.fromScale(0, 0.93)
	fringe.Size = UDim2.fromScale(1, 0.07)
	fringe.BackgroundColor3 = COLORS.gold
	fringe.BorderSizePixel = 0
	fringe.Parent = gui
end

-- A stone lantern (toro) with a warm light.
local function lantern(parent: Instance, base: Vector3)
	part(parent, Vector3.new(2.4, 0.7, 2.4), CFrame.new(at(base, 0.35)), COLORS.lanternStone, Enum.Material.Slate)
	part(parent, Vector3.new(2.8, 1, 1), CFrame.new(at(base, 2.1)) * UPRIGHT, COLORS.lanternStone, Enum.Material.Slate, Enum.PartType.Cylinder)
	local lamp = part(parent, Vector3.new(1.7, 1.5, 1.7), CFrame.new(at(base, 4.25)), COLORS.lanternLight, Enum.Material.Neon)
	light(lamp, COLORS.lanternLight, 16, 1.2)
	lamp:SetAttribute("Flame", true) -- HubScenery flickers its glow and light
	part(parent, Vector3.new(2.9, 0.6, 2.9), CFrame.new(at(base, 5.3)) * CFrame.Angles(0, math.rad(45), 0), COLORS.lanternStone, Enum.Material.Slate)
	lightPool(parent, base, HubConfig.lightPools.lantern, COLORS.lanternLight)
end

-- A cherry tree with falling petals.
local function tree(parent: Instance, base: Vector3)
	part(parent, Vector3.new(7.5, 1.3, 1.3), CFrame.new(at(base, 3.6)) * CFrame.Angles(math.rad(6), 0, 0) * UPRIGHT, COLORS.trunk, Enum.Material.Wood, Enum.PartType.Cylinder)
	local canopy = { { Vector3.new(0, 8.2, 0), 8.5 }, { Vector3.new(2.6, 7.2, 1.2), 6 }, { Vector3.new(-2.4, 7.6, -1), 5.6 } }
	for index, ball in canopy do
		local leaves = part(parent, Vector3.one * ball[2], CFrame.new(at(base + ball[1])), COLORS.blossom, Enum.Material.SmoothPlastic, Enum.PartType.Ball)
		leaves.CastShadow = index == 1
		if index == 1 then
			local petals = Instance.new("ParticleEmitter")
			petals.Color = ColorSequence.new(COLORS.blossom)
			petals.Size = NumberSequence.new(0.3)
			petals.Rate = 3
			petals.Lifetime = NumberRange.new(6, 9)
			petals.Speed = NumberRange.new(0.5, 1.5)
			petals.SpreadAngle = Vector2.new(180, 180)
			petals.Acceleration = Vector3.new(1.4, -0.6, 0.7) -- a light breeze carries them
			petals.Drag = 0.3
			petals.RotSpeed = NumberRange.new(-60, 60)
			petals.Rotation = NumberRange.new(0, 360)
			petals.LightEmission = 0.1
			petals.Parent = leaves
		end
	end
end

-- A display board on two posts with a glowing cap, facing `toward`: title, live status and one line
-- of instructions, each in its own band, so their text never overlaps. Returns the status label.
local function display(parent: Instance, base: Vector3, toward: Vector3, color: Color3, title: string, hint: string): TextLabel
	local size = HubConfig.displaySize
	local frame = facing(base, toward)
	local lift = 2.6
	local board = part(parent, Vector3.new(size.X, size.Y, 0.8), frame * CFrame.new(0, lift + size.Y / 2, 0), COLORS.displayBoard)
	for _, side in { -1, 1 } do
		part(
			parent,
			Vector3.new(0.9, lift + size.Y + 0.4, 0.9),
			frame * CFrame.new(side * (size.X / 2 + 0.45), (lift + size.Y + 0.4) / 2, 0),
			COLORS.displayFrame,
			Enum.Material.Slate
		)
	end
	part(parent, Vector3.new(size.X + 1.8, 0.5, 1.1), frame * CFrame.new(0, lift + size.Y + 0.45, 0), color, Enum.Material.Neon)
	local gui = surface(board, Enum.NormalId.Front, 40)
	local stripe = Instance.new("Frame")
	stripe.Size = UDim2.fromScale(1, 0.05)
	stripe.BackgroundColor3 = color
	stripe.BorderSizePixel = 0
	stripe.Parent = gui
	label(gui, title, 0.09, 0.3, color, Enum.Font.GothamBlack)
	local divider = Instance.new("Frame")
	divider.Position = UDim2.fromScale(0.15, 0.43)
	divider.Size = UDim2.fromScale(0.7, 0.012)
	divider.BackgroundColor3 = color
	divider.BackgroundTransparency = 0.4
	divider.BorderSizePixel = 0
	divider.Parent = gui
	local status = label(gui, "", 0.48, 0.2, Color3.new(1, 1, 1), Enum.Font.GothamBold)
	label(gui, hint, 0.75, 0.17, Color3.fromRGB(200, 200, 215), Enum.Font.GothamMedium)
	return status
end

-- A walkway with a rail on each side between two hub-relative points.
local function bridge(parent: Instance, from: Vector3, to: Vector3)
	local length = (to - from).Magnitude
	local cframe = CFrame.lookAt(at((from + to) / 2), at(to))
	part(parent, Vector3.new(5, 0.6, length + 2), cframe * CFrame.new(0, -0.3, 0), COLORS.wood, Enum.Material.WoodPlanks)
	for _, side in { -1, 1 } do
		part(parent, Vector3.new(0.4, 0.4, length + 2), cframe * CFrame.new(side * 2.6, 2.6, 0), COLORS.torii, Enum.Material.Wood)
		part(parent, Vector3.new(0.5, 2.6, 0.5), cframe * CFrame.new(side * 2.6, 1.3, 0), COLORS.torii, Enum.Material.Wood)
	end
end

-- Zones ----------------------------------------------------------------------------------------

-- The main ground: the spine, the plaza, the arrival terrace with its stair, and their rock.
local function mainIsland(folder: Instance)
	local spine = HubConfig.spine
	slab(folder, spine.x, spine.z, 0, 3, COLORS.ground, Enum.Material.Slate)
	grassLipRect(folder, spine.x, spine.z, 0)
	rockUnderRect(folder, spine.x, spine.z, -3)
	local plaza = HubConfig.plaza
	disc(folder, plaza.center + Vector3.new(0, 0.04, 0), plaza.radius * 2, 3, COLORS.ground, Enum.Material.Slate)
	grassLipDisc(folder, plaza.center, plaza.radius, 0.04)
	rockUnderDisc(folder, plaza.center, plaza.radius, -3, 3)
	-- The avenue: pale paving from the stair to the arena gate with a terracotta border, under the
	-- plaza's gold inlay.
	local half = HubConfig.avenueHalfWidth
	slab(folder, { -half, half }, { spine.z[1] + 8, spine.z[2] }, 0.06, 0.3, COLORS.avenue, Enum.Material.Pavement)
	for _, side in { -1, 1 } do
		slab(folder, { side * half - 0.6, side * half + 0.6 }, { spine.z[1] + 8, spine.z[2] }, 0.07, 0.3, COLORS.tile, Enum.Material.Brick)
	end
	disc(folder, plaza.center + Vector3.new(0, 0.08, 0), 40, 0.3, COLORS.inlay, Enum.Material.Marble)
	disc(folder, plaza.center + Vector3.new(0, 0.1, 0), 37, 0.3, COLORS.inlayInner, Enum.Material.Slate)

	-- The terrace: its floor, a grass lip on its sides and back (the front meets the stair), a solid
	-- riser down to the avenue behind the stair, and rock tapering under the rest.
	local terrace = HubConfig.terrace
	local h = terrace.height
	slab(folder, terrace.x, terrace.z, h, 2, COLORS.ground, Enum.Material.Slate)
	slab(folder, { terrace.x[1] - 1.5, terrace.x[2] + 1.5 }, { terrace.z[1], terrace.z[2] + 1.5 }, h - 0.1, 2.5, COLORS.grass, Enum.Material.Grass)
	slab(folder, { terrace.x[1] + 0.5, terrace.x[2] - 0.5 }, { terrace.z[1], terrace.z[1] + 6 }, h - 2, h - 2, COLORS.rock, Enum.Material.Rock)
	rockUnderRect(folder, terrace.x, terrace.z, h - 2)

	-- The grand stair down from the terrace's front edge, with a balustrade on each side.
	local stairs = HubConfig.stairs
	local front = terrace.z[1]
	for step = 1, stairs.steps do
		local near = front - (step - 1) * stairs.depth
		slab(folder, { -stairs.halfWidth, stairs.halfWidth }, { near - stairs.depth, near }, terrace.height - step, terrace.height - step, COLORS.avenue, Enum.Material.Pavement)
	end
	local bottom = front - stairs.steps * stairs.depth
	for _, side in { -1, 1 } do
		local x = side * (stairs.halfWidth + 0.6)
		local top, low = Vector3.new(x, terrace.height + 1.2, front), Vector3.new(x, 1.2, bottom)
		part(folder, Vector3.new(1.2, 1.4, (top - low).Magnitude + 1), CFrame.lookAt(at((top + low) / 2), at(low)), COLORS.curb, Enum.Material.Slate)
	end
end

-- Curbs along the open edges of the spine and the terrace.
local function edges(folder: Instance)
	local h = HubConfig.terrace.height
	local v = Vector3.new
	local runs = {
		{ v(36, 0, 124), v(36, 0, 70) },
		{ v(36, 0, 62), v(36, 0, 29) },
		{ v(-36, 0, 124), v(-36, 0, 29) },
		{ v(36, 0, -29), v(36, 0, -135) },
		{ v(36, 0, -145), v(36, 0, -160) },
		{ v(-36, 0, -29), v(-36, 0, -160) },
		{ v(-36, 0, -160), v(36, 0, -160) },
		{ v(-82, h, 166), v(28, h, 166) },
		{ v(-82, h, 124), v(-82, h, 166) },
		{ v(28, h, 124), v(28, h, 166) },
		{ v(-82, h, 124), v(-16, h, 124) },
		{ v(16, h, 124), v(28, h, 124) },
	}
	for _, run in runs do
		curb(folder, run[1], run[2])
	end
end

-- The spawn: an invisible SpawnLocation over a round marker, under a torii gate.
local function arrival(folder: Instance)
	local position = HubConfig.spawn
	local spawn = Instance.new("SpawnLocation")
	spawn.Anchored = true
	spawn.Neutral = true
	spawn.Duration = 0 -- no spawn force field
	spawn.Size = Vector3.new(6, 0.2, 6)
	spawn.CFrame = CFrame.new(at(position, 0.4)) -- faces -Z, down the stair and the avenue
	spawn.Transparency = 1
	spawn.CanCollide = false
	spawn.CanTouch = false
	spawn.Parent = folder
	partCount += 1

	local ring = disc(folder, position + Vector3.new(0, 0.14, 0), 10.6, 0.3, COLORS.spawnGlow, Enum.Material.Neon)
	light(ring, COLORS.spawnGlow, 12, 1)
	disc(folder, position + Vector3.new(0, 0.2, 0), 9.4, 0.3, COLORS.spawnStone, Enum.Material.Marble)
	disc(folder, position + Vector3.new(0, 0.26, 0), 3.4, 0.2, COLORS.gold, Enum.Material.Metal)
	for i = 0, 3 do
		part(folder, Vector3.new(1, 0.12, 1), CFrame.new(at(around(position, i * 90, 3.2), 0.24)) * CFrame.Angles(0, math.rad(45), 0), COLORS.gold, Enum.Material.Metal)
	end

	local gate = HubConfig.torii
	for _, side in { -1, 1 } do
		local pillar = gate + Vector3.new(side * 7, 0, 0)
		part(folder, Vector3.new(13.6, 1.4, 1.4), CFrame.new(at(pillar, 6.8)) * UPRIGHT, COLORS.torii, Enum.Material.Wood, Enum.PartType.Cylinder)
		part(folder, Vector3.new(2.2, 0.8, 2.2), CFrame.new(at(pillar, 0.4)), COLORS.dark, Enum.Material.Slate)
	end
	part(folder, Vector3.new(20, 1, 2), CFrame.new(at(gate, 14.1)), COLORS.dark, Enum.Material.Wood)
	part(folder, Vector3.new(18, 0.8, 1.5), CFrame.new(at(gate, 13.2)), COLORS.torii, Enum.Material.Wood)
	part(folder, Vector3.new(16.4, 0.7, 1), CFrame.new(at(gate, 10.8)), COLORS.torii, Enum.Material.Wood)
	local plaque = part(folder, Vector3.new(2.4, 1.7, 0.3), CFrame.new(at(gate, 12)), COLORS.dark, Enum.Material.Wood)
	for _, face in { Enum.NormalId.Front, Enum.NormalId.Back } do
		label(surface(plaque, face, 50), "道場", 0.08, 0.84, COLORS.gold, Enum.Font.GothamBlack)
	end
end

-- The sword in the stone, ringed by the nine faction banners.
local function plaza(folder: Instance)
	local origin = HubConfig.centerpiece
	ghost(disc(folder, origin + Vector3.new(0, 0.16, 0), 10.8, 0.3, COLORS.glow, Enum.Material.Neon))
	disc(folder, origin + Vector3.new(0, 1.4, 0), 9, 1.4, COLORS.rockDark, Enum.Material.Slate)
	disc(folder, origin + Vector3.new(0, 2.6, 0), 6, 1.2, COLORS.lanternStone, Enum.Material.Slate)
	local pivot = CFrame.new(at(origin, 2.6)) * CFrame.Angles(math.rad(4), math.rad(30), math.rad(7))
	local blade = part(folder, Vector3.new(0.35, 11, 1.4), pivot * CFrame.new(0, 4.7, 0), COLORS.blade, Enum.Material.Metal)
	light(blade, COLORS.glow, 18, 1)
	part(folder, Vector3.new(0.15, 10.4, 0.25), pivot * CFrame.new(0, 4.6, 0.62), COLORS.gold, Enum.Material.Neon)
	part(folder, Vector3.new(0.4, 3.4, 3.4), pivot * CFrame.new(0, 10.4, 0) * UPRIGHT, COLORS.gold, Enum.Material.Metal, Enum.PartType.Cylinder)
	part(folder, Vector3.new(0.85, 3.6, 0.85), pivot * CFrame.new(0, 12.4, 0), COLORS.hilt, Enum.Material.Fabric)
	part(folder, Vector3.new(1, 1, 1), pivot * CFrame.new(0, 14.5, 0), COLORS.gold, Enum.Material.Metal, Enum.PartType.Ball)

	local factions = HubConfig.plazaBannerFactions
	for index, traitId in factions do
		local angle = (index - 1) * 360 / #factions + 20
		local base = around(origin, angle, HubConfig.plazaBannerRadius)
		banner(folder, base, around(origin, angle, HubConfig.plazaBannerRadius + 10), traitId, 1)
	end
end

-- The roster gallery: a plinth per unit along the avenue, grouped by faction under a banner.
local function gallery(folder: Instance)
	local config = HubConfig.gallery
	local byFaction: { [string]: { string } } = {}
	for unitType, unit in UnitConfig do
		byFaction[unit.origin] = byFaction[unit.origin] or {}
		table.insert(byFaction[unit.origin], unitType)
	end
	for _, list in byFaction do
		table.sort(list, function(a, b)
			local costA, costB = UnitConfig[a].cost, UnitConfig[b].cost
			if costA ~= costB then
				return costA < costB
			end
			return SkinConfig[a].name < SkinConfig[b].name
		end)
	end

	local plinths = Instance.new("Folder")
	plinths.Name = "Gallery"
	for _, row in config.rows do
		local direction = if row.to < row.from then -1 else 1
		local cursor = row.from
		local outward = if row.x < 0 then -1 else 1
		for _, faction in row.factions do
			local base = Vector3.new(row.x + outward * 3.2, 0, cursor + direction * config.groupGap / 2)
			banner(folder, base, Vector3.new(0, 0, base.Z), faction, config.bannerScale, config.bannerWidth)
			cursor += direction * config.groupGap
			for _, unitType in byFaction[faction] or {} do
				local position = Vector3.new(row.x, 0, cursor + direction * config.spacing / 2)
				cursor += direction * config.spacing
				local frame = facing(position, Vector3.new(0, 0, position.Z))
				local plinth = part(
					plinths,
					Vector3.new(3, config.plinthHeight, 3),
					frame * CFrame.new(0, config.plinthHeight / 2, 0),
					COLORS.plinth,
					Enum.Material.Marble
				)
				plinth.Name = unitType
				plinth:SetAttribute("UnitType", unitType)
				-- A small uplight on the statue, so each one stands out along the avenue.
				local uplight = Instance.new("SpotLight")
				uplight.Face = Enum.NormalId.Top
				uplight.Color = COLORS.lanternLight:Lerp(Color3.new(1, 1, 1), 0.5)
				uplight.Range = config.statueLight.range
				uplight.Brightness = config.statueLight.brightness
				uplight.Angle = config.statueLight.angle
				uplight.Shadows = false
				uplight.Parent = plinth
				local gui = surface(plinth, Enum.NormalId.Front, 40)
				local band = Instance.new("Frame")
				band.Position = UDim2.fromScale(0, 0.12)
				band.Size = UDim2.fromScale(1, 0.05)
				band.BackgroundColor3 = traitColor(faction)
				band.BorderSizePixel = 0
				band.Parent = gui
				label(gui, SkinConfig[unitType].name, 0.3, 0.32, COLORS.dark, Enum.Font.GothamBlack).TextStrokeTransparency = 1
			end
		end
	end
	plinths.Parent = folder
end

-- The arena gate and its platform (the Play pad), with the display. Returns the pad.
local function arenaGate(folder: Instance): Pad
	local config = HubConfig.pads.play
	local origin = config.center
	local top = config.height
	disc(folder, origin + Vector3.new(0, 0.6, 0), config.radius * 2 + 3, 0.6, COLORS.rockDark, Enum.Material.Slate)
	disc(folder, origin + Vector3.new(0, 0.9, 0), config.radius * 2 + 1.4, 0.3, config.color, Enum.Material.Neon)
	local dark = config.color:Lerp(Color3.new(0, 0, 0), 0.6)
	local surfacePart = disc(folder, origin + Vector3.new(0, top, 0), config.radius * 2, top - 0.6, dark, Enum.Material.Glass)
	light(surfacePart, config.color, 24, 2)
	local spots = {}
	for i = 1, config.spots do
		local spot = disc(folder, around(origin, (i - 1) * 360 / config.spots, config.spotRadius) + Vector3.new(0, top + 0.06, 0), 3.2, 0.1, COLORS.spotOff, Enum.Material.SmoothPlastic)
		spot.Name = "Spot" .. i
		table.insert(spots, spot)
	end
	local beam = disc(folder, origin + Vector3.new(0, top + HubConfig.beamHeight, 0), 5, HubConfig.beamHeight, config.color, Enum.Material.Neon)
	beam.Transparency = 0.85
	ghost(beam)

	-- The gate: two great pillars, double beams, a tiled roof with raised ends, dark doors with a
	-- glowing portal in front, and a plaque.
	local gate = HubConfig.gate
	local c = gate.center
	local half = gate.width / 2
	for _, side in { -1, 1 } do
		part(folder, Vector3.new(4, gate.height, 4), CFrame.new(at(c + Vector3.new(side * half, gate.height / 2, 0))), COLORS.torii, Enum.Material.Wood)
		part(folder, Vector3.new(5.5, 2, 5.5), CFrame.new(at(c + Vector3.new(side * half, 1, 0))), COLORS.dark, Enum.Material.Slate)
		part(
			folder,
			Vector3.new(8, 1.4, 9),
			CFrame.new(at(c + Vector3.new(side * (half + 6), gate.height + 3.6, 0))) * CFrame.Angles(0, 0, math.rad(side * 18)),
			COLORS.roof,
			Enum.Material.Slate
		)
	end
	part(folder, Vector3.new(gate.width + 8, 3, 5), CFrame.new(at(c + Vector3.new(0, gate.height + 1.5, 0))), COLORS.dark, Enum.Material.Wood)
	part(folder, Vector3.new(gate.width + 4, 2, 3.6), CFrame.new(at(c + Vector3.new(0, gate.height - 3, 0))), COLORS.torii, Enum.Material.Wood)
	part(folder, Vector3.new(gate.width + 6, 1.4, 9), CFrame.new(at(c + Vector3.new(0, gate.height + 3.7, 0))), COLORS.roof, Enum.Material.Slate)
	part(folder, Vector3.new(gate.width - 4, gate.height - 5, 1), CFrame.new(at(c + Vector3.new(0, (gate.height - 5) / 2, -1.5))), COLORS.dark, Enum.Material.Wood)
	local portal = part(folder, Vector3.new(gate.width - 8, gate.height - 9, 0.3), CFrame.new(at(c + Vector3.new(0, (gate.height - 9) / 2 + 1, 2.6))), COLORS.portal, Enum.Material.Neon)
	portal.Transparency = 0.55
	ghost(portal)
	light(portal, COLORS.portal, 26, 1.5)
	portal:SetAttribute("Pulse", true) -- HubScenery makes it pulse

	-- Light pools around the platform and in front of the gate.
	local pools = HubConfig.lightPools
	lightPool(folder, origin, pools.pad, config.color)
	lightPool(folder, Vector3.new(c.X, 0, c.Z + 4), pools.gate, COLORS.portal)
	local plaque = part(folder, Vector3.new(8, 2.6, 0.4), CFrame.new(at(c + Vector3.new(0, gate.height + 1.5, 2.7))), COLORS.gold, Enum.Material.Metal)
	label(surface(plaque, Enum.NormalId.Back, 40), "闘技場  ARENA", 0.12, 0.76, COLORS.dark, Enum.Font.GothamBlack).TextStrokeTransparency = 1

	local status = display(folder, config.display, config.displayFacing, config.color, config.title, config.hint)
	return {
		kind = "circle",
		center = at(origin, top),
		radius = config.radius,
		min = Vector3.zero,
		max = Vector3.zero,
		top = CENTER.Y + top,
		status = status,
		spots = spots,
		color = config.color,
	}
end

-- The training yard: a walled wooden courtyard whose floor is the Practice pad, dressed with a
-- sparring ring, practice mats, weapon racks, a roofed walkway along the walls and dummies.
local function trainingYard(folder: Instance): Pad
	local config = HubConfig.pads.practice
	local yard = HubConfig.yard
	local x, z = { config.x[1] - 1, config.x[2] + 1 }, { config.z[1] - 1, config.z[2] + 1 }
	slab(folder, x, z, config.height, 3, COLORS.wood, Enum.Material.WoodPlanks)
	-- A grass lip on the three outer sides (the fourth meets the plaza).
	slab(folder, { x[1], x[2] + 1.5 }, { z[1] - 1.5, z[2] + 1.5 }, config.height - 0.1, 2.5, COLORS.grass, Enum.Material.Grass)
	rockUnderRect(folder, x, z, config.height - 3)
	local height = yard.wallHeight
	local wall = function(from: Vector3, to: Vector3)
		local length = (to - from).Magnitude
		local frame = CFrame.lookAt(at((from + to) / 2, height / 2), at(to, height / 2))
		part(folder, Vector3.new(1.2, height, length + 1.2), frame, COLORS.spawnStone, Enum.Material.Plaster)
		part(folder, Vector3.new(2.2, 0.8, length + 2.2), frame * CFrame.new(0, height / 2 + 0.3, 0), COLORS.roof, Enum.Material.Slate)
	end
	local y = config.height
	local open = yard.openingHalfWidth
	wall(Vector3.new(x[2], y, z[1]), Vector3.new(x[2], y, z[2]))
	wall(Vector3.new(x[1], y, z[1]), Vector3.new(x[2], y, z[1]))
	wall(Vector3.new(x[1], y, z[2]), Vector3.new(x[2], y, z[2]))
	wall(Vector3.new(x[1], y, z[1]), Vector3.new(x[1], y, -open))
	wall(Vector3.new(x[1], y, open), Vector3.new(x[1], y, z[2]))
	-- A beam over the opening, with the yard's name.
	local beam = part(folder, Vector3.new(1.6, 1.6, open * 2 + 3), CFrame.new(at(Vector3.new(x[1], y + height + 0.2, 0))), COLORS.torii, Enum.Material.Wood)
	label(surface(beam, Enum.NormalId.Left, 40), "修行場  TRAINING YARD", 0.05, 0.9, COLORS.gold, Enum.Font.GothamBlack)

	-- Training dummies (some larger), facing the opening.
	for _, dummy in yard.dummies do
		local s = dummy.scale
		local base = dummy.position + Vector3.new(0, y, 0)
		local frame = facing(base, Vector3.new(x[1], base.Y, base.Z))
		part(folder, Vector3.new(5 * s, 0.5 * s, 0.5 * s), CFrame.new(at(base, 2.5 * s)) * UPRIGHT, COLORS.wood, Enum.Material.Wood, Enum.PartType.Cylinder)
		part(folder, Vector3.new(1.6, 2.6, 1.2) * s, frame * CFrame.new(0, 4.4 * s, 0), COLORS.blossom:Lerp(COLORS.wood, 0.7), Enum.Material.Fabric)
		part(folder, Vector3.new(4, 0.4, 0.4) * s, frame * CFrame.new(0, 5 * s, 0), COLORS.wood, Enum.Material.Wood)
		part(folder, Vector3.one * 1.4 * s, frame * CFrame.new(0, 6.5 * s, 0), COLORS.spawnStone, Enum.Material.Fabric, Enum.PartType.Ball)
	end

	-- The sparring ring (HubScenery puts two sparring figures in it) and practice mats.
	local ring = yard.ring
	disc(folder, ring.center + Vector3.new(0, y + 0.06, 0), ring.radius * 2, 0.1, COLORS.tile, Enum.Material.Fabric)
	disc(folder, ring.center + Vector3.new(0, y + 0.08, 0), ring.radius * 2 - 1.2, 0.1, COLORS.avenue, Enum.Material.Fabric)
	for index, position in yard.mats do
		local color = yard.matColors[(index - 1) % #yard.matColors + 1]
		part(folder, Vector3.new(6, 0.15, 4), CFrame.new(at(position, y + 0.075)), color, Enum.Material.Fabric)
	end

	-- Weapon racks against the side walls: a backboard, a base and two staves, facing the yard.
	for _, position in yard.racks do
		local base = position + Vector3.new(0, y, 0)
		local frame = facing(base, Vector3.new(base.X, base.Y, 0))
		part(folder, Vector3.new(4, 3.4, 0.3), frame * CFrame.new(0, 1.9, 0.3), COLORS.wood, Enum.Material.Wood)
		part(folder, Vector3.new(4.2, 0.4, 0.9), frame * CFrame.new(0, 0.2, 0), COLORS.dark, Enum.Material.Wood)
		for _, side in { -1, 1 } do
			part(folder, Vector3.new(0.22, 3.8, 0.22), frame * CFrame.new(side * 1.1, 2.1, -0.1) * CFrame.Angles(math.rad(-6), 0, 0), if side < 0 then COLORS.blade else COLORS.trunk, Enum.Material.Metal)
		end
	end

	-- A roofed walkway inside the back and side walls: red posts and a green roof.
	local depth, roofHeight = yard.walkwayDepth, yard.walkwayHeight
	local postX = x[2] - depth
	local posts = {}
	for _, px in yard.walkwayPosts do
		table.insert(posts, Vector3.new(px, y, z[1] + depth))
		table.insert(posts, Vector3.new(px, y, z[2] - depth))
	end
	table.insert(posts, Vector3.new(postX, y, z[1] + depth))
	table.insert(posts, Vector3.new(postX, y, z[2] - depth))
	for _, pz in yard.walkwayBackPosts do
		table.insert(posts, Vector3.new(postX, y, pz))
	end
	for _, post in posts do
		part(folder, Vector3.new(0.7, roofHeight, 0.7), CFrame.new(at(post, roofHeight / 2)), COLORS.rail, Enum.Material.Wood)
	end
	local roofTop = y + roofHeight + 0.5
	slab(folder, { x[1] + 0.6, x[2] }, { z[1], z[1] + depth + 0.6 }, roofTop, 0.5, COLORS.roof, Enum.Material.Slate)
	slab(folder, { x[1] + 0.6, x[2] }, { z[2] - depth - 0.6, z[2] }, roofTop, 0.5, COLORS.roof, Enum.Material.Slate)
	slab(folder, { postX - 0.6, x[2] }, { z[1] + depth + 0.6, z[2] - depth - 0.6 }, roofTop, 0.5, COLORS.roof, Enum.Material.Slate)

	lightPool(folder, Vector3.new(x[1] - 4, 0, 0), HubConfig.lightPools.yard, config.color)

	local status = display(folder, config.display, config.displayFacing, config.color, config.title, config.hint)
	return {
		kind = "rect",
		center = Vector3.zero,
		radius = 0,
		min = at(Vector3.new(config.x[1], config.height, config.z[1])),
		max = at(Vector3.new(config.x[2], config.height, config.z[2])),
		top = CENTER.Y + config.height,
		status = status,
		spots = {},
		color = config.color,
	}
end

-- The item shrine: a pavilion with a pedestal per item, in an arc open toward the plaza.
local function shrine(folder: Instance)
	local config = HubConfig.shrine
	local origin = config.center
	disc(folder, origin + Vector3.new(0, 0.3, 0), config.radius * 2, 3, COLORS.ground, Enum.Material.Slate)
	grassLipDisc(folder, origin, config.radius, 0.3)
	rockUnderDisc(folder, origin, config.radius, -2.7, 3)
	disc(folder, origin + Vector3.new(0, 0.9, 0), config.daisRadius * 2, 0.8, COLORS.plinth, Enum.Material.Marble)
	local roofHeight = 9.5
	for i = 0, 7 do
		local pillar = around(origin, i * 45 + 22.5, config.daisRadius - 1.2)
		part(folder, Vector3.new(roofHeight - 0.9, 1, 1), CFrame.new(at(pillar, 0.9 + (roofHeight - 0.9) / 2)) * UPRIGHT, COLORS.torii, Enum.Material.Wood, Enum.PartType.Cylinder)
	end
	for tier, size in { { 32, roofHeight + 0.5 }, { 20, roofHeight + 2.5 } } do
		for _, turn in { 0, 45 } do
			part(folder, Vector3.new(size[1], 1.2, size[1]), CFrame.new(at(origin, size[2])) * CFrame.Angles(0, math.rad(turn), 0), if tier == 1 then COLORS.roof else COLORS.torii, Enum.Material.Slate)
		end
	end
	part(folder, Vector3.new(1.6, 1.6, 1.6), CFrame.new(at(origin, roofHeight + 4)), COLORS.gold, Enum.Material.Metal, Enum.PartType.Ball)
	local hanging = part(folder, Vector3.new(1.4, 1.8, 1.4), CFrame.new(at(origin, roofHeight - 2)), COLORS.lanternLight, Enum.Material.Neon)
	ghost(hanging)
	light(hanging, COLORS.lanternLight, 20, 1.2)

	local ids = {}
	for itemId in ItemConfig.items do
		table.insert(ids, itemId)
	end
	local order = { [ItemConfig.Category.Offensive] = 1, [ItemConfig.Category.Ability] = 2, [ItemConfig.Category.Defensive] = 3 }
	table.sort(ids, function(a, b)
		local categoryA, categoryB = order[ItemConfig.items[a].category], order[ItemConfig.items[b].category]
		if categoryA ~= categoryB then
			return categoryA < categoryB
		end
		return ItemSkinConfig.items[a].name < ItemSkinConfig.items[b].name
	end)
	local pedestals = Instance.new("Folder")
	pedestals.Name = "Shrine"
	local first, last = config.arc[1], config.arc[2]
	for index, itemId in ids do
		local angle = first + (last - first) * (index - 1) / math.max(#ids - 1, 1)
		local position = around(origin, angle, config.pedestalRadius) + Vector3.new(0, 0.9, 0)
		local frame = facing(position, origin)
		local pedestal = part(pedestals, Vector3.new(1.8, 2.6, 1.8), frame * CFrame.new(0, 1.3, 0), COLORS.plinth, Enum.Material.Marble)
		pedestal.Name = itemId
		pedestal:SetAttribute("ItemId", itemId)
	end
	pedestals.Parent = folder
end

-- The hall of fame: leaderboard boards and a podium on the terrace's wing. Returns the boards.
local function hallOfFame(folder: Instance): { [string]: Board }
	local config = HubConfig.hall
	local boards = {}
	for _, entry in config.boards do
		-- Upright, facing straight into the terrace (+X), in a wooden frame with a small roof, so
		-- its back reads as a finished sign from outside too.
		local frame = facing(entry.position, entry.position + Vector3.new(10, 0, 0))
		local board = part(folder, Vector3.new(10, 11, 0.8), frame * CFrame.new(0, 6.5, 0), COLORS.displayBoard)
		part(folder, Vector3.new(10.6, 11.6, 0.4), frame * CFrame.new(0, 6.5, 0.6), COLORS.wood, Enum.Material.WoodPlanks)
		for _, side in { -1, 1 } do
			part(folder, Vector3.new(0.8, 13, 0.8), frame * CFrame.new(side * 5.5, 6.5, 0.2), COLORS.rail, Enum.Material.Wood)
		end
		part(folder, Vector3.new(11.4, 0.6, 1.2), frame * CFrame.new(0, 12.3, 0), COLORS.gold, Enum.Material.Metal)
		part(folder, Vector3.new(13, 0.7, 3.2), frame * CFrame.new(0, 13.3, 0.2), COLORS.roof, Enum.Material.Slate)
		local gui = surface(board, Enum.NormalId.Front, 40)
		label(gui, entry.title, 0.03, 0.12, COLORS.gold, Enum.Font.GothamBlack)
		local list = Instance.new("Frame")
		list.Name = "Rows"
		list.BackgroundTransparency = 1
		list.Position = UDim2.fromScale(0.06, 0.2)
		list.Size = UDim2.fromScale(0.88, 0.76)
		local layout = Instance.new("UIListLayout")
		layout.SortOrder = Enum.SortOrder.LayoutOrder
		layout.Padding = UDim.new(0.01, 0)
		layout.Parent = list
		list.Parent = gui
		local placeholder = label(gui, config.placeholder, 0.45, 0.12, Color3.fromRGB(200, 200, 215), Enum.Font.GothamMedium)
		boards[entry.id] = { list = list, placeholder = placeholder }
	end
	-- A podium in front of the boards, facing the same way: a base, then 2nd, 1st and 3rd, with a
	-- trophy on 1st. Its numbers face the rest of the terrace (away from the boards).
	local podium = config.podium
	local frame = facing(podium, podium + Vector3.new(10, 0, 0))
	part(folder, Vector3.new(14, 0.4, 5.6), frame * CFrame.new(0, 0.2, 0), COLORS.curb, Enum.Material.Slate)
	-- Local +X is the viewer's left here, so 2nd stands on the left as seen from the terrace.
	for index, step in { { 4.2, 2, "2" }, { 0, 3, "1" }, { -4.2, 1.4, "3" } } do
		local block = part(folder, Vector3.new(4, step[2], 4), frame * CFrame.new(step[1], 0.4 + step[2] / 2, 0), if index == 2 then COLORS.gold else COLORS.plinth, Enum.Material.Marble)
		label(surface(block, Enum.NormalId.Front, 30), step[3], 0.1, 0.8, COLORS.dark, Enum.Font.GothamBlack).TextStrokeTransparency = 1
	end
	part(folder, Vector3.new(0.4, 1.2, 1.2), frame * CFrame.new(0, 3.6, 0) * UPRIGHT, COLORS.gold, Enum.Material.Metal, Enum.PartType.Cylinder)
	part(folder, Vector3.new(1.4, 1.4, 1.4), frame * CFrame.new(0, 4.4, 0), COLORS.gold, Enum.Material.Metal, Enum.PartType.Ball)
	return boards
end

-- The lookout, the garden, the hidden islet and the stepping stones between them.
local function outerIslands(folder: Instance)
	local islands = HubConfig.islands
	local lookout, garden, hidden = islands.lookout, islands.garden, islands.hidden
	disc(folder, lookout.center, lookout.radius * 2, 3, COLORS.ground, Enum.Material.Slate)
	grassLipDisc(folder, lookout.center, lookout.radius, lookout.center.Y)
	rockUnderDisc(folder, lookout.center, lookout.radius, lookout.center.Y - 3)
	ringCurb(folder, lookout.center, lookout.radius, { 270, 73 })
	-- A telescope on a stand and a bench, looking out over the clouds.
	local scope = lookout.center + Vector3.new(6, 0, -6)
	part(folder, Vector3.new(3, 0.5, 0.5), CFrame.new(at(scope, 1.5)) * UPRIGHT, COLORS.dark, Enum.Material.Metal, Enum.PartType.Cylinder)
	part(folder, Vector3.new(3.2, 0.6, 0.6), CFrame.new(at(scope, 3.2)) * CFrame.Angles(0, math.rad(-45), math.rad(20)), COLORS.gold, Enum.Material.Metal, Enum.PartType.Cylinder)
	part(folder, Vector3.new(5, 0.6, 1.6), CFrame.new(at(lookout.center + Vector3.new(-4, 0, 6), 1)) * CFrame.Angles(0, math.rad(30), 0), COLORS.wood, Enum.Material.WoodPlanks)

	disc(folder, garden.center, garden.radius * 2, 3, COLORS.grass, Enum.Material.Grass)
	rockUnderDisc(folder, garden.center, garden.radius, garden.center.Y - 3)
	ringCurb(folder, garden.center, garden.radius, { 67 })
	lantern(folder, garden.center + Vector3.new(4, 0, -4))

	disc(folder, hidden.center, hidden.radius * 2, 2, COLORS.grass, Enum.Material.Grass)
	rockUnderDisc(folder, hidden.center, hidden.radius, hidden.center.Y - 2, 2)
	-- The hidden spot's reward: a small glowing shrine with a note.
	local chest = part(folder, Vector3.new(2.4, 1.6, 1.6), CFrame.new(at(hidden.center, 0.8)), COLORS.torii, Enum.Material.Wood)
	part(folder, Vector3.new(2.6, 0.4, 1.8), CFrame.new(at(hidden.center, 1.8)), COLORS.gold, Enum.Material.Metal)
	local orb = part(folder, Vector3.one * 1.2, CFrame.new(at(hidden.center, 3)), COLORS.spawnGlow, Enum.Material.Neon, Enum.PartType.Ball)
	ghost(orb)
	light(orb, COLORS.spawnGlow, 14, 2)
	local note = surface(chest, Enum.NormalId.Back, 60) -- +Z: toward the last stepping stone
	label(note, "Hidden shrine found!", 0.1, 0.8, COLORS.gold, Enum.Font.GothamBlack)

	for _, stone in HubConfig.stones do
		disc(folder, stone, HubConfig.stoneRadius * 2, 1.4, COLORS.rock, Enum.Material.Slate)
	end
	for _, link in HubConfig.bridges do
		bridge(folder, link.from, link.to)
	end
end

local function emitter(parent: Instance, settings: { [string]: any })
	local particles = Instance.new("ParticleEmitter")
	for property, value in settings do
		(particles :: any)[property] = value
	end
	particles.Parent = parent
end

-- The waterfall: a spring pool with a stone rim, a straight stream between stone banks to the +X
-- edge, a band of foam where it tips over, and three layered sheets falling straight down the
-- island's side into the clouds, with spray along them and mist where they meet the clouds.
local function waterfall(folder: Instance)
	local config = HubConfig.waterfall
	local pond = config.pond
	local width = config.width
	local edgeX = HubConfig.spine.x[2]
	local lipX = edgeX + 1.5 -- the grass lip's outer edge: the falls start just past it
	disc(folder, pond + Vector3.new(0, 0.1, 0), 11.6, 0.3, COLORS.curb, Enum.Material.Slate)
	local pool = disc(folder, pond + Vector3.new(0, 0.14, 0), 10, 0.3, COLORS.water, Enum.Material.Glass)
	pool.Transparency = 0.15
	local streamLength = lipX + 0.4 - pond.X
	local stream = part(folder, Vector3.new(streamLength, 0.3, width), CFrame.new(at(Vector3.new(pond.X + streamLength / 2, -0.02, pond.Z))), COLORS.water, Enum.Material.Glass)
	stream.Transparency = 0.15
	for _, side in { -1, 1 } do
		local bankStart = pond.X + 4.5
		part(folder, Vector3.new(edgeX - bankStart, 0.6, 0.8), CFrame.new(at(Vector3.new((bankStart + edgeX) / 2, 0.3, pond.Z + side * (width / 2 + 0.4)))), COLORS.curb, Enum.Material.Slate)
	end
	local foam = part(folder, Vector3.new(1.4, 0.7, width + 0.4), CFrame.new(at(Vector3.new(lipX + 0.5, 0, pond.Z))), Color3.fromRGB(240, 248, 255), Enum.Material.Neon)
	foam.Transparency = 0.3
	ghost(foam)
	emitter(foam, {
		Color = ColorSequence.new(Color3.new(1, 1, 1)),
		Size = NumberSequence.new(0.6, 1.4),
		Transparency = NumberSequence.new(0.3, 1),
		Rate = 25,
		Lifetime = NumberRange.new(0.6, 1),
		Speed = NumberRange.new(2, 4),
		SpreadAngle = Vector2.new(40, 40),
		EmissionDirection = Enum.NormalId.Top,
		Acceleration = Vector3.new(4, -12, 0),
	})

	-- Three sheets, back to front: a deep one, the main one and pale streaks.
	local top = 0.3
	local sheets = {
		{ 0.9, width + 1, COLORS.water:Lerp(Color3.new(0, 0, 0), 0.2), Enum.Material.Glass, 0.3 },
		{ 1.4, width, COLORS.water, Enum.Material.Glass, 0.35 },
		{ 1.9, width - 2, Color3.fromRGB(225, 240, 255), Enum.Material.Neon, 0.75 },
	}
	for index, sheet in sheets do
		local piece = part(
			folder,
			Vector3.new(0.4, config.drop, sheet[2]),
			CFrame.new(at(Vector3.new(lipX + sheet[1], top - config.drop / 2, pond.Z))),
			sheet[3],
			sheet[4]
		)
		piece.Transparency = sheet[5]
		ghost(piece)
		if index == 2 then
			piece:SetAttribute("Waterfall", true) -- HubAudio plays the falls' sound here
			emitter(piece, {
				Color = ColorSequence.new(Color3.fromRGB(235, 245, 255)),
				Size = NumberSequence.new(1.2, 2.6),
				Transparency = NumberSequence.new(0.4, 1),
				Rate = 35,
				Lifetime = NumberRange.new(1.5, 2.2),
				Speed = NumberRange.new(4, 8),
				EmissionDirection = Enum.NormalId.Right,
				Acceleration = Vector3.new(0, -20, 0),
			})
		end
	end
	local mist = ghost(part(folder, Vector3.new(12, 1, 12), CFrame.new(at(Vector3.new(lipX + 2, HubConfig.clouds.seaHeight + 1, pond.Z))), COLORS.cloud))
	mist.Transparency = 1
	emitter(mist, {
		Color = ColorSequence.new(Color3.new(1, 1, 1)),
		Size = NumberSequence.new(5, 12),
		Transparency = NumberSequence.new(0.45, 1),
		Rate = 8,
		Lifetime = NumberRange.new(3, 5),
		Speed = NumberRange.new(1, 3),
		SpreadAngle = Vector2.new(60, 60),
		EmissionDirection = Enum.NormalId.Top,
	})
end

-- The signpost at the plaza: a post with an arrow board per destination, each board pointing its
-- way. The arrow on each face points the right way for someone reading that face.
local function signpost(folder: Instance)
	local config = HubConfig.signpost
	local position = config.position
	part(folder, Vector3.new(8, 0.6, 0.6), CFrame.new(at(position, 4)) * UPRIGHT, COLORS.wood, Enum.Material.Wood, Enum.PartType.Cylinder)
	part(folder, Vector3.one * 0.9, CFrame.new(at(position, 8.2)), COLORS.gold, Enum.Material.Metal, Enum.PartType.Ball)
	for index, sign in config.signs do
		local flat = Vector3.new(sign.toward.X - position.X, 0, sign.toward.Z - position.Z)
		local direction = if flat.Magnitude > 0 then flat.Unit else Vector3.xAxis
		local center = at(position + direction * 2.7, 7.2 - index * 1.15)
		local board = part(folder, Vector3.new(5, 0.95, 0.25), CFrame.fromMatrix(center, direction, Vector3.yAxis), COLORS.avenue, Enum.Material.Wood)
		-- The board's +X points the way: on its front face that is the reader's left.
		local front = label(surface(board, Enum.NormalId.Front, 40), "◀  " .. sign.text, 0.1, 0.8, COLORS.dark, Enum.Font.GothamBlack)
		local back = label(surface(board, Enum.NormalId.Back, 40), sign.text .. "  ▶", 0.1, 0.8, COLORS.dark, Enum.Font.GothamBlack)
		front.TextStrokeTransparency = 1
		back.TextStrokeTransparency = 1
	end
end

-- Breaks up the big floors: grass beds with a low hedge beside the gallery, round grass beds in
-- the plaza, stone planters with hedges on the terrace, a terracotta band inside the terrace's
-- edge and a tile diamond around the spawn.
local function gardens(folder: Instance)
	for _, bed in HubConfig.beds do
		slab(folder, bed.x, bed.z, 0.25, 0.5, COLORS.grass, Enum.Material.Grass)
		slab(folder, { bed.hedge - 0.7, bed.hedge + 0.7 }, { bed.z[1] + 0.5, bed.z[2] - 0.5 }, 1.6, 1.4, COLORS.hedge, Enum.Material.Grass)
	end
	for _, center in HubConfig.plazaBeds do
		local radius = HubConfig.plazaBedRadius
		disc(folder, center + Vector3.new(0, 0.12, 0), radius * 2 + 1.2, 0.3, COLORS.tile, Enum.Material.Brick)
		disc(folder, center + Vector3.new(0, 0.16, 0), radius * 2, 0.3, COLORS.grass, Enum.Material.Grass)
	end
	for _, position in HubConfig.planters do
		part(folder, Vector3.new(6, 1.2, 2.5), CFrame.new(at(position, 0.6)), COLORS.curb, Enum.Material.Slate)
		part(folder, Vector3.new(5.4, 1, 1.9), CFrame.new(at(position, 1.7)), COLORS.hedge, Enum.Material.Grass)
	end

	local terrace = HubConfig.terrace
	local inset = HubConfig.terraceBorder + 1
	local top = terrace.height + 0.05
	local x1, x2 = terrace.x[1] + inset, terrace.x[2] - inset
	local z1, z2 = terrace.z[1] + inset, terrace.z[2] - inset
	slab(folder, { x1 - 0.6, x2 + 0.6 }, { z1 - 0.6, z1 + 0.6 }, top, 0.3, COLORS.tile, Enum.Material.Brick)
	slab(folder, { x1 - 0.6, x2 + 0.6 }, { z2 - 0.6, z2 + 0.6 }, top, 0.3, COLORS.tile, Enum.Material.Brick)
	slab(folder, { x1 - 0.6, x1 + 0.6 }, { z1, z2 }, top, 0.3, COLORS.tile, Enum.Material.Brick)
	slab(folder, { x2 - 0.6, x2 + 0.6 }, { z1, z2 }, top, 0.3, COLORS.tile, Enum.Material.Brick)
	local spawn = HubConfig.spawn
	local turn = CFrame.Angles(0, math.rad(45), 0)
	part(folder, Vector3.new(18, 0.3, 18), CFrame.new(at(spawn, 0.05 - 0.15)) * turn, COLORS.tile, Enum.Material.Brick)
	part(folder, Vector3.new(15, 0.3, 15), CFrame.new(at(spawn, 0.07 - 0.15)) * turn, COLORS.avenue, Enum.Material.Pavement)
end

-- The invisible box around everything. Fully transparent, so the camera ignores it.
local function boundary(folder: Instance)
	local bounds = HubConfig.bounds
	local barrier = Instance.new("Folder")
	barrier.Name = "Barrier"
	local bottom = HubConfig.fallHeight - 30
	local height = bounds.top - bottom
	local midY = (bounds.top + bottom) / 2
	local spanX, spanZ = bounds.x[2] - bounds.x[1], bounds.z[2] - bounds.z[1]
	local midX, midZ = (bounds.x[1] + bounds.x[2]) / 2, (bounds.z[1] + bounds.z[2]) / 2
	local walls = {
		{ Vector3.new(2, height, spanZ + 4), Vector3.new(bounds.x[1] - 1, midY, midZ) },
		{ Vector3.new(2, height, spanZ + 4), Vector3.new(bounds.x[2] + 1, midY, midZ) },
		{ Vector3.new(spanX + 4, height, 2), Vector3.new(midX, midY, bounds.z[1] - 1) },
		{ Vector3.new(spanX + 4, height, 2), Vector3.new(midX, midY, bounds.z[2] + 1) },
		{ Vector3.new(spanX + 4, 2, spanZ + 4), Vector3.new(midX, bounds.top + 1, midZ) },
	}
	for _, wall in walls do
		local instance = part(barrier, wall[1], CFrame.new(at(wall[2])), COLORS.curb)
		instance.Transparency = 1
		instance.CastShadow = false
		instance.CanTouch = false
	end
	barrier.Parent = folder
end

-- Builds the whole hub into workspace.Hub. Returns the two pads and the leaderboard boards.
function HubBuilder.build(): ({ play: Pad, practice: Pad }, { [string]: Board })
	partCount = 0
	local folder = Instance.new("Folder")
	folder.Name = "Hub"
	mainIsland(folder)
	edges(folder)
	gardens(folder)
	signpost(folder)
	arrival(folder)
	plaza(folder)
	gallery(folder)
	local play = arenaGate(folder)
	local practice = trainingYard(folder)
	shrine(folder)
	local boards = hallOfFame(folder)
	outerIslands(folder)
	waterfall(folder)
	for _, position in HubConfig.lanterns do
		lantern(folder, position)
	end
	for _, position in HubConfig.trees do
		tree(folder, position)
	end
	boundary(folder)
	folder.Parent = workspace
	print(string.format("[HubBuilder] Hub built: %d parts", partCount))
	return { play = play, practice = practice }, boards
end

-- Fills a leaderboard with rows ({ name, value }), best first, up to HubConfig.hall.rowsShown; with
-- no rows the placeholder shows.
function HubBuilder.setLeaderboard(board: Board, rows: { { name: string, value: string } })
	for _, child in board.list:GetChildren() do
		if child:IsA("TextLabel") then
			child:Destroy()
		end
	end
	board.placeholder.Visible = #rows == 0
	for index = 1, math.min(#rows, HubConfig.hall.rowsShown) do
		local row = rows[index]
		local line = Instance.new("TextLabel")
		line.LayoutOrder = index
		line.BackgroundTransparency = 1
		line.Size = UDim2.fromScale(1, 0.11)
		line.Text = string.format("%d.  %s   %s", index, row.name, row.value)
		line.TextColor3 = if index == 1 then COLORS.gold else Color3.new(1, 1, 1)
		line.TextScaled = true
		line.TextXAlignment = Enum.TextXAlignment.Left
		line.Font = Enum.Font.GothamBold
		line.Parent = board.list
	end
end

-- Where players are sent back to: just above the spawn marker.
function HubBuilder.spawnPosition(): Vector3
	return at(HubConfig.spawn, 3)
end

-- True if `position` is below the hub's fall height or outside its bounds.
function HubBuilder.isOutside(position: Vector3): boolean
	local relative = position - CENTER
	local bounds = HubConfig.bounds
	return relative.Y < HubConfig.fallHeight
		or relative.X < bounds.x[1]
		or relative.X > bounds.x[2]
		or relative.Z < bounds.z[1]
		or relative.Z > bounds.z[2]
end

return HubBuilder
