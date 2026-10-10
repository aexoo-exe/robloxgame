-- Item effects in a fight (docs/items.md). CombatSim calls ItemCombat.setup once, after trait
-- start bonuses and before the unit summaries: every board unit's items (Battle unit.items) give
-- their stats for the whole fight (permanent buffs, key "item:<id>:<stat>") and install their effect
-- through Battle hooks. Items work in every form of a unit; summons carry none. Unknown ids are
-- ignored. Numbers are in ItemConfig.
--
-- Effects (ItemConfig items[id].effect):
--   abilityCrit                  the holder's ability hits can crit (Abilities)
--   attackSpeedPercentPerAttack  each basic attack adds a stack of attack speed, up to maxStacks
--   armorShredPercent, seconds   basic attacks SHRED the target's armor
--   bonusDamagePercent           more damage to enemies with more max health than the holder
--   lifestealPercent             heals for a share of all damage dealt; belowPercent, shieldPercent,
--                                shieldSeconds: once per fight, a shield of a share of max health
--   startingMana, manaPerCast    mana at fight start and after each cast
--   manaPerAttack                mana for each basic attack
--   burnPercent, burnSeconds,    ability hits burn the target (true damage, a share of the hit,
--   healingReductionPercent      over burnSeconds) and WOUND it (less healing received) as long
--   attackDamagePercentPerStack, a stack when the holder attacks or is hit, up to maxStacks; at
--   abilityPowerPerStack,        full stacks also fullResist armor and magic resist
--   maxStacks, fullResist
--   damage, cooldown             when hit by a basic attack, magic damage to adjacent enemies
--   healPercent, interval        heals a share of max health every interval
--   resistPerAttacker            armor and magic resist per enemy targeting the holder
--   stunImmuneSeconds            immune to stuns at the start of the fight
-- Events an item causes (heals, shields, damage, damage over time ticks) carry `item` = its id.
-- Pure Luau: no Roblox APIs, so it runs in Lune tests.

local Battle = if script then require(script.Parent.Battle) else require("./Battle")
local CombatMath = if script then require(script.Parent.CombatMath) else require("./CombatMath")
local ItemConfig = if script then require(script.Parent.ItemConfig) else require("./ItemConfig")

local ItemCombat = {}

-- Tags the events emitted since `before` with the item id.
local function tagSince(battle, before: number, id: string)
	for i = before + 1, #battle.events do
		battle.events[i].item = battle.events[i].item or id
	end
end

-- A permanent stat change from an item, separate from every other buff.
local function itemStat(battle, unit, id: string, stat: string, change)
	unit.buffs["item:" .. id .. ":" .. stat] = {
		stat = stat,
		flat = change.flat or 0,
		percent = change.percent or 0,
		endsTick = math.huge,
	}
	if stat == "MaxHealth" then
		Battle.refreshMaxHealth(battle, unit)
	end
end

local function stackBuff(battle, unit, id: string, stat: string, flat: number, percent: number, maxStacks: number)
	Battle.buff(
		battle,
		unit,
		unit,
		stat,
		flat,
		percent,
		math.huge,
		true,
		maxStacks,
		{ key = "item:" .. id .. ":stack:" .. stat, source = id, silent = true }
	)
end

local function stacksOf(unit, id: string, stat: string): number
	local buff = unit.buffs["item:" .. id .. ":stack:" .. stat]
	return if buff then buff.stacks or 1 else 0
end

local EFFECTS = {}

EFFECTS.sunforged_blade = function(_battle, unit)
	unit.abilityCrit = true
end

EFFECTS.runaway_clock = function(battle, unit, id, effect)
	Battle.addHook(battle, "attack", function(_, attacker)
		if attacker == unit then
			stackBuff(battle, unit, id, "AttackSpeed", 0, effect.attackSpeedPercentPerAttack, effect.maxStacks)
		end
	end)
end

EFFECTS.golden_arrow = function(battle, unit, id, effect)
	local key = "item:" .. id .. ":" .. unit.index
	Battle.addHook(battle, "attack", function(_, attacker, target)
		if attacker ~= unit or target.dead then
			return
		end
		local existing = target.buffs[key]
		local active = existing ~= nil and battle.tick < existing.endsTick
		Battle.buff(battle, unit, target, "Armor", 0, -effect.armorShredPercent, effect.seconds, nil, nil, {
			key = key,
			status = Battle.Status.Shred,
			source = id,
			silent = active,
		})
	end)
end

EFFECTS.oni_cutter = function(battle, unit, _id, effect)
	Battle.addHook(battle, "damageMultiplier", function(_, source, target)
		if source == unit and target.maxHealth > unit.maxHealth then
			return 1 + effect.bonusDamagePercent / 100
		end
		return 1
	end)
end

EFFECTS.ghouls_mask = function(battle, unit, id, effect)
	Battle.addHook(battle, "hit", function(_, source, _target, final)
		if source == unit and final > 0 and not unit.dead then
			local before = #battle.events
			Battle.heal(battle, unit, unit, final * effect.lifestealPercent / 100)
			tagSince(battle, before, id)
		end
	end)
	local used = false
	Battle.addHook(battle, "damaged", function(_, damaged)
		if used or damaged ~= unit or unit.health * 100 >= unit.maxHealth * effect.belowPercent then
			return
		end
		used = true
		local before = #battle.events
		Battle.shield(battle, unit, unit, unit.maxHealth * effect.shieldPercent / 100, effect.shieldSeconds)
		tagSince(battle, before, id)
	end)
end

EFFECTS.strange_fruit = function(battle, unit, id, effect)
	Battle.giveMana(battle, unit, effect.startingMana, true)
	Battle.addHook(battle, "cast", function(_, caster)
		if caster == unit then
			local before = #battle.events
			Battle.giveMana(battle, unit, effect.manaPerCast)
			tagSince(battle, before, id)
		end
	end)
