-- Shop. Pool sizes and odds from docs/design/revamp-structure.md (Pool / shop).
-- A unit's price is its UnitConfig cost; selling refunds that full cost.
return table.freeze({
	slots = 5,
	-- EXPERIMENTAL: 1 gold (was 2), pending human playtests; may be too generous for players.
	rerollCost = 1,

	-- Copies of each character in a match's shared pool, by cost (1-5).
	poolCopies = table.freeze({ 30, 26, 22, 15, 10 }),

	-- Percent chance of each cost tier (1, 2, 3, 4, 5) per player level. Each row sums to 100.
	odds = table.freeze({
		[2] = table.freeze({ 100, 0, 0, 0, 0 }),
		[3] = table.freeze({ 75, 25, 0, 0, 0 }),
		[4] = table.freeze({ 55, 30, 15, 0, 0 }),
		[5] = table.freeze({ 40, 30, 25, 5, 0 }),
		[6] = table.freeze({ 25, 30, 30, 14, 1 }),
		[7] = table.freeze({ 18, 25, 32, 22, 3 }),
		[8] = table.freeze({ 12, 20, 30, 31, 7 }),
		[9] = table.freeze({ 8, 15, 25, 37, 15 }),
		[10] = table.freeze({ 5, 10, 20, 40, 25 }),
	}),
})
