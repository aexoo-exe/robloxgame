-- Trait and bond effects during a fight (Overhaul 1, docs/design/overhaul-1.md). CombatSim calls
-- TraitCombat.setup once, after combat-start bonuses (Traits.bonuses), with each side's
-- Traits.fightSetup; each active trait or bond with a handler here installs Battle hooks. Static
-- bonuses (stats, shields, starting mana) are not here: Battle.applyStartBonus applies them.
-- Numbers come from the breakpoint's `params` (TraitConfig) or the bond's (BondConfig).
--
-- Handlers (params):
--   Hunters   bonusPercent, healPercent?: the enemy board unit with the most health is marked (a
--             Mark event); Hunters deal bonusPercent more damage to it; when it dies the mark
--             moves, and with healPercent each Hunter heals that share of its max health
--   Corps     attackSpeedPercent, seconds, wholeTeam: a Corps takedown buffs Corps units' (or the
--             whole team's) attack speed
--   Spirit    breakAttackSpeedPercent, breakSeconds: when a Spirit's trait shield breaks it
--             attacks faster
--   Cursed    dummies, dummyHealth, dummyResist, cursePercent?, curseSeconds?: passive dummies
--             (summons that never act) appear in front at fight start; whoever destroys one is
--             CURSEd (deals less damage)
--   Titans    regenPercent, regenInterval: Titans heal that share of their max health every interval
--   Shinobi   belowPercent, vanishSeconds, shield, shieldSeconds, attackSpeedPercent?,
--             attackSpeedSeconds?: once per fight per unit, below the threshold it vanishes
--             (Battle.vanish) and returns with a shield (and attack speed)
--   Crew      attackDamagePercent, abilityPower, goldCap: each Crew takedown adds that much attack
--             damage percent and ability power to every Crew unit for the fight; the side's
--             takedowns, capped at goldCap, are its `gold` in TraitCombat.results
--   Heroes    meterMax, damageTakenPercent, damageDealtPercent, lockWhenFull: a Hero cast advances
--             the side's meter (a Meter event). While below half, the side takes less damage; from
--             half, it deals more. Full: starts over, or with lockWhenFull both apply for the rest
--             of the fight
--   Assassin  jump?, executeBelowPercent?: at the first tick Assassins jump (a Dash) to the nearest
--             free hex of the enemy back row; their basic attacks execute (Battle.execute) enemies
--             left below the threshold, never bosses
--   Marksman  attackSpeedPercentPerAttack, maxStacks: each basic attack adds a stack of attack
--             speed for the fight
-- Bonds (BondConfig kinds): TAKEDOWN_BOOST, TOGETHER, REMOUNT.
-- Trait buffs carry their trait (or bond id) as the Buff event's `source`.
-- Pure Luau: no Roblox APIs, so it runs in Lune tests.

local Battle = if script then require(script.Parent.Battle) else require("./Battle")
local HexGrid = if script then require(script.Parent.HexGrid) else require("./HexGrid")

local TraitCombat = {}

-- What a side's traits did, for results and reports.
export type SideResult = {
	gold: number, -- Crew takedown gold (capped)
	crewTakedowns: number,
	marks: number, -- Hunters marks placed
	meterFills: number, -- Heroes meter fills
	vanishes: number, -- Shinobi vanishes
	executes: number, -- Assassin executes
}

local function newSideResult(): SideResult
	return { gold = 0, crewTakedowns = 0, marks = 0, meterFills = 0, vanishes = 0, executes = 0 }
end

-- Living board units (not summons) of `side` whose id is in `members` (nil: every one).
local function livingMembers(battle, side: number, members: { [string]: boolean }?)
	local result = {}
	for _, unit in battle.units do
		if unit.side == side and not unit.dead and not unit.summoned and (members == nil or members[unit.id]) then
			table.insert(result, unit)
		end
	end
	return result
end

local function isMember(unit, side: number, members): boolean
	return unit.side == side and not unit.summoned and members[unit.id] == true
end

local function traitBuff(
	battle,
	source,
	target,
	stat: string,
	flat: number,
	percent: number,
	seconds: number,
	key: string,
	name: string
)
	Battle.buff(battle, source, target, stat, flat, percent, seconds, nil, nil, { key = key, source = name })
