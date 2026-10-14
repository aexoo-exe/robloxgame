-- Shape primitives for ability effects (AbilityFx): beams in several styles, travelling slash
-- waves, cone sweeps, ground marks, light columns, spirals, afterimages and slash arcs. Each is a
-- few pooled parts animated by ImpactEffects.shape (its clock, pool and quality level), so they
-- follow the playback speed and cost nothing once finished. Presentation only.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AbilityFxConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("AbilityFxConfig"))

local ImpactEffects = require(script.Parent.ImpactEffects)

local FxKit = {}

local TAU = 2 * math.pi
local FLAT = CFrame.Angles(0, 0, math.pi / 2) -- a cylinder's axis (X) upright: a flat disc
local ALONG = CFrame.Angles(0, math.pi / 2, 0) -- a cylinder's axis (X) along a CFrame's look
local BLACK = Color3.new(0, 0, 0)

local function fadeIn(progress: number, start: number): number
	return start + (1 - start) * progress
end

-- Transparency that holds at `start` until `hold`, then fades out.
local function holdFade(progress: number, start: number, hold: number): number
	if progress < hold then
		return start
	end
	return fadeIn((progress - hold) / (1 - hold), start)
end

-- A unit vector across `direction`, on the ground plane.
local function across(direction: Vector3): Vector3
	local flat = Vector3.new(direction.X, 0, direction.Z)
	if flat.Magnitude < 1e-3 then
		return Vector3.xAxis
	end
	local unit = flat.Unit
	return Vector3.new(-unit.Z, 0, unit.X) -- the ground-plane perpendicular
end

-- A block from `a` to `b`, `width` thick.
local function bar(a: Vector3, b: Vector3, width: number): (CFrame, Vector3)
	local length = (b - a).Magnitude
	return CFrame.lookAt((a + b) / 2, b), Vector3.new(width, width, math.max(length, 0.05))
end

-- Beams ---------------------------------------------------------------------------------------------

local function straight(from: Vector3, to: Vector3, color: Color3, width: number, duration: number, delay: number?)
	ImpactEffects.shape("Block", color, duration, function(part, progress)
		local cframe, size = bar(from, to, width * (1 - 0.7 * progress))
		part.CFrame = cframe
		part.Size = size
		part.Transparency = holdFade(progress, 0.05, 0.35)
	end, delay)
	-- A soft, wider glow around the core.
	ImpactEffects.shape("Block", color, duration * 0.7, function(part, progress)
		local cframe, size = bar(from, to, width * (2.2 - progress))
		part.CFrame = cframe
		part.Size = size
		part.Transparency = fadeIn(progress, 0.7)
	end, delay)
end

local function jagged(from: Vector3, to: Vector3, color: Color3, width: number, duration: number, delay: number?)
	local length = (to - from).Magnitude
	local segments = math.clamp(math.floor(length / 1.3), 3, 9)
	local side = across(to - from)
	for strand = 1, 2 do
		local points = { from }
		for i = 1, segments - 1 do
			local along = from:Lerp(to, i / segments)
			local offset = side * (math.random() - 0.5) * width * 2.6
				+ Vector3.yAxis * (math.random() - 0.5) * width * 1.6
			table.insert(points, along + offset)
		end
		table.insert(points, to)
		local thickness = if strand == 1 then width * 0.45 else width * 0.22
		for i = 1, #points - 1 do
			local a, b = points[i], points[i + 1]
			ImpactEffects.shape("Block", color, duration, function(part, progress)
				local cframe, size = bar(a, b, thickness)
				part.CFrame = cframe
				part.Size = size
				-- A crackling flicker while it fades.
				local flicker = if math.floor(progress * 10 + strand) % 2 == 0 then 0 else 0.45
				part.Transparency = math.min(1, holdFade(progress, 0, 0.3) + flicker * (1 - progress))
			end, delay)
		end
	end
end

