-- Building blocks for the HUD in the UITheme style: scaled screens, dark panels with gold accents,
-- chunky bouncing buttons, outlined text, coin and glyph icons, progress bars, count-up numbers,
-- pops and floating "+N" text. Presentation only.
--
-- Every HUD screen is a ScreenGui inside the device and Roblox UI safe area, with one root frame
-- laid out in UITheme reference pixels and scaled to fit (UI.screen), so layouts work the same
-- on phones and desktops.

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local UITheme = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("UITheme"))

local UI = {}

local COLORS = UITheme.colors
local FONTS = UITheme.fonts
local MOTION = UITheme.motion

-- True on touch devices without a mouse (phones, tablets, Studio's device emulator).
function UI.isTouch(): boolean
	return UserInputService.TouchEnabled and not UserInputService.MouseEnabled
end

-- The UIScale that fits the reference layout into a screen area of `size` pixels, with the
-- device's settings (UITheme.scale.desktop or .touch).
function UI.scaleFor(size: Vector2): number
	local reference = UITheme.scale.reference
	local device = if UI.isTouch() then UITheme.scale.touch else UITheme.scale.desktop
	local fit = math.min(size.X / reference.X, size.Y / reference.Y) * device.multiplier
	return math.clamp(fit, device.min, device.max)
end

-- How much of each screen edge (in screen pixels) the HUD covers, from UITheme.boardInsets at the
-- current scale plus Roblox's top bar, for Arena.setViewInsets.
function UI.boardInsets(): { top: number, bottom: number, left: number, right: number }
	local viewport = workspace.CurrentCamera.ViewportSize
	local inset = GuiService:GetGuiInset()
	local factor = UI.scaleFor(viewport - Vector2.new(0, inset.Y))
	local covered = UITheme.boardInsets
	return {
		top = inset.Y + covered.top * factor,
		bottom = covered.bottom * factor,
		left = covered.left * factor,
		right = covered.right * factor,
	}
end

-- Roots of the match HUD screens, hidden while the player is in the hub (UI.setMatchShown).
local matchRoots: { Frame } = {}
local matchShown = true

-- Shows or hides every match HUD screen (all UI.screen screens except `hub` ones).
function UI.setMatchShown(shown: boolean)
	matchShown = shown
	for _, root in matchRoots do
		root.Visible = shown
	end
end

-- A ScreenGui in the safe area with a root frame in reference pixels, scaled to fit. Returns both;
-- build inside the root. Screens are part of the match HUD (hidden in the hub) unless `hub` is true.
function UI.screen(name: string, displayOrder: number?, hub: boolean?): (ScreenGui, Frame)
	local gui = Instance.new("ScreenGui")
	gui.Name = name
	gui.ResetOnSpawn = false
	gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = displayOrder or 0

	local root = Instance.new("Frame")
	root.Name = "Root"
	root.BackgroundTransparency = 1
	local scale = Instance.new("UIScale")
	scale.Parent = root
	local function fit()
		local size = gui.AbsoluteSize
		if size.X <= 0 or size.Y <= 0 then
			return
		end
		local factor = UI.scaleFor(size)
		scale.Scale = factor
		root.Size = UDim2.fromOffset(size.X / factor, size.Y / factor)
	end
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)
	if not hub then
		root.Visible = matchShown
		table.insert(matchRoots, root)
	end
	root.Parent = gui
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	fit()
	return gui, root
end

local function corner(parent: Instance, radius: number)
	local instance = Instance.new("UICorner")
	instance.CornerRadius = UDim.new(0, radius)
	instance.Parent = parent
end

local function stroke(parent: Instance, color: Color3, thickness: number, mode: Enum.ApplyStrokeMode?): UIStroke
	local instance = Instance.new("UIStroke")
	instance.Color = color
	instance.Thickness = thickness
	instance.ApplyStrokeMode = mode or Enum.ApplyStrokeMode.Border
	instance.LineJoinMode = Enum.LineJoinMode.Round
	instance.Parent = parent
	return instance
end

-- A soft white gloss over the top part of a frame.
local function gloss(parent: Instance, radius: number, height: number)
	local shine = Instance.new("Frame")
	shine.Name = "Gloss"
	shine.Size = UDim2.fromScale(1, height)
	shine.BackgroundColor3 = COLORS.highlight
	shine.BackgroundTransparency = 0.85
	shine.BorderSizePixel = 0
	shine.ZIndex = 0
	corner(shine, radius)
	shine.Parent = parent
end

-- Two short slanted gold stripes in a frame's top-right corner: the anime-style accent.
function UI.accent(parent: GuiObject)
	for i = 0, 1 do
		local stripe = Instance.new("Frame")
		stripe.Name = "Accent"
		stripe.AnchorPoint = Vector2.new(1, 0)
		stripe.Position = UDim2.new(1, -10 - i * 14, 0, 3)
		stripe.Size = UDim2.fromOffset(5, 16)
		stripe.Rotation = UITheme.accentAngle
		stripe.BackgroundColor3 = if i == 0 then COLORS.gold else COLORS.goldDark
		stripe.BorderSizePixel = 0
		stripe.Parent = parent
	end
