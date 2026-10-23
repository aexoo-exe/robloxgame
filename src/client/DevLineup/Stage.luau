-- DevLineup's close-up preview stage: the unit and a target dummy as fight views, drawn and
-- animated by the same code as a fight, on the stage clock (State.stageClock), and the stage keys
-- that act on them (attack, crit, get hit, death, heal + shield, star level, form, quality).
-- Studio only (see DevLineup).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AnimationConfig = require(Shared:WaitForChild("AnimationConfig"))
local CombatConfig = require(Shared:WaitForChild("CombatConfig"))
local Forms = require(Shared:WaitForChild("Forms"))
local RenderConfig = require(Shared:WaitForChild("RenderConfig"))
local UnitConfig = require(Shared:WaitForChild("UnitConfig"))

local Config = require(script.Parent.Config)
local State = require(script.Parent.State)
local TestArena = require(script.Parent.TestArena)

local AbilityFx = require(script.Parent.Parent.AbilityFx)
local CameraCues = require(script.Parent.Parent.CameraCues)
local CharacterLook = require(script.Parent.Parent.CharacterLook)
local Cinematic = require(script.Parent.Parent.Cinematic)
local CombatEffects = require(script.Parent.Parent.CombatEffects)
local CombatFx = require(script.Parent.Parent.CombatFx)
local CombatPlayback = require(script.Parent.Parent.CombatPlayback)
local HitFeel = require(script.Parent.Parent.HitFeel)
local ImpactEffects = require(script.Parent.Parent.ImpactEffects)
local UnitMotion = require(script.Parent.Parent.UnitMotion)
local UnitView = require(script.Parent.Parent.UnitView)
local Vfx = require(script.Parent.Parent.Vfx)

local Stage = {}

local STAGE = Config.STAGE
local PREVIEW = Config.PREVIEW
local HEIGHT = Config.HEIGHT
local stageClock = State.stageClock

function Stage.setCamera(cframe: CFrame)
	local camera = workspace.CurrentCamera
	camera.CameraType = Enum.CameraType.Scriptable
	camera.CFrame = cframe
end

-- The unit's current form, its range in that form, and its attack style.
local function formOf(s: State.Stage): any?
	local forms = UnitConfig[s.unitType].forms
	return if forms then forms[s.formIndex] else nil
end
function Stage.rangeOf(s: State.Stage): number
	return Forms.range(UnitConfig[s.unitType], formOf(s))
end
local function styleOf(s: State.Stage): string
	local form = formOf(s)
	return UnitMotion.styleFor(s.unitType, Stage.rangeOf(s), CharacterLook.of(s.unitType).figure, form and form.name)
end

function Stage.later(s: State.Stage, at: number, run: () -> ())
	table.insert(s.pending, { at = at, run = run })
end
local later = Stage.later

-- The stage camera for the current camera mode (`State.cameraMode`): the unit stands at STAGE
-- facing -X toward the dummy `distance` studs away.
--   front  a three-quarter view of the unit's front, the dummy beside it (the default)
--   side   both from the side, square on to the line between them
--   close  the unit's head and shoulders, from the front
--   board  the normal board camera's angle and distance
function Stage.framing(s: State.Stage, distance: number): CFrame
	local height = HEIGHT * CharacterLook.of(s.unitType).scale * RenderConfig.starSizeScale[s.starLevel]
	local chest = STAGE + Vector3.new(0, height * 0.55, 0)
	local size = height / HEIGHT
	local cameraMode = State.cameraMode
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
local function spawnActors(s: State.Stage)
	local look = CharacterLook.of(s.unitType)
	local ranged = Stage.rangeOf(s) > 1
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
		s.dummy = UnitView.new("dummy", 1, Config.DUMMY_COLOR, STAGE - Vector3.new(distance, 0, 0), s.folder, {
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
	s.stageCamera = Stage.framing(s, distance)
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

function Stage.close()
	local s = State.stage
	if not s then
		return
	end
	State.stage = nil
	if s.fieldPreview then
		CombatPlayback.stop()
	end
	TestArena.leave()
	CombatEffects.clear()
	ImpactEffects.clear()
	HitFeel.clear()
	HitFeel.setFocused(false)
	CombatEffects.setClock(nil)
	ImpactEffects.setClock(nil)
	CameraCues.setClock(nil)
	CameraCues.clear()
	s.folder:Destroy() -- every view of the stage is inside it
end

function Stage.open(unitType: string)
	Stage.close()
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
	local s: State.Stage = {
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
	State.stage = s
	CombatEffects.setClock(stageClock)
	ImpactEffects.setClock(stageClock)
	CameraCues.setClock(stageClock)
	HitFeel.setFocused(true) -- one unit is the focus: full punch-ins
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
function Stage.attack(s: State.Stage, crit: boolean)
	local actor, dummy = s.actor, s.dummy
	if not UnitView.isAlive(actor) then
		return
	end
	local style = styleOf(s)
	local ranged = Stage.rangeOf(s) > 1
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
local function quickCast(s: State.Stage)
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

-- The dummy attacks the unit.
function Stage.getHit(s: State.Stage)
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

function Stage.die(s: State.Stage)
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

function Stage.healAndShield(s: State.Stage)
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
function Stage.nextStar(s: State.Stage)
	if not UnitView.isAlive(s.actor) then
		return
	end
	UnitView.destroy(s.actor)
	s.starLevel = s.starLevel % 3 + 1
	spawnActors(s)
end

-- The unit's next form, shown as a fight shows a form change.
function Stage.nextForm(s: State.Stage)
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
	local distance = if Stage.rangeOf(s) > 1 then PREVIEW.rangedDistance else PREVIEW.meleeDistance
	UnitView.moveTo(s.dummy, STAGE - Vector3.new(distance, 0, 0))
end

function Stage.nextQuality()
	local index = table.find(Config.QUALITIES, ImpactEffects.quality()) or 0
	local name = Config.QUALITIES[index % #Config.QUALITIES + 1]
	ImpactEffects.setQuality(name)
	print("[DevLineup] effects quality: " .. name .. " (charge sparkles apply to units built after this)")
end

function Stage.update(s: State.Stage, now: number, dt: number)
	for i = #s.pending, 1, -1 do
		local job = s.pending[i]
		if now >= job.at then
			table.remove(s.pending, i)
			job.run()
		end
	end
	if State.stage ~= s then
		return -- a job closed the stage
	end
	if s.auto and now >= s.nextAuto then
		s.nextAuto = now + PREVIEW.interval
		s.autoCount += 1
		if s.autoCount % 6 == 0 then
			quickCast(s)
		else
			Stage.attack(s, s.autoCount % 4 == 0)
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
	local arenaMode, arenaCamera = State.arenaMode, State.arenaCamera
	if s.fieldPreview and s.fieldOffset and arenaMode ~= "off" and arenaCamera == "slice" then
		s.camera = TestArena.framing(s, s.fieldOffset) -- the slice orbit moves every frame
	end
	if s.fieldPreview and arenaMode ~= "off" then
		-- An arena's fixed camera: no cues, no drift. The slice's unit keeps its camera shake (its hit
		-- feel is what is being judged); every other unit's recording stays still.
		local shake = if s.unitType == Config.SLICE_UNIT then ImpactEffects.shakeOffset() else CFrame.identity
		Stage.setCamera(s.camera * shake)
	else
		Stage.setCamera(s.camera * ImpactEffects.shakeOffset() * CameraCues.offset(s.camera))
	end
end

return Stage