end

local HANDLERS = {}

HANDLERS.Hunters = function(battle, side: number, trait, result: SideResult)
	local params = trait.params
	local state = { mark = nil }
	local function placeMark()
		local enemies = {}
		for _, unit in battle.units do
			if unit.side ~= side and not unit.dead and not unit.summoned then
				table.insert(enemies, unit)
			end
		end
		state.mark = Battle.pickBest(battle, enemies, function(enemy)
			return enemy.health
		end)
		if state.mark then
			result.marks += 1
			Battle.emit(battle, { kind = "Mark", unit = state.mark.index, side = side, source = "Hunters" })
		end
	end
	placeMark()
	Battle.addHook(battle, "damageMultiplier", function(_, source, target)
		if target == state.mark and isMember(source, side, trait.members) then
			return 1 + params.bonusPercent / 100
		end
		return 1
	end)
	Battle.addHook(battle, "death", function(_, victim)
		if victim ~= state.mark then
			return
		end
		if params.healPercent then
			for _, hunter in livingMembers(battle, side, trait.members) do
				Battle.heal(battle, hunter, hunter, hunter.maxHealth * params.healPercent / 100)
			end
		end
		placeMark()
	end)
end

HANDLERS.Corps = function(battle, side: number, trait)
	local params = trait.params
	Battle.addHook(battle, "takedown", function(_, killer)
		if not isMember(killer, side, trait.members) then
			return
		end
		local receivers = livingMembers(battle, side, if params.wholeTeam then nil else trait.members)
		for _, unit in receivers do
			traitBuff(
				battle,
				killer,
				unit,
				"AttackSpeed",
				0,
				params.attackSpeedPercent,
				params.seconds,
				"trait:Corps",
				"Corps"
			)
		end
	end)
end

HANDLERS.Spirit = function(battle, side: number, trait)
	local params = trait.params
	if not (params and params.breakAttackSpeedPercent) then
		return
	end
	Battle.addHook(battle, "shieldBroken", function(_, unit)
		if isMember(unit, side, trait.members) and unit.shieldSource == "Spirit" then
			unit.shieldSource = nil
			traitBuff(
				battle,
				unit,
				unit,
				"AttackSpeed",
				0,
				params.breakAttackSpeedPercent,
				params.breakSeconds,
				"trait:Spirit",
				"Spirit"
			)
		end
	end)
end

HANDLERS.Cursed = function(battle, side: number, trait)
	local params = trait.params
	local summoner = livingMembers(battle, side, trait.members)[1]
	if not summoner then
		return
	end
	-- In front of the side: the middle of its front row.
	local frontRow = if side == 1 then battle.fieldRows / 2 else battle.fieldRows / 2 + 1
	local near = { math.ceil(battle.columns / 2), frontRow }
	local dummies = {}
	for _ = 1, params.dummies do
		local dummy = Battle.summon(battle, summoner, {
			health = params.dummyHealth,
			attackDamage = 0,
			armor = params.dummyResist,
			magicResist = params.dummyResist,
			attacksPerSecond = 1,
			range = 1,
			moveSpeed = 0,
			passive = true,
			near = near,
			source = "Cursed",
		})
		if dummy then
			dummies[dummy] = true
		end
	end
	if params.cursePercent then
		Battle.addHook(battle, "death", function(_, victim, killer)
			if dummies[victim] and killer and killer.side ~= side then
				Battle.debuff(
					battle,
					victim,
					killer,
					Battle.Status.Curse,
					params.cursePercent,
					params.curseSeconds,
					"Cursed"
				)
			end
		end)
	end
end

HANDLERS.Titans = function(battle, side: number, trait)
	local params = trait.params
	if not (params and params.regenPercent) then
		return
	end
	local interval = math.max(1, Battle.seconds(battle, params.regenInterval))
	local nextTick = interval
	Battle.addHook(battle, "tick", function()
		if battle.tick < nextTick then
			return
		end
		nextTick += interval
		for _, unit in livingMembers(battle, side, trait.members) do
			if unit.health < unit.maxHealth then
				Battle.heal(battle, unit, unit, unit.maxHealth * params.regenPercent / 100)
			end
		end
	end)
