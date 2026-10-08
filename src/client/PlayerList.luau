-- The player list on the right edge: every participant with their avatar, a health bar and number,
-- sorted by standing (still playing by health, then eliminated by placement). You are outlined in
-- gold; your current opponent (or the player whose ghost you fight) is outlined in red with a
-- crossed-swords tag. Eliminated players are dimmed and show their placement. Presentation only:
-- reads MatchState.Players and redraws a few times per second.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local MatchConfig = require(Shared:WaitForChild("MatchConfig"))
local UITheme = require(Shared:WaitForChild("UITheme"))

local UI = require(script.Parent.UI)

local PlayerList = {}

local COLORS = UITheme.colors
local FONTS = UITheme.fonts
local SIZES = UITheme.sizes
local REFRESH_SECONDS = 0.25
local AVATAR = 30

type Entry = {
	userId: number,
	name: string,
	health: number,
	placement: number,
	eliminated: boolean,
	connected: boolean,
}

type Row = {
	frame: Frame,
	stroke: UIStroke,
	avatar: ImageLabel,
	initial: TextLabel,
	name: TextLabel,
	healthBar: UI.Bar,
	healthLabel: TextLabel,
	tag: TextLabel,
	shownUserId: number?, -- the player this row showed last
	shownHealth: number?,
}

-- Participants in display order: still playing by HP (highest first), then eliminated by placement.
local function sortedEntries(playersFolder: Instance): { Entry }
	local entries = {}
	for _, folder in playersFolder:GetChildren() do
		table.insert(entries, {
			userId = folder:GetAttribute("UserId"),
			name = folder:GetAttribute("DisplayName") or folder.Name,
			health = folder:GetAttribute("Health") or 0,
			placement = folder:GetAttribute("Placement") or 0,
			eliminated = folder:GetAttribute("Eliminated") == true,
			connected = folder:GetAttribute("Connected") ~= false,
		})
	end
	table.sort(entries, function(a, b)
		if a.eliminated ~= b.eliminated then
			return not a.eliminated
		elseif a.eliminated then
			return a.placement < b.placement
		elseif a.health ~= b.health then
			return a.health > b.health
		end
		return a.name < b.name
	end)
	return entries
end

local thumbnails: { [number]: string } = {}

-- The player's headshot, fetched once in the background. Practice and bot ids have none.
local function requestThumbnail(userId: number)
	if thumbnails[userId] ~= nil or userId <= 0 then
		return
	end
	thumbnails[userId] = ""
	task.spawn(function()
		local ok, image = pcall(function()
			return Players:GetUserThumbnailAsync(userId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size48x48)
		end)
		if ok then
			thumbnails[userId] = image
		end
	end)
end

local function createRow(parent: Instance, order: number): Row
	local frame = Instance.new("Frame")
	frame.LayoutOrder = order
	frame.Size = UDim2.new(1, 0, 0, SIZES.playerRow)
	frame.BackgroundColor3 = COLORS.panelLight
	frame.BorderSizePixel = 0
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = frame
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2
	stroke.Color = COLORS.outline
	stroke.Parent = frame

	local avatar = Instance.new("ImageLabel")
	avatar.Position = UDim2.fromOffset(5, (SIZES.playerRow - AVATAR) / 2)
	avatar.Size = UDim2.fromOffset(AVATAR, AVATAR)
	avatar.BackgroundColor3 = COLORS.panel
	avatar.BorderSizePixel = 0
	local avatarCorner = Instance.new("UICorner")
	avatarCorner.CornerRadius = UDim.new(1, 0)
	avatarCorner.Parent = avatar
	avatar.Parent = frame
	local initial = UI.text(avatar, "", SIZES.text, FONTS.display)
	initial.AutomaticSize = Enum.AutomaticSize.None
	initial.Size = UDim2.fromScale(1, 1)

	local name = UI.text(frame, "", SIZES.textSmall, FONTS.body)
	name.AutomaticSize = Enum.AutomaticSize.None
	name.Position = UDim2.fromOffset(AVATAR + 10, 3)
	name.Size = UDim2.new(1, -(AVATAR + 50), 0, 16)
	name.TextXAlignment = Enum.TextXAlignment.Left
	name.TextTruncate = Enum.TextTruncate.AtEnd

	local healthBar = UI.bar(frame, UDim2.new(1, -(AVATAR + 52), 0, 10), COLORS.health)
	healthBar.frame.Position = UDim2.new(0, AVATAR + 10, 1, -15)
	local healthLabel = UI.text(frame, "", SIZES.text, FONTS.number)
	healthLabel.AnchorPoint = Vector2.new(1, 0.5)
	healthLabel.Position = UDim2.new(1, -6, 0.5, 0)

	local tag = UI.text(frame, UITheme.icons.opponent, SIZES.text, FONTS.body, COLORS.opponent)
	tag.AnchorPoint = Vector2.new(1, 0.5)
	tag.Position = UDim2.fromScale(0, 0.5) -- just left of the row
	tag.Visible = false

	frame.Parent = parent
	return {
		frame = frame,
		stroke = stroke,
		avatar = avatar,
		initial = initial,
		name = name,
		healthBar = healthBar,
		healthLabel = healthLabel,
		tag = tag,
		shownUserId = nil,
		shownHealth = nil,
	}
