-- A short toast under the top bar when the server refuses one of the player's requests
-- (RequestRefused), for example "Not enough gold". It pops in and hides itself after
-- UITheme.motion.toastTime unless a newer message replaced it. Presentation only.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local RemoteNames = require(Shared:WaitForChild("RemoteNames"))
local UITheme = require(Shared:WaitForChild("UITheme"))

local UI = require(script.Parent.UI)

local RefusalNotice = {}

local showReason: (string) -> () = function() end

function RefusalNotice.start()
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local _, root = UI.screen("RefusalNotice", 10)

	local toast = UI.panel(root, UDim2.fromOffset(0, 0), false)
	toast.AutomaticSize = Enum.AutomaticSize.XY
	toast.AnchorPoint = Vector2.new(0.5, 0)
	toast.Position = UDim2.new(0.5, 0, 0, UITheme.sizes.topBarHeight + 16)
	toast.BackgroundColor3 = UITheme.colors.sell
	toast.Visible = false
	local row = UI.row(toast, 8)
	UI.padding(row, 8)
	UI.glyph(row, UITheme.icons.loss, UITheme.sizes.textLarge).LayoutOrder = 1
	local label = UI.text(row, "", UITheme.sizes.textLarge, UITheme.fonts.display)
	label.LayoutOrder = 2

	local shownCount = 0
	showReason = function(reason: string)
		shownCount += 1
		local thisMessage = shownCount
		label.Text = string.upper(reason)
		toast.Visible = true
		UI.pop(toast, 1.15)
		task.delay(UITheme.motion.toastTime, function()
			if shownCount == thisMessage then
				toast.Visible = false
			end
		end)
	end
	remotes:WaitForChild(RemoteNames.RequestRefused).OnClientEvent:Connect(showReason)
end

-- Shows a refusal the client already knows the server would give (for example
-- PlayerState.Refusal.ItemsLocked when an item is dragged during combat), without a request.
function RefusalNotice.show(reason: string)
	showReason(reason)
end

return RefusalNotice
