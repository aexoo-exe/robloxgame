-- Placeholder visuals for the client. Distances are in studs.
-- The field is laid out on the X/Z plane: columns run along +X, and the local player's side is
-- toward +Z (nearest the camera), with the bench in front of it.
return table.freeze({
	arenaCenter = Vector3.new(0, 0, 120),

	hexRadius = 3, -- center to corner
	cellGap = 0.2, -- shaved off each cell's radius so neighbors are visibly separate
	cellThickness = 0.4,
	benchDistance = 6, -- from the center of the nearest row to the bench slots

	unitSize = Vector3.new(2.2, 3.5, 2.2),
	-- Size multiplier by star level (1, 2, 3), and the symbol repeated after a unit's name.
	starSizeScale = table.freeze({ 1, 1.15, 1.3 }),
	starSymbol = "★",

	ownCellColor = Color3.fromRGB(70, 95, 130),
	enemyCellColor = Color3.fromRGB(120, 75, 75),
	benchSlotColor = Color3.fromRGB(95, 95, 95),
	-- Colors by unit cost (1-5): shop card stripes and borders, and unit bodies on the board and in
	-- combat. Traits show as symbols instead (TraitIconConfig). Which side a unit is on shows in its
	-- health bar color.
	costColors = table.freeze({
		Color3.fromRGB(150, 150, 155), -- 1-cost gray
		Color3.fromRGB(70, 190, 90), -- 2-cost green
		Color3.fromRGB(60, 130, 230), -- 3-cost blue
		Color3.fromRGB(165, 80, 220), -- 4-cost purple
		Color3.fromRGB(235, 185, 50), -- 5-cost gold
	}),
	traitIconSize = 12, -- pixels, on unit info boards (shop cards and the tooltip use larger ones)
	healthBarColor = Color3.fromRGB(80, 220, 100), -- the local player's units
	enemyHealthBarColor = Color3.fromRGB(235, 70, 70),
	shieldColor = Color3.fromRGB(235, 235, 235),
	manaBarColor = Color3.fromRGB(70, 150, 255),
	critFlashColor = Color3.fromRGB(255, 150, 40),
	stunMarkerColor = Color3.fromRGB(255, 230, 60),
	castTextColor = Color3.fromRGB(170, 210, 255),
	healTextColor = Color3.fromRGB(110, 255, 140),
	popTextDuration = 1, -- seconds floating text (ability names, buffs) stays visible
	hitFlashColor = Color3.fromRGB(255, 255, 255),
	hitFlashDuration = 0.08, -- seconds
	refusalNoticeDuration = 2, -- seconds a "request refused" message stays on screen

	-- Trait panel rows: active traits are highlighted, partial ones are dim.
	traitActiveColor = Color3.fromRGB(205, 160, 50),
	traitActiveTextColor = Color3.fromRGB(20, 20, 20),
	traitInactiveColor = Color3.fromRGB(45, 45, 55),
	traitInactiveTextColor = Color3.fromRGB(170, 170, 180),

	-- Combat playback. Durations are in seconds; none of them change fight timing, which comes
	-- from the server's event list.
	visorColor = Color3.fromRGB(30, 30, 40), -- marks the front of a unit, so turning is visible
	turnRate = 14, -- how quickly units turn to face their target (higher is snappier)
	dashDuration = 0.15, -- dashes are instant in the sim; a short slide keeps them readable
	dashTrailColor = Color3.fromRGB(255, 255, 255),
	dashTrailLifetime = 0.2,
	lungeDistance = 0.9, -- melee attacks lunge this far toward the target and back
	lungeDuration = 0.22, -- the lunge peaks halfway, as the hit lands
	projectileFlightTime = 0.25, -- ranged attacks launch this long before the hit lands
	projectileSize = 0.6,
	projectileArcHeight = 1.5,
	ownProjectileColor = Color3.fromRGB(150, 200, 255),
	enemyProjectileColor = Color3.fromRGB(255, 160, 140),
	castGlowColor = Color3.fromRGB(190, 170, 255),
	castGlowDuration = 0.35,
	areaPulseColor = Color3.fromRGB(200, 120, 255),
	areaPulseDuration = 0.45,
	areaPulseTransparency = 0.35, -- starting transparency of each affected hex
	areaWaveDelay = 0.06, -- extra delay per hex from the center, so the pulse spreads outward
	shieldBubbleColor = Color3.fromRGB(150, 220, 255),
	shieldBubbleScale = 1.35, -- bubble diameter relative to the unit's largest side
	summonScale = 0.65, -- summons are drawn smaller than units
	summonTransparency = 0.45, -- and see-through
	areaStunColor = Color3.fromRGB(255, 230, 60), -- AREA_STUN pulse
	dotNumberSize = 13, -- damage-over-time ticks
	-- Forms (transformations). A form's own health pool (a rider's horse) is a second bar stacked
	-- above the health bar. Looks are keyed by form name: `label` floats up when the unit enters the
	-- form, and `mount` adds a placeholder horse (a block body and head under the unit).
	formHealthColor = Color3.fromRGB(230, 160, 60),
	formChangeTextColor = Color3.fromRGB(255, 210, 120),
	formLooks = table.freeze({
		Mounted = table.freeze({ label = "Mounted", mount = Color3.fromRGB(125, 85, 50) }),
		Dismounted = table.freeze({ label = "Dismounted!" }),
	}),
	-- PvE rounds: tint of the top phase label. Creep and boss bodies, names and sizes come from
	-- their theme's looks (PveThemeConfig).
	creepRoundColor = Color3.fromRGB(35, 80, 40),
	bossRoundColor = Color3.fromRGB(100, 25, 25),
	deathFadeDuration = 0.5,
	deathSinkDistance = 1.2,

	-- Floating numbers and text. Sizes are in pixels, so they stay readable on small screens.
	physicalDamageColor = Color3.fromRGB(255, 200, 120),
	magicDamageColor = Color3.fromRGB(200, 140, 255),
	trueDamageColor = Color3.fromRGB(255, 255, 255),
	damageNumberSize = 18,
	critNumberSize = 26,
	floatTextSize = 16, -- ability names, buffs
	damageNumberDuration = 0.8,
	damageNumberRise = 40,
	-- Horizontal lanes (pixel offsets) that successive numbers on one unit cycle through, so several
	-- hits on the same unit stay readable instead of stacking.
	damageNumberLanes = table.freeze({ 0, -34, 34, -17, 17 }),
	maxFloatingTexts = 6, -- per unit; the oldest goes first

	-- Camera position relative to arenaCenter. It looks at arenaCenter.
	cameraOffset = Vector3.new(0, 46, 34),
})