end

EFFECTS.cursebreaker_spear = function(battle, unit, _id, effect)
	Battle.addHook(battle, "attack", function(_, attacker)
		if attacker == unit then
			Battle.giveMana(battle, unit, effect.manaPerAttack, true)
		end
	end)
end

EFFECTS.tattered_grimoire = function(battle, unit, id, effect)
	local burnKey = "item:" .. id .. ":burn:" .. unit.index
	local woundKey = "item:" .. id .. ":wound:" .. unit.index
	Battle.addHook(battle, "hit", function(_, source, target, final, event)
		-- Ability hits only: not basic attacks, damage over time, auras, splash or executes.
		if source ~= unit or final <= 0 or target.dead or event.kind ~= "Damage" then
			return
		end
		if event.dot or event.splash or event.aura or event.execute or event.item then
			return
		end
		local perSecond = final * effect.burnPercent / 100 / effect.burnSeconds
		Battle.damageOverTime(
			battle,
			unit,
			target,
			burnKey,
			perSecond,
			CombatMath.DamageType.True,
			1,
			effect.burnSeconds,
			Battle.Status.Burn,
			id
		)
		local existing = target.buffs[woundKey]
		local active = existing ~= nil and battle.tick < existing.endsTick
		Battle.buff(
			battle,
			unit,
			target,
			"HealingReceived",
			0,
			-effect.healingReductionPercent,
			effect.burnSeconds,
			nil,
			nil,
			{
				key = woundKey,
				status = Battle.Status.Wound,
				source = id,
				silent = active,
			}
		)
	end)
end

EFFECTS.giants_serum = function(battle, unit, id, effect)
	local full = false
	local function addStack()
		if unit.dead or full then
			return
		end
		stackBuff(battle, unit, id, "AD", 0, effect.attackDamagePercentPerStack, effect.maxStacks)
		stackBuff(battle, unit, id, "AP", effect.abilityPowerPerStack, 0, effect.maxStacks)
		if stacksOf(unit, id, "AD") >= effect.maxStacks then
			full = true
			Battle.buff(battle, unit, unit, "Armor", effect.fullResist, 0, math.huge, nil, nil, {
				key = "item:" .. id .. ":full:Armor",
				source = id,
			})
			Battle.buff(battle, unit, unit, "MR", effect.fullResist, 0, math.huge, nil, nil, {
				key = "item:" .. id .. ":full:MR",
				source = id,
			})
		end
	end
	Battle.addHook(battle, "attack", function(_, attacker)
		if attacker == unit then
			addStack()
		end
	end)
	Battle.addHook(battle, "damaged", function(_, damaged)
		if damaged == unit then
			addStack()
		end
	end)
end

EFFECTS.straw_doll = function(battle, unit, id, effect)
	local readyTick = 0
	local cooldown = Battle.seconds(battle, effect.cooldown)
	Battle.addHook(battle, "hit", function(_, _source, target, _final, event)
		if target ~= unit or event.kind ~= "Attack" or unit.dead or battle.tick < readyTick then
			return
		end
		readyTick = battle.tick + cooldown
		for _, enemy in Battle.enemiesOf(battle, unit) do
			if Battle.distance(unit, enemy) == 1 then
				Battle.damage(
					battle,
					unit,
					enemy,
					effect.damage,
					CombatMath.DamageType.Magic,
					"Damage",
					nil,
					nil,
					nil,
					{ item = id }
				)
			end
		end
	end)
end

EFFECTS.cloud_cloak = function(battle, unit, id, effect)
	local interval = math.max(1, Battle.seconds(battle, effect.interval))
	local nextTick = interval
	Battle.addHook(battle, "tick", function()
		if battle.tick < nextTick then
			return
		end
		nextTick += interval
		if not unit.dead and unit.health < unit.maxHealth then
			local before = #battle.events
			Battle.heal(battle, unit, unit, unit.maxHealth * effect.healPercent / 100)
			tagSince(battle, before, id)
		end
	end)
end

EFFECTS.sand_gourd = function(battle, unit, id, effect)
	local attackers = 0
	Battle.addHook(battle, "tick", function()
		if unit.dead then
			return
		end
		local count = 0
		for _, enemy in battle.units do
			if enemy.side ~= unit.side and not enemy.dead and enemy.target == unit then
				count += 1
			end
		end
		if count == attackers then
			return
		end
		attackers = count
		for _, stat in { "Armor", "MR" } do
			Battle.buff(battle, unit, unit, stat, effect.resistPerAttacker * count, 0, math.huge, nil, nil, {
				key = "item:" .. id .. ":" .. stat .. ":attackers",
				source = id,
				silent = true,
			})
		end
	end)
end

EFFECTS.conquerors_will = function(battle, unit, _id, effect)
	unit.stunImmuneUntilTick = Battle.seconds(battle, effect.stunImmuneSeconds)
end

ItemCombat.effects = EFFECTS

-- Applies every board unit's items: stats, then effects, in each unit's slot order.
function ItemCombat.setup(battle)
	for _, unit in battle.units do
		if not unit.summoned then
			for _, id in unit.items or {} do
				local entry = ItemConfig.items[id]
				if entry then
					local stats = {}
					for stat in entry.stats or {} do
						table.insert(stats, stat)
					end
					table.sort(stats)
					for _, stat in stats do
						itemStat(battle, unit, id, stat, entry.stats[stat])
					end
					local apply = EFFECTS[id]
					if apply and entry.effect then
						apply(battle, unit, id, entry.effect)
					end
				end
			end
		end
	end
end

return ItemCombat
