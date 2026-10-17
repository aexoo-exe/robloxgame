-- Chooses the texture an effect draws with (VfxConfig): for a usage (VfxConfig.uses) and the unit
-- drawing it (its id, element and color), the first candidate that is usable, fits the way the
-- effect draws (particle, plane, billboard, beam, screen), takes the color, and (on the client) has
-- loaded. Candidates in order: the unit's variant, its element's variant, the usage's `first`
-- picks, then the role's ranks. A usage switched off (`on = false`) draws neon.
-- Pure: no instances or services, so the audit (scripts/audit-units) runs the same choice.

local VfxConfig = require(script.Parent:WaitForChild("VfxConfig"))

local VfxResolve = {}

export type Flipbook = { layout: string, mode: string, fps: number? }

export type Texture = {
	key: string, -- "<role>:<rank>"
	role: string,
	id: number, -- the image's asset id
	image: string, -- "rbxassetid://<id>"
	mode: string, -- how it draws: "particle", "plane", "billboard", "beam" or "screen"
	blend: string, -- "alpha" or "additive"
	tint: boolean, -- tinted by the effect's color at all (tintShare > 0)
	tintShare: number, -- how far toward the effect's color it is tinted (0: its own colors, 1: full)
	flipbook: Flipbook?,
	brightness: number, -- planes and billboards
	speed: number, -- beam texture scroll
	width: number, -- a beam's width, times the neon bar's
	upright: boolean, -- a billboard keeps the image upright (no random turn)
	-- a plane or billboard drawn as one additive particle sprite (a black background or a flipbook)
	sprite: boolean,
	scale: number, -- particles, sprites and billboards drawn this many times bigger (traits and usage `scale`)
	tile: number?, -- a beam repeats the texture every this many studs (traits `tile`); nil: stretched
	light: number?, -- LightEmission for beams and sprites (usage, else traits `light`); nil: by blend
	shade: Color3?, -- always drawn in this color (traits `shade`)
	opacity: number, -- the most opaque it is ever drawn (usage `opacity`; 1: as its shape says)
}

export type Context = { unit: string?, element: string?, color: Color3? }

-- One step of a choice, for reports: the candidate and why it was taken or passed over.
export type Trace = { key: string, reason: string }

local function hsv(color: Color3): (number, number, number)
	local r, g, b = color.R, color.G, color.B
	local max, min = math.max(r, g, b), math.min(r, g, b)
	local delta = max - min
	local h = 0
	if delta > 1e-6 then
		if max == r then
			h = ((g - b) / delta) % 6
		elseif max == g then
			h = (b - r) / delta + 2
		else
			h = (r - g) / delta + 4
		end
		h /= 6
	end
	return h, if max > 0 then delta / max else 0, max
end

-- Does a baked texture's own color suit `color`?
local function hueFits(baked: Color3, color: Color3): boolean
	local config = VfxConfig.hue
	local h1, s1 = hsv(color)
	local h2, s2 = hsv(baked)
	if s1 < config.minSaturation or s2 < config.minSaturation then
		return s1 < config.minSaturation and s2 < config.minSaturation
	end
	local gap = math.abs(h1 - h2)
	return math.min(gap, 1 - gap) <= config.maxGap
end

local function layoutOf(text: string?): string?
	local grid = if text then string.match(text, "(%d+x%d+)") else nil
	return if grid == "2x2" or grid == "4x4" or grid == "8x8" then grid else nil
end

-- A pick's image and traits: an image pick's own, or the chosen texture of an exported pack.
-- Returns nil and why when it has none.
local function imageOf(role: string, rank: number): (number?, any?, string?)
	local list = VfxConfig.picks[role]
	local pick = nil
	for _, entry in list or {} do
		if entry.rank == rank then
			pick = entry
			break
		end
	end
	if not pick then
		return nil, nil, "no such pick"
	end
	if pick.kind == "image" then
		if not pick.image then
			return nil, nil, pick.pending or "no image id"
		end
		return pick.image, VfxConfig.traits[pick.name] or VfxConfig.traits[pick.image] or { blend = "alpha" }, nil
	end
	local textures = pick.textures
	if not textures or #textures == 0 then
		return nil, nil, pick.pending or "pack not exported"
	end
	local choice = VfxConfig.packs[role .. ":" .. rank]
	local texture = textures[(choice and choice.use) or 1] or textures[1]
	local traits = VfxConfig.traits[texture.texture]
	if not traits then
		local layout = layoutOf(texture.flipbook)
		traits = {
			blend = "additive",
			flipbook = if layout then { layout = layout, mode = texture.mode or "OneShot", fps = texture.fps } else nil,
		}
	end
	return texture.texture, traits, nil
end

-- Whether a texture with `traits` can draw in `mode` for `usage`, and why not.
-- Whether a texture with `traits` can draw in `mode` for `usage`, and why not. The third result is
-- true when it draws as an additive particle sprite in place of a plane or billboard (a black
-- background or a flipbook; VfxConfig.filters.sprites).
local function fits(traits: any, mode: string, usage: any): (boolean, string?, boolean)
	local filters = VfxConfig.filters
	if traits.unusable then
		return false, traits.unusable, false
	end
	if traits.frame or mode == "screen" then
		return traits.frame == true and mode == "screen", "only a full-screen frame draws as a screen", false
	end
	if traits.burst and not usage.burst and not filters.burstAnywhere then
		return false, "a whole burst image: only for single flashes (filters.burstAnywhere)", false
	end
	if mode == "plane" or mode == "billboard" then
		if traits.blend ~= "alpha" or traits.flipbook then
			if filters.sprites then
				return true, nil, true
			end
			return false, "black background or flipbook: needs filters.sprites", false
		end
	elseif mode == "beam" then
		if traits.flipbook then
			return false, "a flipbook: beams cannot play it", false
		end
		if traits.beam == false and filters.beamAlong then
			return false, "does not read along a beam (filters.beamAlong)", false
		end
	end
	return true, nil, false
