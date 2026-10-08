-- Short-lived combat effects that belong to no single unit: projectiles for ranged attacks and
-- pulses on the hexes an area ability hits. Built-in shapes only. Every effect is animated by
-- CombatEffects.update (once per frame) and removed by CombatEffects.clear; nothing is scheduled
-- with task.delay or TweenService. Presentation only.
-- Times come from CombatEffects.setClock (os.clock by default); combat playback sets a clock that
-- runs in fight time, so effects follow the playback speed.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RenderConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("RenderConfig"))

local CombatEffects = {}

-- Anything with a `part` and a `base` (current body position): a UnitView.
type Mover = { part: BasePart, base: Vector3 }

type Projectile = {
	part: Part,
	from: Vector3,
	target: Mover,
	lastTargetPosition: Vector3,
	launchedAt: number,
	arrivesAt: number,
}

type Pulse = {
	part: Part,
	startsAt: number,
	diameter: number,
}

local folder: Folder? = nil
local projectiles: { Projectile } = {}
local pulses: { Pulse } = {}
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

local function effectPart(color: Color3): Part
	if not folder then
		local created = Instance.new("Folder")
		created.Name = "CombatEffects"
		created.Parent = workspace
		folder = created
	end
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = Enum.Material.Neon
	part.Color = color
	part.Parent = folder
	return part
end

local function targetPosition(projectile: Projectile): Vector3
	-- Follow the target while it exists; if it is gone, finish at its last position.
	if projectile.target.part.Parent then
		projectile.lastTargetPosition = projectile.target.part.Position
	end
	return projectile.lastTargetPosition
end

-- Fires a projectile from `from` that reaches `target` at `arrivesAt` (on the effects' clock).
function CombatEffects.projectile(from: Mover, target: Mover, arrivesAt: number, color: Color3)
	local part = effectPart(color)
	part.Shape = Enum.PartType.Ball
	part.Size = Vector3.one * RenderConfig.projectileSize
	part.Position = from.part.Position
	table.insert(projectiles, {
		part = part,
		from = from.part.Position,
		target = target,
		lastTargetPosition = target.part.Position,
		launchedAt = clock(),
		arrivesAt = arrivesAt,
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
		local duration = projectile.arrivesAt - projectile.launchedAt
		local progress = if duration > 0 then (now - projectile.launchedAt) / duration else 1
		if progress >= 1 then
			projectile.part:Destroy()
			table.remove(projectiles, i)
		else
			local arc = Vector3.new(0, RenderConfig.projectileArcHeight * math.sin(math.pi * progress), 0)
			projectile.part.Position = projectile.from:Lerp(targetPosition(projectile), progress) + arc
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
		projectile.part:Destroy()
	end
	table.clear(projectiles)
	for _, pulse in pulses do
		pulse.part:Destroy()
	end
	table.clear(pulses)
end

return CombatEffects
