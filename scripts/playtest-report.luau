-- The playtest report: what the live game logged (docs/playtest.md), read through the Open Cloud
-- DataStore API. Run from the repository root:
--   $env:ROBLOX_API_KEY = "<key>"   (PowerShell; never commit or paste it anywhere else)
--   lune run scripts/playtest-report <universeId> [--csv] [--count=10] [--studio]
--
-- Prints: matches played and their average length, the new-player funnel with its drop-off, quit
-- points, unit pick rates and top-4 rates, trait usage, the most common final boards, and the
-- newest feedback and errors (as scripts/playtest-logs). --csv also writes units.csv, funnel.csv and
-- players.csv into reports/ (gitignored). --count sets how many feedback and error entries print.
-- Matches logged from Studio test sessions are left out unless --studio is given.
-- The key needs DataStore read access (universe-datastores.objects:read) for the experience.

local fs = require("@lune/fs")
local process = require("@lune/process")

local PlaytestData = require("./lib/playtest-data")
local PlaytestStore = require("./lib/playtest-store")

local apiKey = process.env.ROBLOX_API_KEY
local universeId = process.env.ROBLOX_UNIVERSE_ID
local writeCsv, count, includeStudio = false, 10, false
for _, arg in process.args do
	if arg == "--studio" then
		includeStudio = true
	elseif arg == "--csv" then
		writeCsv = true
	elseif string.match(arg, "^%-%-count=%d+$") then
		count = tonumber(string.match(arg, "%d+")) :: number
	elseif string.match(arg, "^%d+$") then
		universeId = arg
	end
end
if not apiKey or apiKey == "" then
	print('ROBLOX_API_KEY is not set. In PowerShell: $env:ROBLOX_API_KEY = "<key>" then run again.')
	process.exit(1)
end
if not universeId then
	print("Usage: lune run scripts/playtest-report <universeId> [--csv] [--count=10] [--studio]")
	process.exit(1)
end

local function read(storeName: string, key: string): any?
	local value, err = PlaytestStore.read(apiKey, universeId :: string, storeName, key)
	if value == nil then
		print(string.format("%s/%s: %s", storeName, key, tostring(err)))
	end
	return value
end

local records = {}
for _, record in read(PlaytestStore.MATCHES, PlaytestStore.LIST_KEY) or {} do
	if includeStudio or not record.studio then
		table.insert(records, record)
	end
end
local funnel = read(PlaytestStore.MATCHES, PlaytestStore.FUNNEL_KEY) or {}

-- Unit rates come from the records shown (the newest 500 matches). The all-time totals the server
-- also keeps (PlaytestMatches/"units") include Studio sessions.
local summary = PlaytestData.summarize(records, funnel)
print(PlaytestData.format(summary))

if writeCsv then
	if not fs.isDir("reports") then
		fs.writeDir("reports")
	end
	for name, text in PlaytestData.csv(summary, records) do
		fs.writeFile("reports/" .. name, text)
		print("wrote reports/" .. name)
	end
end

local feedback = read(PlaytestStore.FEEDBACK, PlaytestStore.LIST_KEY)
if feedback then
	print(string.format("\n== Feedback: %d saved, the newest %d ==", #feedback, math.min(count, #feedback)))
	PlaytestStore.printFeedback(feedback, count)
end
local errors = read(PlaytestStore.ERRORS, PlaytestStore.LIST_KEY)
if errors then
	print(string.format("\n== Errors: %d saved, the newest %d ==", #errors, math.min(count, #errors)))
	PlaytestStore.printErrors(errors, count)
end
