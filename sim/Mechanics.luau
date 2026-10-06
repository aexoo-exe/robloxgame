-- Fight statistics for the engine v2 mechanics (docs/design/revamp-roster.md, measurement list):
-- damage by source, healing and shielding, pulls, summons, COPY, stun uptime, single big hits
-- (overkill) and stacking buffs. Feed every fight result to Mechanics.record, then print
-- Mechanics.report(). Characters are named by internal id.

local UnitConfig = require("../src/shared/UnitConfig")

local Mechanics = {}

local COPY_TARGET_SAMPLE = 8 -- most-copied characters listed

local totals = {
	fights = 0,
	damage = { attack = 0, ability = 0, dot = 0, summon = 0 },
	byType = {}, -- unitType -> { present, attack, ability, dot, summon, heal, shield }
	pull = { casts = 0, moved = 0, survivalSum = 0, survivalCount = 0, diedWithin3 = 0 },
	summons = {}, -- summoner unitType -> { present, casts, made, damage, aliveSeconds }
	copy = { targets = {}, byCost = {} }, -- byCost[cost] = { copies, damage, support, summons }
	stun = { stunnedSeconds = { 0, 0 } }, -- per side, unit-seconds spent stunned
	burst = {}, -- unitType with a single TRUE hit ability -> { present, casts, overkillSum, overkills, kills }
	stacks = {}, -- unitType with a stacking buff -> { present, reached = { fights per highest count 0-3 } }
}

local function typeStats(unitType: string)
	local stats = totals.byType[unitType]
	if not stats then
		stats = { present = 0, attack = 0, ability = 0, dot = 0, summon = 0, heal = 0, shield = 0 }
		totals.byType[unitType] = stats
	end
	return stats
end

-- Abilities with one DAMAGE effect of TRUE damage and nothing else ("single big hit").
local function isSingleTrueHit(unitType: string): boolean
	local effects = UnitConfig[unitType].ability.effects
	return #effects == 1 and effects[1].type == "DAMAGE" and effects[1].damageType == "TRUE"
end

local function hasStackingBuff(unitType: string): boolean
	for _, effect in UnitConfig[unitType].ability.effects do
		if effect.type == "BUFF" and effect.stackPerCast then
			return true
		end
	end
	return false
end

local function hasEffect(unitType: string, effectType: string): boolean
	for _, effect in UnitConfig[unitType].ability.effects do
		if effect.type == effectType then
			return true
		end
	end
	return false
end

