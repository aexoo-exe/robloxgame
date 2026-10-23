-- Server-side bot opponents. When a Play-pad match starts with fewer than MatchConfig.botFillTo
-- players, RoundService fills the empty seats with bots (MatchConfig.botsEnabled turns them off).
-- A bot is a match participant like any player: it has a PlayerState in PlayerService, fights,
-- takes damage and is placed and eliminated by the same Match rules. Bots play at
-- MatchConfig.botDifficulty ("easy": Bot.easyPolicies; "normal": Bot.policies and the trait
-- strategy) with the shared Bot logic (Shared.Bot: buy, sell, reroll, level, items), which goes
-- through the PlayerState rules, then put their chosen units on their real board
-- (Bot.applyPlacement).
--
-- Preparation is played over time, like a person: each bot waits a moment (THINK_FROM..THINK_TO of
-- the Preparation), shops, then places its units one at a time a short gap apart.
-- BotService.finishPreparation (called by RoundService before the boards lock) finishes anything
-- left at once, so every bot's board is complete when Combat starts.
-- Nothing a bot does is sent to any client except through the public MatchState (HP, placement)
-- and the fights it is in.
--
-- Bot ids are negative and far from Studio's test players (-1, -2, ...): BOT_ID_BASE - seat.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Bot = require(ReplicatedStorage.Shared.Bot)
local MatchConfig = require(ReplicatedStorage.Shared.MatchConfig)

local ErrorLog = require(script.Parent.ErrorLog)
local PlayerService = require(script.Parent.PlayerService)

local BotService = {}

local BOT_ID_BASE = -1000
-- When in the Preparation a bot starts shopping (fractions of it), and the gap between placements.
local THINK_FROM, THINK_TO = 0.12, 0.35
local PLACE_GAP = { 0.6, 1.4 } -- seconds

type BotEntry = { name: string, policy: Bot.Policy, memory: Bot.Memory }
-- One bot's Preparation in progress.
type Job = { thread: thread?, prepared: boolean, placed: { any }?, applied: number }

local bots: { [number]: BotEntry } = {}
local jobs: { [number]: Job } = {}
local random = Random.new()

-- True if `userId` is a bot of the running match.
function BotService.isBot(userId: number): boolean
	return bots[userId] ~= nil
end

local function policyFor(seat: number): Bot.Policy
	if MatchConfig.botDifficulty == "normal" then
		return if seat == 3 then Bot.traitPolicy else Bot.policies[(seat - 1) % #Bot.policies + 1]
	end
	return Bot.easyPolicies[(seat - 1) % #Bot.easyPolicies + 1]
end

local function cancelJobs()
	for _, job in jobs do
		if job.thread and coroutine.status(job.thread) ~= "dead" then
			task.cancel(job.thread)
		end
	end
	table.clear(jobs)
end

-- Creates `count` bots for a new match (any previous ones are dropped). Returns their ids and
-- display names. Strategies come from MatchConfig.botDifficulty (policyFor).
function BotService.create(count: number): ({ number }, { [number]: string })
	BotService.clear()
	local ids, names = {}, {}
	for seat = 1, count do
		local id = BOT_ID_BASE - seat
		local name = MatchConfig.botNames[seat] or ("Bot " .. seat)
		bots[id] = { name = name, policy = policyFor(seat), memory = Bot.newMemory(random:NextInteger(1, 2 ^ 30)) }
		table.insert(ids, id)
		names[id] = name
	end
	return ids, names
end

-- Shops (Bot.prepare) if it hasn't yet this Preparation.
local function prepare(id: number, job: Job)
	if job.prepared then
		return
	end
	job.prepared = true
	local entry, state = bots[id], PlayerService.activeState(id)
	if entry and state then
		ErrorLog.call("bot " .. entry.name, function()
			job.placed = Bot.prepare(state, entry.policy, entry.memory)
		end)
	end
end

-- Puts the first `count` of its chosen units on the board (Bot.applyPlacement).
local function place(id: number, job: Job, count: number)
	local entry, state, placed = bots[id], PlayerService.activeState(id), job.placed
	if not entry or not state or not placed then
		return
	end
	count = math.min(count, #placed)
	ErrorLog.call("bot " .. entry.name, function()
		Bot.applyPlacement(state, table.move(placed, 1, count, 1, {}))
	end)
	job.applied = count
end

-- Every bot still in the match starts its Preparation, which lasts `duration` seconds. Called right
-- after PlayerService.beginPreparation (income paid, shop rolled, board unlocked). A bot that errors
-- skips the rest of this Preparation (the error goes to ErrorLog); the match goes on.
function BotService.playPreparation(duration: number)
	cancelJobs()
	for id in bots do
		if PlayerService.activeState(id) then
			local job: Job = { thread = nil, prepared = false, placed = nil, applied = 0 }
			jobs[id] = job
			job.thread = task.delay(duration * (THINK_FROM + random:NextNumber() * (THINK_TO - THINK_FROM)), function()
				prepare(id, job)
				for count = 1, if job.placed then #job.placed else 0 do
					place(id, job, count)
					task.wait(random:NextNumber(PLACE_GAP[1], PLACE_GAP[2]))
				end
			end)
		end
	end
end

-- The Preparation is over: every bot finishes at once (shops if it hasn't, places every unit).
-- Called by RoundService before the boards lock.
function BotService.finishPreparation()
	local pending = jobs
	jobs = {}
	for id, job in pending do
		if job.thread and coroutine.status(job.thread) ~= "dead" then
			task.cancel(job.thread)
		end
		prepare(id, job)
		if job.placed and job.applied < #job.placed then
			place(id, job, #job.placed)
		end
	end
end

-- The match is over: forget the bots.
function BotService.clear()
	cancelJobs()
	table.clear(bots)
end

return BotService
