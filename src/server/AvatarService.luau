-- Builds the catalog avatars of UnitAvatarConfig once, at server start, and shares them with every
-- client as rest-pose templates. Presentation only: nothing here touches combat or economy.
--
-- For each unit it makes an R6 avatar wearing the configured catalog items
-- (Players:CreateHumanoidModelFromDescription, server-side), checks that every item actually
-- arrived (a bad or wrong-slot item is silently left out by Roblox, so it is checked here), and
-- turns it into a template: standing with its feet on the origin, facing -Z, every part anchored,
-- no joints, scripts or root part, each accessory's handle placed on its body part and tagged with
-- that part's name (AvatarBodyPart). Clients pose the parts themselves (Figure).
--
-- Public state, replicated to every client (server-to-client only):
--   ReplicatedStorage.UnitAvatars              Folder of templates, one Model per unit id
--   ReplicatedStorage.UnitAvatars attributes   <unit id> = "loading" | "ready" | "failed"
-- A failed avatar is built once more after UnitAvatarConfig.retryDelay. A unit whose avatar still
-- fails keeps its usual figure; the server warns, naming the unit and the asset, and records it in
-- ErrorLog. No accessory may stretch a unit past UnitAvatarConfig.maxBounds (clampAccessories).
-- RoundService waits for the avatars to settle before a match's intro (waitSettled), and clients
-- lock the set of ready avatars for the whole match (UnitAvatars): no look swaps mid-match.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UnitAvatarConfig = require(ReplicatedStorage.Shared.UnitAvatarConfig)

local ErrorLog = require(script.Parent.ErrorLog)

local AvatarService = {}

local BODY_PARTS = { "Head", "Torso", "Left Arm", "Right Arm", "Left Leg", "Right Leg" }
local LIMB_COLORS = {
	head = "HeadColor",
	torso = "TorsoColor",
	leftArm = "LeftArmColor",
	rightArm = "RightArmColor",
	leftLeg = "LeftLegColor",
	rightLeg = "RightLegColor",
}
local R6_HIPS = 3 -- the torso's center above the feet on an R6 rig, in studs

local folder: Folder

-- The description for `entry`, or for just one of its accessories (`only`), to find which failed.
local function describe(entry: any, only: any?): HumanoidDescription
	local description = Instance.new("HumanoidDescription")
	local slots: { [string]: { string } } = {}
	for _, accessory in entry.accessories or {} do
		if not only or accessory == only then
			slots[accessory.slot] = slots[accessory.slot] or {}
			table.insert(slots[accessory.slot], tostring(accessory.id))
		end
	end
	for slot, ids in slots do
		(description :: any)[slot .. "Accessory"] = table.concat(ids, ",")
	end
	if not only then
		description.Shirt = entry.shirt or 0
		description.Pants = entry.pants or 0
		description.Face = entry.face or 0
	end
	local properties = description :: any
	for limb, property in LIMB_COLORS do
		properties[property] = (entry.colors and entry.colors[limb]) or entry.skin or UnitAvatarConfig.defaultSkin
	end
	return description
end

-- Makes the avatar, giving up after the config's loadTimeout. Returns the model or an error.
local function create(description: HumanoidDescription): (Model?, string?)
	local done, model, problem = false, nil, nil
	task.spawn(function()
		local ok, result =
			pcall(Players.CreateHumanoidModelFromDescription, Players, description, Enum.HumanoidRigType.R6)
		if done then
			if ok then
				result:Destroy() -- too late: the unit already uses its usual figure
			end
			return
		end
		done = true
		if ok then
			model = result
		else
			problem = tostring(result)
		end
	end)
	local deadline = os.clock() + UnitAvatarConfig.loadTimeout
	while not done and os.clock() < deadline do
		task.wait(0.1)
	end
	if not done then
		done = true
		return nil, string.format("timed out after %d s", UnitAvatarConfig.loadTimeout)
	end
	return model, problem
end

local function accessoryCount(model: Model): number
	local count = 0
	for _, child in model:GetChildren() do
		if child:IsA("Accessory") and child:FindFirstChild("Handle") then
			count += 1
		end
	end
	return count
end

-- The templates Roblox puts on an avatar whose shirt or pants failed to load: it silently swaps in
-- its default classic clothing. Learned once from a probe with item ids that are not clothing.
local fallbackTemplates: { shirt: string, pants: string }? = nil

local function defaultClothing(): { shirt: string, pants: string }
	if not fallbackTemplates then
		local probe = Instance.new("HumanoidDescription")
		probe.Shirt = 1 -- two different ids: Roblox refuses one asset in two slots
		probe.Pants = 2
		local model = create(probe)
		local shirt = model and model:FindFirstChildOfClass("Shirt")
		local pants = model and model:FindFirstChildOfClass("Pants")
		fallbackTemplates = {
			shirt = if shirt then shirt.ShirtTemplate else "",
			pants = if pants then pants.PantsTemplate else "",
		}
		if model then
			model:Destroy()
		end
	end
	return fallbackTemplates :: { shirt: string, pants: string }
