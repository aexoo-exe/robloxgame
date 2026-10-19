-- The ultimate moment (match presentation): when a unit of the local player casts an ultimate that
-- opts in, the board slows down around it and the camera leans in, then everything catches up.
-- Client presentation only: the server's fight, its events and its results never change, and the
-- playback ends exactly where server time says it does.
--
-- How it works: CombatPlayback's fight clock (every unit view, effect and event of the fight reads
-- it) runs through a warped clock (UltimateMoment.newClock). A moment is a window of fight time in
-- which that clock runs at SETTINGS.rate (0.4x) of server fight time; once the window ends it runs at
-- SETTINGS.catchUp (2x) until it is back on server time (the debt paid), then 1x again. The window
-- starts `rate x preroll` fight seconds before the cast, so the caster's anticipation (Cinematic
-- squeezes it into that span: speed k = rate) plays at exactly its designed length in real seconds,
-- with no compression, while everything around it plays at 0.4x; the window ends SETTINGS.hold real
-- seconds after the cast (the hit itself plays slowed). Particles keep their real-time life.
--
-- The camera: from the window's start it eases (SETTINGS.cameraIn, real seconds) SETTINGS.cameraShare
-- of the way toward the caster, along its own line of sight (the board's orientation is kept: a
-- translation only), and eases back (cameraOut) when the window ends. Scenes multiply
-- UltimateMoment.cameraOffset(camera) onto their camera.
--
-- Limits: own units only (never an enemy's ultimate); at most one moment at a time, and none within
-- SETTINGS.cooldown fight seconds of the last one's start; none in the last SETTINGS.endMargin
-- seconds of a fight; none when off (EffectSettings.ultimateMoments) or with ReducedCameraMotion;
-- not in dev previews unless the local player's "UltimateMomentPreview" attribute is true.
-- Which ultimates opt in: UltimateConfig.units[id].moment (true / false); unset: tier 2 and up.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UltimateConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("UltimateConfig"))

local EffectSettings = require(script.Parent.EffectSettings)

local UltimateMoment = {}

UltimateMoment.SETTINGS = {
	rate = 0.4, -- the board's speed in a moment
	hold = 0.4, -- real seconds the moment lasts past the cast
	catchUp = 2, -- the board's speed afterwards, until it is back on server time
	cameraShare = 0.4, -- of the way toward the caster
	cameraIn = 0.35, -- real seconds
	cameraOut = 0.4,
	cooldown = 4, -- fight seconds from one moment's start to the next's
	endMargin = 2, -- fight seconds before the fight's end: no moment starts after that
}
local S = UltimateMoment.SETTINGS

-- Whether `unitType`'s ultimate opts in (UltimateConfig `moment`; unset: tier 2 and up).
function UltimateMoment.optedIn(unitType: string?): boolean
	local config = unitType and UltimateConfig.units[unitType]
	if type(config) ~= "table" then
		return false
	end
	if config.moment ~= nil then
		return config.moment == true
	end
	return (config.tier or 0) >= 2
end

-- Whether moments may play now (the player's setting, reduced camera motion).
function UltimateMoment.enabled(): boolean
	return EffectSettings.ultimateMoments() and not EffectSettings.reducedCameraMotion()
end

-- Whether moments may play in a dev preview (DevLineup) too.
function UltimateMoment.inPreview(): boolean
	local player = Players.LocalPlayer
	return player ~= nil and player:GetAttribute("UltimateMomentPreview") == true
end

-- The camera lean of the moment playing (one at a time, real-time eased).
type CameraLean = {
	focus: () -> Vector3?,
	startedAt: number?, -- os.clock() the lean began
	endingAt: number?, -- os.clock() the ease back began
	weight: number, -- where the ease back started from
}
local lean: CameraLean? = nil

local function smooth(t: number): number
	t = math.clamp(t, 0, 1)
	return t * t * (3 - 2 * t)
end

local function leanWeight(now: number): number
	local current = lean
	if not current or not current.startedAt then
		return 0
	end
	if current.endingAt then
		local w = current.weight * (1 - smooth((now - current.endingAt) / S.cameraOut))
		if w <= 0 then
			lean = nil
		end
		return w
	end
	return smooth((now - current.startedAt) / S.cameraIn)
end

-- The offset to multiply onto a scene's camera this frame (identity outside a moment): a move
-- toward the caster along the camera's line of sight to it.
function UltimateMoment.cameraOffset(cameraCFrame: CFrame): CFrame
	local current = lean
	if not current then
		return CFrame.identity
	end
	local w = leanWeight(os.clock())
	local focus = current.focus()
	if w <= 0 or not focus then
		return CFrame.identity
	end
	local relative = cameraCFrame:PointToObjectSpace(focus)
	return CFrame.new(relative * S.cameraShare * w)
end

export type Clock = {
	now: () -> number,
	step: () -> (),
	setEnd: (number) -> (),
	plan: (from: number, cast: number, focus: () -> Vector3?) -> boolean,
	busy: () -> boolean,
	clear: () -> (),
}

-- A warped fight clock over `base` (the server's fight time). Call step() once per frame before
-- anything reads now(). plan(from, cast, focus): a moment whose slow window starts at fight time
-- `from` (the caster's anticipation start) around a cast at `cast`; false when refused (limits).
function UltimateMoment.newClock(base: () -> number): Clock
	local shown = base()
	local lastBase = shown
	local fightEnd = math.huge
	local window: { from: number, to: number, focus: () -> Vector3?, entered: boolean, left: boolean }? = nil
	local lastStart = -math.huge

	local clock = {}

	function clock.now(): number
		return shown
	end

	function clock.setEnd(at: number)
		fightEnd = at
	end

	function clock.busy(): boolean
		return window ~= nil
	end

	function clock.plan(from: number, cast: number, focus: () -> Vector3?): boolean
		if window or not UltimateMoment.enabled() then
			return false
		end
		if from - lastStart < S.cooldown or cast > fightEnd - S.endMargin then
			return false
		end
		window = {
			from = math.max(from, shown),
			to = cast + S.hold * S.rate, -- `hold` real seconds at `rate`
			focus = focus,
			entered = false,
			left = false,
		}
		lastStart = from
		return true
	end

	function clock.step()
		local b = base()
		local db = b - lastBase
		lastBase = b
		if db < 0 or db > 2 then
			-- The base clock jumped (a reset, a long hitch): back on it at once.
			shown = b
			return
		end
		local w = window
		local rate = 1
		if w and shown >= w.from and shown < w.to then
			rate = S.rate
			if not w.entered then
				w.entered = true
				lean = { focus = w.focus, startedAt = os.clock(), endingAt = nil, weight = 0 }
			end
		elseif shown < b then
			rate = S.catchUp
		end
		if w and shown >= w.to and not w.left then
			w.left = true
			local current = lean
			if current and not current.endingAt then
				current.weight = leanWeight(os.clock())
				current.endingAt = os.clock()
			end
		end
		shown = math.min(shown + db * rate, b)
		-- Near the fight's end the board is put back on server time at once: the round ends on time.
		if b >= fightEnd - 0.5 then
			shown = b
		end
		if w and w.left and shown >= b then
			window = nil -- caught up
		end
	end

	function clock.clear()
		window = nil
		shown = base()
		lastBase = shown
		lean = nil
	end

	return clock :: any
end

-- Drops the camera lean (a fight or preview ends).
function UltimateMoment.clear()
	lean = nil
end

return UltimateMoment
