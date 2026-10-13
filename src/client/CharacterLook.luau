-- What players see of a unit type: its name, body color, size multiplier and figure look (Figure).
-- Characters: their SkinConfig name, color and optional model, their first class's prop
-- (FigureConfig.classes) unless their FigureConfig.characters override changes the prop, size,
-- bulk or attack pose, and a ring in their cost's color (RenderConfig.costColors). A character with
-- a hand-built look (UnitLookConfig) is drawn from it instead of the placeholder; the look can
-- also set the attack hand, resting arms, scale and bulk. A character with a catalog avatar
-- (UnitAvatarConfig) is drawn as that avatar once the server has it ready (Figure, UnitAvatars),
-- falling back to its look or placeholder. Creeps and bosses: their theme's look
-- (PveThemeConfig), drawn as hunched figures with no prop or ring. Presentation only.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local FigureConfig = require(Shared:WaitForChild("FigureConfig"))
local Pve = require(Shared:WaitForChild("Pve"))
local RenderConfig = require(Shared:WaitForChild("RenderConfig"))
local SkinConfig = require(Shared:WaitForChild("SkinConfig"))
local UnitConfig = require(Shared:WaitForChild("UnitConfig"))
local FormLookConfig = require(Shared:WaitForChild("FormLookConfig"))
local UnitAvatarConfig = require(Shared:WaitForChild("UnitAvatarConfig"))
local UnitLookConfig = require(Shared:WaitForChild("UnitLookConfig"))

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
-- override (prop, arms, attackHand) if it has one, then by its UnitLookConfig look and its
-- UnitAvatarConfig avatar (hand, arms).
local function classLookOf(character, override, unitLook, avatar): any
	local classLook = FigureConfig.classes[character.classes[1]]
	if override then
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
	end
	for _, source in { unitLook or false, avatar or false } do
		if source and (source.arms or source.hand) then
			classLook = table.clone(classLook)
			classLook.arms = source.arms or classLook.arms
			classLook.hand = source.hand or classLook.hand
		end
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
		local unitLook = UnitLookConfig[unitType]
		local avatar = UnitAvatarConfig.units[unitType]
		local scale = if override and override.scale then override.scale else 1
		if unitLook and unitLook.scale then
			scale *= unitLook.scale
		end
		if avatar and avatar.scale then
			scale *= avatar.scale
		end
		local bulk = if override then override.bulk else nil
		if not bulk and unitLook then
			bulk = unitLook.bulk
		end
		look = {
			name = skin.name,
			color = rgb(skin.color),
			scale = scale,
			figure = {
				style = "roster",
				classLook = classLookOf(character, override, unitLook, avatar),
				ringColor = RenderConfig.costColors[character.cost],
				model = skin.model,
				bulk = bulk,
				attackPose = if override then override.attackPose else nil,
				unitLook = unitLook,
				avatar = if avatar then unitType else nil,
				avatarProp = not avatar or avatar.prop ~= false,
				avatarWeapons = if avatar then avatar.weapons else nil,
				avatarOutfit = if avatar then avatar.outfit else nil,
				unitType = unitType,
				formLooks = FormLookConfig[unitType],
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

-- The figure look of a unit in form `formName`: the form's own look (FormLookConfig), drawn with
-- LookKit in place of the base figure (catalog avatar, hand-built look or placeholder), or the base
-- figure itself when the form has no look of its own. Also returns whether the form has its own
-- look, and that look's extra size multiplier (on top of RenderConfig.formLooks `scale`).
local formFigures: { [any]: { [string]: Figure.Look } } = {}
function CharacterLook.formFigure(base: Figure.Look, formName: string?): (Figure.Look, boolean, number)
	local formLook = if formName and base.formLooks then base.formLooks[formName] else nil
	if not formLook then
		return base, false, 1
	end
	local byForm = formFigures[base]
	if not byForm then
		byForm = {}
		formFigures[base] = byForm
	end
	local figure = byForm[formName :: string]
	if not figure then
		figure = table.clone(base)
		figure.avatar = nil
		figure.avatarWeapons = nil
		figure.avatarOutfit = nil
		figure.unitLook = formLook
		figure.bulk = formLook.bulk or base.bulk
		byForm[formName :: string] = figure
	end
	return figure, true, formLook.scale or 1
end

-- Summons: a plain figure in their summoner's body color, smaller and see-through (UnitView).
CharacterLook.summon = table.freeze({ style = "summon" }) :: Figure.Look

return CharacterLook
