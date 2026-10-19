-- Effect textures on the client: preloads every picked image through instances that use it (a
-- hidden holder of ImageLabels, kept for the session so the images stay cached; Vfx.start), keeps the
-- unit whose effects are being drawn (Vfx.within: its id, element and color pick its variants), and
-- answers which texture a usage draws with (Vfx.texture; VfxResolve with VfxConfig).
-- An image is always drawn while it loads. Only one whose holder label still has not loaded
-- `VfxConfig.loading.failAfter` seconds after start falls back to neon (one warning), and it is
-- retried and re-checked for the rest of the session, so a late load still shows.
-- VfxConfig.loading.requireLoaded = true draws an image only once its label has loaded.
-- Counts how many requests drew textured or fell back, for the debug report (VfxDebug).
-- After the preload, every image is warmed up as a particle (warmUp): batch 2 kit layers draw an
-- image only once it is warm (Vfx.particleReady).
-- Presentation only.

local ContentProvider = game:GetService("ContentProvider")
local LogService = game:GetService("LogService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local VfxConfig = require(Shared:WaitForChild("VfxConfig"))
local VfxPicks = require(Shared:WaitForChild("VfxPicks"))
local VfxResolve = require(Shared:WaitForChild("VfxResolve"))

local Vfx = {}

export type Texture = VfxResolve.Texture
export type Context = VfxResolve.Context

-- Per image id: its holder label (whose IsLoaded is the truth), the last status the preload callback
-- reported (for the report only: it never marks an image failed), whether it is drawn neon for now
-- (not loaded by `failAfter`; re-checked), and how many times its label was asked to fetch it.
type Load = { label: ImageLabel?, reported: string, failed: boolean, attempts: number }
local loads: { [number]: Load } = {}
local started = false
local preloaded = false -- the preload call has returned
local current: Context? = nil
local cache: { [string]: Texture | false } = {}
local recheckedAt = 0
local holder: ScreenGui? = nil

-- Draw counts since Vfx.resetCounts: per usage, textured and fallback requests.
local counts: { [string]: { textured: number, fallback: number } } = {}

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
		entry = { label = nil, reported = "unreported", failed = false, attempts = 0 }
		loads[id] = entry
	end
	return entry
end

local function isLoaded(id: number): boolean
	local entry = loads[id]
	local label = entry and entry.label
	return label ~= nil and label.IsLoaded
end

-- The hidden holder: one 2 px, almost fully transparent ImageLabel per image, on screen (so the
-- engine fetches it) in a ScreenGui that survives respawns.
local function holderLabel(id: number): ImageLabel
	local entry = loadOf(id)
	if entry.label then
		return entry.label
	end
	if not holder then
		local gui = Instance.new("ScreenGui")
		gui.Name = "VfxPreload"
		gui.ResetOnSpawn = false
		gui.IgnoreGuiInset = true
		gui.DisplayOrder = -1000
		gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
		holder = gui
	end
	local label = Instance.new("ImageLabel")
	label.Name = tostring(id)
	label.BackgroundTransparency = 1
	label.ImageTransparency = 0.99
	label.Size = UDim2.fromOffset(2, 2)
	label.Position = UDim2.fromOffset(0, 0)
	label.Image = contentOf(id)
	label.Parent = holder
	entry.label = label
	entry.attempts += 1
	return label
end

-- Marks an image usable again once its label has loaded (a change makes every choice be made again).
local function refresh(id: number)
	local entry = loads[id]
	if entry and entry.failed and isLoaded(id) then
		entry.failed = false
		table.clear(cache)
		print(string.format("[Vfx] texture %s (id %d) loaded after all: drawn from now on", keysOf(id), id))
	end
end

-- Asks a not-yet-loaded label to fetch its image again (cleared and set back).
local function refetch(id: number)
	local entry = loads[id]
	local label = entry and entry.label
	if label and not label.IsLoaded then
		entry.attempts += 1
		label.Image = ""
		label.Image = contentOf(id)
	end
end

-- One warning in Output: each pick's key, name, image id and load result (its holder label's
-- IsLoaded), so a texture that draws neon shows up. `when` says which summary it is.
local function summarize(when: string)
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
			if isLoaded(pick.image) then
				loaded += 1
				result = "loaded"
			elseif entry and entry.failed then
				result = "FAILED: not loaded after "
					.. LOADING.failAfter
					.. " s (drawn neon, still retrying; preload said "
					.. entry.reported
					.. ")"
			else
				result = "still loading (drawn while loading; preload said "
					.. (if entry then entry.reported else "nothing")
					.. ")"
			end
			table.insert(
				lines,
				string.format("  %-13s %-20s image %d  %s", key, tostring(pick.name), pick.image, result)
			)
		end
	end
	warn(
		string.format(
			"[Vfx] texture load summary, %s (VfxPicks generated %s): %d of %d loaded\n%s",
			when,
			tostring(VfxPicks.generated),
			loaded,
			total,
			table.concat(lines, "\n")
		)
	)
