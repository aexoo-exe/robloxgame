-- The hub's sounds (HubConfig.sounds), on this client only and only while the player is in the hub
-- (HubAudio.setActive); everything stops when a match starts:
--   * looping background music and wind, everywhere in the hub
--   * the waterfall's sound at the falls, fading with distance
--   * a chime when the player steps onto the Play pad (their Queued attribute turns on)
--   * a tick on each of the last 5 seconds of the queue countdown, for queued players
-- A sound whose id is empty in the config is a slot still to fill, and is skipped. Presentation only.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local HubConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("HubConfig"))

local HubAudio = {}

local SOUNDS = HubConfig.sounds
local TICK_SECONDS = 5

local active = false
local loops: { Sound } = {}
local chime: Sound? = nil
local tick: Sound? = nil

-- A Sound from a config entry, or nil when its id is still empty.
local function makeSound(entry, parent: Instance, looped: boolean): Sound?
	if not entry or entry.id == "" then
		return nil
	end
	local sound = Instance.new("Sound")
	sound.SoundId = entry.id
	sound.Volume = entry.volume or 0.5
	sound.PlaybackSpeed = entry.speed or 1
	sound.Looped = looped
	sound.Parent = parent
	return sound
end

local function addLoop(sound: Sound?)
	if sound then
		table.insert(loops, sound)
		if active then
			sound:Play()
		end
	end
end

function HubAudio.setActive(value: boolean)
	if value == active then
		return
	end
	active = value
	for _, sound in loops do
		if value then
			sound:Play()
		else
			sound:Stop()
		end
	end
	if not value then
		if chime then
			chime:Stop()
		end
		if tick then
			tick:Stop()
		end
	end
end

function HubAudio.start()
	local player = Players.LocalPlayer
	addLoop(makeSound(SOUNDS.music, SoundService, true))
	addLoop(makeSound(SOUNDS.wind, SoundService, true))
	chime = makeSound(SOUNDS.padChime, SoundService, false)
	tick = makeSound(SOUNDS.countdownTick, SoundService, false)

	-- The falls: a sound on the waterfall's main sheet, heard only nearby.
	task.spawn(function()
		local hub = workspace:WaitForChild("Hub")
		local function attach(instance: Instance)
			if instance:IsA("BasePart") and instance:GetAttribute("Waterfall") then
				local sound = makeSound(SOUNDS.waterfall, instance, true)
				if sound then
					sound.RollOffMode = Enum.RollOffMode.InverseTapered
					sound.RollOffMinDistance = 12
					sound.RollOffMaxDistance = SOUNDS.waterfall.reach or 90
					addLoop(sound)
				end
			end
		end
		hub.DescendantAdded:Connect(attach)
		for _, descendant in hub:GetDescendants() do
			attach(descendant)
		end
	end)

	player:GetAttributeChangedSignal("Queued"):Connect(function()
		if active and chime and player:GetAttribute("Queued") == true then
			chime:Play()
		end
	end)

	-- The countdown ticks.
	task.spawn(function()
		local hubState = ReplicatedStorage:WaitForChild("HubState")
		local lastTick = -1
		while true do
			local startsAt = hubState:GetAttribute("StartsAt") or 0
			local remaining = math.ceil(startsAt - workspace:GetServerTimeNow())
			local counting = active and startsAt > 0 and player:GetAttribute("Queued") == true
			if counting and remaining >= 1 and remaining <= TICK_SECONDS and remaining ~= lastTick then
				lastTick = remaining
				if tick then
					tick:Play()
				end
			elseif not counting then
				lastTick = -1
			end
			task.wait(0.1)
		end
	end)
end

return HubAudio
