-- Studio-only: the dev lineup's reel (DevLineup, key R), which plays a batch of ultimates in one
-- clip: per unit a title card, the ultimate at 1x, a pause, the ultimate again in slow motion, a gap.

return {
	-- Unit ids to play, in order, e.g. { "thunder_nest", "volt_spear" }. Empty: every roster unit
	-- with an ultimate (UltimateConfig.units), by tier then id.
	units = {} :: { string },
	arena = "gray", -- the test arena during the reel: "off", "gray" or "bright"
	camera = "close", -- its fixed camera: "gameplay", "close" or "wide"
	titleSeconds = 1.0, -- the title card (unit id and tier) before each unit
	pauseSeconds = 1.0, -- between the 1x play and the slow one
	slowScale = 0.25, -- the second play's speed
	gapSeconds = 0.5, -- after the slow play, before the next unit
	endSeconds = 2.0, -- the "REEL END" card
}
