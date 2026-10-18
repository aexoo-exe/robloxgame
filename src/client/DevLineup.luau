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
--   R        the reel (ReelConfig): plays a batch of ultimates in one clip, hands off; R again
--            stops it. Per unit: a title card (id and tier), the ultimate at 1x, a pause, the
--            ultimate at 0.25x, a gap; then "REEL END". It forces its arena and camera, hides the
--            panel, and puts the arena, camera, lighting and time scale back when it ends. Other
--            keys are ignored while it plays.
-- Chat commands: /lineup (open or close), /look <unit_id> (close-up of that unit).
-- On opening, the output shows the part counts of the figures. Does nothing outside Studio.
-- Presentation only.

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local TextChatService = game:GetService("TextChatService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AnimationConfig = require(Shared:WaitForChild("AnimationConfig"))
local BoardConfig = require(Shared:WaitForChild("BoardConfig"))
local CombatConfig = require(Shared:WaitForChild("CombatConfig"))
local CombatSim = require(Shared:WaitForChild("CombatSim"))
local Forms = require(Shared:WaitForChild("Forms"))
local Pve = require(Shared:WaitForChild("Pve"))
local HubConfig = require(Shared:WaitForChild("HubConfig"))
local RenderConfig = require(Shared:WaitForChild("RenderConfig"))
local UltimateConfig = require(Shared:WaitForChild("UltimateConfig"))
local UnitConfig = require(Shared:WaitForChild("UnitConfig"))

local CharacterLook = require(script.Parent.CharacterLook)
local AbilityFx = require(script.Parent.AbilityFx)
local CameraCues = require(script.Parent.CameraCues)
local Cinematic = require(script.Parent.Cinematic)
local Arena = require(script.Parent.Arena)
local CombatEffects = require(script.Parent.CombatEffects)
local CombatPlayback = require(script.Parent.CombatPlayback)
local CombatFx = require(script.Parent.CombatFx)
local Figure = require(script.Parent.Figure)
local ImpactEffects = require(script.Parent.ImpactEffects)
local ReelConfig = require(script.Parent.ReelConfig)
local UnitMotion = require(script.Parent.UnitMotion)
local UnitView = require(script.Parent.UnitView)
local Vfx = require(script.Parent.Vfx)
local VfxDebug = require(script.Parent.VfxDebug)

local DevLineup = {}

local ORIGIN_ORDER = { "Hunters", "Corps", "Spirit", "Cursed", "Arcane", "Titans", "Shinobi", "Crew", "Heroes" }
local BASE = HubConfig.center + Vector3.new(0, 260, 0) -- clear sky above the hub
local SPACING = 5.5 -- between units in a row
local ROW_GAP = 9
local HEIGHT = RenderConfig.unitSize.Y
local STAGE = BASE + Vector3.new(0, 0, -40) -- the preview stage, in front of the lineup
local PREVIEW = AnimationConfig.preview
local QUALITIES = { "low", "medium", "high" }
local DUMMY_COLOR = Color3.fromRGB(150, 150, 160)

-- Key 3's preview fight (cast): the unit in its side's front middle cell and dummies across from
-- it, in the dummies' own board coordinates (row 4 = their front): one in front, two beside it,
-- three behind and one further back, so lines, cones and areas all have targets to show on.
local FIELD_ORIGIN = STAGE + Vector3.new(0, 0, -60)
local FIELD_UNIT = { 4, 4 }
local FIELD_DUMMY = "placeholder_creep" -- a PvE creep's look; its stats are replaced
local FIELD_DUMMIES = { { 4, 4 }, { 5, 4 }, { 3, 4 }, { 4, 3 }, { 5, 3 }, { 3, 3 }, { 4, 2 } }
local FIELD_MANA = 12 -- the unit's mana bar in the preview fight (one attack fills most of it)
local FIELD_SECONDS = 25 -- how long the preview fight runs
local FIELD_AFTER = 3.5 -- seconds of the fight shown after the cast

-- Key 3's test arena (T) and its fixed cameras (C; arenaFraming).
local ARENA_MODES = { "off", "gray", "bright" }
local ARENA_CAMERAS = { "gameplay", "close", "wide" }
local GRAY_CENTER = HubConfig.center + Vector3.new(0, 700, 0) -- the board center in the gray arena
local GRAY_SIZE = 400 -- the gray arena's floor, and the box of walls around it
local GRAY_HEIGHT = 200
local GRAY_FLOOR = Color3.fromRGB(95, 95, 100) -- a true mid-gray
local GRAY_BACKDROP = Color3.fromRGB(122, 122, 128) -- a little lighter, so the horizon reads
local CLOSE_FILL = 0.6 -- the close camera: the caster and its target fill this much of the height
local GRAY_LIGHTING: { [string]: any } = {
	Ambient = Color3.fromRGB(110, 110, 110),
	OutdoorAmbient = Color3.fromRGB(128, 128, 128),
	Brightness = 2,
	ClockTime = 13,
	GeographicLatitude = 0,
	ColorShift_Top = Color3.new(0, 0, 0),
	ColorShift_Bottom = Color3.new(0, 0, 0),
	EnvironmentDiffuseScale = 0,
	EnvironmentSpecularScale = 0,
	ExposureCompensation = 0,
	ShadowSoftness = 0.6,
	GlobalShadows = true,
	FogStart = 0,
	FogEnd = 100000,
}

type Entry = {
	unitType: string,
	figure: Figure.Figure,
	root: CFrame,
	height: number,
	mounted: boolean,
}

-- The close-up's preview stage: the unit and a target dummy as fight views.
type Stage = {
	unitType: string,
	folder: Folder,
	actor: UnitView.UnitView,
	dummy: UnitView.UnitView,
	starLevel: number,
	formIndex: number, -- the form shown (UnitConfig forms), 1 for the first
	pending: { { at: number, run: () -> () } },
	dying: { UnitView.UnitView },
	auto: boolean,
	autoCount: number,
	nextAuto: number,
	camera: CFrame,
	stageCamera: CFrame, -- the stage's own framing (the camera returns to it after a field preview)
	fieldPreview: Folder?, -- key 3's preview fight, while it is shown
	fieldFocus: Vector3?, -- what its camera looks at
	fieldOffset: Vector3?, -- from the real arena cells to its cells
	castPresses: number,
}

local folder: Folder? = nil
local entries: { Entry } = {}
local focus: number? = nil
local stage: Stage? = nil
-- The stage runs on its own clock (stage seconds), so the preview can play in slow motion or freeze
-- (DevLineup QA handle, below).
local stageTime = 0
local timeScale = 1
local frozenScale: number? = nil -- the time scale before O froze the effects
local function stageClock(): number
	return stageTime
end
local cameraMode = "front" -- stage camera framing (stageFraming)
local arenaMode = "off" -- ARENA_MODES
local arenaCamera = "gameplay" -- ARENA_CAMERAS
local arenaRestore: (() -> ())? = nil -- undoes what the shown arena changed outside the stage
local titleText = "" -- the HUD title before the arena / camera suffix
-- The reel (R): running, a token that ends its loop when bumped, the modes it replaced, its card.
local reelRunning = false
local reelToken = 0
local reelSaved: { arena: string, camera: string }? = nil
local reelGui: ScreenGui? = nil
local reelCard: TextLabel? = nil
local heartbeat: RBXScriptConnection? = nil
local savedCamera: { cameraType: Enum.CameraType, cframe: CFrame }? = nil
local hud: ScreenGui? = nil
local hudTitle: TextLabel? = nil
local hudHelp: TextLabel? = nil
local emotesWereEnabled: boolean? = nil
local step: (number) -> () -- next / previous close-up (defined below)

-- Step keys: next and previous close-up.
local NEXT_KEYS = { [Enum.KeyCode.Period] = true, [Enum.KeyCode.RightBracket] = true, [Enum.KeyCode.Right] = true }
local PREVIOUS_KEYS = { [Enum.KeyCode.Comma] = true, [Enum.KeyCode.LeftBracket] = true, [Enum.KeyCode.Left] = true }

local OVERVIEW_HELP = "L close   . / ] / Right: next   , / [ / Left: previous"
local CLOSE_UP_HELP = table.concat({
	"L close   M lineup   . ] Right: next   , [ Left: previous",
	"1 attack   2 crit   3 real ability   4 get hit   5 stun   6 death   7 victory   8 heal + shield",
	"9 auto loop   F form   X star level   Q quality   V kit textures   S slow ultimate   O freeze + dump",
	"T arena (off / gray / bright)   C arena camera (gameplay / close / wide)   R reel (ReelConfig)",
}, "\n")

-- The HUD title, with the arena and its camera in a close-up ("gray / close").
local function refreshTitle()
	if hudTitle then
		local arena = if arenaMode == "off" then "arena off" else arenaMode .. " / " .. arenaCamera
		hudTitle.Text = if stage then titleText .. "   " .. arena else titleText
	end
end

-- Shows the key help and the title (the unit in a close-up) on the lineup's on-screen panel.
local function setHud(title: string, help: string)
	titleText = title
	if hudHelp then
		hudHelp.Text = help
	end
	refreshTitle()
end

-- Freezes every live effect (time 0, particles too) and prints each instance (VfxDebug.dumpLive);
-- called again, resumes. The "Dump FX" button and the O key.
local freezeButton: TextButton? = nil
local function toggleFreeze()
	if timeScale ~= 0 then
		frozenScale = timeScale
		timeScale = 0
		ImpactEffects.setTimeScale(0)
		print("[DevLineup] effects frozen (Dump FX / O again to resume)")
		local ok, problem = pcall(VfxDebug.dumpLive)
		if not ok then
			warn("[DevLineup] live-effects dump failed: " .. tostring(problem))
		end
	else
		timeScale = frozenScale or 1
		ImpactEffects.setTimeScale(timeScale)
		print("[DevLineup] effects resumed")
	end
	if freezeButton then
		freezeButton.Text = if timeScale == 0 then "Resume" else "Dump FX"
	end
end

local function hudButton(parent: Instance, text: string, x: number, by: number | () -> ()): TextButton
	local button = Instance.new("TextButton")
	button.AnchorPoint = Vector2.new(0.5, 1)
	button.Position = UDim2.new(0.5, x, 1, -16)
	button.Size = UDim2.fromOffset(96, 40)
	button.BackgroundColor3 = Color3.fromRGB(40, 44, 54)
	button.BackgroundTransparency = 0.15
	button.TextColor3 = Color3.new(1, 1, 1)
	button.Font = Enum.Font.GothamBold
	button.TextSize = 16
	button.Text = text
	button.AutoButtonColor = true
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = button
	button.Activated:Connect(function()
		if type(by) == "function" then
			by()
		else
			step(by)
		end
	end)
	button.Parent = parent
	return button
end

-- The on-screen panel while the lineup is open: Prev / Next buttons, the shown unit, key help.
local function openHud()
	local gui = Instance.new("ScreenGui")
	gui.Name = "DevLineupHud"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 50
	hudButton(gui, "< Prev", -110, -1)
	hudButton(gui, "Next >", 110, 1)
	freezeButton = hudButton(gui, "Dump FX", 220, toggleFreeze)
	local title = Instance.new("TextLabel")
	title.AnchorPoint = Vector2.new(0.5, 1)
	-- Above the buttons, wide enough for the arena / camera suffix.
	title.Position = UDim2.new(0.5, 0, 1, -62)
	title.Size = UDim2.fromOffset(460, 24)
	title.BackgroundTransparency = 1
	title.TextColor3 = Color3.new(1, 1, 1)
	title.TextStrokeTransparency = 0.3
	title.Font = Enum.Font.GothamBold
	title.TextSize = 18
	title.Parent = gui
	local help = Instance.new("TextLabel")
	help.AnchorPoint = Vector2.new(0, 1)
	help.Position = UDim2.new(0, 12, 1, -66)
	help.Size = UDim2.fromOffset(560, 80)
	help.BackgroundColor3 = Color3.fromRGB(20, 22, 28)
	help.BackgroundTransparency = 0.35
	help.TextColor3 = Color3.fromRGB(230, 232, 240)
	help.Font = Enum.Font.Gotham
	help.TextSize = 13
	help.TextXAlignment = Enum.TextXAlignment.Left
	help.TextYAlignment = Enum.TextYAlignment.Top
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 8)
	padding.PaddingTop = UDim.new(0, 6)
	padding.Parent = help
	help.Parent = gui
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	hud, hudTitle, hudHelp = gui, title, help
	-- The reel's title card: large white text on a black bar across the top, readable in a
	-- compressed recording. Its own gui, so it stays while the panel is hidden.
	local cardGui = Instance.new("ScreenGui")
	cardGui.Name = "DevLineupReelCard"
	cardGui.ResetOnSpawn = false
	cardGui.IgnoreGuiInset = true
	cardGui.DisplayOrder = 100
	cardGui.Enabled = false
	local card = Instance.new("TextLabel")
	card.Size = UDim2.new(1, 0, 0, 150)
	card.BackgroundColor3 = Color3.new(0, 0, 0)
	card.BackgroundTransparency = 0
	card.BorderSizePixel = 0
	card.TextColor3 = Color3.new(1, 1, 1)
	card.Font = Enum.Font.GothamBlack
	card.TextSize = 72
	card.Parent = cardGui
	cardGui.Parent = gui.Parent
	reelGui, reelCard = cardGui, card
	-- The emotes menu takes "."; off while the lineup is open.
	local ok, enabled = pcall(StarterGui.GetCoreGuiEnabled, StarterGui, Enum.CoreGuiType.EmotesMenu)
	if ok then
		emotesWereEnabled = enabled
		pcall(StarterGui.SetCoreGuiEnabled, StarterGui, Enum.CoreGuiType.EmotesMenu, false)
	end
