-- A unit on the field or bench: a figure (Figure: a placeholder humanoid with its class prop and a
-- cost ring, or a finished model) and, just above its head, a compact overhead display narrower
-- than a tile (RenderConfig.overhead): star pips, a horse bar for mounted riders, a health bar (any
-- shield shows as a white segment after the health) and a thin mana bar. Nothing else floats above
-- a unit; names and traits are in the unit info panel and the hover tooltip. Higher-star units are
-- drawn larger (RenderConfig.starSizeScale). Presentation only.
-- Callers pass the body color and the figure look (CharacterLook). The unit's `part` is an
-- invisible box of the unit size: it takes clicks and hovers (callers set UnitId, UnitType and
-- StarLevel attributes on it), carries the overhead display, and is what projectiles fly to.
-- A unit created with a form health pool (a mounted rider) shows the pool bar while its form has a
-- pool, and its form's look (RenderConfig.formLooks; a `mount` color adds a placeholder horse).
--
-- Every animation (idle, walking, gliding, turning, attacks, casts, hit flashes and recoils,
-- floating numbers, the stun ring, the shield bubble and the defeat fall) is advanced by
-- UnitView.update, called once per frame. Nothing is scheduled with task.delay or TweenService, so
-- destroying a view removes everything it shows.
-- Times come from the view's clock (os.clock by default). Combat playback passes a clock that runs
-- in fight time, so every animation follows the playback speed.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local FigureConfig = require(Shared:WaitForChild("FigureConfig"))
local ItemConfig = require(Shared:WaitForChild("ItemConfig"))
local ItemSkinConfig = require(Shared:WaitForChild("ItemSkinConfig"))
local RenderConfig = require(Shared:WaitForChild("RenderConfig"))

local Figure = require(script.Parent.Figure)

local UnitView = {}

-- Pixel layout of the floating text board, which is centered on the unit's chest. Numbers start
-- beside the body; callouts start above the head.
local FLOAT_BOARD_SIZE = Vector2.new(240, 240)
local NUMBER_START_Y = 100
local CALLOUT_START_Y = 20
local OVERHEAD = RenderConfig.overhead

local ANIMATION = FigureConfig.animation
local TAU = 2 * math.pi
local rad = math.rad

type Floater = {
	label: TextLabel,
	born: number,
	duration: number,
	startY: number,
	rise: number,
}

export type UnitView = {
	part: Part, -- invisible hitbox
	figure: Figure.Figure,
	pose: Figure.Pose,
	bubble: Part?,
	trail: Trail,
	infoBoard: BillboardGui,
	floatBoard: BillboardGui,
	color: Color3, -- body color
	maxHealth: number,
	maxMana: number?,
	health: number,
	shield: number,
	healthFill: Frame,
	shieldFill: Frame,
	manaFill: Frame,
	stunRing: Part?, -- created on the first stun
	formBar: Frame?, -- the form health pool bar; nil for units created without a pool
	formFill: Frame?,
	maxFormHealth: number?,
	clock: () -> number,

	-- Animation state, in seconds of the view's clock.
	base: Vector3, -- hitbox center without lunge or death offsets
	moveFrom: Vector3,
	moveTo: Vector3,
	moveStart: number,
	moveDuration: number,
	moveIsDash: boolean,
	yaw: number,
	faceTarget: UnitView?,
	lungeDirection: Vector3,
	lungeStart: number?,
	shootStart: number?,
	attackArm: number, -- 1 left, 2 right
	alternateArms: boolean, -- attacks switch arms (classes with a prop in each hand)
	attackPose: string, -- ranged attacks: "recoil" or "point" (FigureConfig.characters)
	castStart: number?,
	hitStart: number?,
	flashUntil: number,
	flashColor: Color3,
	glowUntil: number,
	stunUntil: number,
	trailUntil: number,
	dyingSince: number?,
	selected: boolean,
	phase: number, -- 0-1 offset so neighbors do not idle in step
	floaters: { Floater },
	floaterCount: number,
	shownColor: Color3?, -- body tint now shown (nil: the body color)
	shownMaterial: Enum.Material?,
	shownTransparency: number,
	baseTransparency: number, -- see-through for summons
	figureLook: any, -- the Figure look, kept to rebuild the figure at another size
	baseSize: Vector3, -- the hitbox size before any form scale
	boardHeight: number, -- the overhead display's height in studs
	formScale: number, -- the current form's size multiplier (RenderConfig.formLooks `scale`)
	vanishUntil: number, -- see-through while untargetable (Vanish events)
}

