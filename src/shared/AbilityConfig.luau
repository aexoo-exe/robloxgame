-- Named switches and limits of individual abilities (Overhaul 1, docs/design/overhaul-1.md).
-- Ability amounts live with each ability in UnitConfig; form numbers in FormConfig. Characters are
-- named by internal id only. All values are placeholders.
-- Pure Luau: no Roblox APIs, so it loads in Lune tests too.

return table.freeze({
	-- cyclone_edge: follow-ups per cast (dash to the nearest enemy and repeat the area hit when his
	-- target dies while his attack speed buff lasts).
	cycloneEdgeRepeats = 2,
	-- shade_pack: later casts bring dead wolves back (up to the first cast's count).
	shadePackResummon = true,
	-- shade_pack: mana the caster gains for each wolf basic attack.
	shadePackManaPerHit = 4,
	-- night_parade: cast cycle length. Each cast before the last of the cycle summons a curse; the
	-- last cast recalls every living curse (any number, even none) and fires the line; then the
	-- count starts over.
	nightParadeCycle = 3,
	-- blooming_aid: heals only if an ally (her included) is below this health percentage;
	-- otherwise she hits her current target.
	bloomingAidHealBelowPercent = 70,
	-- flare_kick: hexes around him searched for the lowest-health enemy.
	flareKickRange = 2,
	-- starless_burst: hexes around an enemy counted for the largest cluster.
	starlessBurstClusterRadius = 2,
})
