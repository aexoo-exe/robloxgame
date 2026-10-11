-- The hub's client-side scenery (HubConfig):
--   * a sea of clouds under the hub that hides everything below and around it, with puffs that
--     drift slowly over it
--   * small floating islets that bob, placed away from every walkable area
--   * a statue on every roster gallery plinth (the unit's placeholder figure and character look,
--     from Figure and CharacterLook) and the item pictogram over every shrine pedestal (ItemIcon)
-- The plinths and pedestals are built by the server (HubBuilder) and carry UnitType / ItemId
-- attributes. The clouds, rocks and icons exist only while the player is in the hub
-- (HubScenery.setActive), and only animate then; statues stay put far from the arena.
-- Presentation only.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local HubConfig = require(Shared:WaitForChild("HubConfig"))

local CharacterLook = require(script.Parent.CharacterLook)
local Figure = require(script.Parent.Figure)
local ItemIcon = require(script.Parent.ItemIcon)

local HubScenery = {}

local COLORS = HubConfig.colors
local CENTER = HubConfig.center

local scenery: Folder -- clouds, rocks and item icons: parented only while in the hub
local statues: Folder
local active = false
local animation: RBXScriptConnection? = nil
local puffs: { { part: BasePart, speed: number } } = {}
local rocks: { { pieces: { { part: BasePart, offset: CFrame } }, base: CFrame, phase: number, period: number } } = {}
local random = Random.new(7)

local function decor(parent: Instance, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material?, shape: Enum.PartType?): Part
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	part.Material = material or Enum.Material.SmoothPlastic
	if shape then
		part.Shape = shape
	end
	part.Parent = parent
	return part
end

-- An ellipsoid, using a built-in sphere mesh (no uploaded asset).
local function blob(parent: Instance, size: Vector3, cframe: CFrame, color: Color3): Part
	local part = decor(parent, size, cframe, color)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = part
	return part
end

