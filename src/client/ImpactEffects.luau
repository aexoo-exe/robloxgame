-- Pooled impact effects for combat: particle bursts (sparks, puffs, rising motes), flat ground rings
-- and flash balls, plus the camera shake. Built-in parts and rbxasset particle textures only.
-- Presentation only. Everything comes from AnimationConfig.
--
-- Performance: every effect is pooled. Particles come from a few host parts per kind, reused in
-- turn (particles live in world space, so moving a host does not move what it already emitted);
-- rings and balls come from fixed pools, and a burst that finds its pool busy takes the oldest.
-- Particles alive at once are capped per quality level (bursts shrink to fit), and the quality
-- level scales every particle count and turns rings, trails and charge sparkles on or off.
-- Rings and balls are animated on the effects' clock (ImpactEffects.setClock; combat playback sets
-- its fight-time clock, so they follow the playback speed); particles run in real time.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local AnimationConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("AnimationConfig"))

local ImpactEffects = {}

local POOLS = AnimationConfig.pools
local FLAT = CFrame.Angles(0, 0, math.pi / 2) -- a cylinder's axis (X) upright: a flat disc
local RING_THICKNESS = 0.08

-- Particle kinds: texture and the physics that do not change per burst.
local KINDS = {
	spark = {
		texture = "rbxasset://textures/particles/sparkles_main.dds",
		lightEmission = 1,
		drag = 6,
		acceleration = Vector3.new(0, -12, 0),
	},
	puff = {
		texture = "rbxasset://textures/particles/smoke_main.dds",
		lightEmission = 0.15,
		drag = 3,
		acceleration = Vector3.new(0, 1.5, 0),
	},
	mote = {
		texture = "rbxasset://textures/particles/sparkles_main.dds",
		lightEmission = 1,
		drag = 1,
		acceleration = Vector3.new(0, 3, 0),
	},
}

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

local hosts: { [string]: { ParticleEmitter } } = {}
local nextHost: { [string]: number } = {}
local live: { { expires: number, count: number } } = {} -- particle batches, real time
local liveCount = 0

local free: { [string]: { Part } } = { ring = {}, ball = {} }
local made: { [string]: number } = { ring = 0, ball = 0 }
local active: { Animated } = {}

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
	end
end
ImpactEffects.setQuality(AnimationConfig.quality)

function ImpactEffects.quality(): string
	return qualityName
end

-- Whether the current quality level shows `feature` ("rings", "trails" or "charge").
function ImpactEffects.allows(feature: string): boolean
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
end

local function ensureRunning()
	if not connection then
		connection = RunService.RenderStepped:Connect(update)
	end
end

-- A pooled host emitter of `kind`, taken in turn.
local function host(kind: string): ParticleEmitter
	local list = hosts[kind]
	if not list then
		list = {}
		hosts[kind] = list
		nextHost[kind] = 0
	end
	local index = nextHost[kind] % POOLS.emitters + 1
	nextHost[kind] = index
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
		created.Texture = config.texture
		created.LightEmission = config.lightEmission
		created.LightInfluence = 0
		created.Drag = config.drag
		created.Acceleration = config.acceleration
		created.EmissionDirection = Enum.NormalId.Front
		created.Rate = 0
		created.Enabled = false
		created.ZOffset = 1
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
}

-- Emits a burst of `kind` ("spark", "puff" or "mote") at `position`, aimed along `direction` (nil:
-- all around).
function ImpactEffects.burst(kind: string, position: Vector3, direction: Vector3?, burst: Burst)
	local count = budget(burst.count, burst.lifetime[2])
	if count <= 0 then
		return
	end
	local emitter = host(kind)
	local part = emitter.Parent :: BasePart
	local aim = if direction and direction.Magnitude > 1e-3 then direction.Unit else Vector3.yAxis
	part.CFrame = CFrame.lookAt(position, position + aim)
	emitter.Color = ColorSequence.new(burst.color)
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, burst.size),
		NumberSequenceKeypoint.new(1, if kind == "puff" then burst.size * 1.6 else 0),
	})
	local transparency = burst.transparency or 0
	emitter.Transparency = NumberSequence.new(transparency, 1)
	emitter.Speed = NumberRange.new(burst.speed[1], burst.speed[2])
	emitter.Lifetime = NumberRange.new(burst.lifetime[1], burst.lifetime[2])
	local spread = if direction then burst.spread or 180 else 180
	emitter.SpreadAngle = Vector2.new(spread, spread)
	emitter.RotSpeed = if kind == "puff" then NumberRange.new(-90, 90) else NumberRange.new(0, 0)
	emitter:Emit(count)
end

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

-- A flat ring on the ground at `position` growing to `diameter` studs and fading.
function ImpactEffects.ring(position: Vector3, color: Color3, diameter: number, duration: number?)
	animate(
		"ring",
		CFrame.new(position + Vector3.new(0, 0.1, 0)) * FLAT,
		color,
		diameter * 0.3,
		diameter,
		duration or 0.35,
		0.25
	)
end

-- A glowing ball at `position` swelling to `diameter` studs and fading: the core of a hit or burst.
function ImpactEffects.ball(position: Vector3, color: Color3, diameter: number, duration: number?)
	animate("ball", CFrame.new(position), color, diameter * 0.35, diameter, duration or 0.14, 0.15)
end

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

-- Removes every ring and ball now (particles already emitted finish on their own).
function ImpactEffects.clear()
	for _, effect in active do
		effect.part.Transparency = 1
		effect.part.Parent = nil
		table.insert(free[effect.kind], effect.part)
	end
	table.clear(active)
	trauma = 0
end

return ImpactEffects
