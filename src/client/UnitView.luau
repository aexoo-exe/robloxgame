-- A placeholder unit: a colored block with its name and star level, a health bar (with any shield
-- shown as a white segment after the health), and a mana bar under it. Floating text shows casts,
-- crits and heals; a marker shows stuns. Higher-star units are drawn slightly larger
-- (RenderConfig.starSizeScale). Presentation only.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local RenderConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("RenderConfig"))

local UnitView = {}

export type UnitView = {
	part: Part,
	color: Color3,
	maxHealth: number,
	maxMana: number?,
	health: number,
	shield: number,
	healthFill: Frame,
	shieldFill: Frame,
	manaFill: Frame,
	stunMarker: TextLabel,
	stunVersion: number,
}

export type Options = {
	maxHealth: number?,
	mana: number?,
	maxMana: number?, -- no mana bar fill if nil
}

local function partPosition(groundPosition: Vector3, part: Part): Vector3
	return groundPosition + Vector3.new(0, part.Size.Y / 2, 0)
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
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = false
	part.Size = RenderConfig.unitSize * RenderConfig.starSizeScale[starLevel]
	part.Position = partPosition(groundPosition, part)
	part.Color = color
	part.Material = Enum.Material.SmoothPlastic

	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.fromOffset(90, 54)
	billboard.StudsOffset = Vector3.new(0, part.Size.Y / 2 + 1.5, 0)
	billboard.AlwaysOnTop = true
	billboard.Parent = part

	local stunMarker = Instance.new("TextLabel")
	stunMarker.Size = UDim2.new(1, 0, 0, 14)
	stunMarker.BackgroundTransparency = 1
	stunMarker.Text = "STUNNED"
	stunMarker.TextColor3 = RenderConfig.stunMarkerColor
	stunMarker.TextStrokeTransparency = 0
	stunMarker.Font = Enum.Font.GothamBlack
	stunMarker.TextSize = 12
	stunMarker.Visible = false
	stunMarker.Parent = billboard

	local label = Instance.new("TextLabel")
	label.Position = UDim2.fromOffset(0, 14)
	label.Size = UDim2.new(1, 0, 0, 18)
	label.BackgroundTransparency = 1
	label.Text = name .. " " .. string.rep(RenderConfig.starSymbol, starLevel)
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0
	label.Font = Enum.Font.GothamBold
	label.TextSize = 14
	label.Parent = billboard

	local healthBar = bar(billboard, 34, 8)
	local healthFill = fill(healthBar, RenderConfig.healthBarColor)
	local shieldFill = fill(healthBar, RenderConfig.shieldColor)
	shieldFill.Size = UDim2.fromScale(0, 1)

	local manaBar = bar(billboard, 44, 4)
	local manaFill = fill(manaBar, RenderConfig.manaBarColor)
	manaFill.Size = UDim2.fromScale(0, 1)

	part.Parent = parent
	local view = {
		part = part,
		color = color,
		maxHealth = options.maxHealth or 1,
		maxMana = options.maxMana,
		health = options.maxHealth or 1,
		shield = 0,
		healthFill = healthFill,
		shieldFill = shieldFill,
		manaFill = manaFill,
		stunMarker = stunMarker,
		stunVersion = 0,
	}
	UnitView.setMana(view, options.mana or 0)
	return view
end

-- Moves the unit to a ground position, sliding over `duration` seconds if given.
function UnitView.moveTo(view: UnitView, groundPosition: Vector3, duration: number?)
	local goal = partPosition(groundPosition, view.part)
	if duration and duration > 0 then
		local tweenInfo = TweenInfo.new(duration, Enum.EasingStyle.Linear)
		TweenService:Create(view.part, tweenInfo, { Position = goal }):Play()
	else
		view.part.Position = goal
	end
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

function UnitView.setShield(view: UnitView, shield: number)
	view.shield = shield
	redrawHealth(view)
end

function UnitView.setMana(view: UnitView, mana: number)
	local fraction = if view.maxMana then math.clamp(mana / view.maxMana, 0, 1) else 0
	view.manaFill.Size = UDim2.fromScale(fraction, 1)
end

-- Shows the stun marker for `seconds`. A newer stun replaces the timer of an older one.
function UnitView.stun(view: UnitView, seconds: number)
	view.stunVersion += 1
	local version = view.stunVersion
	view.stunMarker.Visible = true
	task.delay(seconds, function()
		if view.stunVersion == version and view.part.Parent then
			view.stunMarker.Visible = false
		end
	end)
end

-- Floats `text` up from the unit and fades it out.
function UnitView.popText(view: UnitView, text: string, color: Color3)
	if not view.part.Parent then
		return
	end
	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.fromOffset(160, 24)
	billboard.StudsOffset = Vector3.new(0, view.part.Size.Y / 2 + 4, 0)
	billboard.AlwaysOnTop = true
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = text
	label.TextColor3 = color
	label.TextStrokeTransparency = 0
	label.Font = Enum.Font.GothamBlack
	label.TextSize = 18
	label.Parent = billboard
	billboard.Parent = view.part

	local duration = RenderConfig.popTextDuration
	local info = TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(billboard, info, { StudsOffset = billboard.StudsOffset + Vector3.new(0, 2.5, 0) }):Play()
	TweenService:Create(label, info, { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
	task.delay(duration, function()
		billboard:Destroy()
	end)
end

-- Briefly flashes the unit to show it was hit; crits flash in a different color.
function UnitView.flash(view: UnitView, crit: boolean?)
	view.part.Color = if crit then RenderConfig.critFlashColor else RenderConfig.hitFlashColor
	task.delay(RenderConfig.hitFlashDuration, function()
		if view.part.Parent then
			view.part.Color = view.color
		end
	end)
end

function UnitView.setSelected(view: UnitView, selected: boolean)
	view.part.Material = if selected then Enum.Material.Neon else Enum.Material.SmoothPlastic
end

function UnitView.destroy(view: UnitView)
	view.part:Destroy()
end

return UnitView