-- The cloud sea: a huge flat layer under the hub and a ring of more around it to the horizon
-- (the hub's haze hides the rest), and puffs drifting on top.
local function buildClouds()
	local config = HubConfig.clouds
	local top = CENTER.Y + config.seaHeight
	local upright = CFrame.Angles(0, 0, math.pi / 2)
	local seaSize = 2048 -- the largest a part can be
	decor(scenery, Vector3.new(4, seaSize, seaSize), CFrame.new(CENTER.X, top - 2, CENTER.Z) * upright, COLORS.cloud, Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
	for i = 0, 7 do
		local angle = math.rad(i * 45)
		local offset = Vector3.new(math.sin(angle), 0, math.cos(angle)) * 1800
		decor(
			scenery,
			Vector3.new(4, seaSize, seaSize),
			CFrame.new(CENTER + offset + Vector3.new(0, top - CENTER.Y - 6, 0)) * upright,
			COLORS.cloudShade,
			Enum.Material.SmoothPlastic,
			Enum.PartType.Cylinder
		)
	end
	for _ = 1, config.puffs do
		local angle = random:NextNumber(0, math.pi * 2)
		local distance = random:NextNumber(40, config.puffArea)
		local width = random:NextNumber(30, 80)
		local position = CENTER + Vector3.new(math.cos(angle) * distance, config.seaHeight + random:NextNumber(-1, 4), math.sin(angle) * distance)
		local part = blob(
			scenery,
			Vector3.new(width, random:NextNumber(10, 22), width * random:NextNumber(0.5, 0.9)),
			CFrame.new(position),
			if random:NextNumber() < 0.5 then COLORS.cloud else COLORS.cloudShade
		)
		table.insert(puffs, { part = part, speed = config.driftSpeed * random:NextNumber(0.6, 1.4) })
	end
end

-- Small floating islets, bobbing slowly: a grass top over light rock tapering away in two layers,
-- like the outer islands. Each config position is the center of its grass top.
local function buildRocks()
	local upright = CFrame.Angles(0, 0, math.pi / 2)
	for _, offset in HubConfig.floatingRocks do
		local width = random:NextNumber(8, 16)
		local base = CFrame.new(CENTER + offset) * CFrame.Angles(0, random:NextNumber(0, math.pi * 2), 0)
		local pieces = {}
		local function piece(part: BasePart)
			table.insert(pieces, { part = part, offset = base:ToObjectSpace(part.CFrame) })
		end
		piece(decor(scenery, Vector3.new(1.2, width, width), base * CFrame.new(0, -0.6, 0) * upright, COLORS.grass, Enum.Material.Grass, Enum.PartType.Cylinder))
		local layers = { { 0.92, 2.5 }, { 0.55, 3 } }
		local depth = 1.2
		for _, layer in layers do
			local shift = CFrame.new(random:NextNumber(-0.8, 0.8), -depth - layer[2] / 2, random:NextNumber(-0.8, 0.8))
			piece(decor(scenery, Vector3.new(layer[2], width * layer[1], width * layer[1]), base * shift * upright, COLORS.rockLight, Enum.Material.Rock, Enum.PartType.Cylinder))
			depth += layer[2]
		end
		table.insert(rocks, {
			pieces = pieces,
			base = base,
			phase = random:NextNumber(0, math.pi * 2),
			period = random:NextNumber(6, 10),
		})
	end
end

-- A statue on a plinth: the unit's figure at rest, facing the way the plinth faces.
local function addStatue(plinth: Instance)
	local unitType = plinth:GetAttribute("UnitType")
	if not plinth:IsA("BasePart") or type(unitType) ~= "string" then
		return
	end
	local look = CharacterLook.of(unitType)
	local height = HubConfig.gallery.statueHeight * look.scale
	local root = plinth.CFrame * CFrame.new(0, plinth.Size.Y / 2, 0)
	local hitbox = Instance.new("Part")
	hitbox.Name = unitType
	hitbox.Anchored = true
	hitbox.CanCollide = false
	hitbox.CanQuery = false
	hitbox.CanTouch = false
	hitbox.Transparency = 1
	hitbox.Size = Vector3.new(2, height, 2)
	hitbox.Parent = statues
	local figure = Figure.new(look.figure, look.color, height, hitbox)
	Figure.place(figure, root * CFrame.new(0, height / 2, 0), root, {
		bob = 0,
		lean = 0,
		fall = 0,
		leftArm = figure.restArms[1],
		rightArm = figure.restArms[2],
		leftLeg = 0,
		rightLeg = 0,
		stride = 0,
	})
end

-- The item's pictogram floating over its pedestal.
local function addItemIcon(pedestal: Instance)
	local itemId = pedestal:GetAttribute("ItemId")
	if not pedestal:IsA("BasePart") or type(itemId) ~= "string" then
		return
	end
	local billboard = Instance.new("BillboardGui")
	billboard.Adornee = pedestal
	billboard.Size = UDim2.fromScale(2.2, 2.2)
	billboard.StudsOffset = Vector3.new(0, pedestal.Size.Y / 2 + 1.6, 0)
	billboard.LightInfluence = 0
	billboard.MaxDistance = 90
	local icon = ItemIcon.new(itemId, 64, billboard)
	icon.Size = UDim2.fromScale(1, 1)
	billboard.Parent = scenery
end

-- Calls `add` for every child of the hub folder `name`, now and as they arrive.
local function eachChild(name: string, add: (Instance) -> ())
	task.spawn(function()
		local hub = workspace:WaitForChild("Hub")
		local folder = hub:WaitForChild(name)
		folder.ChildAdded:Connect(add)
		for _, child in folder:GetChildren() do
			add(child)
		end
	end)
end

local function animate(dt: number)
	local now = os.clock()
	local area = HubConfig.clouds.puffArea
	for _, puff in puffs do
		local position = puff.part.Position + Vector3.new(puff.speed * dt, 0, 0)
		if position.X - CENTER.X > area then
			position -= Vector3.new(area * 2, 0, 0)
		end
		puff.part.CFrame = CFrame.new(position)
	end
	for _, rock in rocks do
		local lift = math.sin(now * 2 * math.pi / rock.period + rock.phase) * 1.4
		local base = rock.base + Vector3.new(0, lift, 0)
		for _, piece in rock.pieces do
			piece.part.CFrame = base * piece.offset
		end
	end
end

function HubScenery.setActive(value: boolean)
	if value == active or not scenery then
		return
	end
	active = value
	scenery.Parent = if value then workspace else nil
	if value then
		animation = RunService.Heartbeat:Connect(animate)
	elseif animation then
		animation:Disconnect()
		animation = nil
	end
end

function HubScenery.start()
	scenery = Instance.new("Folder")
	scenery.Name = "HubScenery"
	statues = Instance.new("Folder")
	statues.Name = "HubStatues"
	statues.Parent = workspace
	buildClouds()
	buildRocks()
	eachChild("Gallery", addStatue)
	eachChild("Shrine", addItemIcon)
end

return HubScenery
