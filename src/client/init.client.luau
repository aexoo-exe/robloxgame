local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SyncCheck = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("SyncCheck"))

print("robloxgame client is alive!")
print("[client]", SyncCheck.message)

local Arena = require(script.Arena)
local BoardController = require(script.BoardController)
local Celebrate = require(script.Celebrate)
local CombatPlayback = require(script.CombatPlayback)
local MatchHud = require(script.MatchHud)
local PlayerList = require(script.PlayerList)
local RefusalNotice = require(script.RefusalNotice)
local RewardScreen = require(script.RewardScreen)
local RoundResult = require(script.RoundResult)
local ShopPanel = require(script.ShopPanel)
local TopBar = require(script.TopBar)
local TraitPanel = require(script.TraitPanel)
local UI = require(script.UI)
local UnitInfoPanel = require(script.UnitInfoPanel)
local UnitTooltip = require(script.UnitTooltip)

Arena.start()
BoardController.start()
CombatPlayback.start()
TopBar.start()
ShopPanel.start()
PlayerList.start()
TraitPanel.start()
UnitInfoPanel.start()
RoundResult.start()
MatchHud.start()
RewardScreen.start()
UnitTooltip.start()
RefusalNotice.start()

-- Keep the board and bench in the part of the screen the HUD leaves free.
local function fitBoard()
	Arena.setViewInsets(UI.boardInsets())
end
workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(fitBoard)
fitBoard()

-- Upgrades get a sparkle and a star badge over the unit.
BoardController.onUpgrade(function(unit)
	local position = BoardController.unitPosition(unit.id)
	if position then
		Celebrate.starUp(position, unit.starLevel)
	end
end)
