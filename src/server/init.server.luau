local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SyncCheck = require(ReplicatedStorage.Shared.SyncCheck)

print("robloxgame server is alive! ^w^")
print("[server]", SyncCheck.message)

local BoardService = require(script.BoardService)
local CombatService = require(script.CombatService)
local RoundService = require(script.RoundService)

BoardService.start()
CombatService.start()
RoundService.start()
