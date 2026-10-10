-- Everything players see about an item, keyed by its id (ItemConfig): display name, effect text
-- and icon. Renaming or re-wording an item is a change to this file only.
-- Effect text is a template: {path} is replaced by that number from the item's ItemConfig entry
-- (for example {stats.AD.percent}), and {%path} by the number times 100 (0-1 chances as percents).
-- Items.describe fills it in, so the text always shows the current numbers.
-- `icon`: the placeholder pictogram (client ItemPictograms), drawn on a square in the item's
-- category color. Every item has its own.
-- `image` (optional): an image id, e.g. "rbxassetid://1234567890", drawn instead of the pictogram
-- (on the same category-colored square) once real icon art exists. Pass it as skin()'s 4th value.
-- Pure Luau: no Roblox APIs, so it loads in Lune tests too.

local function skin(name: string, icon: string, text: string, image: string?)
	return table.freeze({ name = name, icon = icon, text = text, image = image })
end

return table.freeze({
	-- Icon colors by item category, { red, green, blue }.
	categoryColors = table.freeze({
		OFFENSIVE = table.freeze({ 225, 95, 70 }),
		ABILITY = table.freeze({ 120, 110, 235 }),
		DEFENSIVE = table.freeze({ 90, 170, 110 }),
	}),

	items = table.freeze({
		sunforged_blade = skin(
			"Sunforged Blade",
			"blade",
			"+{stats.AD.percent}% attack damage, +{%stats.CritChance.flat}% crit chance. Abilities can crit."
		),
		runaway_clock = skin(
			"Runaway Clock",
			"clock",
			"+{stats.AttackSpeed.percent}% attack speed. Each attack adds +{effect.attackSpeedPercentPerAttack}% attack speed for the fight (up to {effect.maxStacks})."
		),
		golden_arrow = skin(
			"Golden Arrow",
			"arrow",
			"+{stats.AD.percent}% attack damage, +{%stats.CritChance.flat}% crit chance. Attacks lower the target's armor by {effect.armorShredPercent}% for {effect.seconds}s."
		),
		oni_cutter = skin(
			"Oni Cutter",
			"katana",
			"+{stats.AD.percent}% attack damage, +{stats.AttackSpeed.percent}% attack speed. +{effect.bonusDamagePercent}% damage to enemies with more max health."
		),
		ghouls_mask = skin(
			"Ghoul's Mask",
			"mask",
			"+{stats.AD.percent}% attack damage. Heals for {effect.lifestealPercent}% of damage dealt. Once, below {effect.belowPercent}% health: a shield of {effect.shieldPercent}% max health for {effect.shieldSeconds}s."
		),
		thousand_year_staff = skin("Thousand-Year Staff", "staff", "+{stats.AP.flat} ability power."),
		strange_fruit = skin(
			"Strange Fruit",
			"fruit",
			"+{effect.startingMana} starting mana. +{effect.manaPerCast} mana after each cast."
		),
		cursebreaker_spear = skin(
			"Curse-Breaker Spear",
			"spear",
			"+{stats.AD.percent}% attack damage, +{stats.AP.flat} ability power. +{effect.manaPerAttack} mana per attack."
		),
		tattered_grimoire = skin(
			"Tattered Grimoire",
			"book",
			"+{stats.AP.flat} ability power, +{stats.MaxHealth.percent}% max health. Ability damage burns for {effect.burnPercent}% over {effect.burnSeconds}s; burning enemies receive {effect.healingReductionPercent}% less healing."
		),
		giants_serum = skin(
			"Giant's Serum",
			"syringe",
			"Attacking or being hit: +{effect.attackDamagePercentPerStack}% attack damage and +{effect.abilityPowerPerStack} ability power (up to {effect.maxStacks} times). At full: +{effect.fullResist} armor and magic resist."
		),
		steel_arm = skin("Steel Arm", "arm", "+{stats.MaxHealth.percent}% max health."),
		straw_doll = skin(
			"Straw Doll",
			"doll",
			"+{stats.Armor.flat} armor. When hit by an attack: {effect.damage} magic damage to adjacent enemies (every {effect.cooldown}s at most)."
		),
		cloud_cloak = skin(
			"Cloud Cloak",
			"cloak",
			"+{stats.MR.flat} magic resist. Heals {effect.healPercent}% of max health every {effect.interval}s."
		),
		sand_gourd = skin(
			"Sand Gourd",
			"gourd",
			"+{stats.Armor.flat} armor and magic resist, +{effect.resistPerAttacker} more of each per enemy targeting the holder."
		),
		conquerors_will = skin(
			"Conqueror's Will",
			"crown",
			"+{stats.AttackSpeed.percent}% attack speed. Immune to stuns for the first {effect.stunImmuneSeconds}s."
		),
	}),
})
