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
			spurshot = 220, -- 255 at 1 star
			orbit_breaker = 260, -- 302 at 1 star
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
	}),
})
