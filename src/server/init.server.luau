local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SyncCheck = require(ReplicatedStorage.Shared.SyncCheck)

print("robloxgame server is alive! ^w^")
print("[server]", SyncCheck.message)

local AvatarService = require(script.AvatarService)
local CombatService = require(script.CombatService)
local ErrorLog = require(script.ErrorLog)
local HubService = require(script.HubService)
local PlayerService = require(script.PlayerService)
local PlaytestService = require(script.PlaytestService)
local RoundService = require(script.RoundService)
local VfxMeshes = require(script.VfxMeshes)

ErrorLog.start() -- first, so every later error is recorded (docs/playtest.md)
PlayerService.start()
CombatService.start()
RoundService.start()
HubService.start()
PlaytestService.start() -- how-to-play flag and match feedback
AvatarService.start() -- catalog avatars (visual only); loads in the background
VfxMeshes.start() -- VFX kit meshes into ReplicatedStorage.VfxMeshes (visual only); in the background
