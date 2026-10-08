-- Short celebratory effects: confetti across a HUD screen (round wins) and a sparkle burst with a
-- rising star badge over a unit that just upgraded (BoardController.onUpgrade). Everything removes
-- itself within a couple of seconds. Presentation only; built-in shapes and the default particle
-- texture, no assets.

local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local RenderConfig = require(Shared:WaitForChild("RenderConfig"))
local UITheme = require(Shared:WaitForChild("UITheme"))

local Celebrate = {}

local COLORS = UITheme.colors
local CONFETTI_COUNT = 28
local CONFETTI_COLORS = { COLORS.gold, COLORS.reroll, COLORS.levelUp, COLORS.buy, COLORS.sell }

-- Confetti pieces burst from the top center of `root` (a UI.screen root) and fall away.
function Celebrate.confetti(root: GuiObject)
	for i = 1, CONFETTI_COUNT do
		local piece = Instance.new("Frame")
		piece.AnchorPoint = Vector2.new(0.5, 0.5)
		piece.Position = UDim2.fromScale(0.5, 0.3)
		piece.Size = UDim2.fromOffset(math.random(8, 14), math.random(14, 22))
		piece.BackgroundColor3 = CONFETTI_COLORS[i % #CONFETTI_COLORS + 1]
		piece.BorderSizePixel = 0
		piece.Rotation = math.random(0, 360)
		piece.ZIndex = 40
		piece.Parent = root
		local angle = math.rad(math.random(200, 340))
		local reach = math.random(140, 320)
		local goal = UDim2.new(0.5, math.cos(angle) * reach, 0.3, -math.sin(angle) * reach + 260)
		local duration = 1 + math.random() * 0.6
		TweenService:Create(piece, TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Position = goal,
			Rotation = piece.Rotation + math.random(-540, 540),
			BackgroundTransparency = 1,
		}):Play()
		Debris:AddItem(piece, duration + 0.1)
	end
end

-- A sparkle burst at a world position, in `color`.
function Celebrate.burst(position: Vector3, color: Color3)
	local anchor = Instance.new("Part")
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Transparency = 1
	anchor.Size = Vector3.one
	anchor.Position = position
	local emitter = Instance.new("ParticleEmitter")
	emitter.Color = ColorSequence.new(color)
	emitter.LightEmission = 1
	emitter.Size = NumberSequence.new(0.6, 0)
	emitter.Speed = NumberRange.new(8, 14)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Lifetime = NumberRange.new(0.5, 0.9)
	emitter.Drag = 4
	emitter.Enabled = false
	emitter.Parent = anchor
	anchor.Parent = workspace
	emitter:Emit(36)
	Debris:AddItem(anchor, 1.5)
end

-- A unit reached `starLevel`: a gold burst and a star badge that rises and fades above it.
function Celebrate.starUp(position: Vector3, starLevel: number)
	local color = RenderConfig.overhead.starColors[starLevel] or COLORS.gold
	Celebrate.burst(position, color)

	local anchor = Instance.new("Part")
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Transparency = 1
	anchor.Size = Vector3.one
	anchor.Position = position
	local board = Instance.new("BillboardGui")
	board.Size = UDim2.fromOffset(160, 60)
	board.StudsOffset = Vector3.new(0, 3, 0)
	board.AlwaysOnTop = true
	board.Parent = anchor
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = string.rep(UITheme.icons.star, starLevel)
	label.TextColor3 = color
	label.Font = UITheme.fonts.display
	label.TextScaled = true
	label.Parent = board
	local stroke = Instance.new("UIStroke")
	stroke.Color = COLORS.outline
	stroke.Thickness = 3
	stroke.Parent = label
	anchor.Parent = workspace

	local info = TweenInfo.new(1.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(board, info, { StudsOffset = Vector3.new(0, 6, 0) }):Play()
	TweenService:Create(label, info, { TextTransparency = 1 }):Play()
	TweenService:Create(stroke, info, { Transparency = 1 }):Play()
	Debris:AddItem(anchor, 1.3)
end

return Celebrate
