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
local function styleOf(unitType: string, range: number, look, formName: string?): string
	if formName and AnimationConfig.formStyles[formName] then
		return AnimationConfig.formStyles[formName]
	end
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
		table.insert(names, w.kind .. "@" .. (w.anchor or w.hand or "right") .. (if w.drawn then "(drawn)" else ""))
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

local UltimateConfig = shared("UltimateConfig")
local Vector3 = roblox.Vector3

-- Ultimates: a dry run of each unit's timeline (Ultimates/<unit id>) on stand-ins ----------------------
-- ImpactEffects is replaced by a recorder (FxKit and UltimateKit draw through it), each recorded
-- part's step is run on a checking stand-in part, every beat, the release and the event hooks run
-- on a stand-in run whose methods are Cinematic's (read from its source), and the pose keys are
-- evaluated with the real UnitMotion.

local recorded = {} -- shapes drawn during a dry run, with their real start and end
local stubErrors = {}
local dryClock = 0 -- the dry run's clock (design time)
local recordGroup = "cast" -- shift parts are budgeted apart (they never overlap a cast)
local function recordClock(): number
	return dryClock
end
-- Most effect parts alive at once (the shape pool is AnimationConfig.pools.shapes, shared).
local PEAK_LIMIT = { 14, 18, 26, 34, 44 }
local function expect(value, kind: string, what: string)
	if typeof(value) ~= kind then
		table.insert(stubErrors, string.format("%s: %s expected, got %s", what, kind, typeof(value)))
	end
end

-- Effect textures: the real Vfx (and VfxResolve, VfxConfig) with every image counting as loaded.
-- Each texture request is recorded: per dry run (`textureLog`) and over the whole audit (`chosen`).
local VfxConfig = shared("VfxConfig")
local VfxResolve = shared("VfxResolve")
local Vfx = load("src/client/Vfx")
local textureLog: { { usage: string, key: string? } } = {}
local chosen: { [string]: boolean } = {} -- pick keys some effect drew with
local requested: { [string]: boolean } = {} -- usages some effect asked for
local resolveTexture = Vfx.texture
Vfx.texture = function(usage, color, mode)
	local texture = resolveTexture(usage, color, mode)
	requested[usage] = true
	if texture then
		chosen[texture.key] = true
	end
	table.insert(textureLog, { usage = usage, key = texture and texture.key })
	return texture
end
-- The usage each particle kind draws with, read from ImpactEffects' KINDS (the stub below stands in
-- for it, so the real table is read from its source).
local KIND_USAGE = {}
do
	local text = source("ImpactEffects")
	for kind, body in string.gmatch(text, "\n\t(%a+) = (%b{})") do
		local usage = string.match(body, 'usage = "(%a+)"')
		if usage then
			KIND_USAGE[kind] = usage
		end
	end
end

