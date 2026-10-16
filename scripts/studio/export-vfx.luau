--!nocheck
-- Exports the VFX model-pack picks as plain data for scripts/vfx-apply.luau, in Roblox Studio EDIT
-- mode, without running anything. Paste it into the command bar while the receiver runs
-- (lune run scripts/models-receive 600 vfx). Not run through the Studio MCP.
--
-- For each job it:
--   1. reads the pack with game:GetObjects (unparented: nothing in it can run) and deletes every
--      Script, LocalScript and ModuleScript at once, unrun, plus sounds and click/prompt objects;
--   2. records only what effects can reuse: each ParticleEmitter's texture and settings (flipbook
--      layout, mode and framerate, light emission and influence, size, transparency, lifetime,
--      speed, rotation, drag, orientation), each Beam's and Trail's texture and settings, each
--      Decal's and Texture's image, and each mesh's mesh and texture ids;
--   3. POSTs the dump as JSON to the receiver as <role>_<rank> (HttpEnabled is switched on only for
--      the post and restored at once).
-- Nothing from the pack is kept in the place: the holder is destroyed after each job. Then run
-- lune run scripts/vfx-apply, which reads the dumps into src/shared/VfxPicks.luau.

-- The model-pack picks (docs/references/catalog/vfx-picks.json); `key` is <role>_<rank>.
local JOBS = {
	{ key = "sparks_1", id = 106411022141734 },
	{ key = "rings_3", id = 121643024535039 },
	{ key = "flashes_3", id = 12136850996 },
	{ key = "energy_3", id = 90905357462206 },
	{ key = "fire_1", id = 107157303748652 },
	{ key = "fire_2", id = 16764566328 },
	{ key = "explosions_1", id = 108812638060941 },
	{ key = "auras_1", id = 13295712552 },
	{ key = "auras_2", id = 17800318686 },
}
local RECEIVER = "http://127.0.0.1:34999/"
local MAX_EACH = 64 -- items recorded per class (big packs hold thousands)

local HttpService = game:GetService("HttpService")
assert(not game:GetService("RunService"):IsRunning(), "export-vfx: stop the game first; edit mode only")

local STRIP = { "LuaSourceContainer", "Sound", "ClickDetector", "ProximityPrompt" }

local function round(n: number): number
	return math.floor(n * 1000 + 0.5) / 1000
end
local function range(r: NumberRange)
	return { round(r.Min), round(r.Max) }
end
local function numbers(sequence: NumberSequence)
	local out = {}
	for _, key in sequence.Keypoints do
		table.insert(out, { round(key.Time), round(key.Value) })
	end
	return out
end
local function colors(sequence: ColorSequence)
	local out = {}
	for _, key in sequence.Keypoints do
		table.insert(out, {
			round(key.Time),
			math.floor(key.Value.R * 255 + 0.5),
			math.floor(key.Value.G * 255 + 0.5),
			math.floor(key.Value.B * 255 + 0.5),
		})
	end
	return out
end

local function export(job)
	local objects = game:GetObjects("rbxassetid://" .. job.id)
	local holder = Instance.new("Model")
	for _, object in objects do
		object.Parent = holder -- the holder is not in the game: nothing runs
	end
	local stripped = 0
	for _, descendant in holder:GetDescendants() do
		for _, class in STRIP do
			if descendant.Parent and descendant:IsA(class) then
				stripped += 1
				descendant:Destroy()
				break
			end
		end
	end
	local dump = {
		key = job.key,
		id = job.id,
		stripped = stripped,
		emitters = {},
		beams = {},
		trails = {},
		images = {},
		meshes = {},
	}
	for _, d in holder:GetDescendants() do
		if d:IsA("ParticleEmitter") and #dump.emitters < MAX_EACH then
			table.insert(dump.emitters, {
				name = d.Name,
				texture = d.Texture,
				flipbookLayout = d.FlipbookLayout.Name,
				flipbookMode = d.FlipbookMode.Name,
				flipbookFramerate = round(d.FlipbookFramerate.Max),
				lightEmission = round(d.LightEmission),
				lightInfluence = round(d.LightInfluence),
				size = numbers(d.Size),
				transparency = numbers(d.Transparency),
				color = colors(d.Color),
				lifetime = range(d.Lifetime),
				speed = range(d.Speed),
				rotation = range(d.Rotation),
				rotSpeed = range(d.RotSpeed),
				drag = round(d.Drag),
				orientation = d.Orientation.Name,
				rate = round(d.Rate),
			})
		elseif d:IsA("Beam") and #dump.beams < MAX_EACH then
			table.insert(dump.beams, {
				name = d.Name,
				texture = d.Texture,
				textureMode = d.TextureMode.Name,
				textureLength = round(d.TextureLength),
				textureSpeed = round(d.TextureSpeed),
				lightEmission = round(d.LightEmission),
				width = { round(d.Width0), round(d.Width1) },
				transparency = numbers(d.Transparency),
				color = colors(d.Color),
			})
		elseif d:IsA("Trail") and #dump.trails < MAX_EACH then
			table.insert(dump.trails, {
				name = d.Name,
				texture = d.Texture,
				textureMode = d.TextureMode.Name,
				lifetime = round(d.Lifetime),
				lightEmission = round(d.LightEmission),
				transparency = numbers(d.Transparency),
			})
		elseif (d:IsA("Decal") or d:IsA("Texture")) and #dump.images < MAX_EACH then
			table.insert(dump.images, { name = d.Name, texture = d.Texture })
		elseif d:IsA("MeshPart") and #dump.meshes < MAX_EACH then
			table.insert(dump.meshes, { name = d.Name, mesh = d.MeshId, texture = d.TextureID })
		elseif d:IsA("SpecialMesh") and #dump.meshes < MAX_EACH then
			table.insert(dump.meshes, { name = d.Name, mesh = d.MeshId, texture = d.TextureId })
		end
	end
	holder:Destroy()
	return dump
end

local lines = {}
for _, job in JOBS do
	local ok, dump = pcall(export, job)
	if not ok then
		table.insert(lines, job.key .. ": FAILED " .. tostring(dump))
		continue
	end
	local body = HttpService:JSONEncode(dump)
	local before = HttpService.HttpEnabled
	pcall(function()
		HttpService.HttpEnabled = true
	end)
	local posted, problem = pcall(function()
		return HttpService:PostAsync(RECEIVER .. job.key, body)
	end)
	pcall(function()
		HttpService.HttpEnabled = before
	end)
	table.insert(
		lines,
		string.format(
			"%s: %d emitters, %d beams, %d trails, %d images, %d meshes, %d scripts/sounds deleted unrun%s",
			job.key,
			#dump.emitters,
			#dump.beams,
			#dump.trails,
			#dump.images,
			#dump.meshes,
			dump.stripped,
			if posted then "" else " - POST FAILED: " .. tostring(problem)
		)
	)
end
print("export-vfx:\n" .. table.concat(lines, "\n"))
