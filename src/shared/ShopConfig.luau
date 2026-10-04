-- Shop. Values from docs/design/unit-stats-economy.md sections 6-8.
-- A unit's price is its UnitConfig cost; selling refunds that full cost.
return table.freeze({
	slots = 5,
	rerollCost = 2,

	-- Percent chance of each cost tier (1, 2, 3, 4, 5) per player level. Each row sums to 100.
	odds = table.freeze({
		[2] = table.freeze({ 100, 0, 0, 0, 0 }),
		[3] = table.freeze({ 75, 25, 0, 0, 0 }),
		[4] = table.freeze({ 55, 30, 15, 0, 0 }),
		[5] = table.freeze({ 45, 33, 20, 2, 0 }),
		[6] = table.freeze({ 30, 40, 25, 5, 0 }),
		[7] = table.freeze({ 19, 30, 40, 10, 1 }),
		[8] = table.freeze({ 15, 20, 32, 30, 3 }),
		[9] = table.freeze({ 10, 17, 25, 33, 15 }),
		[10] = table.freeze({ 5, 10, 20, 40, 25 }),
	}),
})
