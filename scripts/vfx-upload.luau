-- Uploads the VFX kit textures (batch 1: assets/vfx/textures/vfx_*.png, not the contact sheet;
-- batch 2: assets/vfx/src_b2/fx_*.png) to Roblox
-- through Open Cloud (Assets API) as Decals, waits for each upload to finish, resolves the Image id
-- the Decal wraps (the id ParticleEmitter.Texture, Beam.Texture and ImageLabel.Image take), and
-- writes assets/vfx/ids.json (texture name -> image id). Run from the repository root:
--   $env:ROBLOX_API_KEY = "<key>"   (PowerShell; never commit or paste it anywhere else)
--   lune run scripts/vfx-upload <userId>
--
-- The key must belong to (or be usable by) that user and have the Assets API (asset:read,
-- asset:write) and Legacy Asset Delivery read access (to resolve the image id). It is read from the
-- ROBLOX_API_KEY environment variable and never printed or written.
--
-- Re-runs only do what is missing: names already in ids.json are skipped, and a Decal that was
-- uploaded but whose image id could not be resolved yet (assets/vfx/decals.json keeps every uploaded
-- Decal id) is only resolved again, not uploaded twice.
-- Then run lune run scripts/vfx-apply to put the ids into the game (src/shared/VfxPicks.luau).
--
-- Batch 2 meshes (assets/vfx/meshes/mesh_*.fbx) are uploaded as Models into assets/vfx/meshes.json
-- (name -> model id), loaded at runtime on the server with InsertService:LoadAsset. If Open Cloud
-- refuses FBX for this key, the textures still go up and the mesh is reported as failed: import it
-- by hand in Studio instead (the steps are in the batch 2 handoff).

local fs = require("@lune/fs")
local net = require("@lune/net")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")
local task = require("@lune/task")

-- Texture folders and the file names each holds (batch 1, batch 2).
local SOURCES = {
	{ dir = "assets/vfx/textures", pattern = "^(vfx_[%w_]+)%.png$" },
	{ dir = "assets/vfx/src_b2", pattern = "^(fx_[%w_]+)%.png$" },
}
local MESHES = "assets/vfx/meshes"
local MESH_IDS = "assets/vfx/meshes.json"
local IDS = "assets/vfx/ids.json"
local DECALS = "assets/vfx/decals.json"
local ASSETS_URL = "https://apis.roblox.com/assets/v1/assets"
local OPERATIONS_URL = "https://apis.roblox.com/assets/v1/operations/"
local DELIVERY_URL = "https://apis.roblox.com/asset-delivery-api/v1/assetId/"
local POLL_TRIES = 30 -- seconds of waiting per upload, roughly (1 s, growing to 3 s apart)
local RESOLVE_TRIES = 6 -- a fresh Decal can take a moment to be deliverable

local apiKey = process.env.ROBLOX_API_KEY
local userId = process.args[1] or process.env.ROBLOX_USER_ID
if not apiKey or apiKey == "" then
	print('ROBLOX_API_KEY is not set. In PowerShell: $env:ROBLOX_API_KEY = "<key>" then run again.')
	process.exit(1)
end
if not userId or not string.match(userId, "^%d+$") then
	print("Usage: lune run scripts/vfx-upload <userId>   (your numeric Roblox user id)")
	process.exit(1)
end
if not fs.isDir(SOURCES[1].dir) then
	print("Missing " .. SOURCES[1].dir .. ". Run from the repository root.")
	process.exit(1)
end

local function readMap(path: string): { [string]: number }
	if not fs.isFile(path) then
		return {}
	end
	local ok, value = pcall(serde.decode, "json", fs.readFile(path))
	if not ok or type(value) ~= "table" then
		print("Unreadable " .. path .. ": fix or delete it.")
		process.exit(1)
	end
	local out = {}
	for name, id in value do
		out[name] = tonumber(id) :: number
	end
	return out
end