export type Options = {
	maxHealth: number?,
	mana: number?,
	maxMana: number?, -- no mana bar fill if nil
	yaw: number?, -- initial facing in radians around the vertical axis (0 faces -Z)
	healthColor: Color3?, -- RenderConfig.healthBarColor if nil
	summon: boolean?, -- drawn smaller and see-through, labeled as a summon
	sizeScale: number?, -- extra size multiplier (PvE creeps and bosses use their theme look's scale)
	look: Figure.Look?, -- the figure to draw (CharacterLook); a plain figure if nil
	formHealth: number?, -- the starting form's health pool; with maxFormHealth, adds the pool bar
	maxFormHealth: number?,
	formLook: any?, -- the starting form's RenderConfig.formLooks entry
	starPips: boolean?, -- show star pips (default true; creeps, bosses and summons pass false)
	clock: (() -> number)?, -- time source for every animation (default os.clock)
	items: { string }?, -- equipped item ids: a row of small item pips over the health bar
}

local function partPosition(groundPosition: Vector3, part: Part): Vector3
	return groundPosition + Vector3.new(0, part.Size.Y / 2, 0)
end

-- Yaw that makes a part's front (-Z) point along `direction`.
local function yawToward(direction: Vector3): number?
	if direction.X * direction.X + direction.Z * direction.Z < 1e-6 then
		return nil
	end
	return math.atan2(-direction.X, -direction.Z)
end

local function wrapAngle(angle: number): number
	return (angle + math.pi) % (2 * math.pi) - math.pi
end

-- A bar across the overhead display, from `top` with `height` (both fractions of its height).
local function bar(parent: Instance, top: number, height: number): Frame
	local frame = Instance.new("Frame")
	frame.Position = UDim2.fromScale(0, top)
	frame.Size = UDim2.fromScale(1, height)
	frame.BackgroundColor3 = OVERHEAD.barBackground
	frame.BorderSizePixel = 0
	frame.Parent = parent
	local stroke = Instance.new("UIStroke")
	stroke.Color = OVERHEAD.barBackground
	stroke.Thickness = 1
	stroke.Parent = frame
	return frame
end

-- Item pips: one small square per equipped item in its category's color, left-aligned (just over
-- the left end of the health bar).
local function itemPips(parent: Instance, items: { string }, height: number)
	local row = Instance.new("Frame")
	row.Size = UDim2.fromScale(1, height)
	row.BackgroundTransparency = 1
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Left
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Padding = UDim.new(0.03, 0)
	layout.Parent = row
	for _, itemId in items do
		local entry = ItemConfig.items[itemId]
		local rgb = entry and ItemSkinConfig.categoryColors[entry.category] or { 150, 150, 150 }
		local pip = Instance.new("Frame")
		pip.Size = UDim2.fromScale(0.85, 0.85)
		pip.SizeConstraint = Enum.SizeConstraint.RelativeYY
		pip.BackgroundColor3 = Color3.fromRGB(rgb[1], rgb[2], rgb[3])
		pip.BorderSizePixel = 0
		pip.Parent = row
		local stroke = Instance.new("UIStroke")
		stroke.Color = OVERHEAD.barBackground
		stroke.Thickness = 1
		stroke.Parent = pip
	end
	row.Parent = parent
end

-- Star pips: one small diamond per star, centered, in the star level's color.
local function starPips(parent: Instance, starLevel: number, height: number)
	local row = Instance.new("Frame")
	row.Size = UDim2.fromScale(1, height)
	row.BackgroundTransparency = 1
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Padding = UDim.new(0.04, 0)
	layout.Parent = row
	for _ = 1, starLevel do
		local holder = Instance.new("Frame")
		holder.Size = UDim2.fromScale(0.75, 0.75)
		holder.SizeConstraint = Enum.SizeConstraint.RelativeYY
		holder.BackgroundTransparency = 1
		holder.Parent = row
		local pip = Instance.new("Frame")
		pip.AnchorPoint = Vector2.new(0.5, 0.5)
		pip.Position = UDim2.fromScale(0.5, 0.5)
		pip.Size = UDim2.fromScale(0.72, 0.72)
		pip.Rotation = 45
		pip.BackgroundColor3 = OVERHEAD.starColors[starLevel]
		pip.BorderSizePixel = 0
		pip.Parent = holder
		local stroke = Instance.new("UIStroke")
		stroke.Color = OVERHEAD.barBackground
		stroke.Thickness = 1
		stroke.Parent = pip
	end
	row.Parent = parent
end

local function fill(parent: Instance, color: Color3): Frame
	local frame = Instance.new("Frame")
	frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundColor3 = color
	frame.BorderSizePixel = 0
	frame.Parent = parent
	return frame
end

