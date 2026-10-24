-- A small in-server event bus for match moments that more than one system cares about, so they can
-- listen without requiring each other (PlaytestAnalytics fires, RetentionService listens).
-- Events: "starUp" (userId, starLevel), "reroll" (userId). A listener's error is recorded and
-- never stops the others.

local ErrorLog = require(script.Parent.ErrorLog)

local MatchEvents = {}

local listeners: { [string]: { (...any) -> () } } = {}

function MatchEvents.on(name: string, callback: (...any) -> ())
	listeners[name] = listeners[name] or {}
	table.insert(listeners[name], callback)
end

function MatchEvents.fire(name: string, ...: any)
	for _, callback in listeners[name] or {} do
		ErrorLog.call("match event " .. name, callback, ...)
	end
end

return MatchEvents
