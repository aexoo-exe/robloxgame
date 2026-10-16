-- A unit on the field or bench: a figure (Figure: a placeholder humanoid with its class prop and a
-- cost ring, or a finished model) and, just above its head, a compact overhead display narrower
-- than a tile (RenderConfig.overhead): star pips, a horse bar for mounted riders, a row of equipped
-- item icons (UnitView.itemAtScreen finds the one under the pointer), a health bar (any shield
-- shows as a white segment after the health) and a thin mana bar. Nothing else floats above
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
-- Combat motion (attack styles, hit reactions, cast wind-up and release, stun, death, victory) is
-- UnitMotion's pose math with AnimationConfig's numbers; CombatFx decides when each one plays.
-- Under it runs the living idle (breathing, weight shifts, looking), heel-to-toe walking and
-- landings (AnimationConfig.living); loose parts swing in Figure (AnimationConfig.secondary). At
-- low effect quality bench units idle plainly and units off screen are not posed
-- (AnimationConfig.motionQuality).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AnimationConfig = require(Shared:WaitForChild("AnimationConfig"))
local FigureConfig = require(Shared:WaitForChild("FigureConfig"))
local RenderConfig = require(Shared:WaitForChild("RenderConfig"))

local CharacterLook = require(script.Parent.CharacterLook)
local Figure = require(script.Parent.Figure)
local ImpactEffects = require(script.Parent.ImpactEffects)
local ItemIcon = require(script.Parent.ItemIcon)
local StatusMarkers = require(script.Parent.StatusMarkers)
local UnitMotion = require(script.Parent.UnitMotion)

local UnitView = {}

-- An equipped item's icon over a unit: its center in studs from the overhead display's center.
type ItemSlot = { itemId: string, x: number, y: number }

-- Live views that show item icons, for UnitView.itemAtScreen (removed on destroy).
local withItems: { [any]: boolean } = {}

-- Pixel layout of the floating text board, which is centered on the unit's chest. Numbers start
-- beside the body; callouts start above the head.
local FLOAT_BOARD_SIZE = Vector2.new(240, 240)
local NUMBER_START_Y = 100
local CALLOUT_START_Y = 20
local OVERHEAD = RenderConfig.overhead

local ANIMATION = FigureConfig.animation
local LIVING = AnimationConfig.living
local TAU = 2 * math.pi
local rad = math.rad

