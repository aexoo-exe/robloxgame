local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SyncCheck = require(ReplicatedStorage.Shared.SyncCheck)

print("robloxgame server is alive! ^w^")
print("[server]", SyncCheck.message)

local AvatarService = require(script.AvatarService)
local CombatService = require(script.CombatService)
local HubService = require(script.HubService)
local PlayerService = require(script.PlayerService)
local RoundService = require(script.RoundService)
local VfxMeshes = require(script.VfxMeshes)

PlayerService.start()
CombatService.start()
RoundService.start()
HubService.start()
AvatarService.start() -- catalog avatars (visual only); loads in the background
VfxMeshes.start() -- VFX kit meshes into ReplicatedStorage.VfxMeshes (visual only); in the background
