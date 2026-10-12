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
-- A unit whose avatar failed or timed out keeps its usual figure; the server warns once, naming the
-- unit and the asset.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UnitAvatarConfig = require(ReplicatedStorage.Shared.UnitAvatarConfig)

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
	for limb, property in LIMB_COLORS do
		local color = (entry.colors and entry.colors[limb]) or entry.skin
		if color then
			(description :: any)[property] = color
		end
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

local function build(unitType: string, entry: any)
	local started = os.clock()
	local model, problem = create(describe(entry))
	local missing = if model then missingItem(entry, model) else nil
	if not model or missing then
		if model then
			model:Destroy()
		end
		folder:SetAttribute(unitType, "failed")
		warn(
			string.format(
				"[UnitAvatars] %s: %s failed to load (%s); it keeps its usual figure.",
				unitType,
				missing or "the avatar",
				if missing then "missing from the avatar" else problem or "unknown error"
			)
		)
		return
	end
	toTemplate(model)
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
	for unitType, entry in UnitAvatarConfig.units do
		task.spawn(build, unitType, entry)
	end
end

return AvatarService
