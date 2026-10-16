-- Headless test of the effect texture skins (scripts/lib/vfx-skins.luau): every skin type shown,
-- updated, hidden and recycled in every order on real ImpactEffects and CombatEffects. No Studio.
-- Run from the repository root:
--   lune run scripts/vfx-skins-test
-- Exits 1 on any problem. scripts/audit-units runs it too.

local process = require("@lune/process")

local run = require("./lib/vfx-skins")

local problems, summary = run()
for _, text in problems do
	print("PROBLEM " .. text)
end
print(string.format("vfx skins: %s, %d problems", summary, #problems))
process.exit(if #problems > 0 then 1 else 0)
