-- Short-lived combat effects that belong to no single unit: projectiles for ranged attacks and
-- pulses on the hexes an area ability hits. Built-in shapes only. Every effect is animated by
-- CombatEffects.update (once per frame) and removed by CombatEffects.clear; nothing is scheduled
-- with task.delay or TweenService. Presentation only.
-- Times come from CombatEffects.setClock (os.clock by default); combat playback sets a clock that
-- runs in fight time, so effects follow the playback speed.
-- Projectiles are pooled (each part keeps its trail), wait hidden until they launch, and look as
-- AnimationConfig.projectiles says; trails show at quality levels that allow them (ImpactEffects).
-- With picked textures (VfxConfig.uses, Vfx) a ball shot glows with an energy sprite around a
-- smaller neon core (`halo`) and a slash wave flies as a textured blade (`slash`); without them
-- they stay neon.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AnimationConfig = require(Shared:WaitForChild("AnimationConfig"))
local RenderConfig = require(Shared:WaitForChild("RenderConfig"))

local ImpactEffects = require(script.Parent.ImpactEffects)
local Vfx = require(script.Parent.Vfx)

local CombatEffects = {}

-- Anything with a `part` and a `base` (current body position): a UnitView.
type Mover = { part: BasePart, base: Vector3 }

-- A pooled projectile part with its trail, and its texture objects (made on first use).
type Shot = {
	part: Part,
	trail: Trail,
	top: Attachment,
	bottom: Attachment,
	sprite: BillboardGui?, -- a ball's halo
	blade: { SurfaceGui }?, -- a wave's two faces
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
	textured: boolean, -- drawn with its texture (sprite or blade)
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

-- Hides a shot's texture objects.
local function plain(shot: Shot)
	if shot.sprite then
		shot.sprite.Enabled = false
	end
	for _, face in shot.blade or {} do
		face.Enabled = false
	end
end

local function label(parent: Instance, texture: Vfx.Texture, color: Color3): ImageLabel
	local image = parent:FindFirstChildOfClass("ImageLabel")
	if not image then
		local made = Instance.new("ImageLabel")
		made.BackgroundTransparency = 1
		made.Size = UDim2.fromScale(1, 1)
		made.Parent = parent
		image = made
	end
	local found = image :: ImageLabel
	found.Image = texture.image
	found.ImageColor3 = Vfx.tint(texture, color)
	return found
end

-- Readies a shot's texture: a halo sprite `across` studs wide, or a blade on its two flat faces.
-- It shows at launch.
local function dress(shot: Shot, texture: Vfx.Texture, color: Color3, across: number)
	if texture.mode == "billboard" then
		if not shot.sprite then
			local sprite = Instance.new("BillboardGui")
			sprite.LightInfluence = 0
			sprite.Adornee = shot.part
			sprite.Parent = shot.part
			shot.sprite = sprite
		end
		local sprite = shot.sprite :: BillboardGui
		sprite.Size = UDim2.fromScale(across, across)
		sprite.Brightness = texture.brightness
		sprite.Enabled = false
		label(sprite, texture, color).Rotation = math.random() * 360
	else
		if not shot.blade then
			local faces = {}
			for i, face in { Enum.NormalId.Top, Enum.NormalId.Bottom } do
				local surface = Instance.new("SurfaceGui")
				surface.LightInfluence = 0
				surface.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
				surface.CanvasSize = Vector2.new(256, 256)
				surface.Face = face
				surface.Parent = shot.part
				faces[i] = surface
			end
			shot.blade = faces
		end
		for _, surface in shot.blade :: { SurfaceGui } do
			surface.Brightness = texture.brightness
			surface.Enabled = false
			label(surface, texture, color)
		end
	end
end

local function releaseShot(shot: Shot)
	shot.trail.Enabled = false
	shot.part.Transparency = 1
	shot.part.Parent = nil
	plain(shot)
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
	-- Textures: a ball's halo, a wave's blade (only where the quality level shows rings).
	local texture = nil
	if not settings.tongue and ImpactEffects.allows("rings") then
		local wanted = if flat then Vfx.texture("slash", color, "plane") else Vfx.texture("halo", color, "billboard")
		if wanted and wanted.mode == (if flat then "plane" else "billboard") then
			texture = wanted
			if flat then
				-- Deep enough for the blade texture to read.
				shot.part.Size = Vector3.new(size * look.width, size * 0.12, size * look.width * 0.45)
			end
			dress(shot, texture, color, size * 3)
		end
	end
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
		textured = texture ~= nil,
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
			if projectile.textured then
				-- A wave is all blade (its neon block hidden); a ball keeps a smaller bright core.
				if shot.blade then
					for _, face in shot.blade do
						face.Enabled = true
					end
				end
				if shot.sprite then
					shot.sprite.Enabled = true
				end
				if shot.part.Shape == Enum.PartType.Block then
					shot.part.Transparency = 1
				else
					shot.part.Size = Vector3.one * projectile.size * 0.6
				end
			end
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
