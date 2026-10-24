-- The shared outline (FigureConfig.outline): a thin dark rim with no fill on unit figures, so
-- avatars, hand-built figures and models read as one cast. Only while the local player is in a
-- match, only on units in the world near the camera (the board and fight they are watching), and
-- at most `max` at once, nearest first: Roblox draws at most 31 Highlights, so the rest stay free
-- for hit flashes, selection and ultimate callouts. Past the cap the farthest units simply go
-- without. A fixed pool of Highlights is reused (never more than `max` exist); each sits on its
-- unit's hitbox (UnitView tags them), which holds every piece of the figure. Presentation only.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local FigureConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("FigureConfig"))

local UnitView = require(script.Parent.UnitView)

local UnitOutlines = {}

local CONFIG = FigureConfig.outline

local pool: { Highlight } = {}
local assigned: { [Instance]: Highlight } = {}

local function newHighlight(): Highlight
	local highlight = Instance.new("Highlight")
	highlight.Name = "UnitOutline"
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	highlight.FillTransparency = 1
	highlight.OutlineColor = CONFIG.color
	highlight.OutlineTransparency = CONFIG.transparency
	return highlight
end

local function release(part: Instance)
	local highlight = assigned[part]
	if not highlight then
		return
	end
	assigned[part] = nil
	if part.Parent and highlight.Parent == part then
		highlight.Adornee = nil
		highlight.Parent = nil
		table.insert(pool, highlight)
	else
		-- The unit was destroyed, and its outline with it: not reusable (a new one is made later).
		pcall(highlight.Destroy, highlight)
	end
end

local function releaseAll()
	for part in assigned do
		release(part)
	end
end

-- The units to outline now: tagged hitboxes in the world within reach, nearest first, at most max.
local function pick(): { BasePart }
	local camera = workspace.CurrentCamera
	if not camera then
		return {}
	end
	local from = camera.CFrame.Position
	local candidates = {}
	for _, part in CollectionService:GetTagged(UnitView.OUTLINE_TAG) do
		if part:IsA("BasePart") and part:IsDescendantOf(workspace) then
			local distance = (part.Position - from).Magnitude
			if distance <= CONFIG.maxDistance then
				table.insert(candidates, { part = part, distance = distance })
			end
		end
	end
	table.sort(candidates, function(a, b)
		return a.distance < b.distance
	end)
	local chosen = {}
	for index = 1, math.min(CONFIG.max, #candidates) do
		chosen[index] = candidates[index].part
	end
	return chosen
end

local function refresh()
	if not CONFIG.enabled or Players.LocalPlayer:GetAttribute("InMatch") ~= true then
		releaseAll()
		return
	end
	local chosen = pick()
	local keep = {}
	for _, part in chosen do
		keep[part] = true
	end
	for part in assigned do
		if not keep[part] or not part.Parent then
			release(part)
		end
	end
	for _, part in chosen do
		if not assigned[part] then
			local highlight = table.remove(pool) or newHighlight()
			highlight.Adornee = part
			highlight.Parent = part
			assigned[part] = highlight
		end
	end
end

function UnitOutlines.start()
	if not CONFIG.enabled then
		return
	end
	task.spawn(function()
		while true do
			local ok, err = pcall(refresh)
			if not ok then
				warn("[UnitOutlines] " .. tostring(err))
			end
			task.wait(CONFIG.refresh)
		end
	end)
end

return UnitOutlines