local function spiral(from: Vector3, to: Vector3, color: Color3, width: number, duration: number, delay: number?)
	straight(from, to, color, width * 0.35, duration, delay)
	local length = (to - from).Magnitude
	local rings = math.clamp(math.floor(length / 1.1), 3, 10)
	local look = CFrame.lookAt(from, to)
	for i = 1, rings do
		local center = from:Lerp(to, i / (rings + 1))
		local turn = i * 0.7
		ImpactEffects.shape("Cylinder", color, duration * 0.8, function(part, progress)
			local diameter = width * (1.2 + 1.6 * progress)
			part.Size = Vector3.new(0.08, diameter, diameter)
			part.CFrame = CFrame.new(center) * look.Rotation * CFrame.Angles(0, 0, turn + progress * 3) * ALONG
			part.Transparency = fadeIn(progress, 0.35)
		end, (delay or 0) + i * 0.025)
	end
end

local function wisp(from: Vector3, to: Vector3, color: Color3, width: number, duration: number, delay: number?)
	local side = across(to - from)
	local segments = 8
	for strand = 1, 3 do
		local phase = strand * 2.1
		local amplitude = width * (0.6 + 0.3 * strand)
		for i = 1, segments do
			ImpactEffects.shape("Block", color, duration * 1.3, function(part, progress)
				local function point(k: number): Vector3
					local wave = math.sin(k * TAU * 1.5 + phase + progress * 8) * amplitude * math.sin(k * math.pi)
					return from:Lerp(to, k) + side * wave + Vector3.yAxis * wave * 0.4
				end
				local cframe, size = bar(point((i - 1) / segments), point(i / segments), width * 0.18)
				part.CFrame = cframe
				part.Size = size
				part.Transparency = holdFade(progress, 0.15, 0.4)
			end, (delay or 0) + i * 0.012)
		end
	end
end

-- A limb that shoots out from `from` to `to`, holds a moment and snaps back, with a fist on its tip.
local function stretch(from: Vector3, to: Vector3, color: Color3, width: number, duration: number, delay: number?)
	local function reach(progress: number): number
		if progress < 0.35 then
			return 1 - (1 - progress / 0.35) ^ 2
		elseif progress < 0.6 then
			return 1
		end
		return 1 - ((progress - 0.6) / 0.4) ^ 2
	end
	ImpactEffects.shape("Cylinder", color, duration, function(part, progress)
		local tip = from:Lerp(to, math.max(reach(progress), 0.02))
		local length = (tip - from).Magnitude
		part.Size = Vector3.new(math.max(length, 0.05), width * 0.5, width * 0.5)
		part.CFrame = CFrame.lookAt((from + tip) / 2, tip) * ALONG
		part.Transparency = 0
	end, delay, Enum.Material.SmoothPlastic)
	ImpactEffects.shape("Ball", color, duration, function(part, progress)
		part.Size = Vector3.one * width * 1.3
		part.CFrame = CFrame.new(from:Lerp(to, math.max(reach(progress), 0.02)))
		part.Transparency = 0
	end, delay, Enum.Material.SmoothPlastic)
end

-- A crescent slash that travels from `from` to `to` and fades.
function FxKit.wave(from: Vector3, to: Vector3, color: Color3, width: number, duration: number, delay: number?)
	local travel = AbilityFxConfig.waveSpeed
	local look = CFrame.lookAt(from, to).Rotation
	for layer = 1, 2 do
		local spread = if layer == 1 then 3.4 else 2.2
		local lag = (layer - 1) * 0.04
		ImpactEffects.shape("Block", color, math.max(duration, travel + 0.15), function(part, progress)
			local total = math.max(duration, travel + 0.15)
			local moved = math.clamp(progress * total / travel, 0, 1)
			local center = from:Lerp(to, moved)
			part.Size = Vector3.new(width * spread, 0.12, width * 0.6)
			part.CFrame = CFrame.new(center) * look * CFrame.Angles(0, 0, 0.25)
			part.Transparency = if moved < 1 then 0.1 * layer else fadeIn((progress * total - travel) / 0.15, 0.2)
		end, (delay or 0) + lag)
	end
end

