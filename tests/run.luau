-- Minimal Lune test runner. Run from the repository root:
--   lune run tests/run.luau
-- Each test file returns a list of { name = string, run = () -> () }. A test fails if it errors.

local process = require("@lune/process")

local suites = {
	{ name = "HexGrid", tests = require("./HexGridTest") },
	{ name = "Board", tests = require("./BoardTest") },
	{ name = "CombatSim", tests = require("./CombatSimTest") },
	{ name = "Roster", tests = require("./RosterTest") },
	{ name = "Economy", tests = require("./EconomyTest") },
	{ name = "Shop", tests = require("./ShopTest") },
	{ name = "PlayerState", tests = require("./PlayerStateTest") },
	{ name = "Star", tests = require("./StarTest") },
	{ name = "MatchRules", tests = require("./MatchRulesTest") },
	{ name = "Pairing", tests = require("./PairingTest") },
	{ name = "Match", tests = require("./MatchTest") },
	{ name = "CombatMath", tests = require("./CombatMathTest") },
	{ name = "Ability", tests = require("./AbilityTest") },
	{ name = "CastReader", tests = require("./CastReaderTest") },
	{ name = "UnitPool", tests = require("./UnitPoolTest") },
}

local passed = 0
local failed = 0

for _, suite in suites do
	for _, test in suite.tests do
		local ok, err = pcall(test.run)
		if ok then
			passed += 1
			print(string.format("  PASS  %s: %s", suite.name, test.name))
		else
			failed += 1
			print(string.format("  FAIL  %s: %s\n        %s", suite.name, test.name, tostring(err)))
		end
	end
end

print(string.format("\n%d passed, %d failed", passed, failed))
process.exit(if failed > 0 then 1 else 0)
