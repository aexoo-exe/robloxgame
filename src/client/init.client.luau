local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SyncCheck = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("SyncCheck"))

print("robloxgame client is alive!")
print("[client]", SyncCheck.message)

local PhaseDisplay = require(script.PhaseDisplay)
PhaseDisplay.start()
