-- Short-lived combat effects that belong to no single unit: projectiles for ranged attacks and
-- pulses on the hexes an area ability hits. Built-in shapes only. Every effect is animated by
-- CombatEffects.update (once per frame) and removed by CombatEffects.clear; nothing is scheduled
-- with task.delay or TweenService. Presentation only.
-- Times come from CombatEffects.setClock (os.clock by default); combat playback sets a clock that
-- runs in fight time, so effects follow the playback speed.
-- Projectiles are pooled (each part keeps its trail), wait hidden until they launch, and look as
-- AnimationConfig.projectiles says; trails show at quality levels that allow them (ImpactEffects).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AnimationConfig = require(Shared:WaitForChild("AnimationConfig"))
local RenderConfig = require(Shared:WaitForChild("RenderConfig"))

local ImpactEffects = require(script.Parent.ImpactEffects)

local CombatEffects = {}

-- Anything with a `part` and a `base` (current body position): a UnitView.
type Mover = { part: BasePart, base: Vector3 }

-- A pooled projectile part with its trail.
type Shot = {
	part: Part,
	trail: Trail,
	top: Attachment,
	bottom: Attachment,
}

type Projectile = {
	shot: Shot,
	from: Vector3,
	origin: () -> Vector3, -- where it leaves from, read at launch (a hand, a fingertip)
	target: Mover,
	lastTargetPosition: Vector3,
	launchedAt: number,
	arrivesAt: number,
	launched: boolean,
	trailing: boolean,
	tongue: boolean?,
	arc: number,
	size: number,
}

type Pulse = {
	part: Part,
	startsAt: number,
	diameter: number,
}

local folder: Folder? = nil
local projectiles: { Projectile } = {}
local pulses: { Pulse } = {}
local spareShots: { Shot } = {}
local clock: () -> number = os.clock

-- Sets the time source for new effects (nil: os.clock).
function CombatEffects.setClock(source: (() -> number)?)
	clock = source or os.clock
end

-- Width of a hex cell across its flat sides.
local HEX_WIDTH = math.sqrt(3) * (RenderConfig.hexRadius - RenderConfig.cellGap)
local PULSE_THICKNESS = 0.12
-- A cylinder's axis is its X axis; this lays it flat.
local FLAT = CFrame.Angles(0, 0, math.pi / 2)
local WHITE = Color3.new(1, 1, 1)

local function getFolder(): Folder
	if not folder then
		local created = Instance.new("Folder")
		created.Name = "CombatEffects"
		created.Parent = workspace
		folder = created
	end
	return folder :: Folder
end

local function effectPart(color: Color3): Part
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = Enum.Material.Neon
	part.Color = color
	part.Parent = getFolder()
	return part
end

-- A projectile part from the pool, hidden, with its trail off and cleared.
local function takeShot(color: Color3): Shot
	local shot = table.remove(spareShots)
	if not shot then
		local part = effectPart(color)
		local top = Instance.new("Attachment")
		top.Parent = part
		local bottom = Instance.new("Attachment")
		bottom.Parent = part
		local trail = Instance.new("Trail")
		trail.Attachment0 = top
		trail.Attachment1 = bottom
		trail.FaceCamera = true
		trail.LightEmission = 1
		trail.Transparency = NumberSequence.new(0.15, 1)
		trail.WidthScale = NumberSequence.new(1, 0)
		trail.Enabled = false
		trail.Parent = part
		shot = { part = part, trail = trail, top = top, bottom = bottom }
	end
	local taken = shot :: Shot
	taken.part.Color = color
	taken.part.Transparency = 1
	taken.part.Parent = getFolder()
	taken.trail.Enabled = false
	taken.trail:Clear()
	return taken
end

local function releaseShot(shot: Shot)
	shot.trail.Enabled = false
	shot.part.Transparency = 1
	shot.part.Parent = nil
	table.insert(spareShots, shot)
end

local function targetPosition(projectile: Projectile): Vector3
	-- Follow the target while it exists; if it is gone, finish at its last position.
	if projectile.target.part.Parent then
		projectile.lastTargetPosition = projectile.target.part.Position
	end
	return projectile.lastTargetPosition
end

