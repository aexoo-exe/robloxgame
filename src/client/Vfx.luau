-- Effect textures on the client: preloads every picked image, staggered and retried (Vfx.start),
-- keeps the unit whose effects are being drawn (Vfx.within: its id, element and color pick its
-- variants), and answers which texture a usage draws with (Vfx.texture; VfxResolve with VfxConfig).
-- An image is drawn while it loads; only one whose every retry failed falls back to neon (one
-- warning naming the role and id), and those are asked about again at draw time, so a late load
-- still shows. VfxConfig.loading.requireLoaded = true waits for a confirmed load instead.
-- Counts how many requests drew textured or fell back, for the debug report (VfxDebug).
-- Presentation only.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local VfxConfig = require(Shared:WaitForChild("VfxConfig"))
local VfxPicks = require(Shared:WaitForChild("VfxPicks"))
local VfxResolve = require(Shared:WaitForChild("VfxResolve"))

local Vfx = {}

export type Texture = VfxResolve.Texture
export type Context = VfxResolve.Context

-- Per image id: its last fetch status name ("Success", "Failure", "TimedOut", "Loading", ...),
-- preload attempts so far, whether it has failed for good (every retry failed), and when its status
-- was last asked again at draw time.
type Load = { status: string, attempts: number, failed: boolean, checkedAt: number }
local loads: { [number]: Load } = {}
local started = false
local preloaded = false -- the staggered first pass has gone through every image
local current: Context? = nil
local cache: { [string]: Texture | false } = {}
local recheckedAt = 0

-- Draw counts since Vfx.resetCounts: per usage, textured and fallback requests.
local counts: { [string]: { textured: number, fallback: number } } = {}

local FAILED = { Failure = true, TimedOut = true }
local LOADING = VfxConfig.loading

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

local function contentOf(id: number): string
	return "rbxassetid://" .. string.format("%d", id)
end

local function loadOf(id: number): Load
	local entry = loads[id]
	if not entry then
		entry = { status = "unreported", attempts = 0, failed = false, checkedAt = 0 }
		loads[id] = entry
	end
	return entry
end

-- The image's fetch status right now (ContentProvider), or nil if it cannot be asked.
local function fetchStatus(id: number): string?
	local ok, status = pcall(function()
		return game:GetService("ContentProvider"):GetAssetFetchStatus(contentOf(id))
	end)
	return if ok and status then status.Name else nil
end

-- Records a status; a change makes every choice be made again.
local function record(id: number, status: string)
	local entry = loadOf(id)
	if status == "Success" and entry.failed then
		entry.failed = false
		print(string.format("[Vfx] texture %s (id %d) loaded after all: drawn from now on", keysOf(id), id))
	end
	if entry.status ~= status then
		entry.status = status
		table.clear(cache)
	end
end

-- One preload attempt of an image. A failure (or no answer) is retried after
-- VfxConfig.loading.retryDelays; only when every attempt has failed is it given up on (and drawn
-- neon), with one warning naming its pick and id.
local function preload(id: number)
	local entry = loadOf(id)
	entry.attempts += 1
	local reported: string? = nil
	local ok = pcall(function()
		game:GetService("ContentProvider"):PreloadAsync({ contentOf(id) }, function(_, status: Enum.AssetFetchStatus)
			reported = status.Name
		end)
	end)
	local status = fetchStatus(id) or reported or (if ok then "Loading" else "Failure")
	if status == "Success" or (reported == "Success" and not FAILED[status]) then
		record(id, "Success")
		return
	end
	record(id, status)
	local delays = LOADING.retryDelays
	if entry.attempts <= #delays then
		task.delay(delays[entry.attempts], preload, id)
	elseif FAILED[status] then
		entry.failed = true
		table.clear(cache)
		warn(
			string.format(
				"[Vfx] texture %s (id %d) failed to load after %d tries (%s): its effects use the neon fallback",
				keysOf(id),
				id,
				entry.attempts,
				status
			)
		)
	end
end

-- One warning in Output once every picked image has loaded or given up (or after `wait` seconds):
-- each pick's key, name, image id and result, so a texture that silently draws neon shows up.
local SUMMARY_WAIT = 45
local function summarize()
	local lines, loaded, total = {}, 0, 0
	for _, role in VfxConfig.roles do
		for _, pick in VfxConfig.picks[role] or {} do
			local key = role .. ":" .. pick.rank
			if not pick.image then
				table.insert(
					lines,
					string.format("  %-13s %-20s NOT UPLOADED (%s)", key, tostring(pick.name), tostring(pick.pending))
				)
				continue
			end
			total += 1
			local entry = loads[pick.image]
			local result
			if entry and entry.status == "Success" then
				loaded += 1
				result = "loaded"
			elseif entry and entry.failed then
				result = "FAILED: " .. entry.status .. " after " .. entry.attempts .. " tries (drawn neon)"
			else
				result = "not loaded yet: "
					.. (if entry then entry.status else "never requested")
					.. " (drawn while loading)"
			end
			table.insert(
				lines,
				string.format("  %-13s %-20s image %d  %s", key, tostring(pick.name), pick.image, result)
			)
		end
	end
	warn(
		string.format(
			"[Vfx] texture load summary (VfxPicks generated %s): %d of %d loaded\n%s",
			tostring(VfxPicks.generated),
			loaded,
			total,
			table.concat(lines, "\n")
		)
	)
end

-- Preloads every picked image, a few at a time (VfxConfig.loading.stagger seconds apart), retrying
-- failures. Images are drawn while they load (Roblox loads them on first use anyway).
function Vfx.start()
	if started then
		return
	end
	started = true
	task.spawn(function()
		local ids = VfxResolve.images()
		for _, id in ids do
			loadOf(id)
			task.spawn(preload, id)
			task.wait(LOADING.stagger)
		end
		preloaded = true
		-- Wait until every image has loaded or been given up on (retries included), then report once.
		local deadline = os.clock() + SUMMARY_WAIT
		while os.clock() < deadline do
			local settled = true
			for _, id in ids do
				local entry = loads[id]
				if not (entry and (entry.status == "Success" or entry.failed)) then
					settled = false
					break
				end
			end
			if settled then
				break
			end
			task.wait(1)
		end
		summarize()
	end)
end

-- An image's status for the report: "Success", "Loading", "Failure (gave up after 4 tries)", ...
function Vfx.status(id: number): string
	local entry = loads[id]
	if not entry then
		return "unreported"
	end
	local text = entry.status .. " (" .. entry.attempts .. " tries)"
	return if entry.failed then "GAVE UP: " .. text else text
end

-- Whether the staggered first pass has started every image.
function Vfx.preloaded(): boolean
	return preloaded
end

-- Whether an image may be drawn: anything but one given up on after every retry failed
-- (VfxConfig.loading.requireLoaded: only once loaded).
function Vfx.usable(id: number): boolean
	local entry = loads[id]
	if LOADING.requireLoaded then
		return entry ~= nil and entry.status == "Success"
	end
	return not (entry and entry.failed)
end

-- Images given up on are asked about again at draw time (every VfxConfig.loading.recheck seconds):
-- one that has loaded since is drawn again.
local function recheckFailed()
	local now = os.clock()
	if now - recheckedAt < LOADING.recheck then
		return
	end
	recheckedAt = now
	for id, entry in loads do
		if entry.failed or (LOADING.requireLoaded and entry.status ~= "Success") then
			entry.checkedAt = now
			local status = fetchStatus(id)
			if status then
				record(id, status)
			end
		end
	end
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
	if hit == false and started then
		recheckFailed() -- a neon choice may have been an image that has loaded since
		hit = cache[key]
	end
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
