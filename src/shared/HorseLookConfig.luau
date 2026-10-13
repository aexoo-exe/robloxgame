-- The colors and markings of each mounted rider's horse (client visuals only), by the rider's unit
-- id (UnitConfig key). The horse's shape is FigureConfig.horse; src/client/HorseKit.luau builds it.
-- Fields (any left out come from `default`):
--   coat, muzzle, mane, hooves, eyes      the horse (no coat: the form's RenderConfig `mount` color)
--   blaze                                 a stripe down the face (optional)
--   socks                                 { 1, 2, 3, 4 }: white lower legs (front left, front right,
--                                         back left, back right) (optional)
--   blanket, trim, saddle, tack, metal    saddle blanket and its edge, saddle, straps and reins,
--                                         stirrup irons
--   pattern                               { kind = "stars" | "tassels", color }: a personal detail
--                                         on the blanket (optional)

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

local function deepFreeze<T>(value: T): T
	if type(value) == "table" and not table.isfrozen(value) then
		for _, child in value :: any do
			deepFreeze(child)
		end
		table.freeze(value)
	end
	return value
end

return deepFreeze({
	default = {
		muzzle = rgb(80, 58, 42),
		mane = rgb(55, 38, 25),
		hooves = rgb(40, 34, 30),
		eyes = rgb(18, 16, 16),
		blanket = rgb(150, 45, 45),
		trim = rgb(230, 200, 120),
		saddle = rgb(72, 46, 28),
		tack = rgb(40, 28, 20),
		metal = rgb(190, 195, 205),
	},

	-- Dark brown with a lighter muzzle; a pale blue blanket with navy edging and small stars.
	spurshot = {
		coat = rgb(78, 52, 34),
		muzzle = rgb(152, 114, 84),
		mane = rgb(32, 22, 16),
		hooves = rgb(38, 32, 28),
		blanket = rgb(150, 200, 236),
		trim = rgb(30, 42, 92),
		saddle = rgb(92, 62, 40),
		tack = rgb(45, 30, 20),
		pattern = { kind = "stars", color = rgb(160, 100, 200) },
	},

	-- Pale grey-white with a darker mane and tail; a purple blanket with gold edging and tassels.
	orbit_breaker = {
		coat = rgb(222, 222, 216),
		muzzle = rgb(190, 186, 182),
		mane = rgb(72, 72, 78),
		hooves = rgb(70, 66, 62),
		blanket = rgb(95, 55, 140),
		trim = rgb(225, 178, 62),
		saddle = rgb(70, 45, 30),
		tack = rgb(40, 28, 20),
		pattern = { kind = "tassels", color = rgb(225, 178, 62) },
	},
})
