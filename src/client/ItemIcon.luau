-- Draws item icons from ItemSkinConfig: a rounded square in the item's category color with the
-- item's pictogram (ItemPictograms) on it, or the skin's image once it has one. Every shape is
-- sized in scale, so an icon draws the same at any size, in screen GUIs and over units on the
-- board. Also gives an item's display name and effect text (Items.describe). Presentation only.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ItemConfig = require(Shared:WaitForChild("ItemConfig"))
local ItemSkinConfig = require(Shared:WaitForChild("ItemSkinConfig"))
local Items = require(Shared:WaitForChild("Items"))

local ItemPictograms = require(script.Parent.ItemPictograms)

local ItemIcon = {}

local OUTLINE = Color3.new(0, 0, 0)
local STROKED_FROM = 24 -- pixels: smaller icons draw their shapes without outlines

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

-- Draws pictogram `name` into `parent` (any size; shapes are in scale). Unknown names draw a "?".
function ItemIcon.drawPictogram(parent: GuiObject, name: string?, stroked: boolean?)
	local shapes = if name then ItemPictograms.pictograms[name] else nil
	if not shapes then
		local unknown = Instance.new("TextLabel")
		unknown.Size = UDim2.fromScale(1, 1)
		unknown.BackgroundTransparency = 1
		unknown.Text = "?"
		unknown.TextScaled = true
		unknown.TextColor3 = Color3.new(1, 1, 1)
		unknown.Font = Enum.Font.GothamBlack
		unknown.Parent = parent
		return
	end
	local canvas = Instance.new("Frame")
	canvas.Name = "Pictogram"
	canvas.AnchorPoint = Vector2.new(0.5, 0.5)
	canvas.Position = UDim2.fromScale(0.5, 0.5)
	canvas.Size = UDim2.fromScale(0.86, 0.86)
	canvas.BackgroundTransparency = 1
	canvas.Parent = parent
	for order, spec in shapes do
		local color = ItemPictograms.palette[spec.color] or Color3.new(1, 1, 1)
		local piece = Instance.new("Frame")
		piece.AnchorPoint = Vector2.new(0.5, 0.5)
		piece.Position = UDim2.fromScale(spec.x, spec.y)
		piece.Size = UDim2.fromScale(spec.w, spec.h)
		piece.Rotation = spec.rot or 0
		piece.BorderSizePixel = 0
		piece.ZIndex = order + 1
		piece.BackgroundColor3 = color
		piece.BackgroundTransparency = if spec.ring then 1 else 0
		if spec.round then
			local corner = Instance.new("UICorner")
			corner.CornerRadius = if spec.round == true then UDim.new(0.5, 0) else UDim.new(spec.round, 0)
			corner.Parent = piece
		end
		if spec.ring or stroked then
			local stroke = Instance.new("UIStroke")
			stroke.Color = if spec.ring then color else OUTLINE
			stroke.Thickness = if spec.ring then 2 else 1
			stroke.Transparency = if spec.ring then 0 else 0.45
			stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
			stroke.Parent = piece
		end
		piece.Parent = canvas
	end
end

-- One icon, `size` pixels square (callers may resize the holder afterwards; everything inside
-- scales with it). Returns the holder frame; its UIStroke can be recolored to highlight it.
function ItemIcon.new(itemId: string, size: number, parent: Instance?): Frame
	local skin = ItemSkinConfig.items[itemId]
	local holder = Instance.new("Frame")
	holder.Name = itemId
	holder.Size = UDim2.fromOffset(size, size)
	holder.BackgroundColor3 = ItemIcon.color(itemId)
	holder.BorderSizePixel = 0
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.2, 0)
	corner.Parent = holder
	local stroke = Instance.new("UIStroke")
	stroke.Color = OUTLINE
	stroke.Thickness = 1
	stroke.Transparency = 0.3
	stroke.Parent = holder

	if skin and skin.image then
		local image = Instance.new("ImageLabel")
		image.Size = UDim2.fromScale(1, 1)
		image.BackgroundTransparency = 1
		image.Image = skin.image
		image.ScaleType = Enum.ScaleType.Fit
		image.Parent = holder
	else
		ItemIcon.drawPictogram(holder, if skin then skin.icon else nil, size >= STROKED_FROM)
	end

	holder.Parent = parent
	return holder
end

-- Highlights (or un-highlights) an icon made by ItemIcon.new.
function ItemIcon.setHighlight(icon: Frame, color: Color3?)
	local stroke = icon:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Color = color or OUTLINE
		stroke.Thickness = if color then 3 else 1
		stroke.Transparency = if color then 0 else 0.3
	end
end

return ItemIcon
