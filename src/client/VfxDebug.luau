-- Studio checks for the effect textures (VfxConfig), reachable from the command bar while playing
-- through DevLineup's QA handle:
--   game.Players.LocalPlayer.DevLineupQA:Invoke("vfxReport")
--       prints the effects quality (and how it was chosen), every picked image with its load status
--       and asset type (an image id, not a decal id), what each usage draws with for a sample unit of
--       every element (or why it falls back to neon), and the textured vs fallback draws since the
--       fight or preview started
--   game.Players.LocalPlayer.DevLineupQA:Invoke("vfxTest", seconds?)
--       puts every picked image in front of the camera for `seconds` (default 8): on a plain
--       unlit plane, and as particles beside it, each labelled with its pick, so you can see whether
--       the images themselves render
-- Studio only (DevLineup). Presentation only.

local ContentProvider = game:GetService("ContentProvider")
local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AbilityFxConfig = require(Shared:WaitForChild("AbilityFxConfig"))
local VfxConfig = require(Shared:WaitForChild("VfxConfig"))
local VfxResolve = require(Shared:WaitForChild("VfxResolve"))

local ImpactEffects = require(script.Parent.ImpactEffects)
local Vfx = require(script.Parent.Vfx)

local VfxDebug = {}

local ASSET_TYPES = { [1] = "Image", [13] = "Decal", [40] = "MeshPart", [10] = "Model" }

-- Every pick, in role and rank order.
local function picks(): { { key: string, role: string, pick: any } }
	local out = {}
	for _, role in VfxConfig.roles do
		for _, pick in VfxConfig.picks[role] or {} do
			table.insert(out, { key = role .. ":" .. pick.rank, role = role, pick = pick })
		end
	end
	return out
end

-- The Creator Store type of an asset id ("Image", "Decal", ...), asked of the marketplace.
local function assetType(id: number): string
	local ok, info = pcall(function()
		return MarketplaceService:GetProductInfo(id, Enum.InfoType.Asset)
	end)
	if not ok or type(info) ~= "table" then
		return "unknown (" .. tostring(info) .. ")"
	end
	return ASSET_TYPES[info.AssetTypeId] or ("type " .. tostring(info.AssetTypeId))
end

local function fetchStatus(id: number): string
	local ok, status = pcall(function()
		return ContentProvider:GetAssetFetchStatus("rbxassetid://" .. string.format("%d", id))
	end)
	return if ok and status then status.Name else "?"
end

-- A sample unit (its id and colors) for each element in AbilityFxConfig.
local function samples(): { { element: string, unit: string?, color: Color3 } }
	local byElement = {}
	local ids = {}
	for unitType in AbilityFxConfig.units do
		table.insert(ids, unitType)
	end
	table.sort(ids)
	for _, unitType in ids do
		local entry = AbilityFxConfig.units[unitType]
		if not byElement[entry.element] then
			byElement[entry.element] = { element = entry.element, unit = unitType, color = entry.primary }
		end
	end
	local out = {}
	local elements = {}
	for element in AbilityFxConfig.elements do
		table.insert(elements, element)
	end
	table.sort(elements)
	for _, element in elements do
		table.insert(out, byElement[element] or { element = element, unit = nil, color = Color3.new(1, 1, 1) })
	end
	return out
end

-- Why a resolve fell back to neon, briefly: each candidate's reason.
local function why(trace: { VfxResolve.Trace }): string
	local parts = {}
	for _, step in trace do
		table.insert(parts, step.key .. " " .. step.reason)
	end
	return if #parts > 0 then table.concat(parts, "; ") else "no candidates"
end

