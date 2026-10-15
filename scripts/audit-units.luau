-- Headless audit of every roster unit's look, weapons, attack style and ability effects (data and
-- code only; no Studio, no test suite, no sim). Loads the real config modules and LookKit with
-- stand-ins for `script` and `game`, builds every look, outfit, weapon and form look into specs and
-- checks them, and checks each ability's effects against what the client draws. Run from the
-- repository root:
--   lune run scripts/audit-units
-- Prints one line per unit (OK, or its problems) and a few notes; exits 1 if any unit has a problem.

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")
local roblox = require("@lune/roblox")

-- Module loader --------------------------------------------------------------------------------------

-- An instance stand-in for a path: children are files and folders, ReplicatedStorage.Shared is
-- src/shared.
local ALIASES = { ["RS/Shared"] = "src/shared" }
local Node = {}
local function node(path: string)
	return setmetatable({ __path = ALIASES[path] or path }, Node)
end
-- Every module and folder under src (by path without ".luau"), read up front: file reads yield,
-- which a metamethod may not.
local PATHS = {}
local function index(directory: string)
	PATHS[directory] = true
	for _, name in fs.readDir(directory) do
		local path = directory .. "/" .. name
		if fs.isDir(path) then
			index(path)
		elseif string.sub(name, -5) == ".luau" then
			PATHS[string.sub(path, 1, -6)] = true
		end
	end
end
index("src")
local function exists(path: string): boolean
	return PATHS[path] ~= nil or ALIASES[path] ~= nil
end
Node.__index = function(self, key)
	local path = rawget(self, "__path")
	if key == "Parent" then
		return node(string.match(path, "^(.*)/[^/]+$"))
	elseif key == "Name" then
		return string.match(path, "[^/]+$")
	elseif key == "WaitForChild" or key == "FindFirstChild" then
		return function(_, name)
			local child = path .. "/" .. name
			if exists(child) then
				return node(child)
			end
			assert(key == "FindFirstChild", "missing " .. child)
			return nil
		end
	end
	local child = path .. "/" .. key
	assert(exists(child), "missing " .. child)
	return node(child)
end

local game = {
	GetService = function(_, name)
		return node(if name == "ReplicatedStorage" then "RS" else "SERVICE/" .. name)
	end,
}

local globals = getfenv(1)
local loaded = {}
local function load(path: string)
	if loaded[path] ~= nil then
		return loaded[path]
	end
	local file = if fs.isFile(path .. ".luau") then path .. ".luau" else path .. "/init.luau"
	local env = setmetatable({
		script = node(path),
		game = game,
		Color3 = roblox.Color3,
		Vector3 = roblox.Vector3,
		Vector2 = roblox.Vector2,
		CFrame = roblox.CFrame,
		Enum = roblox.Enum,
		NumberRange = roblox.NumberRange,
		NumberSequence = roblox.NumberSequence,
		ColorSequence = roblox.ColorSequence,
		UDim2 = roblox.UDim2,
	}, { __index = globals })
	env.require = function(target)
		assert(type(target) == "table", "string require in " .. file)
		return load(rawget(target, "__path"))
	end
	local chunk = luau.load(fs.readFile(file), { debugName = file, environment = env })
	loaded[path] = chunk()
	return loaded[path]
end

local function shared(name: string)
	return load("src/shared/" .. name)
end

local UnitConfig = shared("UnitConfig")
local SkinConfig = shared("SkinConfig")
local FigureConfig = shared("FigureConfig")
local UnitLookConfig = shared("UnitLookConfig")
local FormLookConfig = shared("FormLookConfig")
local UnitAvatarConfig = shared("UnitAvatarConfig")
local UnitModelConfig = shared("UnitModelConfig")
local HorseLookConfig = shared("HorseLookConfig")
local AbilityFxConfig = shared("AbilityFxConfig")
local AnimationConfig = shared("AnimationConfig")
local RenderConfig = shared("RenderConfig")
local LookKit = load("src/client/LookKit")

-- Checks ---------------------------------------------------------------------------------------------

local ANCHORS = {}
for _, name in
	{ "root", "model", "hitbox", "hips", "head", "leftArm", "rightArm", "leftHand", "rightHand", "leftLeg", "rightLeg" }
do
	ANCHORS[name] = true
end
local SHAPES = { Block = true, Ball = true, Cylinder = true, Wedge = true, CornerWedge = true }
local HEIGHT = 5

