-- DevLineup's reel (R): plays a batch of ultimates in one clip (ReelConfig) with title cards and
-- ReelCheck's measurements, then puts the arena, camera, time scale and panel back. R again stops
-- it. Studio only (see DevLineup).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local UltimateConfig = require(Shared:WaitForChild("UltimateConfig"))

local Config = require(script.Parent.Config)
local Field = require(script.Parent.Field)
local Hud = require(script.Parent.Hud)
local Lineup = require(script.Parent.Lineup)
local Slice = require(script.Parent.Slice)
local State = require(script.Parent.State)

local Arena = require(script.Parent.Parent.Arena)
local ImpactEffects = require(script.Parent.Parent.ImpactEffects)
local ReelCheck = require(script.Parent.Parent.ReelCheck)
local ReelConfig = require(script.Parent.Parent.ReelConfig)

local Reel = {}

-- The reel's title card; nil hides it.
local function showCard(text: string?)
	if State.reelGui and State.reelCard then
		State.reelCard.Text = text or ""
		State.reelGui.Enabled = text ~= nil
	end
end

-- Ends the reel (R again, its end, or the lineup closing): its loop stops, and the arena, camera,
-- lighting (the arena's, with the field preview), time scale and panel are put back.
function Reel.finish()
	if not State.reelRunning then
		return
	end
	State.reelRunning = false
	State.reelToken += 1
	-- Stopped partway: the units finished so far are still reported.
	ReelCheck.abort()
	if ReelCheck.hasResults() then
		ReelCheck.report("stopped early")
	end
	showCard(nil)
	if State.hud then
		State.hud.Enabled = true
	end
	State.timeScale = 1
	State.frozenScale = nil
	ImpactEffects.setTimeScale(1)
	local saved = State.reelSaved
	if saved then
		State.arenaMode, State.arenaCamera = saved.arena, saved.camera
		State.reelSaved = nil
	end
	if State.stage then
		Field.endPreview(State.stage)
	end
	Hud.refreshTitle()
	print("[Reel] stopped at " .. string.format("%.3f", os.clock()))
end

-- ReelConfig.units (roster units only), or every roster unit with an ultimate by tier then id.
local function reelUnits(): { string }
	local roster = {}
	for _, entry in State.entries do
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
function Reel.start()
	if State.reelRunning then
		Reel.finish()
		return
	end
	if not State.folder then
		Lineup.open()
	end
	Slice.leave() -- a pending slice-camera restore must not end the reel's previews
	local units = reelUnits()
	if #units == 0 then
		warn("[Reel] no units to play")
		return
	end
	State.reelRunning = true
	State.reelToken += 1
	local token = State.reelToken
	State.reelSaved = { arena = State.arenaMode, camera = State.arenaCamera }
	State.arenaMode, State.arenaCamera = ReelConfig.arena, ReelConfig.camera
	if State.hud then
		State.hud.Enabled = false -- a clean clip: only the title cards
	end
	print(string.format("[Reel] %d units, %s / %s (R stops)", #units, State.arenaMode, State.arenaCamera))

	-- Waits `seconds`; false once the reel was stopped.
	local function hold(seconds: number): boolean
		local endsAt = os.clock() + seconds
		repeat
			task.wait()
			if token ~= State.reelToken then
				return false
			end
		until os.clock() >= endsAt
		return true
	end
	-- The unit's first cast (its ultimate) at `scale`, through its whole preview.
	local function play(s: State.Stage, scale: number): boolean
		State.timeScale = scale
		ImpactEffects.setTimeScale(scale)
		s.castPresses = 0
		ReelCheck.playStarted()
		local casted = Field.cast(s)
		if not casted then
			ReelCheck.noCast()
		end
		local length = if casted then s.previewSeconds or Config.FIELD_AFTER else 0
		local played = hold(length / scale)
		if played then
			ReelCheck.playEnded()
		end
		return played
	end
	-- The field floor's height while a field preview shows (ReelCheck).
	local function fieldFloor(): number?
		local s = State.stage
		return if s and s.fieldOffset then Arena.cellPosition(1, 1).Y + s.fieldOffset.Y else nil
	end

	task.spawn(function()
		for _, unitType in units do
			Lineup.showUnit(unitType)
			local s = State.stage
			if token ~= State.reelToken then
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
				ReelCheck.begin(unitType, tier, fieldFloor)
				if not play(s, 1) or not hold(ReelConfig.pauseSeconds) or not play(s, ReelConfig.slowScale) then
					return
				end
				State.timeScale = 1
				ImpactEffects.setTimeScale(1)
				-- The leak check, on the field as the last play left it.
				if not hold(ReelConfig.leakSeconds) then
					return
				end
				ReelCheck.finish()
				if not hold(ReelConfig.gapSeconds) then
					return
				end
			end
		end
		showCard("REEL END")
		ReelCheck.report()
		if hold(ReelConfig.endSeconds) then
			Reel.finish()
		end
	end)
end

return Reel
