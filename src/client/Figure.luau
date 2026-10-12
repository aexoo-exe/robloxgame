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
}

type Piece = {
	part: BasePart,
	anchor: string,
	offset: CFrame,
	transparency: number, -- the part's own transparency (models), faded on top of
	horse: boolean?,
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
	color: Color3,
	transparency: number,
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

local function addPiece(figure: Figure, part: BasePart, anchor: string, offset: CFrame, horse: boolean?)
	local transparency = part.Transparency
	table.insert(figure.pieces, {
		part = part,
		anchor = anchor,
		offset = offset,
		transparency = transparency,
		horse = horse,
	})
	table.insert(figure.parts, part)
	table.insert(figure.cframes, CFrame.identity)
	if anchor ~= "hitbox" then
		part.Transparency = 1 - (1 - transparency) * (1 - figure.transparency)
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
	if look.avatarProp ~= false then
		buildProps(figure, look, parent)
	end
end

-- A hand-built look (UnitLookConfig): every part LookKit lists, on its anchor. No visor (the face
-- marks the front) and no class prop (the look carries its own weapons).
local function buildLook(figure: Figure, look: Look, parent: Instance)
	local specs = LookKit.specs(look.unitLook, figure.body, figure.height, look.detail == "low")
	for _, spec in specs do
		local part = newPart(parent, spec.shape, spec.size, spec.color, spec.material)
		addPiece(figure, part, spec.anchor, spec.offset)
		if spec.tinted then
			table.insert(figure.tinted, part)
			figure.baseColors[part] = spec.color
			figure.baseMaterials[part] = part.Material
		end
	end
end

-- Builds the figure for `look` with body color `color`, `height` studs tall, under `hitbox` (the
-- unit's invisible click target, moved along with it as the first piece).
function Figure.new(look: Look, color: Color3, height: number, hitbox: BasePart, transparency: number?): Figure
	local pve = look.style == "creep" or look.style == "boss"
	-- A catalog avatar is used only once it is ready; until then (or if it failed) the unit keeps
	-- its hand-built look or placeholder.
	local avatar = if look.avatar and not look.model then UnitAvatars.template(look.avatar) else nil
	local proportions = if avatar
		then FigureConfig.avatarBody
		elseif pve then FigureConfig.pveBody
		else FigureConfig.body
	local body = {}
	for key, value in proportions do
		body[key] = value * height
	end
	-- Bulk widens the torso and limbs, and the head a little (not an avatar: its rig is fixed).
	local bulk = if avatar then 1 else look.bulk or 1
	for _, key in { "torsoWidth", "torsoDepth", "armWidth", "legWidth", "legSpacing" } do
		body[key] *= bulk
	end
	body.headSize *= 1 + (bulk - 1) * 0.4
	local classLook = look.classLook
	local figure: Figure = {
		height = height,
		body = body,
		lean = if pve then rad(FigureConfig.pveLean) else 0,
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
		avatar = nil,
		highlight = nil,
		decals = {},
		color = color,
		transparency = transparency or 0,
		isModel = false,
		horse = nil,
		anchors = {},
	}
	addPiece(figure, hitbox, "hitbox", CFrame.identity)

	local template = if look.model then findModel(look.model) else nil
	if template then
		figure.isModel = true
		buildModel(figure, template, hitbox)
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

-- Adds a placeholder horse in `color` under the figure, or removes it (nil).
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
	local parent = figure.parts[1]
	local bodyLength, bodyWidth, bodyHeight = c.bodyLength * h, c.bodyWidth * h, c.bodyHeight * h
	local seat = c.backHeight * h
	local legWidth = c.legWidth * h
	local legLength = seat - bodyHeight + legWidth / 2
	local function piece(size: Vector3, anchor: string, offset: CFrame, pieceColor: Color3?)
		addPiece(figure, newPart(parent, "Block", size, pieceColor or color), anchor, offset, true)
	end

	piece(Vector3.new(bodyWidth, bodyHeight, bodyLength), "horse", CFrame.identity)
	local joints = {}
	for _, z in { -1, 1 } do -- front (-Z), then back
		for _, x in { -1, 1 } do
			local joint = Vector3.new(
				x * (bodyWidth - legWidth) / 2,
				-bodyHeight / 2 + legWidth / 4,
				z * (bodyLength / 2 - c.legInset * h)
			)
			table.insert(joints, joint)
			piece(
				Vector3.new(legWidth, legLength, legWidth),
				HORSE_LEG_ANCHORS[#joints],
				CFrame.new(0, -legLength / 2, 0)
			)
		end
	end

	local neckLength, neckWidth = c.neckLength * h, c.neckWidth * h
	local neckBase = CFrame.new(0, bodyHeight / 2 - neckWidth * 0.3, -bodyLength / 2 + neckWidth * 0.4)
		* CFrame.Angles(-rad(c.neckAngle), 0, 0)
	piece(Vector3.new(neckWidth, neckLength, neckWidth), "horse", neckBase * CFrame.new(0, neckLength / 2, 0))
	local headLength, headSize = c.headLength * h, c.headSize * h
	local head = neckBase
		* CFrame.new(0, neckLength, 0)
		* CFrame.Angles(rad(c.neckAngle - 30), 0, 0)
		* CFrame.new(0, 0, -headLength / 2 + headSize * 0.3)
	piece(Vector3.new(headSize, headSize, headLength), "horse", head)
	local tailLength, tailWidth = c.tailLength * h, c.tailWidth * h
	piece(
		Vector3.new(tailWidth, tailLength, tailWidth),
		"horse",
		CFrame.new(0, bodyHeight / 2 - tailWidth, bodyLength / 2)
			* CFrame.Angles(-rad(90 - c.tailAngle), 0, 0)
			* CFrame.new(0, -tailLength / 2, 0),
		c.accentColor
	)

	-- Mane, blanket, saddle, reins, a darker muzzle and ears, in the rider's colors (UnitLookConfig
	-- `horse`) or FigureConfig.horse's.
	local tack = (figure.unitLook and figure.unitLook.horse) or {}
	piece(
		Vector3.new(neckWidth * 0.45, neckLength * 0.95, neckWidth * 0.5),
		"horse",
		neckBase * CFrame.new(0, neckLength / 2, neckWidth * 0.4),
		tack.mane or c.maneColor
	)
	piece(
		Vector3.new(bodyWidth * 1.08, bodyHeight * 0.62, h * 0.28),
		"horse",
		CFrame.new(0, bodyHeight * 0.2, 0),
		tack.blanket or c.blanketColor
	)
	piece(
		Vector3.new(bodyWidth * 0.92, h * 0.045, h * 0.2),
		"horse",
		CFrame.new(0, bodyHeight / 2 + h * 0.02, 0),
		tack.saddle or c.saddleColor
	)
	piece(
		Vector3.new(headSize * 1.06, headSize * 0.8, headLength * 0.26),
		"horse",
		head * CFrame.new(0, -headSize * 0.08, -headLength * 0.38),
		c.muzzleColor
	)
	for _, x in { -1, 1 } do
		local bit = (head * CFrame.new(x * headSize * 0.52, -headSize * 0.1, -headLength * 0.2)).Position
		local hold = Vector3.new(x * bodyWidth * 0.3, bodyHeight / 2 + h * 0.08, -h * 0.12)
		piece(
			Vector3.new(h * 0.012, h * 0.012, (hold - bit).Magnitude),
			"horse",
			CFrame.lookAt((bit + hold) / 2, hold),
			c.reinColor
		)
		local ear = newPart(parent, "Wedge", Vector3.new(headSize * 0.15, headSize * 0.4, headSize * 0.25), color)
		addPiece(figure, ear, "horse", head * CFrame.new(x * headSize * 0.3, headSize * 0.6, headLength * 0.35), true)
	end
	figure.horse = { seat = seat, bodyY = seat - bodyHeight / 2, joints = joints }
end

-- Recolors the body (not the props, weapons, face, ring, visor or horse). nil restores the body
-- color: a placeholder's one body color, or each part of a look its own color, blended toward the
-- form tint while a tinted form is on (FigureConfig.lookTintBlend).
function Figure.setTint(figure: Figure, color: Color3?, material: Enum.Material?)
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
			h.FillTransparency = if color then look.flashFill else look.selectFill
			h.OutlineColor = color or look.selectColor
			h.OutlineTransparency = if color then 1 else look.selectOutline
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
		if color then
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
			piece.part.Transparency = 1 - (1 - piece.transparency) * (1 - transparency)
		end
	end
	for _, entry in figure.decals do
		entry.decal.Transparency = 1 - (1 - entry.transparency) * (1 - transparency)
	end
	if figure.highlight and transparency >= 1 then
		figure.highlight.Enabled = false
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
	local feet = if pose.fall ~= 0 then root * CFrame.Angles(pose.fall, 0, 0) else root

	local lean = figure.lean + pose.lean
	if figure.isModel then
		local lift = if horse then horse.seat * 0.75 else 0
		anchors.model = feet * CFrame.new(0, pose.bob + lift, 0) * CFrame.Angles(-lean, 0, 0)
	else
		local seat = if horse then horse.seat else b.legLength
		local hips = feet * CFrame.new(0, seat + pose.bob, 0) * CFrame.Angles(-lean, 0, 0)
		anchors.hips = hips
		anchors.head = hips * figure.headOffset
		local shoulderX = (b.torsoWidth + b.armWidth) / 2
		local shoulderY = b.torsoHeight - b.armWidth / 2
		local leftArm = hips * CFrame.new(-shoulderX, shoulderY, 0) * CFrame.Angles(pose.leftArm, 0, 0)
		local rightArm = hips * CFrame.new(shoulderX, shoulderY, 0) * CFrame.Angles(pose.rightArm, 0, 0)
		anchors.leftArm = leftArm
		anchors.rightArm = rightArm
		local reach = b.handReach or b.armLength
		anchors.leftHand = leftArm * CFrame.new(0, -reach, 0)
		anchors.rightHand = rightArm * CFrame.new(0, -reach, 0)
		if horse then
			-- Astride: legs raised forward and spread.
			local raise, splay = rad(FigureConfig.horse.riderLegs), rad(FigureConfig.horse.riderLegSplay)
			anchors.leftLeg = hips * CFrame.new(-b.legSpacing, 0, 0) * CFrame.Angles(raise, 0, -splay)
			anchors.rightLeg = hips * CFrame.new(b.legSpacing, 0, 0) * CFrame.Angles(raise, 0, splay)
		else
			anchors.leftLeg = hips * CFrame.new(-b.legSpacing, 0, 0) * CFrame.Angles(pose.leftLeg, 0, 0)
			anchors.rightLeg = hips * CFrame.new(b.legSpacing, 0, 0) * CFrame.Angles(pose.rightLeg, 0, 0)
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
