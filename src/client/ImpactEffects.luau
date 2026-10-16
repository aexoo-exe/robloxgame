-- Pooled impact effects for combat: particle bursts (sparks, puffs, rising motes, flames, smoke,
-- glows, shockwaves, explosions, slashes), flat ground rings and flash balls, generic animated
-- shapes, the full-screen impact frame, plus the camera shake. Presentation only. Numbers come from
-- AnimationConfig; textures from VfxConfig (through Vfx).
--
-- Textures: a particle kind draws with its usage's picked texture (VfxConfig.uses; flipbooks play),
-- a flash ball becomes a flash particle, a ground ring a textured plane, and a shape given a texture
-- (ImpactEffects.shape `texture`) is drawn as a textured plane, billboard or beam over the same
-- size, place, color and transparency its step sets, with its neon part hidden. Without a texture
-- (none picked, not loaded yet, failed to load, or the quality level's cap reached) every effect
-- keeps its plain neon or built-in look.
--
-- Performance: every effect is pooled. Particles come from a few host parts per kind and texture,
-- reused in turn (particles live in world space, so moving a host does not move what it already
-- emitted); rings and balls come from fixed pools, and a burst that finds its pool busy takes the
-- oldest. Particles alive at once are capped per quality level (bursts shrink to fit), and the
-- quality level scales every particle count, turns rings, trails and charge sparkles on or off and
-- caps textured shapes (VfxConfig.quality). A shape's texture objects (SurfaceGuis, a
-- BillboardGui, a Beam) are made once per pooled part and kept with it.
-- Rings, balls and shapes are animated on the effects' clock (ImpactEffects.setClock; combat
-- playback sets its fight-time clock, so they follow the playback speed); particles run in real
-- time.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AnimationConfig = require(Shared:WaitForChild("AnimationConfig"))
local VfxConfig = require(Shared:WaitForChild("VfxConfig"))

local Vfx = require(script.Parent.Vfx)

local ImpactEffects = {}

local POOLS = AnimationConfig.pools
local FLAT = CFrame.Angles(0, 0, math.pi / 2) -- a cylinder's axis (X) upright: a flat disc
local RING_THICKNESS = 0.08
local WHITE = Color3.new(1, 1, 1)

-- Particle kinds: the built-in texture (kept when no picked texture fits), the physics that do not
-- change per burst, and `usage`, the VfxConfig.uses entry that picks its texture.
local KINDS = {
	spark = {
		texture = "rbxasset://textures/particles/sparkles_main.dds",
		lightEmission = 1,
		drag = 6,
		acceleration = Vector3.new(0, -12, 0),
		usage = "sparks",
	},
	puff = {
		texture = "rbxasset://textures/particles/smoke_main.dds",
		lightEmission = 0.15,
		drag = 3,
		acceleration = Vector3.new(0, 1.5, 0),
		usage = "smoke",
	},
	mote = {
		texture = "rbxasset://textures/particles/sparkles_main.dds",
		lightEmission = 1,
		drag = 1,
		acceleration = Vector3.new(0, 3, 0),
	},
	-- Ability elements (AbilityFxConfig.elements).
	flame = {
		texture = "rbxasset://textures/particles/fire_main.dds",
		lightEmission = 0.9,
		drag = 2,
		acceleration = Vector3.new(0, 7, 0),
		growth = 0.4,
		usage = "fire",
	},
	ember = {
		texture = "rbxasset://textures/particles/fire_sparks_main.dds",
		lightEmission = 1,
		drag = 2,
		acceleration = Vector3.new(0, 4, 0),
		usage = "sparks",
	},
	smoke = {
		texture = "rbxasset://textures/particles/smoke_main.dds",
		lightEmission = 0,
		drag = 3,
		acceleration = Vector3.new(0, 1, 0),
		growth = 1.8,
		spin = true,
		usage = "smoke",
	},
	bubble = {
		texture = "rbxasset://textures/particles/forcefield_glow_main.dds",
		lightEmission = 0.6,
		drag = 2,
		acceleration = Vector3.new(0, 3.5, 0),
		growth = 1.2,
	},
	glow = {
		texture = "rbxasset://textures/particles/explosion01_core_main.dds",
		lightEmission = 1,
		drag = 4,
		acceleration = Vector3.zero,
		growth = 1.5,
		usage = "glow",
	},
	shock = {
		texture = "rbxasset://textures/particles/explosion01_shockwave_main.dds",
		lightEmission = 0.8,
		drag = 0,
		acceleration = Vector3.zero,
		growth = 4,
		usage = "shock",
	},
	-- A blast (explode strikes): an explosion flipbook when one is picked.
	explosion = {
		texture = "rbxasset://textures/particles/explosion01_core_main.dds",
		lightEmission = 1,
		drag = 3,
		acceleration = Vector3.zero,
		growth = 1.8,
		usage = "explosion",
	},
	-- A slash flash (a flipbook slash drawn as a particle).
	slash = {
		texture = "rbxasset://textures/particles/sparkles_main.dds",
		lightEmission = 1,
		drag = 6,
		acceleration = Vector3.zero,
		growth = 1.3,
		usage = "slashBurst",
	},
	-- The flash particle that stands in for a flash ball (ImpactEffects.ball); only with a texture.
	flash = {
		texture = "rbxasset://textures/particles/explosion01_core_main.dds",
		lightEmission = 1,
		drag = 0,
		acceleration = Vector3.zero,
	},
}
-- Kinds whose particles grow instead of shrinking (end size = start x growth); spin: they rotate.
KINDS.puff.growth = 1.6
KINDS.puff.spin = true

