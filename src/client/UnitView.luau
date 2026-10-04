-- A placeholder unit: a colored block with its name, star level and a health bar above it.
-- Higher-star units are drawn slightly larger (RenderConfig.starSizeScale).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local RenderConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("RenderConfig"))

local UnitView = {}

export type UnitView = {
	part: Part,
	color: Color3,
	healthFill: Frame,
}

local function partPosition(groundPosition: Vector3, part: Part): Vector3
	return groundPosition + Vector3.new(0, part.Size.Y / 2, 0)
end

function UnitView.new(
	name: string,
	starLevel: number,
	color: Color3,
	groundPosition: Vector3,
	parent: Instance
): UnitView
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = false
	part.Size = RenderConfig.unitSize * RenderConfig.starSizeScale[starLevel]
	part.Position = partPosition(groundPosition, part)
	part.Color = color
	part.Material = Enum.Material.SmoothPlastic

	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.fromOffset(90, 30)
	billboard.StudsOffset = Vector3.new(0, part.Size.Y / 2 + 1, 0)
	billboard.AlwaysOnTop = true
	billboard.Parent = part

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 0, 18)
	label.BackgroundTransparency = 1
	label.Text = name .. " " .. string.rep(RenderConfig.starSymbol, starLevel)
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0
	label.Font = Enum.Font.GothamBold
	label.TextSize = 14
	label.Parent = billboard

	local healthBar = Instance.new("Frame")
	healthBar.Position = UDim2.fromOffset(0, 20)
	healthBar.Size = UDim2.new(1, 0, 0, 8)
	healthBar.BackgroundColor3 = Color3.new(0, 0, 0)
	healthBar.BorderSizePixel = 0
	healthBar.Parent = billboard

	local healthFill = Instance.new("Frame")
	healthFill.Size = UDim2.fromScale(1, 1)
	healthFill.BackgroundColor3 = RenderConfig.healthBarColor
	healthFill.BorderSizePixel = 0
	healthFill.Parent = healthBar

	part.Parent = parent
	return { part = part, color = color, healthFill = healthFill }
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

function UnitView.setHealth(view: UnitView, fraction: number)
	view.healthFill.Size = UDim2.fromScale(math.clamp(fraction, 0, 1), 1)
end

-- Briefly flashes the unit to show it was hit.
function UnitView.flash(view: UnitView)
	view.part.Color = RenderConfig.hitFlashColor
	task.delay(RenderConfig.hitFlashDuration, function()
		view.part.Color = view.color
	end)
end

function UnitView.setSelected(view: UnitView, selected: boolean)
	view.part.Material = if selected then Enum.Material.Neon else Enum.Material.SmoothPlastic
end

function UnitView.destroy(view: UnitView)
	view.part:Destroy()
end

return UnitView
