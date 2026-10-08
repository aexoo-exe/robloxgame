-- A unit's figure: a placeholder humanoid built from parts (FigureConfig), or a finished model when
-- its SkinConfig entry names one, plus the cost ring and, for a mounted rider, a placeholder horse.
-- Presentation only.
--
-- Every piece is an anchored part that cannot be clicked (the unit's invisible hitbox takes clicks
-- and carries the info board) and casts no shadow. A piece hangs from a named anchor (root, hips,
-- head, an arm, a hand, a leg, the horse ...): Figure.place works out the anchors from a pose and
-- moves every piece at once with one BulkMoveTo, so a figure costs one call per frame.
-- A figure stands on its root (the ground point under the unit) and faces -Z.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local FigureConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("FigureConfig"))

local Figure = {}

-- What to build. Roster units have a class look and a ring; creeps, bosses and summons have neither.
export type Look = {
	style: string, -- "roster", "summon", "creep" or "boss"
	classLook: any?, -- a FigureConfig.classes entry
	ringColor: Color3?, -- cost ring under the unit
	model: string?, -- SkinConfig `model`: a Model in ReplicatedStorage.CharacterModels
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

local function newPart(parent: Instance, shape: string, size: Vector3, color: Color3, material: string?): Part
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Shape = (Enum.PartType :: any)[shape]
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

-- Builds the figure for `look` with body color `color`, `height` studs tall, under `hitbox` (the
-- unit's invisible click target, moved along with it as the first piece).
function Figure.new(look: Look, color: Color3, height: number, hitbox: BasePart, transparency: number?): Figure
	local pve = look.style == "creep" or look.style == "boss"
	local proportions = if pve then FigureConfig.pveBody else FigureConfig.body
	local body = {}
	for key, value in proportions do
		body[key] = value * height
	end
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
	else
		buildBody(figure, look, hitbox)
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
	piece(
		Vector3.new(headSize, headSize, headLength),
		"horse",
		neckBase
			* CFrame.new(0, neckLength, 0)
			* CFrame.Angles(rad(c.neckAngle - 30), 0, 0)
			* CFrame.new(0, 0, -headLength / 2 + headSize * 0.3)
	)
	local tailLength, tailWidth = c.tailLength * h, c.tailWidth * h
	piece(
		Vector3.new(tailWidth, tailLength, tailWidth),
		"horse",
		CFrame.new(0, bodyHeight / 2 - tailWidth, bodyLength / 2)
			* CFrame.Angles(-rad(90 - c.tailAngle), 0, 0)
			* CFrame.new(0, -tailLength / 2, 0),
		c.accentColor
	)
	figure.horse = { seat = seat, bodyY = seat - bodyHeight / 2, joints = joints }
end

-- Recolors the body (not the props, ring, visor or horse). nil restores the body color.
function Figure.setTint(figure: Figure, color: Color3?, material: Enum.Material?)
	for _, part in figure.tinted do
		part.Color = color or figure.color
		part.Material = material or Enum.Material.SmoothPlastic
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
end

-- Places every piece: the hitbox at `hitboxCFrame`, the figure standing on `root` in `pose`.
function Figure.place(figure: Figure, hitboxCFrame: CFrame, root: CFrame, pose: Pose)
	local b = figure.body
	local anchors = figure.anchors
	local horse = figure.horse
	anchors.hitbox = hitboxCFrame
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
		anchors.leftHand = leftArm * CFrame.new(0, -b.armLength, 0)
		anchors.rightHand = rightArm * CFrame.new(0, -b.armLength, 0)
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

	local cframes = figure.cframes
	for i, piece in figure.pieces do
		cframes[i] = anchors[piece.anchor] * piece.offset
	end
	workspace:BulkMoveTo(figure.parts, cframes, Enum.BulkMoveMode.FireCFrameChanged)
end

return Figure