type Floater = {
	label: TextLabel,
	born: number,
	duration: number,
	startY: number,
	rise: number,
	size: number, -- text size once settled
	pop: number, -- starting size multiplier (AnimationConfig.numbers)
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
	starLevel: number,
	lungeDirection: Vector3, -- toward the current attack's target
	attackStart: number?, -- the current attack motion (UnitMotion.attack)
	attackDuration: number,
	attackStyle: UnitMotion.Style?,
	attackArm: number, -- 1 left, 2 right
	alternateArms: boolean, -- attacks switch arms (classes with a prop in each hand)
	attackPose: string, -- ranged attacks: "recoil" or "point" (FigureConfig.characters)
	windupStart: number?, -- cast wind-up, from windupStart to castStart
	castStart: number?, -- the release
	castColor: Color3, -- the caster's element color (glow, charge orb)
	castStyle: string?, -- a signature's wind-up and release poses (nil: the generic ones)
	castOrb: number, -- the charge orb's size multiplier
	releaseDuration: number,
	-- An ultimate's pose keys (UnitMotion.ultimatePose) from startAt to endAt; design time runs at
	-- `k` before the release (a compressed anticipation).
	ultimate: { track: any, startAt: number, releaseAt: number, endAt: number, k: number }?,
	markers: any?, -- status markers (StatusMarkers)
	chargeOrb: Part?, -- gathers between the hands in a wind-up (made on first use)
	chargeField: ParticleEmitter?, -- sparkles drawn in toward the orb (high quality)
	hitStart: number?,
	knockDirection: Vector3, -- away from the last attacker
	knockStrength: number, -- studs at normal size
	stopAt: number, -- hit-stop: the pose holds at stopAt until stopUntil
	stopUntil: number,
	stopShake: boolean, -- the held unit jitters (the one hit)
	flashUntil: number,
	flashColor: Color3,
	glowUntil: number,
	stunUntil: number,
	stunStars: { Part }?, -- circle the head while stunned (made on first stun)
	trailUntil: number,
	cheerStart: number?, -- victory cheer
	bubblePop: number?, -- the shield bubble popping in
	dyingSince: number?,
	puffed: boolean, -- the death puff has been shown
	selected: boolean,
	phase: number, -- 0-1 offset so neighbors do not idle in step
	rate: number, -- this unit's idle tempo (AnimationConfig.living.rateSpread)
	seed: number, -- offsets its weight shifts and glances
	calm: number, -- 0-1: how much of the living idle shows (fades out while the unit acts)
	landStart: number?, -- landing at the end of a walk or dash (AnimationConfig.living.land)
	landDash: boolean,
	landSide: number, -- the leg the weight lands on (alternates)
	hitSide: number, -- the side the head tips on a hit (alternates)
	benched: boolean, -- on the bench (AnimationConfig.motionQuality `benchDetail`)
	mustPlace: boolean, -- pose the figure next update even off screen (new or redrawn)
	placedAt: Vector3?, -- the body's center at the last posing
	floaters: { Floater },
	floaterCount: number,
	shownColor: Color3?, -- body tint now shown (nil: the body color)
	shownMaterial: Enum.Material?,
	shownTransparency: number,
	baseTransparency: number, -- see-through for summons
	figureLook: any, -- the unit's base Figure look, kept to rebuild the figure at another size or form
	shownLook: any, -- the Figure look drawn now (the base, or the current form's own look)
	formName: string?, -- the current form (UnitConfig forms), if any
	puff: ParticleEmitter?, -- the form-change puff, made on first use
	baseSize: Vector3, -- the hitbox size before any form scale
	boardHeight: number, -- the overhead display's height in studs
	formScale: number, -- the current form's size multiplier (RenderConfig.formLooks `scale`)
	vanishUntil: number, -- see-through while untargetable (Vanish events)
	itemSlots: { ItemSlot }, -- equipped item icons over the health bar
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
	formName: string?, -- the starting form's name (its own look, if it has one: FormLookConfig)
	starPips: boolean?, -- show star pips (default true; creeps, bosses and summons pass false)
	clock: (() -> number)?, -- time source for every animation (default os.clock)
	items: { string }?, -- equipped item ids: a row of item icons over the health bar
	benched: boolean?, -- a bench unit (low effect quality gives it a plain idle)
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

-- Equipped item icons (ItemIcon), centered in a row over the health bar. Returns each icon's center
-- in studs from the overhead display's center (x right, y up; `rowTop` is the row's top, in studs
-- below the display's top edge), for hit-testing hovers and taps (UnitView.itemAtScreen).
local function itemIcons(parent: Instance, items: { string }, rowTop: number, boardHeight: number): { ItemSlot }
	local size, gap = OVERHEAD.itemIconHeight, OVERHEAD.itemIconGap
	local total = #items * size + (#items - 1) * gap
	local slots = {}
	for index, itemId in items do
		local left = (OVERHEAD.width - total) / 2 + (index - 1) * (size + gap)
		local icon = ItemIcon.new(itemId, 12, parent)
		icon.Position = UDim2.fromScale(left / OVERHEAD.width, rowTop / boardHeight)
		icon.Size = UDim2.fromScale(size / OVERHEAD.width, size / boardHeight)
		table.insert(slots, {
			itemId = itemId,
			x = left + size / 2 - OVERHEAD.width / 2,
			y = boardHeight / 2 - (rowTop + size / 2),
		})
	end
	return slots
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
		table.insert(rows, { kind = "items", height = OVERHEAD.itemIconHeight })
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
	local itemSlots: { ItemSlot } = {}
	local top = 0
	for _, row in rows do
		local height = row.height / boardHeight
		if row.kind == "pips" then
			starPips(infoBoard, starLevel, height)
		elseif row.kind == "items" then
			itemSlots = itemIcons(infoBoard, options.items :: { string }, top * boardHeight, boardHeight)
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
		starLevel = starLevel,
		lungeDirection = Vector3.zero,
		attackStart = nil,
		attackDuration = 0,
		attackStyle = nil,
		attackArm = if hand == "left" then 1 else 2,
		alternateArms = hand == "both",
		attackPose = look.attackPose or "recoil",
		windupStart = nil,
		castStart = nil,
		castColor = AnimationConfig.factionColors.summon,
		castStyle = nil,
		castOrb = 1,
		releaseDuration = AnimationConfig.cast.release,
		markers = nil,
		chargeOrb = nil,
		chargeField = nil,
		hitStart = nil,
		knockDirection = Vector3.zero,
		knockStrength = 0,
		stopAt = 0,
		stopUntil = -math.huge, -- timers start in the past: fight time can be negative (a preview)
		stopShake = false,
		flashUntil = -math.huge,
		flashColor = color,
		glowUntil = -math.huge,
		stunUntil = -math.huge,
		stunStars = nil,
		trailUntil = -math.huge,
		cheerStart = nil,
		bubblePop = nil,
		dyingSince = nil,
		puffed = false,
		selected = false,
		phase = math.random(),
		rate = 1 + (math.random() * 2 - 1) * AnimationConfig.living.rateSpread,
		seed = math.random() * 100,
		calm = 1,
		landStart = nil,
		landDash = false,
		landSide = if math.random() < 0.5 then 1 else -1,
		hitSide = 1,
		benched = options.benched == true,
		mustPlace = true,
		placedAt = nil,
		floaters = {},
		floaterCount = 0,
		shownColor = nil,
		shownMaterial = nil,
		shownTransparency = baseTransparency,
		baseTransparency = baseTransparency,
		figureLook = look,
		shownLook = look,
		formName = nil,
		puff = nil,
		baseSize = part.Size,
		boardHeight = boardHeight,
		formScale = 1,
		vanishUntil = -math.huge,
		itemSlots = itemSlots,
	}
	if #itemSlots > 0 then
		withItems[view] = true
	end
	UnitView.setMana(view, options.mana or 0)
	if options.formLook or options.maxFormHealth or options.formName then
		UnitView.setForm(view, options.formLook, options.formHealth, options.maxFormHealth, options.formName)
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

-- A quick puff of smoke around the unit, as it changes into a form with its own look.
local function puff(view: UnitView)
	local emitter = view.puff
	if not emitter then
		local config = RenderConfig.formPuff
		local made = Instance.new("ParticleEmitter")
		made.Texture = "rbxasset://textures/particles/smoke_main.dds" -- built into Roblox
		made.Color = ColorSequence.new(config.color)
		made.LightEmission = config.lightEmission
		made.Transparency = NumberSequence.new(config.transparency, 1)
		made.Lifetime = NumberRange.new(config.lifetime[1], config.lifetime[2])
		made.Speed = NumberRange.new(config.speed[1], config.speed[2])
		made.SpreadAngle = Vector2.new(180, 180)
		made.RotSpeed = NumberRange.new(-90, 90)
		made.Rate = 0
		made.Enabled = false
		made.Parent = view.part
		view.puff = made
		emitter = made
	end
	local height = view.part.Size.Y
	local config = RenderConfig.formPuff
	emitter.Size = NumberSequence.new(height * config.size[1], height * config.size[2])
	emitter:Emit(config.count)
end

-- Redraws the figure with `figureLook` (a form's own look, or the unit's base look) `scale` times
-- its normal size (a giant form), keeping it standing where it is. Returns true if it redrew.
local function redraw(view: UnitView, figureLook: any, scale: number): boolean
	if (view.formScale == scale and view.shownLook == figureLook) or view.dyingSince then
		return false
	end
	view.formScale = scale
	view.shownLook = figureLook
	local old = view.figure
	for i = #old.pieces, 2, -1 do -- piece 1 is the hitbox itself
		old.pieces[i].part:Destroy()
	end
	if old.avatar then
		old.avatar:Destroy() -- its Humanoid, clothing and Highlight
	end
	local oldHeight = view.part.Size.Y
	view.part.Size = view.baseSize * scale
	local lift = Vector3.new(0, (view.part.Size.Y - oldHeight) / 2, 0)
	view.base += lift
	view.moveFrom += lift
	view.moveTo += lift
	view.figure = Figure.new(figureLook, old.color, view.part.Size.Y, view.part, view.baseTransparency)
	view.mustPlace = true
	view.shownTransparency = -1 -- reapply on the next update
	view.shownColor, view.shownMaterial = nil, nil
	view.infoBoard.StudsOffset = Vector3.new(0, view.part.Size.Y / 2 + OVERHEAD.aboveHead + view.boardHeight / 2, 0)
	if view.bubble then
		local size = view.part.Size
		view.bubble.Size = Vector3.one * math.max(size.X, size.Y, size.Z) * RenderConfig.shieldBubbleScale
	end
	return true
end

-- Switches to a new form: its look (a RenderConfig.formLooks entry, or nil for none), its health
-- pool (nil if it has none) and its name (UnitConfig forms). A look with a `mount` color puts the
-- unit on a placeholder horse; any other look removes the horse. A `scale` redraws the unit larger
-- or smaller. A form with its own look (FormLookConfig) is drawn as that look in place of the
-- unit's base figure, with a puff of smoke; a form without one keeps the base figure and its `tint`
-- recolors the body (a placeholder for the form's art).
function UnitView.setForm(view: UnitView, look: any?, formHealth: number?, maxFormHealth: number?, formName: string?)
	local mount = if look and not view.dyingSince then look.mount else nil
	local figureLook, ownLook, extraScale = CharacterLook.formFigure(view.figureLook, formName)
	local lookChanged = figureLook ~= view.shownLook
	local redrawn = redraw(view, figureLook, (if look and look.scale then look.scale else 1) * extraScale)
	if redrawn and lookChanged and view.formName ~= nil then
		puff(view)
	end
	view.formName = formName
	local tint = if look and not ownLook then look.tint else nil
	view.figure.color = tint or view.color
	view.figure.formTint = tint
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

-- How much larger than a normal 1-star this unit is drawn (star level, form, summon and PvE sizes):
-- motion distances in AnimationConfig are for a normal 1-star and scale with this.
function UnitView.sizeFactor(view: UnitView): number
	return view.part.Size.Y / RenderConfig.unitSize.Y
end

-- How large this unit's effects are drawn (AnimationConfig.starScale).
function UnitView.effectScale(view: UnitView): number
	return AnimationConfig.starScale[view.starLevel] or 1
end

-- An attack motion in `style` (AnimationConfig.styles) toward `target`, lasting `duration` and
-- starting at `startAt` (view.clock()). The strike lands at the style's `strike` share of it. Units
-- holding a prop in each hand, and brawlers, switch arms each attack.
function UnitView.attack(view: UnitView, target: UnitView, startAt: number, duration: number, styleName: string)
	local style = UnitMotion.style(styleName)
	local direction = target.part.Position - view.part.Position
	direction = Vector3.new(direction.X, 0, direction.Z)
	if direction.Magnitude > 1e-3 then
		view.lungeDirection = direction.Unit
	end
	if view.alternateArms or style.alternate then
		view.attackArm = 3 - view.attackArm
	end
	view.attackStyle = style
	view.attackStart = startAt
	view.attackDuration = duration
	view.faceTarget = target
end

-- Where a ranged attack's projectile leaves right now: the pointing fingertip (attack pose
-- "point"), else the attacking hand, else (a store model) the chest.
function UnitView.launchPoint(view: UnitView): Vector3
	local figure = view.figure
	if view.attackPose == "point" then
		local angle = if view.attackArm == 1 then view.pose.leftArm else view.pose.rightArm
		local tip = Figure.armTip(figure, view.attackArm, angle, ANIMATION.fingertip * figure.height)
		if tip then
			return tip
		end
	end
	local hand = figure.anchors[if view.attackArm == 1 then "leftHand" else "rightHand"]
	if hand and not figure.isModel then
		return hand.Position
	end
	return view.part.Position
		+ Vector3.new(0, view.part.Size.Y * 0.15, 0)
		+ view.lungeDirection * view.part.Size.X * 0.4
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
		-- Small stars circling over the halo (AnimationConfig.stun).
		local config = AnimationConfig.stun
		local stars = {}
		for _ = 1, config.stars do
			local star = ring:Clone()
			star.Shape = Enum.PartType.Ball
			star.Size = Vector3.one * config.starSize * UnitView.sizeFactor(view)
			star.Color = Color3.new(1, 1, 1)
			star.Parent = view.part
			table.insert(stars, star)
		end
		view.stunStars = stars
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
	rise: number,
	pop: number?
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
	label.TextSize = math.floor(size * (pop or 1) + 0.5)
	label.Parent = view.floatBoard
	table.insert(view.floaters, {
		label = label,
		born = view.clock(),
		duration = duration,
		startY = startY,
		rise = rise,
		size = size,
		pop = pop or 1,
	})
end

-- A number that starts beside the body, rises and fades quickly. Successive numbers on one unit
-- take turns in lanes on alternating sides, with a little jitter, so they do not stack. It pops in
-- `pop` times its size (AnimationConfig.numbers).
local function floatNumber(view: UnitView, text: string, color: Color3, size: number, pop: number?)
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
		RenderConfig.damageNumberRise,
		pop
	)
