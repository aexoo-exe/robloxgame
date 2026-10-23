-- DevLineup's on-screen panel while the lineup is open: Prev / Next / Dump FX buttons, the title
-- (the unit and, in a close-up, the arena and its camera), the key help, and the reel's title card.
-- Also the freeze toggle (Dump FX / O). Studio only (see DevLineup).

local Players = game:GetService("Players")
local StarterGui = game:GetService("StarterGui")

local State = require(script.Parent.State)

local ImpactEffects = require(script.Parent.Parent.ImpactEffects)
local VfxDebug = require(script.Parent.Parent.VfxDebug)

local Hud = {}

-- The HUD title, with the arena and its camera in a close-up ("gray / close").
function Hud.refreshTitle()
	if State.hudTitle then
		local arena = if State.arenaMode == "off" then "arena off" else State.arenaMode .. " / " .. State.arenaCamera
		State.hudTitle.Text = if State.stage then State.titleText .. "   " .. arena else State.titleText
	end
end

-- Shows the key help and the title (the unit in a close-up) on the lineup's on-screen panel.
function Hud.setHud(title: string, help: string)
	State.titleText = title
	if State.hudHelp then
		State.hudHelp.Text = help
	end
	Hud.refreshTitle()
end

-- Freezes every live effect (time 0, particles too) and prints each instance (VfxDebug.dumpLive);
-- called again, resumes. The "Dump FX" button and the O key.
function Hud.toggleFreeze()
	if State.timeScale ~= 0 then
		State.frozenScale = State.timeScale
		State.timeScale = 0
		ImpactEffects.setTimeScale(0)
		print("[DevLineup] effects frozen (Dump FX / O again to resume)")
		local ok, problem = pcall(VfxDebug.dumpLive)
		if not ok then
			warn("[DevLineup] live-effects dump failed: " .. tostring(problem))
		end
	else
		State.timeScale = State.frozenScale or 1
		ImpactEffects.setTimeScale(State.timeScale)
		print("[DevLineup] effects resumed")
	end
	if State.freezeButton then
		State.freezeButton.Text = if State.timeScale == 0 then "Resume" else "Dump FX"
	end
end

local function hudButton(parent: Instance, text: string, x: number, by: number | () -> ()): TextButton
	local button = Instance.new("TextButton")
	button.AnchorPoint = Vector2.new(0.5, 1)
	button.Position = UDim2.new(0.5, x, 1, -16)
	button.Size = UDim2.fromOffset(96, 40)
	button.BackgroundColor3 = Color3.fromRGB(40, 44, 54)
	button.BackgroundTransparency = 0.15
	button.TextColor3 = Color3.new(1, 1, 1)
	button.Font = Enum.Font.GothamBold
	button.TextSize = 16
	button.Text = text
	button.AutoButtonColor = true
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = button
	button.Activated:Connect(function()
		if type(by) == "function" then
			by()
		elseif State.step then
			State.step(by)
		end
	end)
	button.Parent = parent
	return button
end

-- The on-screen panel while the lineup is open: Prev / Next buttons, the shown unit, key help.
function Hud.open()
	local gui = Instance.new("ScreenGui")
	gui.Name = "DevLineupHud"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 50
	hudButton(gui, "< Prev", -110, -1)
	hudButton(gui, "Next >", 110, 1)
	State.freezeButton = hudButton(gui, "Dump FX", 220, Hud.toggleFreeze)
	local title = Instance.new("TextLabel")
	title.AnchorPoint = Vector2.new(0.5, 1)
	-- Above the buttons, wide enough for the arena / camera suffix.
	title.Position = UDim2.new(0.5, 0, 1, -62)
	title.Size = UDim2.fromOffset(460, 24)
	title.BackgroundTransparency = 1
	title.TextColor3 = Color3.new(1, 1, 1)
	title.TextStrokeTransparency = 0.3
	title.Font = Enum.Font.GothamBold
	title.TextSize = 18
	title.Parent = gui
	local help = Instance.new("TextLabel")
	help.AnchorPoint = Vector2.new(0, 1)
	help.Position = UDim2.new(0, 12, 1, -66)
	help.Size = UDim2.fromOffset(560, 80)
	help.BackgroundColor3 = Color3.fromRGB(20, 22, 28)
	help.BackgroundTransparency = 0.35
	help.TextColor3 = Color3.fromRGB(230, 232, 240)
	help.Font = Enum.Font.Gotham
	help.TextSize = 13
	help.TextXAlignment = Enum.TextXAlignment.Left
	help.TextYAlignment = Enum.TextYAlignment.Top
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 8)
	padding.PaddingTop = UDim.new(0, 6)
	padding.Parent = help
	help.Parent = gui
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	State.hud, State.hudTitle, State.hudHelp = gui, title, help
	-- The reel's title card: large white text on a black bar across the top, readable in a
	-- compressed recording. Its own gui, so it stays while the panel is hidden.
	local cardGui = Instance.new("ScreenGui")
	cardGui.Name = "DevLineupReelCard"
	cardGui.ResetOnSpawn = false
	cardGui.IgnoreGuiInset = true
	cardGui.DisplayOrder = 100
	cardGui.Enabled = false
	local card = Instance.new("TextLabel")
	card.Size = UDim2.new(1, 0, 0, 150)
	card.BackgroundColor3 = Color3.new(0, 0, 0)
	card.BackgroundTransparency = 0
	card.BorderSizePixel = 0
	card.TextColor3 = Color3.new(1, 1, 1)
	card.Font = Enum.Font.GothamBlack
	card.TextSize = 72
	card.Parent = cardGui
	cardGui.Parent = gui.Parent
	State.reelGui, State.reelCard = cardGui, card
	-- The emotes menu takes "."; off while the lineup is open.
	local ok, enabled = pcall(StarterGui.GetCoreGuiEnabled, StarterGui, Enum.CoreGuiType.EmotesMenu)
	if ok then
		State.emotesWereEnabled = enabled
		pcall(StarterGui.SetCoreGuiEnabled, StarterGui, Enum.CoreGuiType.EmotesMenu, false)
	end
end

function Hud.close()
	if State.hud then
		State.hud:Destroy()
	end
	State.hud, State.hudTitle, State.hudHelp = nil, nil, nil
	if State.reelGui then
		State.reelGui:Destroy()
	end
	State.reelGui, State.reelCard = nil, nil
	if State.emotesWereEnabled ~= nil then
		pcall(StarterGui.SetCoreGuiEnabled, StarterGui, Enum.CoreGuiType.EmotesMenu, State.emotesWereEnabled)
		State.emotesWereEnabled = nil
	end
end

return Hud
