--!nocheck
-- Vets picked Creator Store models in Roblox Studio, in EDIT mode, without running anything.
-- Run it in the Studio command bar or through the Studio MCP (Edit data model), after filling
-- PICKS from docs/references/catalog/models-picks.json (key = asset ids, best first). It refuses
-- to run in a running game.
--
-- For each picked model it:
--   1. loads it with InsertService:LoadAsset; the result is not parented anywhere, so nothing in it
--      can run;
--   2. reports every Script, LocalScript and ModuleScript (class, path, length and red-flag
--      patterns such as a require by asset id, getfenv or loadstring) and DELETES them, still
--      unparented: no script is ever run, required or enabled;
--   3. puts the script-free model in a sandbox folder in ServerStorage and reports its parts,
--      MeshParts, unions, special meshes, textures, size and rig type (R6 parts, R15, a custom
--      Motor6D rig, loose parts, or one solid mesh), with a suggested mapping of its parts to the
--      figure anchors (head, hips, arms, legs; for a horse: body, head, four legs);
--   4. deletes the sandbox.
-- Triangle counts are not readable here: use the search data (models-data.js, "k tris").

local PICKS = {
	-- iron_rush = { 1234567890, 2345678901 },
	-- spurshot_horse = { 3456789012 },
}
-- Entries whose key ends in _horse are vetted as horses (body, head, four legs).

local InsertService = game:GetService("InsertService")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

assert(not RunService:IsRunning(), "vet-models: stop the game first; it only runs in edit mode")

-- Patterns that deserve a look in a free model's scripts.
local RED_FLAGS = {
	{ "require by asset id", "require%s*%(%s*%d" },
	{ "getfenv / setfenv", "[gs]etfenv" },
	{ "loadstring", "loadstring" },
	{ "HttpService", "HttpService" },
	{ "TeleportService", "TeleportService" },
	{ "MarketplaceService", "MarketplaceService" },
	{ "InsertService", "InsertService" },
	{ "string.reverse / char obfuscation", "string%.reverse" },
	{ "long encoded string", "\\%d%d%d\\%d%d%d\\%d%d%d" },
}

local R6 = { "Head", "Torso", "Left Arm", "Right Arm", "Left Leg", "Right Leg" }
local R15 = { "Head", "UpperTorso", "LowerTorso", "LeftUpperArm", "RightUpperArm", "LeftUpperLeg", "RightUpperLeg" }

-- Name patterns (lowercase) per anchor, for the suggested mapping.
local BODY_ANCHORS = {
	{ "head", { "head" } },
	{ "hips", { "torso", "chest", "body", "hip", "pelvis", "waist" } },
	{ "leftArm", { "left ?upper ?arm", "left ?arm", "l ?arm", "arm ?l$", "leftshoulder" } },
	{ "rightArm", { "right ?upper ?arm", "right ?arm", "r ?arm", "arm ?r$", "rightshoulder" } },
	{ "leftLeg", { "left ?upper ?leg", "left ?leg", "l ?leg", "leg ?l$", "left ?thigh" } },
	{ "rightLeg", { "right ?upper ?leg", "right ?leg", "r ?leg", "leg ?r$", "right ?thigh" } },
}
local HORSE_ANCHORS = {
	{ "horse (body)", { "body", "torso", "chest", "barrel" } },
	{ "head / neck", { "head", "neck" } },
	{ "front left leg", { "front ?left", "left ?front", "fl", "leg ?1" } },
	{ "front right leg", { "front ?right", "right ?front", "fr", "leg ?2" } },
	{ "back left leg", { "back ?left", "left ?back", "rear ?left", "left ?rear", "bl", "hind ?left", "leg ?3" } },
	{ "back right leg", { "back ?right", "right ?back", "rear ?right", "right ?rear", "br", "hind ?right", "leg ?4" } },
}

local function lines(text: string): number
	local _, count = string.gsub(text, "\n", "")
	return count + 1
end