end

local DAMAGE_COLORS = {
	PHYSICAL = "physicalDamageColor",
	MAGIC = "magicDamageColor",
	TRUE = "trueDamageColor",
}

-- `damageType` is a CombatMath.DamageType value; crits are larger, in their own color, and pop
-- harder; ability hits are a little larger (AnimationConfig.numbers).
function UnitView.damageNumber(view: UnitView, amount: number, damageType: string?, crit: boolean?, ability: boolean?)
	local numbers = AnimationConfig.numbers
	local color = RenderConfig[DAMAGE_COLORS[damageType or "PHYSICAL"] or "physicalDamageColor"]
	if crit then
		floatNumber(view, amount .. "!", RenderConfig.critNumberColor, RenderConfig.critNumberSize, numbers.critPop)
	else
		local size = if ability then numbers.abilitySize else RenderConfig.damageNumberSize
		floatNumber(view, tostring(amount), color, size, numbers.pop)
	end
end

function UnitView.healNumber(view: UnitView, amount: number)
	floatNumber(
		view,
		"+" .. amount,
		RenderConfig.healTextColor,
		RenderConfig.damageNumberSize,
		AnimationConfig.numbers.pop
	)
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

-- A cast wind-up from `startAt` to the release at `releaseAt` (both view.clock()): the arms rise, an
-- orb of `color` (the caster's faction) gathers between the hands, and the body glows in the last
-- part (AnimationConfig.cast). UnitView.cast shows the release.
-- A signature's `style` (AbilitySignatures: "punch") replaces the generic wind-up pose, with an orb
-- `orbScale` times the usual size.
function UnitView.castWindup(
	view: UnitView,
	startAt: number,
	releaseAt: number,
	color: Color3,
	style: string?,
	orbScale: number?
)
	view.windupStart = startAt
	view.castStart = releaseAt
	view.castColor = color
	view.castStyle = style
	view.castOrb = orbScale or 1
end

-- The release of a cast, now: arms thrust up and the body flashes in `color` (default: the color of
-- its wind-up). A signature's `style` plays its own release pose over `releaseDuration`. Ability
-- names are not announced.
function UnitView.cast(view: UnitView, color: Color3?, style: string?, releaseDuration: number?)
	local now = view.clock()
	if color then
		view.castColor = color
	end
	view.castStyle = style
	view.releaseDuration = releaseDuration or AnimationConfig.cast.release
	view.castStart = now
	view.glowUntil = now + AnimationConfig.cast.release * 0.5
end

-- Plays an ultimate's pose keys (UnitMotion.ultimatePose) from `startAt` to `endAt` (the view's
-- clock), design time 0 at `releaseAt` and running at `k` before it.
function UnitView.ultimatePose(view: UnitView, track: any, startAt: number, releaseAt: number, k: number, endAt: number)
	view.ultimate = { track = track, startAt = startAt, releaseAt = releaseAt, endAt = endAt, k = k }
