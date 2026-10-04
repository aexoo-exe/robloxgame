-- Stages and player damage. Stages from docs/design/match-structure.md section 3; base damage from
-- the REVISED TABLE in docs/design/pacing-revision.md.
-- A loss costs the stage's base damage plus 1 per surviving enemy unit; a draw costs nothing.
-- Each stage starts at `firstRound`; the last stage covers every later round.
local function stage(firstRound: number, baseDamage: number)
	return table.freeze({ firstRound = firstRound, baseDamage = baseDamage })
end

return table.freeze({
	stages = table.freeze({
		stage(1, 2), -- Stage 1: rounds 1-4
		stage(5, 5), -- Stage 2: rounds 5-8
		stage(9, 8), -- Stage 3: rounds 9-12
		stage(13, 12), -- Stage 4: rounds 13-16
		stage(17, 17), -- Stage 5: rounds 17-20
		stage(21, 24), -- Stage 6: rounds 21+
	}),
	damagePerSurvivingUnit = 1,
})