type Animated = {
	part: Part,
	kind: string, -- "ring" or "ball"
	startsAt: number,
	duration: number,
	from: number, -- diameter at the start
	to: number,
	transparency: number, -- at the start; fades to 1
	center: CFrame,
}

local folder: Folder? = nil
local clock: () -> number = os.clock
local qualityName = "high"
local level = AnimationConfig.qualityLevels.high
local vfxLevel = VfxConfig.quality.high

local hosts: { [string]: { ParticleEmitter } } = {}
local nextHost: { [string]: number } = {}
local live: { { expires: number, count: number } } = {} -- particle batches, real time
local liveCount = 0

local free: { [string]: { Part } } = { ring = {}, ball = {} }
local made: { [string]: number } = { ring = 0, ball = 0 }
local active: { Animated } = {}

-- Generic animated shapes (ImpactEffects.shape): pooled parts by part shape, each driven by its
-- own step function, optionally drawn with a texture.
type Shape = {
	part: BasePart,
	shape: string,
	startsAt: number,
	duration: number,
	step: (BasePart, number) -> (),
	texture: Vfx.Texture?,
	shown: number, -- the transparency its step last set (the neon part itself is hidden)
	spin: number, -- a billboard's turn, degrees (varies so repeats do not look stamped)
}
local spareShapes: { [string]: { BasePart } } = {}
local madeShapes = 0
local shapes: { Shape } = {}
local skinned = 0 -- textured shapes alive

-- The texture objects of a pooled part, made on first use and kept with it.
type Skin = {
	surfaces: { SurfaceGui }?,
	labels: { ImageLabel }?,
	billboard: BillboardGui?,
	sprite: ImageLabel?,
	ends: { Attachment }?,
	beam: Beam?,
}
local skins: { [BasePart]: Skin } = {}
local FACES = {
	X = { Enum.NormalId.Right, Enum.NormalId.Left },
	Y = { Enum.NormalId.Top, Enum.NormalId.Bottom },
	Z = { Enum.NormalId.Front, Enum.NormalId.Back },
}

-- Calls waiting for their moment on the effects' clock (ImpactEffects.later).
local waiting: { { at: number, run: () -> () } } = {}

-- The full-screen impact frame (made on first use).
local frameGui: ScreenGui? = nil
local frameImage: ImageLabel? = nil
local frameUntil = 0

