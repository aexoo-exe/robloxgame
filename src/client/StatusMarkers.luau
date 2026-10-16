-- Readable markers on units with a status (AbilityFxConfig.statuses): slow, weaken, curse, shred,
-- wound, burn, poison and a hunter mark. Each is a few parts or one emitter made on first use and
-- shown until its time runs out; UnitView.update places them every frame (StatusMarkers.update).
-- Stuns keep their own halo and stars (UnitView). Presentation only.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AbilityFxConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("AbilityFxConfig"))

local ImpactEffects = require(script.Parent.ImpactEffects)

local StatusMarkers = {}

local TAU = 2 * math.pi
local FLAT = CFrame.Angles(0, 0, math.pi / 2)

type Marker = {
	untilTime: number,
	parts: { BasePart },
	emitter: ParticleEmitter?,
	shown: boolean,
}

-- Anything with a `part` (the hitbox) and a `figure` with a `height`: a UnitView.
type Holder = { part: BasePart, figure: { height: number }, markers: { [string]: Marker }? }

local function newPart(parent: Instance, shape: Enum.PartType, color: Color3): Part
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Shape = shape
	part.Material = Enum.Material.Neon
	part.Color = color
	part.Transparency = 1
	part.Parent = parent
	return part
end

local function newEmitter(holder: Holder, texture: string, color: Color3, height: number, rise: number): ParticleEmitter
	local attachment = Instance.new("Attachment")
	attachment.Position = Vector3.new(0, -holder.part.Size.Y * 0.1, 0)
	attachment.Parent = holder.part
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = texture
	emitter.Color = ColorSequence.new(color)
	emitter.LightEmission = 0.6
	emitter.LightInfluence = 0
	emitter.Size = NumberSequence.new(height * 0.09, height * 0.03)
	emitter.Transparency = NumberSequence.new(0.2, 1)
	emitter.Lifetime = NumberRange.new(0.5, 0.8)
	emitter.Speed = NumberRange.new(rise * 0.5, rise)
	emitter.SpreadAngle = Vector2.new(25, 25)
	emitter.EmissionDirection = Enum.NormalId.Top
	emitter.Shape = Enum.ParticleEmitterShape.Box
	emitter.Rate = 0
	emitter.Enabled = false
	emitter.Parent = attachment
	return emitter
end

local TEXTURES = {
	wisps = "rbxasset://textures/particles/smoke_main.dds",
	flames = "rbxasset://textures/particles/fire_main.dds",
	bubbles = "rbxasset://textures/particles/forcefield_glow_main.dds",
}

local function build(holder: Holder, status: string): Marker
	local config = AbilityFxConfig.statuses[status]
	local height = holder.figure.height
	local marker: Marker = { untilTime = -math.huge, parts = {}, emitter = nil, shown = false }
	local shape = config.shape
	if TEXTURES[shape] then
		local emitter =
			newEmitter(holder, TEXTURES[shape], config.color, height, if shape == "flames" then 2.2 else 1.4)
		emitter.Rate = 14 * ImpactEffects.particleShare()
		if shape == "wisps" then
			emitter.LightEmission = 0
			emitter.Size = NumberSequence.new(height * 0.08, height * 0.16)
		end
		marker.emitter = emitter
	elseif shape == "ring" or shape == "reticle" then
		table.insert(marker.parts, newPart(holder.part, Enum.PartType.Cylinder, config.color))
		if shape == "reticle" then
			for _ = 1, 4 do
				table.insert(marker.parts, newPart(holder.part, Enum.PartType.Block, config.color))
			end
		end
	else
		-- chevron and cross: two bars; shards: three.
		for _ = 1, if shape == "shards" then 3 else 2 do
			table.insert(marker.parts, newPart(holder.part, Enum.PartType.Block, config.color))
		end
	end
	return marker
end

-- Shows `status`'s marker on a unit until `untilTime` (its clock); a later time extends it.
function StatusMarkers.add(holder: Holder, status: string, untilTime: number)
	if not AbilityFxConfig.statuses[status] then
		return
	end
	local markers = holder.markers
	if not markers then
		markers = {}
		holder.markers = markers
	end
	local m = markers :: { [string]: Marker }
	local marker = m[status]
	if not marker then
		marker = build(holder, status)
		m[status] = marker
	end
	marker.untilTime = math.max(marker.untilTime, untilTime)
end

local function hide(marker: Marker)
	for _, part in marker.parts do
		part.Transparency = 1
	end
	if marker.emitter then
		marker.emitter.Enabled = false
	end
	marker.shown = false
end

-- Places the markers for this frame (`root`: the figure's feet; `hidden`: dying or gone).
function StatusMarkers.update(holder: Holder, now: number, root: CFrame, hidden: boolean)
	local markers = holder.markers
	if not markers then
		return
	end
	local height = holder.figure.height
	for status, marker in markers do
		local on = not hidden and now < marker.untilTime
		if not on then
			if marker.shown then
				hide(marker)
			end
			continue
		end
		marker.shown = true
		local shape = AbilityFxConfig.statuses[status].shape
		local parts = marker.parts
		if marker.emitter then
			marker.emitter.Enabled = true
		elseif shape == "ring" then
			local diameter = height * 0.55
			parts[1].Size = Vector3.new(0.06, diameter, diameter)
			parts[1].CFrame = root * CFrame.new(0, 0.12 + 0.05 * math.sin(now * 4), 0) * FLAT
			parts[1].Transparency = 0.45
		elseif shape == "reticle" then
			local diameter = height * 0.22
			local head = root * CFrame.new(0, height * 1.12, 0) * CFrame.Angles(0, now * 1.5, 0)
			parts[1].Size = Vector3.new(0.05, diameter, diameter)
			parts[1].CFrame = head * FLAT
			parts[1].Transparency = 0.55
			for i = 2, 5 do
				local angle = (i - 2) / 4 * TAU
				parts[i].Size = Vector3.new(0.06, 0.06, diameter * 0.35)
				parts[i].CFrame = head * CFrame.Angles(0, angle, 0) * CFrame.new(0, 0, -diameter * 0.55)
				parts[i].Transparency = 0
			end
		elseif shape == "chevron" then
			-- A downward arrow over the head, bobbing.
			local head = root * CFrame.new(0, height * 1.15 + 0.06 * math.sin(now * 5), 0)
			local length = height * 0.1
			for i, part in parts do
				local side = if i == 1 then 1 else -1
				part.Size = Vector3.new(0.08, length, 0.08)
				part.CFrame = head * CFrame.new(side * length * 0.32, 0, 0) * CFrame.Angles(0, 0, side * 0.7)
				part.Transparency = 0.1
			end
		elseif shape == "shards" then
			local waist = root * CFrame.new(0, height * 0.45, 0)
			for i, part in parts do
				local angle = now * 3 + (i - 1) / #parts * TAU
				part.Size = Vector3.new(0.1, height * 0.08, 0.18)
				part.CFrame = waist
					* CFrame.new(math.cos(angle) * height * 0.32, 0, math.sin(angle) * height * 0.32)
					* CFrame.Angles(0.5, angle, 0.4)
				part.Transparency = 0.05
			end
		elseif shape == "cross" then
			local head = root * CFrame.new(0, height * 1.15, 0) * CFrame.Angles(0, now * 0.8, 0)
			for i, part in parts do
				part.Size = Vector3.new(0.08, height * 0.13, 0.08)
				part.CFrame = head * CFrame.Angles(0, 0, if i == 1 then 0.785 else -0.785)
				part.Transparency = 0.05
			end
		end
	end
end

return StatusMarkers