-- Written by hand so the keys stay sorted (stable diffs).
local function writeMap(path: string, map: { [string]: number })
	local names = {}
	for name in map do
		table.insert(names, name)
	end
	table.sort(names)
	local lines = {}
	for i, name in names do
		table.insert(lines, string.format('\t"%s": %d%s', name, map[name], if i < #names then "," else ""))
	end
	fs.writeFile(path, "{\n" .. table.concat(lines, "\n") .. (if #names > 0 then "\n" else "") .. "}\n")
end

-- A request with the key, retried on rate limits (429) and server errors.
local function call(options: { url: string, method: string?, headers: { [string]: string }?, body: string? }): any
	local headers = table.clone(options.headers or {})
	headers["x-api-key"] = apiKey
	for attempt = 1, 5 do
		local ok, response = pcall(net.request, {
			url = options.url,
			method = options.method or "GET",
			headers = headers,
			body = options.body,
		})
		if ok and response.statusCode ~= 429 and response.statusCode < 500 then
			return response
		end
		local wait = 2 * attempt
		if ok then
			local reset = tonumber(response.headers["x-ratelimit-reset"] or "")
			wait = if reset then math.clamp(reset, 1, 60) else wait
			print(string.format("    (HTTP %d, retrying in %d s)", response.statusCode, wait))
		else
			print(string.format("    (request failed: %s, retrying in %d s)", tostring(response), wait))
		end
		task.wait(wait)
	end
	return nil
end

local function decode(body: string): any
	local ok, value = pcall(serde.decode, "json", body)
	return if ok then value else nil
end

local function describe(response: any): string
	if not response then
		return "no answer after retries"
	end
	return string.format("HTTP %d: %s", response.statusCode, string.sub(response.body or "", 1, 300))
end

-- Uploads one file as an asset (a PNG as a Decal, or an FBX as a Model); returns the asset id, or
-- nil and why.
local function upload(name: string, bytes: string, kind: string?): (number?, string?)
	local model = kind == "Model"
	local boundary = "----vfxkit" .. string.format("%08x", math.random(0, 0x7fffffff))
	local request = serde.encode("json", {
		assetType = if model then "Model" else "Decal",
		displayName = name,
		description = "robloxgame VFX kit " .. (if model then "mesh (" .. name .. ".fbx)" else "texture (" .. name .. ".png)"),
		creationContext = { creator = { userId = userId } },
	})
	local body = table.concat({
		"--" .. boundary,
		'Content-Disposition: form-data; name="request"',
		"Content-Type: application/json",
		"",
		request,
		"--" .. boundary,
		string.format(
			'Content-Disposition: form-data; name="fileContent"; filename="%s.%s"',
			name,
			if model then "fbx" else "png"
		),
		if model then "Content-Type: model/fbx" else "Content-Type: image/png",
		"",
		bytes,
		"--" .. boundary .. "--",
		"",
	}, "\r\n")
	local response = call({
		url = ASSETS_URL,
		method = "POST",
		headers = { ["content-type"] = "multipart/form-data; boundary=" .. boundary },
		body = body,
	})
	if not response or not response.ok then
		return nil, "upload: " .. describe(response)
	end
	local operation = decode(response.body)
	local operationId = operation
		and (operation.operationId or (operation.path and string.match(operation.path, "operations/(.+)$")))
	if not operationId then
		return nil, "upload: no operation in the answer: " .. string.sub(response.body, 1, 300)
	end
	-- Poll the operation until it is done.
	for try = 1, POLL_TRIES do
		if operation.done then
			break
		end
		task.wait(math.min(1 + try * 0.25, 3))
		local poll = call({ url = OPERATIONS_URL .. operationId })
		if not poll or not poll.ok then
			return nil, "operation " .. operationId .. ": " .. describe(poll)
		end
		operation = decode(poll.body) or {}
	end
	if not operation.done then
		return nil, "operation " .. operationId .. " still not done; run again later to retry"
	end
	if operation.error then
		return nil, "rejected: " .. serde.encode("json", operation.error)
	end
	local assetId = operation.response and tonumber(operation.response.assetId)
	if not assetId then
		return nil, "operation done without an asset id: " .. serde.encode("json", operation)
	end
	local moderation = operation.response.moderationResult
	if moderation and moderation.moderationState and moderation.moderationState ~= "Approved" then
		print("    moderation: " .. tostring(moderation.moderationState) .. " (it may stay blank until approved)")
	end
	return assetId, nil
end

-- The Image id inside a Decal: its delivered file is a model holding one Decal whose Texture names it.
local function resolveImage(decalId: number): (number?, string?)
	local why = "not tried"
	for try = 1, RESOLVE_TRIES do
		if try > 1 then
			task.wait(2 * (try - 1))
		end
		local response = call({ url = DELIVERY_URL .. string.format("%d", decalId) })
		if not response or not response.ok then
			why = "asset delivery: " .. describe(response)
			continue
		end
		local info = decode(response.body)
		local location = info and info.location
		if not location then
			why = "asset delivery: no location: " .. string.sub(response.body, 1, 300)
			continue
		end
		local okFile, file = pcall(net.request, { url = location, method = "GET" })
		if not okFile or not file.ok then
			why = "decal file: " .. (if okFile then describe(file) else tostring(file))
			continue
		end
		local content = file.body
		local text: string? = nil
		local okModel, instances = pcall(roblox.deserializeModel, content)
		if okModel then
			for _, instance in instances do
				for _, item in { instance, table.unpack(instance:GetDescendants()) } do
					if item:IsA("Decal") then
						local okTexture, texture = pcall(function()
							return (item :: any).Texture
						end)
						if okTexture and type(texture) == "string" then
							text = texture
						end
					end
				end
			end
		end
		text = text or content -- an XML model names it in plain text too
		local id = tonumber(string.match(text, "rbxassetid://(%d+)") or string.match(text, "[?&]id=(%d+)"))
		if id and id ~= decalId then
			return id, nil
		end
		why = "no image id in the decal file"
	end
	return nil, why
end

local ids = readMap(IDS)
local decals = readMap(DECALS)
local names = {}
local dirOf: { [string]: string } = {}
for _, source in SOURCES do
	if fs.isDir(source.dir) then
		for _, file in fs.readDir(source.dir) do
			local name = string.match(file, source.pattern)
			if name then
				table.insert(names, name)
				dirOf[name] = source.dir
			end
		end
	end
end
table.sort(names)

local done, skipped, failed = 0, 0, {}
for _, name in names do
	if ids[name] then
		skipped += 1
		continue
	end
	print(name)
	local decalId = decals[name]
	if decalId then
		print(string.format("  already uploaded as decal %d: resolving its image", decalId))
	else
		local id, err = upload(name, fs.readFile(dirOf[name] .. "/" .. name .. ".png"))
		if not id then
			print("  FAILED " .. tostring(err))
			table.insert(failed, name)
			continue
		end
		decalId = id
		decals[name] = id
		writeMap(DECALS, decals) -- saved at once, so a crash never uploads it twice
		print(string.format("  uploaded: decal %d", id))
	end
	local imageId, err = resolveImage(decalId :: number)
	if not imageId then
		print("  FAILED to resolve the image id: " .. tostring(err) .. " (run again to retry)")
		table.insert(failed, name)
		continue
	end
	ids[name] = imageId
	writeMap(IDS, ids)
	print(string.format("  image %d", imageId))
	done += 1
end

if not fs.isFile(IDS) then
	writeMap(IDS, ids)
end
print(
	string.format(
		"\n%d uploaded/resolved, %d already in %s, %d failed%s",
		done,
		skipped,
		IDS,
		#failed,
		if #failed > 0 then ": " .. table.concat(failed, ", ") else ""
	)
)

-- Meshes (batch 2): each FBX as a Model. A refusal is reported, not fatal: the manual Studio import
-- covers it.
local meshIds = readMap(MESH_IDS)
local meshFailed = {}
if fs.isDir(MESHES) then
	local meshNames = {}
	for _, file in fs.readDir(MESHES) do
		local name = string.match(file, "^(mesh_[%w_]+)%.fbx$")
		if name then
			table.insert(meshNames, name)
		end
	end
	table.sort(meshNames)
	for _, name in meshNames do
		if meshIds[name] then
			continue
		end
		print(name)
		local id, err = upload(name, fs.readFile(MESHES .. "/" .. name .. ".fbx"), "Model")
		if id then
			meshIds[name] = id
			writeMap(MESH_IDS, meshIds)
			print(string.format("  model %d", id))
		else
			print("  FAILED " .. tostring(err))
			table.insert(meshFailed, name)
		end
	end
	if #meshFailed > 0 then
		print(
			string.format(
				"%d meshes not uploaded (%s): import them by hand in Studio (see the batch 2 handoff)",
				#meshFailed,
				table.concat(meshFailed, ", ")
			)
		)
	end
end

if #failed > 0 then
	process.exit(1)
end
print("Next: lune run scripts/vfx-apply")
