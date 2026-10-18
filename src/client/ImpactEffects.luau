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
local RING_THICKNESS = 0.08
local RING_MAX = 9 -- studs: the widest camera-facing ring (ImpactEffects.ring)

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
local live: { { expires: number, count: number } } = {} -- particle batches, real time
local liveCount = 0
-- Particle time scale (slow-motion previews): every host emitter plays at this speed.
local particleTimeScale = 1

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
	emitted: boolean, -- a sprite's particle is out
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
	billboardImage: ImageLabel?, -- the billboard's image
	ends: { Attachment }?,
	beam: Beam?,
	particle: ParticleEmitter?, -- a black-background or flipbook plane/billboard (one particle)
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

-- How the current level was chosen, for the debug report.
local qualitySource = "default"
-- Textured shapes that stayed neon because of the quality level's cap, since the last count reset.
local capped = 0
local skinnedDrawn = 0

-- Sets the quality level ("low", "medium", "high" or "auto"; see AnimationConfig). Auto: Studio
-- takes `autoStudio`, touch-only devices (phones, tablets) `autoTouch`, everything else (desktops,
-- laptops, consoles) `autoDefault`. Low is only ever chosen by hand.
function ImpactEffects.setQuality(name: string)
	local source = "set to " .. name
	if name == "auto" then
		local touchOnly = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
		if RunService:IsStudio() then
			name, source = AnimationConfig.autoStudio, "auto: Studio"
		elseif touchOnly then
			name, source = AnimationConfig.autoTouch, "auto: touch-only device"
		else
			name, source = AnimationConfig.autoDefault, "auto: desktop"
		end
	end
	if AnimationConfig.qualityLevels[name] then
		qualityName = name
		qualitySource = source
		level = AnimationConfig.qualityLevels[name]
		vfxLevel = VfxConfig.quality[name] or VfxConfig.quality.high
	end
end
ImpactEffects.setQuality(AnimationConfig.quality)

function ImpactEffects.quality(): string
	return qualityName
end

-- The quality level's details for the debug report (VfxDebug).
function ImpactEffects.qualityInfo(): any
	return {
		name = qualityName,
		source = qualitySource,
		maxSkinned = vfxLevel.maxSkinned,
		shapes = level.rings == true,
		particles = level.particles,
		maxParticles = level.maxParticles,
		impactFrame = vfxLevel.impactFrame == true,
		skinnedNow = skinned,
		skinnedDrawn = skinnedDrawn,
		capped = capped,
	}
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

-- Sets the time source for rings and balls (nil: os.clock). A new clock is a new fight or preview:
-- the texture draw counts (Vfx.counts, the cap count) start again.
function ImpactEffects.setClock(source: (() -> number)?)
	clock = source or os.clock
	if source then
		Vfx.resetCounts()
		capped, skinnedDrawn = 0, 0
	end
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
	-- Each kind of object hidden its own way: GUIs are disabled and their images reset, the beam
	-- disabled, and only the particle sprite (a ParticleEmitter) cleared.
	for _, surface in skin.surfaces or {} do
		surface.Enabled = false
	end
	for _, label in skin.labels or {} do
		label.Image = ""
	end
	if skin.billboard then
		skin.billboard.Enabled = false
	end
	if skin.billboardImage then
		skin.billboardImage.Image = ""
	end
	if skin.beam then
		skin.beam.Enabled = false
	end
	if skin.particle then
		skin.particle:Clear()
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
		skin.billboardImage = image(billboard)
	end
	return skin.billboard :: BillboardGui, skin.billboardImage :: ImageLabel
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