end

-- Shows a status marker (StatusMarkers; AbilityFxConfig.statuses) until `untilTime` (its clock).
function UnitView.mark(view: UnitView, status: string, untilTime: number)
	if not view.dyingSince then
		StatusMarkers.add(view :: any, status, untilTime)
	end
end

-- Shows a hit: a flash (crits: orange), a small knock along `direction` (away from the attacker;
-- nil: the last direction) of `strength` studs at normal size (default AnimationConfig.hit), and a
-- squash that recovers.
function UnitView.flash(view: UnitView, crit: boolean?, direction: Vector3?, strength: number?)
	local config = AnimationConfig.hit
	local now = view.clock()
	view.flashUntil = now + config.flashDuration
	view.flashColor = if crit then config.critFlashColor else config.flashColor
	view.hitStart = now
	view.hitSide = -view.hitSide
	if direction then
		local flat = Vector3.new(direction.X, 0, direction.Z)
		if flat.Magnitude > 1e-3 then
			view.knockDirection = flat.Unit
		end
	end
	view.knockStrength = strength or (if crit then config.critKnock else config.knock)
end

-- Hit-stop: the unit holds its pose for `seconds`; `shake` jitters it (the one that was hit). Not
-- again within AnimationConfig.hitStop.cooldown of the last one, unless `force` (a signature),
-- which also extends a hold already running. Returns whether it holds.
function UnitView.hitStop(view: UnitView, seconds: number, shake: boolean?, force: boolean?): boolean
	local now = view.clock()
	if force and now < view.stopUntil then
		view.stopUntil = math.max(view.stopUntil, now + seconds)
		view.stopShake = view.stopShake or shake == true
		return true
	end
	if not force and now < view.stopUntil + AnimationConfig.hitStop.cooldown then
		return false
	end
	view.stopAt = now
	view.stopUntil = now + seconds
	view.stopShake = shake == true
	return true
end

-- The shield bubble pops in (a new shield).
function UnitView.shieldPop(view: UnitView)
	view.bubblePop = view.clock()
end

-- A victory cheer from `startAt` (view.clock(); now if omitted): hops with arms up.
function UnitView.cheer(view: UnitView, startAt: number?)
	if not view.dyingSince then
		view.cheerStart = startAt or view.clock()
	end
end

local function hideCharge(view: UnitView)
	if view.chargeOrb then
		view.chargeOrb.Transparency = 1
	end
	if view.chargeField then
		view.chargeField.Enabled = false
	end
end

-- Starts the defeat: a stagger back (along `direction`, away from the killer, if given), a crumple
-- to the ground, a fade and a small puff (AnimationConfig.death). Keep updating the view until
-- UnitView.update returns false, then destroy it.
function UnitView.kill(view: UnitView, direction: Vector3?)
	if view.dyingSince then
		return
	end
	view.dyingSince = view.clock()
	view.infoBoard.Enabled = false
	view.trail.Enabled = false
	view.faceTarget = nil
	if direction then
		local flat = Vector3.new(direction.X, 0, direction.Z)
		if flat.Magnitude > 1e-3 then
			view.knockDirection = flat.Unit
		end
	end
	if view.bubble then
		view.bubble.Transparency = 1
	end
	hideCharge(view)
end

