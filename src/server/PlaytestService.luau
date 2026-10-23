-- Playtest essentials (docs/playtest.md):
--   * How to play: each player's TutorialSeen attribute (boolean, set once loaded) says whether they
--     have closed the how-to-play intro before. It is kept per player in the PlayerFlags DataStore;
--     if that fails it is false, and the intro shows again next session (fine for a playtest).
--     RequestTutorialSeen marks it seen.
--   * Feedback: RequestSendFeedback(stars, text) after a match. One per player per match. The text
--     is filtered with TextService (dropped if filtering fails) and logged with the match summary
--     (RoundService.summaryOf, PlayerService.unitsUsed) to the server output and the PlaytestFeedback
--     DataStore list (the newest MAX_FEEDBACK). Saving runs in the background; nothing waits on it.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextService = game:GetService("TextService")
local HttpService = game:GetService("HttpService")

local RemoteNames = require(ReplicatedStorage.Shared.RemoteNames)

local ErrorLog = require(script.Parent.ErrorLog)
local PlayerService = require(script.Parent.PlayerService)
local PlaytestStore = require(script.Parent.PlaytestStore)
local Remotes = require(script.Parent.Remotes)
local RoundService = require(script.Parent.RoundService)

local PlaytestService = {}

local MAX_FEEDBACK = 500
local MAX_TEXT = 300

local feedbackSent: { [number]: number } = {} -- UserId -> match id of their last feedback
local tutorialSaved: { [number]: boolean } = {}

local function flagKey(userId: number): string
	return "u" .. tostring(userId)
end

local function loadTutorialFlag(player: Player)
	local ok, flags = PlaytestStore.get(PlaytestStore.PLAYER_FLAGS, flagKey(player.UserId))
	local seen = ok and type(flags) == "table" and flags.tutorialSeen == true
	if player.Parent then
		player:SetAttribute("TutorialSeen", seen)
	end
end

local function onTutorialSeen(player: Player)
	player:SetAttribute("TutorialSeen", true)
	if tutorialSaved[player.UserId] then
		return
	end
	tutorialSaved[player.UserId] = true
	PlaytestStore.set(PlaytestStore.PLAYER_FLAGS, flagKey(player.UserId), { tutorialSeen = true })
end

-- Filtered text for logging, or "" if filtering fails (unfiltered player text is never stored).
local function filter(text: string, userId: number): string
	local ok, result = pcall(function()
		local filtered = TextService:FilterStringAsync(text, userId, Enum.TextFilterContext.PublicChat)
		return filtered:GetNonChatStringForBroadcastAsync()
	end)
	return if ok and type(result) == "string" then result else ""
end

local function onFeedback(player: Player, stars: any, text: any)
	if type(stars) ~= "number" or stars ~= math.floor(stars) or stars < 1 or stars > 5 then
		return
	end
	if type(text) ~= "string" then
		text = ""
	end
	local userId = player.UserId
	local summary = RoundService.summaryOf(userId)
	if not summary or feedbackSent[userId] == summary.matchId then
		return
	end
	feedbackSent[userId] = summary.matchId

	local trimmed = string.sub(string.gsub(text, "^%s+", ""), 1, MAX_TEXT)
	local entry = {
		time = os.time(),
		userId = userId,
		name = player.Name,
		stars = stars,
		text = if trimmed ~= "" then filter(trimmed, userId) else "",
		placement = summary.placement,
		rounds = summary.rounds,
		durationSeconds = summary.durationSeconds,
		practice = summary.practice,
		participants = summary.participants,
		bots = summary.bots,
		matchOver = summary.over,
		units = PlayerService.unitsUsed(userId),
		server = game.JobId,
	}
	print("[Feedback] " .. HttpService:JSONEncode(entry))
	PlaytestStore.append(PlaytestStore.FEEDBACK, { entry }, MAX_FEEDBACK)
end

function PlaytestService.start()
	Remotes.create(RemoteNames.RequestTutorialSeen).OnServerEvent:Connect(function(player: Player)
		ErrorLog.call("request RequestTutorialSeen", onTutorialSeen, player)
	end)
	Remotes.create(RemoteNames.RequestSendFeedback).OnServerEvent:Connect(function(player: Player, stars, text)
		ErrorLog.call("request RequestSendFeedback", onFeedback, player, stars, text)
	end)

	Players.PlayerAdded:Connect(function(player)
		task.spawn(loadTutorialFlag, player)
	end)
	for _, player in Players:GetPlayers() do
		task.spawn(loadTutorialFlag, player)
	end
	Players.PlayerRemoving:Connect(function(player)
		feedbackSent[player.UserId] = nil
		tutorialSaved[player.UserId] = nil
	end)
end

return PlaytestService