-- A beam from `from` to `to` in `style` (AbilityFxConfig.elements `beam`).
function FxKit.beam(
	from: Vector3,
	to: Vector3,
	color: Color3,
	width: number,
	duration: number,
	style: string,
	delay: number?
)
	if (to - from).Magnitude < 0.1 then
		return
	end
	if style == "jagged" then
		jagged(from, to, color, width, duration, delay)
	elseif style == "wave" then
		FxKit.wave(from, to, color, width, duration, delay)
	elseif style == "spiral" then
		spiral(from, to, color, width, duration, delay)
	elseif style == "wisp" then
		wisp(from, to, color, width, duration, delay)
	elseif style == "stretch" then
		stretch(from, to, color, width, duration, delay)
	else
		straight(from, to, color, width, duration, delay)
	end
end

-- Areas ---------------------------------------------------------------------------------------------

-- A cone sweep: blades fan out from `origin` across `halfAngle` (radians) on each side of
-- `direction`, `radius` studs long, one after another.
function FxKit.sweep(
	origin: Vector3,
	direction: Vector3,
	halfAngle: number,
	radius: number,
	color: Color3,
	duration: number,
	delay: number?
)
	local flat = Vector3.new(direction.X, 0, direction.Z)
	if flat.Magnitude < 1e-3 then
		return
	end
	local yaw = math.atan2(-flat.X, -flat.Z)
	local blades = 7
	local sweepTime = duration * 0.45
	for i = 1, blades do
		local angle = yaw - halfAngle + (i - 1) / (blades - 1) * 2 * halfAngle
		local base = CFrame.new(origin) * CFrame.Angles(0, angle, 0)
		ImpactEffects.shape("Block", color, duration - sweepTime * 0.5, function(part, progress)
			local length = radius * (0.55 + 0.45 * math.min(1, progress * 4))
			part.Size = Vector3.new(0.18 + 0.4 * (1 - progress), 0.1, length)
			part.CFrame = base * CFrame.new(0, 0, -length / 2)
			part.Transparency = holdFade(progress, 0.1, 0.25)
		end, (delay or 0) + (i - 1) / (blades - 1) * sweepTime)
	end
	-- A thin fan on the ground under the sweep.
	for i = 1, 3 do
		local angle = yaw - halfAngle * 0.66 + (i - 1) * halfAngle * 0.66
		local base = CFrame.new(origin + Vector3.new(0, 0.05, 0)) * CFrame.Angles(0, angle, 0)
		ImpactEffects.shape("Block", color, duration, function(part, progress)
			local width = 2 * radius * math.tan(halfAngle / 2) * (0.6 + 0.4 * progress)
			part.Size = Vector3.new(width, 0.05, radius)
			part.CFrame = base * CFrame.new(0, 0, -radius / 2)
			part.Transparency = fadeIn(progress, 0.6)
		end, (delay or 0) + sweepTime * 0.3)
	end
end

-- A flat disc on the ground, `diameter` across, fading from `start` transparency.
function FxKit.disc(
	position: Vector3,
	color: Color3,
	diameter: number,
	duration: number,
	start: number?,
	delay: number?
)
	ImpactEffects.shape("Cylinder", color, duration, function(part, progress)
		local grown = diameter * (0.7 + 0.3 * math.min(1, progress * 4))
		part.Size = Vector3.new(0.06, grown, grown)
		part.CFrame = CFrame.new(position + Vector3.new(0, 0.07, 0)) * FLAT
		part.Transparency = holdFade(progress, start or 0.35, 0.5)
	end, delay, Enum.Material.SmoothPlastic)
end

-- A ring that swells on the ground (a disc, see-through), `diameter` at the end.
function FxKit.ring(position: Vector3, color: Color3, diameter: number, duration: number, delay: number?)
	ImpactEffects.shape("Cylinder", color, duration, function(part, progress)
		local grown = diameter * (0.25 + 0.75 * (1 - (1 - progress) ^ 2))
		part.Size = Vector3.new(0.08, grown, grown)
		part.CFrame = CFrame.new(position + Vector3.new(0, 0.12, 0)) * FLAT
		part.Transparency = fadeIn(progress, 0.3)
	end, delay)
