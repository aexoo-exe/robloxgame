-- Retention v1 on the server (docs/design/retention.md): account XP and levels, daily and weekly
-- quests, unit mastery and coins, granted into the player's profile (PlayerData). Every grant
-- happens here; clients only display (ProfileUpdated, MatchRewards) and ask to claim, reroll or
-- equip a title, which is validated (Quests, owned titles) and rate-limited. Nothing here touches a
-- match: rewards are progress, coins, titles and cosmetic ids. Bots are never tracked.
--
-- A human's match is finished (and rewarded) once: when knocked out (their placement is known),
-- when the match ends, or when they leave the game mid-match (PlayerData.beforeRelease: an early
-- leaver's small XP). RoundService reports the match (matchStarted, combat, roundResults,
-- eliminated, matchEnded); star-ups and rerolls arrive through MatchEvents.
-- Analytics (PlaytestAnalytics.event): quest_completed (quest id), level_up_account (level),
-- mastery_level (unit id, level), return_day (days since the first visit, once per UTC day).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Mastery = require(ReplicatedStorage.Shared.Mastery)
local Progression = require(ReplicatedStorage.Shared.Progression)
local Quests = require(ReplicatedStorage.Shared.Quests)
local RemoteNames = require(ReplicatedStorage.Shared.RemoteNames)
local RetentionConfig = require(ReplicatedStorage.Shared.RetentionConfig)
local Traits = require(ReplicatedStorage.Shared.Traits)

local ErrorLog = require(script.Parent.ErrorLog)
local MatchEvents = require(script.Parent.MatchEvents)
local PlayerData = require(script.Parent.PlayerData)
local PlaytestAnalytics = require(script.Parent.PlaytestAnalytics)
local Remotes = require(script.Parent.Remotes)

local RetentionService = {}

local REQUEST_GAP = 0.25 -- seconds between a player's requests
local MASTERY_SHOWN = 12 -- units in the profile view's mastery list

type Tracker = {
	practice: boolean,
	finished: boolean,
	roundsWon: number,
	rerolls: number,
	star2: number,
	star3: number,
	threeTraits: number,
	traitWins: { [string]: number },
	roundsFielded: { [string]: number },
	finalBoard: { string },
	roundTraits: { string }, -- active traits of this round's board
}

local trackers: { [number]: Tracker } = {}
local currentRound = 0
local lastRequest: { [number]: number } = {}
local profileUpdated: RemoteEvent
local matchRewards: RemoteEvent
local started = false

local function today(): number
	return Quests.dayOf(os.time())
end

-- The profile view the client shows (ProfilePanel).
local function viewOf(userId: number, profile): { [string]: any }
	local account = profile.account
	local quests = { daily = {}, weekly = {} }
	for _, kind in { "daily", "weekly" } do
		for index, quest in profile.quests[kind] do
			local spec = Quests.spec(kind, quest)
			if spec then
				table.insert(quests[kind], {
					index = index,
					text = Quests.describe(kind, quest),
					progress = quest.progress,
					target = spec.target,
					claimed = quest.claimed,
					complete = Quests.isComplete(kind, quest),
					coins = spec.coins,
					xp = spec.xp,
				})
			end
		end
	end
	local mastery = {}
	for unitType, entry in profile.mastery do
		table.insert(
			mastery,
			{ unit = unitType, level = entry.level, xp = entry.xp, toNext = Mastery.toNext(entry.xp) }
		)
	end
	table.sort(mastery, function(a, b)
		if a.xp ~= b.xp then
			return a.xp > b.xp
		end
		return a.unit < b.unit
	end)
	for index = #mastery, MASTERY_SHOWN + 1, -1 do
		mastery[index] = nil
	end
	local titles = {}
	for id in profile.titles do
		table.insert(titles, { id = id, text = RetentionConfig.titles[id] or id })
	end
	table.sort(titles, function(a, b)
		return a.text < b.text
	end)
	return {
		saving = PlayerData.isSaving(userId),
		level = account.level,
		xp = account.xp,
		xpToNext = Progression.xpToNext(account.level),
		coins = profile.coins,
		title = profile.equipped.title,
		titleText = RetentionConfig.titles[profile.equipped.title] or "",
		titles = titles,
		quests = quests,
		rerollAvailable = profile.quests.rerollDay ~= today(),
		mastery = mastery,
		days = { played = profile.days.played, streak = profile.days.streak },
		cosmetics = (function()
			local count = 0
			for _ in profile.cosmetics do
				count += 1
			end
			return count
		end)(),
	}
end

local function sendProfile(userId: number)
	local player = Players:GetPlayerByUserId(userId)
	local profile = PlayerData.get(userId)
	if player and profile then
		Quests.rotate(profile.quests, os.time(), userId)
		profileUpdated:FireClient(player, viewOf(userId, profile))
		player:SetAttribute("Title", RetentionConfig.titles[profile.equipped.title] or "")
	end
end

