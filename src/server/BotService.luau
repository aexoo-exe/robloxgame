-- Server-side bot opponents. When a Play-pad match starts with fewer than MatchConfig.botFillTo
-- players, RoundService fills the empty seats with bots (MatchConfig.botsEnabled turns them off).
-- A bot is a match participant like any player: it has a PlayerState in PlayerService, fights,
-- takes damage and is placed and eliminated by the same Match rules. It acts once at the start of
-- every Preparation with the shared Bot logic (Shared.Bot: buy, sell, reroll, level, items), which
-- goes through the PlayerState rules, then puts its chosen units on its real board
-- (Bot.applyPlacement). Nothing a bot does is sent to any client except through the public
-- MatchState (HP, placement) and the fights it is in.
--
-- Bot ids are negative and far from Studio's test players (-1, -2, ...): BOT_ID_BASE - seat.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Bot = require(ReplicatedStorage.Shared.Bot)
local MatchConfig = require(ReplicatedStorage.Shared.MatchConfig)

local PlayerService = require(script.Parent.PlayerService)

local BotService = {}

local BOT_ID_BASE = -1000

type BotEntry = { name: string, policy: Bot.Policy, memory: Bot.Memory }

local bots: { [number]: BotEntry } = {}

-- True if `userId` is a bot of the running match.
function BotService.isBot(userId: number): boolean
	return bots[userId] ~= nil
end

-- Creates `count` bots for a new match (any previous ones are dropped). Returns their ids and
-- display names. Strategies cycle through Bot.policies, with the trait strategy in the 3rd seat.
function BotService.create(count: number): ({ number }, { [number]: string })
	table.clear(bots)
	local ids, names = {}, {}
	for seat = 1, count do
		local id = BOT_ID_BASE - seat
		local name = MatchConfig.botNames[seat] or ("Bot " .. seat)
		local policy = if seat == 3 then Bot.traitPolicy else Bot.policies[(seat - 1) % #Bot.policies + 1]
		bots[id] = { name = name, policy = policy, memory = Bot.newMemory() }
		table.insert(ids, id)
		names[id] = name
	end
	return ids, names
end

-- Every bot still in the match plays its Preparation. Called right after
-- PlayerService.beginPreparation (income paid, shop rolled, board unlocked). A bot that errors skips
-- this Preparation; the match goes on.
function BotService.playPreparation()
	for id, entry in bots do
		local state = PlayerService.activeState(id)
		if state then
			local ok, err = xpcall(function()
				local placed = Bot.prepare(state, entry.policy, entry.memory)
				Bot.applyPlacement(state, placed)
			end, debug.traceback)
			if not ok then
				warn(string.format("[BotService] %s failed its Preparation: %s", entry.name, tostring(err)))
			end
		end
	end
end

-- The match is over: forget the bots.
function BotService.clear()
	table.clear(bots)
end

return BotService