end

-- A dark panel with rounded corners, a gold outline, a top-lit gradient and (unless `accent` is
-- false) the slanted accent. The accent stripes are child frames, so a panel that lays out its
-- children with a list should pass false or put the list in a child frame.
function UI.panel(parent: Instance, size: UDim2, accent: boolean?): Frame
	local frame = Instance.new("Frame")
	frame.Size = size
	frame.BackgroundColor3 = COLORS.panel
	frame.BackgroundTransparency = COLORS.panelTransparency
	frame.BorderSizePixel = 0
	corner(frame, UITheme.corner)
	stroke(frame, COLORS.gold, UITheme.panelStroke)
	local light = Instance.new("UIGradient")
	light.Rotation = 90
	light.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(150, 150, 165))
	light.Parent = frame
	if accent ~= false then
		UI.accent(frame)
	end
	frame.Parent = parent
	return frame
end

-- Text with a thick dark outline, sized to `textSize` reference pixels.
function UI.text(parent: Instance, text: string, textSize: number, font: Enum.Font?, color: Color3?): TextLabel
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Text = text
	label.TextSize = textSize
	label.Font = font or FONTS.body
	label.TextColor3 = color or COLORS.text
	label.Size = UDim2.fromOffset(0, textSize + 4)
	label.AutomaticSize = Enum.AutomaticSize.X
	stroke(label, COLORS.outline, math.max(1, math.floor(textSize / 9)), Enum.ApplyStrokeMode.Contextual)
	label.Parent = parent
	return label
end

-- A glyph icon (UITheme.icons) as outlined text.
function UI.glyph(parent: Instance, glyph: string, size: number, color: Color3?): TextLabel
	local label = UI.text(parent, glyph, size, FONTS.body, color)
	label.AutomaticSize = Enum.AutomaticSize.None
	label.Size = UDim2.fromOffset(size + 4, size + 4)
	return label
end

-- A gold coin: a disc with a darker rim and a shine.
function UI.coin(parent: Instance, size: number): Frame
	local coin = Instance.new("Frame")
	coin.Name = "Coin"
	coin.Size = UDim2.fromOffset(size, size)
	coin.BackgroundColor3 = COLORS.gold
	coin.BorderSizePixel = 0
	corner(coin, size)
	stroke(coin, COLORS.goldDark, math.max(2, size / 9))
	local inner = Instance.new("Frame")
	inner.AnchorPoint = Vector2.new(0.5, 0.5)
	inner.Position = UDim2.fromScale(0.5, 0.5)
	inner.Size = UDim2.fromScale(0.5, 0.5)
	inner.BackgroundTransparency = 1
	corner(inner, size)
	stroke(inner, COLORS.goldDark, math.max(1, size / 14))
	inner.Parent = coin
	local shine = Instance.new("Frame")
	shine.Position = UDim2.fromScale(0.2, 0.14)
	shine.Size = UDim2.fromScale(0.28, 0.18)
	shine.BackgroundColor3 = COLORS.highlight
	shine.BackgroundTransparency = 0.3
	shine.BorderSizePixel = 0
	corner(shine, size)
	shine.Parent = coin
	coin.Parent = parent
	return coin
end

-- A horizontal row that lays out its children left to right, vertically centered.
function UI.row(parent: Instance, gap: number, size: UDim2?): Frame
	local frame = Instance.new("Frame")
	frame.BackgroundTransparency = 1
	frame.Size = size or UDim2.fromScale(0, 0)
	if not size then
		frame.AutomaticSize = Enum.AutomaticSize.XY
	end
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, gap)
	layout.Parent = frame
	frame.Parent = parent
	return frame
end

-- A coin icon and a number, e.g. the price on a button. Returns the row and the number label.
function UI.price(parent: Instance, amount: number, size: number): (Frame, TextLabel)
	local row = UI.row(parent, 4)
	UI.coin(row, size).LayoutOrder = 1
	local label = UI.text(row, tostring(amount), size + 2, FONTS.number, COLORS.gold)
	label.LayoutOrder = 2
	return row, label
end

local function scaleOf(gui: GuiObject): UIScale
	local existing = gui:FindFirstChild("Motion")
	if existing and existing:IsA("UIScale") then
		return existing
	end
	local scale = Instance.new("UIScale")
	scale.Name = "Motion"
	scale.Parent = gui
	return scale
end

-- A quick grow-and-settle, for numbers that changed and things that appeared.
function UI.pop(gui: GuiObject, amount: number?)
	local scale = scaleOf(gui)
	scale.Scale = amount or MOTION.popScale
	TweenService
		:Create(scale, TweenInfo.new(MOTION.popTime, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 })
		:Play()
end

