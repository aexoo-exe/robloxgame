-- Studio-only: every roster unit's figure lined up far above the hub, one row per origin, with its
-- unit id over its head, to check looks (UnitLookConfig, CharacterLook) without playing a match.
-- Riders sit on their horses. A close-up shows one unit looping idle, walk, attack and cast, so held
-- weapons can be seen following the hands.
--   L        open or close the lineup
--   . / ,    close-up of the next / previous unit
--   M        back to the whole lineup
--   F        in a close-up: the unit's next form (its own look from FormLookConfig, or the base
--            figure with the form's tint), with the form's size; cycles back to the first form
-- Chat commands: /lineup (open or close), /look <unit_id> (close-up of that unit).
-- On opening, the output shows the part counts of the figures. Does nothing outside Studio.
-- Presentation only.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TextChatService = game:GetService("TextChatService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local FigureConfig = require(Shared:WaitForChild("FigureConfig"))
local HubConfig = require(Shared:WaitForChild("HubConfig"))
local RenderConfig = require(Shared:WaitForChild("RenderConfig"))
local UnitConfig = require(Shared:WaitForChild("UnitConfig"))

local CharacterLook = require(script.Parent.CharacterLook)
local Figure = require(script.Parent.Figure)

local DevLineup = {}

local ORIGIN_ORDER = { "Hunters", "Corps", "Spirit", "Cursed", "Arcane", "Titans", "Shinobi", "Crew", "Heroes" }
local BASE = HubConfig.center + Vector3.new(0, 260, 0) -- clear sky above the hub
local SPACING = 5.5 -- between units in a row
local ROW_GAP = 9
local HEIGHT = RenderConfig.unitSize.Y
local ANIMATION = FigureConfig.animation
local rad = math.rad

type Entry = {
	unitType: string,
	figure: Figure.Figure,
	root: CFrame,
	height: number,
	hand: string,
	mounted: boolean,
	look: Figure.Look, -- the unit's base figure look
	color: Color3,
	baseHeight: number, -- before any form's size
	formIndex: number, -- the form shown (UnitConfig forms), 1 for the first
}

local folder: Folder? = nil
local entries: { Entry } = {}
local focus: number? = nil
local heartbeat: RBXScriptConnection? = nil
local savedCamera: { cameraType: Enum.CameraType, cframe: CFrame }? = nil

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

-- The close-up loop: idle, walk, attack (each attacking hand in turn) and cast, a second each.
local function animate(entry: Entry, now: number)
	local p = pose(entry.figure)
	local h = entry.height
	local phase = now % 4
	if phase < 1 then
		p.bob = math.sin(phase * 2 * math.pi) * ANIMATION.idleBob * h
	elseif phase < 2 then
		local step = math.sin((now / ANIMATION.walkCycle) * 2 * math.pi)
		p.leftLeg, p.rightLeg = rad(ANIMATION.walkLegSwing) * step, -rad(ANIMATION.walkLegSwing) * step
		p.leftArm -= rad(ANIMATION.walkArmSwing) * step
		p.rightArm += rad(ANIMATION.walkArmSwing) * step
		p.stride = rad(ANIMATION.horseLegSwing) * step
		p.bob = math.abs(step) * ANIMATION.walkBob * h
	elseif phase < 3 then
		local swing = math.sin(math.pi * ((phase - 2) * 2 % 1))
		local left = entry.hand == "left" or (entry.hand == "both" and phase >= 2.5)
		if left then
			p.leftArm += rad(ANIMATION.attackArm) * swing
		else
			p.rightArm += rad(ANIMATION.attackArm) * swing
		end
		p.lean = rad(ANIMATION.attackLean) * swing
	else
		local lift = math.sin(math.pi * (phase - 3))
		local up = rad(ANIMATION.castArms)
		p.leftArm += (up - p.leftArm) * lift
		p.rightArm += (up - p.rightArm) * lift
	end
	place(entry, p)
end

local function setCamera(cframe: CFrame)
	local camera = workspace.CurrentCamera
	camera.CameraType = Enum.CameraType.Scriptable
	camera.CFrame = cframe
end

local function overview()
	if focus then
		place(entries[focus], pose(entries[focus].figure))
	end
	focus = nil
	local count = #rows()
	local middle = BASE + Vector3.new(0, 0, (count - 1) * ROW_GAP / 2)
	setCamera(CFrame.lookAt(middle + Vector3.new(0, 48, -52), middle))
end

local function closeUp(index: number)
	if focus and focus ~= index then
		place(entries[focus], pose(entries[focus].figure))
	end
	focus = index
	local entry = entries[index]
	local target = entry.root.Position + Vector3.new(0, entry.height * 0.55, 0)
	setCamera(CFrame.lookAt(target + Vector3.new(2.6, 1.6, -6.2), target))
	print(string.format("[DevLineup] %s (%d/%d)", entry.unitType, index, #entries))
end

-- Redraws a close-up unit in its next form, as a fight would show it: the form's own look
-- (FormLookConfig) or the base figure with the form's tint, at the form's size, on its horse.
local function nextForm(entry: Entry)
	local forms = UnitConfig[entry.unitType].forms
	if not forms or #forms < 2 then
		print("[DevLineup] " .. entry.unitType .. " has no forms")
		return
	end
	local index = entry.formIndex % #forms + 1
	local form = forms[index]
	local formLook = RenderConfig.formLooks[form.name]
	local figureLook, own, extraScale = CharacterLook.formFigure(entry.look, form.name)
	local height = entry.baseHeight * (if formLook and formLook.scale then formLook.scale else 1) * extraScale
	local old = entry.figure
	local hitbox = old.parts[1]
	for i = #old.pieces, 2, -1 do -- piece 1 is the hitbox
		old.pieces[i].part:Destroy()
	end
	if old.avatar then
		old.avatar:Destroy()
	end
	hitbox.Size = Vector3.new(2, height, 2)
	local figure = Figure.new(figureLook, entry.color, height, hitbox)
	if formLook and formLook.mount then
		Figure.setMount(figure, formLook.mount)
	end
	local tint = if formLook and not own then formLook.tint else nil
	figure.color = tint or entry.color
	figure.formTint = tint
	Figure.setTint(figure, nil)
	entry.figure, entry.height, entry.formIndex = figure, height, index
	print(
		string.format(
			"[DevLineup] %s: form %d/%d %q, %s, %d parts",
			entry.unitType,
			index,
			#forms,
			form.name,
			if own then "own look" elseif tint then "base figure, tinted" else "base figure",
			#figure.parts - 1
		)
	)
end

local function report()
	local total, most, mostId, looks, lookParts = 0, 0, "", 0, 0
	for _, entry in entries do
		local parts = #entry.figure.parts - 1 -- the hitbox is not drawn
		if entry.mounted then
			print(string.format("[DevLineup] %s: %d parts with its horse", entry.unitType, parts))
		end
		local avatar = entry.figure.avatar
		if avatar then
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
				hand = if look.figure.classLook then look.figure.classLook.hand else "right",
				mounted = mounted,
				look = look.figure,
				color = look.color,
				baseHeight = height,
				formIndex = 1,
			}
			place(entry, pose(figure))
			table.insert(entries, entry)
		end
	end
	lineup.Parent = workspace

	local camera = workspace.CurrentCamera
	savedCamera = { cameraType = camera.CameraType, cframe = camera.CFrame }
	heartbeat = RunService.Heartbeat:Connect(function()
		if focus then
			animate(entries[focus], os.clock())
		end
	end)
	overview()
	report()
end

local function close()
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

local function toggle()
	if folder then
		close()
	else
		open()
	end
end

local function step(by: number)
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

local function command(alias: string, run: (string) -> ())
	local chatCommand = Instance.new("TextChatCommand")
	chatCommand.Name = "DevLineup" .. alias
	chatCommand.PrimaryAlias = "/" .. alias
	chatCommand.Triggered:Connect(function(_, text)
		run(string.match(text, "^%S+%s+(%S+)") or "")
	end)
	chatCommand.Parent = TextChatService
end

function DevLineup.start()
	if not RunService:IsStudio() then
		return
	end
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		local key = input.KeyCode
		if key == Enum.KeyCode.L then
			toggle()
		elseif key == Enum.KeyCode.Period then
			step(1)
		elseif key == Enum.KeyCode.Comma then
			step(-1)
		elseif key == Enum.KeyCode.M and folder then
			overview()
		elseif key == Enum.KeyCode.F and focus then
			nextForm(entries[focus])
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
	print("[DevLineup] Studio only: L opens the unit lineup, . and , step through close-ups, M shows them all.")
end

return DevLineup