end

-- The first item of `entry` missing from `model`, as "<kind> <id>", or nil if all arrived.
local function missingItem(entry: any, model: Model): string?
	if entry.shirt then
		local shirt = model:FindFirstChildOfClass("Shirt")
		if not shirt or shirt.ShirtTemplate == "" or shirt.ShirtTemplate == defaultClothing().shirt then
			return "shirt " .. entry.shirt
		end
	end
	if entry.pants then
		local pants = model:FindFirstChildOfClass("Pants")
		if not pants or pants.PantsTemplate == "" or pants.PantsTemplate == defaultClothing().pants then
			return "pants " .. entry.pants
		end
	end
	local wanted = #(entry.accessories or {})
	if accessoryCount(model) < wanted then
		-- Find the culprit: try each accessory on its own.
		for _, accessory in entry.accessories do
			local probe = create(describe(entry, accessory))
			local arrived = probe ~= nil and accessoryCount(probe) == 1
			if probe then
				probe:Destroy()
			end
			if not arrived then
				return string.format("%s accessory %d", accessory.slot, accessory.id)
			end
		end
		return "an accessory"
	end
	return nil
end

-- Rest pose with the feet on the origin, facing -Z; anchored, with no joints, scripts or root.
local function toTemplate(model: Model)
	local torso = model:FindFirstChild("Torso") :: BasePart
	local rest = CFrame.new(0, R6_HIPS, 0)
	local placed = {}
	for _, name in BODY_PARTS do
		local part = model:FindFirstChild(name) :: BasePart
		placed[part] = rest * torso.CFrame:ToObjectSpace(part.CFrame)
	end
	for part, cframe in placed do
		part.CFrame = cframe
	end
	-- Each accessory sits where its handle's attachment meets the body part's attachment.
	for _, accessory in model:GetChildren() do
		local handle = accessory:IsA("Accessory") and accessory:FindFirstChild("Handle")
		local attachment = handle and handle:FindFirstChildOfClass("Attachment")
		if handle and attachment then
			for _, name in BODY_PARTS do
				local part = model:FindFirstChild(name) :: BasePart
				local target = part:FindFirstChild(attachment.Name)
				if target and target:IsA("Attachment") then
					handle.CFrame = part.CFrame * target.CFrame * attachment.CFrame:Inverse()
					handle:SetAttribute("AvatarBodyPart", name)
					break
				end
			end
		end
	end
	local root = model:FindFirstChild("HumanoidRootPart")
	if root then
		root:Destroy()
	end
	for _, descendant in model:GetDescendants() do
		if
			descendant:IsA("JointInstance")
			or descendant:IsA("WeldConstraint")
			or descendant:IsA("BaseScript")
			or descendant:IsA("BodyColors")
		then
			descendant:Destroy()
		elseif descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanCollide = false
			descendant.CanQuery = false
			descendant.CanTouch = false
			descendant.CastShadow = false
		elseif descendant:IsA("Humanoid") then
			descendant.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
			descendant.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
		end
	end
	-- The torso is the template's reference: clients measure every part from it (Figure).
	model.PrimaryPart = model:FindFirstChild("Torso") :: BasePart
end

-- The world-axis box around `parts`: its min and max corners.
local function boxOf(parts: { BasePart }): (Vector3, Vector3)
	local low, high = Vector3.one * math.huge, -Vector3.one * math.huge
	for _, part in parts do
		local half = part.Size / 2
		for x = -1, 1, 2 do
			for y = -1, 1, 2 do
				for z = -1, 1, 2 do
					local corner = part.CFrame:PointToWorldSpace(half * Vector3.new(x, y, z))
					low, high = low:Min(corner), high:Max(corner)
				end
			end
		end
	end
	return low, high
end

-- Scales an accessory's handle by `factor` about the point where it attaches to the body.
local function scaleHandle(handle: BasePart, attachment: Attachment, factor: number)
	local hold = handle.CFrame * attachment.CFrame
	handle.Size *= factor
	local mesh = handle:FindFirstChildOfClass("SpecialMesh")
	if mesh then
		mesh.Scale *= factor
	end
	for _, child in handle:GetChildren() do
		if child:IsA("Attachment") then
			child.Position *= factor
		end
	end
	handle.CFrame = hold * attachment.CFrame:Inverse()
end

