-- DevLineup's lineup: every roster unit's figure in rows far above the hub (one row per origin)
-- with its unit id over its head, the overview camera, close-ups (Stage) and stepping between
-- them, and the part-count report printed on opening. Studio only (see DevLineup).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local RenderConfig = require(Shared:WaitForChild("RenderConfig"))
local UnitConfig = require(Shared:WaitForChild("UnitConfig"))

local Config = require(script.Parent.Config)
local Hud = require(script.Parent.Hud)
local Stage = require(script.Parent.Stage)
local State = require(script.Parent.State)

local CharacterLook = require(script.Parent.Parent.CharacterLook)
local Figure = require(script.Parent.Parent.Figure)

local Lineup = {}

local BASE, SPACING, ROW_GAP, HEIGHT = Config.BASE, Config.SPACING, Config.ROW_GAP, Config.HEIGHT

-- Roster unit ids in rows: one row per origin (in ORIGIN_ORDER, then any others), by cost then id.
local function rows(): { { string } }
	local byOrigin: { [string]: { string } } = {}
	for unitType, unit in UnitConfig do
		if type(unit) == "table" and unit.origin then
			byOrigin[unit.origin] = byOrigin[unit.origin] or {}
			table.insert(byOrigin[unit.origin], unitType)
		end
	end
	local order = table.clone(Config.ORIGIN_ORDER)
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

local function place(entry: State.Entry, p: Figure.Pose)
	Figure.place(entry.figure, entry.root * CFrame.new(0, entry.height / 2, 0), entry.root, p)
end

function Lineup.overview()
	Stage.close()
	State.focus = nil
	local count = #rows()
	local middle = BASE + Vector3.new(0, 0, (count - 1) * ROW_GAP / 2)
	Stage.setCamera(CFrame.lookAt(middle + Vector3.new(0, 48, -52), middle))
	Hud.setHud(string.format("Lineup (%d)", #State.entries), Config.OVERVIEW_HELP)
end

local function closeUp(index: number)
	State.focus = index
	local entries = State.entries
	local entry = entries[index]
	print(string.format("[DevLineup] %s (%d/%d)", entry.unitType, index, #entries))
	Stage.open(entry.unitType)
	Hud.setHud(string.format("%s (%d/%d)", entry.unitType, index, #entries), Config.CLOSE_UP_HELP)
end

local function report()
	local entries = State.entries
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

function Lineup.open()
	local lineup = Instance.new("Folder")
	lineup.Name = "DevLineup"
	State.folder = lineup
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

			local entry: State.Entry = {
				unitType = unitType,
				figure = figure,
				root = root,
				height = height,
				mounted = mounted,
			}
			place(entry, pose(figure))
			table.insert(State.entries, entry)
		end
	end
	lineup.Parent = workspace

	local camera = workspace.CurrentCamera
	State.savedCamera = { cameraType = camera.CameraType, cframe = camera.CFrame }
	local last = os.clock()
	State.heartbeat = RunService.Heartbeat:Connect(function()
		local real = os.clock()
		local dt = (real - last) * State.timeScale
		last = real
		State.stageTime += dt
		if State.stage then
			Stage.update(State.stage, State.stageTime, dt)
		end
	end)
	Hud.open()
	Lineup.overview()
	report()
end

-- Next (`by` 1) or previous (-1) close-up; opens the lineup if needed.
function Lineup.step(by: number)
	if not State.folder then
		Lineup.open()
	end
	local entries = State.entries
	local focus = State.focus
	local index = if focus then (focus - 1 + by) % #entries + 1 elseif by > 0 then 1 else #entries
	closeUp(index)
end

-- The close-up of `unitType`; opens the lineup if needed.
function Lineup.showUnit(unitType: string)
	if not State.folder then
		Lineup.open()
	end
	for index, entry in State.entries do
		if entry.unitType == unitType then
			closeUp(index)
			return
		end
	end
	warn("[DevLineup] no roster unit " .. unitType)
end

return Lineup