-- Lists and deletes every script in `root` (which is not parented anywhere).
local function stripScripts(root: Instance, out: { string })
	local found = {}
	for _, descendant in root:GetDescendants() do
		if descendant:IsA("LuaSourceContainer") then
			table.insert(found, descendant)
		end
	end
	if #found == 0 then
		table.insert(out, "  scripts: none")
		return
	end
	table.insert(out, string.format("  scripts: %d found, all deleted (never run):", #found))
	for _, script in found do
		local ok, source = pcall(function()
			return (script :: any).Source
		end)
		local flags = {}
		if ok and type(source) == "string" then
			for _, flag in RED_FLAGS do
				if string.find(source, flag[2]) then
					table.insert(flags, flag[1])
				end
			end
		end
		table.insert(
			out,
			string.format(
				"    - %s %s (%s lines)%s",
				script.ClassName,
				script:GetFullName(),
				if ok and type(source) == "string" then tostring(lines(source)) else "?",
				if #flags > 0 then "  RED FLAGS: " .. table.concat(flags, ", ") else ""
			)
		)
	end
	for _, script in found do
		script:Destroy()
	end
end

local function hasAll(names: { [string]: boolean }, wanted: { string }): number
	local count = 0
	for _, name in wanted do
		if names[name] then
			count += 1
		end
	end
	return count
end

local function suggestMapping(parts: { BasePart }, anchors: any, out: { string })
	table.insert(out, "  suggested anchor mapping (by part name; check by eye):")
	local used = {}
	for _, anchor in anchors do
		local matches = {}
		for _, part in parts do
			local name = string.lower(part.Name)
			for _, pattern in anchor[2] do
				if string.find(name, pattern) then
					table.insert(matches, part.Name)
					used[part] = true
					break
				end
			end
		end
		table.insert(
			out,
			string.format(
				"    %-16s %s",
				anchor[1],
				if #matches > 0 then table.concat(matches, ", ") else "(none found)"
			)
		)
	end
	local unmatched = 0
	for _, part in parts do
		if not used[part] then
			unmatched += 1
		end
	end
	table.insert(out, string.format("    unmatched parts: %d", unmatched))
end

local function vet(key: string, id: number, sandbox: Folder, out: { string })
	table.insert(out, string.format("%s / %d", key, id))
	local started = os.clock()
	-- LoadAsset needs the model in your inventory; game:GetObjects (Studio plugin level) reads any
	-- public free model. Both return it unparented.
	local ok, loaded = pcall(InsertService.LoadAsset, InsertService, id)
	local how = "LoadAsset"
	if not ok or not loaded then
		local fetched, objects = pcall(function()
			return game:GetObjects("rbxassetid://" .. id)
		end)
		if not fetched or not objects or #objects == 0 then
			table.insert(out, "  LOAD FAILED: " .. tostring(loaded) .. " / GetObjects: " .. tostring(objects))
			return
		end
		local holder = Instance.new("Model")
		holder.Name = tostring(id)
		for _, object in objects do
			object.Parent = holder -- still unparented: the holder is not in the game
		end
		loaded, how = holder, "GetObjects"
	end
	table.insert(out, string.format("  loaded with %s in %.2f s", how, os.clock() - started))

	-- Scripts go first, while nothing is parented.
	stripScripts(loaded, out)
	loaded.Parent = sandbox

	local parts, meshParts, unions, specialMeshes, humanoids, motors, welds = {}, 0, 0, 0, {}, {}, 0
	local textures, names = {}, {}
	for _, descendant in loaded:GetDescendants() do
		if descendant:IsA("BasePart") then
			table.insert(parts, descendant)
			names[descendant.Name] = true
			if descendant:IsA("MeshPart") then
				meshParts += 1
				if descendant.TextureID ~= "" then
					textures[descendant.TextureID] = true
				end
			elseif descendant:IsA("UnionOperation") then
				unions += 1
			end
		elseif descendant:IsA("SpecialMesh") then
			specialMeshes += 1
			if descendant.TextureId ~= "" then
				textures[descendant.TextureId] = true
			end
		elseif descendant:IsA("Decal") then -- includes Texture
			textures[descendant.Texture] = true
		elseif descendant:IsA("SurfaceAppearance") then
			textures["SurfaceAppearance " .. descendant.ColorMap] = true
		elseif descendant:IsA("Humanoid") then
			table.insert(humanoids, descendant)
		elseif descendant:IsA("Motor6D") then
			table.insert(motors, descendant)
		elseif descendant:IsA("Weld") or descendant:IsA("WeldConstraint") then
			welds += 1
		end
	end
	local textureCount = 0
	for _ in textures do
		textureCount += 1
	end
	local size = Vector3.zero
	pcall(function()
		size = (loaded :: any):GetExtentsSize()
	end)
	table.insert(
		out,
		string.format(
			"  parts %d (MeshParts %d, unions %d, special meshes %d), textures %d, Motor6Ds %d, welds %d, size %.1f x %.1f x %.1f studs",
			#parts,
			meshParts,
			unions,
			specialMeshes,
			textureCount,
			#motors,
			welds,
			size.X,
			size.Y,
			size.Z
		)
	)

	-- Rig type.
	local rig
	if hasAll(names, R15) >= 6 then
		rig = "R15 (split limbs, map the upper and lower parts to one anchor each)"
	elseif hasAll(names, R6) >= 5 then
		rig = "R6 parts (maps directly to the anchors)"
	elseif #motors >= 4 then
		rig = "custom Motor6D rig (map its jointed parts to the anchors)"
	elseif #parts <= 2 then
		rig = "one solid mesh (last resort: it can only bob and slide)"
	else
		rig = "loose parts without joints (group them by position to map them)"
	end
	for _, humanoid in humanoids do
		rig ..= string.format("; Humanoid RigType %s", humanoid.RigType.Name)
	end
	table.insert(out, "  rig: " .. rig)
	if #motors > 0 then
		local joints = {}
		for i = 1, math.min(#motors, 12) do
			local motor = motors[i]
			table.insert(
				joints,
				string.format(
					"%s->%s",
					motor.Part0 and motor.Part0.Name or "?",
					motor.Part1 and motor.Part1.Name or "?"
				)
			)
		end
		table.insert(
			out,
			"  joints: "
				.. table.concat(joints, ", ")
				.. (if #motors > 12 then string.format(" (+%d more)", #motors - 12) else "")
		)
	end
	suggestMapping(parts, if string.sub(key, -6) == "_horse" then HORSE_ANCHORS else BODY_ANCHORS, out)
end

local sandbox = Instance.new("Folder")
sandbox.Name = "ModelVetSandbox"
sandbox.Parent = ServerStorage -- nothing in ServerStorage runs, and every script is gone anyway
local out = {}
local ok, problem = pcall(function()
	local keys = {}
	for key in PICKS do
		table.insert(keys, key)
	end
	table.sort(keys)
	for _, key in keys do
		for rank, id in PICKS[key] do
			table.insert(out, "")
			table.insert(out, string.format("#%d", rank))
			vet(key, id, sandbox, out)
		end
	end
end)
sandbox:Destroy()
if not ok then
	table.insert(out, "VET STOPPED: " .. tostring(problem))
end
if #out == 0 then
	table.insert(out, "PICKS is empty: fill it from models-picks.json first.")
end
local report = table.concat(out, "\n")
print(report)
return report
