-- Studio-only: the reel's CHECK pass (DevLineup, key R). While the reel plays a unit it records,
-- from a scan of the effect folders every SAMPLE seconds (nothing per frame):
--   errors    warnings and errors in Output during the unit's plays (LogService)
--   peak      the most live effect instances at once, against ReelConfig.budget[tier]
--   flat      Neon or flat parts, SurfaceGuis, Decals and flat-oriented particles (VelocityPerpendicular)
--             within FLOOR_NEAR studs of the field floor and wider than FLAT_WIDE studs (the old
--             floor "oval"): the widest, with its path
--   light     PointLights within LIGHT_NEAR studs of the floor: the lowest, with its path
--   neon      kit images not loaded when a play started while effects drew their neon fallback
--   leak      effect instances still live ReelConfig.leakSeconds after the last play ended
--   no cast   the unit never cast in its preview fight
-- ReelCheck.report() prints one line per unit ("OK", or "WARN: ..." with short findings).
-- Presentation only: reads effects, never changes them.

local LogService = game:GetService("LogService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local VfxConfig = require(Shared:WaitForChild("VfxConfig"))

local ReelConfig = require(script.Parent.ReelConfig)
local Vfx = require(script.Parent.Vfx)

local ReelCheck = {}

local SAMPLE = 0.15 -- seconds between scans
local FLOOR_NEAR = 1 -- studs from the floor that count as "at floor"
local FLAT_WIDE = 1.5 -- wider than this (studs) is an oval on the floor
local LIGHT_NEAR = 1.5
local FLAT_THIN = 0.35 -- a part thinner than this (its smallest side) is flat
local ROOTS = { "ImpactEffects", "CombatEffects" }

type Finding = { text: string, score: number }
type Record = {
	unit: string,
	tier: number,
	peak: number,
	errors: number,
	firstError: string?,
	flat: Finding?,
	light: Finding?,
	neon: string?,
	leak: string?,
	noCast: boolean?,
}

local results: { Record } = {}
local current: Record? = nil
local floorOf: () -> number? = function()
	return nil
end
local token = 0
local logConnection: RBXScriptConnection? = nil
local unloadedAtStart = 0

local function roots(): { Instance }
	local out = {}
	for _, name in ROOTS do
		local found = workspace:FindFirstChild(name)
		if found then
			table.insert(out, found)
		end
	end
	return out
end

-- Whether an effect instance is drawing now (VfxDebug.dumpLive's rules), and where it is.
local function liveAt(item: Instance): (boolean, Vector3?)
	local parent = item.Parent
	local holder = if item:IsA("BasePart") then item else item:FindFirstAncestorWhichIsA("BasePart")
	local at = if parent and parent:IsA("Attachment")
		then parent.WorldPosition
		elseif holder then holder.Position
		else nil
	if item:IsA("ParticleEmitter") then
		return holder ~= nil and holder.Parent ~= nil, at
	elseif item:IsA("Beam") or item:IsA("PointLight") or item:IsA("SurfaceGui") or item:IsA("BillboardGui") then
		return (item :: any).Enabled, at
	elseif item:IsA("Decal") then
		return item.Transparency < 1, at
	elseif item:IsA("BasePart") then
		return item.Transparency < 1, at
	end
	return false, nil
end

local function widest(size: Vector3): (number, number)
	local thin = math.min(size.X, size.Y, size.Z)
	local wide = math.max(size.X, size.Y, size.Z)
	return thin, wide
end

local function sequenceMax(sequence: NumberSequence): number
	local most = 0
	for _, key in sequence.Keypoints do
		most = math.max(most, key.Value + key.Envelope)
	end
	return most
end

-- Keeps the worse of two findings (a higher score).
local function worse(old: Finding?, text: string, score: number): Finding
	if old and old.score >= score then
		return old
	end
	return { text = text, score = score }
end

-- The flat-on-floor width of an item (0: not a flat visual), and what to call it.
local function flatWidth(item: Instance): (number, string)
	if item:IsA("BasePart") then
		local thin, wide = widest(item.Size)
		if item.Material == Enum.Material.Neon or thin < FLAT_THIN then
			return wide, "flat part"
		end
	elseif item:IsA("SurfaceGui") or item:IsA("Decal") then
		local part = item:FindFirstAncestorWhichIsA("BasePart")
		if item:IsA("SurfaceGui") and item.Adornee and item.Adornee:IsA("BasePart") then
			part = item.Adornee :: BasePart
		end
		if part then
			local _, wide = widest(part.Size)
			return wide, item.ClassName
		end
	elseif item:IsA("ParticleEmitter") then
		if item.Orientation == Enum.ParticleOrientation.VelocityPerpendicular then
			return sequenceMax(item.Size), "flat particles"
		end
	end
	return 0, ""
end

-- One scan: the live count (for the peak) and the flat and light findings.
local function scan(record: Record): (number, Instance?)
	local floor = floorOf()
	local count, any = 0, nil
	for _, root in roots() do
		for _, item in root:GetDescendants() do
			local live, at = liveAt(item)
			if not live then
				continue
			end
			count += 1
			any = any or item
			if not floor or not at then
				continue
			end
			local height = at.Y - floor
			if item:IsA("PointLight") then
				if height <= LIGHT_NEAR then
					record.light = worse(
						record.light,
						string.format("PointLight %.1f studs above floor (%s)", height, item:GetFullName()),
						LIGHT_NEAR - height
					)
				end
			elseif math.abs(height) <= FLOOR_NEAR then
				local wide, what = flatWidth(item)
				if wide > FLAT_WIDE then
					record.flat = worse(
						record.flat,
						string.format("%s %.1f studs at floor (%s)", what, wide, item:GetFullName()),
						wide
					)
				end
			end
		end
	end
	return count, any
end

-- Kit images not loaded now (drawn neon until they load).
local function unloadedImages(): number
	local count = 0
	for _, role in VfxConfig.roles do
		for _, pick in VfxConfig.picks[role] or {} do
			if pick.image and not Vfx.usable(pick.image) then
				count += 1
			end
		end
	end
	return count
end

local function fallbackDraws(): number
	local total = 0
	for _, draws in Vfx.counts() do
		total += draws.fallback
	end
	return total
end

local function stopRecording()
	token += 1
	if logConnection then
		logConnection:Disconnect()
		logConnection = nil
	end
	current = nil
end

-- Starts recording `unitType`; `floor` gives the field floor's height (nil while no field shows).
function ReelCheck.begin(unitType: string, tier: number, floor: () -> number?)
	stopRecording()
	local record: Record = { unit = unitType, tier = tier, peak = 0, errors = 0 }
	current = record
	floorOf = floor
	table.insert(results, record)
	logConnection = LogService.MessageOut:Connect(function(message, kind)
		if kind ~= Enum.MessageType.MessageWarning and kind ~= Enum.MessageType.MessageError then
			return
		end
		if string.sub(message, 1, 6) == "[Reel]" then
			return
		end
		record.errors += 1
		record.firstError = record.firstError or string.sub(message, 1, 70)
	end)
	local mine = token
	task.spawn(function()
		while mine == token do
			local count = scan(record)
			record.peak = math.max(record.peak, count)
			task.wait(SAMPLE)
		end
	end)
end

-- A play (cast) of the recorded unit starts: which kit images are unloaded right now.
function ReelCheck.playStarted()
	unloadedAtStart = unloadedImages()
end

-- The recorded unit did not cast in its preview fight.
function ReelCheck.noCast()
	if current then
		current.noCast = true
	end
end

-- A play ended: neon draws while kit images were unloaded at its start.
function ReelCheck.playEnded()
	local record = current
	if not record or not Vfx.enabled() then
		return
	end
	local fallback = fallbackDraws()
	if unloadedAtStart > 0 and fallback > 0 then
		record.neon = string.format("neon: %d draws, %d kit images not loaded", fallback, unloadedAtStart)
	end
end

-- ReelConfig.leakSeconds after the last play: what is still live is a leak. Ends the recording.
function ReelCheck.finish()
	local record = current
	if not record then
		return
	end
	local count, any = scan(record)
	if count > 0 then
		record.leak = string.format("leak: %d effects still live (%s)", count, if any then any:GetFullName() else "?")
	end
	stopRecording()
end

-- Drops the unit being recorded (the reel was stopped partway).
function ReelCheck.abort()
	local record = current
	stopRecording()
	if record then
		table.remove(results, table.find(results, record) :: number)
	end
end

function ReelCheck.hasResults(): boolean
	return #results > 0
end

-- Prints the report and clears it.
function ReelCheck.report(note: string?)
	local lines = { "==== REEL CHECK ====" .. (if note then " (" .. note .. ")" else "") }
	local ok, warned = 0, 0
	for _, record in results do
		local budget = ReelConfig.budget[record.tier] or ReelConfig.budget[#ReelConfig.budget]
		local findings = {}
		if record.noCast then
			table.insert(findings, "did not cast in the preview fight")
		end
		if record.errors > 0 then
			table.insert(findings, string.format("%d errors/warnings: %s", record.errors, record.firstError or "?"))
		end
		if record.flat then
			table.insert(findings, record.flat.text)
		end
		if record.light then
			table.insert(findings, record.light.text)
		end
		if record.peak > budget then
			table.insert(findings, string.format("peak %d/%d budget", record.peak, budget))
		end
		if record.neon then
			table.insert(findings, record.neon)
		end
		if record.leak then
			table.insert(findings, record.leak)
		end
		local name = record.unit .. string.rep(" ", math.max(1, 20 - #record.unit))
		if #findings == 0 then
			ok += 1
			table.insert(lines, string.format("%s OK (peak %d/%d)", name, record.peak, budget))
		else
			warned += 1
			table.insert(lines, name .. " WARN: " .. table.concat(findings, "; "))
		end
	end
	table.insert(lines, string.format("summary: %d ok, %d with warnings", ok, warned))
	print(table.concat(lines, "\n"))
	table.clear(results)
end

return ReelCheck
