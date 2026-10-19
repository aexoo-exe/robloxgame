-- Studio-only: the dev lineup's reel (DevLineup, key R), which plays a batch of ultimates in one
-- clip: per unit a title card, the ultimate at 1x, a pause, the ultimate again in slow motion, a gap.

return {
	-- Unit ids to play, in order, e.g. { "thunder_nest", "volt_spear" }. Empty: every roster unit
	-- with an ultimate (UltimateConfig.units), by tier then id.
	-- The vertical slice: cinder_arc alone (DevLineup K replays it too).
	units = {
		"cinder_arc",
	} :: { string },
	arena = "gray", -- the test arena during the reel: "off", "gray" or "bright"
	camera = "close", -- its fixed camera: "gameplay", "close" or "wide"
	titleSeconds = 1.0, -- the title card (unit id and tier) before each unit
	pauseSeconds = 1.0, -- between the 1x play and the slow one
	slowScale = 0.25, -- the second play's speed
	gapSeconds = 0.5, -- after the slow play, before the next unit
	endSeconds = 2.0, -- the "REEL END" card

	-- The CHECK pass (ReelCheck), printed at the reel's end.
	-- Most effect parts alive at once per ultimate tier (1-5): the audit's limits
	-- (scripts/audit-units.luau PEAK_LIMIT; keep the two the same). ReelCheck counts live parts
	-- for this, as the audit does.
	budget = { 14, 18, 26, 34, 44 },
	leakSeconds = 3.0, -- after a unit's last play: anything still live then is a leak
}
