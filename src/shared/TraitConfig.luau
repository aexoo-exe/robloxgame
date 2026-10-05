-- Traits: six origins and seven classes. Breakpoints and values are from
-- docs/design/balance-pass-v0.4.md section 1; membership comes from docs/design/world-and-traits.md
-- through each character's `origin` and `classes` in UnitConfig. This file only holds breakpoints
-- and effects, as data for the Traits module.
--
--   kind         "origin" or "class"
--   breakpoints  ascending; each has the member `count` that reaches it and its `effects`. Only the
--                highest breakpoint reached applies (lower ones are replaced, not added).
--
-- Effects use the ability vocabulary and apply at combat start for the whole fight:
--   BUFF    target, stat (AD, AP, AttackSpeed, Armor, MR, MoveSpeed), flat or percent
--   SHIELD  target, amount (scales with the unit's ability power), duration (seconds)
-- Targets: MEMBERS (units with the trait) or ALL_ALLIES (every unit on that player's board).
-- Every number here is a tunable [T] starting value.

local function freezeAll(value)
	if type(value) == "table" then
		for _, child in value do
			freezeAll(child)
		end
		table.freeze(value)
	end
	return value
end

local function buff(stat: string, amount: number, percent: boolean?, target: string?)
	return {
		type = "BUFF",
		target = target or "MEMBERS",
		stat = stat,
		flat = if percent then nil else amount,
		percent = if percent then amount else nil,
	}
end

return freezeAll({
	-- Origins
	Ironveil = {
		kind = "origin",
		breakpoints = {
			{ count = 2, effects = { buff("Armor", 14), buff("MR", 14) } },
			{ count = 3, effects = { buff("Armor", 32), buff("MR", 32) } },
		},
	},
	Emberwake = {
		kind = "origin",
		breakpoints = {
			{ count = 2, effects = { buff("AD", 14, true) } },
			{ count = 3, effects = { buff("AD", 28, true), buff("AttackSpeed", 18, true) } },
		},
	},
	Tideglass = {
		kind = "origin",
		breakpoints = {
			{ count = 2, effects = { buff("AP", 18), buff("MR", 9, false, "ALL_ALLIES") } },
			{ count = 3, effects = { buff("AP", 40), buff("MR", 20, false, "ALL_ALLIES") } },
		},
	},
	Stormcrest = {
		kind = "origin",
		breakpoints = {
			{ count = 2, effects = { buff("AttackSpeed", 18, true) } },
			{ count = 3, effects = { buff("AttackSpeed", 40, true), buff("MoveSpeed", 18, true) } },
		},
	},
	Starfall = {
		kind = "origin",
		breakpoints = {
			{ count = 2, effects = { buff("AP", 24) } },
			{ count = 3, effects = { buff("AP", 52) } },
		},
	},
	Eclipse = {
		kind = "origin",
		breakpoints = {
			{ count = 2, effects = { buff("AD", 12, true), buff("AP", 12) } },
			{ count = 3, effects = { buff("AD", 23, true), buff("AP", 23) } },
			{ count = 4, effects = { buff("AD", 38, true), buff("AP", 45) } },
		},
	},

	-- Classes
	Vanguard = {
		kind = "class",
		breakpoints = {
			{ count = 2, effects = { buff("Armor", 12), buff("MR", 12) } },
			{ count = 4, effects = { buff("Armor", 25), buff("MR", 25) } },
			{ count = 5, effects = { buff("Armor", 42), buff("MR", 42) } },
		},
	},
	Warden = {
		kind = "class",
		breakpoints = {
			{ count = 2, effects = { { type = "SHIELD", target = "MEMBERS", amount = 140, duration = 6 } } },
			{ count = 3, effects = { { type = "SHIELD", target = "MEMBERS", amount = 310, duration = 6 } } },
		},
	},
	Duelist = {
		kind = "class",
		breakpoints = {
			{ count = 2, effects = { buff("AttackSpeed", 14, true) } },
			{ count = 4, effects = { buff("AttackSpeed", 32, true) } },
			{ count = 5, effects = { buff("AttackSpeed", 55, true) } },
		},
	},
	Marksman = {
		kind = "class",
		breakpoints = {
			{ count = 2, effects = { buff("AD", 14, true) } },
			{ count = 3, effects = { buff("AD", 33, true) } },
		},
	},
	Arcanist = {
		kind = "class",
		breakpoints = {
			{ count = 2, effects = { buff("AP", 18) } },
			{ count = 4, effects = { buff("AP", 40) } },
			{ count = 5, effects = { buff("AP", 68) } },
		},
	},
	Mystic = {
		kind = "class",
		breakpoints = {
			{ count = 2, effects = { buff("MR", 12, false, "ALL_ALLIES"), buff("AP", 12) } },
			{ count = 3, effects = { buff("MR", 28, false, "ALL_ALLIES"), buff("AP", 30) } },
		},
	},
	Reaver = {
		kind = "class",
		breakpoints = {
			{ count = 2, effects = { buff("AD", 12, true), buff("AttackSpeed", 12, true) } },
			{ count = 4, effects = { buff("AD", 23, true), buff("AttackSpeed", 28, true) } },
			{ count = 5, effects = { buff("AD", 38, true), buff("AttackSpeed", 50, true) } },
		},
	},
})
