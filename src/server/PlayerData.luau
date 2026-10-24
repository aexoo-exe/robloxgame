-- Player profiles (ProfileSchema), loaded when a player joins and saved safely:
--   * Session lock: the stored value is { data = profile, lock = { job, time } }. Loading takes the
--     lock inside UpdateAsync, so two servers never both own a profile; a lock older than
--     LOCK_STALE seconds (a crashed server) is taken over. Saves refresh it; the last save on leave
--     releases it. A save that finds another server's lock writes nothing.
--   * Retries with backoff: loading tries LOAD_TRIES times (2, 4, 8 ... s apart) while another
--     server holds the lock or DataStores fail; each save tries SAVE_TRIES times.
--   * Never overwrite with empty: every save goes through ProfileSchema.safeToReplace (no invalid,
--     empty or regressed profile over saved progress); a refused save is logged (ErrorLog).
--   * A profile that could not be loaded is a temporary, in-memory one: it is never saved, and
--     PlayerData.isSaving says so (the UI can tell the player).
--   * Autosave every AUTOSAVE seconds, and on leave and shutdown (BindToClose).
--   * Studio uses its own store (STORE .. "_Studio"), so test sessions never touch live profiles.
-- Old PlayerFlags entries (intro seen, funnel steps) are folded into a profile made for the first
-- time; PlayerFlags itself stays in use for those two (PlaytestService, PlaytestAnalytics).

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ProfileSchema = require(ReplicatedStorage.Shared.ProfileSchema)

local ErrorLog = require(script.Parent.ErrorLog)
local PlaytestStore = require(script.Parent.PlaytestStore)

local PlayerData = {}

local STORE = if RunService:IsStudio() then "PlayerProfiles_Studio" else "PlayerProfiles"
local LOCK_STALE = 180 -- seconds: an older lock is a crashed server's
local LOAD_TRIES = 5
local SAVE_TRIES = 3
local AUTOSAVE = 60

PlayerData.STORE = STORE

type Session = {
	profile: ProfileSchema.Profile,
	saving: boolean, -- loaded from the store with its lock, and saveable (not a newer version)
	released: boolean,
}

local sessions: { [number]: Session } = {}
local loadedCallbacks: { (Player, ProfileSchema.Profile) -> () } = {}
local releaseCallbacks: { (Player?, number, ProfileSchema.Profile) -> () } = {}
local started = false

local function keyOf(userId: number): string
	return "p" .. tostring(userId)
end

local function store(): DataStore
	return DataStoreService:GetDataStore(STORE)
end

local function lockedByOther(stored: any, now: number): boolean
	local lock = type(stored) == "table" and stored.lock
	return type(lock) == "table" and lock.job ~= game.JobId and now - (lock.time or 0) < LOCK_STALE
end

-- One load attempt. Returns ("ok", profile, saveable), ("locked") or ("error", message).
local function tryLoad(userId: number, legacyFlags: any): (string, any, boolean?)
	local result, saveable, locked = nil, false, false
	local ok, err = pcall(function()
		store():UpdateAsync(keyOf(userId), function(stored)
			local now = os.time()
			if lockedByOther(stored, now) then
				locked = true
				return nil
			end
			locked = false
			local data = if type(stored) == "table" then stored.data else nil
			local profile, canSave = ProfileSchema.migrate(data, now, if data == nil then legacyFlags else nil)
			result, saveable = profile, canSave
			if not canSave then
				return nil -- a newer version's profile: read it, never write it
			end
			return { data = profile, lock = { job = game.JobId, time = now } }
		end)
	end)
	if not ok then
		return "error", tostring(err)
	end
	if locked then
		return "locked"
	end
	return "ok", result, saveable
end

local save: (userId: number, release: boolean) -> boolean -- below

local function load(player: Player)
	local userId = player.UserId
	-- The old flags entry, folded into a profile made for the first time.
	local _, legacyFlags = PlaytestStore.get(PlaytestStore.PLAYER_FLAGS, "u" .. tostring(userId))
	local profile, saving = nil, false
	for attempt = 1, LOAD_TRIES do
		local status, value, saveable = tryLoad(userId, legacyFlags)
		if status == "ok" then
			profile, saving = value, saveable == true
			break
		end
		warn(
			string.format(
				"[PlayerData] %d: load attempt %d %s%s",
				userId,
				attempt,
				status,
				if value then ": " .. value else ""
			)
		)
		if attempt < LOAD_TRIES then
			task.wait(2 ^ attempt)
		end
		if not player.Parent then
			return -- left while we waited
		end
	end
	if not profile then
		profile = ProfileSchema.default(os.time())
		ErrorLog.record("player data", string.format("%d: profile not loaded; this session is not saved", userId))
	end
	sessions[userId] = { profile = profile, saving = saving, released = false }
	if not player.Parent then
		-- Left while loading (PlayerRemoving found no session): give the lock back now.
		save(userId, true)
		sessions[userId] = nil
		return
	end
	for _, callback in loadedCallbacks do
		task.spawn(ErrorLog.call, "player data loaded", callback, player, profile)
	end
