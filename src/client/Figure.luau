-- A unit's figure: a catalog avatar when the unit has one ready (UnitAvatarConfig, UnitAvatars),
-- else a hand-built look when the unit has one (UnitLookConfig, built by LookKit), else a
-- placeholder humanoid built from parts (FigureConfig), or a finished model when its SkinConfig
-- entry names one, plus the cost ring and, for a mounted rider, a horse. Presentation only.
-- A catalog avatar is an R6 rig whose parts ride the same anchors as any figure, so it takes every
-- pose; its clothing is textured, so hit flashes, cast glows and selection show as a Highlight.
--
-- Every piece is an anchored part that cannot be clicked (the unit's invisible hitbox takes clicks
-- and carries the info board) and casts no shadow. A piece hangs from a named anchor (root, hips,
-- head, an arm, a hand, a leg, the horse ...): Figure.place works out the anchors from a pose and
-- moves every piece at once with one BulkMoveTo, so a figure costs one call per frame.
-- A figure stands on its root (the ground point under the unit) and faces -Z.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local FigureConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("FigureConfig"))
local HorseLookConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("HorseLookConfig"))

local UnitModels = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("UnitModels")

local HorseKit = require(script.Parent.HorseKit)
local LookKit = require(script.Parent.LookKit)
local UnitAvatars = require(script.Parent.UnitAvatars)

local Figure = {}

-- What to build. Roster units have a class look and a ring; creeps, bosses and summons have neither.
export type Look = {
	style: string, -- "roster", "summon", "creep" or "boss"
	classLook: any?, -- a FigureConfig.classes entry (its hand and arm angles; its prop unless unitLook)
	ringColor: Color3?, -- cost ring under the unit
	model: string?, -- SkinConfig `model`: a Model in ReplicatedStorage.CharacterModels
	bulk: number?, -- extra width (FigureConfig.characters)
	attackPose: string?, -- "recoil" or "point" for ranged attacks (FigureConfig.characters)
	unitLook: any?, -- a UnitLookConfig entry: drawn with LookKit instead of the placeholder
	detail: string?, -- "low" leaves out a look's fine details (hub statues)
	avatar: string?, -- unit id of a catalog avatar (UnitAvatarConfig); used once it is ready
	avatarProp: boolean?, -- false: an avatar holds no class prop (UnitAvatarConfig `prop`)
	avatarWeapons: { any }?, -- LookKit weapons worn with an avatar (UnitAvatarConfig `weapons`)
	avatarOutfit: any?, -- LookKit clothing layered on an avatar (UnitAvatarConfig `outfit`)
	modelKey: string?, -- a vetted store model's data (UnitModelConfig, src/shared/UnitModels)
	modelOutfit: any?, -- LookKit pieces added on top of that model (UnitModelConfig `outfit`)
	formModels: { [string]: any }?, -- the unit's forms drawn as store models (UnitModelConfig `forms`)
	unitType: string?, -- the roster unit drawn (CharacterLook), for its form looks
	formLooks: { [string]: any }?, -- the unit's per-form looks (FormLookConfig), by form name
}

