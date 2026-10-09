-- Placeholder visuals for the client. Distances are in studs.
-- The field is laid out on the X/Z plane: columns run along +X, and the local player's side is
-- toward +Z (nearest the camera), with the bench in front of it.
return table.freeze({
	arenaCenter = Vector3.new(0, 0, 120),

	hexRadius = 3, -- center to corner
	cellGap = 0.2, -- shaved off each cell's radius so neighbors are visibly separate
	cellThickness = 0.4,
	benchDistance = 6, -- from the center of the nearest row to the bench slots

	-- A unit's click box (invisible); its figure (FigureConfig) is drawn this tall. Tiles are about
	-- 4.8 studs across, so a 3-star unit (x1.3) still fits its tile.
	unitSize = Vector3.new(2.8, 4.6, 2.8),
	-- Size multiplier by star level (1, 2, 3).
	starSizeScale = table.freeze({ 1, 1.15, 1.3 }),

	-- The display just above each unit's head, in studs: it stays narrower than a tile (about 4.8
	-- studs), so neighbors never overlap. Rows from the top: star pips, the horse bar (riders),
	-- health, mana.
	overhead = table.freeze({
		width = 3.2,
		pipHeight = 0.34,
		formBarHeight = 0.18,
		healthBarHeight = 0.3,
		manaBarHeight = 0.11,
		gap = 0.04,
		aboveHead = 0.12, -- from the top of the unit's box to the bottom of the display
		barBackground = Color3.fromRGB(14, 14, 20),
		-- Star pip colors by star level: bronze, silver, gold.
		starColors = table.freeze({
			Color3.fromRGB(215, 140, 70),
			Color3.fromRGB(205, 215, 230),
			Color3.fromRGB(255, 210, 60),
		}),
	}),

	-- Colors by unit cost (1-5): shop card stripes and borders, and the ring under each unit on the
	-- board and in combat (bodies use the character's SkinConfig color). Traits show as symbols
	-- (TraitIconConfig). Which side a unit is on shows in its health bar color.
	costColors = table.freeze({
		Color3.fromRGB(150, 150, 155), -- 1-cost gray
		Color3.fromRGB(70, 190, 90), -- 2-cost green
		Color3.fromRGB(60, 130, 230), -- 3-cost blue
		Color3.fromRGB(165, 80, 220), -- 4-cost purple
		Color3.fromRGB(235, 185, 50), -- 5-cost gold
	}),
	healthBarColor = Color3.fromRGB(80, 220, 100), -- the local player's units
	enemyHealthBarColor = Color3.fromRGB(235, 70, 70),
	shieldColor = Color3.fromRGB(235, 235, 235),
	manaBarColor = Color3.fromRGB(70, 150, 255),
	critFlashColor = Color3.fromRGB(255, 150, 40),
	stunMarkerColor = Color3.fromRGB(255, 230, 60), -- the halo over a stunned unit
	healTextColor = Color3.fromRGB(110, 255, 140),
	hitFlashColor = Color3.fromRGB(255, 255, 255),
	hitFlashDuration = 0.08, -- seconds

	-- Combat playback. Durations are in seconds; none of them change fight timing, which comes
	-- from the server's event list.
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
	-- Forms (transformations). A form's own health pool (a rider's horse) is a bar above the health
	-- bar. Looks are keyed by form name: `label` floats up as a callout when the unit changes into
	-- the form during a fight (a dismount or remount is a big moment), and `mount` puts the unit on
	-- a placeholder horse of that color (FigureConfig.horse).
	formHealthColor = Color3.fromRGB(230, 160, 60),
	formChangeTextColor = Color3.fromRGB(255, 210, 120),
	-- `scale` draws the unit larger (a giant form) and `tint` recolors its body; both are placeholders
	-- for each form's art. Form names are shared across characters, so they must be unique.
	formLooks = table.freeze({
		Mounted = table.freeze({ label = "Remount!", mount = Color3.fromRGB(125, 85, 50) }),
		Dismounted = table.freeze({ label = "Dismounted!" }),
		Chainsaw = table.freeze({ label = "Chainsaw!", tint = Color3.fromRGB(190, 60, 50) }),
		["Pack Out"] = table.freeze({ label = "Pack out!" }),
		Bruiser = table.freeze({ label = "Bruiser!", tint = Color3.fromRGB(200, 90, 80) }),
		Human = table.freeze({ label = "Human" }),
		Titan = table.freeze({ label = "Titan!", scale = 1.35, tint = Color3.fromRGB(170, 110, 80) }),
		["Gear 2"] = table.freeze({ label = "Gear 2!" }),
		["Gear 3"] = table.freeze({ label = "Gear 3!", tint = Color3.fromRGB(255, 120, 120) }),
		["Core II"] = table.freeze({ label = "Core II!", scale = 1.1, tint = Color3.fromRGB(255, 225, 120) }),
		["Core III"] = table.freeze({ label = "Core III!", scale = 1.2, tint = Color3.fromRGB(255, 250, 200) }),
	}),
	-- Callouts (text over a unit) are kept for big moments: form changes, boss abilities and trait
	-- moments (a mark, a meter phase).
	bossCastTextColor = Color3.fromRGB(255, 120, 90),
	traitTextColor = Color3.fromRGB(150, 230, 255),

	-- Overhaul 1 placeholder visuals (docs/design/overhaul-1.md). Statuses float up as small labels
	-- when applied (debuff buffs and damage over time), keyed by Battle.Status.
	statusLabels = table.freeze({
		SLOW = "Slowed",
		WEAKEN = "Weakened",
		CURSE = "Hexed",
		BURN = "Burning",
		POISON = "Poisoned",
	}),
	statusTextColor = Color3.fromRGB(200, 170, 255),
	-- Trait moments: a hunter mark, and the shared meter's phase after each step (TraitCombat).
	markLabel = "Marked",
	meterLabels = table.freeze({ GUARD = "Guard", FURY = "Fury!", BOTH = "Guard + Fury!" }),
	vanishTransparency = 0.75, -- untargetable units (Vanish events)
	bounceColor = Color3.fromRGB(255, 240, 160), -- the projectile between bounce targets
	bounceFlightTime = 0.2,
	lineAreaColor = Color3.fromRGB(255, 170, 90), -- LINE and CONE area pulses
	-- Clones drawn around a caster while it casts (client only; they are not units): count and
	-- seconds, keyed by ability name (= character id).
	castClones = table.freeze({
		echo_legion = table.freeze({ count = 2, duration = 1.0 }),
	}),
	-- Basic attacks drawn with a different projectile (a long, thin "tongue"), by character id.
	tongueAttacks = table.freeze({ shade_pack = true }),
	tongueColor = Color3.fromRGB(230, 90, 120),
	-- PvE creep and boss bodies, names and sizes come from their theme's looks (PveThemeConfig); the
	-- top bar's round tracker colors come from UITheme.roundKinds.
	deathFadeDuration = 0.5,
	deathSinkDistance = 1.2,

	-- Floating numbers and callouts. Sizes are in pixels, so they stay readable on small screens.
	-- Numbers start beside the unit's body, rise and fade quickly.
	floatingTextFont = Enum.Font.GothamBlack,
	physicalDamageColor = Color3.fromRGB(255, 200, 120),
	magicDamageColor = Color3.fromRGB(200, 140, 255),
	trueDamageColor = Color3.fromRGB(255, 255, 255),
	critNumberColor = Color3.fromRGB(255, 235, 60),
	damageNumberSize = 14,
	critNumberSize = 17,
	dotNumberSize = 11, -- damage-over-time ticks
	calloutTextSize = 18,
	calloutDuration = 1.1,
	damageNumberDuration = 0.55,
	damageNumberRise = 26,
	-- Horizontal lanes (pixel offsets from the body) that successive numbers on one unit cycle
	-- through, alternating sides, plus up to `damageNumberJitter` pixels of random offset, so several
	-- hits on the same unit do not stack.
	damageNumberLanes = table.freeze({ 34, -34, 50, -50, 26, -26 }),
	damageNumberJitter = 6,
	maxFloatingTexts = 6, -- per unit; the oldest goes first

	-- Camera position relative to arenaCenter. It looks at arenaCenter.
	cameraOffset = Vector3.new(0, 46, 34),
})
