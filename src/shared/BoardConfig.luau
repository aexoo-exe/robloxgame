-- Board and bench layout per player. In a player's own coordinates row 1 is the back row and
-- row `rows` is the front row. In combat the two boards form a columns x (rows * 2) field.
return table.freeze({
	columns = 7,
	rows = 4,
	benchSlots = 9,
})