local function finite(n: number): boolean
	return n == n and n > -math.huge and n < math.huge
end

local function materialOk(name: string): boolean
	return (pcall(function()
		return (roblox.Enum.Material :: any)[name]
	end))
end

-- Problems with a list of specs (`what` names them).
local function checkSpecs(specs, what: string, problems: { string })
	if #specs == 0 then
		table.insert(problems, what .. ": no parts")
	end
	for i, spec in specs do
		local bad = nil
		if not ANCHORS[spec.anchor] then
			bad = "anchor " .. tostring(spec.anchor)
		elseif not SHAPES[spec.shape] then
			bad = "shape " .. tostring(spec.shape)
		elseif
			typeof(spec.size) ~= "Vector3"
			or not (spec.size.X > 0 and spec.size.Y > 0 and spec.size.Z > 0)
			or not (finite(spec.size.X) and finite(spec.size.Y) and finite(spec.size.Z))
		then
			bad = "size " .. tostring(spec.size)
		elseif typeof(spec.offset) ~= "CFrame" or not finite(spec.offset.Position.Magnitude) then
			bad = "offset"
		elseif typeof(spec.color) ~= "Color3" then
			bad = "color " .. typeof(spec.color)
		elseif not materialOk(spec.material) then
			bad = "material " .. tostring(spec.material)
		end
		if bad then
			table.insert(problems, string.format("%s part %d: bad %s", what, i, bad))
			return
		end
	end
end

-- The figure's body (studs) as Figure.new builds it.
local function bodyOf(proportions, custom, bulk: number?)
	local body = {}
	for key, value in proportions do
		body[key] = value * HEIGHT
	end
	if custom then
		for key, value in custom do
			body[key] = value * HEIGHT
		end
	end
	local b = if custom then 1 else bulk or 1
	for _, key in { "torsoWidth", "torsoDepth", "armWidth", "legWidth", "legSpacing" } do
		body[key] *= b
	end
	body.headSize *= 1 + (b - 1) * 0.4
	return body
end

local function build(what: string, problems: { string }, run: () -> any)
	local ok, result = pcall(run)
	if not ok then
		table.insert(problems, what .. ": " .. tostring(result))
		return {}
	end
	checkSpecs(result, what, problems)
	return result
end

-- Store model data: present, loads, parts on known anchors.
local function checkModel(key: string, what: string, problems: { string })
	if not fs.isFile("src/shared/UnitModels/" .. key .. ".luau") then
		table.insert(problems, what .. ": model data " .. key .. " missing")
		return nil
	end
	local ok, data = pcall(shared, "UnitModels/" .. key)
	if not ok or type(data) ~= "table" or type(data.parts) ~= "table" or #data.parts == 0 then
		table.insert(problems, what .. ": model data " .. key .. " unreadable")
		return nil
	end
	local horseAnchors = { horse = true, horseLeg1 = true, horseLeg2 = true, horseLeg3 = true, horseLeg4 = true }
	for i, part in data.parts do
		if not (ANCHORS[part.a] or horseAnchors[part.a]) then
			table.insert(problems, string.format("%s: model part %d on unknown anchor %s", what, i, tostring(part.a)))
			break
		end
	end
	return data
end

-- Client source text, to check which event kinds and handlers exist.
local function source(name: string): string
	return fs.readFile("src/client/" .. name .. ".luau")
end
local HANDLED = {}
for _, name in { "CombatPlayback", "AbilityFx" } do
	for kind in string.gmatch(source(name), 'kind == "(%w+)"') do
		HANDLED[kind] = true
	end
end
local SIGNATURE_KINDS = {}
for kind in string.gmatch(source("AbilitySignatures"), "\nkinds%.(%w+) = {") do
	SIGNATURE_KINDS[kind] = true
end
local FX_SOURCE = source("AbilityFx") .. source("FxKit")

-- Events each effect type produces (Abilities, Battle).
local EVENTS = {
	DAMAGE = { "Damage" },
	AREA_DAMAGE = { "Area", "Damage" },
	HEAL = { "Heal" },
	SHIELD = { "Shield" },
	BUFF = { "Buff" },
	DEBUFF = { "Buff" },
	DASH = { "Dash" },
	STUN = { "Stun" },
	AREA_STUN = { "AreaStun", "Stun" },
	SUMMON = { "Summon" },
	PULL = { "Pull" },
	DAMAGE_OVER_TIME = { "Dot", "Damage" },
	COPY = { "Copy" },
	BOUNCE = { "Bounce", "Damage" },
	KNOCKBACK = { "Knockback" },
	RECALL = { "SummonEnd" },
}

