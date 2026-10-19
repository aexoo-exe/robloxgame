-- Sound effects by name (client presentation only; src/client/Sfx.luau plays them). Fill each `id`
-- with a Creator Store audio asset id ("rbxassetid://123..." or just the number). An empty id plays
-- nothing, except a `fallback`: the built-in placeholder sound of that role (UltimateConfig.sounds)
-- plays until the id is filled.
--
--   id            the audio asset ("" until chosen)
--   volume        0-1
--   pitch         { min, max } playback speed, picked at random per play (variation)
--   volumeJitter  each play's volume varies by up to this share (0.1: +-10%)
--   fallback      UltimateConfig.sounds role used while `id` is empty (nil: silent)

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
	sounds = {
		-- A blade drawn back, heat building: a short rising metallic scrape with a low fire crackle
		-- under it (~0.4 s), ending on a held breath.
		-- (No fallback: the built-in "charge" ping played as a monotone ding before the cast.)
		windup = { id = "", volume = 0.45, pitch = { 0.97, 1.03 }, volumeJitter = 0.08 },
		-- One fast blade swing through the air: a sharp, bright whoosh (~0.2 s), no impact in it.
		whoosh = { id = "74419593834838", volume = 0.5, pitch = { 0.92, 1.1 }, volumeJitter = 0.1, fallback = "whoosh" },
		-- A burst of flame catching: a soft "fwoomp" with crackle (~0.6 s), not an explosion.
		fireBurst = { id = "96009794895457", volume = 0.5, pitch = { 0.94, 1.06 }, volumeJitter = 0.1 },
		-- A sword connecting: a short, punchy slice-and-thud (~0.15 s), cartoon-anime style.
		hitImpact = { id = "101309544882556", volume = 0.55, pitch = { 0.9, 1.1 }, volumeJitter = 0.1 },
		-- The finisher: a deep, heavy boom with a fiery tail (~0.8 s), the loudest of the set.
		finisherBoom = { id = "138533090376585", volume = 0.65, pitch = { 0.95, 1.02 }, volumeJitter = 0.05 },
	},
})