end

local function closeHud()
	if hud then
		hud:Destroy()
	end
	hud, hudTitle, hudHelp = nil, nil, nil
	if reelGui then
		reelGui:Destroy()
	end
	reelGui, reelCard = nil, nil
	if emotesWereEnabled ~= nil then
		pcall(StarterGui.SetCoreGuiEnabled, StarterGui, Enum.CoreGuiType.EmotesMenu, emotesWereEnabled)
		emotesWereEnabled = nil
	end
end

-- Roster unit ids in rows: one row per origin (in ORIGIN_ORDER, then any others), by cost then id.
local function rows(): { { string } }
	local byOrigin: { [string]: { string } } = {}
	for unitType, unit in UnitConfig do
		if type(unit) == "table" and unit.origin then
			byOrigin[unit.origin] = byOrigin[unit.origin] or {}
			table.insert(byOrigin[unit.origin], unitType)
		end
	end
	local order = table.clone(ORIGIN_ORDER)
	local extra = {}
	for origin in byOrigin do
		if not table.find(order, origin) then
			table.insert(extra, origin)
		end
	end
	table.sort(extra)
	table.move(extra, 1, #extra, #order + 1, order)
	local result = {}
	for _, origin in order do
		local ids = byOrigin[origin]
		if ids then
			table.sort(ids, function(a, b)
				local costA, costB = UnitConfig[a].cost, UnitConfig[b].cost
				return if costA ~= costB then costA < costB else a < b
			end)
			table.insert(result, ids)
		end
	end
	return result
end

local function pose(figure: Figure.Figure): Figure.Pose
	return {
		bob = 0,
		lean = 0,
		fall = 0,
		leftArm = figure.restArms[1],
		rightArm = figure.restArms[2],
		leftLeg = 0,
		rightLeg = 0,
		stride = 0,
	}
end

local function place(entry: Entry, p: Figure.Pose)
	Figure.place(entry.figure, entry.root * CFrame.new(0, entry.height / 2, 0), entry.root, p)
end

local function setCamera(cframe: CFrame)
	local camera = workspace.CurrentCamera
	camera.CameraType = Enum.CameraType.Scriptable
	camera.CFrame = cframe
end

-- Preview stage ----------------------------------------------------------------------------------

-- The unit's current form, its range in that form, and its attack style.
local function formOf(s: Stage): any?
	local forms = UnitConfig[s.unitType].forms
	return if forms then forms[s.formIndex] else nil
end
local function rangeOf(s: Stage): number
	return Forms.range(UnitConfig[s.unitType], formOf(s))
end
local function styleOf(s: Stage): string
	local form = formOf(s)
	return UnitMotion.styleFor(s.unitType, rangeOf(s), CharacterLook.of(s.unitType).figure, form and form.name)
end

local function later(s: Stage, at: number, run: () -> ())
	table.insert(s.pending, { at = at, run = run })
end

-- The stage camera for the current CAMERA_MODES entry (`cameraMode`): the unit stands at STAGE
-- facing -X toward the dummy `distance` studs away.
--   front  a three-quarter view of the unit's front, the dummy beside it (the default)
--   side   both from the side, square on to the line between them
--   close  the unit's head and shoulders, from the front
--   board  the normal board camera's angle and distance
local function stageFraming(s: Stage, distance: number): CFrame
	local height = HEIGHT * CharacterLook.of(s.unitType).scale * RenderConfig.starSizeScale[s.starLevel]
	local chest = STAGE + Vector3.new(0, height * 0.55, 0)
	local size = height / HEIGHT
	if cameraMode == "side" then
		local middle = STAGE - Vector3.new(distance / 2, -HEIGHT * 0.45, 0)
		return CFrame.lookAt(middle + Vector3.new(0, 2.5 + distance * 0.1, -(7 + distance * 0.75)), middle)
	elseif cameraMode == "close" then
		local head = STAGE + Vector3.new(0, height * 0.8, 0)
		return CFrame.lookAt(head + Vector3.new(-3.2, 0.4, -2.2) * size, head)
	elseif cameraMode == "board" then
		local middle = STAGE - Vector3.new(distance / 2, 0, 0)
		return CFrame.lookAt(middle + RenderConfig.cameraOffset, middle)
	end
	return CFrame.lookAt(chest + Vector3.new(-6.5, 1.4, -6.5) * size, chest - Vector3.new(1.5, 0, 0))
end

-- Places the unit and the dummy (the dummy in front at melee or ranged distance) and frames them.
local function spawnActors(s: Stage)
	local look = CharacterLook.of(s.unitType)
	local ranged = rangeOf(s) > 1
	local distance = if ranged then PREVIEW.rangedDistance else PREVIEW.meleeDistance
	local form = formOf(s)
	-- The unit faces -X toward the dummy; the camera looks at both from the front (-Z).
	local actor = UnitView.new(look.name, s.starLevel, look.color, STAGE, s.folder, {
		sizeScale = look.scale,
		look = look.figure,
		maxHealth = PREVIEW.health,
		mana = 0,
		maxMana = 100,
		yaw = math.pi / 2,
		formLook = if form then RenderConfig.formLooks[form.name] else nil,
		formName = if form then form.name else nil,
		clock = stageClock,
	})
	if not s.dummy or not s.dummy.part.Parent then
		s.dummy = UnitView.new("dummy", 1, DUMMY_COLOR, STAGE - Vector3.new(distance, 0, 0), s.folder, {
			look = { style = "creep" } :: any,
			maxHealth = PREVIEW.health,
			yaw = -math.pi / 2,
			starPips = false,
			clock = stageClock,
		})
	else
		UnitView.moveTo(s.dummy, STAGE - Vector3.new(distance, 0, 0))
	end
	actor.part:SetAttribute("UnitType", s.unitType)
	UnitView.face(actor, s.dummy)
	UnitView.face(s.dummy, actor)
	s.actor = actor
	s.stageCamera = stageFraming(s, distance)
	s.camera = s.stageCamera
	print(
		string.format(
			"[DevLineup] %s %d-star, style %s (%s), form %s",
			s.unitType,
			s.starLevel,
			styleOf(s),
			if ranged then "ranged" else "melee",
			if form then form.name else "none"
		)
	)
end

-- Test arena (T, C) ---------------------------------------------------------------------------------

-- Undoes what the shown arena changed outside the stage (lighting, the real board's parent).
local function leaveArena()
	local restore = arenaRestore
	arenaRestore = nil
	if restore then
		restore()
	end
end

local function slab(parent: Instance, size: Vector3, at: Vector3, color: Color3)
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false -- the backdrop never shades the stage
	part.Size = size
	part.CFrame = CFrame.new(at)
	part.Color = color
	part.Material = Enum.Material.SmoothPlastic
	part.Reflectance = 0
	part.Parent = parent
end

-- Neutral lighting for the gray arena: GRAY_LIGHTING, without atmosphere or color grading (bloom
-- stays, as effects are drawn for it). Returns what puts the hub's lighting back.
local function neutralLighting(): () -> ()
	local saved: { [string]: any } = {}
	for name, value in GRAY_LIGHTING do
		saved[name] = (Lighting :: any)[name]
		;(Lighting :: any)[name] = value
	end
	local removed, disabled = {}, {}
	for _, child in Lighting:GetChildren() do
		if child:IsA("Atmosphere") then
			table.insert(removed, child)
			child.Parent = nil
		elseif child:IsA("PostEffect") and not child:IsA("BloomEffect") and child.Enabled then
			table.insert(disabled, child)
			child.Enabled = false
		end
	end
	return function()
		for name, value in saved do
			(Lighting :: any)[name] = value
		end
		for _, child in removed do
			child.Parent = Lighting
		end
		for _, effect in disabled do
			effect.Enabled = true
		end
	end
end

-- Builds the field preview's ground for `arenaMode` in `parent` and returns the offset from the real
-- arena cells to the field's (CombatPlayback.preview).
--   off     a small floor above the lineup (FIELD_ORIGIN)
--   gray    a mid-gray matte floor in a closed box of plain backdrop, far above the hub, in
--           neutral lighting (no hub props in sight)
--   bright  the real arena board, in place, in the hub's own lighting
local function buildArena(parent: Instance): Vector3
	if arenaMode == "bright" then
		local board = Arena.folder
		if board and board.Parent == nil then -- hidden outside a match
			board.Parent = workspace
			arenaRestore = function()
				board.Parent = nil
			end
		end
		return Vector3.zero
	elseif arenaMode == "gray" then
		local offset = GRAY_CENTER - RenderConfig.arenaCenter
		local floorTop = Arena.cellPosition(1, 1).Y + offset.Y
		local x, z, half = GRAY_CENTER.X, GRAY_CENTER.Z, GRAY_SIZE / 2
		slab(parent, Vector3.new(GRAY_SIZE, 1, GRAY_SIZE), Vector3.new(x, floorTop - 0.5, z), GRAY_FLOOR)
		local wallY = floorTop + GRAY_HEIGHT / 2
		slab(parent, Vector3.new(GRAY_SIZE, GRAY_HEIGHT, 1), Vector3.new(x, wallY, z - half), GRAY_BACKDROP)
		slab(parent, Vector3.new(GRAY_SIZE, GRAY_HEIGHT, 1), Vector3.new(x, wallY, z + half), GRAY_BACKDROP)
		slab(parent, Vector3.new(1, GRAY_HEIGHT, GRAY_SIZE), Vector3.new(x - half, wallY, z), GRAY_BACKDROP)
		slab(parent, Vector3.new(1, GRAY_HEIGHT, GRAY_SIZE), Vector3.new(x + half, wallY, z), GRAY_BACKDROP)
		slab(parent, Vector3.new(GRAY_SIZE, 1, GRAY_SIZE), Vector3.new(x, floorTop + GRAY_HEIGHT, z), GRAY_BACKDROP)
		arenaRestore = neutralLighting()
		return offset
	end
	local offset = FIELD_ORIGIN - Arena.cellPosition(FIELD_UNIT[1], FIELD_UNIT[2])
	local floor = Instance.new("Part")
	floor.Anchored = true
	floor.CanCollide = false
	floor.CanQuery = false
	floor.Size = Vector3.new(44, 1, 44)
	floor.CFrame = CFrame.new(Arena.cellPosition(4, BoardConfig.rows + 1) + offset - Vector3.new(0, 0.5, 0))
	floor.Color = Color3.fromRGB(64, 68, 76)
	floor.Material = Enum.Material.SmoothPlastic
	floor.Parent = parent
	return offset
end

-- The arena's fixed cameras (arenaCamera), from the field's cells only, so every cast of every unit
-- is framed the same:
--   gameplay  the match camera's angle and distance (Arena.boardCamera)
--   close     a 3/4 view from behind the caster's side, the caster and the dummy in front of it
--             together filling CLOSE_FILL of the frame height (sized to the caster's height)
--   wide      high and to the side over the whole field: the full area of an ultimate
local function arenaFraming(s: Stage, offset: Vector3): CFrame
	if arenaCamera == "gameplay" then
		return Arena.boardCamera() + offset
	end
	local caster = Arena.cellPosition(FIELD_UNIT[1], FIELD_UNIT[2]) + offset
	if arenaCamera == "close" then
		local target = Arena.cellPosition(FIELD_UNIT[1], BoardConfig.rows + 1) + offset
		local height = HEIGHT * CharacterLook.of(s.unitType).scale * RenderConfig.starSizeScale[s.starLevel]
		local between = caster:Lerp(target, 0.5) + Vector3.new(0, height * 0.5, 0)
		-- What must fill the frame: the caster's height, plus the rise of the target behind it.
		local shown = height + 1.5
		local fov = math.rad(workspace.CurrentCamera.FieldOfView)
		local distance = math.max(shown / (CLOSE_FILL * 2 * math.tan(fov / 2)), 8)
		return CFrame.lookAt(between + Vector3.new(-13, 10, 17).Unit * distance, between)
	end
	local center = RenderConfig.arenaCenter + offset
	center = Vector3.new(center.X, caster.Y, center.Z)
	return CFrame.lookAt(center + Vector3.new(-30, 44, 46), center)
end

local function closeStage()
	local s = stage
	if not s then
		return
	end
	stage = nil
	if s.fieldPreview then
		CombatPlayback.stop()
	end
	leaveArena()
	CombatEffects.clear()
	ImpactEffects.clear()
	CombatEffects.setClock(nil)
	ImpactEffects.setClock(nil)
	CameraCues.setClock(nil)
	CameraCues.clear()
	s.folder:Destroy() -- every view of the stage is inside it
end

local function openStage(unitType: string)
	closeStage()
	local stageFolder = Instance.new("Folder")
	stageFolder.Name = "DevLineupStage"
	local floor = Instance.new("Part")
	floor.Anchored = true
	floor.CanCollide = false
	floor.CanQuery = false
	floor.Size = Vector3.new(36, 1, 14)
	floor.CFrame = CFrame.new(STAGE + Vector3.new(-5, -0.5, 0))
	floor.Color = Color3.fromRGB(70, 74, 82)
	floor.Material = Enum.Material.SmoothPlastic
	floor.Parent = stageFolder
	stageFolder.Parent = workspace
	local s: Stage = {
		unitType = unitType,
		folder = stageFolder,
		actor = nil :: any,
		dummy = nil :: any,
		starLevel = 1,
		formIndex = 1,
		pending = {},
		dying = {},
		auto = false,
		autoCount = 0,
		nextAuto = 0,
		camera = CFrame.identity,
		stageCamera = CFrame.identity,
		fieldPreview = nil,
		castPresses = 0,
	}
	stage = s
	CombatEffects.setClock(stageClock)
	ImpactEffects.setClock(stageClock)
	CameraCues.setClock(stageClock)
	spawnActors(s)
	print("[DevLineup] keys: 1 attack, 2 crit, 3 cast, 4 get hit, 5 stun, 6 death, 7 victory, 8 heal + shield,")
	print(
		"[DevLineup]       9 auto loop, F form, X star level, Q quality (now "
			.. ImpactEffects.quality()
			.. "), V kit textures (now "
			.. (if Vfx.enabled() then "on" else "off")
			.. "), S ultimate at 0.25x"
	)
end

-- The unit attacks the dummy; the hit lands as the motion strikes (or the projectile arrives).
local function attack(s: Stage, crit: boolean)
	local actor, dummy = s.actor, s.dummy
	if not UnitView.isAlive(actor) then
		return
	end
	local style = styleOf(s)
	local ranged = rangeOf(s) > 1
	local plan = CombatFx.plan(style, PREVIEW.interval, ranged)
	local landsAt = stageClock() + CombatFx.leadTime(plan)
	local tongue = RenderConfig.tongueAttacks[s.unitType] == true
	CombatFx.attack(actor, dummy, landsAt, plan, {
		color = if tongue then RenderConfig.tongueColor else AnimationConfig.projectiles.ownColor,
		tongue = tongue,
	})
	later(s, landsAt, function()
		CombatFx.hit(dummy, actor, {
			damage = if crit then PREVIEW.critDamage else PREVIEW.damage,
			crit = crit,
			slam = UnitMotion.style(style).slam == true,
		})
	end)
end

-- A quick generic cast on the stage (the auto loop): wind-up, release and an ability hit on the
-- dummy, in the unit's element color.
local function quickCast(s: Stage)
	local actor, dummy = s.actor, s.dummy
	if not UnitView.isAlive(actor) then
		return
	end
	local color = AbilityFx.styleOf(s.unitType, CombatFx.factionColor(s.unitType)).primary
	local now = stageClock()
	local release = now + AnimationConfig.cast.windup
	CombatFx.castWindup(actor, now, release, color)
	later(s, release, function()
		CombatFx.castRelease(actor, color)
	end)
	later(s, release + 0.05, function()
		CombatFx.hit(dummy, actor, {
			damage = PREVIEW.abilityDamage,
			damageType = "MAGIC",
			ability = true,
			abilityColor = color,
		})
	end)
end

-- The real ability (key 3) ------------------------------------------------------------------------

-- Leaves the field preview: the playback ends and the stage's unit and dummy come back.
local function endFieldPreview(s: Stage)
	if not s.fieldPreview then
		return
	end
	CombatPlayback.stop() -- also resets the effects' clocks: back to the stage's
	CombatEffects.setClock(stageClock)
	ImpactEffects.setClock(stageClock)
	CameraCues.setClock(stageClock)
	s.fieldPreview:Destroy()
	s.fieldPreview = nil
	s.fieldOffset = nil
	leaveArena()
	s.actor.part.Parent = s.folder
	s.dummy.part.Parent = s.folder
	s.camera = s.stageCamera
end

-- The field preview's camera: from behind the unit's side, closer than the board camera (camera
-- mode "board": at the board camera's own angle and distance).
local function fieldFraming(focusPoint: Vector3): CFrame
	if cameraMode == "board" then
		return CFrame.lookAt(focusPoint + RenderConfig.cameraOffset, focusPoint)
	elseif cameraMode == "close" then
		-- Close on the unit, looking past it toward the dummies (an ultimate close-up).
		local unitAt = FIELD_ORIGIN + Vector3.new(0, 2, 0)
		return CFrame.lookAt(unitAt + Vector3.new(-7, 4, 9), unitAt:Lerp(focusPoint, 0.4))
	end
	return CFrame.lookAt(focusPoint + Vector3.new(0, 11, 15), focusPoint)
end

-- Runs a short fight between the unit and FIELD_DUMMIES with CombatSim, on private copies of the
-- stats (the unit's mana bar shortened so it casts after one attack, then every few attacks; the
-- dummies tough, harmless and standing still). Nothing it runs reaches the server or any real
-- fight. Returns the result, the unit's index and its Cast events, or nil if it never casts.
local function fieldFight(s: Stage): (any?, number?, { any })
	local stats = table.clone(UnitConfig[s.unitType])
	stats.maxMana = math.min(stats.maxMana or FIELD_MANA, FIELD_MANA)
	stats.startingMana = stats.maxMana - 1
	local dummy = table.clone(Pve.pveUnitType(FIELD_DUMMY))
	dummy.health = 1e6
	dummy.attackDamage = 0
	dummy.attacksPerSecond = 0.001
	dummy.range = 12 -- every target in reach: dummies never walk
	local dummies = {}
	for i, cell in FIELD_DUMMIES do
		table.insert(dummies, { id = "dummy" .. i, unitType = FIELD_DUMMY, column = cell[1], row = cell[2] })
	end
	local ok, result = pcall(CombatSim.run, {
		boards = {
			{
				{
					id = "unit",
					unitType = s.unitType,
					starLevel = s.starLevel,
					column = FIELD_UNIT[1],
					row = FIELD_UNIT[2],
				},
			},
			dummies,
		},
		columns = BoardConfig.columns,
		rows = BoardConfig.rows,
		unitTypes = { [s.unitType] = stats, [FIELD_DUMMY] = dummy },
		ticksPerSecond = CombatConfig.ticksPerSecond,
		maxTicks = CombatConfig.ticksPerSecond * FIELD_SECONDS,
		critChance = 0,
		seed = 7,
	})
	if not ok then
		warn("[DevLineup] the preview fight failed: " .. tostring(result))
		return nil, nil, {}
	end
	local actorIndex, sides = nil, {}
	for _, unit in result.units do
		sides[unit.index] = unit.side
		if unit.side == 1 then
			actorIndex = unit.index
		end
	end
	-- The dummies' own attacks and steps are left out of the playback.
	local events, casts = {}, {}
	for _, event in result.events do
		local dummyAct = sides[event.unit] == 2 and (event.kind == "Attack" or event.kind == "Move")
		if not dummyAct then
			table.insert(events, event)
			if event.kind == "Cast" and event.unit == actorIndex then
				table.insert(casts, event)
			end
		end
	end
	result.events = events
	return result, actorIndex, casts
end

-- Key 3: the unit's real ability, as a fight plays it, against several dummies on a small field so
-- its lines, cones and areas show. Each press shows its next cast (forms that change with casts
-- step up); the playback starts just before the cast's wind-up. Returns whether a cast plays.
local function cast(s: Stage): boolean
	endFieldPreview(s)
	local result, _, casts = fieldFight(s)
	if not result or #casts == 0 then
		print("[DevLineup] " .. s.unitType .. " did not cast in the preview fight")
		return false
	end
	s.castPresses += 1
	local index = (s.castPresses - 1) % #casts + 1
	local castEvent = casts[index]
	local ticks = result.ticksPerSecond
	local castAt = castEvent.tick / ticks
	-- Only this cast and what follows it for a few seconds.
	local endTick = castEvent.tick + math.floor(FIELD_AFTER * ticks)
	local kept = {}
	for _, event in result.events do
		if event.tick <= endTick then
			table.insert(kept, event)
		end
	end
	result.events = kept
	result.endTick = endTick
	result.winner = nil
	local from = castAt - AbilityFx.windupLength(s.unitType) - 0.5

	-- The field: the arena's ground (T: buildArena) under the arena cells, shifted by `offset`.
	local fieldFolder = Instance.new("Folder")
	fieldFolder.Name = "FieldPreview"
	local offset = buildArena(fieldFolder)
	local middle = Arena.cellPosition(4, BoardConfig.rows + 1) + offset
	fieldFolder.Parent = s.folder
	s.fieldPreview = fieldFolder
	s.fieldOffset = offset
	s.actor.part.Parent = nil
	s.dummy.part.Parent = nil
	-- Frame the unit and the dummies from behind the unit's side, as the board camera does (in an
	-- arena: its fixed camera).
	s.fieldFocus = FIELD_ORIGIN:Lerp(middle, 0.6)
	s.camera = if arenaMode == "off" then fieldFraming(s.fieldFocus) else arenaFraming(s, offset)
	local startedAt = stageClock()
	CombatPlayback.preview(result, fieldFolder, offset, from, function()
		return from + (stageClock() - startedAt)
	end)
	print(
		string.format(
			"[DevLineup] %s: cast %d of %d in the preview fight (at %.1f s)",
			s.unitType,
			index,
			#casts,
			castAt
		)
	)
	local ultimate = UltimateConfig.units[s.unitType]
	if ultimate and ultimate.look ~= "" then
		print(string.format("[Ultimate] %s (tier %d): %s", s.unitType, ultimate.tier, ultimate.look))
	end
	return true
end

-- The dummy attacks the unit.
local function getHit(s: Stage)
	local actor, dummy = s.actor, s.dummy
	if not UnitView.isAlive(actor) then
		return
	end
	local plan = CombatFx.plan("brawler", PREVIEW.interval, false)
	local landsAt = stageClock() + CombatFx.leadTime(plan)
	CombatFx.attack(dummy, actor, landsAt, plan)
	later(s, landsAt, function()
		CombatFx.hit(actor, dummy, { damage = PREVIEW.damage })
	end)
end

local function die(s: Stage)
	local actor = s.actor
	if not UnitView.isAlive(actor) then
		return
	end
	CombatFx.death(actor, s.dummy)
	table.insert(s.dying, actor)
	later(s, stageClock() + AnimationConfig.death.duration + 0.8, function()
		spawnActors(s)
	end)
end

local function healAndShield(s: Stage)
	local actor = s.actor
	if not UnitView.isAlive(actor) then
		return
	end
	CombatFx.heal(actor, PREVIEW.heal)
	UnitView.setShield(actor, PREVIEW.shield)
	CombatFx.shield(actor)
	later(s, stageClock() + 2.5, function()
		if UnitView.isAlive(actor) then
			UnitView.setShield(actor, 0)
		end
	end)
end

-- Rebuilds the unit (same form) at its next star level.
local function nextStar(s: Stage)
	if not UnitView.isAlive(s.actor) then
		return
	end
	UnitView.destroy(s.actor)
	s.starLevel = s.starLevel % 3 + 1
	spawnActors(s)
end

-- The unit's next form, shown as a fight shows a form change.
local function nextForm(s: Stage)
	local forms = UnitConfig[s.unitType].forms
	if not forms or #forms < 2 then
		print("[DevLineup] " .. s.unitType .. " has no forms")
		return
	end
	if not UnitView.isAlive(s.actor) then
		return
	end
	s.formIndex = s.formIndex % #forms + 1
	local form = forms[s.formIndex]
	local formLook = RenderConfig.formLooks[form.name]
	-- A unit whose ultimate draws its real form changes (Cinematic.shift) plays it here too.
	local actor = s.actor
	Cinematic.shift(
		{
			views = { actor },
			toWorld = function()
				return STAGE
			end,
			now = stageClock,
			ticksPerSecond = CombatConfig.ticksPerSecond,
			events = {},
			summonerOf = function()
				return nil
			end,
		},
		1,
		s.unitType,
		actor,
		AbilityFx.styleOf(s.unitType, CombatFx.factionColor(s.unitType)),
		{
			kind = "Form",
			unit = 1,
			formIndex = s.formIndex,
			form = form.name,
		}
	)
	UnitView.setForm(s.actor, formLook, nil, nil, form.name)
	local _, own = CharacterLook.formFigure(CharacterLook.of(s.unitType).figure, form.name)
	print(
		string.format(
			"[DevLineup] %s: form %d/%d %q, %s, %d parts, style %s",
			s.unitType,
			s.formIndex,
			#forms,
			form.name,
			if own then "own look" elseif formLook and formLook.tint then "base figure, tinted" else "base figure",
			#s.actor.figure.parts - 1,
			styleOf(s)
		)
	)
	-- A form can change the range: move the dummy to match.
	local distance = if rangeOf(s) > 1 then PREVIEW.rangedDistance else PREVIEW.meleeDistance
	UnitView.moveTo(s.dummy, STAGE - Vector3.new(distance, 0, 0))
end

local function nextQuality()
	local index = table.find(QUALITIES, ImpactEffects.quality()) or 0
	local name = QUALITIES[index % #QUALITIES + 1]
	ImpactEffects.setQuality(name)
	print("[DevLineup] effects quality: " .. name .. " (charge sparkles apply to units built after this)")
end

local function cycle(list: { string }, current: string): string
	local index = table.find(list, current) or 0
	return list[index % #list + 1]
end

-- T: the next test arena; a shown cast plays again in it.
local function nextArena(s: Stage)
	arenaMode = cycle(ARENA_MODES, arenaMode)
	print("[DevLineup] arena: " .. arenaMode)
	if s.fieldPreview then
		s.castPresses -= 1 -- the same cast again
		cast(s)
	end
	refreshTitle()
end

-- C: the arena's next fixed camera, applied to a shown cast at once.
local function nextArenaCamera(s: Stage)
	arenaCamera = cycle(ARENA_CAMERAS, arenaCamera)
	print("[DevLineup] arena camera: " .. arenaCamera .. (if arenaMode == "off" then " (T: an arena to use it)" else ""))
	if s.fieldPreview and s.fieldOffset and arenaMode ~= "off" then
		s.camera = arenaFraming(s, s.fieldOffset)
	end
	refreshTitle()
end

local function updateStage(s: Stage, now: number, dt: number)
	for i = #s.pending, 1, -1 do
		local job = s.pending[i]
		if now >= job.at then
			table.remove(s.pending, i)
			job.run()
		end
	end
	if stage ~= s then
		return -- a job closed the stage
	end
	if s.auto and now >= s.nextAuto then
		s.nextAuto = now + PREVIEW.interval
		s.autoCount += 1
		if s.autoCount % 6 == 0 then
			quickCast(s)
		else
			attack(s, s.autoCount % 4 == 0)
		end
	end
	if s.actor.part.Parent and UnitView.isAlive(s.actor) then
		UnitView.update(s.actor, now, dt)
	end
	UnitView.update(s.dummy, now, dt)
	for i = #s.dying, 1, -1 do
		if not UnitView.update(s.dying[i], now, dt) then
			UnitView.destroy(s.dying[i])
			table.remove(s.dying, i)
		end
	end
	if not s.fieldPreview then
		CombatEffects.update(now) -- a field preview's playback updates its own effects
	end
	if s.fieldPreview and arenaMode ~= "off" then
		setCamera(s.camera) -- an arena's fixed camera: no shake, no cues, no drift
	else
		setCamera(s.camera * ImpactEffects.shakeOffset() * CameraCues.offset(s.camera))
	end
end

-- Lineup -------------------------------------------------------------------------------------------

local function overview()
	closeStage()
	focus = nil
	local count = #rows()
	local middle = BASE + Vector3.new(0, 0, (count - 1) * ROW_GAP / 2)
	setCamera(CFrame.lookAt(middle + Vector3.new(0, 48, -52), middle))
	setHud(string.format("Lineup (%d)", #entries), OVERVIEW_HELP)
end

local function closeUp(index: number)
	focus = index
	local entry = entries[index]
	print(string.format("[DevLineup] %s (%d/%d)", entry.unitType, index, #entries))
	openStage(entry.unitType)
	setHud(string.format("%s (%d/%d)", entry.unitType, index, #entries), CLOSE_UP_HELP)
end

local function report()
	local total, most, mostId, looks, lookParts = 0, 0, "", 0, 0
	for _, entry in entries do
		local parts = #entry.figure.parts - 1 -- the hitbox is not drawn
		if entry.mounted then
			print(string.format("[DevLineup] %s: %d parts with its horse", entry.unitType, parts))
		end
		local avatar = entry.figure.avatar
		if entry.figure.modelKey then
			-- Facing check from the model data's face clue (z < 0: the face is at the front).
			local front = entry.figure.modelFront
			local facing = if not front or front.by == "none"
				then "facing unknown (no face clue: check the close-up)"
				elseif front.z < 0 then string.format(
					"faces front (by %s%s)",
					front.by,
					if front.turned then ", turned at build" else ""
				)
				else string.format("FACES BACKWARDS (by %s): rebuild it with scripts/models-build", front.by)
			print(
				string.format(
					"[DevLineup] %s: store model %s, %d parts, %s",
					entry.unitType,
					entry.figure.modelKey,
					parts,
					facing
				)
			)
		elseif avatar then
			print(
				string.format(
					"[DevLineup] %s: catalog avatar, %d parts (with ring and prop), %d instances in the rig",
					entry.unitType,
					parts,
					#avatar:GetDescendants()
				)
			)
		end
		total += parts
		if parts > most then
			most, mostId = parts, entry.unitType
		end
		if entry.figure.unitLook then
			looks += 1
			lookParts += parts
		end
	end
	print(
		string.format(
			"[DevLineup] %d figures, %d parts (average %.1f, most %d: %s). Hand-built looks: %d, average %.1f parts.",
			#entries,
			total,
			total / math.max(#entries, 1),
			most,
			mostId,
			looks,
			lookParts / math.max(looks, 1)
		)
	)
end

local function open()
	local lineup = Instance.new("Folder")
	lineup.Name = "DevLineup"
	folder = lineup
	local allRows = rows()
	local floor = Instance.new("Part")
	floor.Anchored = true
	floor.CanCollide = false
	floor.CanQuery = false
	floor.Size = Vector3.new(SPACING * 8, 1, ROW_GAP * (#allRows + 1))
	floor.CFrame = CFrame.new(BASE + Vector3.new(0, -0.5, (#allRows - 1) * ROW_GAP / 2))
	floor.Color = Color3.fromRGB(70, 74, 82)
	floor.Material = Enum.Material.SmoothPlastic
	floor.Parent = lineup

	for rowIndex, ids in allRows do
		for column, unitType in ids do
			local look = CharacterLook.of(unitType)
			local height = HEIGHT * look.scale
			-- Mirrored so each row reads left to right from the camera (which looks along +Z).
			local x = ((#ids + 1) / 2 - column) * SPACING
			-- Facing -Z, toward the camera.
			local root = CFrame.new(BASE + Vector3.new(x, 0, (rowIndex - 1) * ROW_GAP))
			local hitbox = Instance.new("Part")
			hitbox.Name = unitType
			hitbox.Anchored = true
			hitbox.CanCollide = false
			hitbox.CanQuery = false
			hitbox.CanTouch = false
			hitbox.Transparency = 1
			hitbox.Size = Vector3.new(2, height, 2)
			hitbox.Parent = lineup
			local figure = Figure.new(look.figure, look.color, height, hitbox)
			local unit = UnitConfig[unitType]
			local firstForm = unit.forms and unit.forms[1]
			local formLook = firstForm and RenderConfig.formLooks[firstForm.name]
			local mounted = formLook ~= nil and formLook.mount ~= nil
			if mounted then
				Figure.setMount(figure, formLook.mount)
			end

			local label = Instance.new("BillboardGui")
			label.Size = UDim2.fromOffset(150, 22)
			label.StudsOffset = Vector3.new(0, height * (if mounted then 0.95 else 0.62), 0) -- just over the head
			label.MaxDistance = 250
			local text = Instance.new("TextLabel")
			text.Size = UDim2.fromScale(1, 1)
			text.BackgroundTransparency = 1
			text.Text = unitType
			text.TextColor3 = Color3.new(1, 1, 1)
			text.TextStrokeTransparency = 0.3
			text.Font = Enum.Font.GothamBold
			text.TextSize = 14
			text.Parent = label
			label.Parent = hitbox

			local entry: Entry = {
				unitType = unitType,
				figure = figure,
				root = root,
				height = height,
				mounted = mounted,
			}
			place(entry, pose(figure))
			table.insert(entries, entry)
		end
	end
	lineup.Parent = workspace

	local camera = workspace.CurrentCamera
	savedCamera = { cameraType = camera.CameraType, cframe = camera.CFrame }
	local last = os.clock()
	heartbeat = RunService.Heartbeat:Connect(function()
		local real = os.clock()
		local dt = (real - last) * timeScale
		last = real
		stageTime += dt
		if stage then
			updateStage(stage, stageTime, dt)
		end
	end)
	openHud()
	overview()
	report()
end

-- The reel's title card; nil hides it.
local function showCard(text: string?)
	if reelGui and reelCard then
		reelCard.Text = text or ""
		reelGui.Enabled = text ~= nil
	end
end

-- Ends the reel (R again, its end, or the lineup closing): its loop stops, and the arena, camera,
-- lighting (the arena's, with the field preview), time scale and panel are put back.
local function finishReel()
	if not reelRunning then
		return
	end
	reelRunning = false
	reelToken += 1
	showCard(nil)
	if hud then
		hud.Enabled = true
	end
	timeScale = 1
	frozenScale = nil
	ImpactEffects.setTimeScale(1)
	if reelSaved then
		arenaMode, arenaCamera = reelSaved.arena, reelSaved.camera
		reelSaved = nil
	end
	if stage then
		endFieldPreview(stage)
	end
	refreshTitle()
	print("[Reel] stopped at " .. string.format("%.3f", os.clock()))
end

local function close()
	finishReel()
	closeStage()
	closeHud()
	-- Never leave the effects frozen (Dump FX / O) or slowed (S) after the lineup closes.
	timeScale = 1
	frozenScale = nil
	freezeButton = nil
	ImpactEffects.setTimeScale(1)
	if heartbeat then
		heartbeat:Disconnect()
		heartbeat = nil
	end
	if folder then
		folder:Destroy()
		folder = nil
	end
	table.clear(entries)
	focus = nil
	if savedCamera then
		local camera = workspace.CurrentCamera
		camera.CameraType = savedCamera.cameraType
		camera.CFrame = savedCamera.cframe
		savedCamera = nil
	end
end

-- Judge an ultimate: replay it (as key 3) at 0.25x, particles included, then back to 1x.
local function slowReplay(s: Stage)
	local slow = 0.25
	timeScale = slow
	ImpactEffects.setTimeScale(slow)
	cast(s)
	print("[DevLineup] ultimate at 0.25x (back to 1x in 14 s)")
	task.delay(14, function()
		if timeScale == slow then
			timeScale = 1
			ImpactEffects.setTimeScale(1)
		end
	end)
end

local function toggle()
	if folder then
		close()
	else
		open()
	end
end

step = function(by: number)
	if not folder then
		open()
	end
	local index = if focus then (focus - 1 + by) % #entries + 1 elseif by > 0 then 1 else #entries
	closeUp(index)
end

local function showUnit(unitType: string)
	if not folder then
		open()
	end
	for index, entry in entries do
		if entry.unitType == unitType then
			closeUp(index)
			return
		end
	end
	warn("[DevLineup] no roster unit " .. unitType)
end

-- The reel (R) -------------------------------------------------------------------------------------

-- ReelConfig.units (roster units only), or every roster unit with an ultimate by tier then id.
local function reelUnits(): { string }
	local roster = {}
	for _, entry in entries do
		roster[entry.unitType] = true
	end
	local list = {}
	if #ReelConfig.units > 0 then
		for _, unitType in ReelConfig.units do
			if roster[unitType] then
				table.insert(list, unitType)
			else
				warn("[Reel] no roster unit " .. unitType .. " (skipped)")
			end
		end
		return list
	end
	for unitType, ultimate in UltimateConfig.units do
		if roster[unitType] and type(ultimate) == "table" then
			table.insert(list, unitType)
		end
	end
	table.sort(list, function(a, b)
		local tierA, tierB = UltimateConfig.units[a].tier or 0, UltimateConfig.units[b].tier or 0
		return if tierA ~= tierB then tierA < tierB else a < b
	end)
	return list
end

-- Plays the reel, or stops it if it is playing. Its waits are in real seconds.
local function startReel()
	if reelRunning then
		finishReel()
		return
	end
	if not folder then
		open()
	end
	local units = reelUnits()
	if #units == 0 then
		warn("[Reel] no units to play")
		return
	end
	reelRunning = true
	reelToken += 1
	local token = reelToken
	reelSaved = { arena = arenaMode, camera = arenaCamera }
	arenaMode, arenaCamera = ReelConfig.arena, ReelConfig.camera
	if hud then
		hud.Enabled = false -- a clean clip: only the title cards
	end
	print(string.format("[Reel] %d units, %s / %s (R stops)", #units, arenaMode, arenaCamera))

	-- Waits `seconds`; false once the reel was stopped.
	local function hold(seconds: number): boolean
		local endsAt = os.clock() + seconds
		repeat
			task.wait()
			if token ~= reelToken then
				return false
			end
		until os.clock() >= endsAt
		return true
	end
	-- The unit's first cast (its ultimate) at `scale`, through its whole preview.
	local function play(s: Stage, scale: number): boolean
		timeScale = scale
		ImpactEffects.setTimeScale(scale)
		s.castPresses = 0
		local length = if cast(s) then AbilityFx.windupLength(s.unitType) + 0.5 + FIELD_AFTER else 0
		return hold(length / scale)
	end

	task.spawn(function()
		for _, unitType in units do
			showUnit(unitType)
			local s = stage
			if token ~= reelToken then
				return
			end
			if s then
				local ultimate = UltimateConfig.units[unitType]
				local tier = if type(ultimate) == "table" and ultimate.tier then ultimate.tier else 0
				showCard(string.format("%s   ·   TIER %d", unitType, tier))
				if not hold(ReelConfig.titleSeconds) then
					return
				end
				showCard(nil)
				print(string.format("[Reel] %s start at %.3f", unitType, os.clock()))
				if
					not play(s, 1)
					or not hold(ReelConfig.pauseSeconds)
					or not play(s, ReelConfig.slowScale)
				then
					return
				end
				timeScale = 1
				ImpactEffects.setTimeScale(1)
				if not hold(ReelConfig.gapSeconds) then
					return
				end
			end
		end
		showCard("REEL END")
		if hold(ReelConfig.endSeconds) then
			finishReel()
		end
	end)
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
local PREVIEW_KEYS: { [Enum.KeyCode]: (Stage) -> () } = {
	[Enum.KeyCode.One] = function(s)
		attack(s, false)
	end,
	[Enum.KeyCode.Two] = function(s)
		attack(s, true)
	end,
	[Enum.KeyCode.Three] = function(s)
		cast(s)
	end,
	[Enum.KeyCode.Four] = getHit,
	[Enum.KeyCode.Five] = function(s)
		if UnitView.isAlive(s.actor) then
			CombatFx.stun(s.actor, PREVIEW.stun, true)
		end
	end,
	[Enum.KeyCode.Six] = die,
	[Enum.KeyCode.Seven] = function(s)
		if UnitView.isAlive(s.actor) then
			CombatFx.victory({ s.actor }, stageClock())
		end
	end,
	[Enum.KeyCode.Eight] = healAndShield,
	[Enum.KeyCode.Nine] = function(s)
		s.auto = not s.auto
		s.nextAuto = stageClock()
		print("[DevLineup] auto " .. (if s.auto then "on" else "off"))
	end,
	[Enum.KeyCode.F] = nextForm,
	[Enum.KeyCode.X] = nextStar,
	[Enum.KeyCode.Q] = function()
		nextQuality()
	end,
}

-- A handle for Studio scripts (the command bar, Studio MCP; DevLineupQA below) for visual checks:
-- show(unitId), ultimate(unitId) (shows it and plays its next cast, as key 3), press("One" ...
-- "Nine", "F", "X", "Q"), timeScale(0.25) for slow motion (0 freezes), freezeAfter(stageSeconds),
-- camera("front" | "side" | "close" | "board"; "close" also frames key 3's preview close on the
-- unit), state(), vfxReport() and vfxTest(seconds) (VfxDebug: effect textures). Studio only.
local function qaHandle()
	return {
		show = function(unitType: string)
			showUnit(unitType)
		end,
		-- Shows the unit and plays its next cast (its ultimate) in the field preview, as key 3.
		ultimate = function(unitType: string)
			if not stage or stage.unitType ~= unitType then
				showUnit(unitType)
			end
			local s = stage
			if s then
				cast(s)
			end
		end,
		press = function(keyName: string)
			local key = (Enum.KeyCode :: any)[keyName]
			local s = stage
			if s and PREVIEW_KEYS[key] then
				if key ~= Enum.KeyCode.Three and key ~= Enum.KeyCode.Q then
					endFieldPreview(s)
				end
				PREVIEW_KEYS[key](s)
			end
		end,
		timeScale = function(scale: number)
			timeScale = scale
		end,
		freezeAfter = function(seconds: number)
			local s = stage
			if s then
				later(s, stageClock() + seconds, function()
					timeScale = 0
				end)
			end
		end,
		camera = function(mode: string)
			cameraMode = mode
			local s = stage
			if s then
				local distance = if rangeOf(s) > 1 then PREVIEW.rangedDistance else PREVIEW.meleeDistance
				s.stageCamera = stageFraming(s, distance)
				s.camera = if s.fieldPreview and s.fieldFocus then fieldFraming(s.fieldFocus) else s.stageCamera
			end
		end,
		state = function()
			local s = stage
			return {
				unit = if s then s.unitType else nil,
				star = if s then s.starLevel else nil,
				form = if s then s.formIndex else nil,
				time = stageTime,
				scale = timeScale,
				preview = s ~= nil and s.fieldPreview ~= nil,
				arena = arenaMode,
				arenaCamera = arenaCamera,
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
		-- While the reel plays, only R (stop) does anything.
		if reelRunning then
			if key == Enum.KeyCode.R then
				finishReel()
			end
			return
		end
		-- Roblox's emotes menu (and the default camera, for the arrows) mark these keys processed:
		-- while the lineup is open they still step.
		if folder and NEXT_KEYS[key] then
			step(1)
			return
		elseif folder and PREVIOUS_KEYS[key] then
			step(-1)
			return
		end
		-- O is the default camera's zoom-out key and S a movement key: Roblox marks both processed,
		-- so while the lineup is open they are handled before that check.
		if folder and key == Enum.KeyCode.O and not UserInputService:GetFocusedTextBox() then
			toggleFreeze()
			return
		end
		if folder and key == Enum.KeyCode.S and stage then
			slowReplay(stage)
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
			step(1)
		elseif key == Enum.KeyCode.Comma or key == Enum.KeyCode.LeftBracket then
			step(-1)
		elseif key == Enum.KeyCode.M and folder then
			overview()
		elseif key == Enum.KeyCode.T and stage then
			nextArena(stage)
		elseif key == Enum.KeyCode.C and stage then
			nextArenaCamera(stage)
		elseif key == Enum.KeyCode.R and folder then
			startReel()
		elseif stage and PREVIEW_KEYS[key] then
			if key ~= Enum.KeyCode.Three and key ~= Enum.KeyCode.Q then
				endFieldPreview(stage)
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
			showUnit(unitType)
		end
	end)
	print(
		"[DevLineup] Studio only: L opens the unit lineup; . ] Right / , [ Left (or the on-screen buttons) step through close-ups; M shows them all."
	)
end

return DevLineup
