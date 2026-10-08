-- What players see of a unit type: its name, body color, size multiplier and figure look (Figure).
-- Characters: their SkinConfig name, color and optional model, their first class's prop
-- (FigureConfig.classes) unless their FigureConfig.characters override changes the prop, size,
-- bulk or attack pose, and a ring in their cost's color (RenderConfig.costColors). Creeps and
-- bosses: their theme's look (PveThemeConfig), drawn as hunched figures with no prop or ring.
-- Presentation only.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local FigureConfig = require(Shared:WaitForChild("FigureConfig"))
local Pve = require(Shared:WaitForChild("Pve"))
local RenderConfig = require(Shared:WaitForChild("RenderConfig"))
local SkinConfig = require(Shared:WaitForChild("SkinConfig"))
local UnitConfig = require(Shared:WaitForChild("UnitConfig"))

local Figure = require(script.Parent.Figure)

local CharacterLook = {}

export type CharacterLook = {
	name: string,
	color: Color3,
	scale: number,
	figure: Figure.Look,
}

local function rgb(color: { number }): Color3
	return Color3.fromRGB(color[1], color[2], color[3])
end

local cache: { [string]: CharacterLook } = {}

-- A character's prop and arm look: its first class's, changed by its FigureConfig.characters
-- override (prop, arms, attackHand) if it has one.
local function classLookOf(character, override): any
	local classLook = FigureConfig.classes[character.classes[1]]
	if not override then
		return classLook
	end
	local prop = override.prop
	if prop == false then
		classLook = { hand = "right", arms = { 0, 0 }, parts = {} }
	elseif type(prop) == "string" then
		classLook = FigureConfig.classes[prop]
	elseif type(prop) == "table" then
		classLook = prop
	end
	if override.arms or override.attackHand then
		classLook = table.clone(classLook)
		classLook.arms = override.arms or classLook.arms
		classLook.hand = override.attackHand or classLook.hand
	end
	return classLook
end

function CharacterLook.of(unitType: string): CharacterLook
	local cached = cache[unitType]
	if cached then
		return cached
	end
	local look: CharacterLook
	local character = UnitConfig[unitType]
	if character then
		local skin = SkinConfig[unitType]
		local override = FigureConfig.characters[unitType]
		look = {
			name = skin.name,
			color = rgb(skin.color),
			scale = if override and override.scale then override.scale else 1,
			figure = {
				style = "roster",
				classLook = classLookOf(character, override),
				ringColor = RenderConfig.costColors[character.cost],
				model = skin.model,
				bulk = if override then override.bulk else nil,
				attackPose = if override then override.attackPose else nil,
			},
		}
	else
		local stats = Pve.pveUnitType(unitType)
		look = {
			name = stats.look.name,
			color = rgb(stats.look.color),
			scale = stats.look.scale or 1,
			figure = { style = if stats.kind == "boss" then "boss" else "creep" },
		}
	end
	cache[unitType] = look
	return look
end

-- Summons: a plain figure in their summoner's body color, smaller and see-through (UnitView).
CharacterLook.summon = table.freeze({ style = "summon" }) :: Figure.Look

return CharacterLook
