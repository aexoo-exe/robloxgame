local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SyncCheck = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("SyncCheck"))

print("robloxgame client is alive!")
print("[client]", SyncCheck.message)

local Arena = require(script.Arena)
local BoardController = require(script.BoardController)
local CombatPlayback = require(script.CombatPlayback)
local MatchHud = require(script.MatchHud)
local PhaseDisplay = require(script.PhaseDisplay)
local RefusalNotice = require(script.RefusalNotice)
local ShopPanel = require(script.ShopPanel)
local TraitPanel = require(script.TraitPanel)

Arena.start()
BoardController.start()
CombatPlayback.start()
PhaseDisplay.start()
MatchHud.start()
ShopPanel.start()
TraitPanel.start()
RefusalNotice.start()