-- A chunky button: a bright fill with a gloss, a thick dark outline and rounded corners. It squashes
-- when pressed and bounces back on release. Connect to `Activated` to act on it.
function UI.button(parent: Instance, color: Color3, size: UDim2): TextButton
	local button = Instance.new("TextButton")
	button.Size = size
	button.Text = ""
	button.AutoButtonColor = false
	button.BackgroundColor3 = color
	button.BorderSizePixel = 0
	button:SetAttribute("Color", color)
	corner(button, UITheme.buttonCorner)
	stroke(button, COLORS.outline, UITheme.buttonStroke)
	gloss(button, UITheme.buttonCorner, 0.45)
	local gradient = Instance.new("UIGradient")
	gradient.Rotation = 90
	gradient.Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(190, 190, 200))
	gradient.Parent = button

	local scale = scaleOf(button)
	local press = TweenInfo.new(0.06, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local release = TweenInfo.new(MOTION.bounceTime, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	button.InputBegan:Connect(function(input)
		local kind = input.UserInputType
		if kind == Enum.UserInputType.MouseButton1 or kind == Enum.UserInputType.Touch then
			TweenService:Create(scale, press, { Scale = MOTION.pressScale }):Play()
		end
	end)
	button.InputEnded:Connect(function(input)
		local kind = input.UserInputType
		if kind == Enum.UserInputType.MouseButton1 or kind == Enum.UserInputType.Touch then
			scale.Scale = MOTION.bounceScale
			TweenService:Create(scale, release, { Scale = 1 }):Play()
		end
	end)
	button.Parent = parent
	return button
end

-- Shows a button as usable or not: disabled buttons turn gray. Callers also ignore their clicks.
function UI.setEnabled(button: GuiButton, enabled: boolean)
	button.BackgroundColor3 = if enabled then button:GetAttribute("Color") or COLORS.buy else COLORS.disabled
	button:SetAttribute("Enabled", enabled)
end

function UI.isEnabled(button: GuiButton): boolean
	return button:GetAttribute("Enabled") ~= false
end

export type Bar = { frame: Frame, fill: Frame }

-- A rounded progress bar with an outline.
function UI.bar(parent: Instance, size: UDim2, color: Color3): Bar
	local frame = Instance.new("Frame")
	frame.Size = size
	frame.BackgroundColor3 = COLORS.outline
	frame.BorderSizePixel = 0
	corner(frame, 6)
	stroke(frame, COLORS.outline, 2)
	local fill = Instance.new("Frame")
	fill.Size = UDim2.fromScale(0, 1)
	fill.BackgroundColor3 = color
	fill.BorderSizePixel = 0
	corner(fill, 6)
	local shine = Instance.new("UIGradient")
	shine.Rotation = 90
	shine.Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(170, 170, 180))
	shine.Parent = fill
	fill.Parent = frame
	frame.Parent = parent
	return { frame = frame, fill = fill }
end

function UI.setBar(bar: Bar, fraction: number, animate: boolean?)
	local goal = UDim2.fromScale(math.clamp(fraction, 0, 1), 1)
	if animate then
		TweenService:Create(bar.fill, TweenInfo.new(0.3, Enum.EasingStyle.Quad), { Size = goal }):Play()
	else
		bar.fill.Size = goal
	end
end

-- Counts a number label up (or down) to `value`, then pops it when it went up.
function UI.countTo(label: TextLabel, value: number)
	local from = label:GetAttribute("Value")
	label:SetAttribute("Value", value)
	if type(from) ~= "number" or from == value then
		label.Text = tostring(value)
		return
	end
	local counter = Instance.new("NumberValue")
	counter.Value = from
	counter.Changed:Connect(function(current)
		label.Text = tostring(math.round(current))
	end)
	local tween = TweenService:Create(
		counter,
		TweenInfo.new(MOTION.countUpTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Value = value }
	)
	tween.Completed:Connect(function()
		label.Text = tostring(value)
		counter:Destroy()
	end)
	tween:Play()
	if value > from then
		UI.pop(label)
	end
end

-- "+N"-style text that rises from `anchor` and fades.
function UI.floatUp(anchor: GuiObject, text: string, color: Color3)
	local label = UI.text(anchor, text, UITheme.sizes.textLarge, FONTS.display, color)
	label.AnchorPoint = Vector2.new(0.5, 1)
	label.Position = UDim2.fromScale(0.5, 0)
	label.ZIndex = 10
	local info = TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(label, info, { Position = UDim2.new(0.5, 0, 0, -36), TextTransparency = 1 }):Play()
	local outline = label:FindFirstChildOfClass("UIStroke")
	if outline then
		TweenService:Create(outline, info, { Transparency = 1 }):Play()
	end
	task.delay(1, function()
		label:Destroy()
	end)
end

-- Inner padding for a frame, in reference pixels.
function UI.padding(parent: Instance, all: number)
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, all)
	padding.PaddingBottom = UDim.new(0, all)
	padding.PaddingLeft = UDim.new(0, all)
	padding.PaddingRight = UDim.new(0, all)
	padding.Parent = parent
end

-- A vertical list layout for a frame's children.
function UI.list(parent: Instance, gap: number, horizontalAlignment: Enum.HorizontalAlignment?): UIListLayout
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, gap)
	layout.HorizontalAlignment = horizontalAlignment or Enum.HorizontalAlignment.Left
	layout.Parent = parent
	return layout
end

return UI