local trauma = 0
local traumaAt = os.clock()
local connection: RBXScriptConnection? = nil

local function getFolder(): Folder
	if not folder or not folder.Parent then
		local created = Instance.new("Folder")
		created.Name = "ImpactEffects"
		created.Parent = workspace
		folder = created
	end
	return folder :: Folder
end

local function bare(part: BasePart)
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
end

-- Sets the quality level ("low", "medium", "high" or "auto"; see AnimationConfig).
function ImpactEffects.setQuality(name: string)
	if name == "auto" then
		local touchOnly = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
		name = if touchOnly then AnimationConfig.autoTouch else AnimationConfig.autoDefault
	end
	if AnimationConfig.qualityLevels[name] then
		qualityName = name
		level = AnimationConfig.qualityLevels[name]
		vfxLevel = VfxConfig.quality[name] or VfxConfig.quality.high
	end
end
ImpactEffects.setQuality(AnimationConfig.quality)

function ImpactEffects.quality(): string
	return qualityName
end

-- Whether the current quality level shows `feature` ("rings", "trails", "charge" or "impactFrame").
function ImpactEffects.allows(feature: string): boolean
	if feature == "impactFrame" then
		return vfxLevel.impactFrame == true
	end
	return (level :: any)[feature] == true
end

-- The share of particles the current quality level emits (0-1).
function ImpactEffects.particleShare(): number
	return level.particles
end

-- Sets the time source for rings and balls (nil: os.clock).
function ImpactEffects.setClock(source: (() -> number)?)
	clock = source or os.clock
end

-- Texture objects -----------------------------------------------------------------------------------

local function skinOf(part: BasePart): Skin
	local skin = skins[part]
	if not skin then
		skin = {}
		skins[part] = skin
	end
	return skin :: Skin
end

local function hideSkin(part: BasePart)
	local skin = skins[part]
	if not skin then
		return
	end
	for _, surface in skin.surfaces or {} do
		surface.Enabled = false
	end
	if skin.billboard then
		skin.billboard.Enabled = false
	end
	if skin.beam then
		skin.beam.Enabled = false
	end
end

