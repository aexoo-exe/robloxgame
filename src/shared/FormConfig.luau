-- Tunable numbers for forms (transformations; see Forms.luau and docs/forms.md). Characters are
-- named by internal id only.
-- Pure Luau: no Roblox APIs, so it loads in Lune tests too.

return table.freeze({
	-- How a form's own health pool interacts with the rest of combat. Every form follows these
	-- unless it sets the same key in its own `rules` table.
	rules = table.freeze({
		-- Shields absorb a hit before the form's health pool. false: the pool takes the hit first,
		-- and the shield only absorbs once the pool is gone.
		shieldsAbsorbBeforeFormHealth = true,
		-- Heals (and lifesteal, when it exists) restore the unit's own health only. true: healing
		-- beyond the unit's missing health also refills the pool, up to its maximum.
		healingRestoresFormHealth = false,
		-- Damage-over-time ticks hit the pool like any other damage. false: they skip the pool and
		-- hit the unit's own health.
		damageOverTimeHitsFormHealth = true,
		-- Stuns and damage over time on the unit continue through a form change. false: changing
		-- form ends them (buffs and shields always stay).
		statusEffectsCarryThrough = true,
		-- Damage to the pool gives the unit mana as if its own health had lost that much (same
		-- formula, same cap per hit, against the unit's own max health). false: pool damage gives
		-- no mana, like shield damage.
		formHealthDamageGivesMana = true,
	}),

	-- Rider mounts (the Mounted and Dismounted forms; see UnitConfig).
	mount = table.freeze({
		-- Horse health pool per rider, before scaling: like unit health it is multiplied by the star
		-- level's health multiplier and CombatConfig.globalHealthMultiplier (StarLevel.scaleHealth).
		horseHealth = table.freeze({
			spurshot = 300, -- 390 at 1 star (x1.2992)
			orbit_breaker = 260, -- 338 at 1 star
		}),
		-- Added to the rider's move speed while mounted (flat, on the move speed scalar). This is the
		-- riders' former extra speed: their UnitConfig move speed went from 1.2 to 1.0.
		mountedMoveSpeedBonus = 0.2,
		-- Added to the rider's attack damage while mounted (flat).
		mountedBonusDamage = 0,
		-- When true, a dismounted rider remounts after its next takedown (it lands the killing blow
		-- on an enemy board unit; summons do not count), at most remountsPerFight times per fight.
		remountEnabled = false,
		remountsPerFight = 1,
		-- Horse pool on remount, as a percentage of its full pool.
		remountHorseHealthPercent = 50,
		-- With remountEnabled false, a rider can still remount when this flag is set for the fight
		-- (the spurshot + orbit_breaker bond sets it; BondConfig).
		remountFlag = "remount",
	}),

	-- Overhaul 1 forms (placeholders). Stat changes are { flat = n } or { percent = n }; splash is the
	-- percentage of a basic attack that also hits enemies next to the target.
	-- ripcord_frenzy: the first cast only transforms; the chainsaw form lasts the rest of the fight.
	ripcordFrenzy = table.freeze({
		chainsawAttackSpeedPercent = 60,
		chainsawSplashPercent = 70,
	}),
	-- titanheart: a smaller human form; below the health threshold (once per fight) a titan form with
	-- its own health pool, back to human when the pool is empty.
	titanheart = table.freeze({
		humanAttackDamagePercent = -25,
		humanArmorFlat = -15,
		humanMagicResistFlat = -15,
		titanBelowPercent = 50,
		titanHealth = 900, -- pool before scaling (StarLevel.scaleHealth): 1169 at 1 star
		titanAttackDamagePercent = 35,
		titanArmorFlat = 15,
		titanSplashPercent = 35,
	}),
	-- field_medic: below the health threshold (once per fight) a melee bruiser form.
	fieldMedic = table.freeze({
		bruiserBelowPercent = 50,
		bruiserRange = 1,
		bruiserAttackDamageFlat = 35,
		bruiserAttackSpeedPercent = 20,
		bruiserArmorFlat = 15,
	}),
	-- elastic_wardrum: gears for the rest of the fight. Gear 2 attacks faster; gear 3 also splashes.
	elasticWardrum = table.freeze({
		attackSpeedPercent = 30,
		splashPercent = 40,
	}),
	-- ascending_core's three forms change only its ability and look (RenderConfig.formLooks).
})