end

local function split(key: string): (string?, number?)
	local role, rank = string.match(key, "^(%a+):(%d+)$")
	return role, tonumber(rank)
end

-- The candidates for `usageName` in `context`, in order: { key, explicit } (explicit: a variant).
function VfxResolve.candidates(usageName: string, context: Context?): { { key: string, explicit: boolean } }
	local usage = VfxConfig.uses[usageName]
	local out = {}
	if not usage then
		return out
	end
	local seen = {}
	local function add(key: string?, explicit: boolean)
		if key and not seen[key] then
			seen[key] = true
			table.insert(out, { key = key, explicit = explicit })
		end
	end
	local unitVariants = if context and context.unit then VfxConfig.units[context.unit] else nil
	local elementVariants = if context and context.element then VfxConfig.elements[context.element] else nil
	for _, role in usage.roles do
		add(unitVariants and unitVariants[role], true)
		add(elementVariants and elementVariants[role], true)
	end
	for _, key in usage.first or {} do
		add(key, false)
	end
	for _, role in usage.roles do
		local ranks = {}
		for _, pick in VfxConfig.picks[role] or {} do
			table.insert(ranks, pick.rank)
		end
		table.sort(ranks)
		for _, rank in ranks do
			add(role .. ":" .. rank, false)
		end
	end
	return out
end

-- The texture `usageName` draws with for `context` (nil: keep the neon look), and the steps of
-- the choice. `loaded(id)` (optional) says whether an image has loaded; without it every image
-- counts as loaded. `mode` (optional) only accepts textures that draw that way (an effect that can
-- only be a plane passes over a flipbook to the next plane texture, rather than going neon).
function VfxResolve.resolve(
	usageName: string,
	context: Context?,
	loaded: ((number) -> boolean)?,
	mode: string?
): (Texture?, { Trace })
	local trace: { Trace } = {}
	local usage = VfxConfig.uses[usageName]
	if not usage then
		table.insert(trace, { key = usageName, reason = "unknown usage" })
		return nil, trace
	end
	if usage.on == false then
		table.insert(trace, { key = usageName, reason = "switched off (VfxConfig.uses " .. usageName .. ".on)" })
		return nil, trace
	end
	local color = context and context.color
	for _, candidate in VfxResolve.candidates(usageName, context) do
		local key = candidate.key
		local role, rank = split(key)
		if not role or not rank then
			table.insert(trace, { key = key, reason = "not a <role>:<rank> name" })
			continue
		end
		local id, traits, missing = imageOf(role, rank)
		if not id or not traits then
			table.insert(trace, { key = key, reason = missing or "no texture" })
			continue
		end
		local chosen, why, sprite = nil, nil, false
		for _, way in usage.modes do
			if mode and way ~= mode then
				why = why or ("this effect draws only as a " .. mode)
				continue
			end
			local ok, reason, asSprite = fits(traits, way, usage)
			if ok then
				chosen, sprite = way, asSprite
				break
			end
			why = why or reason
		end
		if not chosen then
			table.insert(trace, { key = key, reason = why or "does not fit" })
			continue
		end
		if
			VfxConfig.hue.strict
			and traits.baked
			and color
			and not candidate.explicit
			and not hueFits(traits.baked, color)
		then
			table.insert(trace, { key = key, reason = "baked hue rejected (hue.strict)" })
			continue
		end
		if loaded and not loaded(id) then
			table.insert(trace, { key = key, reason = "failed to load" })
			continue
		end
		table.insert(trace, { key = key, reason = "used" })
		-- Tinting: full for plain textures; a baked texture only part of the way (or not at all
		-- when its color already suits the effect, or with hue.strict); none with tint = false.
		local share = 1
		if traits.tint == false or traits.shade then
			share = 0
		elseif traits.baked then
			share = if VfxConfig.hue.strict
					or not color
					or hueFits(traits.baked, color)
				then 0
				else VfxConfig.hue.bakedTint
		end
		return {
			key = key,
			role = role,
			id = id,
			image = "rbxassetid://" .. string.format("%d", id),
			mode = chosen,
			blend = traits.blend or "alpha",
			tint = share > 0,
			tintShare = share,
			flipbook = traits.flipbook,
			brightness = usage.brightness or 1,
			speed = usage.speed or 0,
			width = usage.width or 1,
			upright = usage.upright == true,
			sprite = sprite,
			scale = (traits.scale or 1) * (usage.scale or 1),
			tile = traits.tile,
			light = usage.light or traits.light,
			shade = traits.shade,
			opacity = usage.opacity or 1,
		},
			trace
	end
	return nil, trace
end

-- The color to draw `texture` in for an effect of `color`: white (its own colors) blended toward
-- `color` by its tint share.
function VfxResolve.tint(texture: Texture, color: Color3): Color3
	if texture.shade then
		return texture.shade
	end
	local share = texture.tintShare
	if share >= 1 then
		return color
	elseif share <= 0 then
		return Color3.new(1, 1, 1)
	end
	return Color3.new(1, 1, 1):Lerp(color, share)
end

-- Every image id any pick can draw with (for preloading).
function VfxResolve.images(): { number }
	local out, seen = {}, {}
	for _, role in VfxConfig.roles do
		for _, pick in VfxConfig.picks[role] or {} do
			local id, traits = imageOf(role, pick.rank)
			if id and not seen[id] and not (traits and traits.unusable) then
				seen[id] = true
				table.insert(out, id)
			end
		end
	end
	return out
end

return VfxResolve