loaded["src/client/ImpactEffects"] = {
	shape = function(shape, color, duration, step, delay, _material, texture, textureOnly)
		expect(color, "Color3", "shape color")
		expect(duration, "number", "shape duration")
		if texture ~= nil and type(texture) ~= "table" then
			table.insert(stubErrors, "shape texture: a Vfx texture or nil expected")
		end
		if textureOnly and not texture then
			return -- a glow layer with no texture draws nothing
		end
		local startAt = recordClock() + (delay or 0)
		local group = recordGroup
		table.insert(
			recorded,
			{ shape = shape, step = step, startAt = startAt, endAt = startAt + duration, group = group }
		)
	end,
	ball = function(position, color, diameter, _duration, usage, textureColor)
		expect(position, "Vector3", "ball position")
		expect(color, "Color3", "ball color")
		expect(diameter, "number", "ball size")
		Vfx.texture(usage or "flash", textureColor or color, "particle")
	end,
	ring = function(position, color, diameter)
		expect(position, "Vector3", "ring position")
		expect(color, "Color3", "ring color")
		expect(diameter, "number", "ring size")
		Vfx.texture("ring", color, "plane")
	end,
	burst = function(kind, position, _direction, burst)
		expect(kind, "string", "burst kind")
		expect(position, "Vector3", "burst position")
		expect(burst.color, "Color3", "burst color")
		if KIND_USAGE[kind] then
			Vfx.texture(KIND_USAGE[kind], burst.color, "particle")
		end
	end,
	emit = function(position, spec)
		expect(position, "Vector3", "emit position")
		expect(spec.count, "number", "emit count")
		expect(spec.color, "ColorSequence", "emit color")
		expect(spec.size, "NumberSequence", "emit size")
		expect(spec.transparency, "NumberSequence", "emit transparency")
		if spec.usage then
			Vfx.texture(spec.usage, nil, "particle")
		end
	end,
	light = function(position, color, brightness, range, duration)
		expect(position, "Vector3", "light position")
		expect(color, "Color3", "light color")
		expect(brightness, "number", "light brightness")
		expect(range, "number", "light range")
		expect(duration, "number", "light duration")
	end,
	setTimeScale = function() end,
	later = function(_delay, fn)
		fn()
	end,
	impactFrame = function() end,
	shake = function(amount)
		expect(amount, "number", "shake")
	end,
	allows = function()
		return true
	end,
	quality = function()
		return "high"
	end,
	particleShare = function()
		return 1
	end,
}
local Ultimates = load("src/client/Ultimates")
local UnitMotion = load("src/client/UnitMotion")

-- A part that checks what a step sets on it.
local function checkingPart()
	return setmetatable({}, {
		__newindex = function(self, key, value)
			if key == "Size" then
				assert(typeof(value) == "Vector3", "Size is " .. typeof(value))
				assert(
					finite(value.X)
						and finite(value.Y)
						and finite(value.Z)
						and value.X >= 0
						and value.Y >= 0
						and value.Z >= 0,
					"bad Size " .. tostring(value)
				)
			elseif key == "CFrame" then
				assert(typeof(value) == "CFrame", "CFrame is " .. typeof(value))
				assert(finite(value.Position.Magnitude), "bad CFrame")
			elseif key == "Transparency" then
				assert(type(value) == "number" and finite(value), "bad Transparency")
			end
			rawset(self, key, value)
		end,
	})
end

local RUN_METHODS = {}
for name in string.gmatch(source("Cinematic"), "\nfunction Methods%.(%w+)") do
	RUN_METHODS[name] = true
end
local POSE_CHANNELS = {}
for _, name in
	{
		"leftArm",
		"rightArm",
		"leftArmOut",
		"rightArmOut",
		"lean",
		"twist",
		"tilt",
		"fall",
		"leftLeg",
		"rightLeg",
		"crouch",
		"tremble",
		"lunge",
		"rise",
		"spin",
		"headPitch",
		"headYaw",
		"headRoll",
	}
do
	POSE_CHANNELS[name] = true
end
local EASE_NAMES = { linear = true, ["in"] = true, out = true, inOut = true, snap = true, back = true, hold = true }

local function mockView(position: Vector3)
	local hips = roblox.CFrame.new(position - Vector3.new(0, 0.5, 0))
	return {
		part = { Position = position, Size = Vector3.new(2, 5, 1), Parent = {} },
		figure = {
			isModel = false,
			anchors = {
				hips = hips,
				head = hips * roblox.CFrame.new(0, 2, 0),
				leftHand = hips * roblox.CFrame.new(-1, 0, -0.5),
				rightHand = hips * roblox.CFrame.new(1, 0, -0.5),
			},
		},
		yaw = 0,
		starLevel = 1,
	}
end

