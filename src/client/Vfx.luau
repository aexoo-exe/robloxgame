-- Effect textures on the client: preloads every picked image once (Vfx.start), keeps the unit whose
-- effects are being drawn (Vfx.within: its id, element and color pick its variants), and answers
-- which texture a usage draws with (Vfx.texture; VfxResolve with VfxConfig). An image that failed to
-- load is never chosen (the effect keeps its neon look, with one warning naming the role and id);
-- one still loading is used (VfxConfig.loading.requireLoaded = true waits for it instead).
-- Counts how many requests drew textured or fell back, for the debug report (VfxDebug).
-- Presentation only.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local VfxConfig = require(Shared:WaitForChild("VfxConfig"))
local VfxResolve = require(Shared:WaitForChild("VfxResolve"))

local Vfx = {}

export type Texture = VfxResolve.Texture
export type Context = VfxResolve.Context

-- Image id -> fetch status name ("Success", "Failure", "TimedOut", "Loading", ...); missing: not
-- reported yet.
local statuses: { [number]: string } = {}
local started = false
local preloaded = false -- PreloadAsync has returned
local current: Context? = nil
local cache: { [string]: Texture | false } = {}

-- Draw counts since Vfx.resetCounts: per usage, textured and fallback requests.
local counts: { [string]: { textured: number, fallback: number } } = {}

local FAILED = { Failure = true, TimedOut = true }

-- The pick keys ("<role>:<rank>") that draw with each image id, for warnings and the report.
local function keysOf(id: number): string
	local keys = {}
	for _, role in VfxConfig.roles do
		for _, pick in VfxConfig.picks[role] or {} do
			if pick.image == id then
				table.insert(keys, role .. ":" .. pick.rank)
			end
		end
	end
	return if #keys > 0 then table.concat(keys, ",") else "?"
end

local function record(id: number, status: string)
	if statuses[id] == status then
		return
	end
	statuses[id] = status
	table.clear(cache)
	if FAILED[status] then
		warn(
			string.format(
				"[Vfx] texture %s (id %d) failed to load (%s): its effects use the neon fallback",
				keysOf(id),
				id,
				status
			)
		)
	end
end

-- Preloads every picked image; a failure is warned about once and that image falls back to neon.
function Vfx.start()
	if started then
		return
	end
	started = true
	local ContentProvider = game:GetService("ContentProvider")
	local ids, contents = {}, {}
	for _, id in VfxResolve.images() do
		table.insert(ids, id)
		table.insert(contents, "rbxassetid://" .. string.format("%d", id))
	end
	task.spawn(function()
		local ok, problem = pcall(function()
			ContentProvider:PreloadAsync(contents, function(contentId: string, status: Enum.AssetFetchStatus)
				local id = tonumber(string.match(contentId, "(%d+)$"))
				if id then
					record(id, status.Name)
				end
			end)
		end)
		if not ok then
			warn("[Vfx] preloading failed: " .. tostring(problem))
		end
		preloaded = true
		-- Whatever the callback did not report: ask for each image's status directly.
		for i, id in ids do
			if not statuses[id] then
				local asked, status = pcall(function()
					return ContentProvider:GetAssetFetchStatus(contents[i])
				end)
				if asked and status then
					record(id, status.Name)
				end
			end
		end
	end)
end

-- The fetch status of an image ("unreported" when nothing has said yet).
function Vfx.status(id: number): string
	return statuses[id] or "unreported"
end

-- Whether PreloadAsync has finished.
function Vfx.preloaded(): boolean
	return preloaded
end

-- Whether an image may be drawn: not failed (VfxConfig.loading.requireLoaded: only once loaded).
function Vfx.usable(id: number): boolean
	local status = statuses[id]
	if VfxConfig.loading.requireLoaded then
		return status == "Success"
	end
	return not (status and FAILED[status])
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
	return string.format(
		"%d,%d,%d",
		math.floor(color.R * 15 + 0.5),
		math.floor(color.G * 15 + 0.5),
		math.floor(color.B * 15 + 0.5)
	)
end

local function count(usage: string, textured: boolean)
	local entry = counts[usage]
	if not entry then
		entry = { textured = 0, fallback = 0 }
		counts[usage] = entry
	end
	if textured then
		entry.textured += 1
	else
		entry.fallback += 1
	end
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
	if hit == nil then
		local texture = VfxResolve.resolve(usage, {
			unit = context and context.unit,
			element = context and context.element,
			color = color,
		}, if started then Vfx.usable else nil, mode)
		hit = texture or false
		cache[key] = hit
	end
	count(usage, hit ~= false)
	return hit or nil
end

-- Draw counts per usage since the last reset (the start of a fight or preview).
function Vfx.counts(): { [string]: { textured: number, fallback: number } }
	return counts
end

function Vfx.resetCounts()
	table.clear(counts)
end

-- The color to draw `texture` in for an effect of `color` (VfxResolve.tint).
function Vfx.tint(texture: Texture, color: Color3): Color3
	return VfxResolve.tint(texture, color)
end

return Vfx
