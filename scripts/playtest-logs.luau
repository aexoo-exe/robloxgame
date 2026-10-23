-- Prints the playtest logs the live game saved (docs/playtest.md): the newest server errors
-- (ErrorLog, DataStore PlaytestErrors) and match feedback (PlaytestService, DataStore
-- PlaytestFeedback), read through the Open Cloud DataStore API. Run from the repository root:
--   $env:ROBLOX_API_KEY = "<key>"   (PowerShell; never commit or paste it anywhere else)
--   lune run scripts/playtest-logs <universeId> [errors|feedback|both] [count=20]
--
-- The universe id is the experience's id (Creator Hub > the experience > the "..." menu > Copy
-- Universe ID). The key needs the DataStore API with read access (universe-datastores.objects:read
-- and universe-datastores.objects:list) for that experience. It is read from ROBLOX_API_KEY and
-- never printed or written.

local net = require("@lune/net")
local process = require("@lune/process")
local serde = require("@lune/serde")

local ENTRY_URL = "https://apis.roblox.com/datastores/v1/universes/%s/standard-datastores/datastore/entries/entry"
local LIST_KEY = "recent" -- PlaytestStore.LIST_KEY
local STORES = { errors = "PlaytestErrors", feedback = "PlaytestFeedback" }

local apiKey = process.env.ROBLOX_API_KEY
local universeId = process.args[1] or process.env.ROBLOX_UNIVERSE_ID
local which = process.args[2] or "both"
local count = tonumber(process.args[3]) or 20
if not apiKey or apiKey == "" then
	print('ROBLOX_API_KEY is not set. In PowerShell: $env:ROBLOX_API_KEY = "<key>" then run again.')
	process.exit(1)
end
if not universeId or not string.match(universeId, "^%d+$") or not (which == "both" or STORES[which]) then
	print("Usage: lune run scripts/playtest-logs <universeId> [errors|feedback|both] [count=20]")
	process.exit(1)
end

-- The list saved under LIST_KEY in `storeName`, or nil and why not.
local function readList(storeName: string): ({ any }?, string?)
	local url = string.format(ENTRY_URL, universeId)
		.. "?datastoreName="
		.. net.urlEncode(storeName)
		.. "&entryKey="
		.. net.urlEncode(LIST_KEY)
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

local function printErrors(list: { any })
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

local function printFeedback(list: { any })
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

local failed = false
for _, kind in { "errors", "feedback" } do
	if which == "both" or which == kind then
		local list, err = readList(STORES[kind])
		if not list then
			print(string.format("%s: %s", STORES[kind], err))
			failed = true
		else
			print(
				string.format("== %s: %d saved, showing the newest %d ==", STORES[kind], #list, math.min(count, #list))
			)
			if kind == "errors" then
				printErrors(list)
			else
				printFeedback(list)
			end
		end
	end
end
process.exit(if failed then 1 else 0)