end

-- Particle warm-up ----------------------------------------------------------------------------------
-- A texture's first use as a particle in a session can fail ("ContentId ... failed due to: Asset
-- content representation is being generated") even after its ImageLabel has loaded: the label does
-- not make Roblox prepare the particle form. So, after the preload, one hidden ParticleEmitter per
-- image emits one particle (0.01 studs, nearly transparent, inside the camera's near clip: never seen)
-- and the emitter is preloaded too. An image is warm when that reports no failure and no content
-- failure for it is logged within WARM_SETTLE seconds. One that failed is tried again WARM_RETRIES
-- seconds after the warm-up began; the emitters go after WARM_KEEP seconds and one summary line is
-- printed. Past that, an image still not warm is tried again (one emitter, briefly) when an effect
-- asks for it, at most every WARM_LATE seconds.
local WARM_RETRIES = { 2, 5, 10 }
local WARM_KEEP = 15
local WARM_SETTLE = 1
local WARM_LATE = 10
-- Per image id: "pending" (warming), "ready" or "failed"; nil before the warm-up reaches it.
local warmState: { [number]: string } = {}
local warmFailedAt: { [number]: number } = {} -- os.clock() of the last content failure logged
local warmTriedAt: { [number]: number } = {}
local warmHolder: BasePart? = nil
local warmEnded = false -- WARM_KEEP has passed: the summary is out, the emitters are gone

-- The hidden part the warm-up emitters sit on, placed just in front of the camera (inside its near
-- clip). Under the camera, not the effect folders: ReelCheck never counts it.
local function warmPart(): BasePart
	if warmHolder and warmHolder.Parent then
		return warmHolder
	end
	local part = Instance.new("Part")
	part.Name = "VfxWarmUp"
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Transparency = 1
	part.Size = Vector3.one * 0.05
	part.Parent = workspace.CurrentCamera or workspace
	warmHolder = part
	return part
end

local function placeWarmPart()
	local camera = workspace.CurrentCamera
	if camera and warmHolder then
		warmHolder.CFrame = camera.CFrame * CFrame.new(0, 0, -0.02)
	end
end

-- One warm-up attempt for image `id` on `emitter` (made when nil); sets warmState[id]. Yields.
local function warmAttempt(id: number, emitter: ParticleEmitter?): ParticleEmitter
	local host = warmPart()
	local made = emitter
	if not made then
		local created = Instance.new("ParticleEmitter")
		created.Rate = 0
		created.Enabled = false
		created.LockedToPart = true
		created.Size = NumberSequence.new(0.01)
		-- Nearly, not fully, transparent: a fully transparent particle may never be drawn at all.
		created.Transparency = NumberSequence.new(0.98)
		created.Lifetime = NumberRange.new(0.5)
		created.Speed = NumberRange.new(0)
		created.LightEmission = 0
		created.LightInfluence = 0
		created.Parent = host
		made = created
	end
	local particle = made :: ParticleEmitter
	warmState[id] = "pending"
	warmTriedAt[id] = os.clock()
	local began = os.clock()
	particle.Texture = ""
	particle.Texture = contentOf(id)
	placeWarmPart()
	particle:Emit(1)
	local status = "unreported"
	local ok = pcall(function()
		ContentProvider:PreloadAsync({ particle }, function(_, fetch: Enum.AssetFetchStatus)
			status = fetch.Name
		end)
	end)
	task.wait(WARM_SETTLE)
	local logged = (warmFailedAt[id] or 0) >= began
	local fetched = status == "Success" or status == "unreported" -- unreported: already cached
	warmState[id] = if ok and fetched and not logged then "ready" else "failed"
	return particle
end

-- Content failures logged for images being warmed (Roblox logs one once per asset per session).
local function watchFailures(): RBXScriptConnection
	return LogService.MessageOut:Connect(function(message)
		if not string.find(message, "failed", 1, true) then
			return
		end
		local id = tonumber(string.match(message, "rbxassetid://(%d+)"))
		if id and warmState[id] then
			warmFailedAt[id] = os.clock()
		end
	end)
end

local function warmUp(ids: { number })
	local began = os.clock()
	local log = watchFailures()
	local follow = RunService.RenderStepped:Connect(placeWarmPart)
	local emitters: { [number]: ParticleEmitter } = {}
	local function attempt(id: number)
		emitters[id] = warmAttempt(id, emitters[id])
	end
	for _, id in ids do
		warmState[id] = "pending"
		task.spawn(attempt, id)
	end
	for _, at in WARM_RETRIES do
		task.wait(math.max(0, began + at - os.clock()))
		for _, id in ids do
			if warmState[id] == "failed" then
				task.spawn(attempt, id)
			end
		end
	end
	task.wait(math.max(0, began + WARM_KEEP - os.clock()))
	follow:Disconnect()
	for _, emitter in emitters do
		emitter:Destroy()
	end
	local ready, missing = 0, {}
	for _, id in ids do
		if warmState[id] == "ready" then
			ready += 1
		else
			table.insert(missing, keysOf(id) .. " " .. string.format("%d", id))
		end
	end
	warmEnded = true
	print(
		string.format("[Vfx] particle warm-up: %d/%d ready", ready, #ids)
			.. (if #missing > 0 then " (not yet: " .. table.concat(missing, ", ") .. ")" else "")
	)
	if #missing == 0 then
		log:Disconnect()
	end
end

-- Whether image `id` may be drawn as a kit particle: its label has loaded and its particle warm-up
-- succeeded. Before Vfx.start (no warm-up at all) the label alone decides. One that is still not warm
-- after the warm-up is tried again in the background, at most every WARM_LATE seconds.
function Vfx.particleReady(id: number): boolean
	if not isLoaded(id) then
		return false
	end
	local state = warmState[id]
	if state == nil then
		return not started
	end
	if state == "failed" and warmEnded and os.clock() - (warmTriedAt[id] or 0) >= WARM_LATE then
		warmTriedAt[id] = os.clock()
		task.spawn(function()
			local emitter = warmAttempt(id, nil)
			emitter:Destroy()
		end)
	end
	return state == "ready"
end

-- Preloads every picked image: each gets a label in the hidden holder, and the labels are preloaded
-- in one PreloadAsync call (its callback only noted for the report). Prints the summary when that
-- returns, then warms every image up as a particle (warmUp). At `failAfter` seconds an image whose
-- label still has not loaded is drawn neon (one warning) and, from then on, re-fetched every
-- `retryEvery` seconds until it loads. A second summary prints at `LATE_SUMMARY` seconds if anything
-- had not loaded by then.
local LATE_SUMMARY = 60
function Vfx.start()
	if started then
		return
	end
	started = true
	task.spawn(function()
		local began = os.clock()
		local ids = VfxResolve.images()
		local labels = {}
		for _, id in ids do
			table.insert(labels, holderLabel(id))
		end
		local ok, err = pcall(function()
			game:GetService("ContentProvider")
				:PreloadAsync(labels, function(asset: string, status: Enum.AssetFetchStatus)
					local id = tonumber(string.match(asset, "(%d+)%s*$"))
					if id and loads[id] then
						loads[id].reported = status.Name
					end
				end)
		end)
		if not ok then
			warn("[Vfx] PreloadAsync failed (images still load through their labels): " .. tostring(err))
		end
		preloaded = true
		summarize(string.format("preload finished in %.1f s", os.clock() - began))
		task.spawn(warmUp, ids)

		task.wait(math.max(0, LOADING.failAfter - (os.clock() - began)))
		local missing = {}
		for _, id in ids do
			if not isLoaded(id) then
				loads[id].failed = true
				table.insert(missing, keysOf(id) .. " " .. string.format("%d", id))
			end
		end
		if #missing > 0 then
			table.clear(cache)
			warn(
				string.format(
					"[Vfx] %d textures not loaded after %d s, drawn neon until they load (retrying): %s",
					#missing,
					LOADING.failAfter,
					table.concat(missing, ", ")
				)
			)
		end

		-- For the rest of the session: re-fetch what has not loaded, and draw it again once it has.
		local lateDone = false
		while true do
			local anyMissing = false
			for _, id in ids do
				if isLoaded(id) then
					refresh(id)
				else
					anyMissing = true
					refetch(id)
				end
			end
			if not lateDone and os.clock() - began >= LATE_SUMMARY then
				lateDone = true
				if anyMissing then
					summarize(string.format("at %d s", LATE_SUMMARY))
				end
			end
			if not anyMissing and lateDone then
				break
			end
			task.wait(LOADING.retryEvery)
		end
	end)
end

-- An image's status for the report: "loaded", "loading: not loaded (...)", "NEON: not loaded (...)".
function Vfx.status(id: number): string
	local entry = loads[id]
	if not entry then
		return "unreported"
	end
	if isLoaded(id) then
		return "loaded"
	end
	local text = string.format("not loaded (%d fetches, preload said %s)", entry.attempts, entry.reported)
	return if entry.failed then "NEON: " .. text else "loading: " .. text
end

-- Whether the preload call has returned.
-- Whether image `id` has really loaded (its holder label's IsLoaded): batch 2 kit layers draw only
-- then, so an image that failed (or has not loaded yet) never draws as a blank square.
function Vfx.isLoaded(id: number): boolean
	return isLoaded(id)
end

function Vfx.preloaded(): boolean
	return preloaded
end

-- Whether an image may be drawn: anything not marked neon after `failAfter` (requireLoaded: only
-- once its holder label has loaded).
function Vfx.usable(id: number): boolean
	if LOADING.requireLoaded then
		return isLoaded(id)
	end
	local entry = loads[id]
	return not (entry and entry.failed)
end

-- Images drawn neon are looked at again at draw time (every VfxConfig.loading.recheck seconds): one
-- whose label has loaded since is drawn again.
local function recheckFailed()
	local now = os.clock()
	if now - recheckedAt < LOADING.recheck then
		return
	end
	recheckedAt = now
	for id, entry in loads do
		if entry.failed then
			refresh(id)
		elseif LOADING.requireLoaded and isLoaded(id) then
			table.clear(cache)
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

-- Kit textures on or off for every effect (the dev lineup's V key, for A/B checks). Off: every
-- effect draws its neon fallback, as if no texture were picked.
local enabled = true
function Vfx.setEnabled(on: boolean)
	enabled = on
end
function Vfx.enabled(): boolean
	return enabled
end

-- The texture `usage` (VfxConfig.uses) draws with now, for an effect of `color`, or nil (neon).
-- `mode` only accepts textures that draw that way ("plane", "billboard", "beam", "particle").
function Vfx.texture(usage: string, color: Color3?, mode: string?): Texture?
	if not enabled then
		count(usage, false)
		return nil
	end
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
