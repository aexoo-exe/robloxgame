-- Plays named sound effects (SfxConfig) for presentation: non-positional, each play with its own
-- pitch and volume variation, cleaned up when it ends. A name whose id is empty plays its built-in
-- fallback (UltimateConfig.sounds) if it has one, else nothing (silently), so effects can call
-- Sfx.play before the real sounds are chosen.
--
-- Use: Sfx.play("whoosh"), Sfx.play("finisherBoom", { volume = 1.2 }). Returns whether it played.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local SfxConfig = require(Shared:WaitForChild("SfxConfig"))
local UltimateConfig = require(Shared:WaitForChild("UltimateConfig"))

local Sfx = {}

local LONGEST = 6 -- seconds a sound may live before it is cleaned up anyway

local function content(id: string): string
	if string.match(id, "^%d+$") then
		return "rbxassetid://" .. id
	end
	return id
end

export type PlayOptions = {
	volume: number?, -- times the configured volume
	pitch: number?, -- times the picked pitch
}

-- Plays sound `name` now. False when it has no id and no fallback (or is unknown).
function Sfx.play(name: string, opts: PlayOptions?): boolean
	local spec = SfxConfig.sounds[name]
	if not spec then
		return false
	end
	local id, volume, pitch, length = spec.id, spec.volume or 0.5, 1, nil
	if id == "" or id == nil then
		local fallback = spec.fallback and UltimateConfig.sounds[spec.fallback]
		if not fallback then
			return false
		end
		id, volume, pitch, length = fallback.id, fallback.volume, fallback.speed or 1, fallback.length
	end
	local range = spec.pitch or { 1, 1 }
	pitch *= range[1] + (range[2] - range[1]) * math.random()
	local jitter = spec.volumeJitter or 0
	volume *= 1 + (math.random() * 2 - 1) * jitter
	local o = opts or {}
	local sound = Instance.new("Sound")
	sound.SoundId = content(id)
	sound.Volume = math.clamp(volume * (o.volume or 1), 0, 10)
	sound.PlaybackSpeed = pitch * (o.pitch or 1)
	sound.Parent = SoundService
	sound.Ended:Once(function()
		sound:Destroy()
	end)
	sound:Play()
	task.delay(length or LONGEST, function()
		if sound.Parent then
			sound:Destroy()
		end
	end)
	return true
end

return Sfx