function UnitView.new(
	name: string,
	starLevel: number,
	color: Color3,
	groundPosition: Vector3,
	parent: Instance,
	options: Options?
): UnitView
	options = options or {}
	local yaw = options.yaw or 0
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CastShadow = false
	part.Transparency = 1
	part.Size = RenderConfig.unitSize
		* RenderConfig.starSizeScale[starLevel]
		* (if options.summon then RenderConfig.summonScale else 1)
		* (options.sizeScale or 1)
	local base = partPosition(groundPosition, part)
	part.CFrame = CFrame.new(base) * CFrame.Angles(0, yaw, 0)

	local size = part.Size
	local baseTransparency = if options.summon then RenderConfig.summonTransparency else 0
	local look = options.look or { style = "summon" }
	local figure = Figure.new(look, color, size.Y, part, baseTransparency)
	local hand = if look.classLook then look.classLook.hand else "right"

	local trailTop = Instance.new("Attachment")
	trailTop.Position = Vector3.new(0, size.Y * 0.3, 0)
	trailTop.Parent = part
	local trailBottom = Instance.new("Attachment")
	trailBottom.Position = Vector3.new(0, -size.Y * 0.3, 0)
	trailBottom.Parent = part
	local trail = Instance.new("Trail")
	trail.Attachment0 = trailTop
	trail.Attachment1 = trailBottom
	trail.Color = ColorSequence.new(RenderConfig.dashTrailColor)
	trail.Transparency = NumberSequence.new(0.3, 1)
	trail.Lifetime = RenderConfig.dashTrailLifetime
	trail.FaceCamera = true
	trail.Enabled = false
	trail.Parent = part

	-- The overhead display, sized in studs so it scales with the view and stays narrower than a
	-- tile. Rows from the top (heights in studs): star pips, the horse bar (riders), health, mana.
	local pips = options.starPips ~= false
	local rows = {}
	if pips then
		table.insert(rows, { kind = "pips", height = OVERHEAD.pipHeight })
	end
	if options.maxFormHealth then
		table.insert(rows, { kind = "form", height = OVERHEAD.formBarHeight })
	end
	if options.items and #options.items > 0 then
		table.insert(rows, { kind = "items", height = OVERHEAD.itemPipHeight })
	end
	table.insert(rows, { kind = "health", height = OVERHEAD.healthBarHeight })
	table.insert(rows, { kind = "mana", height = OVERHEAD.manaBarHeight })
	local boardHeight = 0
	for _, row in rows do
		boardHeight += row.height + OVERHEAD.gap
	end

	local infoBoard = Instance.new("BillboardGui")
	infoBoard.Size = UDim2.fromScale(OVERHEAD.width, boardHeight)
	infoBoard.StudsOffset = Vector3.new(0, size.Y / 2 + OVERHEAD.aboveHead + boardHeight / 2, 0)
	infoBoard.AlwaysOnTop = true
	infoBoard.Parent = part

	local formBar, formFill, healthFill, shieldFill, manaFill = nil, nil, nil, nil, nil
	local top = 0
	for _, row in rows do
		local height = row.height / boardHeight
		if row.kind == "pips" then
			starPips(infoBoard, starLevel, height)
		elseif row.kind == "items" then
			local holder = Instance.new("Frame")
			holder.Position = UDim2.fromScale(0, top)
			holder.Size = UDim2.fromScale(1, height)
			holder.BackgroundTransparency = 1
			holder.Parent = infoBoard
			itemPips(holder, options.items :: { string }, 1)
		elseif row.kind == "form" then
			formBar = bar(infoBoard, top, height)
			formFill = fill(formBar :: Frame, RenderConfig.formHealthColor)
		elseif row.kind == "health" then
			local healthBar = bar(infoBoard, top, height)
			healthFill = fill(healthBar, options.healthColor or RenderConfig.healthBarColor)
			shieldFill = fill(healthBar, RenderConfig.shieldColor)
			shieldFill.Size = UDim2.fromScale(0, 1)
		else
			local manaBar = bar(infoBoard, top, height)
			manaFill = fill(manaBar, RenderConfig.manaBarColor)
			manaFill.Size = UDim2.fromScale(0, 1)
		end
		top += (row.height + OVERHEAD.gap) / boardHeight
	end

	-- Floating numbers and callouts, in pixels so they stay readable on small screens.
	local floatBoard = Instance.new("BillboardGui")
	floatBoard.Size = UDim2.fromOffset(FLOAT_BOARD_SIZE.X, FLOAT_BOARD_SIZE.Y)
	floatBoard.StudsOffset = Vector3.new(0, size.Y * 0.1, 0)
	floatBoard.AlwaysOnTop = true
	floatBoard.Parent = part

	part.Parent = parent
	local view = {
		part = part,
		figure = figure,
		pose = {
			bob = 0,
			lean = 0,
			fall = 0,
			leftArm = 0,
			rightArm = 0,
			leftLeg = 0,
			rightLeg = 0,
			stride = 0,
		},
		bubble = nil,
		trail = trail,
		infoBoard = infoBoard,
		floatBoard = floatBoard,
		color = color,
		maxHealth = options.maxHealth or 1,
		maxMana = options.maxMana,
		health = options.maxHealth or 1,
		shield = 0,
		healthFill = healthFill :: Frame,
		shieldFill = shieldFill :: Frame,
		manaFill = manaFill :: Frame,
		stunRing = nil,
		formBar = formBar,
		formFill = formFill,
		maxFormHealth = options.maxFormHealth,
		clock = options.clock or os.clock,

		base = base,
		moveFrom = base,
		moveTo = base,
		moveStart = 0,
		moveDuration = 0,
		moveIsDash = false,
		yaw = yaw,
		faceTarget = nil,
		lungeDirection = Vector3.zero,
		lungeStart = nil,
		shootStart = nil,
		attackArm = if hand == "left" then 1 else 2,
		alternateArms = hand == "both",
		attackPose = look.attackPose or "recoil",
		castStart = nil,
		hitStart = nil,
		flashUntil = 0,
		flashColor = color,
		glowUntil = 0,
		stunUntil = 0,
		trailUntil = 0,
		dyingSince = nil,
		selected = false,
		phase = math.random(),
		floaters = {},
		floaterCount = 0,
		shownColor = nil,
		shownMaterial = nil,
		shownTransparency = baseTransparency,
		baseTransparency = baseTransparency,
		figureLook = look,
		baseSize = part.Size,
		boardHeight = boardHeight,
		formScale = 1,
		vanishUntil = 0,
	}
	UnitView.setMana(view, options.mana or 0)
	if options.formLook or options.maxFormHealth then
		UnitView.setForm(view, options.formLook, options.formHealth, options.maxFormHealth)
	end
	UnitView.update(view, view.clock(), 0)
	return view
