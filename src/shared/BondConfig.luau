-- Bonds: two characters that get something extra when both are on the board (placed, not bench).
-- Characters are named by internal id; players see both characters' display names (SkinConfig).
-- TraitCombat runs each bond's `kind`; every number is a placeholder (Overhaul 1,
-- docs/design/overhaul-1.md).
--   TAKEDOWN_BOOST  a takedown by one gives the other a damage boost (DamageDealt percent) for a
--                   few seconds
--   TOGETHER        both deal more damage (DamageDealt percent) while both are alive; when one dies
--                   the survivor gains mana and a short damage boost
--   REMOUNT         each may remount once per fight (FormConfig.mount; sets the remount flag)
-- Pure Luau: no Roblox APIs, so it loads in Lune tests too.

local FormConfig = if script then require(script.Parent.FormConfig) else require("./FormConfig")

return table.freeze({
	{
		id = "crash_kick",
		units = table.freeze({ "threefold_crash", "flare_kick" }),
		kind = "TAKEDOWN_BOOST",
		params = table.freeze({ damagePercent = 20, seconds = 4 }),
	},
	{
		id = "cursed_pair",
		units = table.freeze({ "night_parade", "infinite_collapse" }),
		kind = "TOGETHER",
		params = table.freeze({ damagePercent = 12, survivorMana = 40, survivorPercent = 30, survivorSeconds = 5 }),
	},
	{
		id = "riders",
		units = table.freeze({ "spurshot", "orbit_breaker" }),
		kind = "REMOUNT",
		params = table.freeze({ flag = FormConfig.mount.remountFlag }),
	},
})