function VfxDebug.report(): string
	local lines = {}
	local function line(text: string)
		table.insert(lines, text)
	end
	local quality = ImpactEffects.qualityInfo()
	line("==== VFX REPORT ====")
	line(
		string.format(
			"quality: %s (%s) | shapes drawn: %s | maxSkinned: %d | textured shapes alive: %d | particles x%.2f, cap %d | impact frame: %s",
			quality.name,
			quality.source,
			tostring(quality.shapes),
			quality.maxSkinned,
			quality.skinnedNow,
			quality.particles,
			quality.maxParticles,
			tostring(quality.impactFrame)
		)
	)
	line(
		string.format(
			"loading: requireLoaded=%s, first pass done=%s, retries after %s s | hue.strict=%s bakedTint=%.2f | filters: sprites=%s burstAnywhere=%s beamAlong=%s",
			tostring(VfxConfig.loading.requireLoaded),
			tostring(Vfx.preloaded()),
			table.concat(VfxConfig.loading.retryDelays, "/"),
			tostring(VfxConfig.hue.strict),
			VfxConfig.hue.bakedTint,
			tostring(VfxConfig.filters.sprites),
			tostring(VfxConfig.filters.burstAnywhere),
			tostring(VfxConfig.filters.beamAlong)
		)
	)

	line("-- picked images (the id drawn with must be an Image, not the Decal):")
	for _, entry in picks() do
		local pick = entry.pick
		if pick.kind == "model" then
			line(
				string.format(
					"  %-13s model %d: %s",
					entry.key,
					pick.asset,
					if pick.textures
						then #pick.textures .. " exported textures"
						else "pending (" .. tostring(pick.pending) .. ")"
				)
			)
		elseif not pick.image then
			line(string.format("  %-13s %s: %s", entry.key, tostring(pick.name), tostring(pick.pending)))
		else
			local traits = VfxConfig.traits[pick.name] or VfxConfig.traits[pick.image]
			line(
				string.format(
					"  %-13s %s image %d [%s] (decal %s [%s]) | vfx status %s | fetch status %s | usable %s%s",
					entry.key,
					tostring(pick.name),
					pick.image,
					assetType(pick.image),
					tostring(pick.asset),
					if pick.asset then assetType(pick.asset) else "-",
					Vfx.status(pick.image),
					fetchStatus(pick.image),
					tostring(Vfx.usable(pick.image)),
					if traits and traits.unusable then " | UNUSABLE: " .. traits.unusable else ""
				)
			)
		end
	end

	line("-- usages: what each draws with per element (sample unit), or NEON and why:")
	local usages = {}
	for usage in VfxConfig.uses do
		table.insert(usages, usage)
	end
	table.sort(usages)
	local sampleUnits = samples()
	local allTextured, someTextured, allNeon = 0, 0, 0
	for _, usage in usages do
		local config = VfxConfig.uses[usage]
		-- Group the elements by result.
		local groups, order = {}, {}
		for _, sample in sampleUnits do
			local texture, trace = VfxResolve.resolve(
				usage,
				{ unit = sample.unit, element = sample.element, color = sample.color },
				Vfx.usable
			)
			local result
			if texture then
				result = texture.key
					.. " "
					.. texture.mode
					.. (if texture.sprite then " (as an additive sprite)" else "")
				local shaped = texture.mode == "plane" or texture.mode == "billboard" or texture.mode == "beam"
				if shaped and not quality.shapes then
					result ..= " (but shapes are off at this quality: neon/none)"
				elseif shaped and quality.skinnedNow >= quality.maxSkinned then
					result ..= " (quality cap reached right now: neon)"
				end
			else
				result = "NEON (" .. why(trace) .. ")"
			end
			if not groups[result] then
				groups[result] = {}
				table.insert(order, result)
			end
			table.insert(groups[result], sample.element .. (if sample.unit then "/" .. sample.unit else ""))
		end
		local neon = 0
		for _, result in order do
			if string.sub(result, 1, 4) == "NEON" then
				neon += #groups[result]
			end
		end
		if neon == 0 then
			allTextured += 1
		elseif neon == #sampleUnits then
			allNeon += 1
		else
			someTextured += 1
		end
		line(string.format("  %s [%s; %s]:", usage, table.concat(config.roles, ","), table.concat(config.modes, ",")))
		for _, result in order do
			line("      " .. result .. " <- " .. table.concat(groups[result], " "))
		end
	end

	line(
		string.format(
			"usages: %d of %d textured for every element, %d for some, %d neon for all",
			allTextured,
			#usages,
			someTextured,
			allNeon
		)
	)
	line("-- draws since the fight/preview started (texture requests: textured / neon fallback):")
	local counts = Vfx.counts()
	local names = {}
	for usage in counts do
		table.insert(names, usage)
	end
	table.sort(names)
	local textured, fallback = 0, 0
	for _, usage in names do
		local c = counts[usage]
		textured += c.textured
		fallback += c.fallback
		line(string.format("  %-12s %d / %d", usage, c.textured, c.fallback))
	end
	line(
		string.format(
			"  total %d textured / %d fallback | textured shapes drawn %d, kept neon by the quality cap %d",
			textured,
			fallback,
			quality.skinnedDrawn,
			quality.capped
		)
	)
	if #names == 0 then
		line("  (no effects drawn yet: play a fight or press 1-9 in a lineup close-up, then report again)")
	end
	line("==== END VFX REPORT ====")
	local text = table.concat(lines, "\n")
	print(text)
	return text
end

