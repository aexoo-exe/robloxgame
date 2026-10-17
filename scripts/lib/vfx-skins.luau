-- Headless test of the effect texture skins: loads the real ImpactEffects and CombatEffects with
-- stand-in services and drives every skin type (neon, plane, billboard, beam, particle sprite on a
-- plane and on a billboard, particles, flipbooks) through show -> update -> hide -> recycle, in every
-- order on the same pooled part, plus clear(), the update guard, rings, flash balls, bursts and
-- projectile skins. Instances are real Lune roblox instances behind a thin wrapper: properties are
-- checked as Roblox checks them (an unknown member errors, like "Clear is not a valid member of
-- ImageLabel"), and only the engine methods Lune lacks (ParticleEmitter:Emit/Clear, Trail:Clear) are
-- stood in for. Used by scripts/audit-units.luau and scripts/vfx-skins-test.luau.
-- Returns run(): problems ({ string }) and a summary line.

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")

local CFrame = roblox.CFrame
local Color3 = roblox.Color3
local Vector3 = roblox.Vector3

-- Instance wrapper ---------------------------------------------------------------------------------

-- Engine methods Lune's instances do not implement, by class: stood in for (they do nothing here).
local ENGINE_METHODS = {
	ParticleEmitter = { Emit = true, Clear = true },
	Trail = { Clear = true },
}
-- Methods every instance has that Lune implements.
local COMMON = {
	IsA = true,
	Destroy = true,
	FindFirstChild = true,
	FindFirstChildOfClass = true,
	GetChildren = true,
	GetDescendants = true,
	ClearAllChildren = true,
	SetAttribute = true,
	GetAttribute = true,
}

local wrappers = setmetatable({}, { __mode = "k" })
local Wrapper = {}

local function unwrap(value: any): any
	if type(value) == "table" and rawget(value, "__real") then
		return rawget(value, "__real")
	end
	return value
end

local function wrap(value: any): any
	if typeof(value) ~= "Instance" then
		return value
	end
	local found = wrappers[value]
	if found then
		return found
	end
	local made = setmetatable({ __real = value }, Wrapper)
	wrappers[value] = made
	return made
end

Wrapper.__index = function(self, key)
	local real = rawget(self, "__real")
	local engine = ENGINE_METHODS[real.ClassName]
	if engine and engine[key] then
		return function()
			return nil
		end
	end
	if COMMON[key] then
		return function(_, ...)
			local args = table.pack(...)
			for i = 1, args.n do
				args[i] = unwrap(args[i])
			end
			local result = real[key](real, table.unpack(args, 1, args.n))
			if type(result) == "table" then
				local out = {}
				for i, item in result do
					out[i] = wrap(item)
				end
				return out
			end
			return wrap(result)
		end
	end
	-- A part's Position is derived from its CFrame by the engine (Lune stores only the CFrame).
	if key == "Position" and real:IsA("BasePart") then
		return real.CFrame.Position
	end
	return wrap(real[key]) -- an unknown member errors, as in Roblox
end
Wrapper.__newindex = function(self, key, value)
	local real = rawget(self, "__real")
	if key == "Position" and real:IsA("BasePart") then
		real.CFrame = CFrame.new(value) * real.CFrame.Rotation
		return
	end
	real[key] = unwrap(value)
end

-- Module loader (its own cache: the audit stubs ImpactEffects for its dry runs) ---------------------

local ALIASES = { ["RS/Shared"] = "src/shared" }
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

local function run(): ({ string }, string)
	index("src")
	local problems: { string } = {}
	local warnings: { string } = {}
	local function problem(text: string)
		table.insert(problems, text)
	end

	local Node = {}
	local function node(path: string)
		return setmetatable({ __path = ALIASES[path] or path }, Node)
	end
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
				return if exists(child) then node(child) else nil
			end
		end
		local child = path .. "/" .. key
		assert(exists(child), "missing " .. child)
		return node(child)
	end

	-- Stand-in services.
	local frame: (() -> ())? = nil
	local services = {
		RunService = {
			IsStudio = function()
				return true
			end,
			RenderStepped = {
				Connect = function(_, fn)
					frame = fn
					return { Disconnect = function() end }
				end,
			},
		},
		UserInputService = { TouchEnabled = false, KeyboardEnabled = true },
		Players = { LocalPlayer = nil },
	}
	local game = {
		GetService = function(_, name)
			if name == "ReplicatedStorage" then
				return node("RS")
			end
			return services[name] or error("no stand-in for service " .. name)
		end,
	}
	local workspace = wrap(roblox.Instance.new("Folder"))

	-- Vfx stand-in: textures are forced by the test.
	local forced: { [string]: any } = {} -- mode -> texture, or nothing (neon)
	local VfxResolve -- set after loading
	local VfxStub = {
		texture = function(_usage, _color, mode)
			return forced[mode or "particle"]
		end,
		tint = function(texture, color)
			return VfxResolve.tint(texture, color)
		end,
		resetCounts = function() end,
		context = function()
			return nil
		end,
		within = function(_, fn, ...)
			return fn(...)
		end,
	}

	local loaded = { ["src/client/Vfx"] = VfxStub }
	local globals = getfenv(1)
	local function load(path: string)
		if loaded[path] ~= nil then
			return loaded[path]
		end
		local file = if fs.isFile(path .. ".luau") then path .. ".luau" else path .. "/init.luau"
		local env = setmetatable({
			script = node(path),
			game = game,
			workspace = workspace,
			Instance = {
				new = function(className: string)
					return wrap(roblox.Instance.new(className))
				end,
			},
			warn = function(...)
				local parts = {}
				for _, item in { ... } do
					table.insert(parts, tostring(item))
				end
				table.insert(warnings, table.concat(parts, " "))
			end,
			Color3 = roblox.Color3,
			Vector3 = roblox.Vector3,
			Vector2 = roblox.Vector2,
			CFrame = roblox.CFrame,
			Enum = roblox.Enum,
			NumberRange = roblox.NumberRange,
			NumberSequence = roblox.NumberSequence,
			NumberSequenceKeypoint = roblox.NumberSequenceKeypoint,
			ColorSequence = roblox.ColorSequence,
			ColorSequenceKeypoint = roblox.ColorSequenceKeypoint,
			UDim2 = roblox.UDim2,
			UDim = roblox.UDim,
		}, { __index = globals })
		env.require = function(target)
			return load(rawget(target, "__path"))
		end
		local chunk = luau.load(fs.readFile(file), { debugName = file, environment = env })
		loaded[path] = chunk()
		return loaded[path]
	end

	VfxResolve = load("src/shared/VfxResolve")
	local ImpactEffects = load("src/client/ImpactEffects")
	local CombatEffects = load("src/client/CombatEffects")

	-- Textures of every skin type.
	local function texture(mode: string, extra: any?): any
		local t = {
			key = "test:" .. mode,
			role = "test",
			id = 1,
			image = "rbxassetid://1",
			mode = mode,
			blend = "alpha",
			tint = true,
			tintShare = 1,
			flipbook = nil,
			brightness = 1.5,
			speed = 0,
			width = 1,
			upright = false,
			sprite = false,
		}
		for key, value in extra or {} do
			t[key] = value
		end
		return t
	end
	local SKINS = {
		{ name = "neon", texture = nil },
		{ name = "plane", texture = texture("plane") },
		{ name = "billboard", texture = texture("billboard") },
		{ name = "beam", texture = texture("beam", { blend = "additive" }) },
		{ name = "sprite billboard", texture = texture("billboard", { sprite = true, blend = "additive" }) },
		{
			name = "sprite plane flipbook",
			texture = texture("plane", { sprite = true, flipbook = { layout = "4x4", mode = "OneShot" } }),
		},
		{ name = "untinted billboard", texture = texture("billboard", { tint = false, tintShare = 0 }) },
	}

	local now = 0
	ImpactEffects.setClock(function()
		return now
	end)
	local function tick(seconds: number, what: string)
		now += seconds
		if frame then
			local ok, err = pcall(frame)
			if not ok then
				problem(what .. ": the update errored: " .. tostring(err))
			end
		end
	end
	local function step(part, progress)
		part.Size = Vector3.new(2, 0.1, 2) * (1 + progress)
		part.CFrame = CFrame.new(0, 1, 0)
		part.Transparency = progress
	end

	-- Every skin after every other on the same pooled part, for each part shape.
	local cycles = 0
	for _, shape in { "Block", "Ball", "Cylinder" } do
		for _, first in SKINS do
			for _, second in SKINS do
				for _, skin in { first, second } do
					ImpactEffects.shape(shape, Color3.new(1, 0.5, 0), 0.2, step, nil, nil, skin.texture)
					local what = string.format("%s %s after %s", shape, skin.name, first.name)
					tick(0.05, what) -- shown
					tick(0.1, what) -- updated
					tick(0.2, what) -- hidden and recycled
					cycles += 1
				end
			end
		end
	end
	-- Cleared mid-life, then reused.
	for _, skin in SKINS do
		ImpactEffects.shape("Ball", Color3.new(1, 1, 1), 1, step, nil, nil, skin.texture)
		tick(0.05, "clear: " .. skin.name)
		local ok, err = pcall(ImpactEffects.clear)
		if not ok then
			problem("clear() with a " .. skin.name .. " shape: " .. tostring(err))
		end
	end
	-- Rings, flash balls, bursts, delayed calls.
	for _, skin in SKINS do
		forced = {}
		if skin.texture then
			forced[skin.texture.mode] = skin.texture
			forced.particle = texture("particle", { blend = "additive", flipbook = skin.texture.flipbook })
		end
		local ok, err = pcall(function()
			ImpactEffects.ring(Vector3.zero, Color3.new(0, 1, 1), 3, 0.2)
			ImpactEffects.ball(Vector3.zero, Color3.new(1, 1, 1), 1, 0.1)
			ImpactEffects.ball(Vector3.zero, Color3.new(1, 1, 1), 1, 0.1, "critFlash", Color3.new(1, 0.5, 0))
			for _, kind in { "spark", "puff", "flame", "smoke", "glow", "shock", "explosion", "slash", "mote" } do
				ImpactEffects.burst(kind, Vector3.zero, Vector3.yAxis, {
					color = Color3.new(1, 0, 0),
					count = 3,
					size = 1,
					speed = { 1, 2 },
					lifetime = { 0.1, 0.2 },
				})
			end
			ImpactEffects.later(0.05, function() end)
		end)
		if not ok then
			problem("rings, balls and bursts with " .. skin.name .. ": " .. tostring(err))
		end
		tick(0.1, "rings and balls: " .. skin.name)
		tick(0.4, "rings and balls: " .. skin.name)
	end
	forced = {}

	-- The update guard: a failing effect is dropped and reported once; the next one still works.
	local before = #warnings
	for _ = 1, 3 do
		ImpactEffects.shape("Block", Color3.new(1, 1, 1), 0.2, function()
			error("deliberate test failure")
		end, nil, nil, texture("plane"))
		tick(0.05, "guard")
		tick(0.3, "guard")
	end
	local guardWarnings = #warnings - before
	if guardWarnings ~= 1 then
		problem(string.format("a failing effect should warn once per kind; it warned %d times", guardWarnings))
	end
	table.remove(warnings, before + 1)
	ImpactEffects.shape("Block", Color3.new(1, 1, 1), 0.2, step, nil, nil, texture("plane"))
	tick(0.05, "after the guard")
	tick(0.3, "after the guard")

	-- Projectile skins, each after each on the same pooled shot.
	local shooter = { part = wrap(roblox.Instance.new("Part")), base = Vector3.zero }
	local target = { part = wrap(roblox.Instance.new("Part")), base = Vector3.zero }
	target.part.Position = Vector3.new(0, 0, -10)
	target.part.Parent = workspace
	local SHOTS = {
		{ name = "neon orb", look = "orb", forced = {} },
		{ name = "halo", look = "orb", forced = { billboard = texture("billboard") } },
		{
			name = "glow",
			look = "orb",
			forced = { billboard = texture("billboard", { sprite = true, blend = "additive" }) },
		},
		{ name = "neon wave", look = "wave", forced = {} },
		{ name = "blade", look = "wave", forced = { plane = texture("plane") } },
		{ name = "sprite blade (stays neon)", look = "wave", forced = { plane = texture("plane", { sprite = true }) } },
	}
	local shotClock = 0
	CombatEffects.setClock(function()
		return shotClock
	end)
	for _, first in SHOTS do
		for _, second in SHOTS do
			for _, shot in { first, second } do
				forced = shot.forced
				local ok, err = pcall(function()
					CombatEffects.projectile(shooter, target, shotClock + 0.3, Color3.new(0.5, 0.8, 1), {
						look = shot.look,
						launchAt = shotClock + 0.05,
					})
					for _ = 1, 4 do
						shotClock += 0.1
						CombatEffects.update(shotClock)
					end
				end)
				if not ok then
					problem(string.format("projectile %s after %s: %s", shot.name, first.name, tostring(err)))
				end
				cycles += 1
			end
		end
	end
	forced = {}
	pcall(CombatEffects.clear)

	for _, text in warnings do
		problem("unexpected warning: " .. text)
	end
	return problems,
		string.format(
			"%d show/update/hide/recycle cycles over %d shape skins and %d projectile skins",
			cycles,
			#SKINS,
			#SHOTS
		)
end

return run
