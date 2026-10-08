-- What players see of a unit type: its name, body color, size multiplier and figure look (Figure).
-- Characters: their SkinConfig name, color and optional model, their first class's prop
-- (FigureConfig.classes) and a ring in their cost's color (RenderConfig.costColors). Creeps and
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

function CharacterLook.of(unitType: string): CharacterLook
	local cached = cache[unitType]
	if cached then
		return cached
	end
	local look: CharacterLook
	local character = UnitConfig[unitType]
	if character then
		local skin = SkinConfig[unitType]
		look = {
			name = skin.name,
			color = rgb(skin.color),
			scale = 1,
			figure = {
				style = "roster",
				classLook = FigureConfig.classes[character.classes[1]],
				ringColor = RenderConfig.costColors[character.cost],
				model = skin.model,
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
