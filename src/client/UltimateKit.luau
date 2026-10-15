-- Building blocks for signature ultimates (Ultimates/<unit id>): parts that live over a span of an
-- ultimate's design time (Cinematic), following the caster's hands or any moving point, and a few
-- composed pieces (an orb, particles drawn in or pushed out, a growing shell, a ground groove,
-- drifting motes). All of them are pooled ImpactEffects shapes on the effects' clock, so they follow
-- slow motion and fast-forward and cost nothing once finished. Presentation only.

local ImpactEffects = require(script.Parent.ImpactEffects)

local UltimateKit = {}

UltimateKit.WHITE = Color3.new(1, 1, 1)
UltimateKit.BLACK = Color3.new(0, 0, 0)
UltimateKit.DUST = Color3.fromRGB(196, 186, 168)

local FLAT = CFrame.Angles(0, 0, math.pi / 2)

function UltimateKit.smooth(t: number): number
	t = math.clamp(t, 0, 1)
	return t * t * (3 - 2 * t)
end
function UltimateKit.easeIn(t: number): number
	t = math.clamp(t, 0, 1)
	return t * t
end
function UltimateKit.easeOut(t: number): number
	t = math.clamp(t, 0, 1)
	return 1 - (1 - t) * (1 - t)
end

-- A part that lives from design time `from` to `to` of `run` (compressed before the release like
-- the rest of the anticipation). `step(part, u)` sets it each frame, `u` 0-1 across the span.
function UltimateKit.live(
	run: any,
	from: number,
	to: number,
	shape: string,
	color: Color3,
	step: (BasePart, number) -> (),
	material: Enum.Material?
)
	local now = run:now()
	local startAt, endAt = run:time(from), run:time(to)
	local delay = math.max(0, startAt - now)
	local duration = math.max(0.03, endAt - math.max(startAt, now))
	ImpactEffects.shape(shape, color, duration, step, delay, material)
end

-- A glowing orb at `where()` from `from` to `to`, `size(u)` studs across, pulsing a little: a
-- bright core inside a soft, larger halo of the same color.
function UltimateKit.orb(
	run: any,
	from: number,
	to: number,
	color: Color3,
	where: () -> Vector3,
	size: (number) -> number,
	transparency: ((number) -> number)?
)
	UltimateKit.live(run, from, to, "Ball", color:Lerp(UltimateKit.WHITE, 0.35), function(part, u)
		local pulse = 1 + 0.08 * math.sin(run:now() * 38)
		part.Size = Vector3.one * math.max(0.05, size(u) * pulse)
		part.CFrame = CFrame.new(where())
		part.Transparency = if transparency then transparency(u) else 0.05
	end)
	UltimateKit.live(run, from, to, "Ball", color, function(part, u)
		local pulse = 1 + 0.15 * math.sin(run:now() * 23 + 1)
		part.Size = Vector3.one * math.max(0.05, size(u) * 1.9 * pulse)
		part.CFrame = CFrame.new(where())
		local base = if transparency then transparency(u) else 0.05
		part.Transparency = 0.6 + 0.4 * base
	end)
end

-- `count` small motes drawn in from `radius` studs around `center()` over the span (each takes
-- `travel` real seconds), the way a pull looks. `outward` pushes them out from the center instead.
function UltimateKit.converge(
	run: any,
	from: number,
	to: number,
	center: () -> Vector3,
	color: Color3,
	radius: number,
	count: number,
	outward: boolean?,
	travel: number?
)
	local span = run:time(to) - run:time(from)
	local life = travel or 0.28
	for i = 1, count do
		local direction = Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5)
		direction = if direction.Magnitude > 1e-3 then direction.Unit else Vector3.yAxis
		local delay = math.max(0, run:time(from) - run:now()) + (i - 1) / count * math.max(0, span - life)
		ImpactEffects.shape("Ball", color, life, function(part, u)
			local k = if outward then UltimateKit.easeOut(u) else 1 - UltimateKit.easeIn(u)
			part.Size = Vector3.one * (0.22 * (if outward then 1 - u * 0.6 else 0.5 + u * 0.5))
			part.CFrame = CFrame.new(center() + direction * radius * k)
			part.Transparency = if outward then 0.1 + 0.85 * u else 0.6 - 0.5 * u
		end, delay)
	end
