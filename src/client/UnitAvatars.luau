-- The catalog avatar templates the server shares (src/server/AvatarService.luau): which units have
-- one ready, and waiting for a unit's avatar to settle (ready or failed). Presentation only.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UnitAvatars = {}

local function folder(): Instance?
	return ReplicatedStorage:FindFirstChild("UnitAvatars")
end

-- The unit's rest-pose avatar template if it is ready, else nil (still loading, failed or none).
function UnitAvatars.template(unitType: string): Model?
	local avatars = folder()
	if not avatars or avatars:GetAttribute(unitType) ~= "ready" then
		return nil
	end
	local model = avatars:FindFirstChild(unitType)
	return if model and model:IsA("Model") then model else nil
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

return UnitAvatars