end

-- Saves `userId`'s profile (and releases its lock when `release`). Returns whether it was written.
save = function(userId: number, release: boolean): boolean
	local session = sessions[userId]
	if not session or not session.saving or session.released then
		return false
	end
	local profile = session.profile
	for attempt = 1, SAVE_TRIES do
		local refused, lostLock = nil, false
		local ok, err = pcall(function()
			store():UpdateAsync(keyOf(userId), function(stored)
				local now = os.time()
				if lockedByOther(stored, now) then
					lostLock = true
					return nil
				end
				local safe, why =
					ProfileSchema.safeToReplace(if type(stored) == "table" then stored.data else nil, profile)
				if not safe then
					refused = why
					return nil
				end
				profile.lastSeen = now
				return { data = profile, lock = if release then nil else { job = game.JobId, time = now } }
			end)
		end)
		if ok then
			if lostLock then
				-- Another server owns it now: stop saving from here (it has the newer copy).
				session.saving = false
				ErrorLog.record("player data", string.format("%d: lock taken by another server; not saved", userId))
				return false
			end
			if refused then
				ErrorLog.record("player data", string.format("%d: save refused (%s)", userId, refused))
				return false
			end
			if release then
				session.released = true
			end
			return true
		end
		warn(string.format("[PlayerData] %d: save attempt %d failed: %s", userId, attempt, tostring(err)))
		if attempt < SAVE_TRIES then
			task.wait(2 ^ (attempt - 1))
		end
	end
	ErrorLog.record("player data", string.format("%d: save failed after %d tries", userId, SAVE_TRIES))
	return false
end

local function releasePlayer(userId: number, player: Player?)
	local session = sessions[userId]
	if not session then
		return
	end
	for _, callback in releaseCallbacks do
		ErrorLog.call("player data release", callback, player, userId, session.profile)
	end
	save(userId, true)
	sessions[userId] = nil
end

-- The player's profile (loaded or temporary), or nil until it has loaded.
function PlayerData.get(userId: number): ProfileSchema.Profile?
	local session = sessions[userId]
	return if session then session.profile else nil
end

-- True if the player's profile is being saved (false for a temporary one, or a newer version's).
function PlayerData.isSaving(userId: number): boolean
	local session = sessions[userId]
	return session ~= nil and session.saving
end

-- Calls `callback(player, profile)` when a player's profile is ready (loaded or temporary).
function PlayerData.onLoaded(callback: (Player, ProfileSchema.Profile) -> ())
	table.insert(loadedCallbacks, callback)
end

-- Calls `callback(player?, userId, profile)` just before a profile's last save (the player left, or
-- the server is shutting down): the last chance to grant anything into it.
function PlayerData.beforeRelease(callback: (Player?, number, ProfileSchema.Profile) -> ())
	table.insert(releaseCallbacks, callback)
end

function PlayerData.start()
	assert(not started, "PlayerData.start called more than once")
	started = true
	Players.PlayerAdded:Connect(function(player)
		ErrorLog.call("player data load", load, player)
	end)
	for _, player in Players:GetPlayers() do
		task.spawn(ErrorLog.call, "player data load", load, player)
	end
	Players.PlayerRemoving:Connect(function(player)
		releasePlayer(player.UserId, player)
	end)
	task.spawn(function()
		while true do
			task.wait(AUTOSAVE)
			for userId in sessions do
				task.spawn(ErrorLog.call, "player data autosave", save, userId, false)
			end
		end
	end)
	game:BindToClose(function()
		local pending = 0
		for userId in sessions do
			pending += 1
			task.spawn(function()
				ErrorLog.call("player data shutdown", releasePlayer, userId, Players:GetPlayerByUserId(userId))
				pending -= 1
			end)
		end
		local deadline = os.clock() + 25
		while pending > 0 and os.clock() < deadline do
			task.wait(0.1)
		end
	end)
end

return PlayerData