-- An ability's effects (and those of its follow-ups) into `out`.
local function effectsOf(ability, out)
	for _, effect in ability.effects or {} do
		table.insert(out, effect)
	end
	if ability.onTargetKilled then
		effectsOf(ability.onTargetKilled, out)
	end
	return out
end

local function checkAbility(unitType: string, ability, what: string, problems: { string }, notes: { string })
	for _, effect in effectsOf(ability, {}) do
		local events = EVENTS[effect.type]
		if not events then
			table.insert(problems, what .. ": no event mapping for effect " .. tostring(effect.type))
			continue
		end
		for _, kind in events do
			if not HANDLED[kind] then
				table.insert(problems, string.format("%s: %s event (%s) is not drawn", what, kind, effect.type))
			end
		end
		local statuses = {}
		if effect.status then
			table.insert(statuses, effect.status)
		end
		if effect.weakenPercent then
			table.insert(statuses, "WEAKEN")
		end
		for _, status in statuses do
			if not AbilityFxConfig.statuses[status] then
				table.insert(problems, what .. ": no status marker for " .. status)
			end
		end
		if effect.type == "DAMAGE_OVER_TIME" and not effect.status then
			table.insert(notes, what .. ": damage over time with no status (no marker)")
		end
	end
	local _ = unitType
end

local ELEMENT_VALUES = {
	beam = { "straight", "jagged", "wave", "spiral", "wisp", "stretch" },
	strike = { "bolt", "flame", "splash", "swirl", "burst", "slash", "shock", "rings", "explode", "stretch" },
	ground = { "crack", "scorch", "splash", "glyph", "clock", "rings", "smoke", "none" },
}
local PARTICLES = { "spark", "flame", "ember", "smoke", "bubble", "mote", "puff", "glow" }
local function oneOf(value, list): boolean
	return table.find(list, value) ~= nil
end

local function checkElement(unitType: string, problems: { string })
	local entry = AbilityFxConfig.units[unitType]
	if not entry then
		table.insert(problems, "no AbilityFxConfig.units entry (default element)")
		return "default"
	end
	local def = AbilityFxConfig.elements[entry.element]
	if not def then
		table.insert(problems, "unknown element " .. tostring(entry.element))
		return entry.element
	end
	for field, list in ELEMENT_VALUES do
		if not oneOf(def[field], list) then
			table.insert(
				problems,
				string.format("element %s: unknown %s %s", entry.element, field, tostring(def[field]))
			)
		end
	end
	if not oneOf(def.particle, PARTICLES) or (def.accent and not oneOf(def.accent, PARTICLES)) then
		table.insert(problems, "element " .. entry.element .. ": unknown particle")
	end
	if def.ground ~= "none" and not string.find(FX_SOURCE, '"' .. def.ground .. '"', 1, true) then
		table.insert(problems, "element " .. entry.element .. ": ground mark " .. def.ground .. " not drawn by FxKit")
	end
	if typeof(entry.primary) ~= "Color3" or typeof(entry.secondary) ~= "Color3" then
		table.insert(problems, "element colors missing")
	end
	return entry.element
end

-- The attack style UnitMotion.styleFor picks (its rules, on the look CharacterLook builds).
local function styleOf(unitType: string, range: number, look): string
	if AnimationConfig.unitStyles[unitType] then
		return AnimationConfig.unitStyles[unitType]
	end
	local ranged = range > 1
	if look.attackPose == "point" and ranged then
		return "point"
	end
	if not ranged then
		for _, weapon in look.weapons or {} do
			local style = AnimationConfig.weaponStyles[weapon.kind]
			if style and not weapon.anchor then
				return style
			end
		end
	end
	local class = UnitConfig[unitType].classes[1]
	local style = if ranged then AnimationConfig.rangedClasses[class] else AnimationConfig.meleeClasses[class]
	return style or (if ranged then AnimationConfig.defaultRanged else AnimationConfig.defaultMelee)
end

local function weaponList(weapons): string
	local names = {}
	for _, w in weapons or {} do
		table.insert(names, w.kind .. "@" .. (w.anchor or w.hand or "right"))
	end
	return if #names > 0 then table.concat(names, ",") else "-"
end

