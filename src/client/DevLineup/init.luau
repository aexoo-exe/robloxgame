-- Studio-only: every roster unit's figure lined up far above the hub, one row per origin, with its
-- unit id over its head, to check looks (UnitLookConfig, CharacterLook) without playing a match.
-- Riders sit on their horses.
-- A close-up puts one unit on a preview stage in front of a target dummy, drawn and animated by the
-- same code as a fight (UnitView, CombatFx), so combat motion and effects can be triggered on
-- demand (AnimationConfig; `preview` sets the dummy distance, interval and amounts):
--   L        open or close the lineup
--   . / ,    close-up of the next / previous unit; also ] / [ and the Right / Left arrows, and
--            the Next / Prev buttons at the bottom of the screen
--   M        back to the whole lineup
-- Roblox's emotes menu binds "." and swallows it (the input arrives already processed), so while
-- the lineup is open the emotes menu is turned off and the step keys are taken even when processed
-- (never while typing in a text box). A key-help label shows while the lineup is open.
--   In a close-up:
--   1        attack the dummy (the unit's attack style; melee or ranged by its range)
--   2        a critical attack
--   3        the unit's real ability, as a fight plays it, on a small field of dummies (lines,
--            cones and areas show); each press shows its next cast (see `cast`)
--   4        get hit (the dummy attacks the unit)
--   5        stunned
--   6        death (the unit comes back after a moment)
--   7        victory cheer
--   8        healed and shielded (the shield ends after a moment)
--   9        auto: attack on the preview interval, with a crit every 4th and a cast every 6th
--   F        the unit's next form (its own look from FormLookConfig, or the base figure with the
--            form's tint), with the form's size; cycles back to the first form
--   X        next star level (effects grow with it)
--   Q        next effects quality (low, medium, high)
--   T        key 3's test arena: off (the field above the lineup), gray (a neutral matte stage,
--            neutral lighting, plain backdrop) or bright (the real arena board in the hub's look);
--            replays the shown cast there
--   C        the arena's fixed camera: gameplay (the match camera), close (3/4 on the caster and
--            its target) or wide (the whole field). In an arena the camera never shakes or drifts,
--            so every recording of a cast is framed the same.
--   G        as K, with the match camera's framing (the arena's "gameplay" camera, no orbit): the
--            slice the way players see it; S after it replays at 0.25x with that camera
--   K        the vertical slice (SLICE_UNIT): opens its close-up if needed and replays its
--            ultimate (its first cast) on key 3's field of dummies; S then replays that same
--            ultimate at 0.25x to study the timing (S on any other unit shows its next cast).
--            Both use the slice camera, an orbit locked on the caster / front target midpoint:
--            right-mouse drag or the arrows orbit, the wheel or + / - zoom, Q raises, E lowers,
--            P prints the framing and keeps it for this session's next K / S. It hands back the
--            previous camera 2 s after the replay ends.
--   R        the reel (ReelConfig): plays a batch of ultimates in one clip, hands off; R again
--            stops it. Per unit: a title card (id and tier), the ultimate at 1x, a pause, the
--            ultimate at 0.25x, a gap; then "REEL END". It forces its arena and camera, hides the
--            panel, and puts the arena, camera, lighting and time scale back when it ends. Other
--            keys are ignored while it plays.
-- Chat commands: /lineup (open or close), /look <unit_id> (close-up of that unit).
-- On opening, the output shows the part counts of the figures. Does nothing outside Studio.
-- Presentation only.
--
-- Modules (this folder): Config (fixed settings), State (shared state), Hud (the on-screen panel),
-- Lineup (the figures, close-ups, stepping), Stage (the close-up's preview stage and its keys),
-- TestArena (key 3's arenas and cameras), Field (key 3's preview fight, T, C), Slice (K, G, S and
-- the slice camera), Reel (R). This module wires the keys, chat commands and the QA handle.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TextChatService = game:GetService("TextChatService")
local UserInputService = game:GetService("UserInputService")

local Config = require(script.Config)
local Field = require(script.Field)
local Hud = require(script.Hud)
local Lineup = require(script.Lineup)
local Reel = require(script.Reel)
local Slice = require(script.Slice)
local Stage = require(script.Stage)
local State = require(script.State)
local TestArena = require(script.TestArena)

local CombatFx = require(script.Parent.CombatFx)
local ImpactEffects = require(script.Parent.ImpactEffects)
local UnitView = require(script.Parent.UnitView)
local Vfx = require(script.Parent.Vfx)
local VfxDebug = require(script.Parent.VfxDebug)

local DevLineup = {}

local PREVIEW = Config.PREVIEW
local stageClock = State.stageClock

local function close()
	Reel.finish()
	Slice.leave()
	Stage.close()
	Hud.close()
	-- Never leave the effects frozen (Dump FX / O) or slowed (S) after the lineup closes.
	State.timeScale = 1
	State.frozenScale = nil
	State.freezeButton = nil
	ImpactEffects.setTimeScale(1)
	if State.heartbeat then
		State.heartbeat:Disconnect()
		State.heartbeat = nil
	end
	if State.folder then
		State.folder:Destroy()
		State.folder = nil
	end
	table.clear(State.entries)
	State.focus = nil
	local saved = State.savedCamera
	if saved then
		local camera = workspace.CurrentCamera
		camera.CameraType = saved.cameraType
		camera.CFrame = saved.cframe
		State.savedCamera = nil
	end
end

local function toggle()
	if State.folder then
		close()
	else
		Lineup.open()
	end
end

local function command(alias: string, run: (string) -> ())
	local chatCommand = Instance.new("TextChatCommand")
	chatCommand.Name = "DevLineup" .. alias
	chatCommand.PrimaryAlias = "/" .. alias
	chatCommand.Triggered:Connect(function(_, text)
		run(string.match(text, "^%S+%s+(%S+)") or "")
	end)
	chatCommand.Parent = TextChatService
end

-- Preview keys, in a close-up.
local PREVIEW_KEYS: { [Enum.KeyCode]: (State.Stage) -> () } = {
	[Enum.KeyCode.One] = function(s)
		Stage.attack(s, false)
	end,
	[Enum.KeyCode.Two] = function(s)
		Stage.attack(s, true)
	end,
	[Enum.KeyCode.Three] = function(s)
		Field.cast(s)
	end,
	[Enum.KeyCode.Four] = Stage.getHit,
	[Enum.KeyCode.Five] = function(s)
		if UnitView.isAlive(s.actor) then
			CombatFx.stun(s.actor, PREVIEW.stun, true)
		end
	end,
	[Enum.KeyCode.Six] = Stage.die,
	[Enum.KeyCode.Seven] = function(s)
		if UnitView.isAlive(s.actor) then
			CombatFx.victory({ s.actor }, stageClock())
		end
	end,
	[Enum.KeyCode.Eight] = Stage.healAndShield,
	[Enum.KeyCode.Nine] = function(s)
		s.auto = not s.auto
		s.nextAuto = stageClock()
		print("[DevLineup] auto " .. (if s.auto then "on" else "off"))
	end,
	[Enum.KeyCode.F] = Stage.nextForm,
	[Enum.KeyCode.X] = Stage.nextStar,
	[Enum.KeyCode.Q] = function()
		Stage.nextQuality()
	end,
}

-- A handle for Studio scripts (the command bar, Studio MCP; DevLineupQA below) for visual checks:
-- show(unitId), ultimate(unitId) (shows it and plays its next cast, as key 3), press("One" ...
-- "Nine", "F", "X", "Q"), timeScale(0.25) for slow motion (0 freezes), freezeAfter(stageSeconds),
-- hold(beat, offset?, mode?) (the slice held at one beat of its ultimate) and resume(),
-- camera("front" | "side" | "close" | "board"; "close" also frames key 3's preview close on the
-- unit), state(), vfxReport() and vfxTest(seconds) (VfxDebug: effect textures). Studio only.
local function qaHandle()
	return {
		show = function(unitType: string)
			Lineup.showUnit(unitType)
		end,
		-- Shows the unit and plays its next cast (its ultimate) in the field preview, as key 3.
		ultimate = function(unitType: string)
			if not State.stage or State.stage.unitType ~= unitType then
				Lineup.showUnit(unitType)
			end
			local s = State.stage
			if s then
				Field.cast(s)
			end
		end,
		press = function(keyName: string)
			local key = (Enum.KeyCode :: any)[keyName]
			local s = State.stage
			if s and PREVIEW_KEYS[key] then
				if key ~= Enum.KeyCode.Three and key ~= Enum.KeyCode.Q then
					Field.endPreview(s)
				end
				PREVIEW_KEYS[key](s)
			end
		end,
		timeScale = function(scale: number)
			State.timeScale = scale
		end,
		freezeAfter = function(seconds: number)
			local s = State.stage
			if s then
				Stage.later(s, stageClock() + seconds, function()
					State.timeScale = 0
				end)
			end
		end,
		camera = function(mode: string)
			State.cameraMode = mode
			local s = State.stage
			if s then
				local distance = if Stage.rangeOf(s) > 1 then PREVIEW.rangedDistance else PREVIEW.meleeDistance
				s.stageCamera = Stage.framing(s, distance)
				s.camera = if s.fieldPreview and s.fieldFocus
					then TestArena.fieldFraming(s.fieldFocus)
					else s.stageCamera
			end
		end,
		-- Replays the slice and holds it at one beat (Slice.hold): hold("load"), hold("finisher", 0.05),
		-- hold(-0.5), hold("set", 0, "side" | "front34" | "back34" | "gameplay"), hold("load", 0, "side", 3)
		-- (the preview fight's third cast). Yields until held;
		-- returns what it held at.
		hold = function(beat: number | string, offset: number?, mode: string?, cast: number?)
			return Slice.hold(beat, offset, mode, cast)
		end,
		-- Goes on from a hold or a freeze (as O).
		resume = function()
			if State.timeScale == 0 then
				Hud.toggleFreeze()
			end
		end,
		state = function()
			local s = State.stage
			return {
				unit = if s then s.unitType else nil,
				star = if s then s.starLevel else nil,
				form = if s then s.formIndex else nil,
				time = State.stageTime,
				scale = State.timeScale,
				preview = s ~= nil and s.fieldPreview ~= nil,
				arena = State.arenaMode,
				arenaCamera = State.arenaCamera,
			}
		end,
		-- Effect texture checks (VfxDebug): the report, and every image shown in front of the camera.
		vfxReport = function()
			return VfxDebug.report()
		end,
		vfxTest = function(seconds: number?)
			return VfxDebug.test(seconds)
		end,
	}
end

function DevLineup.start()
	if not RunService:IsStudio() then
		return
	end
	State.step = Lineup.step -- the HUD's Prev / Next buttons
	-- The QA handle, reachable from Studio scripts as a BindableFunction on the local player:
	-- Players.LocalPlayer.DevLineupQA:Invoke("show", "unit_id"), :Invoke("press", "One"), ...
	local handle = qaHandle()
	local bindable = Instance.new("BindableFunction")
	bindable.Name = "DevLineupQA"
	bindable.OnInvoke = function(name: string, ...)
		local run = (handle :: any)[name]
		return if run then run(...) else nil
	end
	bindable.Parent = Players.LocalPlayer
	UserInputService.InputBegan:Connect(function(input, processed)
		if UserInputService:GetFocusedTextBox() then
			return -- typing (chat, a text box)
		end
		local key = input.KeyCode
		local stage = State.stage
		-- While the reel plays, only R (stop) does anything.
		if State.reelRunning then
			if key == Enum.KeyCode.R then
				Reel.finish()
			end
			return
		end
		-- While the slice camera is on, its keys (arrows, Q, E, P, + / -) are its controls only.
		if Slice.controlsBound() and Slice.KEYS[key] then
			return
		end
		-- Roblox's emotes menu (and the default camera, for the arrows) mark these keys processed:
		-- while the lineup is open they still step.
		if State.folder and Config.NEXT_KEYS[key] then
			Lineup.step(1)
			return
		elseif State.folder and Config.PREVIOUS_KEYS[key] then
			Lineup.step(-1)
			return
		end
		-- O is the default camera's zoom-out key and S a movement key: Roblox marks both processed,
		-- so while the lineup is open they are handled before that check.
		if State.folder and key == Enum.KeyCode.O and not UserInputService:GetFocusedTextBox() then
			Hud.toggleFreeze()
			return
		end
		if State.folder and key == Enum.KeyCode.S and stage then
			Slice.slowReplay(stage)
			return
		end
		if processed then
			return
		end
		if key == Enum.KeyCode.L then
			toggle()
		elseif key == Enum.KeyCode.V then
			-- A/B: every effect with its kit texture, or its neon fallback.
			Vfx.setEnabled(not Vfx.enabled())
			print("[DevLineup] kit textures: " .. (if Vfx.enabled() then "ON" else "OFF (neon fallback)"))
		elseif key == Enum.KeyCode.Period or key == Enum.KeyCode.RightBracket then
			Lineup.step(1)
		elseif key == Enum.KeyCode.Comma or key == Enum.KeyCode.LeftBracket then
			Lineup.step(-1)
		elseif key == Enum.KeyCode.M and State.folder then
			Lineup.overview()
		elseif key == Enum.KeyCode.T and stage then
			Field.nextArena(stage)
		elseif key == Enum.KeyCode.C and stage then
			Field.nextArenaCamera(stage)
		elseif key == Enum.KeyCode.R and State.folder then
			Reel.start()
		elseif key == Enum.KeyCode.K then
			Slice.replay("slice")
		elseif key == Enum.KeyCode.G then
			Slice.replay("gameplay")
		elseif stage and PREVIEW_KEYS[key] then
			if key ~= Enum.KeyCode.Three and key ~= Enum.KeyCode.Q then
				Field.endPreview(stage)
			end
			PREVIEW_KEYS[key](stage)
		end
	end)
	-- Chat commands work with the new chat (TextChatService) only.
	pcall(command, "lineup", function()
		toggle()
	end)
	pcall(command, "look", function(unitType)
		if unitType ~= "" then
			Lineup.showUnit(unitType)
		end
	end)
	print(
		"[DevLineup] Studio only: L opens the unit lineup; . ] Right / , [ Left (or the on-screen buttons) step through close-ups; M shows them all."
	)
end

return DevLineup