local function image(parent: Instance): ImageLabel
	local label = Instance.new("ImageLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.fromScale(0.5, 0.5)
	label.Parent = parent
	return label
end

-- Two unlit SurfaceGuis (the plane's two sides), one image each.
local function surfacesOf(part: BasePart, skin: Skin): ({ SurfaceGui }, { ImageLabel })
	if not skin.surfaces then
		local surfaces, labels = {}, {}
		for i = 1, 2 do
			local surface = Instance.new("SurfaceGui")
			surface.LightInfluence = 0
			surface.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
			surface.CanvasSize = Vector2.new(256, 256)
			surface.Enabled = false
			surface.Parent = part
			surfaces[i] = surface
			labels[i] = image(surface)
		end
		skin.surfaces, skin.labels = surfaces, labels
	end
	return skin.surfaces :: { SurfaceGui }, skin.labels :: { ImageLabel }
end

local function billboardOf(part: BasePart, skin: Skin): (BillboardGui, ImageLabel)
	if not skin.billboard then
		local billboard = Instance.new("BillboardGui")
		billboard.LightInfluence = 0
		billboard.Enabled = false
		billboard.Adornee = part
		billboard.Parent = part
		skin.billboard = billboard
		skin.sprite = image(billboard)
	end
	return skin.billboard :: BillboardGui, skin.sprite :: ImageLabel
end

local function beamOf(part: BasePart, skin: Skin): (Beam, { Attachment })
	if not skin.beam then
		local ends = {}
		for i = 1, 2 do
			local attachment = Instance.new("Attachment")
			attachment.Parent = part
			ends[i] = attachment
		end
		local beam = Instance.new("Beam")
		beam.Attachment0 = ends[1]
		beam.Attachment1 = ends[2]
		beam.FaceCamera = true
		beam.Segments = 1
		beam.LightInfluence = 0
		beam.TextureMode = Enum.TextureMode.Stretch
		beam.TextureLength = 1
		beam.Enabled = false
		beam.Parent = part
		skin.beam, skin.ends = beam, ends
	end
	return skin.beam :: Beam, skin.ends :: { Attachment }
end

-- Draws a textured shape over what its step just set (size, place, color, `shown` transparency).
local function drawSkin(entry: Shape)
	local part = entry.part
	local texture = entry.texture :: Vfx.Texture
	local skin = skinOf(part)
	local color = if texture.tint then part.Color else WHITE
	local size = part.Size
	local seen = entry.shown
	if texture.mode == "plane" then
		local axis = if size.X <= size.Y and size.X <= size.Z then "X" elseif size.Y <= size.Z then "Y" else "Z"
		local surfaces, labels = surfacesOf(part, skin)
		for i, surface in surfaces do
			surface.Face = FACES[axis][i]
			surface.Brightness = texture.brightness
			surface.Enabled = seen < 1
			local label = labels[i]
			label.Image = texture.image
			label.ImageColor3 = color
			label.ImageTransparency = seen
		end
	elseif texture.mode == "billboard" then
		local billboard, sprite = billboardOf(part, skin)
		local across = math.max(size.X, size.Y, size.Z)
		billboard.Size = UDim2.fromScale(across, across)
		billboard.Brightness = texture.brightness
		billboard.Enabled = seen < 1
		sprite.Image = texture.image
		sprite.ImageColor3 = color
		sprite.ImageTransparency = seen
		sprite.Rotation = if texture.upright then 0 else entry.spin
	elseif texture.mode == "beam" then
		local beam, ends = beamOf(part, skin)
		-- Along the bar the neon part draws: a cylinder's axis (X), a block's length (Z, as bars are
		-- built with CFrame.lookAt); as wide as the other two sides.
		local length, width, along
		if entry.shape == "Cylinder" then
			length, width, along = size.X, (size.Y + size.Z) / 2, Vector3.xAxis
		else
			length, width, along = size.Z, (size.X + size.Y) / 2, Vector3.zAxis
		end
		ends[1].Position = along * (length / 2)
		ends[2].Position = -along * (length / 2)
		beam.Texture = texture.image
		beam.TextureSpeed = texture.speed
		beam.LightEmission = if texture.blend == "additive" then 1 else 0
		beam.Width0 = width * texture.width
		beam.Width1 = width * texture.width
		beam.Color = ColorSequence.new(color)
		beam.Transparency = NumberSequence.new(seen)
		beam.Enabled = seen < 1
	end
end

-- Puts a shape's part back in its pool.
local function retire(entry: Shape)
	local part = entry.part
	part.Transparency = 1
	part.Parent = nil
	if entry.texture then
		hideSkin(part)
		skinned -= 1
	end
	table.insert(spareShapes[entry.shape], part)
end

local function hideFrame()
	if frameGui then
		frameGui.Enabled = false
	end
end

local function update()
	local now = clock()
	for i = #active, 1, -1 do
		local effect = active[i]
		local progress = (now - effect.startsAt) / effect.duration
		if progress >= 1 then
			effect.part.Transparency = 1
			effect.part.Parent = nil
			table.insert(free[effect.kind], effect.part)
			table.remove(active, i)
		elseif progress >= 0 then
			local eased = 1 - (1 - progress) * (1 - progress)
			local diameter = effect.from + (effect.to - effect.from) * eased
			local part = effect.part
			part.Transparency = effect.transparency + (1 - effect.transparency) * progress
			if effect.kind == "ring" then
				part.Size = Vector3.new(RING_THICKNESS, diameter, diameter)
			else
				part.Size = Vector3.one * diameter
			end
			part.CFrame = effect.center
		end
	end
	for i = #shapes, 1, -1 do
		local shape = shapes[i]
		local progress = (now - shape.startsAt) / shape.duration
		if progress >= 1 then
			retire(shape)
			table.remove(shapes, i)
		elseif progress >= 0 then
			if shape.texture then
				-- The step sets the look on the (hidden) neon part; the texture draws it.
				local part = shape.part
				part.Transparency = shape.shown
				shape.step(part, progress)
				shape.shown = part.Transparency
				part.Transparency = 1
				drawSkin(shape)
			else
				shape.step(shape.part, progress)
			end
		end
	end
	for i = #waiting, 1, -1 do
		local call = waiting[i]
		if now >= call.at then
			table.remove(waiting, i)
			local ok, problem = pcall(call.run)
			if not ok then
				warn("[ImpactEffects] " .. tostring(problem))
			end
		end
	end
	if frameGui and frameGui.Enabled and os.clock() >= frameUntil then
		hideFrame()
	end
end

local function ensureRunning()
	if not connection then
		connection = RunService.RenderStepped:Connect(update)
	end
end

-- Particles -------------------------------------------------------------------------------------------

-- A pooled host emitter of `kind` drawing `texture` (nil: the kind's built-in texture), taken in turn.
local function host(kind: string, texture: Vfx.Texture?): ParticleEmitter
	local key = if texture then kind .. "|" .. texture.image else kind
	local list = hosts[key]
	if not list then
		list = {}
		hosts[key] = list
		nextHost[key] = 0
	end
	local index = nextHost[key] % POOLS.emitters + 1
	nextHost[key] = index
	local emitter = list[index]
	if not emitter or not emitter.Parent or not emitter.Parent.Parent then
		local part = Instance.new("Part")
		part.Name = kind
		bare(part)
		part.Transparency = 1
		part.Size = Vector3.one * 0.2
		part.Parent = getFolder()
		local config = KINDS[kind]
		local created = Instance.new("ParticleEmitter")
		created.Texture = if texture then texture.image else config.texture
		-- A black-background texture only reads when added as light.
		created.LightEmission = if texture and texture.blend == "additive" then 1 else config.lightEmission
		created.LightInfluence = 0
		created.Drag = config.drag
		created.Acceleration = config.acceleration
		created.EmissionDirection = Enum.NormalId.Front
		created.Rate = 0
		created.Enabled = false
		created.ZOffset = 1
		local flipbook = texture and texture.flipbook
		if flipbook then
			created.FlipbookLayout = (Enum.ParticleFlipbookLayout :: any)["Grid" .. flipbook.layout]
			created.FlipbookMode = (Enum.ParticleFlipbookMode :: any)[flipbook.mode]
				or Enum.ParticleFlipbookMode.OneShot
			if flipbook.fps then
				created.FlipbookFramerate = NumberRange.new(flipbook.fps)
			end
			created.FlipbookStartRandom = flipbook.mode == "Loop"
		end
		created.Parent = part
		list[index] = created
		emitter = created
	end
	return emitter
end

-- How many of `wanted` particles may be emitted now (quality share and the live cap).
local function budget(wanted: number, lifetime: number): number
	local real = os.clock()
	for i = #live, 1, -1 do
		if live[i].expires <= real then
			liveCount -= live[i].count
			table.remove(live, i)
		end
	end
	local count = math.floor(wanted * level.particles + 0.5)
	count = math.min(count, level.maxParticles - liveCount)
	if count <= 0 then
		return 0
	end
	liveCount += count
	table.insert(live, { expires = real + lifetime, count = count })
	return count
end

export type Burst = {
	color: Color3,
	count: number,
	size: number, -- studs, shrinking to nothing
	speed: { number }, -- { min, max }
	lifetime: { number }, -- { min, max }
	spread: number?, -- degrees around `direction` (default all around)
	transparency: number?,
	color2: Color3?, -- the color particles fade to (default `color`)
}

-- Emits a burst of `kind` (KINDS: spark, puff, mote, flame, ember, smoke, bubble, glow, shock,
-- explosion, slash) at `position`, aimed along `direction` (nil: all around). Sparks shrink away;
-- puffs, smoke, bubbles, glows, shockwaves and explosions grow (KINDS `growth`). The kind's picked
-- texture is used when there is one (VfxConfig.uses), in the effect's color unless the texture
-- keeps its own.
function ImpactEffects.burst(kind: string, position: Vector3, direction: Vector3?, burst: Burst)
	local config = KINDS[kind]
	if not config then
		return
	end
	local count = budget(burst.count, burst.lifetime[2])
	if count <= 0 then
		return
	end
	local texture = if config.usage then Vfx.texture(config.usage, burst.color, "particle") else nil
	if texture and texture.mode ~= "particle" then
		texture = nil
	end
	local emitter = host(kind, texture)
	local part = emitter.Parent :: BasePart
	local aim = if direction and direction.Magnitude > 1e-3 then direction.Unit else Vector3.yAxis
	part.CFrame = CFrame.lookAt(position, position + aim)
	if texture and not texture.tint then
		emitter.Color = ColorSequence.new(WHITE)
	else
		emitter.Color = ColorSequence.new(burst.color, burst.color2 or burst.color)
	end
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, burst.size),
		NumberSequenceKeypoint.new(1, burst.size * (config.growth or 0)),
	})
	local transparency = burst.transparency or 0
	emitter.Transparency = NumberSequence.new(transparency, 1)
	emitter.Speed = NumberRange.new(burst.speed[1], burst.speed[2])
	emitter.Lifetime = NumberRange.new(burst.lifetime[1], burst.lifetime[2])
	local spread = if direction then burst.spread or 180 else 180
	emitter.SpreadAngle = Vector2.new(spread, spread)
	-- Picked textures turn at random so repeats do not look stamped (flames stay upright).
	local turns = config.spin or (texture ~= nil and kind ~= "flame")
	emitter.RotSpeed = if config.spin then NumberRange.new(-90, 90) else NumberRange.new(0, 0)
	emitter.Rotation = if turns then NumberRange.new(0, 360) else NumberRange.new(0, 0)
	emitter:Emit(count)
