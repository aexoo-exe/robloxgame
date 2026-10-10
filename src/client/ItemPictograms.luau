-- Placeholder item pictograms, drawn from plain UI frames over the item's category color
-- (ItemIcon). Keyed by the `icon` name in ItemSkinConfig. Each pictogram is a list of shapes in
-- the icon's own space (0-1 across and down, from the top-left), drawn in order:
--   x, y      the shape's center
--   w, h      its size
--   rot       rotation in degrees, clockwise (optional)
--   round     true: fully rounded ends (circles and ovals); a number: corner radius as a share of
--             the shape's size (optional)
--   color     one of the PALETTE names
--   ring      true: only the outline is drawn (optional)
-- Presentation only. An item skin with an `image` is drawn from the image instead.

local PALETTE = {
	light = Color3.fromRGB(246, 246, 250),
	steel = Color3.fromRGB(196, 208, 224),
	dark = Color3.fromRGB(34, 30, 42),
	gold = Color3.fromRGB(255, 212, 80),
	wood = Color3.fromRGB(140, 92, 54),
	red = Color3.fromRGB(205, 50, 60),
	green = Color3.fromRGB(90, 220, 110),
	violet = Color3.fromRGB(236, 205, 255),
	plum = Color3.fromRGB(96, 40, 120),
	leaf = Color3.fromRGB(70, 170, 70),
	cyan = Color3.fromRGB(150, 240, 255),
	straw = Color3.fromRGB(232, 200, 112),
	sand = Color3.fromRGB(218, 176, 104),
	sky = Color3.fromRGB(225, 240, 255),
	leather = Color3.fromRGB(120, 50, 45),
}

local function shape(x: number, y: number, w: number, h: number, color: string, extra: { [string]: any }?)
	local entry = { x = x, y = y, w = w, h = h, color = color }
	for key, value in extra or {} do
		entry[key] = value
	end
	return table.freeze(entry)
end

local function circle(x: number, y: number, size: number, color: string, extra: { [string]: any }?)
	local options = { round = true }
	for key, value in extra or {} do
		options[key] = value
	end
	return shape(x, y, size, size, color, options)
end

