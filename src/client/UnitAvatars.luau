-- The catalog avatar templates the server shares (src/server/AvatarService.luau): which units have
-- one ready, and waiting for a unit's avatar to settle (ready or failed). Presentation only.
--
-- No look swaps mid-match: while the local player is in a match (InMatch, from the intro on), the
-- set of avatars to use is locked: the ones ready (template replicated) when the match's intro
-- started, or when this client joined a match already running. A unit whose avatar becomes ready
-- later stays its figure for the rest of that match; the next match uses it. The server waits
-- (capped) for avatars still loading before the intro (AvatarService.waitSettled). In the hub every
-- template is preloaded (ContentProvider) as it arrives, so its meshes and textures are in memory
-- before a match.

local ContentProvider = game:GetService("ContentProvider")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UnitAvatars = {}

local locked: { [string]: boolean }? = nil -- the avatars this match uses, while locked
local preloaded: { [Instance]: boolean } = {}

local function folder(): Instance?
	return ReplicatedStorage:FindFirstChild("UnitAvatars")
end

-- The ready template, ignoring the lock.
local function readyTemplate(unitType: string): Model?
	local avatars = folder()
	if not avatars or avatars:GetAttribute(unitType) ~= "ready" then
		return nil
	end
	local model = avatars:FindFirstChild(unitType)
	return if model and model:IsA("Model") then model else nil
end

-- The unit's rest-pose avatar template if it is ready (and, during a match, in the match's locked
-- set), else nil (still loading, failed, none, or ready too late for this match).
function UnitAvatars.template(unitType: string): Model?
	if locked and not locked[unitType] then
		return nil
	end
	return readyTemplate(unitType)
end

-- Calls `callback` once the unit's avatar is ready or has failed, or after `timeout` seconds,
-- whichever comes first. At once for a unit that is not loading.
function UnitAvatars.whenSettled(unitType: string, timeout: number, callback: () -> ())
	task.spawn(function()
		local deadline = os.clock() + timeout
		local avatars = ReplicatedStorage:WaitForChild("UnitAvatars", timeout)
		while avatars and os.clock() < deadline do
			local status = avatars:GetAttribute(unitType)
			if status ~= "loading" and (status ~= "ready" or avatars:FindFirstChild(unitType)) then
				break
			end
			task.wait(0.2)
		end
		callback()
	end)
end

local function lock()
	local set = {}
	local avatars = folder()
	if avatars then
		for _, child in avatars:GetChildren() do
			if readyTemplate(child.Name) then
				set[child.Name] = true
			end
		end
	end
	locked = set
end

local function preload(model: Instance)
	if preloaded[model] or not model:IsA("Model") then
		return
	end
	preloaded[model] = true
	task.spawn(function()
		pcall(ContentProvider.PreloadAsync, ContentProvider, { model })
	end)
end

-- Starts the hub preloading and the per-match lock. Call before any figure is built.
function UnitAvatars.start()
	local localPlayer = Players.LocalPlayer
	task.spawn(function()
		local avatars = ReplicatedStorage:WaitForChild("UnitAvatars")
		for _, child in avatars:GetChildren() do
			preload(child)
		end
		avatars.ChildAdded:Connect(preload)
	end)
	-- Locked from the intro on (the server has waited for the avatars by then), or at once when
	-- this client joins a match already running; unlocked back in the hub.
	local matchState = ReplicatedStorage:WaitForChild("MatchState")
	local function update()
		local inMatch = localPlayer:GetAttribute("InMatch") == true
		local running = matchState:GetAttribute("Phase") ~= "Waiting"
		if inMatch and running and not locked then
			lock()
		elseif not inMatch then
			locked = nil
		end
	end
	localPlayer:GetAttributeChangedSignal("InMatch"):Connect(update)
	matchState:GetAttributeChangedSignal("Phase"):Connect(update)
	update()
end

return UnitAvatars