end

-- Runs `fn` `delay` seconds from now on the effects' clock (at once when `delay` is 0 or nil): a
-- burst that belongs to a delayed beat. ImpactEffects.clear drops what is still waiting.
function ImpactEffects.later(delay: number?, fn: () -> ())
	if not delay or delay <= 0 then
		fn()
		return
	end
	table.insert(waiting, { at = clock() + delay, run = fn })
	ensureRunning()
end

-- Shapes ------------------------------------------------------------------------------------------------

-- A pooled part of `shape` ("Block", "Ball" or "Cylinder"; Neon, or `material`) shown for
-- `duration` (the effects' clock) from `delay` on, and driven each frame by `step(part, progress)`
-- (progress 0-1), which sets its size, place, color and transparency. With `texture` (Vfx.texture)
-- it is drawn as that texture instead (a plane on its thinnest side, a billboard as wide as it, or a
-- beam along a cylinder's axis or a block's Z length), within the quality level's cap of textured
-- shapes; a plane should be a "Block" (a SurfaceGui covers a block's face). Nothing at
-- quality levels without rings. At most AnimationConfig.pools.shapes at once: past that the oldest
-- is reused.
function ImpactEffects.shape(
	shape: string,
	color: Color3,
	duration: number,
	step: (BasePart, number) -> (),
	delay: number?,
	material: Enum.Material?,
	texture: Vfx.Texture?
)
	if not level.rings then
		return
	end
	local list = spareShapes[shape]
	if not list then
		list = {}
		spareShapes[shape] = list
	end
	local part = table.remove(list)
	if not part then
		if madeShapes < POOLS.shapes then
			madeShapes += 1
			local created = Instance.new("Part")
			created.Name = shape
			bare(created)
			created.Shape = (Enum.PartType :: any)[shape]
			part = created
		else
			-- The pool is full: reuse the oldest shape of this kind, if any.
			for i, running in shapes do
				if running.shape == shape then
					table.remove(shapes, i)
					part = running.part
					if running.texture then
						hideSkin(running.part)
						skinned -= 1
					end
					break
				end
			end
			if not part then
				return
			end
		end
	end
	if texture and skinned >= vfxLevel.maxSkinned then
		texture = nil -- the quality level's cap: this one stays neon
	end
	if texture then
		skinned += 1
	end
	local p = part :: BasePart
	ensureRunning()
	p.Color = color
	p.Material = material or Enum.Material.Neon
	p.Transparency = 1
	p.Parent = getFolder()
	table.insert(shapes, {
		part = p,
		shape = shape,
		startsAt = clock() + (delay or 0),
		duration = duration,
		step = step,
		texture = texture,
		shown = 1,
		spin = math.random() * 360,
	})
end

-- Rings and flash balls -----------------------------------------------------------------------------

local function pooled(kind: string): Part?
	local list = free[kind]
	local part = table.remove(list)
	if part then
		return part
	end
	if made[kind] < (if kind == "ring" then POOLS.rings else POOLS.balls) then
		made[kind] += 1
		local created = Instance.new("Part")
		created.Name = kind
		bare(created)
		created.Material = Enum.Material.Neon
		created.Shape = if kind == "ring" then Enum.PartType.Cylinder else Enum.PartType.Ball
		return created
	end
	-- The pool is busy: take the oldest of this kind.
	for i, effect in active do
		if effect.kind == kind then
			table.remove(active, i)
			return effect.part
		end
	end
	return nil
end

local function animate(
	kind: string,
	center: CFrame,
	color: Color3,
	from: number,
	to: number,
	duration: number,
	transparency: number
)
	if not level.rings then
		return
	end
	local part = pooled(kind)
	if not part then
		return
	end
	ensureRunning()
	part.Color = color
	part.Transparency = 1
	part.CFrame = center
	part.Parent = getFolder()
	table.insert(active, {
		part = part,
		kind = kind,
		startsAt = clock(),
		duration = duration,
		from = from,
		to = to,
		transparency = transparency,
		center = center,
	})
end

-- A flat ring on the ground at `position` growing to `diameter` studs and fading: the picked ring
-- texture (VfxConfig.uses `ring`) on a plane, or a neon disc.
function ImpactEffects.ring(position: Vector3, color: Color3, diameter: number, duration: number?)
	local seconds = duration or 0.35
	local texture = Vfx.texture("ring", color, "plane")
	if texture and level.rings then
		local center = CFrame.new(position + Vector3.new(0, 0.1, 0)) * FLAT
		ImpactEffects.shape("Block", color, seconds, function(part, progress)
			local eased = 1 - (1 - progress) * (1 - progress)
			local grown = diameter * (0.3 + 0.7 * eased)
			part.Size = Vector3.new(0.05, grown, grown)
			part.CFrame = center
			part.Transparency = 0.25 + 0.75 * progress
		end, nil, nil, texture)
		return
	end
	animate(
		"ring",
		CFrame.new(position + Vector3.new(0, 0.1, 0)) * FLAT,
		color,
		diameter * 0.3,
		diameter,
		seconds,
		0.25
	)
end

-- A flash at `position` swelling to `diameter` studs and fading: the core of a hit or burst. With
-- a picked flash texture (VfxConfig.uses `flash`, or `usage` such as "critFlash") it is one flash
-- particle (VfxConfig.flash) around a small neon core; otherwise a glowing neon ball.
-- `textureColor` (default `color`) picks and tints the texture; the neon ball keeps `color`.
function ImpactEffects.ball(
	position: Vector3,
	color: Color3,
	diameter: number,
	duration: number?,
	usage: string?,
	textureColor: Color3?
)
	local seconds = duration or 0.14
	if not level.rings then
		return
	end
	local tint = textureColor or color
	local texture = Vfx.texture(usage or "flash", tint, "particle")
	if texture and texture.mode == "particle" then
		local config = VfxConfig.flash
		local life = seconds * config.life
		if budget(1, life) > 0 then
			local emitter = host("flash", texture)
			local part = emitter.Parent :: BasePart
			part.CFrame = CFrame.new(position)
			emitter.Color = ColorSequence.new(if texture.tint then tint else WHITE)
			emitter.Size = NumberSequence.new(diameter * config.from, diameter)
			emitter.Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0.05),
				NumberSequenceKeypoint.new(0.4, 0.25),
				NumberSequenceKeypoint.new(1, 1),
			})
			emitter.Speed = NumberRange.new(0)
			emitter.Lifetime = NumberRange.new(life)
			emitter.Rotation = NumberRange.new(0, 360)
			emitter.RotSpeed = NumberRange.new(0)
			emitter:Emit(1)
		end
		if config.core > 0 then
			local core = diameter * config.core
			animate("ball", CFrame.new(position), color, core * 0.35, core, seconds, 0.15)
		end
		return
	end
	animate("ball", CFrame.new(position), color, diameter * 0.35, diameter, seconds, 0.15)