-- Every picked image in front of the camera for `seconds`: a plain unlit plane, and particles beside
-- it, each labelled with its pick.
function VfxDebug.test(seconds: number?)
	local camera = workspace.CurrentCamera
	if not camera then
		return "no camera"
	end
	local life = seconds or 8
	local folder = Instance.new("Folder")
	folder.Name = "VfxTest"
	local images = {}
	for _, entry in picks() do
		if entry.pick.kind == "image" and entry.pick.image then
			table.insert(images, entry)
		end
	end
	local columns = 6
	local spacing = 4.2
	local distance = 24
	local rows = math.ceil(#images / columns)
	local origin = camera.CFrame
	local lines = {}
	for i, entry in images do
		local column = (i - 1) % columns
		local row = math.floor((i - 1) / columns)
		local x = (column - (columns - 1) / 2) * spacing
		local y = ((rows - 1) / 2 - row) * spacing
		local frame = origin * CFrame.new(x - spacing * 0.22, y, -distance)
		local image = "rbxassetid://" .. string.format("%d", entry.pick.image)

		-- The plane: an invisible part with the image on the side facing the camera.
		local plane = Instance.new("Part")
		plane.Anchored = true
		plane.CanCollide = false
		plane.CanQuery = false
		plane.CanTouch = false
		plane.CastShadow = false
		plane.Transparency = 1
		plane.Size = Vector3.new(2.4, 2.4, 0.05)
		plane.CFrame = frame
		plane.Parent = folder
		local surface = Instance.new("SurfaceGui")
		surface.Face = Enum.NormalId.Back -- the part faces away from the camera, as the camera does
		surface.LightInfluence = 0
		surface.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
		surface.CanvasSize = Vector2.new(256, 256)
		surface.Parent = plane
		local backing = Instance.new("Frame")
		backing.Size = UDim2.fromScale(1, 1)
		backing.BackgroundColor3 = Color3.fromRGB(40, 40, 48)
		backing.BackgroundTransparency = 0.2
		backing.Parent = surface
		local label = Instance.new("ImageLabel")
		label.BackgroundTransparency = 1
		label.Size = UDim2.fromScale(1, 1)
		label.Image = image
		label.Parent = surface

		-- Particles beside it, with the texture's flipbook if it has one.
		local holder = Instance.new("Part")
		holder.Anchored = true
		holder.CanCollide = false
		holder.CanQuery = false
		holder.CanTouch = false
		holder.Transparency = 1
		holder.Size = Vector3.one * 0.2
		holder.CFrame = origin * CFrame.new(x + spacing * 0.3, y, -distance)
		holder.Parent = folder
		local traits = VfxConfig.traits[entry.pick.name] or VfxConfig.traits[entry.pick.image] or {}
		local emitter = Instance.new("ParticleEmitter")
		emitter.Texture = image
		emitter.LightEmission = if traits.blend == "additive" then 1 else 0
		emitter.LightInfluence = 0
		emitter.Size = NumberSequence.new(1.4)
		emitter.Transparency = NumberSequence.new(0, 1)
		emitter.Lifetime = NumberRange.new(1)
		emitter.Speed = NumberRange.new(0.3)
		emitter.Rate = 3
		if traits.flipbook then
			emitter.FlipbookLayout = (Enum.ParticleFlipbookLayout :: any)["Grid" .. traits.flipbook.layout]
			emitter.FlipbookMode = (Enum.ParticleFlipbookMode :: any)[traits.flipbook.mode]
				or Enum.ParticleFlipbookMode.OneShot
		end
		emitter.Parent = holder

		-- The label.
		local tag = Instance.new("BillboardGui")
		tag.Size = UDim2.fromOffset(160, 36)
		tag.StudsOffset = Vector3.new(0, -1.9, 0)
		tag.AlwaysOnTop = true
		tag.Parent = plane
		local text = Instance.new("TextLabel")
		text.Size = UDim2.fromScale(1, 1)
		text.BackgroundTransparency = 1
		text.TextColor3 = Color3.new(1, 1, 1)
		text.TextStrokeTransparency = 0
		text.TextScaled = true
		text.Text = entry.key .. " " .. string.format("%d", entry.pick.image)
		text.Parent = tag
		table.insert(
			lines,
			string.format("  %s image %d (%s)", entry.key, entry.pick.image, Vfx.status(entry.pick.image))
		)
	end
	folder.Parent = workspace
	task.delay(life, function()
		folder:Destroy()
	end)
	local text = string.format(
		"VFX TEST: %d images in front of the camera for %d s (plane left, particles right of each label):\n%s",
		#images,
		life,
		table.concat(lines, "\n")
	)
	print(text)
	return text
end

return VfxDebug