function UnitView.isAlive(view: UnitView): boolean
	return view.dyingSince == nil and view.part.Parent ~= nil
end

-- Progress (0-1) of a one-shot animation that started at `start` and lasts `duration`, or nil when
-- it is not playing.
local function progressOf(start: number?, duration: number, now: number): number?
	if not start or now < start or duration <= 0 then
		return nil
	end
	local progress = (now - start) / duration
	return if progress < 1 then progress else nil
end

-- Progress (0-1) of the cast wind-up, or nil outside it.
local function windupOf(view: UnitView, now: number): number?
	local start, release = view.windupStart, view.castStart
	if not start or not release or now < start or now >= release then
		return nil
	end
	return (now - start) / (release - start)
end

-- Whether a point is on screen, or within AnimationConfig.offscreenMargin of it (nil: no).
local function onScreen(point: Vector3?): boolean
	local camera = workspace.CurrentCamera
	if not point or not camera then
		return point ~= nil
	end
	local at = camera:WorldToViewportPoint(point)
	local size = camera.ViewportSize
	local margin = AnimationConfig.offscreenMargin
	return at.Z > 0
		and at.X > -size.X * margin
		and at.X < size.X * (1 + margin)
		and at.Y > -size.Y * margin
		and at.Y < size.Y * (1 + margin)
end

