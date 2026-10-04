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

	ownCellColor = Color3.fromRGB(70, 95, 130),
	enemyCellColor = Color3.fromRGB(120, 75, 75),
	benchSlotColor = Color3.fromRGB(95, 95, 95),
	ownUnitColor = Color3.fromRGB(60, 140, 255),
	enemyUnitColor = Color3.fromRGB(235, 80, 80),
	healthBarColor = Color3.fromRGB(80, 220, 100),
	hitFlashColor = Color3.fromRGB(255, 255, 255),
	hitFlashDuration = 0.08, -- seconds

	-- Camera position relative to arenaCenter. It looks at arenaCenter.
	cameraOffset = Vector3.new(0, 46, 34),
})