-- Keys of unit-keyed config tables that are not unit ids (typos).
local strays = {}
local function checkKeys(name: string, map)
	for key in map do
		if not UnitConfig[key] and key ~= "default" then
			table.insert(strays, name .. "." .. tostring(key))
		end
	end
end
checkKeys("UnitLookConfig", UnitLookConfig)
checkKeys("FormLookConfig", FormLookConfig)
checkKeys("UnitAvatarConfig.units", UnitAvatarConfig.units)
checkKeys("UnitModelConfig", UnitModelConfig)
checkKeys("HorseLookConfig", HorseLookConfig)
checkKeys("AbilityFxConfig.units", AbilityFxConfig.units)
checkKeys("AbilityFxConfig.signatures", AbilityFxConfig.signatures)
checkKeys("FigureConfig.characters", FigureConfig.characters)
checkKeys("RenderConfig.castClones", RenderConfig.castClones)
checkKeys("RenderConfig.tongueAttacks", RenderConfig.tongueAttacks)
checkKeys("AnimationConfig.unitStyles", AnimationConfig.unitStyles)

-- Units ----------------------------------------------------------------------------------------------

local ORDER = { "Heroes", "Crew", "Shinobi", "Titans", "Arcane", "Cursed", "Spirit", "Corps", "Hunters" }
local byFaction = {}
for unitType, character in UnitConfig do
	byFaction[character.origin] = byFaction[character.origin] or {}
	table.insert(byFaction[character.origin], unitType)
end