function Mechanics.record(result)
	totals.fights += 1
	local tps = result.ticksPerSecond
	local units = {} -- index -> { unitType, side, summoned, summoner }
	local health, shield = {}, {}
	local deathTick = {}
	local present = {}
	for _, unit in result.units do
		units[unit.index] = { unitType = unit.unitType, side = unit.side }
		health[unit.index] = unit.maxHealth
		shield[unit.index] = 0
		present[unit.unitType] = true
	end
	for unitType in present do
		typeStats(unitType).present += 1
		if hasEffect(unitType, "SUMMON") then
			local entry = totals.summons[unitType] or { present = 0, casts = 0, made = 0, damage = 0, aliveSeconds = 0 }
			entry.present += 1
			totals.summons[unitType] = entry
		end
		if isSingleTrueHit(unitType) then
			local entry = totals.burst[unitType]
				or { present = 0, casts = 0, overkillSum = 0, overkills = 0, kills = 0 }
			entry.present += 1
			totals.burst[unitType] = entry
		end
	end

	local summonStart = {}
	local pulled = {} -- unit index -> tick it was pulled
	local stunIntervals = {} -- unit index -> { start, finish, total }
	local copy = nil -- the COPY being resolved: { unit, tick, cost }
	local stackMax = {} -- unit index (stacking-buff unit) -> highest stack count seen

	-- The real unit a damage event is credited to (a summon's summoner).
	local function creditedType(index: number): string?
		local info = units[index]
		if not info then
			return nil
		end
		return if info.summoned then units[info.summoner].unitType else info.unitType
	end

	for _, event in result.events do
		local kind = event.kind
		if
			copy
			and not (event.tick == copy.tick and (event.unit == copy.unit or kind == "Death" or kind == "MaxHealth"))
		then
			copy = nil
		end

		if kind == "Summon" then
			local summoner = units[event.unit]
			units[event.summon] =
				{ unitType = summoner.unitType, side = summoner.side, summoned = true, summoner = event.unit }
			health[event.summon] = event.maxHealth
			shield[event.summon] = 0
			summonStart[event.summon] = event.tick
			local credited = creditedType(event.unit)
			if totals.summons[credited] then
				totals.summons[credited].made += 1
			end
			if copy then
				totals.copy.byCost[copy.cost].summons += 1
			end
		elseif kind == "Attack" or kind == "Damage" then
			local info = units[event.unit]
			local credited = creditedType(event.unit)
			local source = if info and info.summoned
				then "summon"
				elseif kind == "Attack" then "attack"
				elseif event.dot then "dot"
				else "ability"
			totals.damage[source] += event.damage
			if credited then
				typeStats(credited)[source] += event.damage
			end
			if copy and kind == "Damage" and not event.dot then
				totals.copy.byCost[copy.cost].damage += event.damage
			end
			if source == "summon" and totals.summons[credited] then
				totals.summons[credited].damage += event.damage
			end
			-- Overkill of single big hits: damage beyond the target's health and shield.
			if kind == "Damage" and not event.dot and info and not info.summoned and totals.burst[info.unitType] then
				local before = (health[event.target] or 0) + (shield[event.target] or 0)
				local entry = totals.burst[info.unitType]
				if event.damage > before then
					entry.overkills += 1
					entry.overkillSum += event.damage - before
				end
				if event.health <= 0 then
					entry.kills += 1
				end
			end
			health[event.target] = event.health
			shield[event.target] = event.shield
		elseif kind == "Heal" then
			health[event.target] = event.health
			local credited = creditedType(event.unit)
			if credited then
				typeStats(credited).heal += event.amount
			end
			if copy then
				totals.copy.byCost[copy.cost].support += event.amount
			end
		elseif kind == "Shield" then
			shield[event.target] = event.shield
			local credited = creditedType(event.unit)
			if credited and not event.source then
				typeStats(credited).shield += event.shield
			end
			if copy then
				totals.copy.byCost[copy.cost].support += event.shield
			end
		elseif kind == "ShieldEnd" then
			shield[event.unit] = 0
		elseif kind == "MaxHealth" then
			health[event.unit] = event.health
		elseif kind == "Cast" then
			local info = units[event.unit]
			if info.unitType and hasEffect(info.unitType, "PULL") then
				totals.pull.casts += 1
			end
			if info.unitType and totals.burst[info.unitType] then
				totals.burst[info.unitType].casts += 1
			end
			if info.unitType and totals.summons[info.unitType] then
				totals.summons[info.unitType].casts += 1
			end
		elseif kind == "Pull" and hasEffect(units[event.unit].unitType, "PULL") then
			-- Pulls by the character's own ability (copied pulls are not counted here).
			totals.pull.moved += 1
			pulled[event.target] = event.tick
		elseif kind == "Copy" then
			local copiedType = units[event.target].unitType
			local cost = UnitConfig[copiedType].cost
			totals.copy.targets[copiedType] = (totals.copy.targets[copiedType] or 0) + 1
			local entry = totals.copy.byCost[cost] or { copies = 0, damage = 0, support = 0, summons = 0 }
			entry.copies += 1
			totals.copy.byCost[cost] = entry
			copy = { unit = event.unit, tick = event.tick, cost = cost }
		elseif kind == "Stun" then
			local finish = event.tick + math.round(event.duration * tps)
			local current = stunIntervals[event.target]
			if current and event.tick <= current.finish then
				current.finish = math.max(current.finish, finish)
			else
				local total = if current then current.total + (current.finish - current.start) else 0
				stunIntervals[event.target] = { start = event.tick, finish = finish, total = total }
			end
		elseif kind == "Buff" and event.stacks then
			stackMax[event.unit] = math.max(stackMax[event.unit] or 0, event.stacks)
		elseif kind == "Death" or kind == "SummonEnd" then
			deathTick[event.unit] = event.tick
		end
	end

	-- Stunned time, cut off at each unit's death or the end of the fight.
	for index, interval in stunIntervals do
		local stop = deathTick[index] or result.endTick
		local last = math.max(0, math.min(interval.finish, stop) - interval.start)
		local seconds = (interval.total + last) / tps
		totals.stun.stunnedSeconds[units[index].side] += seconds
	end
	-- How long pulled units lived after the pull.
	for index, tick in pulled do
		local lived = ((deathTick[index] or result.endTick) - tick) / tps
		totals.pull.survivalSum += lived
		totals.pull.survivalCount += 1
		if deathTick[index] and lived <= 3 then
			totals.pull.diedWithin3 += 1
		end
	end
	-- Summon uptime.
	for index, start in summonStart do
		local entry = totals.summons[units[units[index].summoner].unitType]
		if entry then
			entry.aliveSeconds += ((deathTick[index] or result.endTick) - start) / tps
		end
	end
	-- Highest stack count reached, per stacking-buff unit (0 if it never cast).
	for _, unit in result.units do
		if hasStackingBuff(unit.unitType) then
			-- reached[n + 1] counts fights whose highest stack count was n (0-3).
			local entry = totals.stacks[unit.unitType] or { present = 0, reached = { 0, 0, 0, 0 } }
			entry.present += 1
			local reached = stackMax[unit.index] or 0
			entry.reached[reached + 1] += 1
			totals.stacks[unit.unitType] = entry
		end
	end
end

local function percent(part: number, whole: number): string
	return if whole > 0 then string.format("%.1f%%", part / whole * 100) else "-"
end

local function sortedKeys(map, by)
	local keys = {}
	for key in map do
		table.insert(keys, key)
	end
	table.sort(keys, by or function(a, b)
		return a < b
	end)
	return keys
end

function Mechanics.report()
	local damage = totals.damage
	local all = damage.attack + damage.ability + damage.dot + damage.summon
	print(
		string.format(
			"Damage by source (all units, all star levels): basic attacks %s, abilities %s, damage over time %s, summons %s",
			percent(damage.attack, all),
			percent(damage.ability, all),
			percent(damage.dot, all),
			percent(damage.summon, all)
		)
	)

	print("Per character per fight it appeared in (all star levels): damage split; healing and shielding given")
	for _, unitType in
		sortedKeys(totals.byType, function(a, b)
			local costA, costB = UnitConfig[a].cost, UnitConfig[b].cost
			return costA < costB or (costA == costB and a < b)
		end)
	do
		local stats = totals.byType[unitType]
		local dealt = stats.attack + stats.ability + stats.dot + stats.summon
		local parts = {
			string.format("attack %s", percent(stats.attack, dealt)),
			string.format("ability %s", percent(stats.ability, dealt)),
		}
		if stats.dot > 0 then
			table.insert(parts, "over time " .. percent(stats.dot, dealt))
		end
		if stats.summon > 0 then
			table.insert(parts, "summons " .. percent(stats.summon, dealt))
		end
		if stats.heal > 0 then
			table.insert(parts, string.format("heals %.0f", stats.heal / stats.present))
		end
		if stats.shield > 0 then
			table.insert(parts, string.format("shields %.0f", stats.shield / stats.present))
		end
		print(string.format("  %-18s %s  [%d fights]", unitType, table.concat(parts, ", "), stats.present))
	end

	local pull = totals.pull
	print(
		string.format(
			"Pulls: %d casts, %s moved their target; pulled targets lived %.1fs on average after the pull, %s died within 3s",
			pull.casts,
			percent(pull.moved, pull.casts),
			if pull.survivalCount > 0 then pull.survivalSum / pull.survivalCount else 0,
			percent(pull.diedWithin3, pull.survivalCount)
		)
	)

	print("Summons, per fight the summoner appeared in: casts, summons made, summon damage, summon-seconds alive")
	for _, unitType in sortedKeys(totals.summons) do
		local entry = totals.summons[unitType]
		print(
			string.format(
				"  %-18s %.2f casts, %.2f summons, %.0f damage, %.1f summon-seconds  [%d fights]",
				unitType,
				entry.casts / entry.present,
				entry.made / entry.present,
				entry.damage / entry.present,
				entry.aliveSeconds / entry.present,
				entry.present
			)
		)
	end

	local copyCount = 0
	for _, count in totals.copy.targets do
		copyCount += count
	end
	local mostCopied = {}
	for i, unitType in
		sortedKeys(totals.copy.targets, function(a, b)
			return totals.copy.targets[a] > totals.copy.targets[b]
				or (totals.copy.targets[a] == totals.copy.targets[b] and a < b)
		end)
	do
		if i <= COPY_TARGET_SAMPLE then
			table.insert(
				mostCopied,
				string.format("%s %s", unitType, percent(totals.copy.targets[unitType], copyCount))
			)
		end
	end
	print(string.format("COPY: %d copies; most copied: %s", copyCount, table.concat(mostCopied, ", ")))
	for cost = 1, 5 do
		local entry = totals.copy.byCost[cost]
		if entry then
			print(
				string.format(
					"  copied %d-cost: %d copies, %.0f damage, %.0f healing+shielding, %.2f summons per copy",
					cost,
					entry.copies,
					entry.damage / entry.copies,
					entry.support / entry.copies,
					entry.summons / entry.copies
				)
			)
		end
	end

	print(
		string.format(
			"Stun uptime: side 1 units spent %.1f unit-seconds stunned per fight, side 2 %.1f",
			totals.stun.stunnedSeconds[1] / totals.fights,
			totals.stun.stunnedSeconds[2] / totals.fights
		)
	)

	for _, unitType in sortedKeys(totals.burst) do
		local entry = totals.burst[unitType]
		print(
			string.format(
				"Single big hit %s: %.2f casts per fight, %s of casts kill, %s overkill with %.0f damage wasted on average  [%d fights]",
				unitType,
				entry.casts / entry.present,
				percent(entry.kills, entry.casts),
				percent(entry.overkills, entry.casts),
				if entry.overkills > 0 then entry.overkillSum / entry.overkills else 0,
				entry.present
			)
		)
	end

	for _, unitType in sortedKeys(totals.stacks) do
		local entry = totals.stacks[unitType]
		local parts = {}
		for stacks = 0, 3 do
			table.insert(parts, string.format("%d: %s", stacks, percent(entry.reached[stacks + 1], entry.present)))
		end
		print(
			string.format(
				"Stacking buff %s: highest stacks reached per fight %s  [%d fights]",
				unitType,
				table.concat(parts, ", "),
				entry.present
			)
		)
	end
end

return Mechanics