-- Grants a level-up or mastery reward into the profile.
local function grant(profile, reward)
	if not reward then
		return
	end
	if reward.coins then
		profile.coins += reward.coins
	end
	if reward.title then
		profile.titles[reward.title] = true
	end
	if reward.cosmetic then
		profile.cosmetics[reward.cosmetic] = true
	end
end

-- Account XP into the profile, with its level-up rewards. Returns the levels reached.
local function addAccountXp(userId: number, profile, amount: number): { any }
	local reached = Progression.addXp(profile.account, amount)
	for _, step in reached do
		grant(profile, step.reward)
		PlaytestAnalytics.event(userId, "level_up_account", step.level)
	end
	return reached
end

local function newTracker(practice: boolean): Tracker
	return {
		practice = practice,
		finished = false,
		roundsWon = 0,
		rerolls = 0,
		star2 = 0,
		star3 = 0,
		threeTraits = 0,
		traitWins = {},
		roundsFielded = {},
		finalBoard = {},
		roundTraits = {},
	}
end

-- A match starts: one tracker per human (`isBot` filters the bots out).
function RetentionService.matchStarted(participants: { number }, isBot: (number) -> boolean, practice: boolean)
	table.clear(trackers)
	currentRound = 0
	for _, userId in participants do
		if not isBot(userId) then
			trackers[userId] = newTracker(practice)
		end
	end
end

-- This round's boards (PlayerService.lockBoards): units fielded, active traits.
function RetentionService.combat(round: number, boards: { [number]: { any } })
	currentRound = round
	for userId, units in boards do
		local tracker = trackers[userId]
		if tracker and not tracker.finished then
			local board = {}
			for _, unit in units do
				tracker.roundsFielded[unit.unitType] = (tracker.roundsFielded[unit.unitType] or 0) + 1
				table.insert(board, unit.unitType)
			end
			tracker.finalBoard = board
			local active = {}
			for _, state in Traits.summary(units) do
				if state.active then
					table.insert(active, state.name)
				end
			end
			tracker.roundTraits = active
			if #active >= 3 then
				tracker.threeTraits += 1
			end
		end
	end
end

-- The round's winners (PvP and PvE fights won), by UserId.
function RetentionService.roundResults(winners: { [number]: boolean })
	for userId in winners do
		local tracker = trackers[userId]
		if tracker and not tracker.finished then
			tracker.roundsWon += 1
			for _, trait in tracker.roundTraits do
				tracker.traitWins[trait] = (tracker.traitWins[trait] or 0) + 1
			end
		end
	end
end

-- Finishes `userId`'s match once: XP, coins, quest progress, mastery; sends the summary.
local function finish(userId: number, placement: number, rounds: number, leftEarly: boolean)
	local tracker = trackers[userId]
	local profile = PlayerData.get(userId)
	if not tracker or tracker.finished or not profile then
		return
	end
	tracker.finished = true
	local now = os.time()
	local practice = tracker.practice
	local top4 = not practice and placement >= 1 and placement <= 4

	-- The day: the first match of each UTC day pays a small bonus; a missed day only restarts
	-- the streak count.
	local day = Quests.dayOf(now)
	local days = profile.days
	local coins = 0
	if days.last ~= day then
		days.streak = if days.last == day - 1 then days.streak + 1 else 1
		days.best = math.max(days.best, days.streak)
		days.played += 1
		days.last = day
		coins += RetentionConfig.matchXp.firstMatchOfDayCoins
	end
	if not leftEarly then
		profile.stats.matches += 1
	end
	if top4 then
		profile.stats.top4 += 1
	end
	if not practice and placement == 1 then
		profile.stats.wins += 1
	end

	-- Quests.
	Quests.rotate(profile.quests, now, userId)
	local changes = Quests.addStats(profile.quests, {
		matches = if leftEarly then 0 else 1,
		top4 = if top4 then 1 else 0,
		roundsWon = tracker.roundsWon,
		rerolls = tracker.rerolls,
		star2 = tracker.star2,
		star3 = tracker.star3,
		threeTraits = tracker.threeTraits,
		traitWins = tracker.traitWins,
	})
	local questTicks = {}
	for _, change in changes do
		local spec = Quests.spec(change.kind, change.quest)
		table.insert(questTicks, {
			kind = change.kind,
			text = Quests.describe(change.kind, change.quest),
			before = change.before,
			after = change.after,
			target = spec and spec.target or change.after,
			completed = change.completed,
		})
		if change.completed then
			PlaytestAnalytics.event(userId, "quest_completed", 1, change.quest.id)
		end
	end

	-- Account XP.
	local before = { level = profile.account.level, xp = profile.account.xp }
	local xp =
		Progression.matchXp({ placement = placement, rounds = rounds, practice = practice, leftEarly = leftEarly })
	local coinsBefore = profile.coins
	local levels = addAccountXp(userId, profile, xp)
	profile.coins += coins

	-- Mastery.
	local masteryGains = {}
	for unitType, amount in Mastery.matchGains(tracker.roundsFielded, tracker.finalBoard, top4) do
		local entryBefore = profile.mastery[unitType] and profile.mastery[unitType].level or 1
		local reached = Mastery.add(profile.mastery, unitType, amount)
		for _, step in reached do
			grant(profile, step.reward)
			PlaytestAnalytics.event(userId, "mastery_level", step.level, unitType)
		end
		table.insert(masteryGains, {
			unit = unitType,
			xp = amount,
			levelBefore = entryBefore,
			level = profile.mastery[unitType].level,
		})
	end
	table.sort(masteryGains, function(a, b)
		return a.xp > b.xp
	end)

	local player = Players:GetPlayerByUserId(userId)
	if player then
		local reachedLevels = {}
		for _, step in levels do
			table.insert(reachedLevels, {
				level = step.level,
				coins = step.reward and step.reward.coins or 0,
				title = step.reward and step.reward.title and RetentionConfig.titles[step.reward.title] or nil,
				cosmetic = step.reward and step.reward.cosmetic or nil,
			})
		end
		matchRewards:FireClient(player, {
			placement = placement,
			practice = practice,
			leftEarly = leftEarly,
			xp = xp,
			before = before,
			after = { level = profile.account.level, xp = profile.account.xp },
			levelsReached = reachedLevels,
			coins = profile.coins - coinsBefore,
			quests = questTicks,
			mastery = masteryGains,
		})
		sendProfile(userId)
	end