end

-- Shows the form health pool. Hidden when `formHealth` is nil (the form has no pool).
function UnitView.setFormHealth(view: UnitView, formHealth: number?)
	if not view.formBar or not view.formFill then
		return
	end
	view.formBar.Visible = formHealth ~= nil
	if formHealth and view.maxFormHealth then
		view.formFill.Size = UDim2.fromScale(math.clamp(formHealth / view.maxFormHealth, 0, 1), 1)
	end
end

-- Rebuilds the figure `scale` times its normal size (a giant form), keeping it standing where it is.
local function rescale(view: UnitView, scale: number)
	if view.formScale == scale or view.dyingSince then
		return
	end
	view.formScale = scale
	local old = view.figure
	for i = #old.pieces, 2, -1 do -- piece 1 is the hitbox itself
		old.pieces[i].part:Destroy()
	end
	local oldHeight = view.part.Size.Y
	view.part.Size = view.baseSize * scale
	local lift = Vector3.new(0, (view.part.Size.Y - oldHeight) / 2, 0)
	view.base += lift
	view.moveFrom += lift
	view.moveTo += lift
	view.figure = Figure.new(view.figureLook, old.color, view.part.Size.Y, view.part, view.baseTransparency)
	view.shownTransparency = -1 -- reapply on the next update
	view.shownColor, view.shownMaterial = nil, nil
	view.infoBoard.StudsOffset = Vector3.new(0, view.part.Size.Y / 2 + OVERHEAD.aboveHead + view.boardHeight / 2, 0)
	if view.bubble then
		local size = view.part.Size
		view.bubble.Size = Vector3.one * math.max(size.X, size.Y, size.Z) * RenderConfig.shieldBubbleScale
	end
end

