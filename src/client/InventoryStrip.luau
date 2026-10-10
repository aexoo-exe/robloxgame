-- The item inventory strip, bottom left above the shop, next to the bench: every unequipped item
-- (PlayerState view `inventory`) as an icon. To equip one (during Preparation):
--   * drag it (mouse or touch) onto one of your units on the board or bench, or
--   * tap it to pick it up (it lights up), then tap the unit. Tap it again to put it down.
-- An item in a unit's slot can be picked up the same way from the unit info panel and tapped onto
-- another unit (a move). While a unit is selected, items sharing one of its recommendation tags
-- (Items.unitTags) are outlined in gold; tags never block equipping. Items that just arrived
-- (picked from an item choice, or returned by a sale, merge or unequip) flash green for a moment.
-- The client only asks; the server decides (RequestEquipItem, RequestMoveItem). Presentation only.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ItemConfig = require(Shared:WaitForChild("ItemConfig"))
local Items = require(Shared:WaitForChild("Items"))
local Phase = require(Shared:WaitForChild("Phase"))
local RemoteNames = require(Shared:WaitForChild("RemoteNames"))
local UITheme = require(Shared:WaitForChild("UITheme"))
local UnitConfig = require(Shared:WaitForChild("UnitConfig"))

local Arena = require(script.Parent.Arena)
local BoardController = require(script.Parent.BoardController)
local ItemIcon = require(script.Parent.ItemIcon)
local ItemSelection = require(script.Parent.ItemSelection)
local UI = require(script.Parent.UI)

local InventoryStrip = {}

local COLORS = UITheme.colors
local FONTS = UITheme.fonts
local SIZES = UITheme.sizes
local ICON = 26
local GAP = 4
local DRAG_THRESHOLD = 8 -- pixels before a press becomes a drag
local SELECTED_COLOR = Color3.new(1, 1, 1)
local FRESH_COLOR = Color3.fromRGB(120, 255, 140) -- an item that just arrived
local FRESH_SECONDS = 1.6

