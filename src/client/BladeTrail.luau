-- Slash trails on a held blade: Roblox Trails between two Attachments on the blade (near the hilt
-- and at the tip), so each cut draws its own arc as the blade really moves. Presentation only.
--
-- A unit's figure is anchored parts placed each frame (Figure.place), with no welds to hang a trail
-- on, so a hidden carrier part follows the hand's anchor every frame (RenderStepped) and the two
-- Attachments ride it. A held weapon runs along the hand anchor's -Z (LookKit weapons: the grip a
-- little above the anchor, the blade past the fist), so the attachments sit on that line at
-- `from` and `to` of the figure's height from the hand. The trail is as wide as the blade between
-- them. Lifetimes follow the effects' time scale (slow motion keeps the same arc on screen).
--
-- Use:
--   local blade = BladeTrail.attach(view, { hand = "right", from = 0.2, to = 0.66 })
--   blade:add("cut1", { colors = ColorSequence..., lifetime = 0.2 })
--   blade:enable("cut1")   -- just before the strike (clears its old points)
--   blade:disable("cut1")  -- after the follow-through: what is drawn fades over its lifetime
--   blade:tip(), blade:base()  -- world points on the blade now
--   blade:destroy()        -- also happens on its own once the unit's view is gone

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local ImpactEffects = require(script.Parent.ImpactEffects)
local ViewScale = require(script.Parent.ViewScale)

local BladeTrail = {}

local GRIP = 0.045 -- the grip's height above the hand anchor, a share of the figure's height (LookKit)

export type Options = {
	hand: string?, -- "right" (default) or "left"
	from: number?, -- the trail's inner edge along the blade, a share of the figure's height (0.2)
	to: number?, -- its outer edge: the tip (0.66 for a katana: LookKit's hilt, guard and 0.5 blade)
	-- Scale with the camera distance (ViewScale), each frame: the ribbon reaches further past the
	-- hilt (`to` - `from` times the scale) and lives up to 50% longer at the match camera, so cuts
	-- read from far away. Off: the blade's own size and the trails' own lifetimes.
	viewScale: boolean?,
}

export type TrailSpec = {
	colors: ColorSequence, -- along the trail: head (the blade) to tail
	lifetime: number?, -- seconds at 1x (default 0.2)
	lightEmission: number?, -- default 0.45
	transparency: NumberSequence?, -- default 0 at the head to 1 at the tail
	widthScale: NumberSequence?, -- default 1 at the head tapering to 0.25
}

local folder: Folder? = nil
local function holder(): Folder
	if not folder or not folder.Parent then
		local made = Instance.new("Folder")
		made.Name = "BladeTrails" -- not an effect folder ReelCheck counts: trails are not parts
		made.Parent = Workspace
		folder = made
	end
	return folder :: Folder
end

export type Handle = {
	view: any,
	carrier: BasePart,
	baseAttachment: Attachment,
	tipAttachment: Attachment,
	trails: { [string]: { trail: Trail, lifetime: number } },
	connection: RBXScriptConnection?,
	hand: string,
	from: number,
	to: number,
	viewScale: boolean,
	add: (Handle, string, TrailSpec) -> Trail,
	enable: (Handle, string) -> (),
	disable: (Handle, string) -> (),
	tip: (Handle) -> Vector3,
	base: (Handle) -> Vector3,
	destroy: (Handle) -> (),
}

-- The hand anchor now, or nil (a store model or a figure without hands).
local function anchorOf(handle: Handle): CFrame?
	local figure = handle.view and handle.view.figure
	if not figure or figure.isModel then
		return nil
	end
	return figure.anchors[handle.hand .. "Hand"]
end

local Methods = {}
Methods.__index = Methods

function Methods.add(self: Handle, name: string, spec: TrailSpec): Trail
	local trail = Instance.new("Trail")
	trail.Name = name
	trail.Attachment0 = self.baseAttachment
	trail.Attachment1 = self.tipAttachment
	trail.FaceCamera = false
	trail.LightInfluence = 0
	trail.LightEmission = spec.lightEmission or 0.45
	trail.Color = spec.colors
	trail.Transparency = spec.transparency or NumberSequence.new(0, 1)
	trail.WidthScale = spec.widthScale
		or NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(1, 0.25),
		})
	trail.MinLength = 0.02
	trail.Lifetime = spec.lifetime or 0.2
	trail.Enabled = false
	trail.Parent = self.carrier
	self.trails[name] = { trail = trail, lifetime = spec.lifetime or 0.2 }
	return trail
end

function Methods.enable(self: Handle, name: string)
	local entry = self.trails[name]
	if entry then
		entry.trail:Clear() -- no segment from where the blade last was
		entry.trail.Enabled = true
	end
end

function Methods.disable(self: Handle, name: string)
	local entry = self.trails[name]
	if entry then
		entry.trail.Enabled = false
	end
end

function Methods.tip(self: Handle): Vector3
	return self.tipAttachment.WorldPosition
end

function Methods.base(self: Handle): Vector3
	return self.baseAttachment.WorldPosition
end

function Methods.destroy(self: Handle)
	if self.connection then
		self.connection:Disconnect()
		self.connection = nil
	end
	self.carrier:Destroy()
end

-- Puts the carrier on the hand and the attachments on the blade; trail lifetimes follow slow motion.
local function follow(handle: Handle)
	local view = handle.view
	if not view or not view.part or not view.part.Parent then
		Methods.destroy(handle)
		return
	end
	local anchor = anchorOf(handle)
	if not anchor then
		return
	end
	local h = view.figure.height
	handle.carrier.CFrame = anchor
	local reach, life = 1, 1
	if handle.viewScale then
		reach = ViewScale.of(anchor.Position)
		life = 1 + 0.5 * ViewScale.share(reach)
	end
	local to = handle.from + (handle.to - handle.from) * reach
	handle.baseAttachment.Position = Vector3.new(0, GRIP * h, -handle.from * h)
	handle.tipAttachment.Position = Vector3.new(0, GRIP * h, -to * h)
	local scale = math.max(ImpactEffects.timeScale(), 0.05)
	for _, entry in handle.trails do
		entry.trail.Lifetime = entry.lifetime * life / scale
	end
end

-- A blade on `view`'s hand that trails can be added to (BladeTrail module comment).
function BladeTrail.attach(view: any, opts: Options?): Handle
	local o = opts or {}
	local carrier = Instance.new("Part")
	carrier.Name = "BladeTrail"
	carrier.Anchored = true
	carrier.CanCollide = false
	carrier.CanQuery = false
	carrier.CanTouch = false
	carrier.CastShadow = false
	carrier.Transparency = 1
	carrier.Size = Vector3.one * 0.1
	local base = Instance.new("Attachment")
	base.Name = "BladeBase"
	base.Parent = carrier
	local tip = Instance.new("Attachment")
	tip.Name = "BladeTip"
	tip.Parent = carrier
	local handle: Handle = setmetatable({
		view = view,
		carrier = carrier,
		baseAttachment = base,
		tipAttachment = tip,
		trails = {},
		connection = nil,
		hand = o.hand or "right",
		from = o.from or 0.2,
		to = o.to or 0.66,
		viewScale = o.viewScale == true,
	}, Methods) :: any
	follow(handle)
	carrier.Parent = holder()
	handle.connection = RunService.RenderStepped:Connect(function()
		follow(handle)
	end)
	return handle
end

return BladeTrail
