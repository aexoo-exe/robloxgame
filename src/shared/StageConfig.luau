-- Stages and player damage. Values from docs/design/match-structure.md sections 2-3.
-- A loss costs the stage's base damage plus 1 per surviving enemy unit; a draw costs nothing.
-- Each stage starts at `firstRound`; the last stage covers every later round.
local function stage(firstRound: number, baseDamage: number)
	return table.freeze({ firstRound = firstRound, baseDamage = baseDamage })
end

return table.freeze({
	stages = table.freeze({
		stage(1, 2), -- Stage 1: rounds 1-4
		stage(5, 4), -- Stage 2: rounds 5-8
		stage(9, 6), -- Stage 3: rounds 9-12
		stage(13, 8), -- Stage 4: rounds 13-16
		stage(17, 11), -- Stage 5: rounds 17-20
		stage(21, 15), -- Stage 6: rounds 21+
	}),
	damagePerSurvivingUnit = 1,
})
