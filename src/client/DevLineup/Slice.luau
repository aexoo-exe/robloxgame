-- DevLineup's vertical slice: K replays SLICE_UNIT's ultimate with the slice camera (an orbit the
-- user aims), G with the match camera's framing, S at 0.25x; the slice camera's controls; and the
-- restore of the arena and camera once a replay has played. Studio only (see DevLineup).

local ContextActionService = game:GetService("ContextActionService")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Config = require(script.Parent.Config)
local Field = require(script.Parent.Field)
local Hud = require(script.Parent.Hud)
local Lineup = require(script.Parent.Lineup)
local State = require(script.Parent.State)

local Cinematic = require(script.Parent.Parent.Cinematic)
local HitFeel = require(script.Parent.Parent.HitFeel)
local ImpactEffects = require(script.Parent.Parent.ImpactEffects)

local Slice = {}

local SLICE_UNIT = Config.SLICE_UNIT

-- The slice camera's controls, while it is on: right-mouse drag or the arrow keys orbit around the
-- focus, the mouse wheel or + / - zoom, Q raises and E lowers, P prints the framing and keeps it
-- for this session's next K / S (State.sliceFraming). Bound through ContextActionService above
-- every default binding and sunk, so the default camera and the character controls never see them.
local SLICE_ACTION = "DevLineupSliceCamera"
Slice.KEYS = {
	[Enum.KeyCode.Up] = true,
	[Enum.KeyCode.Down] = true,
	[Enum.KeyCode.Left] = true,
	[Enum.KeyCode.Right] = true,
	[Enum.KeyCode.Q] = true,
	[Enum.KeyCode.E] = true,
	[Enum.KeyCode.P] = true,
	[Enum.KeyCode.Equals] = true,
	[Enum.KeyCode.Minus] = true,
	[Enum.KeyCode.KeypadPlus] = true,
	[Enum.KeyCode.KeypadMinus] = true,
} :: { [Enum.KeyCode]: boolean }
local ORBIT_RATE = 90 -- degrees per second (arrow keys)
local MOUSE_RATE = 0.3 -- degrees per pixel of right-mouse drag
local ZOOM_RATE = 1.8 -- distance factor per second (+ / - held)
local WHEEL_STEP = 0.88 -- distance factor per wheel notch
local RISE_RATE = 4 -- studs per second (Q / E)
local sliceHeld: { [Enum.KeyCode]: boolean } = {}
local sliceOrbiting = false
local sliceControls: RBXScriptConnection? = nil
-- Which camera the slice replays use: "slice" (K: the orbit) or "gameplay" (G: the match camera's
-- framing, Arena.boardCamera). S replays with the last one used.
local sliceCameraMode = "slice"

-- True while the slice camera's controls are bound (its keys are its own).
function Slice.controlsBound(): boolean
	return sliceControls ~= nil
end

local function clampSliceView()
	local sliceView = State.sliceView
	sliceView.pitch = math.clamp(sliceView.pitch, -10, 80)
	sliceView.distance = math.clamp(sliceView.distance, 3, 60)
	sliceView.height = math.clamp(sliceView.height, -4, 12)
end

local function saveSliceView()
	local sliceView = State.sliceView
	State.sliceFraming = table.clone(sliceView)
	print(
		string.format(
			"[DevLineup] slice camera saved for this session: yaw %.1f, pitch %.1f, distance %.2f, height %.2f"
				.. " (DevLineup SLICE_DEFAULT to keep it)",
			sliceView.yaw,
			sliceView.pitch,
			sliceView.distance,
			sliceView.height
		)
	)
end

local function onSliceInput(_: string, state: Enum.UserInputState, input: InputObject): Enum.ContextActionResult
	local sliceView = State.sliceView
	local kind = input.UserInputType
	if kind == Enum.UserInputType.MouseButton2 then
		sliceOrbiting = state == Enum.UserInputState.Begin
		UserInputService.MouseBehavior = if sliceOrbiting
			then Enum.MouseBehavior.LockCurrentPosition
			else Enum.MouseBehavior.Default
		return Enum.ContextActionResult.Sink
	elseif kind == Enum.UserInputType.MouseMovement then
		if not sliceOrbiting then
			return Enum.ContextActionResult.Pass -- only a drag is ours
		end
		sliceView.yaw -= input.Delta.X * MOUSE_RATE
		sliceView.pitch += input.Delta.Y * MOUSE_RATE
		clampSliceView()
		return Enum.ContextActionResult.Sink
	elseif kind == Enum.UserInputType.MouseWheel then
		sliceView.distance *= WHEEL_STEP ^ input.Position.Z
		clampSliceView()
		return Enum.ContextActionResult.Sink
	end
	local key = input.KeyCode
	if key == Enum.KeyCode.P then
		if state == Enum.UserInputState.Begin then
			saveSliceView()
		end
	else
		sliceHeld[key] = state == Enum.UserInputState.Begin
	end
	return Enum.ContextActionResult.Sink