end

-- A full-screen impact frame: `texture` (Vfx.texture "impactFrame") over the whole screen for
-- `seconds` (real time), at `transparency`. Nothing where the quality level does not allow it.
function ImpactEffects.impactFrame(texture: Vfx.Texture, seconds: number, transparency: number?)
	if not ImpactEffects.allows("impactFrame") then
		return
	end
	local player = Players.LocalPlayer
	local playerGui = player and player:FindFirstChildOfClass("PlayerGui")
	if not playerGui then
		return
	end
	if not frameGui or not frameGui.Parent then
		local gui = Instance.new("ScreenGui")
		gui.Name = "ImpactFrame"
		gui.IgnoreGuiInset = true
		gui.ResetOnSpawn = false
		gui.DisplayOrder = 50
		gui.Enabled = false
		gui.Parent = playerGui
		local label = Instance.new("ImageLabel")
		label.BackgroundTransparency = 1
		label.Size = UDim2.fromScale(1, 1)
		label.ScaleType = Enum.ScaleType.Crop
		label.Parent = gui
		frameGui, frameImage = gui, label
	end
	local label = frameImage :: ImageLabel
	label.Image = texture.image
	label.ImageTransparency = transparency or 0
	(frameGui :: ScreenGui).Enabled = true
	frameUntil = os.clock() + seconds
	ensureRunning()
