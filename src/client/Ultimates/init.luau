-- The signature ultimate registry: one child module per unit id (src/client/Ultimates/<unit id>),
-- each returning its timeline (Cinematic: pose, beats, release, event). Its tier, lengths and notes
-- are in UltimateConfig. A unit with no module keeps the generated ability effects (AbilityFx).
-- Presentation only.

local Ultimates = {}

local cache: { [string]: any } = {}

-- The ultimate of a unit type, or nil. A module that fails to load warns once and is left out.
function Ultimates.of(unitType: string): any?
	local cached = cache[unitType]
	if cached ~= nil then
		return cached or nil
	end
	local module = script:FindFirstChild(unitType)
	local def = false
	if module then
		local ok, result = pcall(require, module)
		if ok and type(result) == "table" then
			def = result
		else
			warn("[Ultimates] " .. unitType .. " failed to load: " .. tostring(result))
		end
	end
	cache[unitType] = def
	return def or nil
end

return Ultimates
