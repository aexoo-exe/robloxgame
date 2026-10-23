-- Reads the playtest DataStores of the live game through the Open Cloud DataStore API, and prints
-- the error and feedback logs. Shared by scripts/playtest-logs.luau and scripts/playtest-report.luau.
-- The API key is passed in (from ROBLOX_API_KEY) and never printed or written.

local net = require("@lune/net")
local serde = require("@lune/serde")

local PlaytestStore = {}

local ENTRY_URL = "https://apis.roblox.com/datastores/v1/universes/%s/standard-datastores/datastore/entries/entry"

-- Store and key names (src/server/PlaytestStore.luau and PlaytestAnalytics.luau).
PlaytestStore.LIST_KEY = "recent"
PlaytestStore.ERRORS = "PlaytestErrors"
PlaytestStore.FEEDBACK = "PlaytestFeedback"
PlaytestStore.MATCHES = "PlaytestMatches"
PlaytestStore.FUNNEL_KEY = "funnel"
PlaytestStore.UNITS_KEY = "units"

-- The value saved under `key` in `storeName`: (value) when found, ({}) when nothing is saved yet,
-- or (nil, why not).
function PlaytestStore.read(apiKey: string, universeId: string, storeName: string, key: string): (any?, string?)
	local url = string.format(ENTRY_URL, universeId)
		.. "?datastoreName="
		.. net.urlEncode(storeName)
		.. "&entryKey="
		.. net.urlEncode(key)
	local ok, response = pcall(net.request, { url = url, method = "GET", headers = { ["x-api-key"] = apiKey } })
	if not ok then
		return nil, "request failed: " .. tostring(response)
	end
	if response.statusCode == 404 then
		return {}, nil -- nothing saved yet
	end
	if response.statusCode ~= 200 then
		return nil, string.format("HTTP %d: %s", response.statusCode, response.body)
	end
	local decoded, value = pcall(serde.decode, "json", response.body)
	if not decoded or type(value) ~= "table" then
		return nil, "unexpected answer: " .. string.sub(response.body, 1, 200)
	end
	return value, nil
end

local function stamp(time: number?): string
	return if time then os.date("!%Y-%m-%d %H:%M UTC", time) :: string else "?"
end

-- The newest `count` server errors (ErrorLog entries).
function PlaytestStore.printErrors(list: { any }, count: number)
	for index = math.max(1, #list - count + 1), #list do
		local entry = list[index]
		print(
			string.format(
				"\n[%s] %s  (phase %s, round %s, x%s)\n  %s\n  %s",
				stamp(entry.time),
				tostring(entry.source),
				tostring(entry.phase),
				tostring(entry.round),
				tostring(entry.count),
				tostring(entry.message),
				(string.gsub(tostring(entry.stack), "\n", "\n  "))
			)
		)
	end
end

-- The newest `count` feedback entries (PlaytestService).
function PlaytestStore.printFeedback(list: { any }, count: number)
	for index = math.max(1, #list - count + 1), #list do
		local entry = list[index]
		print(
			string.format(
				'\n[%s] %s  %d/5  placement #%s of %s (%s bots), %s rounds, %d s%s\n  units: %s\n  "%s"',
				stamp(entry.time),
				tostring(entry.name),
				tonumber(entry.stars) or 0,
				tostring(entry.placement),
				tostring(entry.participants),
				tostring(entry.bots),
				tostring(entry.rounds),
				tonumber(entry.durationSeconds) or 0,
				if entry.practice then ", practice" else "",
				table.concat(entry.units or {}, ", "),
				tostring(entry.text or "")
			)
		)
	end
end

return PlaytestStore
