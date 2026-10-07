-- Plays back the fight the server simulated. CombatStarted carries the starting units and every
-- event with its tick; events are applied as server time passes `startsAt`. Presentation only:
-- nothing here changes what happens in the fight or when.
--
-- The event list is known in full when the fight starts, so attacks are anticipated: melee
-- attackers start their lunge early so it peaks as the hit lands, and ranged attackers launch a
-- projectile that arrives as the hit lands. Damage types and area centers come from CastReader,
-- since events do not carry them.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BoardConfig = require(Shared:WaitForChild("BoardConfig"))
local CombatConfig = require(Shared:WaitForChild("CombatConfig"))
local Forms = require(Shared:WaitForChild("Forms"))
local HexGrid = require(Shared:WaitForChild("HexGrid"))
local Phase = require(Shared:WaitForChild("Phase"))
local Pve = require(Shared:WaitForChild("Pve"))
local RemoteNames = require(Shared:WaitForChild("RemoteNames"))
local RenderConfig = require(Shared:WaitForChild("RenderConfig"))
local SkinConfig = require(Shared:WaitForChild("SkinConfig"))
local UnitConfig = require(Shared:WaitForChild("UnitConfig"))

-- What players see of a unit type: name, body color and size. Characters use their SkinConfig name
-- and their cost's color; creeps and bosses use their theme's look (PveThemeConfig).
local function lookOf(unitType: string): { name: string, color: Color3, scale: number }
	local character = UnitConfig[unitType]
	if character then
		return { name = SkinConfig[unitType].name, color = RenderConfig.costColors[character.cost], scale = 1 }
	end
	local look = Pve.pveUnitType(unitType).look
	return {
		name = look.name,
		color = Color3.fromRGB(look.color[1], look.color[2], look.color[3]),
		scale = look.scale or 1,
	}
end

-- Display name of an ability. Abilities are named by their character's internal id.
local function abilityName(abilityId: string): string
	local skin = SkinConfig[abilityId]
	return if skin then skin.ability else abilityId
end

local Arena = require(script.Parent.Arena)
local CastReader = require(script.Parent.CastReader)
local CombatEffects = require(script.Parent.CombatEffects)
local TraitIcon = require(script.Parent.TraitIcon)
local UnitView = require(script.Parent.UnitView)

local CombatPlayback = {}

-- One-shot effects (numbers, flashes, text) are skipped for events older than this, so a client
-- that joins mid-fight does not get a burst of everything that already happened.
local STALE_SECONDS = 0.5

local views: { [number]: UnitView.UnitView } = {} -- living units, by unit index
local dying: { [UnitView.UnitView]: boolean } = {} -- fading out; destroyed when the fade ends
local connection: RBXScriptConnection? = nil

local function clear()
	if connection then
		connection:Disconnect()
		connection = nil
	end
	for _, view in views do
		UnitView.destroy(view)
	end
	table.clear(views)
	for view in dying do
		UnitView.destroy(view)
	end
	table.clear(dying)
	CombatEffects.clear()
end

