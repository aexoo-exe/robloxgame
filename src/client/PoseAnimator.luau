-- Keyframed poses for units: whole-body poses at times, eased from one to the next, with holds and a
-- held-tension shiver. Presentation only.
--
-- A unit's body is not a rig of Motor6D joints: every unit (catalog avatars included) is anchored
-- parts placed each frame from a Figure.Pose by UnitView (Figure.place, one BulkMoveTo). So a pose
-- here is a set of pose channels (UnitMotion.ultimatePose), not joint CFrames:
--   leftArm, rightArm          degrees raised forward from the resting angle (negative: back)
--   leftArmOut, rightArmOut    degrees raised out to the side (negative: across the chest)
--   lean, twist, tilt, fall    degrees (lean forward; twist positive: the right shoulder forward)
--   spin                       degrees, the whole body about the vertical
--   leftLeg, rightLeg          degrees forward (negative: back)
--   crouch                     hips dropped, a fraction of leg length
--   tremble                    degrees of a fast sideways shiver (held tension)
--   lunge, rise                studs (normal size) forward along the facing, and up
--   headPitch, headYaw, headRoll  degrees
-- The pose layers on top of the unit's own motion (idle, hits, stun, death) every frame, on the
-- view's clock (the fight's, or the dev stage's), so it follows slow motion, freezes and hit-stop.
-- Nothing is written to the body to undo: when the keys end (or stop) the layer settles out over
-- AnimationConfig.overlap.ultimateSettle and the unit's own motion is all that is left.
--
-- Overlap: the head and arms trail the body. Their keys land OVERLAP seconds after the key's time
-- (never past their next key), so the torso leads and the limbs follow instead of every channel
-- arriving at once. Snap keys stay exactly on time (a strike lands on its hit), and so do holds.
--
-- Keyframes: { { at = t, pose = { channel = value }, ease = "...", hold = seconds?, shiver = degrees? } }
-- in order of `at` (seconds; for an ultimate, design seconds relative to the release, negative before
-- it). `ease` shapes the way into the key from the one before (UnitMotion EASES: "linear", "in",
-- "out", "inOut", "snap", "back", "backOut", "quadIn", "quadOut", "expoIn", "expoOut", "hold");
-- default "inOut". A key sets only the channels it names: the others carry on from their own last
-- key. `hold` keeps the key's pose that long after `at` (a key at at + hold with the same values);
-- `shiver` shakes it through the hold (the tremble channel, back to 0 when the hold ends). A channel
-- with no key before a key that names it starts from 0 (rest) at the first key's time.
--
-- Use:
--   * In an ultimate module (Cinematic runs it on the cast's timeline, anticipation compressed to
--     the real window):  def.pose = PoseAnimator.track(KEYFRAMES)
--   * Anywhere else: local handle = PoseAnimator.play(view, KEYFRAMES, { at = now })
--     handle:stop() eases it out early; handle:playing() says whether it still plays.

local UnitView = require(script.Parent.UnitView)

local PoseAnimator = {}

export type Keyframe = {
	at: number,
	pose: { [string]: number }?,
	ease: string?,
	hold: number?,
	shiver: number?,
}

export type Track = { [string]: { any } }

-- Design seconds each channel's keys trail the body by (the overlap); channels not listed lead.
local OVERLAP = {
	headPitch = 0.05,
	headYaw = 0.05,
	headRoll = 0.05,
	leftArm = 0.035,
	rightArm = 0.035,
	leftArmOut = 0.035,
	rightArmOut = 0.035,
}
local ON_TIME = { snap = true, hold = true } -- eases whose keys never trail

-- Shifts a channel's keys (sorted) later by `lag`, except the first, snaps and holds, never onto or
-- past the next key.
local function trail(keys: { any }, lag: number)
	for i = 2, #keys do
		local key = keys[i]
		if not ON_TIME[key[3] or ""] then
			local next = keys[i + 1]
			local latest = if next then next[1] - 1e-4 else math.huge
			key[1] = math.max(key[1], math.min(key[1] + lag, latest))
		end
	end