local failed = 0
local count = 0
local noFallback = {} -- avatars with no hand-built look: the placeholder shows until they load
for _, faction in ORDER do
	local units = byFaction[faction] or {}
	table.sort(units, function(a, b)
		return UnitConfig[a].cost < UnitConfig[b].cost or (UnitConfig[a].cost == UnitConfig[b].cost and a < b)
	end)
	print("== " .. faction)
	for _, unitType in units do
		count += 1
		local character = UnitConfig[unitType]
		local problems, notes = {}, {}
		local unitLook = UnitLookConfig[unitType]
		local avatar = UnitAvatarConfig.units[unitType]
		local modelConfig = UnitModelConfig[unitType]
		local override = FigureConfig.characters[unitType]
		if not SkinConfig[unitType] then
			table.insert(problems, "no SkinConfig entry")
		end
		if not AnimationConfig.factionColors[character.origin] then
			table.insert(problems, "no faction color")
		end

		-- Look source, in Figure's order: store model, catalog avatar, hand-built look, placeholder.
		local sourceName = "placeholder"
		local weapons = nil
		if modelConfig and modelConfig.model then
			sourceName = "model"
			local data = checkModel(modelConfig.model, "model", problems)
			if data and modelConfig.outfit then
				build("model outfit", problems, function()
					return LookKit.outfitSpecs(modelConfig.outfit, bodyOf(FigureConfig.body, data.proportions), HEIGHT)
				end)
			end
		elseif avatar then
			sourceName = "avatar"
			if type(avatar.accessories) ~= "table" or #avatar.accessories == 0 then
				table.insert(problems, "avatar has no accessories")
			end
			for _, accessory in avatar.accessories or {} do
				if type(accessory.id) ~= "number" or type(accessory.slot) ~= "string" then
					table.insert(problems, "avatar accessory without slot/id")
				end
			end
			if not avatar.shirt and not avatar.pants then
				table.insert(notes, "avatar wears no shirt or pants")
			end
			if not unitLook then
				table.insert(noFallback, unitType)
			end
			weapons = if avatar.weapons == false then nil else avatar.weapons or (unitLook and unitLook.weapons)
			local body = bodyOf(FigureConfig.avatarBody)
			local outfit = avatar.outfit
				or (if unitLook and unitLook.tendrils then { tendrils = unitLook.tendrils } else nil)
			if outfit then
				build("avatar outfit", problems, function()
					return LookKit.outfitSpecs(outfit, body, HEIGHT)
				end)
			end
			if weapons then
				build("avatar weapons", problems, function()
					return LookKit.weaponSpecs(weapons, body, HEIGHT)
				end)
			end
		elseif unitLook then
			sourceName = "look"
		end
		-- The hand-built look builds whenever it exists (the fallback of an avatar or model).
		if unitLook then
			local bulk = (override and override.bulk) or unitLook.bulk
			build("look", problems, function()
				return LookKit.specs(unitLook, bodyOf(FigureConfig.body, unitLook.proportions, bulk), HEIGHT)
			end)
			build("look (low detail)", problems, function()
				return LookKit.specs(unitLook, bodyOf(FigureConfig.body, unitLook.proportions, bulk), HEIGHT, true)
			end)
			if sourceName == "look" then
				weapons = unitLook.weapons
			end
		end
		if sourceName == "placeholder" then
			table.insert(problems, "no look: placeholder figure")
		end

		-- Forms: a look of their own (model or FormLookConfig) or a RenderConfig.formLooks entry.
		-- The first form needs no entry unless a trigger returns to it (nil: no callout, no tint).
		local formNotes = {}
		local formStyles = {}
		local returnedTo = {}
		for _, form in character.forms or {} do
			if form.trigger and form.trigger.to then
				returnedTo[form.trigger.to] = true
			end
		end
		for i, form in character.forms or {} do
			local formModel = modelConfig and modelConfig.forms and modelConfig.forms[form.name]
			local formLook = FormLookConfig[unitType] and FormLookConfig[unitType][form.name]
			if (i > 1 or returnedTo[form.name]) and not RenderConfig.formLooks[form.name] then
				table.insert(problems, "form " .. form.name .. ": no RenderConfig.formLooks entry")
			end
			if formModel then
				checkModel(formModel.model, "form " .. form.name, problems)
			end
			if formLook then
				build("form " .. form.name, problems, function()
					local bulk = formLook.bulk or (override and override.bulk) or (unitLook and unitLook.bulk)
					return LookKit.specs(formLook, bodyOf(FigureConfig.body, formLook.proportions, bulk), HEIGHT)
				end)
			end
			local own = if formModel then "model" elseif formLook then "look" else nil
			if i > 1 or own then
				table.insert(formNotes, form.name .. "=" .. (own or "base"))
			end
			if form.range and form.range ~= character.range then
				local look = if formLook then { weapons = formLook.weapons } else { weapons = weapons }
				table.insert(formStyles, form.name .. ":" .. styleOf(unitType, form.range, look))
			end
			if form.ability then
				checkAbility(unitType, form.ability, "form " .. form.name .. " ability", problems, notes)
			end
		end
		local formNames = {}
		for _, form in character.forms or {} do
			formNames[form.name] = true
		end
		for formName in FormLookConfig[unitType] or {} do
			if not formNames[formName] then
				table.insert(problems, "FormLookConfig form " .. formName .. " is not one of its forms")
			end
		end
		if character.forms and character.forms[1] and character.forms[1].name == "Mounted" then
			if not HorseLookConfig[unitType] then
				table.insert(problems, "rider without a HorseLookConfig look")
			end
		end

		-- Ability and element.
		checkAbility(unitType, character.ability, "ability", problems, notes)
		local element = checkElement(unitType, problems)
		local signature = AbilityFxConfig.signatures[unitType]
		if signature and not SIGNATURE_KINDS[signature.kind] then
			table.insert(problems, "signature kind " .. tostring(signature.kind) .. " has no handler")
		end

		-- Weapons for the attack style: the drawn figure's (models carry their own).
		for _, w in weapons or {} do
			if not LookKit.WEAPONS[w.kind] then
				table.insert(problems, "unknown weapon " .. tostring(w.kind))
			end
		end
		local style = styleOf(unitType, character.range, {
			weapons = weapons,
			attackPose = override and override.attackPose,
		})
		if #formStyles > 0 then
			style ..= " (" .. table.concat(formStyles, ", ") .. ")"
		end

		local line = string.format(
			"%-18s %-6s r%d %-14s %-9s wpn %s%s%s",
			unitType,
			sourceName,
			character.range,
			style,
			element,
			weaponList(weapons),
			if #formNotes > 0 then "  forms " .. table.concat(formNotes, ",") else "",
			if signature then "  sig " .. signature.kind else ""
		)
		print(line)
		for _, problem in problems do
			print("    PROBLEM " .. problem)
		end
		for _, note in notes do
			print("    note    " .. note)
		end
		if #problems > 0 then
			failed += 1
		end
	end
end

for _, stray in strays do
	print("PROBLEM unknown unit id key: " .. stray)
	failed += 1
end
table.sort(noFallback)
print(string.format("\nnote: %d avatars fall back to the placeholder: %s", #noFallback, table.concat(noFallback, ", ")))
print(string.format("%d units, %d with problems", count, failed))
process.exit(if failed > 0 then 1 else 0)
