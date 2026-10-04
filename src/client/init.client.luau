local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SyncCheck = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("SyncCheck"))

print("robloxgame client is alive!")
print("[client]", SyncCheck.message)

local Arena = require(script.Arena)
local BoardController = require(script.BoardController)
local CombatPlayback = require(script.CombatPlayback)
local PhaseDisplay = require(script.PhaseDisplay)
local ShopPanel = require(script.ShopPanel)

Arena.start()
BoardController.start()
CombatPlayback.start()
PhaseDisplay.start()
ShopPanel.start()
