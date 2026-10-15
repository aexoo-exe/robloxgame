-- Camera emphasis for ultimates: a push toward a focus point and a screen dim, layered on top of
-- whatever camera the scene sets (Arena's board camera, DevLineup's stage) through
-- CameraCues.offset(). Only Tier 4-5 ultimates ask for cues (UltimateConfig.tiers `camera`), only
-- on the board the local player watches (CameraCues.setWatched), at most
-- UltimateConfig.camera.maxConcurrent at once, with a cooldown after each, intensities capped,
-- and none while EffectSettings asks for reduced camera motion (pushes) or reduced effects
-- (dims). A refused cue is simply skipped: the ultimate still plays. Times run on the effects'
-- clock (CameraCues.setClock, as ImpactEffects), so pushes follow slow motion and fast-forward.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UltimateConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("UltimateConfig"))

local EffectSettings = require(script.Parent.EffectSettings)

local CameraCues = {}

local CONFIG = UltimateConfig.camera

-- One cue: a push (studs toward `focus`) and a dim (0-1), each eased in over `rise`, held, eased
-- out over `fall`, between `startAt` and `endAt`.
type Cue = {
	owner: any,
	key: string,
	priority: number,
	startAt: number,
	endAt: number,
	rise: number,
	fall: number,
	push: number,
	dim: number,
	focus: Vector3?,
}

local cues: { Cue } = {}
local lastEndAt = -math.huge
local watched = true
local clock: () -> number = os.clock
local dimEffect: ColorCorrectionEffect? = nil

function CameraCues.setClock(source: (() -> number)?)
	clock = source or os.clock
end

-- Whether the board on screen is the local player's (cues are only shown then).
function CameraCues.setWatched(on: boolean)
	watched = on
end

local function smooth(t: number): number
	t = math.clamp(t, 0, 1)
	return t * t * (3 - 2 * t)
end

local function weight(cue: Cue, now: number): number
	if now < cue.startAt or now > cue.endAt then
		return 0
	end
	local up = if cue.rise > 0 then smooth((now - cue.startAt) / cue.rise) else 1
	local down = if cue.fall > 0 then smooth((cue.endAt - now) / cue.fall) else 1
	return math.min(up, down)
end

local function prune(now: number)
	for i = #cues, 1, -1 do
		if now > cues[i].endAt then
			lastEndAt = math.max(lastEndAt, cues[i].endAt)
			table.remove(cues, i)
		end
	end
end

export type Request = {
	owner: any, -- who asks (an ultimate's run): the concurrency limit counts owners
	key: string?, -- one live cue per owner and key; a new request replaces it
	tier: number,
	startAt: number,
	endAt: number,
	rise: number?,
	fall: number?,
	push: number?, -- studs
	dim: number?, -- 0-1
	focus: Vector3?,
}

-- Asks for a cue. Returns whether it was taken (false: refused by tier, setting, limit or
-- cooldown; the caller just goes on without it).
function CameraCues.request(request: Request): boolean
	local tier = UltimateConfig.tiers[request.tier]
	if not watched or not tier or not tier.camera then
		return false
	end
	local now = clock()
	prune(now)
	local push = if EffectSettings.reducedCameraMotion() then 0 else math.min(request.push or 0, CONFIG.maxPush)
	local dim = if EffectSettings.reducedEffects() or not tier.dim then 0 else math.min(request.dim or 0, CONFIG.maxDim)
	if push <= 0 and dim <= 0 then
		return false
	end
	local key = request.key or "main"
	local mine, others = false, {}
	for i = #cues, 1, -1 do
		local cue = cues[i]
		if cue.owner == request.owner then
			mine = true
			if cue.key == key then
				table.remove(cues, i)
			end
		else
			others[cue.owner] = math.max(others[cue.owner] or 0, cue.priority)
		end
	end
	if not mine then
		local count, lowest, lowestOwner = 0, math.huge, nil
		for owner, priority in others do
			count += 1
			if priority < lowest then
				lowest, lowestOwner = priority, owner
			end
		end
		if count >= CONFIG.maxConcurrent then
			-- A higher tier takes over from a lower one; otherwise the newcomer goes without.
			if lowest >= request.tier then
				return false
			end
			for i = #cues, 1, -1 do
				if cues[i].owner == lowestOwner then
					table.remove(cues, i)
				end
			end
		elseif count == 0 and now < lastEndAt + CONFIG.cooldown then
			return false -- the last cue ended moments ago: let the camera rest
		end
	end
	table.insert(cues, {
		owner = request.owner,
		key = key,
		priority = request.tier,
		startAt = request.startAt,
		endAt = request.endAt,
		rise = request.rise or 0.25,
		fall = request.fall or 0.3,
		push = push,
		dim = dim,
		focus = request.focus,
	})
	return true
end

-- Ends `owner`'s cue now (easing out from where it is).
function CameraCues.release(owner: any)
	local now = clock()
	for _, cue in cues do
		if cue.owner == owner and cue.endAt > now + cue.fall then
			cue.endAt = now + cue.fall
		end
	end
end

-- Drops every cue (a fight ends, a preview closes).
function CameraCues.clear()
	table.clear(cues)
	lastEndAt = -math.huge
	if dimEffect then
		dimEffect.Enabled = false
	end
end

local function dimmer(): ColorCorrectionEffect?
	local camera = workspace.CurrentCamera
	if not camera then
		return nil
	end
	if not dimEffect or dimEffect.Parent ~= camera then
		local made = Instance.new("ColorCorrectionEffect")
		made.Name = "UltimateDim"
		made.Enabled = false
		made.Parent = camera
		dimEffect = made
	end
	return dimEffect
end

-- The offset to multiply onto the scene camera's CFrame this frame (identity when no cue), and it
-- updates the screen dim. `cameraCFrame` is the scene camera before the offset.
function CameraCues.offset(cameraCFrame: CFrame): CFrame
	local now = clock()
	prune(now)
	local push, dim = 0, 0
	local focus = nil
	for _, cue in cues do
		local w = weight(cue, now)
		if w > 0 then
			if cue.push * w > push then
				push, focus = cue.push * w, cue.focus
			end
			dim = math.max(dim, cue.dim * w)
		end
	end
	local effect = if dim > 0 or (dimEffect and dimEffect.Enabled) then dimmer() else nil
	if effect then
		effect.Enabled = dim > 0.005
		effect.Brightness = -0.35 * dim
		effect.Saturation = -0.6 * dim
		effect.Contrast = 0.25 * dim
	end
	if push <= 0 then
		return CFrame.identity
	end
	-- Move along the line to the focus (or straight ahead), in the camera's own space.
	local direction = Vector3.new(0, 0, -1)
	if focus then
		local relative = cameraCFrame:PointToObjectSpace(focus)
		if relative.Magnitude > 1e-3 then
			direction = relative.Unit
			push = math.min(push, relative.Magnitude * 0.25)
		end
	end
	return CFrame.new(direction * push)
end

return CameraCues
