-- Studio-only: the dev lineup's reel (DevLineup, key R), which plays a batch of ultimates in one
-- clip: per unit a title card, the ultimate at 1x, a pause, the ultimate again in slow motion, a gap.

return {
	-- Unit ids to play, in order, e.g. { "thunder_nest", "volt_spear" }. Empty: every roster unit
	-- with an ultimate (UltimateConfig.units), by tier then id.
	-- Now: the units already on VfxRecipe (batches 1-3).
	units = {
		"snapfire",
		"cinder_arc",
		"burst_vector",
		"flare_kick",
		"boiling_crown",
		"infinite_collapse",
		"ascending_core",
		"thunder_nest",
		"volt_spear",
		"zero_field",
		"titanheart",
		"echo_legion",
		"starless_burst",
		"final_argument",
		"skyboulder",
		"marsh_fortress",
		"iron_rush",
		"reelbreaker",
		"blooming_aid",
		"clockbreaker",
	} :: { string },
	arena = "gray", -- the test arena during the reel: "off", "gray" or "bright"
	camera = "close", -- its fixed camera: "gameplay", "close" or "wide"
	titleSeconds = 1.0, -- the title card (unit id and tier) before each unit
	pauseSeconds = 1.0, -- between the 1x play and the slow one
	slowScale = 0.25, -- the second play's speed
	gapSeconds = 0.5, -- after the slow play, before the next unit
	endSeconds = 2.0, -- the "REEL END" card

	-- The CHECK pass (ReelCheck), printed at the reel's end.
	-- Most live effect instances at once per ultimate tier (1-5); more is a warning. A starting
	-- guess for the check, not a rule elsewhere: tune it from the reports.
	budget = { 14, 18, 22, 26, 32 },
	leakSeconds = 3.0, -- after a unit's last play: anything still live then is a leak
}
