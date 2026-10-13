-- Receives model dumps from Studio (scripts/studio/export-models.luau POSTs each one to
-- http://127.0.0.1:34999/<key>) and writes them to docs/references/catalog/models/dumps/<key>.json
-- (gitignored), for scripts/models-build.luau. Run from the repository root:
--   lune run scripts/models-receive [seconds]     listens for that long (default 600), then stops
-- Only listens on this computer (127.0.0.1); only accepts POST /<key> with a short word key.

local fs = require("@lune/fs")
local net = require("@lune/net")
local process = require("@lune/process")
local task = require("@lune/task")

local DIR = "docs/references/catalog/models/dumps"
local seconds = tonumber(process.args[1]) or 600
if not fs.isDir(DIR) then
	fs.writeDir(DIR)
end
local handle = net.serve(34999, {
	address = "127.0.0.1",
	handleRequest = function(request)
		local key = string.match(request.path, "^/([%w_]+)$")
		if request.method ~= "POST" or not key or #key > 40 then
			return { status = 400, body = "POST /<key>" }
		end
		fs.writeFile(DIR .. "/" .. key .. ".json", request.body)
		print(string.format("received %s (%d bytes)", key, #request.body))
		return { status = 200, body = "ok" }
	end,
})
print(string.format("listening on 127.0.0.1:34999 for %d s", seconds))
task.wait(seconds)
handle.stop()
print("stopped")