end

function PlayerList.start()
	local matchState = ReplicatedStorage:WaitForChild("MatchState")
	local playersFolder = matchState:WaitForChild("Players")
	local localUserId = Players.LocalPlayer.UserId

	local _, root = UI.screen("PlayerList", 3)
	local panel = UI.panel(root, UDim2.fromOffset(SIZES.sidePanelWidth, 0), false)
	panel.AutomaticSize = Enum.AutomaticSize.Y
	panel.AnchorPoint = Vector2.new(1, 0)
	panel.Position = UDim2.new(1, -SIZES.margin, 0, SIZES.topBarHeight + 14)
	UI.padding(panel, 6)
	UI.list(panel, 4)

	local rows: { Row } = {}
	for order = 1, MatchConfig.maxPlayers do
		local row = createRow(panel, order)
		row.frame.Visible = false
		rows[order] = row
	end

	local function refresh()
		local entries = sortedEntries(playersFolder)
		panel.Visible = #entries > 0
		local own = playersFolder:FindFirstChild(tostring(localUserId))
		local opponentName = if own then own:GetAttribute("Opponent") or "" else ""

		for order, row in rows do
			local entry = entries[order]
			row.frame.Visible = entry ~= nil
			if entry then
				requestThumbnail(entry.userId)
				local image = thumbnails[entry.userId]
				row.avatar.Image = image or ""
				row.initial.Text = if image and image ~= "" then "" else string.upper(string.sub(entry.name, 1, 1))
				row.name.Text = entry.name
				local isYou = entry.userId == localUserId
				local isOpponent = opponentName ~= ""
					and (opponentName == entry.name or opponentName == "Ghost of " .. entry.name)
				row.stroke.Color = if isYou then COLORS.you elseif isOpponent then COLORS.opponent else COLORS.outline
				row.stroke.Thickness = if isYou or isOpponent then 3 else 2
				row.tag.Visible = isOpponent
				row.frame.BackgroundTransparency = if entry.eliminated then 0.6 else 0
				if entry.eliminated then
					row.healthLabel.Text = "#" .. entry.placement
					row.healthLabel.TextColor3 = COLORS.textDim
					UI.setBar(row.healthBar, 0)
					row.shownHealth = nil
				else
					local fraction = entry.health / MatchConfig.startingHealth
					row.healthLabel.Text = tostring(entry.health)
					row.healthLabel.TextColor3 = if fraction <= 0.25 then COLORS.healthLow else COLORS.text
					row.healthBar.fill.BackgroundColor3 = if fraction <= 0.25 then COLORS.healthLow else COLORS.health
					-- Rows are reused as the order changes: animate only a change for the same player.
					local samePlayer = row.shownUserId == entry.userId
					if not samePlayer or row.shownHealth ~= entry.health then
						UI.setBar(row.healthBar, fraction, samePlayer)
						if samePlayer and entry.health < (row.shownHealth or entry.health) then
							UI.pop(row.healthLabel)
						end
					end
					row.shownHealth = entry.health
				end
				row.name.TextTransparency = if entry.connected then 0 else 0.5
				row.shownUserId = entry.userId
			end
		end
	end

	task.spawn(function()
		while true do
			refresh()
			task.wait(REFRESH_SECONDS)
		end
	end)
end

return PlayerList