end

-- Per-channel keys ({ { t, value, ease } }, UnitMotion.ultimatePose's track) from keyframes.
function PoseAnimator.track(keyframes: { Keyframe }): Track
	local track: Track = {}
	local first = if #keyframes > 0 then keyframes[1].at else 0
	local function add(channel: string, at: number, value: number, ease: string?)
		local keys = track[channel]
		if not keys then
			keys = {}
			track[channel] = keys
			if at > first then
				table.insert(keys, { first, 0 }) -- from rest at the first key's time
			end
		end
		local last = keys[#keys]
		if last and last[1] >= at then
			-- Two keys at one time: the later wins (a key just after another, e.g. a hold's end).
			at = last[1] + 1e-4
		end
		table.insert(keys, { at, value, ease })
	end
	for _, key in keyframes do
		local pose = key.pose or {}
		for channel, value in pose do
			add(channel, key.at, value, key.ease)
		end
		if key.hold and key.hold > 0 then
			for channel, value in pose do
				add(channel, key.at + key.hold, value, "linear")
			end
		end
		if key.shiver then
			local ends = key.at + (key.hold or 0)
			add("tremble", key.at, key.shiver, key.ease)
			add("tremble", ends, key.shiver, "linear")
			add("tremble", ends + 1e-3, 0, "hold")
		end
	end
	-- Keys are added in keyframe order; a channel's keys must also be in time order. Then the head and
	-- arms trail the body (OVERLAP).
	for channel, keys in track do
		table.sort(keys, function(a, b)
			return a[1] < b[1]
		end)
		local lag = OVERLAP[channel]
		if lag then
			trail(keys, lag)
		end
	end
	return track
end

-- The first and last key times of a track.
function PoseAnimator.span(track: Track): (number, number)
	local from, to = math.huge, -math.huge
	for _, keys in track do
		if #keys > 0 then
			from = math.min(from, keys[1][1])
			to = math.max(to, keys[#keys][1])
		end
	end
	if from > to then
		return 0, 0
	end
	return from, to
end

export type PlayOptions = {
	at: number?, -- the view's clock time keyframe time 0 falls on (default: now minus the first key's time)
	speed: number?, -- design seconds per clock second before keyframe time 0 (<= 1 compresses; default 1)
	tail: number?, -- clock seconds kept after the last key before the layer settles out (default 0.05)
}

export type Handle = {
	track: Track,
	view: any,
	stop: (Handle) -> (),
	playing: (Handle) -> boolean,
}

-- Plays keyframes (or a track from PoseAnimator.track) on a unit view. Replaces whatever pose keys the
-- view is playing (an ultimate's, another handle's).
function PoseAnimator.play(view: any, keyframes: { Keyframe } | Track, opts: PlayOptions?): Handle
	local o = opts or {}
	local track: Track = if (keyframes :: any)[1] ~= nil
		then PoseAnimator.track(keyframes :: { Keyframe })
		else keyframes :: Track
	local from, to = PoseAnimator.span(track)
	local now = view.clock()
	local speed = math.clamp(o.speed or 1, 1e-3, 1)
	local zero = o.at or (now - math.min(from, 0) * speed)
	-- Keyframe time `t` as the view's clock time (compressed before 0, as Cinematic does).
	local function clockOf(t: number): number
		return if t < 0 then zero + t * speed else zero + t
	end
	UnitView.ultimatePose(view, track, clockOf(from), zero, speed, clockOf(to) + (o.tail or 0.05))
	local handle = {
		track = track,
		view = view,
	}
	function handle.stop(self: Handle)
		UnitView.endUltimatePose(self.view, self.track)
	end
	function handle.playing(self: Handle): boolean
		return UnitView.playingPose(self.view, self.track)
	end
	return handle :: any
end

return PoseAnimator