-- One of each event an ability can produce, from the caster (1) on two enemies (2, 3).
local FAKE_EVENTS = {
	{ kind = "Dash", unit = 1, column = 4, row = 5 },
	{ kind = "Pull", unit = 1, target = 2 },
	{ kind = "Area", unit = 1, column = 4, row = 6, radius = 2, shape = nil },
	{
		kind = "Area",
		unit = 1,
		column = 4,
		row = 6,
		shape = "LINE",
		cells = { { 4, 6 }, { 4, 7 } },
		fromColumn = 4,
		fromRow = 4,
	},
	{ kind = "AreaStun", unit = 1, column = 4, row = 6, radius = 2 },
	{ kind = "Damage", unit = 1, target = 2, damage = 100 },
	{ kind = "Damage", unit = 1, target = 3, damage = 100 },
	{ kind = "Stun", unit = 1, target = 2, duration = 1 },
	{ kind = "Knockback", unit = 1, target = 2, column = 4, row = 7 },
	{ kind = "Bounce", unit = 1, from = 2, target = 3 },
	{ kind = "Shield", unit = 1, target = 1, shield = 100 },
	{ kind = "Heal", unit = 1, target = 3, amount = 50 },
	{ kind = "Buff", unit = 1, target = 1, stat = "AD", percent = 10 },
	{ kind = "Dot", unit = 1, target = 2, status = "BURN" },
	{ kind = "Summon", unit = 1, summon = 4, column = 3, row = 5 },
	{ kind = "Form", unit = 1, formIndex = 2, form = "Form" },
	{ kind = "Copy", unit = 1, target = 2, ability = "x" },
}
-- The same events, last first: hits before areas (handlers that depend on order take both paths).
local REVERSED_EVENTS = {}
for i = #FAKE_EVENTS, 1, -1 do
	table.insert(REVERSED_EVENTS, FAKE_EVENTS[i])
end
local CIRCLE_EVENTS = {}
for _, event in FAKE_EVENTS do
	if event.shape ~= "LINE" then
		table.insert(CIRCLE_EVENTS, event)
	end
end

