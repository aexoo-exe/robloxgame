-- Plays back the fight the server simulated. CombatStarted carries the starting units and every
-- event with its tick; events are applied as server time passes `startsAt`. Presentation only.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BoardConfig = require(Shared:WaitForChild("BoardConfig"))
local HexGrid = require(Shared:WaitForChild("HexGrid"))
local Phase = require(Shared:WaitForChild("Phase"))
local RemoteNames = require(Shared:WaitForChild("RemoteNames"))
local RenderConfig = require(Shared:WaitForChild("RenderConfig"))
local UnitConfig = require(Shared:WaitForChild("UnitConfig"))

local Arena = require(script.Parent.Arena)
local UnitView = require(script.Parent.UnitView)

local CombatPlayback = {}

local views: { [number]: UnitView.UnitView } = {}
local connection: RBXScriptConnection? = nil

local function clear()
	if connection then
		connection:Disconnect()
		connection = nil
	end
	for _, view in views do
		UnitView.destroy(view)
	end
	table.clear(views)
end

local function play(playback)
	clear()
	local result = playback.result

	-- Show the local player's side nearest the camera. Spectators see side 1's view.
	local localSide = if playback.sideUserIds[2] == Players.LocalPlayer.UserId then 2 else 1
	local function toWorld(column: number, row: number): Vector3
		if localSide == 2 then
			column, row = HexGrid.rotateHalfTurn(column, row, BoardConfig.columns, BoardConfig.rows * 2)
		end
		return Arena.cellPosition(column, row)
	end

	local unitsByIndex = {}
	for _, unit in result.units do
		unitsByIndex[unit.index] = unit
		local color = if unit.side == localSide then RenderConfig.ownUnitColor else RenderConfig.enemyUnitColor
		views[unit.index] = UnitView.new(unit.unitType, color, toWorld(unit.column, unit.row), Arena.folder)
	end

	local function apply(event)
		local view = views[event.unit]
		if event.kind == "Move" and view then
			local moveSeconds = 1 / UnitConfig[unitsByIndex[event.unit].unitType].moveSpeed
			UnitView.moveTo(view, toWorld(event.column, event.row), moveSeconds)
		elseif event.kind == "Attack" then
			local targetView = views[event.target]
			if targetView then
				UnitView.setHealth(targetView, event.health / unitsByIndex[event.target].maxHealth)
				UnitView.flash(targetView)
			end
		elseif event.kind == "Death" and view then
			UnitView.destroy(view)
			views[event.unit] = nil
		end
	end

	local nextEvent = 1
	connection = RunService.RenderStepped:Connect(function()
		local currentTick = (workspace:GetServerTimeNow() - playback.startsAt) * result.ticksPerSecond
		while nextEvent <= #result.events and result.events[nextEvent].tick <= currentTick do
			apply(result.events[nextEvent])
			nextEvent += 1
		end
		if nextEvent > #result.events and connection then
			connection:Disconnect()
			connection = nil
		end
	end)
end

function CombatPlayback.start()
	local matchState = ReplicatedStorage:WaitForChild("MatchState")
	local remotes = ReplicatedStorage:WaitForChild("Remotes")

	remotes:WaitForChild(RemoteNames.CombatStarted).OnClientEvent:Connect(play)

	-- Survivors stay on the field through Results; clear them when the next round's board appears.
	matchState:GetAttributeChangedSignal("Phase"):Connect(function()
		local phase = matchState:GetAttribute("Phase")
		if phase == Phase.Preparation or phase == Phase.Waiting then
			clear()
		end
	end)
end

return CombatPlayback
