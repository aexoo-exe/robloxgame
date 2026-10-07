-- Everything players see about a character, keyed by its internal id (UnitConfig key): its display
-- name, its ability's display name and its color as { red, green, blue } (0-255). All character
-- text in the UI comes from here and nowhere else, so renaming or reskinning a character is a
-- change to this file only. Names are from docs/design/revamp-roster.md (Block 2).
-- The colors are not drawn at the moment: unit bodies and shop cards are colored by cost
-- (RenderConfig.costColors), and traits show as symbols (TraitIconConfig).
-- Pure Luau: no Roblox APIs, so it loads in Lune tests too.

local HUNTERS = { 214, 120, 52 }
local CORPS = { 112, 152, 196 }
local SPIRIT = { 120, 200, 140 }
local CURSED = { 150, 70, 180 }
local ARCANE = { 90, 110, 230 }
local TITANS = { 150, 120, 95 }
local SHINOBI = { 70, 170, 175 }
local CREW = { 232, 92, 92 }
local HEROES = { 240, 200, 70 }

local function skin(name: string, ability: string, color: { number })
	return table.freeze({ name = name, ability = ability, color = table.freeze(table.clone(color)) })
end

return table.freeze({
	-- 1-cost
	flashline = skin("Lightitsu", "Flashline", HUNTERS),
	cinder_arc = skin("Tontaro", "Cinder Arc", HUNTERS),
	wolfstep = skin("Thorvinn", "Wolfstep", CORPS),
	spurshot = skin("Jonny", "Spurshot", SPIRIT),
	ripcord_frenzy = skin("Dengi", "Ripcord Frenzy", CURSED),
	null_edge = skin("Pasta", "Null Edge", ARCANE),
	bitter_vapor = skin("Meow-Meow", "Bitter Vapor", ARCANE),
	iron_rush = skin("Armored Giant", "Iron Rush", TITANS),
	blooming_aid = skin("Saku", "Blooming Aid", SHINOBI),

	-- 2-cost
	redline_cut = skin("Mika", "Redline Cut", CORPS),
	flare_kick = skin("Love-cook", "Flare Kick", CREW),
	burst_vector = skin("Kachan", "Burst Vector", HEROES),
	skybreaker = skin("Quirkless", "Skybreaker", HEROES),
	crimson_hunger = skin("Kenny", "Crimson Hunger", CURSED),
	orbit_breaker = skin("Jyro", "Orbit Breaker", SPIRIT),
	marsh_fortress = skin("Toad Samurai", "Marsh Fortress", SHINOBI),
	shade_pack = skin("Potential Man", "Shade Pack", CURSED),
	field_medic = skin("Boku wa Docta", "Field Medic", CREW),

	-- 3-cost
	volt_spear = skin("Saucekay", "Volt Spear", SHINOBI),
	thunder_nest = skin("Zolduck", "Thunder Nest", HUNTERS),
	threefold_crash = skin("Moss Head", "Threefold Crash", CREW),
	titanheart = skin("Aaron", "Titanheart", TITANS),
	snapfire = skin("Ray", "Snapfire", ARCANE),
	mirror_script = skin("Kashi", "Mirror Script", SHINOBI),
	clockbreaker = skin("Goataro", "Clockbreaker", SPIRIT),
	skyboulder = skin("Beast Giant", "Skyboulder", TITANS),
	horizon_cut = skin("Itchigo", "Horizon Cut", HUNTERS),
	zero_field = skin("Urarocka", "Zero Field", HEROES),

	-- 4-cost
	reelbreaker = skin("Freaks", "Reelbreaker", HUNTERS),
	elastic_wardrum = skin("Rubber Man", "Elastic Wardrum", CREW),
	starless_burst = skin("Archmage", "Starless Burst", ARCANE),
	echo_legion = skin("Fish Cake", "Echo Legion", SHINOBI),
	night_command = skin("Leveler", "Night Command", HUNTERS),
	frozen_moment = skin("Za Warudo", "Frozen Moment", SPIRIT),
	cyclone_edge = skin("Revi", "Cyclone Edge", CORPS),
	night_parade = skin("Bangs", "Night Parade", CURSED),
	restoration_strike = skin("Joeskay", "Restoration Strike", SPIRIT),

	-- 5-cost
	severing_temple = skin("Thukuna", "Severing Temple", CURSED),
	ascending_core = skin("Sonion", "Ascending Core", HEROES),
	final_argument = skin("Punchman", "Final Argument", HEROES),
	infinite_collapse = skin("The Strongest", "Infinite Collapse", CURSED),
	boiling_crown = skin("Colossal Giant", "Boiling Crown", TITANS),
})
