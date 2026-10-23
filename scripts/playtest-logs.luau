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

local process = require("@lune/process")

local PlaytestStore = require("./lib/playtest-store")

local STORES = { errors = PlaytestStore.ERRORS, feedback = PlaytestStore.FEEDBACK }

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

local failed = false
for _, kind in { "errors", "feedback" } do
	if which == "both" or which == kind then
		local list, err = PlaytestStore.read(apiKey, universeId, STORES[kind], PlaytestStore.LIST_KEY)
		if not list then
			print(string.format("%s: %s", STORES[kind], err))
			failed = true
		else
			print(
				string.format("== %s: %d saved, showing the newest %d ==", STORES[kind], #list, math.min(count, #list))
			)
			if kind == "errors" then
				PlaytestStore.printErrors(list, count)
			else
				PlaytestStore.printFeedback(list, count)
			end
		end
	end
end
process.exit(if failed then 1 else 0)
