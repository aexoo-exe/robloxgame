-- DataStore storage for the playtest tools (ErrorLog, PlaytestService). A log is one DataStore key
-- (PlaytestStore.LIST_KEY) holding a list of the newest entries, oldest first, capped. Every call is
-- wrapped in pcall: in Studio without API access, in an unpublished place, or when DataStores
-- throttle, nothing is saved and the callers still print their entries. Every call yields, so call
-- from task.spawn on anything time-critical.
-- Reading the logs: docs/playtest.md (Studio command bar or scripts/playtest-logs.luau).

local DataStoreService = game:GetService("DataStoreService")

local PlaytestStore = {}

PlaytestStore.LIST_KEY = "recent"
PlaytestStore.ERRORS = "PlaytestErrors"
PlaytestStore.FEEDBACK = "PlaytestFeedback"
PlaytestStore.PLAYER_FLAGS = "PlayerFlags"
PlaytestStore.MATCHES = "PlaytestMatches" -- keys: LIST_KEY (match records), "units", "funnel"

-- Appends `entries` to the list in `storeName`, keeping the newest `cap`. Returns true if saved.
function PlaytestStore.append(storeName: string, entries: { any }, cap: number): boolean
	local ok, err = pcall(function()
		DataStoreService:GetDataStore(storeName):UpdateAsync(PlaytestStore.LIST_KEY, function(old)
			local list = if type(old) == "table" then old else {}
			for _, entry in entries do
				table.insert(list, entry)
			end
			while #list > cap do
				table.remove(list, 1)
			end
			return list
		end)
	end)
	if not ok then
		warn(string.format("[PlaytestStore] %s not saved: %s", storeName, tostring(err)))
	end
	return ok
end

-- Updates a key with `transform(old) -> new` (UpdateAsync: safe against other servers writing it).
-- `transform` may return nil to leave the key as it is. Returns (true, the value saved) or (false).
function PlaytestStore.update(storeName: string, key: string, transform: (any) -> any): (boolean, any)
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(storeName):UpdateAsync(key, transform)
	end)
	if not ok then
		warn(string.format("[PlaytestStore] %s/%s not updated: %s", storeName, key, tostring(result)))
		return false, nil
	end
	return true, result
end

-- Reads a key. Returns (true, value) or (false, nil) if the DataStore is unavailable.
function PlaytestStore.get(storeName: string, key: string): (boolean, any)
	local ok, value = pcall(function()
		return DataStoreService:GetDataStore(storeName):GetAsync(key)
	end)
	if not ok then
		warn(string.format("[PlaytestStore] %s/%s not read: %s", storeName, key, tostring(value)))
		return false, nil
	end
	return true, value
end

-- Writes a key. Returns true if saved.
function PlaytestStore.set(storeName: string, key: string, value: any): boolean
	local ok, err = pcall(function()
		DataStoreService:GetDataStore(storeName):SetAsync(key, value)
	end)
	if not ok then
		warn(string.format("[PlaytestStore] %s/%s not saved: %s", storeName, key, tostring(err)))
	end
	return ok
end

return PlaytestStore
