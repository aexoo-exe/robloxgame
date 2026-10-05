-- Shop. Values from docs/design/unit-stats-economy.md sections 6-8.
-- A unit's price is its UnitConfig cost; selling refunds that full cost.
return table.freeze({
	slots = 5,
	-- EXPERIMENTAL: 2 -> 1 in docs/design/balance-pass-v0.4.md section 5, to test whether reroll
	-- economics limit rerolling. Pending human playtests; may be too generous for players.
	rerollCost = 1,

	-- Copies of each character in a match's shared pool, by cost (1-5). docs/design/world-and-traits.md
	-- (Shared pool), from the first spec's section 14.
	poolCopies = table.freeze({ 22, 20, 17, 10, 9 }),

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