end

-- A ground mark of `style` (AbilityFxConfig.elements `ground`) with `radius` studs.
function FxKit.mark(
	position: Vector3,
	color: Color3,
	accent: Color3,
	radius: number,
	style: string,
	duration: number,
	delay: number?
)
	if style == "crack" then
		local dark = color:Lerp(BLACK, 0.7)
		local cracks = 7
		for i = 1, cracks do
			local angle = (i + math.random() * 0.6) / cracks * TAU
			local length = radius * (0.55 + math.random() * 0.45)
			local base = CFrame.new(position + Vector3.new(0, 0.08, 0)) * CFrame.Angles(0, angle, 0)
			ImpactEffects.shape("Block", dark, duration, function(part, progress)
				local grown = length * math.min(1, progress * 6)
				part.Size = Vector3.new(0.16, 0.05, math.max(grown, 0.05))
				part.CFrame = base * CFrame.new(0, 0, -grown / 2)
				part.Transparency = holdFade(progress, 0.05, 0.6)
			end, delay, Enum.Material.Slate)
		end
		FxKit.disc(position, dark, radius * 0.7, duration, 0.4, delay)
	elseif style == "scorch" then
		FxKit.disc(position, color:Lerp(BLACK, 0.75), radius * 2, duration, 0.3, delay)
		FxKit.disc(position, color, radius * 0.9, duration * 0.5, 0.4, delay)
	elseif style == "splash" then
		FxKit.disc(position, color, radius * 2, duration, 0.5, delay)
		FxKit.ring(position, accent, radius * 2.4, duration * 0.6, delay)
	elseif style == "glyph" then
		FxKit.disc(position, color, radius * 2, duration, 0.6, delay)
		for i = 1, 2 do
			ImpactEffects.shape("Block", if i == 1 then color else accent, duration, function(part, progress)
				local side = radius * (1.15 - 0.25 * i)
				part.Size = Vector3.new(side, 0.05, side)
				part.CFrame = CFrame.new(position + Vector3.new(0, 0.1 + i * 0.02, 0))
					* CFrame.Angles(0, (i * 0.785) + progress * (if i == 1 then 2 else -2), 0)
				part.Transparency = holdFade(progress, 0.45, 0.5)
			end, delay)
		end
	elseif style == "clock" then
		FxKit.disc(position, color, radius * 2, duration, 0.55, delay)
		for i = 1, 2 do
			local length = radius * (if i == 1 then 0.85 else 0.55)
			ImpactEffects.shape("Block", accent, duration, function(part, progress)
				local angle = progress * TAU * (if i == 1 then 1.5 else 0.25)
				part.Size = Vector3.new(0.14, 0.06, length)
				part.CFrame = CFrame.new(position + Vector3.new(0, 0.12, 0))
					* CFrame.Angles(0, -angle, 0)
					* CFrame.new(0, 0, -length / 2)
				part.Transparency = holdFade(progress, 0.05, 0.6)
			end, delay)
		end
	elseif style == "rings" then
		for i = 1, 3 do
			FxKit.ring(
				position,
				if i == 2 then accent else color,
				radius * 2 * (0.5 + 0.25 * i),
				duration * 0.6,
				(delay or 0) + i * 0.08
			)
		end
	elseif style == "smoke" then
		ImpactEffects.burst("smoke", position + Vector3.new(0, 0.3, 0), nil, {
			color = color:Lerp(BLACK, 0.4),
			color2 = accent,
			count = math.clamp(math.floor(radius * 3), 4, 16),
			size = 0.9,
			speed = { radius * 0.8, radius * 1.6 },
			lifetime = { 0.5, 0.9 },
			transparency = 0.3,
		})
	end
end

-- A column of light rising from `position`, `height` tall.
function FxKit.column(position: Vector3, color: Color3, height: number, width: number, duration: number, delay: number?)
	ImpactEffects.shape("Cylinder", color, duration, function(part, progress)
		local rise = math.min(1, progress * 4)
		local grown = height * rise
		part.Size = Vector3.new(math.max(grown, 0.05), width * (1 - 0.6 * progress), width * (1 - 0.6 * progress))
		part.CFrame = CFrame.new(position + Vector3.new(0, grown / 2, 0)) * FLAT
		part.Transparency = holdFade(progress, 0.25, 0.4)
	end, delay)
