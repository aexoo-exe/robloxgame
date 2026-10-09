-- Traits: breakpoints and effects, as data for the Traits module (counting, combat-start bonuses)
-- and TraitCombat (effects during the fight). Membership comes from each character's `origin`
-- (its faction) and `classes` in UnitConfig. A trait's count is the number of different characters
-- with it on the board; the highest breakpoint reached applies (lower ones are replaced, not added).
-- Every number is a placeholder (Overhaul 1, docs/design/overhaul-1.md).
--
-- Each entry:
--   Name = {
--     kind = "origin" or "class",
--     breakpoints = { { count = 2, effects = { ... }, params = { ... } }, ... }, -- ascending
--   }
-- `effects` apply at combat start for the whole fight (Traits.bonuses, Battle.applyStartBonus):
--   BUFF    target, stat (Battle.StatFields), flat or percent
--   SHIELD  target, amount (scales with the unit's ability power), duration (seconds)
--   MANA    target, amount: starting mana
-- Targets: MEMBERS (units with the trait), ALL_ALLIES (every unit on that player's board) or
-- NON_MEMBERS (every unit without it).
-- `params` are read by the trait's handler in TraitCombat (what each one means is listed there).
-- Pure Luau: no Roblox APIs, so it loads in Lune tests too.

local function buff(stat: string, amount: number, percent: boolean?, target: string?)
	return {
		type = "BUFF",
		target = target or "MEMBERS",
		stat = stat,
		flat = if percent then nil else amount,
		percent = if percent then amount else nil,
	}
end

local function mana(amount: number, target: string?)
	return { type = "MANA", target = target or "MEMBERS", amount = amount }
end

local function shield(amount: number, duration: number)
	return { type = "SHIELD", target = "MEMBERS", amount = amount, duration = duration }
end

local function step(count: number, effects, params)
	return { count = count, effects = effects or {}, params = params }
end

return table.freeze({
	-- Factions ----------------------------------------------------------------------------------

	-- The enemy with the most health is marked; Hunters deal bonus damage to it; the mark moves when
	-- it dies. Step 4: a bigger bonus, and Hunters heal (a share of their max health) when it dies.
	Hunters = {
		kind = "origin",
		breakpoints = {
			step(2, nil, { bonusPercent = 20 }),
			step(4, nil, { bonusPercent = 35, healPercent = 10 }),
		},
	},
	-- A Corps takedown gives all Corps units attack speed briefly. Step 3: the whole team.
	Corps = {
		kind = "origin",
		breakpoints = {
			step(2, nil, { attackSpeedPercent = 25, seconds = 3, wholeTeam = false }),
			step(3, nil, { attackSpeedPercent = 35, seconds = 4, wholeTeam = true }),
		},
	},
	-- Spirit units start with a shield. Step 4: bigger, and when it breaks the unit attacks faster.
	Spirit = {
		kind = "origin",
		breakpoints = {
			step(2, { shield(150, 8) }),
			step(4, { shield(300, 8) }, { breakAttackSpeedPercent = 30, breakSeconds = 4 }),
		},
	},
	-- Dummies that never attack appear on the side at fight start and can be targeted (they count
	-- toward CombatConfig.maxEntitiesPerSide). Step 4: tougher, and whoever destroys one is cursed
	-- (deals less damage) briefly. Step 6: two dummies.
	Cursed = {
		kind = "origin",
		breakpoints = {
			step(2, nil, { dummies = 1, dummyHealth = 450, dummyResist = 20 }),
			step(4, nil, { dummies = 1, dummyHealth = 800, dummyResist = 35, cursePercent = 25, curseSeconds = 4 }),
			step(6, nil, { dummies = 2, dummyHealth = 800, dummyResist = 35, cursePercent = 25, curseSeconds = 4 }),
		},
	},
	-- Arcane units start with bonus mana. Step 3: the whole team does.
	Arcane = {
		kind = "origin",
		breakpoints = {
			step(2, { mana(20) }),
			step(3, { mana(30, "ALL_ALLIES") }),
		},
	},
	-- Bonus max health. Step 3: also health regeneration (a share of max health every second).
	Titans = {
		kind = "origin",
		breakpoints = {
			step(2, { buff("MaxHealth", 15, true) }),
			step(3, { buff("MaxHealth", 25, true) }, { regenPercent = 1.5, regenInterval = 1 }),
		},
	},
	-- Once per fight, below a health threshold, a Shinobi vanishes (untargetable, not acting) for a
	-- moment and returns with a shield. Step 4: a bigger shield and a short attack speed boost.
	Shinobi = {
		kind = "origin",
		breakpoints = {
			step(2, nil, { belowPercent = 30, vanishSeconds = 1, shield = 150, shieldSeconds = 4 }),
			step(4, nil, {
				belowPercent = 30,
				vanishSeconds = 1,
				shield = 300,
				shieldSeconds = 4,
				attackSpeedPercent = 40,
				attackSpeedSeconds = 3,
			}),
		},
	},
	-- Each Crew takedown gives every Crew unit a small boost for the fight (attack damage percent and
	-- ability power, stacking). After a PvP fight the takedowns pay gold, up to a cap per round (1, step 3: 2).
	Crew = {
		kind = "origin",
		breakpoints = {
			step(2, nil, { attackDamagePercent = 5, abilityPower = 5, goldCap = 1 }),
			step(3, nil, { attackDamagePercent = 8, abilityPower = 8, goldCap = 2 }),
		},
	},
	-- A shared meter advances one point per Hero cast. While it is in its first half the team takes
	-- less damage; in its second half the team deals more. When full it starts over; at step 4 a
	-- full meter keeps both for the rest of the fight.
	Heroes = {
		kind = "origin",
		breakpoints = {
			step(2, nil, { meterMax = 4, damageTakenPercent = 10, damageDealtPercent = 10, lockWhenFull = false }),
			step(4, nil, { meterMax = 4, damageTakenPercent = 18, damageDealtPercent = 18, lockWhenFull = true }),
		},
	},

	-- Classes -----------------------------------------------------------------------------------

	Blade = {
		kind = "class",
		breakpoints = {
			step(2, { buff("AD", 10, true) }),
			step(4, { buff("AD", 20, true) }),
			step(6, { buff("AD", 32, true) }),
		},
	},
	-- Crit chance (flat, 0-1) and crit damage (flat on the multiplier). Step 4: at fight start
	-- Assassins jump to the nearest free hex in the enemy back row. Step 6: their basic attacks
	-- execute enemies left below a health threshold (never bosses).
	Assassin = {
		kind = "class",
		breakpoints = {
			step(2, { buff("CritChance", 0.10), buff("CritDamage", 0.15) }),
			step(4, { buff("CritChance", 0.15), buff("CritDamage", 0.25) }, { jump = true }),
			step(6, { buff("CritChance", 0.20), buff("CritDamage", 0.35) }, { jump = true, executeBelowPercent = 12 }),
		},
	},
	Brawler = {
		kind = "class",
		breakpoints = {
			step(2, { buff("MaxHealth", 15, true) }),
			step(4, { buff("MaxHealth", 25, true) }),
			step(6, { buff("MaxHealth", 40, true) }),
		},
	},
	Caster = {
		kind = "class",
		breakpoints = {
			step(2, { buff("AP", 12) }),
			step(4, { buff("AP", 25) }),
			step(6, { buff("AP", 40) }),
		},
	},
	-- Armor and magic resist, with a smaller share for the rest of the team.
	Guardian = {
		kind = "class",
		breakpoints = {
			step(2, {
				buff("Armor", 15),
				buff("MR", 15),
				buff("Armor", 5, false, "NON_MEMBERS"),
				buff("MR", 5, false, "NON_MEMBERS"),
			}),
			step(4, {
				buff("Armor", 30),
				buff("MR", 30),
				buff("Armor", 10, false, "NON_MEMBERS"),
				buff("MR", 10, false, "NON_MEMBERS"),
			}),
			step(6, {
				buff("Armor", 50),
				buff("MR", 50),
				buff("Armor", 15, false, "NON_MEMBERS"),
				buff("MR", 15, false, "NON_MEMBERS"),
			}),
		},
	},
	-- Attack speed that builds with each basic attack, up to a number of stacks, for the fight.
	Marksman = {
		kind = "class",
		breakpoints = {
			step(2, nil, { attackSpeedPercentPerAttack = 4, maxStacks = 10 }),
			step(4, nil, { attackSpeedPercentPerAttack = 7, maxStacks = 10 }),
		},
	},
	-- The team's heals and shields are stronger (HealPower). Step 4: the team also takes less magic
	-- damage.
	Support = {
		kind = "class",
		breakpoints = {
			step(2, { buff("HealPower", 15, true, "ALL_ALLIES") }),
			step(4, { buff("HealPower", 25, true, "ALL_ALLIES"), buff("MagicDamageTaken", -15, true, "ALL_ALLIES") }),
		},
	},
})
