-- The fast-forward indicator: a bright badge under the top bar ("▶▶ 2x") shown while a fight plays
-- faster than normal (CombatPlayback, Playback). It pops when the speed changes and pulses while
-- shown. Presentation only.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local UITheme = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("UITheme"))

local UI = require(script.Parent.UI)

local FastForwardBadge = {}

local badge: Frame? = nil
local label: TextLabel? = nil
local pulse: Tween? = nil
local pulseScale: UIScale? = nil
local shownSpeed = 1

local function build()
	local _, root = UI.screen("FastForwardBadge", 6)
	local frame = Instance.new("Frame")
	frame.AnchorPoint = Vector2.new(0.5, 0)
	frame.Position = UDim2.new(0.5, 0, 0, UITheme.sizes.topBarHeight + 12)
	frame.AutomaticSize = Enum.AutomaticSize.XY
	frame.BackgroundColor3 = UITheme.colors.reroll
	frame.BorderSizePixel = 0
	frame.Visible = false
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = frame
	local stroke = Instance.new("UIStroke")
	stroke.Color = UITheme.colors.outline
	stroke.Thickness = 3
	stroke.Parent = frame
	local row = UI.row(frame, 6)
	UI.padding(row, 6)
	UI.text(row, UITheme.icons.fastForward, UITheme.sizes.textLarge, UITheme.fonts.display).LayoutOrder = 1
	local text = UI.text(row, "", UITheme.sizes.textLarge + 4, UITheme.fonts.display)
	text.LayoutOrder = 2
	frame.Parent = root
	badge, label = frame, text

	-- A gentle, endless pulse of the badge's size while it is shown.
	local scale = Instance.new("UIScale")
	scale.Parent = frame
	pulseScale = scale
	pulse = TweenService:Create(
		scale,
		TweenInfo.new(0.45, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
		{ Scale = 1.08 }
	)
end

-- Shows the badge for `speed` (hidden at 1x or slower).
function FastForwardBadge.setSpeed(speed: number)
	if speed == shownSpeed then
		return
	end
	shownSpeed = speed
	if not badge then
		build()
	end
	local frame, text, tween = badge :: Frame, label :: TextLabel, pulse :: Tween
	frame.Visible = speed > 1
	if speed > 1 then
		text.Text = string.format("%gx", speed)
		tween:Play()
		UI.pop(text, 1.4)
	else
		tween:Cancel()
		local scale = pulseScale :: UIScale
		scale.Scale = 1
	end
end

return FastForwardBadge