-- A sprite: one particle locked to the part, made on first use. Emitter properties (size, fade,
-- color) apply to a particle already out, so it follows the shape's step every frame.
local SPRITE_FACES = { X = Enum.NormalId.Right, Y = Enum.NormalId.Top, Z = Enum.NormalId.Front }
local function spriteOf(part: BasePart, skin: Skin): ParticleEmitter
	if not skin.particle then
		local emitter = Instance.new("ParticleEmitter")
		emitter.Rate = 0
		emitter.Enabled = false
		emitter.LockedToPart = true
		emitter.LightInfluence = 0
		emitter.Speed = NumberRange.new(0.001) -- a heading for flat sprites, no visible movement
		emitter.SpreadAngle = Vector2.zero
		emitter.Drag = 0
		emitter.Acceleration = Vector3.zero
		emitter.RotSpeed = NumberRange.new(0)
		emitter.ZOffset = 0.5
		emitter.Parent = part
		skin.particle = emitter
	end
	return skin.particle :: ParticleEmitter
end

-- Draws a black-background or flipbook texture as one additive particle in place of a plane (flat,
-- across the part's thinnest side) or a billboard (facing the camera).
local function drawSprite(entry: Shape, skin: Skin, color: Color3, size: Vector3, seen: number)
	local texture = entry.texture :: Vfx.Texture
	local emitter = spriteOf(entry.part, skin)
	local across
	if texture.mode == "plane" then
		local axis = if size.X <= size.Y and size.X <= size.Z then "X" elseif size.Y <= size.Z then "Y" else "Z"
		across = if axis == "X"
			then math.max(size.Y, size.Z)
			elseif axis == "Y" then math.max(size.X, size.Z)
			else math.max(size.X, size.Y)
		if not entry.emitted then
			emitter.Orientation = Enum.ParticleOrientation.VelocityPerpendicular
			emitter.EmissionDirection = SPRITE_FACES[axis]
		end
	else
		across = math.max(size.X, size.Y, size.Z)
		if not entry.emitted then
			emitter.Orientation = Enum.ParticleOrientation.FacingCamera
		end
	end
	emitter.Size = NumberSequence.new(across * (texture.scale or 1))
	emitter.Transparency = NumberSequence.new(math.clamp(seen, 0, 1))
	emitter.Color = ColorSequence.new(color)
	if not entry.emitted then
		entry.emitted = true
		emitter.Texture = texture.image
		emitter.LightEmission = texture.light or (if texture.blend == "additive" then 1 else 0)
		emitter.Brightness = texture.brightness
		emitter.Rotation = NumberRange.new(if texture.upright then 0 else entry.spin)
		local flipbook = texture.flipbook
		if flipbook then
			emitter.FlipbookLayout = (Enum.ParticleFlipbookLayout :: any)["Grid" .. flipbook.layout]
			emitter.FlipbookMode = (Enum.ParticleFlipbookMode :: any)[flipbook.mode]
				or Enum.ParticleFlipbookMode.OneShot
			emitter.FlipbookFramerate = NumberRange.new(flipbook.fps or 24)
			-- A one-shot sheet plays over the particle's life: the shape's.
			emitter.Lifetime =
				NumberRange.new(if flipbook.mode == "OneShot" then math.max(entry.duration, 0.05) else 30)
		else
			emitter.FlipbookLayout = Enum.ParticleFlipbookLayout.None
			emitter.Lifetime = NumberRange.new(30) -- cleared when the shape ends
		end
		emitter:Clear()
		emitter:Emit(1)
	end
end

-- Draws a textured shape over what its step just set (size, place, color, `shown` transparency).
local function drawSkin(entry: Shape)
	local part = entry.part
	local texture = entry.texture :: Vfx.Texture
	local skin = skinOf(part)
	local color = Vfx.tint(texture, part.Color)
	local size = part.Size
	-- A usage's opacity cap (VfxConfig.uses `opacity`): ground discs and patches never read as solid.
	local seen = 1 - (1 - entry.shown) * (texture.opacity or 1)
	if texture.sprite then
		drawSprite(entry, skin, color, size, seen)
	elseif texture.mode == "plane" then
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
		local across = math.max(size.X, size.Y, size.Z) * (texture.scale or 1)
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
		-- Tiling textures repeat every `tile` studs (a pooled beam may have tiled before).
		if texture.tile then
			beam.TextureMode = Enum.TextureMode.Wrap
			beam.TextureLength = texture.tile
		else
			beam.TextureMode = Enum.TextureMode.Stretch
			beam.TextureLength = 1
		end
		beam.LightEmission = texture.light or (if texture.blend == "additive" then 1 else 0)
		beam.Brightness = texture.brightness
		beam.Width0 = width * texture.width
		beam.Width1 = width * texture.width
		beam.Color = ColorSequence.new(color)
		beam.Transparency = NumberSequence.new(seen)
		beam.Enabled = seen < 1
	end
end

-- Puts a shape's part back in its pool (its slot in the textured cap is freed first, so a failure
-- hiding its texture cannot leak the slot).
local function retire(entry: Shape)
	local part = entry.part
	if entry.texture then
		skinned -= 1
		entry.texture = nil
		hideSkin(part)
	end
	part.Transparency = 1
	part.Parent = nil
	table.insert(spareShapes[entry.shape], part)