export type ProjectileOptions = {
	launchAt: number?, -- when it leaves (on the effects' clock; default now)
	origin: (() -> Vector3)?, -- where it leaves from, read at launch (default the shooter's middle)
	look: string?, -- an AnimationConfig.projectiles entry: "shot", "orb", "bounce" or "wave" (default "orb")
	tongue: boolean?, -- a thin bar that stretches from the start to its tip instead of a ball
	scale: number?, -- size multiplier (star level)
}

-- Fires a projectile from `from` that reaches `target` at `arrivesAt` (on the effects' clock), so
-- it lands as the hit lands. It waits hidden until `launchAt`. A `tongue` projectile is a thin bar
-- that stretches straight from the start to its tip instead of an arcing ball (a placeholder look
-- for some attacks).
function CombatEffects.projectile(
	from: Mover,
	target: Mover,
	arrivesAt: number,
	color: Color3,
	options: ProjectileOptions?
)
	local settings: ProjectileOptions = options or {}
	local looks = AnimationConfig.projectiles
	local look = if settings.tongue then looks.tongue else looks[settings.look or "orb"] or looks.orb
	local size = look.size * (settings.scale or 1)
	local shot = takeShot(color)
	-- A flat look (a slash wave) is a wide, thin blade across its flight, its trail as wide.
	local flat = not settings.tongue and look.flat == true
	shot.part.Shape = if settings.tongue or flat then Enum.PartType.Block else Enum.PartType.Ball
	shot.part.Size = if flat then Vector3.new(size * look.width, size * 0.12, size * 0.35) else Vector3.one * size
	local trailing = not settings.tongue and look.trail ~= nil and ImpactEffects.allows("trails")
	if trailing and flat then
		local half = size * look.width / 2
		shot.top.Position = Vector3.new(half, 0, 0)
		shot.bottom.Position = Vector3.new(-half, 0, 0)
		shot.trail.Lifetime = look.trail
		shot.trail.Color = ColorSequence.new(color:Lerp(WHITE, 0.35), color)
	elseif trailing then
		local half = size * (look.trailWidth or 1) / 2
		shot.top.Position = Vector3.new(0, half, 0)
		shot.bottom.Position = Vector3.new(0, -half, 0)
		shot.trail.Lifetime = look.trail
		shot.trail.Color = ColorSequence.new(color:Lerp(WHITE, 0.35), color)
	end
	local shooter = from.part
	local now = clock()
	table.insert(projectiles, {
		shot = shot,
		from = shooter.Position,
		origin = settings.origin or function()
			return shooter.Position
		end,
		target = target,
		lastTargetPosition = target.part.Position,
		launchedAt = math.max(settings.launchAt or now, now),
		arrivesAt = arrivesAt,
		launched = false,
		trailing = trailing,
		tongue = settings.tongue,
		arc = look.arc or 0,
		size = size,
	})
end

-- Pulses the given ground positions. Each entry is { position = Vector3, delay = seconds }. `color`
-- defaults to RenderConfig.areaPulseColor.
function CombatEffects.areaPulse(cells: { { position: Vector3, delay: number } }, color: Color3?)
	local now = clock()
	for _, cell in cells do
		local part = effectPart(color or RenderConfig.areaPulseColor)
		part.Shape = Enum.PartType.Cylinder
		part.Transparency = 1 -- shown when its delay has passed
		part.Size = Vector3.new(PULSE_THICKNESS, HEX_WIDTH, HEX_WIDTH)
		part.CFrame = CFrame.new(cell.position + Vector3.new(0, PULSE_THICKNESS, 0)) * FLAT
		table.insert(pulses, { part = part, startsAt = now + cell.delay, diameter = HEX_WIDTH })
	end
end

-- Advances every effect to `now` (on the effects' clock) and removes finished ones.
function CombatEffects.update(now: number)
	for i = #projectiles, 1, -1 do
		local projectile = projectiles[i]
		local shot = projectile.shot
		if now < projectile.launchedAt then
			continue
		end
		if not projectile.launched then
			-- Leaves now, from wherever the hand (or fingertip) is at this moment.
			projectile.launched = true
			projectile.from = projectile.origin()
			shot.part.Position = projectile.from
			shot.part.Transparency = 0
			shot.trail:Clear()
			shot.trail.Enabled = projectile.trailing
		end
		local duration = projectile.arrivesAt - projectile.launchedAt
		local progress = if duration > 0 then (now - projectile.launchedAt) / duration else 1
		if progress >= 1 then
			releaseShot(shot)
			table.remove(projectiles, i)
		elseif projectile.tongue then
			local tip = projectile.from:Lerp(targetPosition(projectile), progress)
			local length = (tip - projectile.from).Magnitude
			local thickness = projectile.size * 0.4
			shot.part.Size = Vector3.new(thickness, thickness, math.max(thickness, length))
			if length > 1e-3 then
				shot.part.CFrame = CFrame.lookAt((projectile.from + tip) / 2, tip)
			end
		else
			local arc = Vector3.new(0, projectile.arc * math.sin(math.pi * progress), 0)
			local position = projectile.from:Lerp(targetPosition(projectile), progress) + arc
			local heading = position - shot.part.Position
			-- Faces along its flight, so the trail's width stays across it.
			shot.part.CFrame = if heading.Magnitude > 1e-3
				then CFrame.lookAt(position, position + heading)
				else CFrame.new(position)
		end
	end

	for i = #pulses, 1, -1 do
		local pulse = pulses[i]
		local progress = (now - pulse.startsAt) / RenderConfig.areaPulseDuration
		if progress >= 1 then
			pulse.part:Destroy()
			table.remove(pulses, i)
		elseif progress >= 0 then
			local start = RenderConfig.areaPulseTransparency
			pulse.part.Transparency = start + (1 - start) * progress
			-- Grows from 60% to full size with an ease-out.
			local scale = 0.6 + 0.4 * (1 - (1 - progress) * (1 - progress))
			pulse.part.Size = Vector3.new(PULSE_THICKNESS, pulse.diameter * scale, pulse.diameter * scale)
		end
	end
end

-- Removes every effect at once.
function CombatEffects.clear()
	for _, projectile in projectiles do
		releaseShot(projectile.shot)
	end
	table.clear(projectiles)
	for _, pulse in pulses do
		pulse.part:Destroy()
	end
	table.clear(pulses)
end

return CombatEffects
