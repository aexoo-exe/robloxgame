-- The hub's lighting and sky (HubConfig.lighting), on this client only, while the player is in the
-- hub. Entering the hub saves the Lighting properties it changes and moves the arena's sky,
-- atmosphere and post effects aside; leaving puts all of them back exactly, so the arena looks the
-- same in a match as before. The baseplate is hidden in the hub too (the island floats over open
-- sky), and shown again for matches. Presentation only.

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local HubConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("HubConfig"))

local HubLighting = {}

local EFFECT_CLASSES = { "Sky", "Atmosphere", "ColorCorrectionEffect", "BloomEffect", "SunRaysEffect" }

local active = false
local savedProperties: { [string]: any } = {}
local savedChildren: { Instance } = {}
local hubChildren: { Instance } = {}
local hiddenBaseplate: { [Instance]: number } = {} -- part or decal -> its transparency before

local function isEffect(instance: Instance): boolean
	for _, className in EFFECT_CLASSES do
		if instance:IsA(className) then
			return true
		end
	end
	return false
end

local function create(className: string, properties: { [string]: any })
	local instance = Instance.new(className)
	for property, value in properties do
		(instance :: any)[property] = value
	end
	instance.Parent = Lighting
	table.insert(hubChildren, instance)
end

-- Hides (or shows again) the baseplate and anything drawn on it, such as a grid texture.
local function setBaseplateHidden(hidden: boolean)
	if hidden then
		local baseplate = workspace:FindFirstChild("Baseplate")
		if not baseplate then
			return
		end
		for _, instance in { baseplate, unpack(baseplate:GetDescendants()) } do
			if instance:IsA("BasePart") or instance:IsA("Decal") then
				hiddenBaseplate[instance] = (instance :: any).Transparency
				;(instance :: any).Transparency = 1
			end
		end
	else
		for instance, transparency in hiddenBaseplate do
			if instance.Parent then
				(instance :: any).Transparency = transparency
			end
		end
		table.clear(hiddenBaseplate)
	end
end

function HubLighting.setActive(value: boolean)
	if value == active then
		return
	end
	active = value
	local config = HubConfig.lighting
	if value then
		table.clear(savedProperties)
		for property, setting in config.properties do
			savedProperties[property] = (Lighting :: any)[property]
			;(Lighting :: any)[property] = setting
		end
		table.clear(savedChildren)
		for _, child in Lighting:GetChildren() do
			if isEffect(child) then
				table.insert(savedChildren, child)
				child.Parent = nil
			end
		end
		create("Atmosphere", config.atmosphere)
		create("Sky", config.sky)
		create("ColorCorrectionEffect", config.colorCorrection)
		create("BloomEffect", config.bloom)
	else
		for _, child in hubChildren do
			child:Destroy()
		end
		table.clear(hubChildren)
		for property, setting in savedProperties do
			(Lighting :: any)[property] = setting
		end
		for _, child in savedChildren do
			child.Parent = Lighting
		end
		table.clear(savedChildren)
	end
	setBaseplateHidden(value)
end

return HubLighting
