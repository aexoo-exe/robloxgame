local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SyncCheck = require(ReplicatedStorage.Shared.SyncCheck)

print("robloxgame server is alive! ^w^")
print("[server]", SyncCheck.message)

local CombatService = require(script.CombatService)
local HubService = require(script.HubService)
local PlayerService = require(script.PlayerService)
local RoundService = require(script.RoundService)

PlayerService.start()
CombatService.start()
RoundService.start()
HubService.start()