end

-- A see-through shell growing at `center` from `from` to `to` design seconds, `size(u)` across.
function UltimateKit.shell(
	run: any,
	from: number,
	to: number,
	color: Color3,
	center: Vector3,
	size: (number) -> number,
	transparency: (number) -> number,
	material: Enum.Material?
)
	UltimateKit.live(run, from, to, "Ball", color, function(part, u)
		part.Size = Vector3.one * math.max(0.05, size(u))
		part.CFrame = CFrame.new(center)
		part.Transparency = transparency(u)
	end, material)
end

-- A glowing groove on the ground from `a` to `b` (ground points), `width` studs, held then faded.
function UltimateKit.groove(run: any, from: number, to: number, color: Color3, a: Vector3, b: Vector3, width: number)
	local flatA = Vector3.new(a.X, a.Y + 0.06, a.Z)
	local flatB = Vector3.new(b.X, flatA.Y, b.Z)
	local length = (flatB - flatA).Magnitude
	if length < 0.1 then
		return
	end
	local frame = CFrame.lookAt((flatA + flatB) / 2, flatB)
	UltimateKit.live(run, from, to, "Block", color, function(part, u)
		local drawn = math.min(1, u * 8)
		part.Size = Vector3.new(width * (1 - 0.5 * u), 0.05, length * drawn)
		part.CFrame = frame * CFrame.new(0, 0, length * (1 - drawn) / 2)
		part.Transparency = 0.15 + 0.85 * UltimateKit.easeIn(u)
	end)
end

-- A flat disc on the ground at `center`, `diameter(u)` across, `transparency(u)`.
function UltimateKit.pool(
	run: any,
	from: number,
	to: number,
	color: Color3,
	center: Vector3,
	diameter: (number) -> number,
	transparency: (number) -> number,
	material: Enum.Material?
)
	UltimateKit.live(run, from, to, "Cylinder", color, function(part, u)
		local d = math.max(0.05, diameter(u))
		part.Size = Vector3.new(0.05, d, d)
		part.CFrame = CFrame.new(center + Vector3.new(0, 0.05, 0)) * FLAT
		part.Transparency = transparency(u)
	end, material or Enum.Material.SmoothPlastic)
end

-- A block set each frame from `u`: its CFrame, size and transparency.
function UltimateKit.block(
	run: any,
	from: number,
	to: number,
	color: Color3,
	frame: (number) -> CFrame,
	size: (number) -> Vector3,
	transparency: (number) -> number,
	material: Enum.Material?
)
	UltimateKit.live(run, from, to, "Block", color, function(part, u)
		part.Size = size(u)
		part.CFrame = frame(u)
		part.Transparency = transparency(u)
	end, material)
end

-- A held beam from `a()` to `b()` (moving points), `width(u)` thick: a bright core in a wider glow.
function UltimateKit.beam(
	run: any,
	from: number,
	to: number,
	core: Color3,
	glow: Color3,
	a: () -> Vector3,
	b: () -> Vector3,
	width: (number) -> number
)
	for layer = 1, 2 do
		UltimateKit.live(run, from, to, "Cylinder", if layer == 1 then core else glow, function(part, u)
			local p, q = a(), b()
			local length = math.max((q - p).Magnitude, 0.05)
			local w = math.max(0.05, width(u) * (if layer == 1 then 1 else 2.2))
			part.Size = Vector3.new(length, w, w)
			part.CFrame = CFrame.lookAt((p + q) / 2, q) * CFrame.Angles(0, math.pi / 2, 0)
			part.Transparency = if layer == 1 then 0.05 + 0.9 * UltimateKit.easeIn(u) else 0.55 + 0.45 * u
		end)
	end
end

