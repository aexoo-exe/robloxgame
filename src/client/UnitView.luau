-- A placeholder unit: a block colored by origin with a dark visor marking its front, its name and star level,
-- a health bar (with any shield shown as a white segment after the health), and a mana bar under
-- it. Higher-star units are drawn slightly larger (RenderConfig.starSizeScale). Presentation only.
-- A unit created with a form health pool (a mounted rider) also gets a pool bar stacked above the
-- health bar, shown while its form has a pool, and its form's look (RenderConfig.formLooks).
--
-- In combat, every animation (gliding, turning, lunges, hit flashes, cast glows, floating numbers,
-- the stun marker, the shield bubble and the death fade) is advanced by UnitView.update, called
-- once per frame. Nothing is scheduled with task.delay or TweenService, so destroying a view
-- removes everything it shows. Views that are never updated (the board during Preparation) just
-- sit where they were placed.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RenderConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("RenderConfig"))

local UnitView = {}

-- Pixel layout of the floating text board, which is centered on the same point as the info board.
local FLOAT_BOARD_SIZE = Vector2.new(220, 220)
local FLOAT_START_Y = 55 -- top of a new number, just above the info board
local CAST_TEXT_START_Y = 25

type Floater = {
	label: TextLabel,
	born: number,
	duration: number,
	startY: number,
	rise: number,
}

export type UnitView = {
	part: Part,
	visor: Part,
	bubble: Part?,
	trail: Trail,
	infoBoard: BillboardGui,
	floatBoard: BillboardGui,
	color: Color3,
	maxHealth: number,
	maxMana: number?,
	health: number,
	shield: number,
	healthFill: Frame,
	shieldFill: Frame,
	manaFill: Frame,
	stunMarker: TextLabel,
	formBar: Frame?, -- the form health pool bar; nil for units created without a pool
	formFill: Frame?,
	maxFormHealth: number?,
	formParts: { Part }, -- the current form's look (placeholder horse)

	-- Animation state, in os.clock() seconds.
	base: Vector3, -- part center without lunge or death offsets
	moveFrom: Vector3,
	moveTo: Vector3,
	moveStart: number,
	moveDuration: number,
	moveIsDash: boolean,
	yaw: number,
	faceTarget: UnitView?,
	lungeDirection: Vector3,
	lungeStart: number?,
	flashUntil: number,
	flashColor: Color3,
	glowUntil: number,
	stunUntil: number,
	trailUntil: number,
	dyingSince: number?,
	floaters: { Floater },
	floaterCount: number,
	shownColor: Color3,
	shownMaterial: Enum.Material,
	baseTransparency: number, -- see-through for summons
}

