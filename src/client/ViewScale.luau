-- How much bigger an effect should be drawn at `position` so it reads from the camera: 1 at the
-- close and dev cameras, up to MAX at the match camera (high and far). Presentation only.
--
-- The camera's distance to the point, as seen through a 70 degree field of view (a wider view
-- shows things smaller, as if further), eased between NEAR and FAR:
--   distance <= NEAR (20 studs)  -> 1
--   distance >= FAR  (60 studs)  -> MAX (1.8)
--   between: smoothstep
-- The match camera sits ~55-75 studs from the board (RenderConfig.cameraOffset, fitted); the dev
-- lineup's close and slice cameras ~10-20.
--
-- Use: local s = ViewScale.of(position) and multiply sizes (and counts or brightness) by it;
-- ViewScale.share(s) gives 0-1 of the way from 1 to MAX (for things that should grow less, such as
-- lifetimes: 1 + 0.5 * ViewScale.share(s) is +50% at the match camera).

local ViewScale = {}

ViewScale.NEAR = 20
ViewScale.FAR = 60
ViewScale.MAX = 1.8
local REFERENCE_FOV = math.tan(math.rad(70) / 2)

function ViewScale.of(position: Vector3): number
	local camera = workspace.CurrentCamera
	if not camera then
		return 1
	end
	local distance = (camera.CFrame.Position - position).Magnitude
	distance *= math.tan(math.rad(camera.FieldOfView) / 2) / REFERENCE_FOV
	local t = math.clamp((distance - ViewScale.NEAR) / (ViewScale.FAR - ViewScale.NEAR), 0, 1)
	t = t * t * (3 - 2 * t)
	return 1 + (ViewScale.MAX - 1) * t
end

-- 0 at scale 1, 1 at ViewScale.MAX.
function ViewScale.share(scale: number): number
	return math.clamp((scale - 1) / (ViewScale.MAX - 1), 0, 1)
end

return ViewScale