-- Switches to a new form: its look (a RenderConfig.formLooks entry, or nil for none) and its health
-- pool (nil if it has none). A look with a `mount` color puts the unit on a placeholder horse; any
-- other look removes the horse. A `scale` redraws the unit larger or smaller, and a `tint` recolors
-- its body (placeholders for each form's art).
function UnitView.setForm(view: UnitView, look: any?, formHealth: number?, maxFormHealth: number?)
	local mount = if look and not view.dyingSince then look.mount else nil
	rescale(view, if look and look.scale then look.scale else 1)
	view.figure.color = if look and look.tint then look.tint else view.color
	Figure.setTint(view.figure, nil)
	view.shownColor, view.shownMaterial = nil, nil
	Figure.setMount(view.figure, mount)
	if maxFormHealth then
		view.maxFormHealth = maxFormHealth
	end
	UnitView.setFormHealth(view, formHealth)
end

-- Where the body is heading right now (ignoring lunges), for a move that may be in progress.
local function currentBase(view: UnitView, now: number): Vector3
	if view.moveDuration <= 0 then
		return view.moveTo
	end
	local alpha = math.clamp((now - view.moveStart) / view.moveDuration, 0, 1)
	if view.moveIsDash then
		alpha = 1 - (1 - alpha) * (1 - alpha)
	end
	return view.moveFrom:Lerp(view.moveTo, alpha)
end

local function startMove(view: UnitView, groundPosition: Vector3, duration: number, isDash: boolean)
	local now = view.clock()
	view.moveFrom = currentBase(view, now)
	view.moveTo = partPosition(groundPosition, view.part)
	view.moveStart = now
	view.moveDuration = duration
	view.moveIsDash = isDash
end

-- Moves the unit to a ground position: walks there over `duration` seconds (driven by
-- UnitView.update), or snaps there at once if no duration is given.
function UnitView.moveTo(view: UnitView, groundPosition: Vector3, duration: number?)
	if duration and duration > 0 then
		startMove(view, groundPosition, duration, false)
	else
		local goal = partPosition(groundPosition, view.part)
		view.moveFrom, view.moveTo, view.moveDuration, view.base = goal, goal, 0, goal
		UnitView.update(view, view.clock(), 0)
	end
end

-- A fast slide with a short trail.
function UnitView.dashTo(view: UnitView, groundPosition: Vector3)
	startMove(view, groundPosition, RenderConfig.dashDuration, true)
	view.trailUntil = view.clock() + RenderConfig.dashDuration
end

-- Turns toward `target` whenever the unit is not moving.
function UnitView.face(view: UnitView, target: UnitView?)
	view.faceTarget = target
end

local function nextAttackArm(view: UnitView)
	if view.alternateArms then
		view.attackArm = 3 - view.attackArm
	end
end

-- A melee attack: a small lunge toward `target` and back with a swing of the attacking arm,
-- starting at `startAt` (view.clock(); now if omitted). It peaks halfway through
-- RenderConfig.lungeDuration.
function UnitView.lunge(view: UnitView, target: UnitView, startAt: number?)
	local direction = target.part.Position - view.part.Position
	direction = Vector3.new(direction.X, 0, direction.Z)
	if direction.Magnitude < 1e-3 then
		return
	end
	nextAttackArm(view)
	view.lungeDirection = direction.Unit
	view.lungeStart = startAt or view.clock()
	view.faceTarget = target
end

-- A ranged attack: faces `target` and recoils (or points, with attack pose "point"), starting at
-- `startAt` (view.clock(); now if omitted).
function UnitView.shoot(view: UnitView, target: UnitView, startAt: number?)
	nextAttackArm(view)
	view.shootStart = startAt or view.clock()
	view.faceTarget = target
end

-- Where a ranged attack's projectile starts: the pointing fingertip for attack pose "point", else
-- the middle of the unit.
function UnitView.launchPoint(view: UnitView): Vector3
	if view.attackPose == "point" then
		local tip = Figure.armTip(
			view.figure,
			view.attackArm,
			rad(ANIMATION.pointArm),
			ANIMATION.fingertip * view.figure.height
		)
		if tip then
			return tip
		end
	end
	return view.part.Position
end

local function redrawHealth(view: UnitView)
	local healthFraction = math.clamp(view.health / view.maxHealth, 0, 1)
	local shieldFraction = math.clamp(view.shield / view.maxHealth, 0, 1 - healthFraction)
	view.healthFill.Size = UDim2.fromScale(healthFraction, 1)
	view.shieldFill.Position = UDim2.fromScale(healthFraction, 0)
	view.shieldFill.Size = UDim2.fromScale(shieldFraction, 1)
end

function UnitView.setHealth(view: UnitView, health: number)
	view.health = health
	redrawHealth(view)
end

-- Shows the shield in the health bar, and as a bubble around the unit while it is above zero.
function UnitView.setShield(view: UnitView, shield: number)
	view.shield = shield
	redrawHealth(view)
	if shield > 0 and not view.bubble and not view.dyingSince then
		local size = view.part.Size
		local bubble = Instance.new("Part")
		bubble.Anchored = true
		bubble.CanCollide = false
		bubble.CanQuery = false
		bubble.CanTouch = false
		bubble.CastShadow = false
		bubble.Shape = Enum.PartType.Ball
		bubble.Size = Vector3.one * math.max(size.X, size.Y, size.Z) * RenderConfig.shieldBubbleScale
		bubble.Color = RenderConfig.shieldBubbleColor
		bubble.Material = Enum.Material.ForceField
		bubble.CFrame = view.part.CFrame
		bubble.Parent = view.part
		view.bubble = bubble
	end
	if view.bubble then
		view.bubble.Transparency = if shield > 0 and not view.dyingSince then 0 else 1
	end
end

function UnitView.setMana(view: UnitView, mana: number)
	local fraction = if view.maxMana then math.clamp(mana / view.maxMana, 0, 1) else 0
	view.manaFill.Size = UDim2.fromScale(fraction, 1)
end

-- Shows the stun ring around the head for `seconds`. A newer stun replaces the timer of an older one.
function UnitView.stun(view: UnitView, seconds: number)
	if seconds > 0 and not view.stunRing then
		local ring = Instance.new("Part")
		ring.Anchored = true
		ring.CanCollide = false
		ring.CanQuery = false
		ring.CanTouch = false
		ring.CastShadow = false
		ring.Shape = Enum.PartType.Cylinder
		local diameter = view.figure.height * 0.32
		ring.Size = Vector3.new(0.08, diameter, diameter)
		ring.Color = RenderConfig.stunMarkerColor
		ring.Material = Enum.Material.Neon
		ring.Transparency = 1
		ring.Parent = view.part
		view.stunRing = ring
	end
	view.stunUntil = view.clock() + seconds
end

local function addFloater(
	view: UnitView,
	text: string,
	color: Color3,
	size: number,
	x: number,
	startY: number,
	duration: number,
	rise: number
)
	if not view.part.Parent then
		return
	end
	if #view.floaters >= RenderConfig.maxFloatingTexts then
		table.remove(view.floaters, 1).label:Destroy()
	end
	local label = Instance.new("TextLabel")
	label.AnchorPoint = Vector2.new(0.5, 0)
	label.Position = UDim2.new(0.5, x, 0, startY)
	label.Size = UDim2.fromOffset(FLOAT_BOARD_SIZE.X / 2, size + 6)
	label.BackgroundTransparency = 1
	label.Text = text
	label.TextColor3 = color
	label.TextStrokeTransparency = 0
	label.TextStrokeColor3 = Color3.new(0, 0, 0)
	label.Font = RenderConfig.floatingTextFont
	label.TextSize = size
	label.Parent = view.floatBoard
	table.insert(view.floaters, {
		label = label,
		born = view.clock(),
		duration = duration,
		startY = startY,
		rise = rise,
	})
end

-- A number that starts beside the body, rises and fades quickly. Successive numbers on one unit
-- take turns in lanes on alternating sides, with a little jitter, so they do not stack.
local function floatNumber(view: UnitView, text: string, color: Color3, size: number)
	local lanes = RenderConfig.damageNumberLanes
	local lane = view.floaterCount % #lanes + 1
	view.floaterCount += 1
	local jitter = RenderConfig.damageNumberJitter
	addFloater(
		view,
		text,
		color,
		size,
		lanes[lane] + math.random(-jitter, jitter),
		NUMBER_START_Y + math.random(-jitter, jitter),
		RenderConfig.damageNumberDuration,
		RenderConfig.damageNumberRise
	)
end

local DAMAGE_COLORS = {
	PHYSICAL = "physicalDamageColor",
	MAGIC = "magicDamageColor",
	TRUE = "trueDamageColor",
}

-- `damageType` is a CombatMath.DamageType value; crits are a little larger, in their own color.
function UnitView.damageNumber(view: UnitView, amount: number, damageType: string?, crit: boolean?)
	local color = RenderConfig[DAMAGE_COLORS[damageType or "PHYSICAL"] or "physicalDamageColor"]
	if crit then
		floatNumber(view, amount .. "!", RenderConfig.critNumberColor, RenderConfig.critNumberSize)
	else
		floatNumber(view, tostring(amount), color, RenderConfig.damageNumberSize)
	end
end

function UnitView.healNumber(view: UnitView, amount: number)
	floatNumber(view, "+" .. amount, RenderConfig.healTextColor, RenderConfig.damageNumberSize)
end

-- A damage-over-time tick: a small number in the damage type's color, with no hit flash.
function UnitView.dotNumber(view: UnitView, amount: number, damageType: string?)
	local color = RenderConfig[DAMAGE_COLORS[damageType or "PHYSICAL"] or "physicalDamageColor"]
	floatNumber(view, tostring(amount), color, RenderConfig.dotNumberSize)
end

-- A short status label (Slowed, Burning, ...) that floats up like a small number.
function UnitView.statusText(view: UnitView, text: string, color: Color3)
	floatNumber(view, text, color, RenderConfig.dotNumberSize)
end

-- The unit turns see-through for `seconds` while it is untargetable.
function UnitView.vanish(view: UnitView, seconds: number)
	view.vanishUntil = view.clock() + seconds
end

-- Sets a new max health (and current health), as after a MaxHealth bonus.
function UnitView.setMaxHealth(view: UnitView, maxHealth: number, health: number)
	view.maxHealth = maxHealth
	UnitView.setHealth(view, health)
end

-- A callout for a big moment (a boss ability, a dismount): `text` floats up from above the unit
-- and fades. Callers decide what counts as big (CombatPlayback).
function UnitView.callout(view: UnitView, text: string, color: Color3)
	addFloater(
		view,
		text,
		color,
		RenderConfig.calloutTextSize,
		0,
		CALLOUT_START_Y,
		RenderConfig.calloutDuration,
		RenderConfig.damageNumberRise / 2
	)
end

-- A cast: the unit glows briefly and throws its arms up. Ability names are not announced.
function UnitView.cast(view: UnitView)
	local now = view.clock()
	view.glowUntil = now + RenderConfig.castGlowDuration
	view.castStart = now
end

-- Briefly flashes the unit and knocks it back to show it was hit; crits flash in a different color.
function UnitView.flash(view: UnitView, crit: boolean?)
	local now = view.clock()
	view.flashUntil = now + RenderConfig.hitFlashDuration
	view.flashColor = if crit then RenderConfig.critFlashColor else RenderConfig.hitFlashColor
	view.hitStart = now
end

-- Starts the defeat: the unit falls backward, sinks and fades. Keep updating the view until
-- UnitView.update returns false, then destroy it.
function UnitView.kill(view: UnitView)
	if view.dyingSince then
		return
	end
	view.dyingSince = view.clock()
	view.infoBoard.Enabled = false
	view.trail.Enabled = false
	view.faceTarget = nil
	if view.bubble then
		view.bubble.Transparency = 1
	end
end

function UnitView.isAlive(view: UnitView): boolean
	return view.dyingSince == nil and view.part.Parent ~= nil
end

-- Progress (0-1) of a one-shot animation that started at `start` and lasts `duration`, or nil when
-- it is not playing.
local function progressOf(start: number?, duration: number, now: number): number?
	if not start or now < start then
		return nil
	end
	local progress = (now - start) / duration
	return if progress < 1 then progress else nil
end

-- Works out this frame's pose from the animation state. Later layers add to earlier ones: idle or
-- walking, then an attack, a cast, a hit recoil, a stun and the defeat fall.
local function updatePose(view: UnitView, now: number, moving: boolean)
	local pose = view.pose
	local figure = view.figure
	local height = figure.height
	local rest = figure.restArms
	local idle = math.sin((now / ANIMATION.idlePeriod + view.phase) * TAU)
	pose.bob = idle * ANIMATION.idleBob * height
	pose.lean, pose.fall, pose.stride = 0, 0, 0
	pose.leftArm = rest[1] + rad(ANIMATION.idleArmSway) * idle
	pose.rightArm = rest[2] - rad(ANIMATION.idleArmSway) * idle
	pose.leftLeg, pose.rightLeg = 0, 0

	if moving then
		local step = math.sin((now / ANIMATION.walkCycle + view.phase) * TAU)
		local legSwing = rad(ANIMATION.walkLegSwing) * step
		local armSwing = rad(ANIMATION.walkArmSwing) * step
		pose.leftLeg, pose.rightLeg = legSwing, -legSwing
		pose.leftArm, pose.rightArm = rest[1] - armSwing, rest[2] + armSwing
		pose.bob = math.abs(step) * ANIMATION.walkBob * height
		pose.stride = rad(ANIMATION.horseLegSwing) * step
	end

	-- Attacks: the attacking arm swings with a melee lunge, or kicks up with a ranged shot, or (attack
	-- pose "point") snaps up to point at the target, holds, and drops back.
	local armRaise, attackLean = 0, 0
	local lunge = progressOf(view.lungeStart, RenderConfig.lungeDuration, now)
	local pointing = view.attackPose == "point"
	local shot = progressOf(view.shootStart, if pointing then ANIMATION.pointDuration else ANIMATION.shootDuration, now)
	if lunge then
		local swing = math.sin(math.pi * lunge)
		armRaise, attackLean = rad(ANIMATION.attackArm) * swing, rad(ANIMATION.attackLean) * swing
	elseif shot and pointing then
		local reach = math.min(1, shot * 6, (1 - shot) * 3)
		local current = if view.attackArm == 1 then pose.leftArm else pose.rightArm
		armRaise = (rad(ANIMATION.pointArm) - current) * reach
	elseif shot then
		local recoil = math.sin(math.pi * shot)
		armRaise, attackLean = rad(ANIMATION.shootArm) * recoil, rad(ANIMATION.shootLean) * recoil
	end
	if view.attackArm == 1 then
		pose.leftArm += armRaise
	else
		pose.rightArm += armRaise
	end
	pose.lean += attackLean

	local cast = progressOf(view.castStart, ANIMATION.castDuration, now)
	if cast then
		local lift = math.sin(math.pi * cast)
		local up = rad(ANIMATION.castArms)
		pose.leftArm += (up - pose.leftArm) * lift
		pose.rightArm += (up - pose.rightArm) * lift
	end

	local hit = progressOf(view.hitStart, ANIMATION.hitDuration, now)
	if hit then
		pose.lean += rad(ANIMATION.hitLean) * (1 - hit)
	end

	if now < view.stunUntil and not view.dyingSince then
		-- Stunned: arms drop and the idle stops.
		pose.bob = 0
		pose.leftArm *= 0.3
		pose.rightArm *= 0.3
	end

	if view.dyingSince then
		local progress = math.clamp((now - view.dyingSince) / RenderConfig.deathFadeDuration, 0, 1)
		local eased = 1 - (1 - progress) * (1 - progress)
		pose.fall = rad(ANIMATION.defeatFall) * eased
		pose.leftArm *= 1 - eased
		pose.rightArm *= 1 - eased
	end
end

-- Advances every animation to `now` (view.clock()); `dt` is the frame time. Returns false once a
-- dying view has finished fading and has no floating text left, when it should be destroyed.
function UnitView.update(view: UnitView, now: number, dt: number): boolean
	local part = view.part

	-- Position: the walk or dash, plus any lunge, minus any death sink.
	local base = currentBase(view, now)
	local moving = view.moveDuration > 0 and now < view.moveStart + view.moveDuration
	if view.moveDuration > 0 and not moving then
		view.moveDuration = 0
	end
	view.base = base
	local offset = Vector3.zero
	local lunge = progressOf(view.lungeStart, RenderConfig.lungeDuration, now)
	if lunge then
		offset = view.lungeDirection * (RenderConfig.lungeDistance * math.sin(math.pi * lunge))
	end

	-- Facing: along the path while moving, otherwise toward the target.
	local desiredYaw = nil
	if moving then
		desiredYaw = yawToward(view.moveTo - view.moveFrom)
	elseif view.faceTarget and UnitView.isAlive(view.faceTarget) then
		desiredYaw = yawToward(view.faceTarget.base - base)
	end
	if desiredYaw then
		local difference = wrapAngle(desiredYaw - view.yaw)
		view.yaw = wrapAngle(view.yaw + difference * math.min(1, RenderConfig.turnRate * dt))
	end

	local transparency = view.baseTransparency
	if now < view.vanishUntil then
		transparency = math.max(transparency, RenderConfig.vanishTransparency)
	end
	if view.dyingSince then
		local progress = math.clamp((now - view.dyingSince) / RenderConfig.deathFadeDuration, 0, 1)
		transparency = view.baseTransparency + (1 - view.baseTransparency) * progress
		offset -= Vector3.new(0, RenderConfig.deathSinkDistance * progress, 0)
	end
	if transparency ~= view.shownTransparency then
		Figure.setTransparency(view.figure, transparency)
		view.shownTransparency = transparency
	end

	updatePose(view, now, moving)
	local center = base + offset
	local rotation = CFrame.Angles(0, view.yaw, 0)
	local hitboxCFrame = CFrame.new(center) * rotation
	local root = CFrame.new(center - Vector3.new(0, part.Size.Y / 2, 0)) * rotation
	Figure.place(view.figure, hitboxCFrame, root, view.pose)
	if view.bubble and view.bubble.Transparency < 1 then
		view.bubble.CFrame = hitboxCFrame
	end

	-- Body tint: a hit flash wins over a cast glow, which wins over the selection glow.
	local color, material = nil, nil
	if now < view.flashUntil then
		color = view.flashColor
	elseif now < view.glowUntil then
		color, material = RenderConfig.castGlowColor, Enum.Material.Neon
	elseif view.selected then
		material = Enum.Material.Neon
	end
	if color ~= view.shownColor or material ~= view.shownMaterial then
		Figure.setTint(view.figure, color, material)
		view.shownColor, view.shownMaterial = color, material
	end

	-- Stunned: a tilted halo wobbles just above the head.
	local stunned = now < view.stunUntil and not view.dyingSince
	local ring = view.stunRing
	if ring then
		ring.Transparency = if stunned then 0.2 else 1
		if stunned then
			ring.CFrame = root
				* CFrame.new(0, view.figure.height * 1.03, 0)
				* CFrame.Angles(0, now * 4, 0)
				* CFrame.Angles(0.25, 0, math.pi / 2)
		end
	end
	local trailing = now < view.trailUntil and not view.dyingSince
	if view.trail.Enabled ~= trailing then
		view.trail.Enabled = trailing
	end

	-- Floating text rises with an ease-out and fades over its second half.
	for i = #view.floaters, 1, -1 do
		local floater = view.floaters[i]
		local progress = (now - floater.born) / floater.duration
		if progress >= 1 then
			floater.label:Destroy()
			table.remove(view.floaters, i)
		else
			local eased = 1 - (1 - progress) * (1 - progress)
			local y = floater.startY - floater.rise * eased
			floater.label.Position = UDim2.new(floater.label.Position.X, UDim.new(0, y))
			local fade = math.clamp(progress * 2 - 1, 0, 1)
			floater.label.TextTransparency = fade
			floater.label.TextStrokeTransparency = fade
		end
	end

	if view.dyingSince then
		return now - view.dyingSince < RenderConfig.deathFadeDuration or #view.floaters > 0
	end
	return true
end

function UnitView.setSelected(view: UnitView, selected: boolean)
	view.selected = selected
	UnitView.update(view, view.clock(), 0)
end

function UnitView.destroy(view: UnitView)
	view.part:Destroy()
	table.clear(view.floaters)
end

return UnitView