-- One frame's posture. Angles are in radians; arms and legs are raised forward from hanging.
export type Pose = {
	bob: number, -- studs up
	lean: number, -- forward (negative leans back)
	fall: number, -- backward about the feet
	leftArm: number,
	rightArm: number,
	leftLeg: number,
	rightLeg: number,
	stride: number, -- horse legs
	-- Optional (nil: 0), for combat motion (UnitMotion):
	twist: number?, -- upper body turned about the vertical (positive: the right shoulder forward)
	crouch: number?, -- hips dropped by this fraction of leg length, legs splayed to match (a squash)
	tilt: number?, -- sideways, about the feet (positive: toward the figure's right)
	leftArmOut: number?, -- each arm raised out to its side (radians; ultimate pose keys)
	rightArmOut: number?,
}

type Piece = {
	part: BasePart,
	anchor: string,
	offset: CFrame,
	transparency: number, -- the part's own transparency (models), faded on top of
	horse: boolean?,
	drawn: boolean?, -- part of a weapon drawn only while it is out (Figure.setDrawn)
}

export type Figure = {
	height: number,
	body: { [string]: number }, -- proportions in studs
	lean: number, -- resting lean (radians)
	restArms: { number }, -- resting arm angles { left, right } (radians)
	headOffset: CFrame,
	pieces: { Piece },
	parts: { BasePart }, -- the pieces' parts, in order, for BulkMoveTo
	cframes: { CFrame },
	tinted: { BasePart }, -- body parts recolored by hit flashes, cast glows and selection
	-- A look's tinted parts keep their own colors and materials to return to. Parts not listed
	-- return to `color` (placeholders: one body color).
	baseColors: { [BasePart]: Color3 },
	baseMaterials: { [BasePart]: Enum.Material },
	formTint: Color3?, -- a form's tint (RenderConfig.formLooks), blended into a look's own colors
	unitLook: any?,
	avatar: Model?, -- the catalog avatar's model, if the figure is one
	highlight: Highlight?, -- an avatar's flash, glow and selection (made on first use)
	decals: { { decal: Decal, transparency: number } }, -- faded with the parts (an avatar's face)
	emitters: { ParticleEmitter }, -- a look's steam; off while the figure is fading away
	modelKey: string?, -- the store model drawn, if the figure is one (UnitModels)
	modelFront: any?, -- that model's face clue { by, z, turned } (z < 0: it faces the front)
	unitType: string?, -- the roster unit drawn (its horse's colors: HorseLookConfig)
	color: Color3,
	transparency: number,
	weaponOut: boolean, -- drawn weapons (LookKit `drawn`) show only while this is on
	isModel: boolean,
	horse: { seat: number, bodyY: number, joints: { Vector3 } }?,
	anchors: { [string]: CFrame },
}

local rad = math.rad
local FLAT = CFrame.Angles(0, 0, math.pi / 2) -- stands a cylinder's axis (X) upright: a flat disc
-- Horse legs: front left, front right, back left, back right. Diagonal pairs swing together.
local HORSE_LEG_PHASES = { 1, -1, -1, 1 }
local HORSE_LEG_ANCHORS = { "horseLeg1", "horseLeg2", "horseLeg3", "horseLeg4" }

local function newPart(parent: Instance, shape: string, size: Vector3, color: Color3, material: string?): BasePart
	local part: BasePart
	if shape == "Wedge" then
		part = Instance.new("WedgePart")
	elseif shape == "CornerWedge" then
		part = Instance.new("CornerWedgePart")
	else
		local block = Instance.new("Part")
		block.Shape = (Enum.PartType :: any)[shape]
		part = block
	end
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Size = size
	part.Color = color
	part.Material = (Enum.Material :: any)[material or "SmoothPlastic"]
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	return part
end

-- Soft see-through puffs drifting up from a part (a look's steam): built-in smoke texture, no light.
local function emitter(part: BasePart, config: any, height: number): ParticleEmitter
	local made = Instance.new("ParticleEmitter")
	made.Texture = "rbxasset://textures/particles/smoke_main.dds" -- built into Roblox
	made.Color = ColorSequence.new(config.color or Color3.new(1, 1, 1))
	made.Transparency = NumberSequence.new(config.transparency or 0.55, 1)
	local size = (config.size or 0.18) * height
	made.Size = NumberSequence.new(size * 0.6, size * 1.6)
	made.Lifetime = NumberRange.new(1.2, 2)
	made.Speed = NumberRange.new(height * 0.12, height * 0.25)
	made.SpreadAngle = Vector2.new(25, 25)
	made.Acceleration = Vector3.new(0, height * 0.05, 0)
	made.RotSpeed = NumberRange.new(-40, 40)
	made.Rate = config.rate or 4
	made.LightInfluence = 1
	made.Parent = part
	return made
end

-- A part from a LookKit spec, with the spec's own transparency (recorded by addPiece for fades) and
-- its emitter, if any.
local function specPart(parent: Instance, spec: LookKit.Spec, figure: any?): BasePart
	local part = newPart(parent, spec.shape, spec.size, spec.color, spec.material)
	part.Transparency = spec.transparency
	if spec.emitter and figure then
		table.insert(figure.emitters, emitter(part, spec.emitter, figure.height))
	end
	return part
end

-- A piece's transparency as shown: its own, faded by the figure's; a drawn weapon's is hidden while
-- the weapon is put away.
local function shownTransparency(figure: Figure, piece: Piece): number
	if piece.drawn and not figure.weaponOut then
		return 1
	end
	return 1 - (1 - piece.transparency) * (1 - figure.transparency)
end

local function addPiece(
	figure: Figure,
	part: BasePart,
	anchor: string,
	offset: CFrame,
	horse: boolean?,
	drawn: boolean?
)
	local piece = {
		part = part,
		anchor = anchor,
		offset = offset,
		transparency = part.Transparency,
		horse = horse,
		drawn = drawn,
	}
	table.insert(figure.pieces, piece)
	table.insert(figure.parts, part)
	table.insert(figure.cframes, CFrame.identity)
	if anchor ~= "hitbox" then
		part.Transparency = shownTransparency(figure, piece)
	end
end

local function findModel(name: string): Model?
	local folder = ReplicatedStorage:FindFirstChild("CharacterModels")
	local model = folder and folder:FindFirstChild(name)
	return if model and model:IsA("Model") then model else nil
end

-- A finished model, scaled to the figure's height and moved as one body.
local function buildModel(figure: Figure, template: Model, parent: Instance)
	local model = template:Clone()
	for _, descendant in model:GetDescendants() do
		-- Every part is placed directly, so joints and scripts are not needed.
		if descendant:IsA("JointInstance") or descendant:IsA("WeldConstraint") or descendant:IsA("BaseScript") then
			descendant:Destroy()
		elseif descendant:IsA("Humanoid") then
			descendant.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		end
	end
	local _, size = model:GetBoundingBox()
	model:ScaleTo(model:GetScale() * figure.height / size.Y)
	local center, scaled = model:GetBoundingBox()
	local bottom = CFrame.new(center.Position - Vector3.new(0, scaled.Y / 2, 0))
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanCollide = false
			descendant.CanQuery = false
			descendant.CanTouch = false
			descendant.CastShadow = false
			addPiece(figure, descendant, "model", bottom:ToObjectSpace(descendant.CFrame))
		end
	end
	model.Parent = parent
end

local function buildBody(figure: Figure, look: Look, parent: Instance)
	local b = figure.body
	local h = figure.height
	local color = figure.color
	local function bodyPart(shape: string, size: Vector3, anchor: string, offset: CFrame)
		local part = newPart(parent, shape, size, color)
		addPiece(figure, part, anchor, offset)
		table.insert(figure.tinted, part)
		return part
	end

	bodyPart(
		"Block",
		Vector3.new(b.torsoWidth, b.torsoHeight, b.torsoDepth),
		"hips",
		CFrame.new(0, b.torsoHeight / 2, 0)
	)
	local roster = look.style == "roster" or look.style == "summon"
	bodyPart(if roster then "Ball" else "Block", Vector3.one * b.headSize, "head", CFrame.identity)
	for _, side in { "left", "right" } do
		bodyPart(
			"Block",
			Vector3.new(b.armWidth, b.armLength, b.armWidth),
			side .. "Arm",
			CFrame.new(0, -b.armLength / 2, 0)
		)
		bodyPart(
			"Block",
			Vector3.new(b.legWidth, b.legLength, b.legWidth),
			side .. "Leg",
			CFrame.new(0, -b.legLength / 2, 0)
		)
	end

	-- The visor marks the front, so turning is visible. Bosses get glowing eyes instead.
	local boss = look.style == "boss"
	local visor = newPart(
		parent,
		"Block",
		Vector3.new(b.headSize * 0.75, b.headSize * 0.22, b.headSize * 0.15),
		if boss then FigureConfig.bossEyeColor else FigureConfig.visorColor,
		if boss then "Neon" else nil
	)
	addPiece(figure, visor, "head", CFrame.new(0, b.headSize * 0.08, -b.headSize * 0.45))
	if boss then
		local horn = FigureConfig.bossHorn
		for _, side in { -1, 1 } do
			local part = newPart(parent, "Block", horn.size * h, horn.color)
			local offset = CFrame.new(side * b.headSize * 0.3, b.headSize * 0.5, 0)
				* CFrame.Angles(0, 0, -side * rad(25))
				* CFrame.new(0, horn.size.Y * h / 2, 0)
			addPiece(figure, part, "head", offset)
		end
	end
end

-- The class prop (FigureConfig.classes) on the hand anchor(s), for placeholders and avatars.
local function buildProps(figure: Figure, look: Look, parent: Instance)
	local h = figure.height
	local classLook = look.classLook
	if classLook then
		local hands = if classLook.hand == "both" then { "left", "right" } else { classLook.hand }
		for _, hand in hands do
			for _, prop in classLook.parts do
				local part = newPart(parent, prop.shape, prop.size * h, prop.color, prop.material)
				local turn = prop.turn
				local offset = CFrame.new(prop.at * h) * CFrame.Angles(rad(turn.X), rad(turn.Y), rad(turn.Z))
				addPiece(figure, part, hand .. "Hand", offset)
			end
		end
	end
end

local REST_POSE: Pose = {
	bob = 0,
	lean = 0,
	fall = 0,
	leftArm = 0,
	rightArm = 0,
	leftLeg = 0,
	rightLeg = 0,
	stride = 0,
}

-- The R6 body part each anchor carries (accessories carry their AvatarBodyPart attribute).
local AVATAR_ANCHORS = {
	Head = "head",
	Torso = "hips",
	["Left Arm"] = "leftArm",
	["Right Arm"] = "rightArm",
	["Left Leg"] = "leftLeg",
	["Right Leg"] = "rightLeg",
}

local computeAnchors: (figure: Figure, root: CFrame, pose: Pose) -> ()

-- A catalog avatar: a copy of the server's rest-pose template (UnitAvatars), scaled to the figure's
-- height. Its body uses R6 proportions (FigureConfig.avatarBody), so the rig's parts sit on the
-- figure's anchors at rest; each part keeps its offset from its anchor and follows every pose.
-- Accessories ride the anchor of the body part they are attached to. The class prop goes on the
-- hands as for placeholders. Body parts take form tints; textured clothing and accessories do not.
local function buildAvatar(figure: Figure, look: Look, template: Model, parent: Instance)
	local model = template:Clone()
	model:ScaleTo(figure.height / FigureConfig.avatarRigHeight)
	computeAnchors(figure, CFrame.identity, REST_POSE)
	local rest = table.clone(figure.anchors)
	-- Every part is measured from the torso, whose center sits half a torso above the hips anchor
	-- (the model's pivot is not reliable: it does not replicate as the server set it).
	local torso = model:FindFirstChild("Torso") :: BasePart
	local torsoRest = rest.hips * CFrame.new(0, figure.body.torsoHeight / 2, 0)
	local torsoFrame = torso.CFrame
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			local bodyPart = AVATAR_ANCHORS[descendant.Name]
			local anchor = bodyPart or AVATAR_ANCHORS[descendant:GetAttribute("AvatarBodyPart") or ""] or "hips"
			local at = torsoRest * torsoFrame:ToObjectSpace(descendant.CFrame)
			addPiece(figure, descendant, anchor, rest[anchor]:ToObjectSpace(at))
			if bodyPart then
				table.insert(figure.tinted, descendant)
				figure.baseColors[descendant] = descendant.Color
				figure.baseMaterials[descendant] = descendant.Material
			end
		elseif descendant:IsA("Decal") then
			table.insert(figure.decals, { decal = descendant, transparency = descendant.Transparency })
		end
	end
	figure.avatar = model
	model.Parent = parent
	-- Block-built clothing layered on the avatar (UnitAvatarConfig `outfit`, for a unit with no
	-- catalog shirt or pants). Its parts go inside the avatar's model so its Highlight (flashes,
	-- glows, selection) covers them too, and they take form tints like the body.
	if look.avatarOutfit then
		for _, spec in LookKit.outfitSpecs(look.avatarOutfit, figure.body, figure.height, look.detail == "low") do
			local part = specPart(model, spec, figure)
			addPiece(figure, part, spec.anchor, spec.offset)
			if spec.tinted then
				table.insert(figure.tinted, part)
				figure.baseColors[part] = spec.color
				figure.baseMaterials[part] = part.Material
			end
		end
	end
	if look.avatarProp ~= false then
		buildProps(figure, look, parent)
	end
	-- LookKit weapons worn with the avatar (UnitAvatarConfig `weapons`), on the same anchors.
	if look.avatarWeapons then
		for _, spec in LookKit.weaponSpecs(look.avatarWeapons, figure.body, figure.height, look.detail == "low") do
			addPiece(figure, specPart(parent, spec, figure), spec.anchor, spec.offset, nil, spec.drawn)
		end
	end
end

-- A hand-built look (UnitLookConfig): every part LookKit lists, on its anchor. No visor (the face
-- marks the front) and no class prop (the look carries its own weapons).
local function buildLook(figure: Figure, look: Look, parent: Instance)
	local specs = LookKit.specs(look.unitLook, figure.body, figure.height, look.detail == "low")
	for _, spec in specs do
		local part = specPart(parent, spec, figure)
		addPiece(figure, part, spec.anchor, spec.offset, nil, spec.drawn)
		if spec.tinted then
			table.insert(figure.tinted, part)
			figure.baseColors[part] = spec.color
			figure.baseMaterials[part] = part.Material
		end
	end
end

-- A vetted store model's data (src/shared/UnitModels/<key>), or nil if it is missing or broken.
local modelCache: { [string]: any } = {}
local function modelData(key: string): any?
	local cached = modelCache[key]
	if cached ~= nil then
		return cached or nil
	end
	local module = UnitModels:FindFirstChild(key)
	local ok, data = false, nil
	if module and module:IsA("ModuleScript") then
		ok, data = pcall(require, module)
	end
	if not ok or type(data) ~= "table" or type(data.parts) ~= "table" then
		warn(string.format("[UnitModels] %s: model data missing or unreadable; using the usual figure", key))
		modelCache[key] = false
		return nil
	end
	modelCache[key] = data
	return data
end

local SHAPES = { Block = "Block", Ball = "Ball", Cylinder = "Cylinder", Wedge = "Wedge", CornerWedge = "CornerWedge" }

-- A part from model data, `scale` studs per model height, and its pose (standing on the origin,
-- facing -Z). Meshes and decals become a SpecialMesh and Decals (set at runtime from the ids).
local function dataPart(parent: Instance, item: any, scale: number): (BasePart, CFrame)
	local material = if pcall(function()
			return (Enum.Material :: any)[item.m]
		end)
		then item.m
		else "SmoothPlastic"
	local part = newPart(
		parent,
		SHAPES[item.s] or "Block",
		Vector3.new(item.z[1], item.z[2], item.z[3]) * scale,
		Color3.fromRGB(item.c[1], item.c[2], item.c[3]),
		material
	)
	part.Transparency = item.t or 0
	local k = item.k
	if k then
		local mesh = Instance.new("SpecialMesh")
		pcall(function()
			mesh.MeshType = (Enum.MeshType :: any)[k.type]
		end)
		if k.id and k.id ~= "" then
			mesh.MeshId = k.id
		end
		if k.tex then
			mesh.TextureId = k.tex
		end
		local meshScale = Vector3.new(k.scale[1], k.scale[2], k.scale[3])
		mesh.Scale = if k.native then meshScale * scale else meshScale
		if k.offset then
			mesh.Offset = Vector3.new(k.offset[1], k.offset[2], k.offset[3]) * scale
		end
		if k.vertex then
			mesh.VertexColor = Vector3.new(k.vertex[1], k.vertex[2], k.vertex[3])
		end
		mesh.Parent = part
	end
	for _, decal in item.d or {} do
		local made = Instance.new("Decal")
		made.Texture = decal[1]
		pcall(function()
			made.Face = (Enum.NormalId :: any)[decal[2]]
		end)
		made.Transparency = decal[3] or 0
		made.Parent = part
	end
	local p = item.p
	return part,
		CFrame.new(p[1] * scale, p[2] * scale, p[3] * scale, p[4], p[5], p[6], p[7], p[8], p[9], p[10], p[11], p[12])
end

-- A vetted store model (UnitModelConfig): every part of its data on the anchor of its limb, at
-- the figure's height. Its proportions (from the model's joints) put the anchors on its joints, so
-- limbs swing from the shoulders and hips. Like an avatar it sits in a Model of its own, so a
-- Highlight shows flashes, glows and selection over its textured meshes; its colors take form
-- tints. LookKit pieces in `modelOutfit` (steam) are added on top.
local function buildModelData(figure: Figure, look: Look, data: any, parent: Instance)
	local model = Instance.new("Model")
	model.Name = data.key or "model"
	computeAnchors(figure, CFrame.identity, REST_POSE)
	local rest = table.clone(figure.anchors)
	for _, item in data.parts do
		local part, pose = dataPart(model, item, figure.height)
		local anchor = if rest[item.a] then item.a else "hips"
		addPiece(figure, part, anchor, rest[anchor]:ToObjectSpace(pose))
		table.insert(figure.tinted, part)
		figure.baseColors[part] = part.Color
		figure.baseMaterials[part] = part.Material
		for _, child in part:GetChildren() do
			if child:IsA("Decal") then
				table.insert(figure.decals, { decal = child, transparency = child.Transparency })
			end
		end
	end
	if look.modelOutfit then
		for _, spec in LookKit.outfitSpecs(look.modelOutfit, figure.body, figure.height, look.detail == "low") do
			local part = specPart(model, spec, figure)
			addPiece(figure, part, spec.anchor, spec.offset)
		end
	end
	figure.avatar = model
	figure.modelKey = data.key
	figure.modelFront = data.front
	model.Parent = parent
end

-- Builds the figure for `look` with body color `color`, `height` studs tall, under `hitbox` (the
-- unit's invisible click target, moved along with it as the first piece).
function Figure.new(look: Look, color: Color3, height: number, hitbox: BasePart, transparency: number?): Figure
	local pve = look.style == "creep" or look.style == "boss"
	-- A catalog avatar is used only once it is ready; until then (or if it failed) the unit keeps
	-- its hand-built look or placeholder.
	-- A vetted store model comes first (its data is in the game; a missing one falls through).
	local data = if look.modelKey and not look.model then modelData(look.modelKey) else nil
	local avatar = if look.avatar and not look.model and not data then UnitAvatars.template(look.avatar) else nil
	local proportions = if avatar
		then FigureConfig.avatarBody
		elseif pve then FigureConfig.pveBody
		else FigureConfig.body
	-- A hand-built look may set its own proportions (UnitLookConfig `proportions`: a giant's long
	-- arms, a crouching creature's short legs); a store model brings the proportions of its joints.
	-- They are final: bulk does not widen them further.
	local unitLook = if avatar or data then nil else look.unitLook
	local custom = if data then data.proportions else unitLook and unitLook.proportions
	local body = {}
	for key, value in proportions do
		body[key] = value * height
	end
	if custom then
		for key, value in custom do
			body[key] = value * height
		end
	end
	-- Bulk widens the torso and limbs, and the head a little (not an avatar: its rig is fixed).
	local bulk = if avatar or custom then 1 else look.bulk or 1
	for _, key in { "torsoWidth", "torsoDepth", "armWidth", "legWidth", "legSpacing" } do
		body[key] *= bulk
	end
	body.headSize *= 1 + (bulk - 1) * 0.4
	local classLook = look.classLook
	local figure: Figure = {
		height = height,
		body = body,
		lean = if pve then rad(FigureConfig.pveLean) elseif unitLook and unitLook.lean then rad(unitLook.lean) else 0,
		restArms = {
			rad(if classLook then classLook.arms[1] else 0),
			rad(if classLook then classLook.arms[2] else 0),
		},
		headOffset = CFrame.new(0, body.torsoHeight + body.neck + body.headSize / 2, 0),
		pieces = {},
		parts = {},
		cframes = {},
		tinted = {},
		baseColors = {},
		baseMaterials = {},
		formTint = nil,
		unitLook = look.unitLook,
		unitType = look.unitType,
		avatar = nil,
		highlight = nil,
		decals = {},
		emitters = {},
		color = color,
		transparency = transparency or 0,
		weaponOut = false,
		isModel = false,
		horse = nil,
		anchors = {},
	}
	addPiece(figure, hitbox, "hitbox", CFrame.identity)

	local template = if look.model then findModel(look.model) else nil
	if template then
		figure.isModel = true
		buildModel(figure, template, hitbox)
	elseif data then
		buildModelData(figure, look, data, hitbox)
	elseif avatar then
		buildAvatar(figure, look, avatar, hitbox)
	elseif look.unitLook then
		buildLook(figure, look, hitbox)
	else
		buildBody(figure, look, hitbox)
		buildProps(figure, look, hitbox)
	end

	if look.ringColor then
		local ring = FigureConfig.ring
		local diameter = ring.diameter * height
		local thickness = ring.thickness * height
		local part =
			newPart(hitbox, "Cylinder", Vector3.new(thickness, diameter, diameter), look.ringColor, ring.material)
		addPiece(figure, part, "root", CFrame.new(0, thickness / 2 + 0.03, 0) * FLAT)
	end
	return figure
end

-- The rider's resting hands in the horse body's space, its hips `hipsAbove` above the body's center
-- (the rider sits on the top of the back), for the reins.
local function riderHands(figure: Figure, hipsAbove: number): { Vector3 }
	local b = figure.body
	local hips = CFrame.new(0, hipsAbove, 0)
	local hands = {}
	for i, x in { -1, 1 } do
		local shoulder = hips
			* CFrame.new(x * (b.torsoWidth + b.armWidth) / 2, b.torsoHeight - b.armWidth / 2, 0)
			* CFrame.Angles(figure.restArms[i], 0, 0)
		hands[i] = (shoulder * CFrame.new(0, -(b.handReach or b.armLength), 0)).Position
	end
	return hands
end

-- A store horse under the rider (model data, kind "horse"): scaled so its saddle is at the seat
-- height, its body on the "horse" anchor and each leg on its leg anchor (so it strides), recolored
-- by paint role from the rider's HorseLookConfig look, its textured saddle pad tinted to the
-- blanket color; reins from the bit to the rider's hands and the rider's blanket detail added.
local function mountModel(figure: Figure, look: any, data: any)
	local c = FigureConfig.horse
	local h = figure.height
	local seat = c.backHeight * h
	local scale = seat / data.seat -- studs per model height
	local bodyY = data.bodyY * scale
	local body = CFrame.new(0, bodyY, 0)
	local joints = {}
	local rests: { [string]: CFrame } = { horse = body }
	for i, leg in data.legs do
		local joint = Vector3.new(leg[1], leg[2], leg[3]) * scale - Vector3.new(0, bodyY, 0)
		joints[i] = joint
		rests[HORSE_LEG_ANCHORS[i]] = body * CFrame.new(joint)
	end
	local colors = {
		coat = look.coat,
		coatShade = look.coatShade or look.coat:Lerp(Color3.new(0, 0, 0), 0.15),
		socks = look.markings or Color3.fromRGB(240, 240, 236),
		muzzle = look.muzzle,
		mane = look.mane,
		hoof = look.hooves,
	}
	local parent = figure.parts[1]
	for _, item in data.parts do
		local part, pose = dataPart(parent, item, scale)
		if colors[item.r] then
			part.Color = colors[item.r]
		elseif item.r == "saddle" then
			-- the pad is textured: tint it toward the blanket color
			local mesh = part:FindFirstChildOfClass("SpecialMesh")
			if mesh then
				mesh.VertexColor = Vector3.new(look.blanket.R, look.blanket.G, look.blanket.B) * 1.15
			end
		end
		local anchor = if rests[item.a] then item.a else "horse"
		addPiece(figure, part, anchor, rests[anchor]:ToObjectSpace(pose), true)
	end

	local function piece(shape: string, size: Vector3, cframe: CFrame, pieceColor: Color3)
		addPiece(figure, newPart(parent, shape, size, pieceColor), "horse", cframe, true)
	end
	-- Reins from each side of the bit to the rider's hands (in the body's space).
	local hands = riderHands(figure, seat - bodyY)
	for i, x in { -1, 1 } do
		local bit = Vector3.new(data.bit[1] * x, data.bit[2], data.bit[3]) * scale - Vector3.new(0, bodyY, 0)
		local hand = hands[i]
		piece(
			"Block",
			Vector3.new(h * 0.01, h * 0.01, (hand - bit).Magnitude),
			CFrame.lookAt((bit + hand) / 2, hand),
			look.tack
		)
	end
	-- The rider's detail on the saddle pad's sides.
	local saddle, pattern = data.saddle, look.pattern
	if saddle and pattern then
		local center = Vector3.new(saddle.center[1], saddle.center[2], saddle.center[3]) * scale
			- Vector3.new(0, bodyY, 0)
		local size = Vector3.new(saddle.size[1], saddle.size[2], saddle.size[3]) * scale
		for _, x in { -1, 1 } do
			for _, z in { -1, 1 } do
				if pattern.kind == "stars" then
					piece(
						"Block",
						Vector3.new(h * 0.006, h * 0.03, h * 0.03),
						CFrame.new(center + Vector3.new(x * (size.X / 2 + h * 0.004), -size.Y * 0.15, z * size.Z * 0.2))
							* CFrame.Angles(math.rad(45), 0, 0),
						pattern.color
					)
				elseif pattern.kind == "tassels" then
					piece(
						"Ball",
						Vector3.one * h * 0.028,
						CFrame.new(center + Vector3.new(x * size.X / 2, -size.Y * 0.45, z * size.Z * 0.42)),
						pattern.color
					)
				end
			end
		end
	end
	figure.horse = { seat = seat, bodyY = bodyY, joints = joints }
end

-- Puts the figure on its horse (HorseKit: the rider's HorseLookConfig colors and markings, with
-- `color` as the coat when the rider has none), or takes it off (nil). The reins run to the
-- rider's resting hands.
function Figure.setMount(figure: Figure, color: Color3?)
	for i = #figure.pieces, 1, -1 do
		local piece = figure.pieces[i]
		if piece.horse then
			piece.part:Destroy()
			table.remove(figure.pieces, i)
			table.remove(figure.parts, i)
			table.remove(figure.cframes, i)
		end
	end
	figure.horse = nil
	if not color then
		return
	end

	local c = FigureConfig.horse
	local h = figure.height
	local look = table.clone(HorseLookConfig.default)
	for key, value in HorseLookConfig[figure.unitType or ""] or {} do
		look[key] = value
	end
	look.coat = look.coat or color

	-- A vetted store horse (HorseLookConfig `model`), if its data is in the game.
	local data = if look.model then modelData(look.model) else nil
	if data and data.kind == "horse" then
		mountModel(figure, look, data)
		return
	end

	local hands = riderHands(figure, c.bodyHeight * h / 2)
	local horse = HorseKit.build(look, c, h, hands)
	local parent = figure.parts[1]
	for _, spec in horse.specs do
		addPiece(figure, specPart(parent, spec), spec.anchor, spec.offset, true)
	end
	figure.horse = { seat = horse.seat, bodyY = horse.bodyY, joints = horse.joints }
end

-- Recolors the body (not the props, weapons, face, ring, visor or horse). nil restores the body
-- color: a placeholder's one body color, or each part of a look its own color, blended toward the
-- form tint while a tinted form is on (FigureConfig.lookTintBlend). `blend` (0-1) only tints part of
-- the way and keeps the figure readable (a cast glow: FigureConfig.glow); without it a color covers
-- the body (a hit flash).
function Figure.setTint(figure: Figure, color: Color3?, material: Enum.Material?, blend: number?)
	local formTint = figure.formTint
	local avatar = figure.avatar
	if avatar then
		-- Clothing and accessories are textured, so recoloring parts would barely show: a Highlight
		-- over the whole avatar shows the flash or glow (or a soft white fill with an outline for
		-- selection). Its body parts still take the form tint below. A Highlight is made only on first
		-- use and is off otherwise (Roblox draws at most 31 at once).
		local look = FigureConfig.avatarHighlight
		local highlight = figure.highlight
		if color or material then
			if not highlight then
				highlight = Instance.new("Highlight")
				highlight.DepthMode = Enum.HighlightDepthMode.Occluded
				highlight.Adornee = avatar
				highlight.Parent = avatar
				figure.highlight = highlight
			end
			local h = highlight :: Highlight
			h.FillColor = color or look.selectColor
			h.OutlineColor = color or look.selectColor
			if color and blend then
				-- A glow: a light fill and a bright rim, so the avatar still reads.
				h.FillTransparency = 1 - blend * look.glowFill
				h.OutlineTransparency = look.glowOutline
			else
				h.FillTransparency = if color then look.flashFill else look.selectFill
				h.OutlineTransparency = if color then 1 else look.selectOutline
			end
			h.Enabled = true
		elseif highlight then
			highlight.Enabled = false
		end
		for _, part in figure.tinted do
			local base = figure.baseColors[part]
			part.Color = if formTint then base:Lerp(formTint, FigureConfig.lookTintBlend) else base
		end
		return
	end
	for _, part in figure.tinted do
		local base = figure.baseColors[part]
		if color and blend then
			part.Color = (base or figure.color):Lerp(color, blend)
		elseif color then
			part.Color = color
		elseif base then
			part.Color = if formTint then base:Lerp(formTint, FigureConfig.lookTintBlend) else base
		else
			part.Color = figure.color
		end
		part.Material = material or figure.baseMaterials[part] or Enum.Material.SmoothPlastic
	end
end

-- Fades every piece but the hitbox: 0 is each part's own look, 1 is invisible.
function Figure.setTransparency(figure: Figure, transparency: number)
	figure.transparency = transparency
	for _, piece in figure.pieces do
		if piece.anchor ~= "hitbox" then
			piece.part.Transparency = shownTransparency(figure, piece)
		end
	end
	for _, entry in figure.decals do
		entry.decal.Transparency = 1 - (1 - entry.transparency) * (1 - transparency)
	end
	for _, stream in figure.emitters do
		stream.Enabled = transparency < 0.5
	end
	if figure.highlight and transparency >= 1 then
		figure.highlight.Enabled = false
	end
end

-- Shows (`out`) or hides the figure's drawn weapons (LookKit weapons with `drawn`): a sword drawn
-- for a strike and put away after.
function Figure.setDrawn(figure: Figure, out: boolean)
	if figure.weaponOut == out then
		return
	end
	figure.weaponOut = out
	for _, piece in figure.pieces do
		if piece.drawn then
			piece.part.Transparency = shownTransparency(figure, piece)
		end
	end
end

-- Where the tip of an arm raised `armAngle` radians forward would be, `beyond` studs past the end
-- of the arm, in the figure's posture at its last placement. `side` 1 is the left arm, 2 the
-- right. nil for finished models (no arm to point with) or before the first placement.
function Figure.armTip(figure: Figure, side: number, armAngle: number, beyond: number): Vector3?
	local hips = figure.anchors.hips
	if figure.isModel or not hips then
		return nil
	end
	local b = figure.body
	local shoulderX = (b.torsoWidth + b.armWidth) / 2 * (if side == 1 then -1 else 1)
	local shoulder = hips * CFrame.new(shoulderX, b.torsoHeight - b.armWidth / 2, 0)
	local reach = b.handReach or b.armLength
	return (shoulder * CFrame.Angles(armAngle, 0, 0) * CFrame.new(0, -(reach + beyond), 0)).Position
end

-- Works out every anchor but the hitbox for the figure standing on `root` in `pose`.
computeAnchors = function(figure: Figure, root: CFrame, pose: Pose)
	local b = figure.body
	local anchors = figure.anchors
	local horse = figure.horse
	anchors.root = root
	local tilt = pose.tilt or 0
	local feet = if pose.fall ~= 0 or tilt ~= 0 then root * CFrame.Angles(pose.fall, 0, -tilt) else root
	local twist = pose.twist or 0
	-- Riders stay seated: no crouch on a horse.
	local crouch = if horse then 0 else math.clamp(pose.crouch or 0, 0, 0.9)

	local lean = figure.lean + pose.lean
	if figure.isModel then
		-- A model cannot bend its legs: a crouch is a smaller dip of the whole model.
		local lift = if horse then horse.seat * 0.75 else 0
		local dip = crouch * figure.height * 0.12
		anchors.model = feet
			* CFrame.new(0, pose.bob + lift - dip, 0)
			* CFrame.Angles(0, twist, 0)
			* CFrame.Angles(-lean, 0, 0)
	else
		local seat = if horse then horse.seat else b.legLength * (1 - crouch)
		-- The legs hang from the pelvis; the upper body (torso, head, arms) also turns with `twist`.
		local pelvis = feet * CFrame.new(0, seat + pose.bob, 0) * CFrame.Angles(-lean, 0, 0)
		local hips = if twist ~= 0
			then feet * CFrame.new(0, seat + pose.bob, 0) * CFrame.Angles(0, twist, 0) * CFrame.Angles(-lean, 0, 0)
			else pelvis
		anchors.hips = hips
		anchors.head = hips * figure.headOffset
		local shoulderX = (b.torsoWidth + b.armWidth) / 2
		local shoulderY = b.torsoHeight - b.armWidth / 2
		-- An arm raised out to the side turns about the shoulder's front axis first (out: away from
		-- the body), then forward.
		local leftArm = hips
			* CFrame.new(-shoulderX, shoulderY, 0)
			* CFrame.Angles(0, 0, -(pose.leftArmOut or 0))
			* CFrame.Angles(pose.leftArm, 0, 0)
		local rightArm = hips
			* CFrame.new(shoulderX, shoulderY, 0)
			* CFrame.Angles(0, 0, pose.rightArmOut or 0)
			* CFrame.Angles(pose.rightArm, 0, 0)
		anchors.leftArm = leftArm
		anchors.rightArm = rightArm
		local reach = b.handReach or b.armLength
		anchors.leftHand = leftArm * CFrame.new(0, -reach, 0)
		anchors.rightHand = rightArm * CFrame.new(0, -reach, 0)
		if horse then
			-- Astride: legs raised forward and spread.
			local raise, splay = rad(FigureConfig.horse.riderLegs), rad(FigureConfig.horse.riderLegSplay)
			anchors.leftLeg = pelvis * CFrame.new(-b.legSpacing, 0, 0) * CFrame.Angles(raise, 0, -splay)
			anchors.rightLeg = pelvis * CFrame.new(b.legSpacing, 0, 0) * CFrame.Angles(raise, 0, splay)
		else
			-- A crouch splays the legs so the feet stay on the ground under the lowered hips.
			local splay = if crouch > 0 then math.acos(1 - crouch) else 0
			anchors.leftLeg = pelvis * CFrame.new(-b.legSpacing, 0, 0) * CFrame.Angles(pose.leftLeg, 0, -splay)
			anchors.rightLeg = pelvis * CFrame.new(b.legSpacing, 0, 0) * CFrame.Angles(pose.rightLeg, 0, splay)
		end
	end
	if horse then
		local body = feet * CFrame.new(0, horse.bodyY + pose.bob * 0.5, 0)
		anchors.horse = body
		for i, joint in horse.joints do
			anchors[HORSE_LEG_ANCHORS[i]] = body
				* CFrame.new(joint)
				* CFrame.Angles(pose.stride * HORSE_LEG_PHASES[i], 0, 0)
		end
	end
end

-- Places every piece: the hitbox at `hitboxCFrame`, the figure standing on `root` in `pose`.
function Figure.place(figure: Figure, hitboxCFrame: CFrame, root: CFrame, pose: Pose)
	local anchors = figure.anchors
	anchors.hitbox = hitboxCFrame
	computeAnchors(figure, root, pose)

	local cframes = figure.cframes
	for i, piece in figure.pieces do
		cframes[i] = anchors[piece.anchor] * piece.offset
	end
	workspace:BulkMoveTo(figure.parts, cframes, Enum.BulkMoveMode.FireCFrameChanged)
end

return Figure
