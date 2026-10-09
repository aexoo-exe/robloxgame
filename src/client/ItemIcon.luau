-- Draws placeholder item icons from ItemSkinConfig: a rounded square in the item's category color
-- with one or two letters, or the skin's image once it has one. Also gives an item's display name
-- and effect text (Items.describe). Presentation only.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ItemConfig = require(Shared:WaitForChild("ItemConfig"))
local ItemSkinConfig = require(Shared:WaitForChild("ItemSkinConfig"))
local Items = require(Shared:WaitForChild("Items"))

local ItemIcon = {}

-- The item's category color.
function ItemIcon.color(itemId: string): Color3
	local entry = ItemConfig.items[itemId]
	local rgb = entry and ItemSkinConfig.categoryColors[entry.category] or { 120, 120, 120 }
	return Color3.fromRGB(rgb[1], rgb[2], rgb[3])
end

function ItemIcon.name(itemId: string): string
	local skin = ItemSkinConfig.items[itemId]
	return if skin then skin.name else itemId
end

-- The item's effect text with its current numbers.
function ItemIcon.text(itemId: string): string
	return Items.describe(itemId, ItemSkinConfig)
end

-- One icon, `size` pixels square. Returns the holder frame; its UIStroke can be recolored to
-- highlight it.
function ItemIcon.new(itemId: string, size: number, parent: Instance?): Frame
	local skin = ItemSkinConfig.items[itemId]
	local holder = Instance.new("Frame")
	holder.Name = itemId
	holder.Size = UDim2.fromOffset(size, size)
	holder.BackgroundColor3 = ItemIcon.color(itemId)
	holder.BorderSizePixel = 0
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, math.max(3, math.floor(size * 0.2)))
	corner.Parent = holder
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.new(0, 0, 0)
	stroke.Thickness = 1
	stroke.Transparency = 0.3
	stroke.Parent = holder

	if skin and skin.image then
		local image = Instance.new("ImageLabel")
		image.Size = UDim2.fromScale(1, 1)
		image.BackgroundTransparency = 1
		image.Image = skin.image
		image.Parent = holder
	else
		local letters = Instance.new("TextLabel")
		letters.Size = UDim2.fromScale(1, 1)
		letters.BackgroundTransparency = 1
		letters.Text = if skin then skin.letters else "?"
		letters.TextColor3 = Color3.new(1, 1, 1)
		letters.TextStrokeTransparency = 0.5
		letters.Font = Enum.Font.GothamBlack
		letters.TextSize = math.max(7, math.floor(size * 0.45))
		letters.Parent = holder
	end

	holder.Parent = parent
	return holder
end

-- Highlights (or un-highlights) an icon made by ItemIcon.new.
function ItemIcon.setHighlight(icon: Frame, color: Color3?)
	local stroke = icon:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Color = color or Color3.new(0, 0, 0)
		stroke.Thickness = if color then 3 else 1
		stroke.Transparency = if color then 0 else 0.3
	end
end

return ItemIcon