-- Problems with a unit's ultimate (nil, "NOT STARTED" if it has none).
local function checkUltimate(unitType: string, problems: { string }): string
	local config = UltimateConfig.units[unitType]
	if not config then
		table.insert(problems, "no UltimateConfig entry")
		return "-"
	end
	if config.tier ~= UnitConfig[unitType].cost then
		table.insert(
			problems,
			string.format("ultimate tier %d is not its cost %d", config.tier, UnitConfig[unitType].cost)
		)
	end
	if not (config.preroll > 0 and config.linger > 0) then
		table.insert(problems, "ultimate preroll and linger must be > 0")
	end
	local ok, def = pcall(Ultimates.of, unitType)
	if not ok then
		table.insert(problems, "ultimate failed to load: " .. tostring(def))
		return "BROKEN"
	end
	if not def then
		-- The registry warns and leaves out a module that fails to load: that is a problem here.
		if PATHS["src/client/Ultimates/" .. unitType] then
			table.insert(problems, "ultimate module exists but failed to load (see the warning above)")
			return "BROKEN"
		end
		return "NOT STARTED"
	end
	if config.look == "" then
		table.insert(problems, "ultimate has no `look` note")
	end
	local function fail(what: string, err)
		table.insert(problems, "ultimate " .. what .. ": " .. tostring(err))
	end

	-- Pose keys: known channels, ordered keys in the run's span, known eases; evaluate across it.
	local function checkTrack(track, relative: boolean?)
		for channel, keys in track do
			if not POSE_CHANNELS[channel] then
				fail("pose", "unknown channel " .. tostring(channel))
			end
			for i, key in keys do
				if type(key[1]) ~= "number" or type(key[2]) ~= "number" then
					fail("pose", channel .. " key " .. i .. " is not { t, value }")
				elseif i > 1 and key[1] < keys[i - 1][1] then
					fail("pose", channel .. " keys out of order at " .. i)
				elseif not relative and (key[1] < -config.preroll - 1e-6 or key[1] > config.linger + 1e-6) then
					fail(
						"pose",
						string.format(
							"%s key at %.2f is outside -%.2f..%.2f",
							channel,
							key[1],
							config.preroll,
							config.linger
						)
					)
				end
				if key[3] and not EASE_NAMES[key[3]] then
					fail("pose", channel .. " unknown ease " .. tostring(key[3]))
				end
			end
		end
		do
			local t = -config.preroll
			while t <= config.linger do
				local pose =
					{ bob = 0, lean = 0, fall = 0, leftArm = 0, rightArm = 0, leftLeg = 0, rightLeg = 0, stride = 0 }
				local evaluated, lunge, rise = pcall(UnitMotion.ultimatePose, pose, track, t, 1, { 0, 0 }, t)
				if not evaluated then
					fail("pose", lunge)
					break
				end
				for key, value in pose do
					if not finite(value) then
						fail("pose", key .. " not finite at " .. t)
					end
				end
				if not (finite(lunge) and finite(rise)) then
					fail("pose", "lunge or rise not finite")
				end
				t += 0.05
			end
		end
	end
	if def.pose then
		checkTrack(def.pose)
	end

	-- A dry run: beats in order, scheduled beats, the release, then every kind of event. Each runs
	-- with the caster's texture context (as Cinematic does), and its texture requests are counted.
	local maxPeak, total = 0, 0
	local unitEntry = AbilityFxConfig.units[unitType]
	local vfxContext = {
		unit = unitType,
		element = unitEntry and unitEntry.element or AbilityFxConfig.default,
		color = unitEntry and unitEntry.primary,
	}
	table.clear(textureLog)
	-- Three times: a cast with every event kind, one with a circle hit and no line, and one in reverse order (units whose
	-- choreography follows the cast take both branches).
	for _, castEvents in { FAKE_EVENTS, CIRCLE_EVENTS, REVERSED_EVENTS } do
		table.clear(recorded)
		recordGroup = "cast"
		table.clear(stubErrors)
		local entry = AbilityFxConfig.units[unitType]
		local views =
			{ mockView(Vector3.new(0, 2.5, 0)), mockView(Vector3.new(0, 2.5, -9)), mockView(Vector3.new(3, 2.5, -10)) }
		dryClock = -config.preroll
		local pending = {}
		local run = {
			unitIndex = 1,
			unitType = unitType,
			view = views[1],
			style = {
				element = entry and entry.element or "magic",
				def = AbilityFxConfig.elements[entry and entry.element or "magic"],
				primary = entry and entry.primary or roblox.Color3.new(1, 1, 1),
				secondary = entry and entry.secondary or roblox.Color3.new(1, 1, 1),
			},
			tier = config.tier,
			config = config,
			def = def,
			context = {
				views = views,
				toWorld = function(column, row)
					return Vector3.new(column * 3, 0, -row * 3)
				end,
				now = function()
					return dryClock
				end,
				ticksPerSecond = 10,
				events = castEvents,
			},
			startAt = -config.preroll,
			releaseAt = 0,
			endAt = config.linger,
			k = 1,
			castIndex = 1,
			cast = castEvents,
			reduced = false,
			pending = pending,
			memo = {},
		}
		local methods = {
			time = function(_, t)
				return t
			end,
			span = function(_, _t, seconds)
				return seconds
			end,
			at = function(_, t, fn)
				assert(type(t) == "number" and type(fn) == "function", "at(t, fn) expects a time and a function")
				table.insert(pending, { at = t, run = fn })
			end,
			now = function()
				return dryClock
			end,
			designTime = function()
				return dryClock
			end,
			alive = function()
				return true
			end,
			chest = function()
				return Vector3.new(0, 3, 0)
			end,
			ground = function()
				return Vector3.new(0, 0, 0)
			end,
			head = function()
				return Vector3.new(0, 4.5, 0)
			end,
			hand = function(_, side)
				assert(side == "left" or side == "right", "hand(side): left or right")
				return Vector3.new(if side == "left" then -1 else 1, 2.5, -0.6)
			end,
			forward = function()
				return Vector3.new(0, 0, -1)
			end,
			scale = function()
				return 1
			end,
			find = function(_, ...)
				local wanted = { ... }
				for _, event in castEvents do
					if table.find(wanted, event.kind) then
						return event
					end
				end
				return nil
			end,
			area = function()
				return Vector3.new(12, 0, -18), 7.5
			end,
			targets = function()
				return { views[2], views[3] }
			end,
			target = function()
				return views[2]
			end,
			camera = function(_, from, to, cue)
				assert(type(from) == "number" and type(to) == "number" and from <= to, "camera(from, to): from <= to")
				assert(type(cue) == "table", "camera cue table")
			end,
			shake = function(_, amount)
				assert(type(amount) == "number", "shake(amount)")
			end,
			sound = function(_, role)
				assert(UltimateConfig.sounds[role], "unknown sound role " .. tostring(role))
			end,
			pose = function(_, track)
				checkTrack(track, true)
			end,
			summons = function()
				return { views[3] }
			end,
			face = function() end,
			hitStop = function(_, _view, seconds)
				assert(type(seconds) == "number" and seconds >= 0, "hitStop(view, seconds)")
			end,
		}
		for name in RUN_METHODS do
			if not methods[name] then
				fail("audit", "the stand-in run lacks Cinematic method " .. name)
			end
		end
		setmetatable(run, {
			__index = function(_, key)
				local method = methods[key]
				if method and RUN_METHODS[key] then
					return method
				end
				error("run has no method or field " .. tostring(key), 2)
			end,
		})
		-- Per-cast pose keys: picked from every event kind, and from a cast with only a circle hit.
		if def.poseFor then
			for _, cast in { castEvents, { castEvents[3], castEvents[6] } } do
				run.cast = cast
				local picked, track = pcall(def.poseFor, run)
				if not picked then
					fail("poseFor", track)
				elseif type(track) ~= "table" then
					fail("poseFor", "returned no pose keys")
				else
					checkTrack(track)
				end
			end
			run.cast = castEvents
		end
		local beats = table.clone(def.beats or {})
		table.sort(beats, function(a, b)
			return a.at < b.at
		end)
		for _, beat in beats do
			if type(beat.at) ~= "number" or type(beat.run) ~= "function" then
				fail("beat", "needs { at = number, run = function }")
			elseif beat.at < -config.preroll - 1e-6 or beat.at > config.linger + 1e-6 then
				fail("beat", string.format("at %.2f is outside -%.2f..%.2f", beat.at, config.preroll, config.linger))
			else
				table.insert(pending, { at = beat.at, run = beat.run })
			end
		end
		local released = false
		local guard = 0
		while (#pending > 0 or not released) and guard < 500 do
			guard += 1
			table.sort(pending, function(a, b)
				return a.at < b.at
			end)
			local nextBeat = pending[1]
			if not released and (not nextBeat or nextBeat.at >= 0) then
				released = true
				dryClock = 0
				if def.release then
					local okRelease, err = pcall(Vfx.within, vfxContext, def.release, run)
					if not okRelease then
						fail("release", err)
					end
				end
				if def.event then
					-- Each event at the time its effect really lands: the unit's ability's `delay`s,
					-- taken in order per event kind (delayed hits do not pile onto the release).
					local delays = {}
					for _, effect in UnitConfig[unitType].ability.effects or {} do
						for _, produced in EVENTS[effect.type] or {} do
							delays[produced] = delays[produced] or {}
							table.insert(delays[produced], effect.delay or 0)
						end
					end
					for _, event in castEvents do
						local queue = delays[event.kind]
						dryClock = if queue and #queue > 0 then table.remove(queue, 1) else 0
						local okEvent, err = pcall(Vfx.within, vfxContext, def.event, run, event)
						if not okEvent then
							fail("event " .. event.kind, err)
						end
					end
					dryClock = 0
				end
			else
				table.remove(pending, 1)
				dryClock = nextBeat.at
				local okBeat, err = pcall(Vfx.within, vfxContext, nextBeat.run, run)
				if not okBeat then
					fail(string.format("beat at %.2f", nextBeat.at), err)
				end
			end
		end
		-- A form change outside a cast (`shift`), and the beats it schedules.
		if def.shift then
			dryClock = 0
			recordGroup = "shift"
			local okShift, err =
				pcall(Vfx.within, vfxContext, def.shift, run, { kind = "Form", unit = 1, formIndex = 2, form = "Form" })
			if not okShift then
				fail("shift", err)
			end
			table.sort(pending, function(a, b)
				return a.at < b.at
			end)
			while #pending > 0 do
				local beat = table.remove(pending, 1)
				dryClock = beat.at
				local okBeat, beatErr = pcall(Vfx.within, vfxContext, beat.run, run)
				if not okBeat then
					fail(string.format("shift beat at %.2f", beat.at), beatErr)
				end
			end
		end
		-- Every part drawn, stepped through its life.
		for _, shape in recorded do
			for _, u in { 0, 0.5, 1 } do
				local okStep, err = pcall(shape.step, checkingPart(), u)
				if not okStep then
					fail("part step (" .. shape.shape .. ")", err)
					break
				end
			end
		end
		for _, err in stubErrors do
			fail("effect", err)
		end
		-- The busiest moment: parts alive at once.
		local peak = 0
		for _, a in recorded do
			local alive = 0
			for _, b in recorded do
				if b.group == a.group and b.startAt <= a.startAt and b.endAt > a.startAt then
					alive += 1
				end
			end
			peak = math.max(peak, alive)
		end
		if peak > PEAK_LIMIT[config.tier] then
			fail(
				"budget",
				string.format("%d parts alive at once (tier %d limit %d)", peak, config.tier, PEAK_LIMIT[config.tier])
			)
		end
		maxPeak = math.max(maxPeak, peak)
		total += #recorded
	end
	-- Texture requests: how many drew with a picked texture (the rest keep the neon look).
	local textured = 0
	for _, request in textureLog do
		if request.key then
			textured += 1
		end
	end
	if #textureLog == 0 then
		table.insert(problems, "ultimate draws nothing through the texture system (VfxConfig)")
	end
	return string.format("DONE %d/%d tex %d/%d", maxPeak, total, textured, #textureLog)
end
-- Units ----------------------------------------------------------------------------------------------

local ORDER = { "Heroes", "Crew", "Shinobi", "Titans", "Arcane", "Cursed", "Spirit", "Corps", "Hunters" }
local byFaction = {}
for unitType, character in UnitConfig do
	byFaction[character.origin] = byFaction[character.origin] or {}
	table.insert(byFaction[character.origin], unitType)
end

local failed = 0
local count = 0
local ultimates = { done = 0, missing = 0 }
-- `lune run scripts/audit-units all`: a unit without an ultimate is a problem too.
local requireAll = process.args[1] == "all"
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
				local specs = build("avatar weapons", problems, function()
					return LookKit.weaponSpecs(weapons, body, HEIGHT)
				end)
				-- Quick-draw weapons: their parts (and only theirs) are marked drawn.
				local marked, wanted = 0, 0
				for _, spec in specs do
					marked += if spec.drawn then 1 else 0
				end
				for _, w in weapons do
					if w.drawn then
						wanted += #LookKit.weaponSpecs({ w }, body, HEIGHT)
					end
				end
				if marked ~= wanted then
					table.insert(problems, string.format("drawn weapon parts: %d marked, %d expected", marked, wanted))
				end
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
			if i > 1 and (form.range and form.range ~= character.range or AnimationConfig.formStyles[form.name]) then
				local look = if formLook then { weapons = formLook.weapons } else { weapons = weapons }
				table.insert(
					formStyles,
					form.name .. ":" .. styleOf(unitType, form.range or character.range, look, form.name)
				)
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
		-- Every style chosen exists, with its projectile look for ranged ones.
		for _, name in { style, table.unpack(formStyles) } do
			name = string.match(name, "[%w]+$")
			local motion = AnimationConfig.styles[name]
			if not motion then
				table.insert(problems, "unknown attack style " .. name)
			elseif motion.projectile and not AnimationConfig.projectiles[motion.projectile] then
				table.insert(problems, "style " .. name .. ": unknown projectile " .. motion.projectile)
			end
		end
		if #formStyles > 0 then
			style ..= " (" .. table.concat(formStyles, ", ") .. ")"
		end
		local ultimate = checkUltimate(unitType, problems)
		ultimates[ultimate == "NOT STARTED" and "missing" or "done"] += 1
		if ultimate == "NOT STARTED" and requireAll then
			table.insert(problems, "no ultimate yet")
		end

		local line = string.format(
			"%-18s ult T%d %-24s %-6s r%d %-14s %-9s wpn %s%s%s",
			unitType,
			UltimateConfig.units[unitType] and UltimateConfig.units[unitType].tier or 0,
			ultimate,
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

-- Effect textures (VfxConfig) ----------------------------------------------------------------------------
-- Every usage the effect code names exists; how each resolves by default (a texture, or the neon
-- fallback and why); each variant names a real pick; what each unit draws differently; and which
-- picks no effect ever draws with.

print("\n== Effect textures (VfxConfig, VfxPicks generated " .. tostring(shared("VfxPicks").generated) .. ")")
local vfxFailed = 0
local function vfxProblem(text: string)
	print("PROBLEM vfx: " .. text)
	vfxFailed += 1
end

local function isPick(key: string): boolean
	local role, rank = string.match(key, "^(%a+):(%d+)$")
	for _, pick in (role and VfxConfig.picks[role]) or {} do
		if pick.rank == tonumber(rank) then
			return true
		end
	end
	return false
end

-- Usages named in the effect code.
local named: { [string]: string } = {}
for _, file in { "ImpactEffects", "FxKit", "UltimateKit", "CombatEffects", "CombatFx", "AbilityFx", "Cinematic" } do
	local text = source(file)
	for _, pattern in
		{
			'textured%("(%a+)"',
			'Vfx%.texture%("(%a+)"',
			'Vfx%.texture, "(%a+)"',
			'usage = "(%a+)"',
			'usage or "(%a+)"',
			'ballDuration, "(%a+)"',
			'then "(%a+Flash)"',
		}
	do
		for usage in string.gmatch(text, pattern) do
			named[usage] = named[usage] or file
		end
	end
end
for usage, file in named do
	if not VfxConfig.uses[usage] then
		vfxProblem(file .. " names usage " .. usage .. ", which VfxConfig.uses lacks")
	end
end

-- Variants name real picks, units and elements.
for unitType, roles in VfxConfig.units do
	if not UnitConfig[unitType] then
		vfxProblem("units." .. unitType .. ": no such unit")
	end
	for role, key in roles do
		if not isPick(key) then
			vfxProblem(string.format("units.%s.%s = %q: no such pick", unitType, role, key))
		end
	end
end
for element, roles in VfxConfig.elements do
	if not AbilityFxConfig.elements[element] then
		vfxProblem("elements." .. element .. ": no such element (AbilityFxConfig.elements)")
	end
	for role, key in roles do
		if not isPick(key) then
			vfxProblem(string.format("elements.%s.%s = %q: no such pick", element, role, key))
		end
	end
end

-- Each usage by default (no unit), and every unit's and color's choice (to find unused picks).
local usages = {}
for usage in VfxConfig.uses do
	table.insert(usages, usage)
end
table.sort(usages)
local function why(trace): string
	local parts = {}
	for _, step in trace do
		table.insert(parts, step.key .. ": " .. step.reason)
	end
	return table.concat(parts, "; ")
end
print("usage         roles                 default")
for _, usage in usages do
	local texture, trace = VfxResolve.resolve(usage, nil)
	if texture then
		chosen[texture.key] = true
	end
	print(
		string.format(
			"%-13s %-21s %s%s",
			usage,
			table.concat(VfxConfig.uses[usage].roles, ","),
			if texture then texture.key .. " (" .. texture.mode .. ")" else "NEON FALLBACK (" .. why(trace) .. ")",
			if named[usage] then "" else "  [not drawn by any effect]"
		)
	)
end
local colors = {}
for _, color in AnimationConfig.factionColors do
	table.insert(colors, color)
end
for _, damage in { "PHYSICAL", "MAGIC", "TRUE" } do
	table.insert(colors, AnimationConfig.impact[damage].color)
	table.insert(colors, AnimationConfig.impact[damage].core)
end
table.insert(colors, AnimationConfig.hit.critFlashColor)
for _, usage in usages do
	for _, color in colors do
		local texture = VfxResolve.resolve(usage, { color = color })
		if texture then
			chosen[texture.key] = true
		end
	end
end
print("unit variants (where a unit draws differently from the default):")
local unitIds = {}
for unitType in UnitConfig do
	table.insert(unitIds, unitType)
end
table.sort(unitIds)
for _, unitType in unitIds do
	local entry = AbilityFxConfig.units[unitType]
	local element = if entry then entry.element else AbilityFxConfig.default
	local differs = {}
	for _, usage in usages do
		local base = VfxResolve.resolve(usage, nil)
		local seen = {}
		for _, color in { entry and entry.primary, entry and entry.secondary } do
			local texture = VfxResolve.resolve(usage, { unit = unitType, element = element, color = color })
			if texture then
				chosen[texture.key] = true
			end
			local key = if texture then texture.key else "neon"
			if key ~= (if base then base.key else "neon") and not seen[key] then
				seen[key] = true
				table.insert(differs, usage .. "=" .. key)
			end
		end
	end
	if #differs > 0 then
		print(string.format("  %-18s %-9s %s", unitType, element, table.concat(differs, " ")))
	end
end

-- Picks no effect draws with, and why.
print("unused picks:")
local unused = 0
for _, role in VfxConfig.roles do
	for _, pick in VfxConfig.picks[role] or {} do
		local key = role .. ":" .. pick.rank
		if not chosen[key] then
			unused += 1
			local reason
			if pick.kind == "model" and not pick.textures then
				reason = "model pack, needs Studio (scripts/studio/export-vfx.luau)"
			elseif pick.kind == "image" and not pick.image then
				reason = pick.pending or "no image id"
			else
				local traits = VfxConfig.traits[pick.name] or VfxConfig.traits[pick.image or 0]
				reason = if traits and traits.unusable
					then traits.unusable
					else "never the first fitting choice (assign it in VfxConfig `units` or `elements`)"
			end
			print(string.format("  %-13s %s  %s", key, pick.name or "?", reason))
		end
	end
end
if unused == 0 then
	print("  none")
end
-- Every texture skin shown, updated, hidden and recycled on the real effect modules
-- (scripts/lib/vfx-skins.luau; also lune run scripts/vfx-skins-test).
local skinProblems, skinSummary = require("./lib/vfx-skins")()
for _, text in skinProblems do
	vfxProblem("skins: " .. text)
end
print(string.format("skins: %s, %d problems", skinSummary, #skinProblems))
if vfxFailed > 0 then
	failed += 1
end
table.sort(noFallback)
print(string.format("\nnote: %d avatars fall back to the placeholder: %s", #noFallback, table.concat(noFallback, ", ")))
print(string.format("ultimates: %d done, %d not started", ultimates.done, ultimates.missing))
print(string.format("%d units, %d with problems", count, failed))
process.exit(if failed > 0 then 1 else 0)