end

local function held(...: Enum.KeyCode): number
	for _, key in { ... } do
		if sliceHeld[key] then
			return 1
		end
	end
	return 0
end

local function bindSliceControls()
	if sliceControls then
		return
	end
	local inputs: { any } = {
		Enum.UserInputType.MouseButton2,
		Enum.UserInputType.MouseMovement,
		Enum.UserInputType.MouseWheel,
	}
	for key in Slice.KEYS do
		table.insert(inputs, key)
	end
	ContextActionService:BindActionAtPriority(
		SLICE_ACTION,
		onSliceInput,
		false,
		Enum.ContextActionPriority.High.Value + 50,
		table.unpack(inputs)
	)
	-- Held keys move the orbit at a steady rate (real seconds: the same in slow motion).
	sliceControls = RunService.RenderStepped:Connect(function(dt)
		local sliceView = State.sliceView
		sliceView.yaw += (held(Enum.KeyCode.Left) - held(Enum.KeyCode.Right)) * ORBIT_RATE * dt
		sliceView.pitch += (held(Enum.KeyCode.Up) - held(Enum.KeyCode.Down)) * ORBIT_RATE * dt
		local zoom = held(Enum.KeyCode.Minus, Enum.KeyCode.KeypadMinus)
			- held(Enum.KeyCode.Equals, Enum.KeyCode.KeypadPlus)
		sliceView.distance *= ZOOM_RATE ^ (zoom * dt)
		sliceView.height += (held(Enum.KeyCode.Q) - held(Enum.KeyCode.E)) * RISE_RATE * dt
		clampSliceView()
	end)
end

local function unbindSliceControls()
	local controls = sliceControls
	if not controls then
		return
	end
	ContextActionService:UnbindAction(SLICE_ACTION)
	controls:Disconnect()
	sliceControls = nil
	table.clear(sliceHeld)
	if sliceOrbiting then
		sliceOrbiting = false
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	end
end

-- The slice camera (K, S on the slice unit): the arena's "slice" framing (a gray arena if none is
-- on), then, once the replay has played (`seconds` real seconds after it starts), the arena and
-- camera from before, the field preview ended (back on the stage). A new replay restarts the wait.
local function enterSliceCamera()
	if not State.sliceSaved then
		State.sliceSaved = { arena = State.arenaMode, camera = State.arenaCamera }
	end
	if State.arenaMode == "off" then
		State.arenaMode = "gray"
	end
	State.arenaCamera = sliceCameraMode
	-- With the match camera, hit feel is as in a match (a mild punch-in), not a focused close-up's.
	HitFeel.setFocused(sliceCameraMode ~= "gameplay")
	if sliceCameraMode == "slice" then
		State.sliceView = table.clone(State.sliceFraming) -- each replay starts from the saved framing
		bindSliceControls()
	else
		unbindSliceControls() -- the match camera is not aimed
	end
	State.sliceToken += 1
	Hud.refreshTitle()
end

function Slice.leave()
	local saved = State.sliceSaved
	unbindSliceControls()
	if not saved then
		return
	end
	State.sliceSaved = nil
	State.sliceToken += 1
	State.arenaMode, State.arenaCamera = saved.arena, saved.camera
	HitFeel.setFocused(State.stage ~= nil)
	local s = State.stage
	if s and s.fieldPreview then
		Field.endPreview(s)
	end
	Hud.refreshTitle()
end