-- `count` thin slash flashes across a disc of `radius` around `center`, each a blink, spread over
-- the span: an area filling with cuts. `colors` alternate.
function UltimateKit.slashes(
	run: any,
	from: number,
	to: number,
	center: Vector3,
	radius: number,
	count: number,
	colors: { Color3 },
	height: number?
)
	local span = run:time(to) - run:time(from)
	local start = math.max(0, run:time(from) - run:now())
	for i = 1, count do
		local angle = math.random() * 2 * math.pi
		local r = radius * math.sqrt(math.random())
		local at = center
			+ Vector3.new(math.cos(angle) * r, (height or 1.4) * (0.3 + math.random()), math.sin(angle) * r)
		local frame = CFrame.new(at)
			* CFrame.Angles(0, math.random() * math.pi * 2, 0)
			* CFrame.Angles(0, 0, (math.random() - 0.5) * 1.8)
		local length = radius * (0.5 + math.random() * 0.6)
		local color = colors[(i - 1) % #colors + 1]
		ImpactEffects.shape("Block", color, 0.12, function(part, u)
			part.Size = Vector3.new(length * (0.6 + 0.4 * u), 0.08, 0.08)
			part.CFrame = frame
			part.Transparency = u * 0.9
		end, start + (i - 1) / count * span)
	end
end

-- Spiky aura flames rising around the caster from `from` to `to`: `count` thin spikes at the waist,
-- each licking up and fading in turn, `height(u)` studs tall.
function UltimateKit.aura(run: any, from: number, to: number, color: Color3, count: number, height: (number) -> number)
	for i = 1, count do
		local angle = (i - 1) / count * 2 * math.pi
		local phase = (i * 0.37) % 1
		UltimateKit.live(run, from, to, "Block", color, function(part, u)
			local base = run:ground()
			local radius = run.view.part.Size.X * 0.55
			local flicker = (run:now() * 3 + phase) % 1
			local tall = height(u) * (0.5 + 0.5 * math.sin(flicker * math.pi))
			local foot = base + Vector3.new(math.cos(angle) * radius, 0.2, math.sin(angle) * radius)
			part.Size = Vector3.new(0.14, math.max(tall, 0.05), 0.14)
			part.CFrame = CFrame.new(foot + Vector3.new(0, tall / 2, 0)) * CFrame.Angles(0, -angle, 0.12)
			part.Transparency = 0.25 + 0.6 * flicker
		end)
	end
end

-- Wind streaks: `count` long thin lines shooting from `origin` along `direction` (ground plane),
-- spread across `width` studs, `length` studs long, starting at design time `at`.
function UltimateKit.streaks(
	run: any,
	at: number,
	origin: Vector3,
	direction: Vector3,
	count: number,
	length: number,
	width: number,
	color: Color3
)
	local flat = Vector3.new(direction.X, 0, direction.Z)
	if flat.Magnitude < 1e-3 then
		return
	end
	flat = flat.Unit
	local side = Vector3.new(-flat.Z, 0, flat.X)
	for _ = 1, count do
		local offset = side * (math.random() - 0.5) * width + Vector3.new(0, 0.4 + math.random() * 2.4, 0)
		local reach = length * (0.6 + math.random() * 0.4)
		local lag = math.random() * 0.08
		UltimateKit.live(run, at + lag, at + lag + 0.35, "Block", color, function(part, u)
			local tip = origin + offset + flat * reach * UltimateKit.easeOut(u)
			local tail = origin + offset + flat * reach * UltimateKit.easeIn(u)
			local span = math.max((tip - tail).Magnitude, 0.05)
			part.Size = Vector3.new(0.07, 0.07, span)
			part.CFrame = CFrame.lookAt((tip + tail) / 2, tip + flat * 0.01)
			part.Transparency = 0.2 + 0.7 * u
		end)
	end
end

-- Motes drifting up from a disc of `radius` around `center`, a few at a time, from `from` to `to`.
function UltimateKit.drift(
	run: any,
	from: number,
	to: number,
	color: Color3,
	center: Vector3,
	radius: number,
	every: number
)
	local t = from
	while t < to do
		run:at(t, function()
			local angle = math.random() * 2 * math.pi
			local r = radius * math.sqrt(math.random())
			ImpactEffects.burst(
				"mote",
				center + Vector3.new(math.cos(angle) * r, 0.3, math.sin(angle) * r),
				Vector3.yAxis,
				{
					color = color,
					count = 4,
					size = 0.28,
					speed = { 1, 2.5 },
					lifetime = { 0.6, 1 },
					spread = 25,
					transparency = 0.2,
				}
			)
		end)
		t += every
	end
end

return UltimateKit