local PICTOGRAMS = {
	-- A straight sword leaning right, with a small sun behind it.
	blade = {
		circle(0.24, 0.24, 0.24, "gold"),
		shape(0.56, 0.44, 0.13, 0.62, "steel", { rot = 45 }),
		shape(0.34, 0.66, 0.36, 0.08, "gold", { rot = 45 }),
		shape(0.27, 0.73, 0.08, 0.18, "wood", { rot = 45 }),
		circle(0.2, 0.8, 0.1, "gold"),
	},
	-- A pocket watch.
	clock = {
		shape(0.5, 0.12, 0.16, 0.09, "dark", { round = 0.3 }),
		circle(0.5, 0.54, 0.7, "light"),
		shape(0.5, 0.41, 0.07, 0.28, "dark"),
		shape(0.6, 0.54, 0.22, 0.07, "dark"),
		circle(0.5, 0.54, 0.1, "red"),
	},
	-- An arrow flying up and right.
	arrow = {
		shape(0.48, 0.52, 0.07, 0.72, "gold", { rot = 45 }),
		shape(0.76, 0.24, 0.22, 0.22, "gold", { rot = 45 }),
		shape(0.24, 0.76, 0.06, 0.24, "light"),
		shape(0.24, 0.76, 0.24, 0.06, "light"),
	},
	-- A long thin katana with a round guard and a wrapped hilt.
	katana = {
		shape(0.57, 0.39, 0.08, 0.74, "steel", { rot = 30 }),
		circle(0.38, 0.72, 0.17, "gold"),
		shape(0.31, 0.83, 0.09, 0.22, "dark", { rot = 30 }),
		shape(0.31, 0.83, 0.05, 0.05, "red", { rot = 75 }),
	},
	-- A pale mask with dark eye holes and a grin.
	mask = {
		shape(0.5, 0.5, 0.62, 0.76, "light", { round = true }),
		shape(0.37, 0.43, 0.15, 0.1, "dark", { rot = 15, round = 0.4 }),
		shape(0.63, 0.43, 0.15, 0.1, "dark", { rot = -15, round = 0.4 }),
		shape(0.5, 0.68, 0.3, 0.07, "dark"),
		shape(0.42, 0.68, 0.03, 0.09, "light"),
		shape(0.58, 0.68, 0.03, 0.09, "light"),
	},
	-- A wooden staff topped with a glowing orb.
	staff = {
		shape(0.47, 0.6, 0.08, 0.7, "wood", { rot = 15 }),
		circle(0.58, 0.23, 0.3, "cyan"),
		circle(0.54, 0.19, 0.08, "light"),
	},
	-- A swirled fruit with a stem and a leaf.
	fruit = {
		circle(0.5, 0.58, 0.64, "violet"),
		circle(0.4, 0.52, 0.2, "plum", { ring = true }),
		circle(0.62, 0.66, 0.18, "plum", { ring = true }),
		shape(0.5, 0.2, 0.06, 0.16, "wood", { rot = 15 }),
		shape(0.64, 0.19, 0.2, 0.09, "leaf", { rot = -20, round = true }),
	},
	-- An upright spear with a red tassel.
	spear = {
		shape(0.5, 0.62, 0.07, 0.68, "wood"),
		shape(0.5, 0.22, 0.13, 0.22, "steel"),
		shape(0.5, 0.13, 0.17, 0.17, "steel", { rot = 45 }),
		shape(0.5, 0.35, 0.2, 0.05, "red"),
		shape(0.44, 0.42, 0.04, 0.12, "red"),
	},
	-- A leather book with a gold emblem and a torn corner.
	book = {
		shape(0.5, 0.52, 0.62, 0.72, "leather", { round = 0.08 }),
		shape(0.78, 0.52, 0.07, 0.64, "light"),
		shape(0.22, 0.52, 0.07, 0.72, "dark"),
		shape(0.5, 0.5, 0.17, 0.17, "gold", { rot = 45 }),
		shape(0.74, 0.84, 0.14, 0.1, "dark", { rot = 30 }),
	},
	-- A syringe of green serum, needle up and left.
	syringe = {
		shape(0.27, 0.27, 0.04, 0.22, "steel", { rot = -45 }),
		shape(0.5, 0.5, 0.2, 0.46, "light", { rot = -45, round = 0.2 }),
		shape(0.46, 0.46, 0.12, 0.26, "green", { rot = -45 }),
		shape(0.67, 0.67, 0.05, 0.14, "steel", { rot = -45 }),
		shape(0.74, 0.74, 0.28, 0.06, "dark", { rot = -45 }),
	},
	-- A flexed metal arm with bolts.
	arm = {
		shape(0.4, 0.68, 0.52, 0.2, "steel", { round = 0.4 }),
		shape(0.62, 0.45, 0.2, 0.42, "steel", { round = 0.4 }),
		circle(0.62, 0.22, 0.27, "steel"),
		circle(0.24, 0.68, 0.07, "dark"),
		circle(0.4, 0.68, 0.07, "dark"),
		shape(0.62, 0.5, 0.2, 0.04, "dark"),
	},
	-- A straw doll bound with string.
	doll = {
		circle(0.5, 0.23, 0.26, "straw"),
		shape(0.5, 0.56, 0.22, 0.4, "straw"),
		shape(0.5, 0.45, 0.62, 0.1, "straw"),
		shape(0.42, 0.83, 0.09, 0.24, "straw", { rot = 12 }),
		shape(0.58, 0.83, 0.09, 0.24, "straw", { rot = -12 }),
		shape(0.5, 0.37, 0.2, 0.04, "dark"),
		shape(0.5, 0.67, 0.24, 0.04, "dark"),
	},
	-- A hooded cloak with a small cloud.
	cloak = {
		shape(0.34, 0.62, 0.16, 0.58, "sky", { rot = 12 }),
		shape(0.66, 0.62, 0.16, 0.58, "sky", { rot = -12 }),
		shape(0.5, 0.6, 0.36, 0.6, "sky"),
		circle(0.5, 0.25, 0.32, "sky"),
		circle(0.5, 0.27, 0.16, "dark"),
		circle(0.5, 0.42, 0.09, "gold"),
		circle(0.8, 0.16, 0.14, "light"),
		circle(0.88, 0.2, 0.11, "light"),
	},
	-- A gourd with a cork and a red band.
	gourd = {
		circle(0.5, 0.65, 0.52, "sand"),
		circle(0.5, 0.33, 0.32, "sand"),
		shape(0.5, 0.47, 0.28, 0.06, "red"),
		shape(0.5, 0.14, 0.13, 0.09, "dark", { round = 0.3 }),
	},
	-- A crown with three points and jewels.
	crown = {
		shape(0.25, 0.47, 0.2, 0.2, "gold", { rot = 45 }),
		shape(0.5, 0.41, 0.22, 0.22, "gold", { rot = 45 }),
		shape(0.75, 0.47, 0.2, 0.2, "gold", { rot = 45 }),
		shape(0.5, 0.67, 0.64, 0.2, "gold"),
		circle(0.5, 0.67, 0.11, "red"),
		circle(0.29, 0.67, 0.08, "cyan"),
		circle(0.71, 0.67, 0.08, "cyan"),
	},
}

return table.freeze({
	palette = table.freeze(PALETTE),
	pictograms = table.freeze(PICTOGRAMS),
})