end

-- A helix of small orbs rising around `position` (wind, spin).
function FxKit.spiral(
	position: Vector3,
	color: Color3,
	radius: number,
	height: number,
	duration: number,
	delay: number?
)
	local orbs = 8
	for i = 1, orbs do
		local offset = (i - 1) / orbs
		ImpactEffects.shape("Ball", color, duration, function(part, progress)
			local t = math.clamp(progress * 1.4 - offset * 0.4, 0, 1)
			local angle = (offset + t * 1.5) * TAU
			local r = radius * (1 - 0.4 * t)
			part.Size = Vector3.one * (0.35 * (1 - 0.5 * t))
			part.CFrame = CFrame.new(position + Vector3.new(math.cos(angle) * r, height * t, math.sin(angle) * r))
			part.Transparency = fadeIn(t, 0.1)
		end, delay)
	end
end

-- An afterimage of a unit: a see-through block of `size` at `cframe`.
function FxKit.ghost(cframe: CFrame, size: Vector3, color: Color3, duration: number, delay: number?)
	ImpactEffects.shape("Block", color, duration, function(part, progress)
		part.Size = size * (1 - 0.15 * progress)
		part.CFrame = cframe
		part.Transparency = fadeIn(progress, 0.55)
	end, delay)
end

-- A blade arc: a crescent of short blocks across `center`, facing along `facing`, tilted `tilt`
-- radians from level, `size` studs across.
function FxKit.slashArc(
	center: Vector3,
	facing: Vector3,
	color: Color3,
	size: number,
	tilt: number,
	duration: number,
	delay: number?
)
	local flat = Vector3.new(facing.X, 0, facing.Z)
	local look = if flat.Magnitude > 1e-3 then CFrame.lookAt(center, center + flat).Rotation else CFrame.identity
	local pieces = 6
	for i = 1, pieces do
		local a = -0.9 + (i - 1) / (pieces - 1) * 1.8
		local b = -0.9 + i / (pieces - 1) * 1.8
		ImpactEffects.shape("Block", color, duration, function(part, progress)
			local drawn = math.min(1, progress * 5)
			if (i - 1) / pieces > drawn then
				part.Transparency = 1
				return
			end
			local function at(angle: number): Vector3
				return Vector3.new(math.sin(angle) * size / 2, 0, -math.cos(angle) * size * 0.25)
			end
			local frame = CFrame.new(center) * look * CFrame.Angles(0, 0, tilt)
			local pa, pb = frame:PointToWorldSpace(at(a)), frame:PointToWorldSpace(at(b))
			local cframe, partSize = bar(pa, pb, 0.12 * (1 - 0.5 * progress) + 0.06)
			part.CFrame = cframe
			part.Size = partSize
			part.Transparency = holdFade(progress, 0, 0.35)
		end, delay)
	end
end

-- Discs across a line (a pressure cone): each wider than the last, from `from` along `direction`.
function FxKit.pressureCone(
	from: Vector3,
	direction: Vector3,
	length: number,
	halfAngle: number,
	color: Color3,
	duration: number,
	delay: number?
)
	if direction.Magnitude < 1e-3 then
		return
	end
	local unit = direction.Unit
	local discs = 6
	for i = 1, discs do
		local distance = length * i / discs
		local center = from + unit * distance
		local diameter = 0.6 + 2 * distance * math.tan(halfAngle)
		ImpactEffects.shape("Cylinder", color, duration, function(part, progress)
			local grown = diameter * (0.6 + 0.4 * progress)
			part.Size = Vector3.new(0.1, grown, grown)
			part.CFrame = CFrame.lookAt(center, center + unit) * ALONG
			part.Transparency = fadeIn(progress, 0.35 + 0.08 * i)
		end, (delay or 0) + i * 0.025)
	end
end

return FxKit