-- 0-1 from any number, the same every time (a unit's glance directions).
local function hash(n: number): number
	local x = math.sin(n * 12.9898) * 43758.5453
	return x - math.floor(x)
end

local function smooth(t: number): number
	return t * t * (3 - 2 * t)
end

-- The living idle (AnimationConfig.living), scaled by `calm`: breathing, a weight shift from leg to
-- leg every few seconds, and the head looking toward the target ahead of the body's turn, or
-- glancing aside now and then when there is none. Each unit runs at its own tempo and phase.
local function livingIdle(view: UnitView, now: number, calm: number)
	local pose = view.pose
	local rate = view.rate
	if calm > 0 then
		local breath = math.sin((now * rate / LIVING.breathPeriod + view.phase * 1.7) * TAU)
		pose.lean -= rad(LIVING.breathLean) * breath * calm
		local open = rad(LIVING.breathArms) * (0.5 + 0.5 * breath) * calm
		pose.leftArmOut = (pose.leftArmOut or 0) + open
		pose.rightArmOut = (pose.rightArmOut or 0) + open
		pose.headPitch = (pose.headPitch or 0) + rad(LIVING.breathHead) * breath * calm

		-- The weight moves from one leg (side 1: the right) to the other, then holds.
		local cycle = now * rate / LIVING.shiftEvery + view.seed
		local index = math.floor(cycle)
		local from = if index % 2 == 0 then 1 else -1
		local side = from * (1 - 2 * smooth(math.clamp((cycle - index) / LIVING.shiftBlend, 0, 1)))
		pose.shift = (pose.shift or 0) + side * LIVING.shift * calm
		pose.roll = (pose.roll or 0) - side * rad(LIVING.shiftRoll) * calm
		pose.headRoll = (pose.headRoll or 0) + side * rad(LIVING.shiftHead) * calm
	end

	local target = view.faceTarget
	local toward = if target and UnitView.isAlive(target) then yawToward(target.base - view.base) else nil
	if toward then
		-- The eyes lead the turn (not only while calm: the body turns between attacks too).
		local max = rad(LIVING.lookMax)
		pose.headYaw = (pose.headYaw or 0) + math.clamp(wrapAngle(toward - view.yaw) * LIVING.lookLead, -max, max)
	elseif calm > 0 then
		local cycle = now * rate / LIVING.glanceEvery + view.seed * 3.1
		local index = math.floor(cycle)
		local into = (cycle - index) / LIVING.glanceHold
		if into < 1 then
			local shape = smooth(math.min(1, math.sin(math.pi * into) * 1.6)) * calm
			pose.headYaw = (pose.headYaw or 0) + rad(LIVING.glanceYaw) * (hash(index + view.seed) * 2 - 1) * shape
			pose.headPitch = (pose.headPitch or 0)
				+ rad(LIVING.glancePitch) * (hash(index * 1.3 + view.seed + 7) - 0.5) * shape
		end
	end
end

-- Works out this frame's pose from the animation state, and returns the body's offset from its
-- place (studs). Later layers add to earlier ones: idle or walking, then an attack, a cast wind-up
-- or release, a hit, a stun, a victory cheer and the defeat. `dt` is the frame time; `detail` adds
-- the living idle (off for bench units at low effect quality).
local function updatePose(view: UnitView, now: number, moving: boolean, dt: number, detail: boolean): Vector3
	local pose = view.pose
	local figure = view.figure
	local height = figure.height
	local rest = figure.restArms
	local idle = math.sin((now * view.rate / ANIMATION.idlePeriod + view.phase) * TAU)
	pose.bob = idle * ANIMATION.idleBob * height
	pose.lean, pose.fall, pose.stride = 0, 0, 0
	pose.twist, pose.crouch, pose.tilt = 0, 0, 0
	pose.leftArmOut, pose.rightArmOut, pose.spin = 0, 0, 0
	pose.headPitch, pose.headYaw, pose.headRoll = 0, 0, 0
	pose.shift, pose.roll = 0, 0
	pose.leftArm = rest[1] + rad(ANIMATION.idleArmSway) * idle
	pose.rightArm = rest[2] - rad(ANIMATION.idleArmSway) * idle
	pose.leftLeg, pose.rightLeg = 0, 0

	-- What plays now. The living idle fades out while anything does, and back in after.
	local style = view.attackStyle
	local attack = if style then progressOf(view.attackStart, view.attackDuration, now) else nil
	local windup = windupOf(view, now)
	local release = progressOf(view.castStart, view.releaseDuration, now)
	local hit = progressOf(view.hitStart, AnimationConfig.hit.duration, now)
	local cheer = progressOf(view.cheerStart, AnimationConfig.victory.duration, now)
	local ultimate = view.ultimate
	if ultimate and now > ultimate.endAt then
		view.ultimate = nil
		ultimate = nil
	end
	local inUltimate = ultimate ~= nil and now >= ultimate.startAt
	local busy = moving
		or attack ~= nil
		or windup ~= nil
		or release ~= nil
		or hit ~= nil
		or cheer ~= nil
		or inUltimate
		or now < view.stunUntil
		or view.dyingSince ~= nil
	local goal = if busy then 0 else 1
	view.calm += math.clamp(goal - view.calm, -dt * LIVING.calmRate, dt * LIVING.calmRate)
	if detail then
		livingIdle(view, now, view.calm)
	end

	if moving then
		-- Heel to toe: lowest at each heel strike (with a quick dip just after it), highest as the
		-- legs pass. The arms counter-swing a little behind the legs, the shoulders counter-twist, the
		-- hips sway over the stance leg and the body leans into the direction; the head stays level.
		local walk = LIVING.walk
		local theta = (now / ANIMATION.walkCycle + view.phase) * TAU
		local step = math.sin(theta)
		local legSwing = rad(ANIMATION.walkLegSwing) * step
		local armSwing = rad(ANIMATION.walkArmSwing) * math.sin(theta - walk.armLag)
		pose.leftLeg, pose.rightLeg = legSwing, -legSwing
		pose.leftArm, pose.rightArm = rest[1] - armSwing, rest[2] + armSwing
		local passing = 0.5 + 0.5 * math.cos(2 * theta)
		local landing = math.max(0, math.sin(2 * theta - math.pi))
		pose.bob = (ANIMATION.walkBob * passing - walk.heelDip * landing) * height
		pose.stride = rad(ANIMATION.horseLegSwing) * step
		pose.twist = (pose.twist or 0) + rad(walk.twist) * step
		pose.shift = (pose.shift or 0) + walk.shift * math.cos(theta)
		pose.roll = (pose.roll or 0) + rad(walk.roll) * math.cos(theta)
		local lean
		if view.moveIsDash then
			-- A dash leans hard at the start and straightens as it slows.
			lean = walk.dashLean * (1 - math.clamp((now - view.moveStart) / view.moveDuration, 0, 1))
		else
			local speed = (view.moveTo - view.moveFrom).Magnitude / math.max(view.moveDuration, 1e-3)
			lean = math.min(walk.maxLean, walk.lean * speed / walk.leanSpeed)
		end
		pose.lean += rad(lean)
		pose.headPitch = (pose.headPitch or 0) - rad(lean) * walk.headSteady
	end

	-- Landing at the end of a walk or dash: the hips drop onto one leg, rise just past rest, settle.
	local land = progressOf(view.landStart, LIVING.land.duration, now)
	if land then
		local config = LIVING.land
		local depth = if view.landDash then config.dashDepth else config.depth
		local drop = if land < config.dropAt
			then 1 - (1 - land / config.dropAt) ^ 2
			else UnitMotion.settle((land - config.dropAt) / (1 - config.dropAt))
		pose.crouch = (pose.crouch or 0) + depth * math.max(drop, 0)
		local over = math.max(-drop, 0) / math.max(AnimationConfig.overlap.settle, 1e-3)
		pose.bob += over * config.lift * height
		pose.shift = (pose.shift or 0) + view.landSide * config.shift * math.max(drop, 0)
		pose.headPitch = (pose.headPitch or 0)
			+ rad(config.headNod) * math.sin(math.pi * math.clamp((land - 0.1) / 0.6, 0, 1))
	end

	local size = UnitView.sizeFactor(view)
	local offset = Vector3.zero
	if style and attack then
		local lunge = UnitMotion.attack(pose, style, attack, view.attackArm)
		offset += view.lungeDirection * (lunge * size)
	end

	local punch = view.castStyle == "punch"
	if windup and punch then
		UnitMotion.punchWindup(pose, windup, now)
	elseif windup then
		UnitMotion.castWindup(pose, windup)
	elseif release and punch then
		offset += view.lungeDirection * (UnitMotion.punchRelease(pose, release) * size)
	elseif release then
		UnitMotion.castRelease(pose, release)
	end
	-- An ultimate's pose keys, eased in at the start; at the end they settle out with a small
	-- overshoot (AnimationConfig.overlap.ultimateSettle).
	if ultimate and inUltimate then
		local t = if now < ultimate.releaseAt
			then (now - ultimate.releaseAt) / math.max(ultimate.k, 1e-3)
			else now - ultimate.releaseAt
		local w = math.min(1, (now - ultimate.startAt) / 0.12)
		local tail = AnimationConfig.overlap.ultimateSettle
		local left = ultimate.endAt - now
		if left < tail then
			w *= UnitMotion.settle(1 - left / tail)
		end
		local lunge, rise = UnitMotion.ultimatePose(pose, ultimate.track, t, w, figure.restArms, now)
		offset += CFrame.Angles(0, view.yaw, 0).LookVector * (lunge * size) + Vector3.new(0, rise * size, 0)
	end

	-- A quick-draw weapon (LookKit `drawn`) is out for every attack, cast and ultimate, put away after.
	Figure.setDrawn(figure, attack ~= nil or windup ~= nil or release ~= nil or inUltimate)

	if hit then
		local knock = UnitMotion.hit(pose, hit, view.hitSide)
		offset += view.knockDirection * (view.knockStrength * knock * size)
	end

	if now < view.stunUntil and not view.dyingSince then
		UnitMotion.stunned(pose, now, view.phase)
	end

	if cheer and not view.dyingSince then
		offset += Vector3.new(0, UnitMotion.victory(pose, cheer) * size, 0)
	end

	if view.dyingSince then
		local progress = math.clamp((now - view.dyingSince) / AnimationConfig.death.duration, 0, 1)
		local step, sink = UnitMotion.death(pose, progress)
		local back = if view.knockDirection.Magnitude > 0
			then view.knockDirection
			else -CFrame.Angles(0, view.yaw, 0).LookVector
		offset += back * (step * size) - Vector3.new(0, sink * size, 0)
	end
	return offset
end

-- The orb that gathers between the hands in a cast wind-up, and (high quality) a field of
-- sparkles drawn in toward it. Made on first use.
local function chargeOrb(view: UnitView): Part
	local orb = view.chargeOrb
	if orb then
		return orb
	end
	local made = Instance.new("Part")
	made.Anchored = true
	made.CanCollide = false
	made.CanQuery = false
	made.CanTouch = false
	made.CastShadow = false
	made.Shape = Enum.PartType.Ball
	made.Material = Enum.Material.Neon
	made.Transparency = 1
	made.Parent = view.part
	view.chargeOrb = made
	if ImpactEffects.allows("charge") then
		local field = made:Clone()
		field.Name = "ChargeField"
		field.Size = Vector3.one * 2.6 * UnitView.sizeFactor(view)
		field.Parent = view.part
		local sparkles = Instance.new("ParticleEmitter")
		sparkles.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		sparkles.LightEmission = 1
		sparkles.LightInfluence = 0
		sparkles.Shape = Enum.ParticleEmitterShape.Sphere
		sparkles.ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface
		sparkles.ShapeInOut = Enum.ParticleEmitterShapeInOut.Inward
		sparkles.Speed = NumberRange.new(4, 5)
		sparkles.Lifetime = NumberRange.new(0.22, 0.28)
		sparkles.Size = NumberSequence.new(0.16 * UnitView.sizeFactor(view), 0)
		sparkles.Transparency = NumberSequence.new(0.1, 0.6)
		sparkles.Rate = AnimationConfig.cast.chargeRate * ImpactEffects.particleShare()
		sparkles.Enabled = false
		sparkles.Parent = field
		view.chargeField = sparkles
	end
	return made
end

-- Advances every animation to `now` (view.clock()); `dt` is the frame time. Returns false once a
-- dying view has finished fading and has no floating text left, when it should be destroyed.
function UnitView.update(view: UnitView, now: number, dt: number): boolean
	local part = view.part

	-- Position: the walk or dash, plus the motion's offset (lunges, knocks, hops, the death).
	local base = currentBase(view, now)
	local moving = view.moveDuration > 0 and now < view.moveStart + view.moveDuration
	if view.moveDuration > 0 and not moving then
		-- Arrived: the landing (AnimationConfig.living.land), on the other leg than the last one.
		if not view.dyingSince then
			view.landStart = view.moveStart + view.moveDuration
			view.landDash = view.moveIsDash
			view.landSide = -view.landSide
		end
		view.moveDuration = 0
	end
	view.base = base

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
	local death = AnimationConfig.death
	local dying = if view.dyingSince then math.clamp((now - view.dyingSince) / death.duration, 0, 1) else nil
	if dying then
		local fade = math.clamp((dying - death.fadeFrom) / (1 - death.fadeFrom), 0, 1)
		transparency = view.baseTransparency + (1 - view.baseTransparency) * fade
	end
	if transparency ~= view.shownTransparency then
		Figure.setTransparency(view.figure, transparency)
		view.shownTransparency = transparency
	end

	-- What the effect quality keeps of the motion (AnimationConfig.motionQuality): bench units may
	-- get a plain idle, and loose parts may hang rigid.
	local quality = AnimationConfig.motionQuality[ImpactEffects.quality()] or AnimationConfig.motionQuality.high
	local detail = quality.benchDetail or not view.benched
	local swinging = quality.secondary and detail
	if view.figure.swingOn ~= swinging then
		Figure.setSwinging(view.figure, swinging)
	end

	-- Hit-stop holds the pose (and its offset) where it was; the one hit jitters.
	local held = now < view.stopUntil
	local offset = updatePose(view, if held then view.stopAt else now, moving, dt, detail)
	if held and view.stopShake then
		local jitter = AnimationConfig.hitStop.jitter * UnitView.sizeFactor(view)
		offset += Vector3.new((math.random() - 0.5) * 2 * jitter, 0, (math.random() - 0.5) * 2 * jitter)
	end
	local center = base + offset
	local rotation = CFrame.Angles(0, view.yaw, 0)
	local hitboxCFrame = CFrame.new(center) * rotation
	local root = CFrame.new(center - Vector3.new(0, part.Size.Y / 2, 0)) * rotation
	-- Off screen (where the quality allows skipping it) only the click box moves; the figure is posed
	-- again once the unit, or where it was last posed, is back in view.
	if view.mustPlace or dt <= 0 or not quality.skipOffscreen or onScreen(center) or onScreen(view.placedAt) then
		Figure.place(view.figure, hitboxCFrame, root, view.pose, dt)
		view.mustPlace = false
		view.placedAt = center
	else
		part.CFrame = hitboxCFrame
	end
	if view.bubble and view.bubble.Transparency < 1 then
		local size = part.Size
		local scale = 1
		local pop = progressOf(view.bubblePop, AnimationConfig.shield.pop, now)
		if pop then
			scale = 1 + (AnimationConfig.shield.popScale - 1) * (1 - pop) * (1 - pop)
		end
		view.bubble.Size = Vector3.one * math.max(size.X, size.Y, size.Z) * RenderConfig.shieldBubbleScale * scale
		view.bubble.CFrame = hitboxCFrame
	end

	-- The death puff, as the body reaches the ground.
	if dying and not view.puffed and dying >= death.puffAt then
		view.puffed = true
		local scale = UnitView.sizeFactor(view)
		ImpactEffects.burst("puff", root.Position + Vector3.new(0, 0.3 * scale, 0), nil, {
			color = death.puffColor,
			count = death.puffCount,
			size = death.puffSize[1] * scale,
			speed = { 2 * scale, 4 * scale },
			lifetime = { 0.35, 0.6 },
			transparency = 0.25,
		})
	end

	StatusMarkers.update(view :: any, now, root, dying ~= nil)

	-- The cast wind-up: the orb gathers between the hands (over the head for a figure with none).
	local windup = if dying then nil else windupOf(view, now)
	if windup then
		local orb = chargeOrb(view)
		local anchors = view.figure.anchors
		local left, right = anchors.leftHand, anchors.rightHand
		local scale = UnitView.sizeFactor(view)
		local at = if left
				and right
				and not view.figure.isModel
			then (left.Position + right.Position) / 2 + Vector3.new(0, 0.25 * scale, 0)
			else center + Vector3.new(0, part.Size.Y * 0.65, 0)
		local charge = windup
		if view.castStyle == "punch" then
			-- The energy gathers at the drawn-back fist, then throbs through the held beat.
			if right and not view.figure.isModel then
				at = right.Position
			end
			local still = AnimationConfig.signaturePoses.punch.stillFrom
			charge = math.min(1, windup / still)
				* (1 + 0.12 * math.sin(now * 40) * math.max(0, windup - still) / (1 - still))
		end
		orb.Color = view.castColor
		orb.Size = Vector3.one
			* math.max(0.05, AnimationConfig.cast.orbSize * view.castOrb * scale * UnitView.effectScale(view) * charge)
		orb.CFrame = CFrame.new(at)
		orb.Transparency = 0.1
		local field = view.chargeField
		if field then
			local fieldPart = field.Parent :: BasePart
			fieldPart.CFrame = CFrame.new(at)
			field.Color = ColorSequence.new(view.castColor)
			field.Enabled = true
		end
	elseif view.chargeOrb and view.chargeOrb.Transparency < 1 then
		hideCharge(view)
	end

	-- Body tint: a hit flash wins over a cast glow (the end of a wind-up, and the release), which
	-- wins over the selection glow.
	-- The glow tints part of the way (AnimationConfig.cast.glowBlend) so the unit still reads.
	local color, material, blend = nil, nil, nil
	local glowing = windup ~= nil and windup >= AnimationConfig.cast.glowFrom
	if now < view.flashUntil then
		color = view.flashColor
	elseif glowing or now < view.glowUntil then
		color, blend = view.castColor, AnimationConfig.cast.glowBlend
	elseif view.selected then
		material = Enum.Material.Neon
	end
	if color ~= view.shownColor or material ~= view.shownMaterial then
		Figure.setTint(view.figure, color, material, blend)
		view.shownColor, view.shownMaterial = color, material
	end

	-- Stunned: a tilted halo wobbles just above the head, with small stars circling it.
	local stunned = now < view.stunUntil and not view.dyingSince
	local ring = view.stunRing
	if ring then
		ring.Transparency = if stunned then 0.2 else 1
		if stunned then
			local head = root * CFrame.new(0, view.figure.height * 1.03, 0)
			ring.CFrame = head * CFrame.Angles(0, now * 4, 0) * CFrame.Angles(0.25, 0, math.pi / 2)
			local stars = view.stunStars or {}
			local radius = ring.Size.Y / 2
			local config = AnimationConfig.stun
			for i, star in stars do
				local angle = now * config.starSpeed + (i - 1) / #stars * TAU
				star.CFrame = head
					* CFrame.new(math.cos(angle) * radius, 0.08 * math.sin(angle * 2), math.sin(angle) * radius)
			end
		end
		for _, star in view.stunStars or {} do
			star.Transparency = if stunned then 0 else 1
		end
	end
	local trailing = now < view.trailUntil and not view.dyingSince
	if view.trail.Enabled ~= trailing then
		view.trail.Enabled = trailing
	end

	-- Floating text pops in, rises with an ease-out and fades over its second half.
	local popTime = AnimationConfig.numbers.popTime
	for i = #view.floaters, 1, -1 do
		local floater = view.floaters[i]
		local age = now - floater.born
		local progress = age / floater.duration
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
			if floater.pop ~= 1 then
				local settle = math.clamp(age / popTime, 0, 1)
				local size = floater.size * (floater.pop + (1 - floater.pop) * settle)
				floater.label.TextSize = math.floor(size + 0.5)
				if settle >= 1 then
					floater.pop = 1
				end
			end
		end
	end

	if view.dyingSince then
		return now - view.dyingSince < death.duration or #view.floaters > 0
	end
	return true
end

function UnitView.setSelected(view: UnitView, selected: boolean)
	view.selected = selected
	UnitView.update(view, view.clock(), 0)
end

function UnitView.destroy(view: UnitView)
	withItems[view] = nil
	view.part:Destroy()
	table.clear(view.floaters)
end

-- The equipped item whose overhead icon is under a screen position (GUI coordinates, like
-- InputObject.Position), among every shown unit; nil if none. Also returns the icon's screen
-- center. Board, bench and combat units all count.
function UnitView.itemAtScreen(screenPosition: Vector2): (string?, Vector2?)
	local camera = workspace.CurrentCamera
	local right, up = camera.CFrame.RightVector, camera.CFrame.UpVector
	local half = OVERHEAD.itemIconHeight / 2
	for view in withItems do
		local part = view.part
		if not part:IsDescendantOf(workspace) then
			if not part.Parent then
				withItems[view] = nil
			end
			continue
		end
		if not view.infoBoard.Enabled then
			continue
		end
		-- The display is centered StudsOffset (camera space) above the unit and faces the camera.
		local center = part.Position + up * view.infoBoard.StudsOffset.Y
		for _, slot in view.itemSlots do
			local world = center + right * slot.x + up * slot.y
			local point, visible = camera:WorldToScreenPoint(world)
			if visible then
				local edge = camera:WorldToScreenPoint(world + right * half)
				local reach = math.abs(edge.X - point.X)
				local screen = Vector2.new(point.X, point.Y)
				local offset = screenPosition - screen
				if math.abs(offset.X) <= reach and math.abs(offset.Y) <= reach then
					return slot.itemId, screen
				end
			end
		end
	end
	return nil, nil
end

return UnitView