-- After `seconds` stage seconds (the replay's length: slow motion stretches it and a freeze stops it)
-- plus SLICE_AIM real seconds to aim on the still field; never while frozen or in the middle of a
-- right-mouse drag (it waits for both to end).
local SLICE_AIM = 2
local function leaveSliceCameraAfter(seconds: number)
	local token = State.sliceToken
	local deadline = State.stageClock() + seconds
	task.spawn(function()
		while token == State.sliceToken and (State.stageClock() < deadline or State.timeScale == 0) do
			task.wait(0.2)
		end
		task.wait(SLICE_AIM)
		while token == State.sliceToken and (sliceOrbiting or State.timeScale == 0) do
			task.wait(0.2)
		end
		if token == State.sliceToken then
			Slice.leave()
		end
	end)
end

-- S: judge an ultimate: replay it (as key 3) at 0.25x, particles included, then back to 1x.
function Slice.slowReplay(s: State.Stage)
	local slow = 0.25
	State.timeScale = slow
	ImpactEffects.setTimeScale(slow)
	local slice = s.unitType == SLICE_UNIT
	if slice then
		s.castPresses = 0 -- the slice: the same ultimate K shows (its first cast), not the next one
		enterSliceCamera()
	end
	Field.cast(s)
	if slice then
		leaveSliceCameraAfter((s.previewSeconds or Config.FIELD_AFTER) + 0.5)
	end
	print("[DevLineup] ultimate at 0.25x (back to 1x in 14 s)")
	task.delay(14, function()
		if State.timeScale == slow then
			State.timeScale = 1
			ImpactEffects.setTimeScale(1)
		end
	end)
end

-- K: the vertical slice's ultimate at 1x on key 3's field (its first cast, every time), with the
-- slice camera (`mode` "slice"); G: the same with the match camera's framing ("gameplay"), to judge
-- it the way players see it.
function Slice.replay(mode: string)
	sliceCameraMode = mode
	if not State.folder then
		Lineup.open()
	end
	if not State.stage or State.stage.unitType ~= SLICE_UNIT then
		Lineup.showUnit(SLICE_UNIT)
	end
	local s = State.stage
	if not s then
		return
	end
	State.timeScale = 1
	ImpactEffects.setTimeScale(1)
	s.castPresses = 0
	enterSliceCamera()
	Field.cast(s)
	leaveSliceCameraAfter((s.previewSeconds or Config.FIELD_AFTER) + 0.5)
	print(
		string.format(
			"[DevLineup] slice: %s, %s camera (S: the same at 0.25x)",
			SLICE_UNIT,
			if mode == "gameplay" then "match" else "slice"
		)
	)
end

-- The slice unit's running ultimate (Cinematic), if any.
local function sliceRun(): any?
	for index = 1, 256 do
		local run = Cinematic.running(index)
		if run and run.unitType == SLICE_UNIT then
			return run
		end
	end
	return nil
end

local HOLD_SCALE = 0.25 -- the replay plays slowed on its way, so it stops within a few ms of the beat
local HOLD_TIMEOUT = 20 -- real seconds

-- Replays the slice (as K; G with `mode` "gameplay") and holds it at `beat`: a design time (seconds
-- from the real hit, negative before it) or the name of one of the module's plan times
-- (run.memo.plan: "windup", "set", "load", "finisher", ...), plus `offset` design seconds. The stage
-- clock, poses, effects and the slice camera all stop there (O, or the QA handle's `resume`, goes
-- on), so a screenshot catches exactly that beat. Yields until held (Studio MCP: one call, then
-- capture); returns what it held at, or why it could not.
function Slice.hold(beat: number | string, offset: number?, mode: string?): string
	local before = sliceRun()
	Slice.replay(mode or "slice")
	State.timeScale = HOLD_SCALE
	ImpactEffects.setTimeScale(HOLD_SCALE)
	local started = os.clock()
	local function giveUp(why: string): string
		State.timeScale = 1
		ImpactEffects.setTimeScale(1)
		warn("[DevLineup] hold: " .. why)
		return why
	end
	local run = nil
	while not run and os.clock() - started < HOLD_TIMEOUT do
		local found = sliceRun()
		if found and found ~= before then
			run = found
		else
			RunService.RenderStepped:Wait()
		end
	end
	if not run then
		return giveUp("no ultimate of " .. SLICE_UNIT .. " started")
	end
	local target: number? = if type(beat) == "number" then beat else nil
	while os.clock() - started < HOLD_TIMEOUT do
		local plan: any = run.memo.plan
		if not target and plan then
			if type(plan[beat]) ~= "number" then
				local names = {}
				for name in plan do
					table.insert(names, name)
				end
				table.sort(names)
				return giveUp(string.format("no beat %q in the plan (%s)", tostring(beat), table.concat(names, ", ")))
			end
			target = plan[beat]
		end
		if target and run:designTime() >= target + (offset or 0) then
			State.frozenScale = 1
			State.timeScale = 0
			ImpactEffects.setTimeScale(0)
			if State.freezeButton then
				State.freezeButton.Text = "Resume"
			end
			local report = string.format(
				"%s held at %s%s (design %.3f s)",
				SLICE_UNIT,
				tostring(beat),
				if offset and offset ~= 0 then string.format(" %+.2f", offset) else "",
				run:designTime()
			)
			print("[DevLineup] " .. report)
			return report
		end
		RunService.RenderStepped:Wait()
	end
	return giveUp("timed out before " .. tostring(beat))
end

return Slice