-- No accessory may make the unit's bounds bigger than UnitAvatarConfig.maxBounds x the body's
-- height on any axis (a normal unit is the body alone): a bigger one is scaled down about its
-- attachment point. Returns what was clamped ("<accessory> x<factor>").
local function clampAccessories(model: Model): { string }
	local body = {}
	for _, name in BODY_PARTS do
		table.insert(body, model:FindFirstChild(name) :: BasePart)
	end
	local bodyLow, bodyHigh = boxOf(body)
	local limit = (bodyHigh.Y - bodyLow.Y) * UnitAvatarConfig.maxBounds
	local function fits(handle: BasePart): boolean
		local low, high = boxOf({ handle })
		local size = high:Max(bodyHigh) - low:Min(bodyLow)
		return size.X <= limit and size.Y <= limit and size.Z <= limit
	end
	local clamped = {}
	for _, accessory in model:GetChildren() do
		local handle = accessory:IsA("Accessory") and accessory:FindFirstChild("Handle")
		local attachment = handle and handle:IsA("BasePart") and handle:FindFirstChildOfClass("Attachment")
		if handle and attachment and not fits(handle) then
			local total = 1
			while not fits(handle) and total > 0.3 do
				scaleHandle(handle, attachment, 0.9)
				total *= 0.9
			end
			table.insert(clamped, string.format("%s x%.2f", accessory.Name, total))
		end
	end
	return clamped
end

-- Every settled: no unit's avatar still loading.
function AvatarService.settled(): boolean
	if not folder then
		return false
	end
	for unitType in UnitAvatarConfig.units do
		if folder:GetAttribute(unitType) == "loading" then
			return false
		end
	end
	return true
end

-- Waits until every avatar has settled (ready or failed), at most `seconds`. Called before a
-- match's intro, so the clients' lock (UnitAvatars) sees every avatar that could make it.
function AvatarService.waitSettled(seconds: number)
	local deadline = os.clock() + seconds
	while not AvatarService.settled() and os.clock() < deadline do
		task.wait(0.25)
	end
end

-- One attempt: the avatar model with every item, or nil and what failed.
local function attempt(entry: any): (Model?, string?)
	local model, problem = create(describe(entry))
	local missing = if model then missingItem(entry, model) else nil
	if model and not missing then
		return model, nil
	end
	if model then
		model:Destroy()
	end
	return nil,
		string.format(
			"%s failed to load (%s)",
			missing or "the avatar",
			if missing then "missing from the avatar" else problem or "unknown error"
		)
end

local function build(unitType: string, entry: any)
	local started = os.clock()
	local model, failure = attempt(entry)
	if not model then
		-- Once more after a short wait (a catalog hiccup or throttling often passes).
		warn(string.format("[UnitAvatars] %s: %s; retrying in %d s", unitType, failure, UnitAvatarConfig.retryDelay))
		task.wait(UnitAvatarConfig.retryDelay)
		model, failure = attempt(entry)
	end
	if not model then
		folder:SetAttribute(unitType, "failed")
		local message = string.format("%s: %s after a retry; it keeps its usual figure.", unitType, tostring(failure))
		warn("[UnitAvatars] " .. message)
		ErrorLog.record("avatar " .. unitType, message)
		return
	end
	-- A unit may go without a shirt or pants (its bare limbs take its tuned colors, and a
	-- block-built outfit can cover them): drop any clothing it did not ask for.
	if not entry.shirt then
		for _, shirt in model:GetChildren() do
			if shirt:IsA("Shirt") then
				shirt:Destroy()
			end
		end
	end
	if not entry.pants then
		for _, pants in model:GetChildren() do
			if pants:IsA("Pants") then
				pants:Destroy()
			end
		end
	end
	toTemplate(model)
	for _, clamp in clampAccessories(model) do
		warn(
			string.format(
				"[UnitAvatars] %s clamped %s (over %.1fx a normal unit)",
				unitType,
				clamp,
				UnitAvatarConfig.maxBounds
			)
		)
	end
	model.Name = unitType
	model.Parent = folder
	folder:SetAttribute(unitType, "ready")
	print(string.format("[UnitAvatars] %s ready in %.2f s", unitType, os.clock() - started))
end

function AvatarService.start()
	folder = Instance.new("Folder")
	folder.Name = "UnitAvatars"
	for unitType in UnitAvatarConfig.units do
		folder:SetAttribute(unitType, "loading")
	end
	folder.Parent = ReplicatedStorage

	-- A queue worked by `buildAtOnce` builders, so dozens of avatars do not all hit Roblox at once.
	-- The default clothing is learned first, so the builders share one probe.
	local jobs = {}
	for unitType in UnitAvatarConfig.units do
		table.insert(jobs, unitType)
	end
	table.sort(jobs)
	task.spawn(function()
		defaultClothing()
		local nextJob = 1
		for _ = 1, math.min(UnitAvatarConfig.buildAtOnce, #jobs) do
			task.spawn(function()
				while nextJob <= #jobs do
					local unitType = jobs[nextJob]
					nextJob += 1
					build(unitType, UnitAvatarConfig.units[unitType])
				end
			end)
		end
	end)
end

return AvatarService
