-- Traits (docs/design/world-and-traits.md): six origins and seven classes. Membership comes from
-- each character's `origin` and `classes` in UnitConfig; this file only holds breakpoints and
-- effects, as data for the Traits module.
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
			{ count = 2, effects = { buff("Armor", 12), buff("MR", 12) } },
			{ count = 4, effects = { buff("Armor", 28), buff("MR", 28) } },
		},
	},
	Emberwake = {
		kind = "origin",
		breakpoints = {
			{ count = 2, effects = { buff("AD", 12, true) } },
			{ count = 4, effects = { buff("AD", 25, true), buff("AttackSpeed", 15, true) } },
		},
	},
	Tideglass = {
		kind = "origin",
		breakpoints = {
			{ count = 2, effects = { buff("AP", 15), buff("MR", 8, false, "ALL_ALLIES") } },
			{ count = 4, effects = { buff("AP", 35), buff("MR", 18, false, "ALL_ALLIES") } },
		},
	},
	Stormcrest = {
		kind = "origin",
		breakpoints = {
			{ count = 2, effects = { buff("AttackSpeed", 15, true) } },
			{ count = 4, effects = { buff("AttackSpeed", 35, true), buff("MoveSpeed", 15, true) } },
		},
	},
	Starfall = {
		kind = "origin",
		breakpoints = {
			{ count = 2, effects = { buff("AP", 20) } },
			{ count = 4, effects = { buff("AP", 45) } },
		},
	},
	Eclipse = {
		kind = "origin",
		breakpoints = {
			{ count = 2, effects = { buff("AD", 10, true), buff("AP", 10) } },
			{ count = 3, effects = { buff("AD", 20, true), buff("AP", 20) } },
			{ count = 5, effects = { buff("AD", 35, true), buff("AP", 40) } },
		},
	},

	-- Classes
	Vanguard = {
		kind = "class",
		breakpoints = {
			{ count = 2, effects = { buff("Armor", 10), buff("MR", 10) } },
			{ count = 4, effects = { buff("Armor", 22), buff("MR", 22) } },
			{ count = 6, effects = { buff("Armor", 38), buff("MR", 38) } },
		},
	},
	Warden = {
		kind = "class",
		breakpoints = {
			{ count = 2, effects = { { type = "SHIELD", target = "MEMBERS", amount = 120, duration = 6 } } },
			{ count = 4, effects = { { type = "SHIELD", target = "MEMBERS", amount = 280, duration = 6 } } },
		},
	},
	Duelist = {
		kind = "class",
		breakpoints = {
			{ count = 2, effects = { buff("AttackSpeed", 12, true) } },
			{ count = 4, effects = { buff("AttackSpeed", 28, true) } },
			{ count = 6, effects = { buff("AttackSpeed", 50, true) } },
		},
	},
	Marksman = {
		kind = "class",
		breakpoints = {
			{ count = 2, effects = { buff("AD", 12, true) } },
			{ count = 4, effects = { buff("AD", 30, true) } },
		},
	},
	Arcanist = {
		kind = "class",
		breakpoints = {
			{ count = 2, effects = { buff("AP", 15) } },
			{ count = 4, effects = { buff("AP", 35) } },
			{ count = 6, effects = { buff("AP", 60) } },
		},
	},
	Mystic = {
		kind = "class",
		breakpoints = {
			{ count = 2, effects = { buff("MR", 10, false, "ALL_ALLIES"), buff("AP", 10) } },
			{ count = 4, effects = { buff("MR", 25, false, "ALL_ALLIES"), buff("AP", 25) } },
		},
	},
	Reaver = {
		kind = "class",
		breakpoints = {
			{ count = 2, effects = { buff("AD", 10, true), buff("AttackSpeed", 10, true) } },
			{ count = 4, effects = { buff("AD", 20, true), buff("AttackSpeed", 25, true) } },
			{ count = 6, effects = { buff("AD", 35, true), buff("AttackSpeed", 45, true) } },
		},
	},
})