end

HANDLERS.Shinobi = function(battle, side: number, trait, result: SideResult)
	local params = trait.params
	local used = {}
	Battle.addHook(battle, "damaged", function(_, unit)
		if used[unit] or not isMember(unit, side, trait.members) then
			return
		end
		if unit.health * 100 >= unit.maxHealth * params.belowPercent then
			return
		end
		used[unit] = true
		result.vanishes += 1
		Battle.vanish(battle, unit, params.vanishSeconds)
		Battle.schedule(battle, Battle.seconds(battle, params.vanishSeconds), unit, function()
			local before = #battle.events
			Battle.shield(battle, unit, unit, params.shield, params.shieldSeconds)
			if #battle.events > before then
				battle.events[#battle.events].source = "Shinobi"
			end
			if params.attackSpeedPercent then
				traitBuff(
					battle,
					unit,
					unit,
					"AttackSpeed",
					0,
					params.attackSpeedPercent,
					params.attackSpeedSeconds,
					"trait:Shinobi",
					"Shinobi"
				)
			end
		end)
	end)
end

HANDLERS.Crew = function(battle, side: number, trait, result: SideResult)
	local params = trait.params
	Battle.addHook(battle, "takedown", function(_, killer)
		if not isMember(killer, side, trait.members) then
			return
		end
		result.crewTakedowns += 1
		result.gold = math.min(params.goldCap, result.crewTakedowns)
		local takedowns = result.crewTakedowns
		for _, unit in livingMembers(battle, side, trait.members) do
			traitBuff(
				battle,
				killer,
				unit,
				"AD",
				0,
				params.attackDamagePercent * takedowns,
				math.huge,
				"trait:Crew:AD",
				"Crew"
			)
			traitBuff(
				battle,
				killer,
				unit,
				"AP",
				params.abilityPower * takedowns,
				0,
				math.huge,
				"trait:Crew:AP",
				"Crew"
			)
		end
	end)
end

HANDLERS.Heroes = function(battle, side: number, trait, result: SideResult)
	local params = trait.params
	local state = { meter = 0, locked = false }
	local half = params.meterMax / 2
	local function guarding(): boolean
		return state.locked or state.meter < half
	end
	local function furious(): boolean
		return state.locked or state.meter >= half
	end
	Battle.addHook(battle, "cast", function(_, caster)
		if state.locked or not isMember(caster, side, trait.members) then
			return
		end
		state.meter += 1
		if state.meter >= params.meterMax then
			result.meterFills += 1
			if params.lockWhenFull then
				state.locked = true
				state.meter = params.meterMax
			else
				state.meter = 0
			end
		end
		Battle.emit(battle, {
			kind = "Meter",
			unit = caster.index,
			side = side,
			source = "Heroes",
			value = state.meter,
			max = params.meterMax,
			phase = if state.locked then "BOTH" elseif guarding() then "GUARD" else "FURY",
		})
	end)
	Battle.addHook(battle, "damageMultiplier", function(_, source, target)
		local multiplier = 1
		if target.side == side and guarding() then
			multiplier *= 1 - params.damageTakenPercent / 100
		end
		if source.side == side and furious() then
			multiplier *= 1 + params.damageDealtPercent / 100
		end
		return multiplier
	end)
end

HANDLERS.Assassin = function(battle, side: number, trait, result: SideResult)
	local params = trait.params
	if not params then
		return
	end
	if params.jump then
		local done = false
		Battle.addHook(battle, "tick", function()
			if done then
				return
			end
			done = true
			local backRow = if side == 1 then battle.fieldRows else 1
			for _, unit in livingMembers(battle, side, trait.members) do
				local bestColumn, bestDistance = nil, math.huge
				for column = 1, battle.columns do
					if Battle.isFree(battle, column, backRow) then
						local distance = HexGrid.distance(unit.column, unit.row, column, backRow)
						if distance < bestDistance then
							bestColumn, bestDistance = column, distance
						end
					end
				end
				if bestColumn then
					Battle.relocate(battle, unit, bestColumn, backRow)
					Battle.emit(
						battle,
						{ kind = "Dash", unit = unit.index, column = bestColumn, row = backRow, source = "Assassin" }
					)
				end
			end
		end)
	end
	if params.executeBelowPercent then
		Battle.addHook(battle, "attack", function(_, attacker, target)
			if target.dead or not isMember(attacker, side, trait.members) or target.stats.kind == "boss" then
				return
			end
			if target.health * 100 < target.maxHealth * params.executeBelowPercent then
				result.executes += 1
				Battle.execute(battle, attacker, target)
			end
		end)
	end
end

HANDLERS.Marksman = function(battle, side: number, trait)
	local params = trait.params
	Battle.addHook(battle, "attack", function(_, attacker)
		if isMember(attacker, side, trait.members) then
			Battle.buff(
				battle,
				attacker,
				attacker,
				"AttackSpeed",
				0,
				params.attackSpeedPercentPerAttack,
				math.huge,
				true,
				params.maxStacks,
				{ key = "trait:Marksman", source = "Marksman", silent = true }
			)
		end
	end)
end

local BONDS = {}

BONDS.TAKEDOWN_BOOST = function(battle, side: number, active)
	local bond, params = active.bond, active.bond.params
	Battle.addHook(battle, "takedown", function(_, killer)
		if not isMember(killer, side, active.members) then
			return
		end
		for _, unit in livingMembers(battle, side, active.members) do
			if unit.unitType ~= killer.unitType then
				traitBuff(
					battle,
					killer,
					unit,
					"DamageDealt",
					0,
					params.damagePercent,
					params.seconds,
					"bond:" .. bond.id,
					bond.id
				)
			end
		end
	end)
end

BONDS.TOGETHER = function(battle, side: number, active)
	local bond, params = active.bond, active.bond.params
	local key = "bond:" .. bond.id
	for _, unit in livingMembers(battle, side, active.members) do
		traitBuff(battle, unit, unit, "DamageDealt", 0, params.damagePercent, math.huge, key, bond.id)
	end
	local broken = false
	Battle.addHook(battle, "death", function(_, victim)
		if broken or not isMember(victim, side, active.members) then
			return
		end
		-- The bond breaks once no copy of the fallen character is left.
		local survivors, fallenLeft = {}, false
		for _, unit in livingMembers(battle, side, active.members) do
			if unit.unitType == victim.unitType then
				fallenLeft = true
			else
				table.insert(survivors, unit)
			end
		end
		if fallenLeft then
			return
		end
		broken = true
		for _, unit in survivors do
			Battle.removeBuff(battle, unit, key)
			Battle.giveMana(battle, unit, params.survivorMana)
			traitBuff(
				battle,
				unit,
				unit,
				"DamageDealt",
				0,
				params.survivorPercent,
				params.survivorSeconds,
				key .. ":survivor",
				bond.id
			)
		end
	end)
end

BONDS.REMOUNT = function(battle, side: number, active)
	for _, unit in livingMembers(battle, side, active.members) do
		unit.flags[active.bond.params.flag] = true
	end
end

-- Installs the hooks of both sides' traits and bonds. `setups` is { side 1, side 2 } of
-- Traits.fightSetup (either may be nil). Results go to battle.sideState[side].traits.
function TraitCombat.setup(battle, setups)
	for side = 1, 2 do
		local setup = setups and setups[side]
		local result = newSideResult()
		battle.sideState[side].traits = result
		if setup then
			local names = {}
			for name in setup.traits do
				table.insert(names, name)
			end
			table.sort(names) -- a fixed order, so hooks run the same way every time
			for _, name in names do
				local handler = HANDLERS[name]
				local trait = setup.traits[name]
				if handler and trait.params then
					handler(battle, side, trait, result)
				end
			end
			for _, active in setup.bonds do
				local handler = BONDS[active.bond.kind]
				if handler then
					handler(battle, side, active)
				end
			end
		end
	end
end

-- What each side's traits did this fight: { side 1, side 2 } of SideResult.
function TraitCombat.results(battle): { SideResult }
	return {
		battle.sideState[1].traits or newSideResult(),
		battle.sideState[2].traits or newSideResult(),
	}
end

TraitCombat.handlers = HANDLERS
TraitCombat.bondHandlers = BONDS

return TraitCombat
