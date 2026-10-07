-- Draws placeholder trait symbols from TraitIconConfig: a colored circle, diamond or square with
-- one or two letters, or the entry's image once it has one. Presentation only.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TraitIconConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("TraitIconConfig"))

local TraitIcon = {}

-- A unit type's traits in display order: origin first, then classes.
function TraitIcon.traitsOf(unit): { string }
	local traits = { unit.origin }
	for _, class in unit.classes do
		table.insert(traits, class)
	end
	return traits
end

local function entryColor(entry): Color3
	return Color3.fromRGB(entry.color[1], entry.color[2], entry.color[3])
end

-- Display name of a trait (its id if it has no entry).
function TraitIcon.name(traitId: string): string
	local entry = TraitIconConfig[traitId]
	return if entry then entry.name else traitId
end

-- One symbol, `size` pixels square. Unknown traits get a gray square with "?".
function TraitIcon.new(traitId: string, size: number, parent: Instance?): Frame
	local entry = TraitIconConfig[traitId]
		or { name = traitId, letters = "?", shape = "square", color = { 120, 120, 120 } }
	local holder = Instance.new("Frame")
	holder.Name = traitId
	holder.Size = UDim2.fromOffset(size, size)
	holder.BackgroundTransparency = 1

	if entry.image then
		local image = Instance.new("ImageLabel")
		image.Size = UDim2.fromScale(1, 1)
		image.BackgroundTransparency = 1
		image.Image = entry.image
		image.Parent = holder
	else
		local color = entryColor(entry)
		local shape = Instance.new("Frame")
		shape.BorderSizePixel = 0
		shape.BackgroundColor3 = color
		shape.AnchorPoint = Vector2.new(0.5, 0.5)
		shape.Position = UDim2.fromScale(0.5, 0.5)
		if entry.shape == "diamond" then
			-- A square turned 45 degrees, scaled so its corners stay inside the holder.
			shape.Size = UDim2.fromScale(0.72, 0.72)
			shape.Rotation = 45
		else
			shape.Size = UDim2.fromScale(1, 1)
		end
		if entry.shape == "circle" then
			local corner = Instance.new("UICorner")
			corner.CornerRadius = UDim.new(0.5, 0)
			corner.Parent = shape
		end
		local stroke = Instance.new("UIStroke")
		stroke.Color = Color3.new(0, 0, 0)
		stroke.Thickness = 1
		stroke.Transparency = 0.3
		stroke.Parent = shape
		shape.Parent = holder

		-- The letters sit beside the shape, not in it, so a diamond's letters stay upright.
		local letters = Instance.new("TextLabel")
		letters.Size = UDim2.fromScale(1, 1)
		letters.BackgroundTransparency = 1
		letters.Text = entry.letters
		local brightness = 0.299 * color.R + 0.587 * color.G + 0.114 * color.B
		letters.TextColor3 = if brightness > 0.55 then Color3.fromRGB(20, 20, 25) else Color3.new(1, 1, 1)
		letters.Font = Enum.Font.GothamBlack
		letters.TextSize = math.max(7, math.floor(size * 0.55))
		letters.Parent = holder
	end

	holder.Parent = parent
	return holder
end

-- A symbol with the trait's name beside it, sized to fit its text.
function TraitIcon.labeled(traitId: string, size: number, textSize: number, parent: Instance?): Frame
	local row = Instance.new("Frame")
	row.Name = traitId
	row.Size = UDim2.fromOffset(0, size)
	row.AutomaticSize = Enum.AutomaticSize.X
	row.BackgroundTransparency = 1
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 3)
	layout.Parent = row

	local symbol = TraitIcon.new(traitId, size, row)
	symbol.LayoutOrder = 1
	local label = Instance.new("TextLabel")
	label.LayoutOrder = 2
	label.Size = UDim2.fromOffset(0, size)
	label.AutomaticSize = Enum.AutomaticSize.X
	label.BackgroundTransparency = 1
	label.Text = TraitIcon.name(traitId)
	label.TextColor3 = Color3.fromRGB(225, 225, 230)
	label.Font = Enum.Font.Gotham
	label.TextSize = textSize
	label.Parent = row

	row.Parent = parent
	return row
end

-- A horizontal row of symbols (with names when `textSize` is given) for `traits`, left to right.
function TraitIcon.row(traits: { string }, size: number, textSize: number?, gap: number?): Frame
	local row = Instance.new("Frame")
	row.BackgroundTransparency = 1
	row.Size = UDim2.new(1, 0, 0, size)
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, gap or 2)
	layout.Parent = row
	for order, traitId in traits do
		local item = if textSize
			then TraitIcon.labeled(traitId, size, textSize, row)
			else TraitIcon.new(traitId, size, row)
		item.LayoutOrder = order
	end
	return row
end

return TraitIcon
