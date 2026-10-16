-- Effect textures on the client: preloads every picked image once (Vfx.start), keeps the unit whose
-- effects are being drawn (Vfx.within: its id, element and color pick its variants), and answers
-- which texture a usage draws with (Vfx.texture; VfxResolve with VfxConfig). An image that has not
-- loaded, or failed to, is never chosen: the effect keeps its neon look. Presentation only.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local VfxResolve = require(Shared:WaitForChild("VfxResolve"))

local Vfx = {}

export type Texture = VfxResolve.Texture
export type Context = VfxResolve.Context

local loaded: { [number]: boolean } = {} -- image id -> loaded
local started = false
local current: Context? = nil
local cache: { [string]: Texture | false } = {}

-- Preloads every picked image; until each one has loaded, effects that would use it stay neon.
function Vfx.start()
	if started then
		return
	end
	started = true
	local ContentProvider = game:GetService("ContentProvider")
	local ids = {}
	for _, id in VfxResolve.images() do
		table.insert(ids, "rbxassetid://" .. string.format("%d", id))
	end
	task.spawn(function()
		local ok, problem = pcall(function()
			ContentProvider:PreloadAsync(ids, function(contentId: string, status: Enum.AssetFetchStatus)
				local id = tonumber(string.match(contentId, "(%d+)$"))
				if id then
					loaded[id] = status == Enum.AssetFetchStatus.Success
					table.clear(cache)
					if not loaded[id] then
						warn(
							"[Vfx] texture "
								.. contentId
								.. " did not load ("
								.. status.Name
								.. "); its effects stay neon"
						)
					end
				end
			end)
		end)
		if not ok then
			warn("[Vfx] preloading failed: " .. tostring(problem))
		end
	end)
end

local function isLoaded(id: number): boolean
	return loaded[id] == true
end

-- Runs `fn(...)` with `context` (the unit drawing: { unit, element, color }) as the current one, so
-- the effects it makes take that unit's and element's variants (VfxConfig `units`, `elements`).
function Vfx.within(context: Context?, fn: (...any) -> ...any, ...: any): ...any
	local previous = current
	current = context
	local results = table.pack(pcall(fn, ...))
	current = previous
	if not results[1] then
		error(results[2], 0)
	end
	return table.unpack(results, 2, results.n)
end

-- The current unit's context (nil outside Vfx.within).
function Vfx.context(): Context?
	return current
end

local function colorKey(color: Color3?): string
	if not color then
		return "-"
	end
	return string.format("%d,%d,%d", color.R * 15 + 0.5, color.G * 15 + 0.5, color.B * 15 + 0.5)
end

-- The texture `usage` (VfxConfig.uses) draws with now, for an effect of `color`, or nil (neon).
-- `mode` only accepts textures that draw that way ("plane", "billboard", "beam", "particle").
function Vfx.texture(usage: string, color: Color3?, mode: string?): Texture?
	local context = current
	local key = table.concat({
		usage,
		(context and context.unit) or "",
		(context and context.element) or "",
		colorKey(color),
		mode or "",
	}, "|")
	local hit = cache[key]
	if hit ~= nil then
		return hit or nil
	end
	local texture = VfxResolve.resolve(usage, {
		unit = context and context.unit,
		element = context and context.element,
		color = color,
	}, if started then isLoaded else nil, mode)
	cache[key] = texture or false
	return texture
end

return Vfx