end

-- Camera shake ----------------------------------------------------------------------------------------

-- Kicks the camera: adds `amount` (0-1) of trauma (AnimationConfig.shake). Nothing if shake is off.
function ImpactEffects.shake(amount: number)
	if not AnimationConfig.cameraShake then
		return
	end
	local real = os.clock()
	trauma = math.max(0, trauma - (real - traumaAt) * AnimationConfig.shake.decay)
	traumaAt = real
	trauma = math.min(1, trauma + amount)
end

-- The camera's shake offset right now (identity when still), to multiply onto the camera's CFrame.
function ImpactEffects.shakeOffset(): CFrame
	if trauma <= 0 then
		return CFrame.identity
	end
	local config = AnimationConfig.shake
	local real = os.clock()
	local current = math.max(0, trauma - (real - traumaAt) * config.decay)
	if current <= 0 then
		trauma = 0
		return CFrame.identity
	end
	local power = current * current
	local t = real * config.frequency
	local x = math.noise(t, 0.3) * 2
	local y = math.noise(0.7, t) * 2
	local roll = math.noise(t, t * 0.5 + 3.1) * 2
	return CFrame.new(x * config.maxOffset * power, y * config.maxOffset * power, 0)
		* CFrame.Angles(0, 0, math.rad(config.maxRoll) * roll * power)
end

-- Removes every ring, ball, shape and the impact frame now (particles already emitted finish on
-- their own).
function ImpactEffects.clear()
	for _, effect in active do
		effect.part.Transparency = 1
		effect.part.Parent = nil
		table.insert(free[effect.kind], effect.part)
	end
	table.clear(active)
	for _, shape in shapes do
		retire(shape)
	end
	table.clear(shapes)
	table.clear(waiting)
	hideFrame()
	trauma = 0
end

return ImpactEffects