function InventoryStrip.start()
	local matchState = ReplicatedStorage:WaitForChild("MatchState")
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local requestEquip = remotes:WaitForChild(RemoteNames.RequestEquipItem)
	local requestMove = remotes:WaitForChild(RemoteNames.RequestMoveItem)

	local _, root = UI.screen("InventoryStrip", 4)
	local panel = UI.panel(root, UDim2.fromOffset(SIZES.traitPanelWidth, 0), false)
	panel.AutomaticSize = Enum.AutomaticSize.Y
	panel.AnchorPoint = Vector2.new(0, 1)
	panel.Position = UDim2.new(0, SIZES.margin, 1, -(UITheme.boardInsets.bottom + 6))
	UI.padding(panel, 6)
	UI.list(panel, 4)
	panel.Visible = false

	-- Where "+item" text rises from: the panel's top edge (the panel itself lays out its children).
	local arrivalAnchor = Instance.new("Frame")
	arrivalAnchor.BackgroundTransparency = 1
	arrivalAnchor.Size = UDim2.fromOffset(SIZES.traitPanelWidth, 0)
	arrivalAnchor.Position = panel.Position - UDim2.fromOffset(0, 40)
	arrivalAnchor.Parent = root
	local rootScale = root:FindFirstChildOfClass("UIScale") :: UIScale
	panel:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		local height = panel.AbsoluteSize.Y / math.max(rootScale.Scale, 0.01) -- in reference pixels
		arrivalAnchor.Position = panel.Position - UDim2.fromOffset(0, height)
	end)

	local title = UI.text(panel, "", SIZES.textSmall, FONTS.body, COLORS.textDim)
	title.LayoutOrder = 1

	local grid = Instance.new("Frame")
	grid.LayoutOrder = 2
	grid.BackgroundTransparency = 1
	grid.Size = UDim2.fromScale(1, 0)
	grid.AutomaticSize = Enum.AutomaticSize.Y
	local gridLayout = Instance.new("UIGridLayout")
	gridLayout.CellSize = UDim2.fromOffset(ICON, ICON)
	gridLayout.CellPadding = UDim2.fromOffset(GAP, GAP)
	gridLayout.SortOrder = Enum.SortOrder.LayoutOrder
	gridLayout.Parent = grid
	grid.Parent = panel

	-- The icon that follows the pointer while dragging, in its own unscaled screen.
	local dragGui = Instance.new("ScreenGui")
	dragGui.Name = "ItemDrag"
	dragGui.IgnoreGuiInset = true
	dragGui.DisplayOrder = 20
	dragGui.ResetOnSpawn = false
	dragGui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

	local inventory: { string } = {}
	local icons: { Frame } = {}
	local tags: { string } = {}
	local press: { index: number, start: Vector2, input: InputObject }? = nil
	local ghost: Frame? = nil

	local function canEquip(): boolean
		return matchState:GetAttribute("Phase") == Phase.Preparation
	end

	local fresh: { [number]: number } = {} -- inventory index -> os.clock() its arrival highlight ends

	local function refreshHighlights()
		local selection = ItemSelection.get()
		local now = os.clock()
		for index, icon in icons do
			local itemId = inventory[index]
			if fresh[index] and now < fresh[index] then
				ItemIcon.setHighlight(icon, FRESH_COLOR)
			elseif selection and selection.kind == "inventory" and selection.index == index then
				ItemIcon.setHighlight(icon, SELECTED_COLOR)
			elseif #tags > 0 and Items.matches(itemId, tags) then
				ItemIcon.setHighlight(icon, COLORS.gold)
			else
				ItemIcon.setHighlight(icon, nil)
			end
		end
	end

	local function render()
		for _, icon in icons do
			icon:Destroy()
		end
		table.clear(icons)
		title.Text = string.format("ITEMS %d/%d", #inventory, ItemConfig.rules.inventoryCap)
		panel.Visible = #inventory > 0
		for index, itemId in inventory do
			local icon = ItemIcon.new(itemId, ICON, grid)
			icon.LayoutOrder = index
			icon.Active = true
			icon.InputBegan:Connect(function(input)
				local isPress = input.UserInputType == Enum.UserInputType.MouseButton1
					or input.UserInputType == Enum.UserInputType.Touch
				if isPress and not press then
					press = { index = index, start = Vector2.new(input.Position.X, input.Position.Y), input = input }
				end
			end)
			icons[index] = icon
		end
		refreshHighlights()
	end

	local function endDrag()
		if ghost then
			ghost:Destroy()
			ghost = nil
		end
		press = nil
	end

	-- A tap toggles picking the item up.
	local function tap(index: number)
		local selection = ItemSelection.get()
		if selection and selection.kind == "inventory" and selection.index == index then
			ItemSelection.clear()
		elseif inventory[index] and canEquip() then
			ItemSelection.set({ kind = "inventory", index = index, itemId = inventory[index] })
		end
	end

	-- A drop over one of the player's units equips the item there.
	local function drop(index: number, screenPosition: Vector2)
		local hit = Arena.raycast(screenPosition)
		local unitId = if hit then hit.Instance:GetAttribute("UnitId") else nil
		if unitId and canEquip() and inventory[index] then
			requestEquip:FireServer(index, unitId)
		end
	end

	UserInputService.InputChanged:Connect(function(input)
		if not press then
			return
		end
		local touch = press.input.UserInputType == Enum.UserInputType.Touch
		if
			(touch and input ~= press.input) or (not touch and input.UserInputType ~= Enum.UserInputType.MouseMovement)
		then
			return
		end
		local position = Vector2.new(input.Position.X, input.Position.Y)
		if not ghost and (position - press.start).Magnitude >= DRAG_THRESHOLD and canEquip() then
			ghost = ItemIcon.new(inventory[press.index], ICON + 6, dragGui)
			ItemSelection.clear()
		end
		if ghost then
			ghost.AnchorPoint = Vector2.new(0.5, 0.5)
			ghost.Position = UDim2.fromOffset(position.X, position.Y)
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if not press then
			return
		end
		local isPress = input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
		if not isPress or (press.input.UserInputType == Enum.UserInputType.Touch and input ~= press.input) then
			return
		end
		local index = press.index
		if ghost then
			drop(index, Vector2.new(input.Position.X, input.Position.Y))
		else
			tap(index)
		end
		endDrag()
	end)

	-- With an item picked up, a tap on a unit places it there.
	BoardController.setUnitTapHandler(function(unitId: string): boolean
		local selection = ItemSelection.get()
		if not selection then
			return false
		end
		if selection.kind == "inventory" then
			requestEquip:FireServer(selection.index, unitId)
		elseif selection.kind == "unit" and selection.unitId ~= unitId then
			requestMove:FireServer(selection.unitId, selection.slot, unitId)
		end
		ItemSelection.clear()
		return true
	end)

	ItemSelection.onChanged(refreshHighlights)
	BoardController.onInspect(function(info)
		local unit = if info then UnitConfig[info.unitType] else nil
		tags = if unit then Items.unitTags(unit.classes) else {}
		refreshHighlights()
	end)
	-- Items that just arrived (picked, or returned by a sale, a merge or an unequip) light up and pop
	-- for a moment, so the player sees where they went.
	local function flashArrivals(previous: { string })
		local had: { [string]: number } = {}
		for _, itemId in previous do
			had[itemId] = (had[itemId] or 0) + 1
		end
		local seen: { [string]: number } = {}
		table.clear(fresh)
		local names = {}
		for index, itemId in inventory do
			seen[itemId] = (seen[itemId] or 0) + 1
			if seen[itemId] > (had[itemId] or 0) then
				fresh[index] = os.clock() + FRESH_SECONDS
				UI.pop(icons[index], 1.5)
				table.insert(names, ItemIcon.name(itemId))
			end
		end
		if #names == 0 then
			return
		end
		refreshHighlights()
		UI.floatUp(arrivalAnchor, "+" .. table.concat(names, ", +"), COLORS.gold)
		task.delay(FRESH_SECONDS, refreshHighlights)
	end

	remotes:WaitForChild(RemoteNames.PlayerStateUpdated).OnClientEvent:Connect(function(view)
		local previous = inventory
		inventory = view.inventory or {}
		ItemSelection.clear()
		render()
		flashArrivals(previous)
	end)
	matchState:GetAttributeChangedSignal("Phase"):Connect(function()
		if not canEquip() then
			ItemSelection.clear()
			endDrag()
		end
	end)
	render()
end

return InventoryStrip
