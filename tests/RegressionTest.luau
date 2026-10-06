-- Engine changes must leave existing fights exactly as they were: every fixed-seed fight with the
-- current roster (tests/RegressionFights.luau) must match its fingerprint recorded before engine v2.

local RegressionFights = require("./RegressionFights")
local expected = require("./RegressionFingerprints")

local tests = {}

table.insert(tests, {
	name = "fixed-seed fights with the current roster match the recorded results exactly",
	run = function()
		assert(#expected == RegressionFights.count, "fingerprint count changed")
		local mismatches = {}
		for seed = 1, RegressionFights.count do
			if RegressionFights.fingerprint(seed) ~= expected[seed] then
				table.insert(mismatches, tostring(seed))
			end
		end
		assert(#mismatches == 0, "fights changed for seeds: " .. table.concat(mismatches, ", "))
	end,
})

return tests