end

-- Knocked out: their placement is known now.
function RetentionService.eliminated(userId: number, round: number, placement: number)
	finish(userId, placement, round, false)
end

-- The match is over: everyone not finished yet. `stoppedEarly`: a practice match its player left
-- (their small leaver XP).
function RetentionService.matchEnded(placements: { [number]: number }, rounds: number, stoppedEarly: boolean)
	for userId in trackers do
		finish(userId, placements[userId] or 0, rounds, stoppedEarly)
	end
	table.clear(trackers)
end

-- A rate-limited, validated request from a player with a loaded profile.
local function request(remoteName: string, handler: (Player, any, ...any) -> ())
	Remotes.create(remoteName).OnServerEvent:Connect(function(player: Player, ...)
		local userId = player.UserId
		local now = os.clock()
		if now - (lastRequest[userId] or -math.huge) < REQUEST_GAP then
			return
		end
		lastRequest[userId] = now
		local profile = PlayerData.get(userId)
		if not profile then
			return
		end
		ErrorLog.call("request " .. remoteName, handler, player, profile, ...)
		sendProfile(userId)
	end)
end

function RetentionService.start()
	assert(not started, "RetentionService.start called more than once")
	started = true
	profileUpdated = Remotes.create(RemoteNames.ProfileUpdated)
	matchRewards = Remotes.create(RemoteNames.MatchRewards)

	request(RemoteNames.RequestProfile, function() end)
	request(RemoteNames.RequestClaimQuest, function(player, profile, kind, index)
		if type(kind) ~= "string" or type(index) ~= "number" then
			return
		end
		Quests.rotate(profile.quests, os.time(), player.UserId)
		local reward = Quests.claim(profile.quests, kind, index)
		if reward then
			profile.coins += reward.coins
			addAccountXp(player.UserId, profile, reward.xp)
		end
	end)
	request(RemoteNames.RequestRerollQuest, function(player, profile, index)
		if type(index) ~= "number" then
			return
		end
		Quests.rotate(profile.quests, os.time(), player.UserId)
		Quests.reroll(profile.quests, index, os.time(), player.UserId)
	end)
	request(RemoteNames.RequestEquipTitle, function(_player, profile, titleId)
		if type(titleId) == "string" and (titleId == "" or profile.titles[titleId]) then
			profile.equipped.title = titleId
		end
	end)

	MatchEvents.on("starUp", function(userId: number, starLevel: number)
		local tracker = trackers[userId]
		if tracker and not tracker.finished then
			if starLevel == 2 then
				tracker.star2 += 1
			elseif starLevel >= 3 then
				tracker.star3 += 1
			end
		end
	end)
	MatchEvents.on("reroll", function(userId: number)
		local tracker = trackers[userId]
		if tracker and not tracker.finished then
			tracker.rerolls += 1
		end
	end)

	PlayerData.onLoaded(function(player, profile)
		local userId = player.UserId
		local day = today()
		if profile.days.seen ~= day then
			if profile.days.seen ~= -1 then
				PlaytestAnalytics.event(userId, "return_day", day - profile.days.first)
			end
			profile.days.seen = day
		end
		sendProfile(userId)
	end)
	-- Leaving mid-match: an early leaver's small reward goes in before the last save.
	PlayerData.beforeRelease(function(_player, userId)
		local tracker = trackers[userId]
		if tracker and not tracker.finished then
			finish(userId, 0, currentRound, true)
		end
		lastRequest[userId] = nil
	end)
end

return RetentionService