local function play(playback)
	clear()
	local result = playback.result

	-- Show the local player's side nearest the camera. Spectators see side 1's view.
	local localSide = if playback.sideUserIds[2] == Players.LocalPlayer.UserId then 2 else 1
	local function toWorld(column: number, row: number): Vector3
		if localSide == 2 then
			column, row = HexGrid.rotateHalfTurn(column, row, BoardConfig.columns, BoardConfig.rows * 2)
		end
		return Arena.cellPosition(column, row)
	end
	local function serverTimeOf(tick: number): number
		return playback.startsAt + tick / result.ticksPerSecond
	end

	-- A unit's form data by index (nil for units without forms).
	local function formOf(unitType: string, formIndex: number?)
		local forms = Pve.unitType(unitType).forms
		return if forms and formIndex then forms[formIndex] else nil
	end
	local function formLook(form)
		return if form then RenderConfig.formLooks[form.name] else nil
	end

	local unitsByIndex = {}
	for _, unit in result.units do
		unitsByIndex[unit.index] = unit
		local own = unit.side == localSide
		local form = formOf(unit.unitType, unit.formIndex)
		local look = lookOf(unit.unitType)
		views[unit.index] =
			UnitView.new(look.name, unit.starLevel, look.color, toWorld(unit.column, unit.row), Arena.folder, {
				sizeScale = look.scale,
				maxHealth = unit.maxHealth,
				mana = unit.mana,
				maxMana = unit.maxMana,
				-- Both sides start facing each other; the local side is nearest the camera (+Z).
				yaw = if own then 0 else math.pi,
				healthColor = if own then RenderConfig.healthBarColor else RenderConfig.enemyHealthBarColor,
				formHealth = unit.formHealth,
				maxFormHealth = unit.maxFormHealth,
				formLook = formLook(form),
				-- Creeps and bosses have no traits.
				traits = if UnitConfig[unit.unitType] then TraitIcon.traitsOf(UnitConfig[unit.unitType]) else nil,
			})
		views[unit.index].part:SetAttribute("UnitType", unit.unitType) -- for the hover tooltip
	end

	-- Side, range and move speed of every unit, summons included. Summons appear only in Summon
	-- events, so they are read up front: attack anticipation looks ahead of the applied events.
	-- Move speed includes the starting form's change and is updated as Form events apply.
	local info = {}
	for _, unit in result.units do
		local stats = Pve.unitType(unit.unitType)
		local form = formOf(unit.unitType, unit.formIndex)
		info[unit.index] = {
			side = unit.side,
			range = stats.range,
			moveSpeed = Forms.baseStat(stats, form, "MoveSpeed", "moveSpeed"),
		}
	end
	for _, event in result.events do
		if event.kind == "Summon" and info[event.unit] then
			info[event.summon] = {
				side = info[event.unit].side,
				range = event.range,
				moveSpeed = event.moveSpeed,
				summoner = event.unit,
			}
		end
	end

	local reading = CastReader.read(result.units, result.events, function(index, name)
		local unit = unitsByIndex[index]
		return if unit then Forms.abilityNamed(Pve.unitType(unit.unitType), name) else nil
	end)

	-- Pulses every field cell within the area's radius, spreading outward from its center.
	local function pulseArea(area: CastReader.Area, color: Color3?)
		local cells = {}
		for row = 1, BoardConfig.rows * 2 do
			for column = 1, BoardConfig.columns do
				local distance = HexGrid.distance(area.column, area.row, column, row)
				if distance <= area.radius then
					table.insert(cells, {
						position = toWorld(column, row),
						delay = distance * RenderConfig.areaWaveDelay,
					})
				end
			end
		end
		CombatEffects.areaPulse(cells, color)
	end

	-- Applies one CombatSim event (see the Event list in CombatSim) to the views. `fresh` is false
	-- for events that happened a while ago, which skip their one-shot effects.
	local function apply(index: number, event, fresh: boolean)
		local view = views[event.unit]
		local targetView = if event.target then views[event.target] else nil
		local kind = event.kind
		if kind == "Move" and view then
			local hexesPerSecond = CombatConfig.baseMoveSpeed * info[event.unit].moveSpeed
			UnitView.moveTo(view, toWorld(event.column, event.row), 1 / hexesPerSecond)
		elseif kind == "Dash" and view then
			UnitView.dashTo(view, toWorld(event.column, event.row))
		elseif kind == "Attack" or kind == "Damage" then
			if view and event.mana then
				UnitView.setMana(view, event.mana)
			end
			if view and targetView and kind == "Attack" then
				UnitView.face(view, targetView)
			end
			if targetView then
				UnitView.setHealth(targetView, event.health)
				UnitView.setShield(targetView, event.shield)
				UnitView.setMana(targetView, event.targetMana)
				if event.formHealth then
					UnitView.setFormHealth(targetView, event.formHealth)
				end
				if fresh and event.dot then
					UnitView.dotNumber(targetView, event.damage, event.damageType)
				elseif fresh then
					UnitView.flash(targetView, event.crit)
					UnitView.damageNumber(targetView, event.damage, reading.damageTypes[index], event.crit)
				end
			end
		elseif kind == "Cast" and view then
			UnitView.setMana(view, 0)
			if fresh then
				UnitView.cast(view, abilityName(event.ability))
				for _, area in reading.areas[index] or {} do
					pulseArea(area)
				end
			end
		elseif kind == "Heal" and targetView then
			UnitView.setHealth(targetView, event.health)
			if event.formHealth then
				UnitView.setFormHealth(targetView, event.formHealth)
			end
			if fresh then
				UnitView.healNumber(targetView, event.amount)
			end
		elseif kind == "Shield" and targetView then
			UnitView.setShield(targetView, event.shield)
			-- Combat-start shields from a trait name it (e.g. "Warden").
			if event.source and fresh then
				UnitView.popText(targetView, event.source, RenderConfig.shieldBubbleColor)
			end
		elseif kind == "ShieldEnd" and view then
			UnitView.setShield(view, 0)
		elseif kind == "Stun" and targetView then
			UnitView.stun(targetView, event.duration)
		elseif kind == "Buff" and targetView and fresh then
			local amount = if event.percent ~= 0 then event.percent .. "%" else tostring(event.flat)
			local stacks = if event.stacks and event.stacks > 1 then " x" .. event.stacks else ""
			UnitView.popText(targetView, "+" .. amount .. " " .. event.stat .. stacks, RenderConfig.castTextColor)
		elseif kind == "MaxHealth" and view then
			UnitView.setMaxHealth(view, event.maxHealth, event.health)
		elseif kind == "AreaStun" and fresh then
			pulseArea({ column = event.column, row = event.row, radius = event.radius }, RenderConfig.areaStunColor)
		elseif kind == "Summon" and view then
			local own = info[event.summon].side == localSide
			views[event.summon] =
				UnitView.new("summon", 1, view.color, toWorld(event.column, event.row), Arena.folder, {
					maxHealth = event.maxHealth,
					yaw = if own then 0 else math.pi,
					healthColor = if own then RenderConfig.healthBarColor else RenderConfig.enemyHealthBarColor,
					summon = true,
				})
		elseif kind == "Pull" and targetView then
			-- The pulled unit slides to its new cell, like a dash.
			UnitView.dashTo(targetView, toWorld(event.column, event.row))
		elseif kind == "Copy" and view and fresh then
			UnitView.popText(view, "Copy: " .. abilityName(event.ability), RenderConfig.castTextColor)
		elseif kind == "Form" and view then
			-- The server decided the form change; this only shows it.
			local unit = unitsByIndex[event.unit]
			local form = formOf(unit.unitType, event.formIndex)
			local look = formLook(form)
			UnitView.setForm(view, look, event.formHealth, event.maxFormHealth)
			UnitView.setHealth(view, event.health)
			info[event.unit].moveSpeed = Forms.baseStat(Pve.unitType(unit.unitType), form, "MoveSpeed", "moveSpeed")
			if event.cleansed then
				UnitView.stun(view, 0)
			end
			if fresh then
				UnitView.popText(view, if look then look.label else event.form, RenderConfig.formChangeTextColor)
			end
		elseif (kind == "Death" or kind == "SummonEnd") and view then
			-- Deaths and expiring summons fade out.
			UnitView.kill(view)
			views[event.unit] = nil
			dying[view] = true
		end
	end

	local function isRanged(unitIndex: number): boolean
		return info[unitIndex] ~= nil and info[unitIndex].range > 1
	end
	local function leadTime(unitIndex: number): number
		return if isRanged(unitIndex) then RenderConfig.projectileFlightTime else RenderConfig.lungeDuration / 2
	end

	-- Starts the wind-up of an attack that lands at `landsAt` (server time).
	local function anticipate(event, landsAt: number, serverNow: number)
		local attacker = views[event.unit]
		local target = views[event.target]
		if not attacker or not target then
			return
		end
		UnitView.face(attacker, target)
		local landsIn = landsAt - serverNow
		if isRanged(event.unit) then
			local own = info[event.unit].side == localSide
			local color = if own then RenderConfig.ownProjectileColor else RenderConfig.enemyProjectileColor
			CombatEffects.projectile(attacker, target, os.clock() + landsIn, color)
		else
			UnitView.lunge(attacker, target, os.clock() + landsIn - RenderConfig.lungeDuration / 2)
		end
	end

	local events = result.events
	local nextEvent = 1
	local nextAnticipated = 1
	local maxLead = math.max(RenderConfig.projectileFlightTime, RenderConfig.lungeDuration / 2)
	local upcoming = {} -- indexes of attacks inside the lead window, not yet wound up
	local lastFrame = os.clock()

	connection = RunService.RenderStepped:Connect(function()
		local now = os.clock()
		local dt = now - lastFrame
		lastFrame = now
		local serverNow = workspace:GetServerTimeNow()

		while nextAnticipated <= #events and serverTimeOf(events[nextAnticipated].tick) - maxLead <= serverNow do
			if events[nextAnticipated].kind == "Attack" then
				table.insert(upcoming, nextAnticipated)
			end
			nextAnticipated += 1
		end
		for i = #upcoming, 1, -1 do
			local event = events[upcoming[i]]
			local landsAt = serverTimeOf(event.tick)
			if serverNow >= landsAt - leadTime(event.unit) then
				table.remove(upcoming, i)
				if landsAt > serverNow then
					anticipate(event, landsAt, serverNow)
				end
			end
		end

		local currentTick = (serverNow - playback.startsAt) * result.ticksPerSecond
		while nextEvent <= #events and events[nextEvent].tick <= currentTick do
			local event = events[nextEvent]
			apply(nextEvent, event, serverNow - serverTimeOf(event.tick) < STALE_SECONDS)
			nextEvent += 1
		end

		-- Survivors keep animating (turning, fading numbers) until the views are cleared.
		for _, view in views do
			UnitView.update(view, now, dt)
		end
		for view in dying do
			if not UnitView.update(view, now, dt) then
				UnitView.destroy(view)
				dying[view] = nil
			end
		end
		CombatEffects.update(now)
	end)
end

function CombatPlayback.start()
	local matchState = ReplicatedStorage:WaitForChild("MatchState")
	local remotes = ReplicatedStorage:WaitForChild("Remotes")

	remotes:WaitForChild(RemoteNames.CombatStarted).OnClientEvent:Connect(play)

	-- Survivors stay on the field through Results; clear them when the next round's board appears.
	matchState:GetAttributeChangedSignal("Phase"):Connect(function()
		local phase = matchState:GetAttribute("Phase")
		if phase == Phase.Preparation or phase == Phase.Waiting then
			clear()
		end
	end)
end

return CombatPlayback
