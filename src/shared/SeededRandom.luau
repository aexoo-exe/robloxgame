-- Deterministic pseudo-random numbers (Park-Miller "minimal standard" generator).
-- Every intermediate value stays below 2^53, so results are exact and identical on every machine.
-- Pure Luau: no Roblox APIs, so it runs in Lune tests.

local SeededRandom = {}

local MODULUS = 2147483647
local MULTIPLIER = 48271

export type SeededRandom = { state: number }

function SeededRandom.new(seed: number): SeededRandom
	return { state = math.floor(seed) % (MODULUS - 1) + 1 }
end

-- Returns an integer from 1 to max.
function SeededRandom.nextInt(rng: SeededRandom, max: number): number
	rng.state = (rng.state * MULTIPLIER) % MODULUS
	return rng.state % max + 1
end

-- Shuffles a list in place.
function SeededRandom.shuffle(rng: SeededRandom, list: { any })
	for i = #list, 2, -1 do
		local j = SeededRandom.nextInt(rng, i)
		list[i], list[j] = list[j], list[i]
	end
end

return SeededRandom