end

-- An effect that errors is dropped, and its error is warned about once per kind of effect, so one
-- bad effect can never break the update every frame.
local reported: { [string]: boolean } = {}
local function report(kind: string, problem: any)
	if not reported[kind] then
		reported[kind] = true
		warn(string.format("[ImpactEffects] a %s effect failed and was dropped: %s", kind, tostring(problem)))
	end
end

local function kindOf(entry: Shape): string
	local texture = entry.texture
	if not texture then
		return entry.shape
	end
	return entry.shape .. " " .. texture.mode .. (if texture.sprite then " sprite" else "")
end

-- One frame of a shape at `progress` (0-1).
local function advance(shape: Shape, progress: number)
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

-- Lets go of a shape whose texture could not be hidden: its part is destroyed (never pooled with a
-- texture still showing) and the pool may make a new one.
local function discard(shape: Shape)
	skins[shape.part] = nil
	madeShapes -= 1
	pcall(function()
		shape.part:Destroy()
	end)
end

-- Drops a shape whose update failed: back to its pool if it retires cleanly, else discarded.
local function drop(shape: Shape)
	if not pcall(retire, shape) then
		discard(shape)
	end
end

local function hideFrame()
	if frameGui then
		frameGui.Enabled = false
	end
end

-- Light flashes: a PointLight at `position` that peaks at once and dies out over `duration` (the
-- effects' clock, so it follows slow motion), `range` studs. Not at quality levels without rings.
type Light = { part: BasePart, light: PointLight, startsAt: number, duration: number, brightness: number }
local lights: { Light } = {}
local spareLights: { BasePart } = {}

local function stepLights(now: number)
	for i = #lights, 1, -1 do
		local entry = lights[i]
		local progress = (now - entry.startsAt) / entry.duration
		if progress >= 1 then
			table.remove(lights, i)
			entry.light.Enabled = false
			entry.part.Parent = nil
			table.insert(spareLights, entry.part)
		else
			-- Peaks at once, dies out faster than linear.
			entry.light.Brightness = entry.brightness * (1 - progress) * (1 - progress)
		end
	end
end

local function update()
	local now = clock()
	for i = #active, 1, -1 do
		local effect = active[i]
		local progress = (now - effect.startsAt) / effect.duration
		if progress >= 1 then
			table.remove(active, i)
			effect.part.Transparency = 1
			effect.part.Parent = nil
			table.insert(free[effect.kind], effect.part)
		elseif progress >= 0 then
			local ok, problem = pcall(function()
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
			end)
			if not ok then
				report(effect.kind, problem)
				table.remove(active, i)
				effect.part.Parent = nil
			end
		end
	end
	for i = #shapes, 1, -1 do
		local shape = shapes[i]
		local progress = (now - shape.startsAt) / shape.duration
		if progress >= 1 then
			table.remove(shapes, i)
			local kind = kindOf(shape)
			local ok, problem = pcall(retire, shape)
			if not ok then
				report(kind, problem)
				discard(shape)
			end
		elseif progress >= 0 then
			local ok, problem = pcall(advance, shape, progress)
			if not ok then
				report(kindOf(shape), problem)
				table.remove(shapes, i)
				drop(shape)
			end
		end
	end
	stepLights(now)
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

-- Host emitters per key (a kind or emit texture), up to HOST_CAP. A ParticleEmitter's Size, Color,
-- Transparency, Drag and Acceleration also apply to the particles it already shows: a host still
-- showing particles taken for another effect restyles them (a tiny ember's host turning a big
-- flash into a dot, or a dot into a screen-filling ball). So an idle host (its particles all gone)
-- is taken first, then a new one; only when HOST_CAP are all busy is the one that frees soonest
-- reused (counted: emitStats.stolen).
local HOST_CAP = POOLS.emitters * 4
local busyUntil: { [ParticleEmitter]: number } = setmetatable({}, { __mode = "k" }) :: any

-- What the particle budget and the host pools did since the last reset (ReelCheck's report).
local emitStats = { spawned = 0, dropped = 0, trimmed = 0, stolen = 0, shapesDropped = 0, lightsDropped = 0 }

local function takeHost(key: string, make: () -> ParticleEmitter, seconds: number): ParticleEmitter
	local list = hosts[key]
	if not list then
		list = {}
		hosts[key] = list
	end
	local real = os.clock()
	-- Real seconds its particles stay out (longer in slow motion; ImpactEffects.setTimeScale).
	local busy = real + seconds / math.max(particleTimeScale, 0.05)
	local soonest: ParticleEmitter? = nil
	local soonestAt = math.huge
	for i = #list, 1, -1 do
		local emitter = list[i]
		if not emitter.Parent or not emitter.Parent.Parent then
			table.remove(list, i)
			continue
		end
		local freeAt = busyUntil[emitter] or 0
		if freeAt <= real then
			busyUntil[emitter] = busy
			emitter:SetAttribute("liveUntil", busy)
			return emitter
		end
		if freeAt < soonestAt then
			soonest, soonestAt = emitter, freeAt
		end
	end
	local emitter: ParticleEmitter
	if #list < HOST_CAP or not soonest then
		emitter = make()
		table.insert(list, emitter)
	else
		emitStats.stolen += 1
		emitter = soonest :: ParticleEmitter
		busy = math.max(busy, soonestAt)
	end
	busyUntil[emitter] = busy
	emitter:SetAttribute("liveUntil", busy)
	return emitter
end

-- A host emitter of `kind` drawing `texture` (nil: the kind's built-in texture) for particles living
-- up to `seconds` (takeHost).
local function host(kind: string, texture: Vfx.Texture?, seconds: number): ParticleEmitter
	local key = if texture then kind .. "|" .. texture.image else kind
	return takeHost(key, function()
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
		return created
	end, seconds)
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
	local share = math.floor(wanted * level.particles + 0.5)
	local count = math.min(share, level.maxParticles - liveCount)
	if count <= 0 then
		if share > 0 then
			emitStats.dropped += 1 -- the live particle cap is full: nothing drawn
		end
		return 0
	end
	emitStats.spawned += 1
	if count < share then
		emitStats.trimmed += share - count -- particles cut by the live cap
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
	local emitter = host(kind, texture, burst.lifetime[2])
	local part = emitter.Parent :: BasePart
	local aim = if direction and direction.Magnitude > 1e-3 then direction.Unit else Vector3.yAxis
	part.CFrame = CFrame.lookAt(position, position + aim)
	if texture and texture.tintShare < 1 then
		emitter.Color =
			ColorSequence.new(Vfx.tint(texture, burst.color), Vfx.tint(texture, burst.color2 or burst.color))
	else
		emitter.Color = ColorSequence.new(burst.color, burst.color2 or burst.color)
	end
	-- Textures whose art sits small in its frame (fire) are drawn bigger (traits `scale`).
	local size = burst.size * (if texture then texture.scale or 1 else 1)
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, size),
		NumberSequenceKeypoint.new(1, size * (config.growth or 0)),
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

-- Fully specified particles (the showcase recipe) ----------------------------------------------------

function ImpactEffects.setTimeScale(scale: number)
	particleTimeScale = math.clamp(scale, 0, 1)
	for _, list in hosts do
		for _, emitter in list do
			emitter.TimeScale = particleTimeScale
		end
	end
end

export type Emit = {
	usage: string?, -- VfxConfig.uses entry for the texture (nil: `fallback` only)
	fallback: string?, -- the texture when none is picked or the kit is off (default sparkles)
	count: number,
	color: ColorSequence, -- the textures are white masks: this is their whole color
	size: NumberSequence,
	transparency: NumberSequence,
	lifetime: { number }, -- { min, max } seconds
	speed: { number }?, -- { min, max } studs/s (default none)
	spread: number?, -- degrees around `direction` (default 180: all around)
	direction: Vector3?, -- default up
	drag: number?,
	acceleration: Vector3?, -- gravity is Vector3.new(0, -g, 0); rising smoke and embers go up
	lightEmission: number?, -- 1: adds light (fire, glow, sparks); 0: covers (smoke)
	brightness: number?,
	rotation: { number }?, -- { min, max } degrees (default random all around)
	rotSpeed: { number }?, -- { min, max } degrees/s
	flat: boolean?, -- lies flat, facing up (ground shockwaves, scorches)
	stretch: boolean?, -- turns along its velocity (streak sparks read as arcs)
	zOffset: number?,
}

-- Emits `spec.count` particles at `position` with every property given (ImpactEffects.Emit), drawn
-- with the usage's kit texture (its flipbook plays: one-shot sheets over each particle's life) or the
-- fallback texture. Within the quality level's particle share and cap; nothing when none is left.
function ImpactEffects.emit(position: Vector3, spec: Emit)
	local count = budget(spec.count, spec.lifetime[2])
	if count <= 0 then
		return
	end
	local texture = if spec.usage then Vfx.texture(spec.usage, nil, "particle") else nil
	if texture and texture.mode ~= "particle" then
		texture = nil
	end
	local content = if texture then texture.image else (spec.fallback or KINDS.spark.texture)
	-- An idle host of this texture (takeHost): a busy one would restyle the particles it still shows.
	local emitter = takeHost("emit|" .. content, function()
		local part = Instance.new("Part")
		part.Name = "emit"
		bare(part)
		part.Transparency = 1
		part.Size = Vector3.one * 0.2
		part.Parent = getFolder()
		local created = Instance.new("ParticleEmitter")
		created.Texture = content
		created.LightInfluence = 0
		created.Rate = 0
		created.Enabled = false
		local flipbook = texture and texture.flipbook
		if flipbook then
			created.FlipbookLayout = (Enum.ParticleFlipbookLayout :: any)["Grid" .. flipbook.layout]
			created.FlipbookMode = (Enum.ParticleFlipbookMode :: any)[flipbook.mode]
				or Enum.ParticleFlipbookMode.OneShot
			created.FlipbookFramerate = NumberRange.new(flipbook.fps or 24)
			created.FlipbookStartRandom = flipbook.mode == "Loop"
		end
		created.Parent = part
		return created
	end, spec.lifetime[2])
	local scale = if texture then texture.scale or 1 else 1
	local part = emitter.Parent :: BasePart
	local aim = if spec.direction and spec.direction.Magnitude > 1e-3 then spec.direction.Unit else Vector3.yAxis
	part.CFrame = CFrame.lookAt(position, position + aim)
	emitter.EmissionDirection = Enum.NormalId.Front
	emitter.TimeScale = particleTimeScale
	emitter:SetAttribute("vfx", (spec.usage or "(none)") .. (if texture then " " .. texture.key else " (no texture)"))
	emitter.Color = spec.color
	if scale ~= 1 then
		local points = {}
		for _, point in spec.size.Keypoints do
			table.insert(points, NumberSequenceKeypoint.new(point.Time, point.Value * scale, point.Envelope * scale))
		end
		emitter.Size = NumberSequence.new(points)
	else
		emitter.Size = spec.size
	end
	emitter.Transparency = spec.transparency
	emitter.Lifetime = NumberRange.new(spec.lifetime[1], spec.lifetime[2])
	local speed = spec.speed or { 0, 0 }
	-- Flat particles need a heading to lie across: a tiny speed straight up.
	local least = if spec.flat then 0.001 else 0
	emitter.Speed = NumberRange.new(math.max(speed[1], least), math.max(speed[2], least))
	local spread = if spec.flat then 0 else (spec.spread or 180)
	emitter.SpreadAngle = Vector2.new(spread, spread)
	emitter.Orientation = if spec.flat
		then Enum.ParticleOrientation.VelocityPerpendicular
		elseif spec.stretch then Enum.ParticleOrientation.VelocityParallel
		else Enum.ParticleOrientation.FacingCamera
	emitter.Drag = spec.drag or 0
	emitter.Acceleration = spec.acceleration or Vector3.zero
	emitter.LightEmission = spec.lightEmission or 0
	emitter.Brightness = spec.brightness or 1
	local rotation = spec.rotation or { 0, 360 }
	emitter.Rotation = NumberRange.new(rotation[1], rotation[2])
	local rotSpeed = spec.rotSpeed or { 0, 0 }
	emitter.RotSpeed = NumberRange.new(rotSpeed[1], rotSpeed[2])
	-- A camera-facing sprite larger than its height above the floor is cut by it and reads as a flat
	-- oval on the ground: by default it is drawn toward the camera by half its largest size.
	if spec.zOffset then
		emitter.ZOffset = spec.zOffset
	elseif spec.flat then
		emitter.ZOffset = 0.2
	else
		local largest = 0
		for _, point in emitter.Size.Keypoints do
			largest = math.max(largest, point.Value)
		end
		emitter.ZOffset = math.clamp(largest * 0.5, 1, 8)
	end
	emitter:Emit(count)
end

-- A light flash (see stepLights): `brightness` at once, out over `duration`.
-- At most MAX_LIGHTS at once: each PointLight paints a hard-edged disc on the floor, so many small
-- ones read as a ring of flat ovals.
local MAX_LIGHTS = 3
function ImpactEffects.light(position: Vector3, color: Color3, brightness: number, range: number, duration: number)
	if not level.rings or #lights >= MAX_LIGHTS then
		if level.rings then
			emitStats.lightsDropped += 1
		end
		return
	end
	local part = table.remove(spareLights)
	if not part then
		local created = Instance.new("Part")
		created.Name = "light"
		bare(created)
		created.Transparency = 1
		created.Size = Vector3.one * 0.2
		local point = Instance.new("PointLight")
		point.Shadows = false
		point.Parent = created
		part = created
	end
	local p = part :: BasePart
	local point = p:FindFirstChildOfClass("PointLight") :: PointLight
	p.CFrame = CFrame.new(position)
	point.Color = color
	point.Range = range
	point.Brightness = brightness
	point.Enabled = true
	p.Parent = getFolder()
	table.insert(lights, { part = p, light = point, startsAt = clock(), duration = duration, brightness = brightness })
	ensureRunning()
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
-- shapes; a plane should be a "Block" (a SurfaceGui covers a block's face). `textureOnly`: drawn
-- only textured (nothing instead of neon). Nothing at
-- quality levels without rings. At most AnimationConfig.pools.shapes at once: past that the oldest
-- is reused.
function ImpactEffects.shape(
	shape: string,
	color: Color3,
	duration: number,
	step: (BasePart, number) -> (),
	delay: number?,
	material: Enum.Material?,
	texture: Vfx.Texture?,
	textureOnly: boolean?
)
	if not level.rings then
		return
	end
	-- A texture-only layer (a glow over a neon core) draws nothing without its texture, including
	-- when the quality level's cap of textured shapes is reached.
	if textureOnly and (not texture or skinned >= vfxLevel.maxSkinned) then
		return
	end
	-- A textured plane past the cap would fall back to a flat neon slab on the ground (a sticker):
	-- it is skipped instead.
	if texture and texture.mode == "plane" and skinned >= vfxLevel.maxSkinned then
		capped += 1
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
				emitStats.shapesDropped += 1 -- the shape pool is full of other kinds
				return
			end
		end
	end
	if texture and skinned >= vfxLevel.maxSkinned then
		texture = nil -- the quality level's cap: this one stays neon
		capped += 1
	end
	if texture then
		skinned += 1
		skinnedDrawn += 1
	end
	local p = part :: BasePart
	-- What it draws, for the live-effects dump (VfxDebug.dumpLive, the dev lineup's O key).
	p:SetAttribute("vfx", if texture then texture.key .. " " .. texture.mode else "neon")
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
		emitted = false,
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

-- A ring at `position` (ground) growing to `diameter` studs and fading: a soft camera-facing ring
-- raised off the ground. Never a plane lying on the floor (the ring texture on a flat Block read as
-- a sticker, the reel check's "SurfaceGui at floor").
function ImpactEffects.ring(position: Vector3, color: Color3, diameter: number, duration: number?, start: number?)
	local seconds = duration or 0.35
	local first = start or 0.25 -- the starting transparency
	if not level.rings then
		return
	end
	-- Camera-facing, a ring as wide as a big area would cover the whole close-up: capped.
	diameter = math.min(diameter, RING_MAX)
	-- Raised so its lower edge stays above the floor (cut by the floor it read as a faint partial
	-- arc); a wide ring rises at most ~3 studs.
	ImpactEffects.emit(position + Vector3.new(0, 0.3 + math.min(diameter * 0.45, 2.8), 0), {
		usage = "shock",
		fallback = KINDS.bubble.texture,
		count = 1,
		color = ColorSequence.new(color),
		size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, diameter * 0.3),
			NumberSequenceKeypoint.new(1, diameter),
		}),
		transparency = NumberSequence.new(math.max(first, 0.45), 1),
		lifetime = { seconds, seconds },
		lightEmission = 1,
	})
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
			local emitter = host("flash", texture, life)
			local part = emitter.Parent :: BasePart
			part.CFrame = CFrame.new(position)
			emitter.Color = ColorSequence.new(Vfx.tint(texture, tint))
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

-- What the effects pipeline did since the last reset (ReelCheck): particle emits spawned, dropped
-- whole by the live particle cap, particles trimmed by it, busy hosts reused (restyled), shapes
-- dropped by a full pool, textured shapes left neon or skipped by the quality cap (maxSkinned),
-- lights dropped by MAX_LIGHTS.
function ImpactEffects.emitStats(): { [string]: number }
	return {
		spawned = emitStats.spawned,
		dropped = emitStats.dropped,
		trimmed = emitStats.trimmed,
		stolen = emitStats.stolen,
		shapesDropped = emitStats.shapesDropped,
		capped = capped,
		lightsDropped = emitStats.lightsDropped,
	}
end

function ImpactEffects.resetEmitStats()
	for name in emitStats do
		emitStats[name] = 0
	end
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
		if not pcall(retire, shape) then
			discard(shape)
		end
	end
	table.clear(shapes)
	table.clear(waiting)
	for _, entry in lights do
		entry.light.Enabled = false
		entry.part.Parent = nil
		table.insert(spareLights, entry.part)
	end
	table.clear(lights)
	hideFrame()
	trauma = 0
end

return ImpactEffects
