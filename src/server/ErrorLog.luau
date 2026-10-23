-- Playtest error log: every server error is printed and kept in a DataStore list (PlaytestStore
-- ERRORS, the newest MAX_ENTRIES), each with where it came from (`source`), the stack, the match
-- phase and round at the time, and the server time.
--   * ErrorLog.record(source, message, stack?) records one error.
--   * ErrorLog.call(source, fn, ...) runs fn with xpcall and records an error instead of throwing;
--     returns true and fn's results, or false.
--   * Errors nobody caught (any server script thread) are recorded through ScriptContext.Error.
-- Writes are batched every FLUSH_SECONDS (and on shutdown), so a burst of errors costs one write;
-- the same error from the same source within a batch is counted, not repeated.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ScriptContext = game:GetService("ScriptContext")

local PlaytestStore = require(script.Parent.PlaytestStore)

local ErrorLog = {}

local MAX_ENTRIES = 200
local FLUSH_SECONDS = 30
local MAX_MESSAGE = 500
local MAX_STACK = 1500

type Entry = {
	time: number, -- os.time()
	source: string,
	message: string,
	stack: string,
	phase: string,
	round: number,
	count: number, -- times seen in this batch
	server: string, -- game.JobId ("" in Studio)
}

local pending: { Entry } = {}
local started = false

local function matchContext(): (string, number)
	local matchState = ReplicatedStorage:FindFirstChild("MatchState")
	if not matchState then
		return "", 0
	end
	return tostring(matchState:GetAttribute("Phase") or ""), tonumber(matchState:GetAttribute("Round")) or 0
end

function ErrorLog.record(source: string, message: any, stack: string?)
	local text = string.sub(tostring(message), 1, MAX_MESSAGE)
	local trace = string.sub(stack or "", 1, MAX_STACK)
	local phase, round = matchContext()
	warn(string.format("[ErrorLog] %s (phase %s, round %d): %s\n%s", source, phase, round, text, trace))
	for _, entry in pending do
		if entry.source == source and entry.message == text then
			entry.count += 1
			return
		end
	end
	table.insert(pending, {
		time = os.time(),
		source = source,
		message = text,
		stack = trace,
		phase = phase,
		round = round,
		count = 1,
		server = game.JobId,
	})
end

function ErrorLog.call(source: string, fn: (...any) -> ...any, ...: any): (boolean, ...any)
	local results = table.pack(xpcall(fn, function(err)
		ErrorLog.record(source, err, debug.traceback(nil, 2))
		return err
	end, ...))
	if not results[1] then
		return false
	end
	return table.unpack(results, 1, results.n)
end

local function flush()
	if #pending == 0 then
		return
	end
	local batch = pending
	pending = {}
	PlaytestStore.append(PlaytestStore.ERRORS, batch, MAX_ENTRIES)
end

function ErrorLog.start()
	assert(not started, "ErrorLog.start called more than once")
	started = true
	ScriptContext.Error:Connect(function(message, stack, origin)
		-- Client errors don't reach the server's ScriptContext; this is server scripts only.
		local name = if origin then origin:GetFullName() else "?"
		ErrorLog.record("uncaught " .. name, message, stack)
	end)
	task.spawn(function()
		while true do
			task.wait(FLUSH_SECONDS)
			flush()
		end
	end)
	game:BindToClose(flush)
end

return ErrorLog