export type Options = {
	maxHealth: number?,
	mana: number?,
	maxMana: number?, -- no mana bar fill if nil
	yaw: number?, -- initial facing in radians around the vertical axis (0 faces -Z)
	healthColor: Color3?, -- RenderConfig.healthBarColor if nil
	summon: boolean?, -- drawn smaller and see-through, labeled as a summon
	formHealth: number?, -- the starting form's health pool; with maxFormHealth, adds the pool bar
	maxFormHealth: number?,
	formLook: any?, -- the starting form's RenderConfig.formLooks entry
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

local function decoration(parent: Part, size: Vector3, cframe: CFrame, color: Color3): Part
	local piece = Instance.new("Part")
	piece.Anchored = false
	piece.CanCollide = false
	piece.CanQuery = false -- clicks on the board must hit the unit's body
	piece.CanTouch = false
	piece.Massless = true
	piece.Size = size
	piece.CFrame = cframe
	piece.Color = color
	piece.Material = Enum.Material.SmoothPlastic
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = parent
	weld.Part1 = piece
	weld.Parent = piece
	piece.Parent = parent
	return piece
end

local function bar(parent: Instance, y: number, height: number): Frame
	local frame = Instance.new("Frame")
	frame.Position = UDim2.fromOffset(0, y)
	frame.Size = UDim2.new(1, 0, 0, height)
	frame.BackgroundColor3 = Color3.new(0, 0, 0)
	frame.BorderSizePixel = 0
	frame.Parent = parent
	return frame
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
	part.Size = RenderConfig.unitSize
		* RenderConfig.starSizeScale[starLevel]
		* (if options.summon then RenderConfig.summonScale else 1)
	local base = partPosition(groundPosition, part)
	part.CFrame = CFrame.new(base) * CFrame.Angles(0, yaw, 0)
	part.Color = color
	part.Material = Enum.Material.SmoothPlastic

	local size = part.Size
	local visorSize = Vector3.new(size.X * 0.7, size.Y * 0.16, size.Z * 0.35)
	local visor = decoration(
		part,
		visorSize,
		part.CFrame * CFrame.new(0, size.Y * 0.25, -(size.Z + visorSize.Z) / 2 + 0.05),
		RenderConfig.visorColor
	)

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

	local infoBoard = Instance.new("BillboardGui")
	infoBoard.Size = UDim2.fromOffset(90, 54)
	infoBoard.StudsOffset = Vector3.new(0, size.Y / 2 + 1.5, 0)
	infoBoard.AlwaysOnTop = true
	infoBoard.Parent = part

	local stunMarker = Instance.new("TextLabel")
	stunMarker.Size = UDim2.new(1, 0, 0, 14)
	stunMarker.BackgroundTransparency = 1
	stunMarker.Text = "STUNNED"
	stunMarker.TextColor3 = RenderConfig.stunMarkerColor
	stunMarker.TextStrokeTransparency = 0
	stunMarker.Font = Enum.Font.GothamBlack
	stunMarker.TextSize = 12
	stunMarker.Visible = false
	stunMarker.Parent = infoBoard

	local label = Instance.new("TextLabel")
	label.Position = UDim2.fromOffset(0, 14)
	label.Size = UDim2.new(1, 0, 0, 18)
	label.BackgroundTransparency = 1
	label.Text = if options.summon then "summon" else name .. " " .. string.rep(RenderConfig.starSymbol, starLevel)
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0
	label.Font = Enum.Font.GothamBold
	label.TextSize = 14
	label.Parent = infoBoard

	-- A unit with a form health pool gets the pool bar on top; the bars below move down to fit it.
	local formBar, formFill = nil, nil
	local barsOffset = 0
	if options.maxFormHealth then
		barsOffset = 6
		infoBoard.Size = UDim2.fromOffset(90, 54 + barsOffset)
		formBar = bar(infoBoard, 34, 5)
		formFill = fill(formBar, RenderConfig.formHealthColor)
	end

	local healthBar = bar(infoBoard, 34 + barsOffset, 8)
	local healthFill = fill(healthBar, options.healthColor or RenderConfig.healthBarColor)
	local shieldFill = fill(healthBar, RenderConfig.shieldColor)
	shieldFill.Size = UDim2.fromScale(0, 1)

	local manaBar = bar(infoBoard, 44 + barsOffset, 4)
	local manaFill = fill(manaBar, RenderConfig.manaBarColor)
	manaFill.Size = UDim2.fromScale(0, 1)

	local floatBoard = Instance.new("BillboardGui")
	floatBoard.Size = UDim2.fromOffset(FLOAT_BOARD_SIZE.X, FLOAT_BOARD_SIZE.Y)
	floatBoard.StudsOffset = infoBoard.StudsOffset
	floatBoard.AlwaysOnTop = true
	floatBoard.Parent = part

	part.Parent = parent
	local view = {
		part = part,
		visor = visor,
		bubble = nil,
		trail = trail,
		infoBoard = infoBoard,
		floatBoard = floatBoard,
		color = color,
		maxHealth = options.maxHealth or 1,
		maxMana = options.maxMana,
		health = options.maxHealth or 1,
		shield = 0,
		healthFill = healthFill,
		shieldFill = shieldFill,
		manaFill = manaFill,
		stunMarker = stunMarker,
		formBar = formBar,
		formFill = formFill,
		maxFormHealth = options.maxFormHealth,
		formParts = {},

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
		flashUntil = 0,
		flashColor = color,
		glowUntil = 0,
		stunUntil = 0,
		trailUntil = 0,
		dyingSince = nil,
		floaters = {},
		floaterCount = 0,
		shownColor = color,
		shownMaterial = part.Material,
		baseTransparency = if options.summon then RenderConfig.summonTransparency else 0,
	}
	UnitView.setMana(view, options.mana or 0)
	if options.formLook or options.maxFormHealth then
		UnitView.setForm(view, options.formLook, options.formHealth, options.maxFormHealth)
	end
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

-- Switches to a new form: its look (a RenderConfig.formLooks entry, or nil for the plain block) and
-- its health pool (nil if it has none).
function UnitView.setForm(view: UnitView, look: any?, formHealth: number?, maxFormHealth: number?)
	for _, piece in view.formParts do
		piece:Destroy()
	end
	table.clear(view.formParts)
	if look and look.mount and not view.dyingSince then
		-- Placeholder horse: a long low body under the unit, sticking out front and back, and a head
		-- at the front (-Z).
		local size = view.part.Size
		local bodySize = Vector3.new(size.X * 1.05, size.Y * 0.32, size.Z * 1.9)
		local headSize = Vector3.new(size.X * 0.4, size.Y * 0.4, size.Z * 0.45)
		local bottom = -size.Y / 2
		local bodyOffset = CFrame.new(0, bottom + bodySize.Y / 2, 0)
		local headOffset = CFrame.new(0, bottom + bodySize.Y + headSize.Y / 2 - 0.1, -(bodySize.Z - headSize.Z) / 2)
		local body = decoration(view.part, bodySize, view.part.CFrame * bodyOffset, look.mount)
		local head = decoration(view.part, headSize, view.part.CFrame * headOffset, look.mount)
		for _, piece in { body, head } do
			piece.Transparency = view.part.Transparency
			table.insert(view.formParts, piece)
		end
	end
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
	local now = os.clock()
	view.moveFrom = currentBase(view, now)
	view.moveTo = partPosition(groundPosition, view.part)
	view.moveStart = now
	view.moveDuration = duration
	view.moveIsDash = isDash
end

-- Moves the unit to a ground position: glides over `duration` seconds (driven by UnitView.update),
-- or snaps there at once if no duration is given.
function UnitView.moveTo(view: UnitView, groundPosition: Vector3, duration: number?)
	if duration and duration > 0 then
		startMove(view, groundPosition, duration, false)
	else
		local goal = partPosition(groundPosition, view.part)
		view.moveFrom, view.moveTo, view.moveDuration, view.base = goal, goal, 0, goal
		view.part.CFrame = CFrame.new(goal) * CFrame.Angles(0, view.yaw, 0)
	end
end

-- A fast slide with a short trail.
function UnitView.dashTo(view: UnitView, groundPosition: Vector3)
	startMove(view, groundPosition, RenderConfig.dashDuration, true)
	view.trailUntil = os.clock() + RenderConfig.dashDuration
end

-- Turns toward `target` whenever the unit is not moving.
function UnitView.face(view: UnitView, target: UnitView?)
	view.faceTarget = target
end

-- A small lunge toward `target` and back, starting at `startAt` (os.clock(); now if omitted). It
-- peaks halfway through RenderConfig.lungeDuration.
function UnitView.lunge(view: UnitView, target: UnitView, startAt: number?)
	local direction = target.part.Position - view.part.Position
	direction = Vector3.new(direction.X, 0, direction.Z)
	if direction.Magnitude < 1e-3 then
		return
	end
	view.lungeDirection = direction.Unit
	view.lungeStart = startAt or os.clock()
	view.faceTarget = target
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
		local diameter = math.max(size.X, size.Y, size.Z) * RenderConfig.shieldBubbleScale
		local bubble = decoration(view.part, Vector3.one * diameter, view.part.CFrame, RenderConfig.shieldBubbleColor)
		bubble.Shape = Enum.PartType.Ball
		bubble.Material = Enum.Material.ForceField
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

-- Shows the stun marker for `seconds`. A newer stun replaces the timer of an older one.
function UnitView.stun(view: UnitView, seconds: number)
	view.stunUntil = os.clock() + seconds
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
	label.Size = UDim2.fromOffset(FLOAT_BOARD_SIZE.X, size + 6)
	label.BackgroundTransparency = 1
	label.Text = text
	label.TextColor3 = color
	label.TextStrokeTransparency = 0
	label.Font = Enum.Font.GothamBlack
	label.TextSize = size
	label.Parent = view.floatBoard
	table.insert(view.floaters, {
		label = label,
		born = os.clock(),
		duration = duration,
		startY = startY,
		rise = rise,
	})
end

-- A number that floats up and fades. Successive numbers on one unit take turns in a few lanes.
local function floatNumber(view: UnitView, text: string, color: Color3, size: number)
	local lanes = RenderConfig.damageNumberLanes
	local lane = view.floaterCount % #lanes + 1
	view.floaterCount += 1
	-- Alternate lanes also start a little higher, so neighbors do not line up.
	local startY = FLOAT_START_Y - (lane % 2) * 10
	addFloater(
		view,
		text,
		color,
		size,
		lanes[lane],
		startY,
		RenderConfig.damageNumberDuration,
		RenderConfig.damageNumberRise
	)
end

local DAMAGE_COLORS = {
	PHYSICAL = "physicalDamageColor",
	MAGIC = "magicDamageColor",
	TRUE = "trueDamageColor",
}

-- `damageType` is a CombatMath.DamageType value; crits are drawn larger.
function UnitView.damageNumber(view: UnitView, amount: number, damageType: string?, crit: boolean?)
	local color = RenderConfig[DAMAGE_COLORS[damageType or "PHYSICAL"] or "physicalDamageColor"]
	if crit then
		floatNumber(view, amount .. "!", color, RenderConfig.critNumberSize)
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

-- Sets a new max health (and current health), as after a MaxHealth bonus.
function UnitView.setMaxHealth(view: UnitView, maxHealth: number, health: number)
	view.maxHealth = maxHealth
	UnitView.setHealth(view, health)
end

-- Floats `text` up from above the unit and fades it out (ability names, buffs).
function UnitView.popText(view: UnitView, text: string, color: Color3)
	addFloater(
		view,
		text,
		color,
		RenderConfig.floatTextSize,
		0,
		CAST_TEXT_START_Y,
		RenderConfig.popTextDuration,
		RenderConfig.damageNumberRise / 2
	)
end

-- Shows the ability name above the caster and makes it glow briefly.
function UnitView.cast(view: UnitView, abilityName: string)
	view.glowUntil = os.clock() + RenderConfig.castGlowDuration
	UnitView.popText(view, abilityName, RenderConfig.castTextColor)
end

-- Briefly flashes the unit to show it was hit; crits flash in a different color.
function UnitView.flash(view: UnitView, crit: boolean?)
	view.flashUntil = os.clock() + RenderConfig.hitFlashDuration
	view.flashColor = if crit then RenderConfig.critFlashColor else RenderConfig.hitFlashColor
end

-- Starts the death fade. Keep updating the view until UnitView.update returns false, then destroy it.
function UnitView.kill(view: UnitView)
	if view.dyingSince then
		return
	end
	view.dyingSince = os.clock()
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

-- Advances every animation to `now` (os.clock()); `dt` is the frame time. Returns false once a
-- dying view has finished fading and has no floating text left, when it should be destroyed.
function UnitView.update(view: UnitView, now: number, dt: number): boolean
	local part = view.part

	-- Position: the glide or dash, plus any lunge, minus any death sink.
	local base = currentBase(view, now)
	local moving = view.moveDuration > 0 and now < view.moveStart + view.moveDuration
	if view.moveDuration > 0 and not moving then
		view.moveDuration = 0
	end
	view.base = base
	local offset = Vector3.zero
	if view.lungeStart and now >= view.lungeStart then
		local progress = (now - view.lungeStart) / RenderConfig.lungeDuration
		if progress >= 1 then
			view.lungeStart = nil
		else
			offset = view.lungeDirection * (RenderConfig.lungeDistance * math.sin(math.pi * progress))
		end
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
	if view.dyingSince then
		local progress = math.clamp((now - view.dyingSince) / RenderConfig.deathFadeDuration, 0, 1)
		transparency = view.baseTransparency + (1 - view.baseTransparency) * progress
		offset -= Vector3.new(0, RenderConfig.deathSinkDistance * progress, 0)
	end

	local cframe = CFrame.new(base + offset) * CFrame.Angles(0, view.yaw, 0)
	if part.CFrame ~= cframe then
		part.CFrame = cframe
	end
	if part.Transparency ~= transparency then
		part.Transparency = transparency
		view.visor.Transparency = transparency
		for _, piece in view.formParts do
			piece.Transparency = transparency
		end
	end

	-- Color: a hit flash wins over a cast glow.
	local color, material = view.color, Enum.Material.SmoothPlastic
	if now < view.flashUntil then
		color = view.flashColor
	elseif now < view.glowUntil then
		color, material = RenderConfig.castGlowColor, Enum.Material.Neon
	end
	if color ~= view.shownColor then
		part.Color = color
		view.shownColor = color
	end
	if material ~= view.shownMaterial then
		part.Material = material
		view.shownMaterial = material
	end

	local stunned = now < view.stunUntil and not view.dyingSince
	if view.stunMarker.Visible ~= stunned then
		view.stunMarker.Visible = stunned
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
	view.part.Material = if selected then Enum.Material.Neon else Enum.Material.SmoothPlastic
	view.shownMaterial = view.part.Material
end

function UnitView.destroy(view: UnitView)
	view.part:Destroy()
	table.clear(view.floaters)
end

return UnitView
