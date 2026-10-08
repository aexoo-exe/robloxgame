-- Plays back the fight the server simulated. CombatStarted carries the starting units and every
-- event with its tick; events are applied as server time passes `startsAt`. Presentation only:
-- nothing here changes what happens in the fight or when.
--
-- Long fights play faster (fast-forward, CombatConfig.playbackSpeeds): the playback runs on a
-- fight-time clock, Playback.fightSeconds(server time since `startsAt`), which every unit view and
-- effect uses, so movement, animations, projectiles and numbers all follow the speed. The server
-- times the Combat phase with the same schedule. A badge shows the speed while it is above 1x.
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
local Playback = require(Shared:WaitForChild("Playback"))
local Pve = require(Shared:WaitForChild("Pve"))
local RemoteNames = require(Shared:WaitForChild("RemoteNames"))
local RenderConfig = require(Shared:WaitForChild("RenderConfig"))
local SkinConfig = require(Shared:WaitForChild("SkinConfig"))
local UnitConfig = require(Shared:WaitForChild("UnitConfig"))

-- Display name of an ability. Abilities are named by their character's internal id.
local function abilityName(abilityId: string): string
	local skin = SkinConfig[abilityId]
	return if skin then skin.ability else abilityId
end

local Arena = require(script.Parent.Arena)
local CastReader = require(script.Parent.CastReader)
local CharacterLook = require(script.Parent.CharacterLook)
local CombatEffects = require(script.Parent.CombatEffects)
local FastForwardBadge = require(script.Parent.FastForwardBadge)
local UnitView = require(script.Parent.UnitView)

local CombatPlayback = {}

-- One-shot effects (numbers, flashes, text) are skipped for events older than this (fight
-- seconds), so a client that joins mid-fight does not get a burst of everything that already
-- happened.
local STALE_SECONDS = 0.5

local views: { [number]: UnitView.UnitView } = {} -- living units, by unit index
local dying: { [UnitView.UnitView]: boolean } = {} -- fading out; destroyed when the fade ends
local connection: RBXScriptConnection? = nil

local function clear()
	if connection then
		connection:Disconnect()
		connection = nil
	end
	FastForwardBadge.setSpeed(1)
	CombatEffects.setClock(nil)
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
	-- Fight time: the moment of the fight on screen now, with fast-forward applied. Every view and
	-- effect of this fight runs on it.
	local function fightNow(): number
		return Playback.fightSeconds(workspace:GetServerTimeNow() - playback.startsAt)
	end
	local function fightTimeOf(tick: number): number
		return tick / result.ticksPerSecond
	end
	local fightEnd = fightTimeOf(result.endTick)
	CombatEffects.setClock(fightNow)

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
		local look = CharacterLook.of(unit.unitType)
		local character = UnitConfig[unit.unitType] ~= nil
		views[unit.index] =
			UnitView.new(look.name, unit.starLevel, look.color, toWorld(unit.column, unit.row), Arena.folder, {
				sizeScale = look.scale,
				look = look.figure,
				maxHealth = unit.maxHealth,
				mana = unit.mana,
				maxMana = unit.maxMana,
				-- Both sides start facing each other; the local side is nearest the camera (+Z).
				yaw = if own then 0 else math.pi,
				healthColor = if own then RenderConfig.healthBarColor else RenderConfig.enemyHealthBarColor,
				formHealth = unit.formHealth,
				maxFormHealth = unit.maxFormHealth,
				formLook = formLook(form),
				starPips = character, -- creeps and bosses have no star level to show
				clock = fightNow,
			})
		-- For the hover tooltip and the unit info panel.
		views[unit.index].part:SetAttribute("UnitType", unit.unitType)
		views[unit.index].part:SetAttribute("StarLevel", unit.starLevel)
	end

	-- Boss abilities get a callout; ordinary casts only glow.
	local function isBoss(unitIndex: number): boolean
		local unit = unitsByIndex[unitIndex]
		local pve = if unit then Pve.pveUnitType(unit.unitType) else nil
		return pve ~= nil and pve.kind == "boss"
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
				UnitView.cast(view)
				if isBoss(event.unit) then
					UnitView.callout(view, abilityName(event.ability), RenderConfig.bossCastTextColor)
				end
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
		elseif kind == "ShieldEnd" and view then
			UnitView.setShield(view, 0)
		elseif kind == "Stun" and targetView then
			UnitView.stun(targetView, event.duration)
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
					look = CharacterLook.summon,
					starPips = false,
					clock = fightNow,
				})
		elseif kind == "Pull" and targetView then
			-- The pulled unit slides to its new cell, like a dash.
			UnitView.dashTo(targetView, toWorld(event.column, event.row))
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
			-- A form change mid-fight (a dismount, a remount) is a big moment: it gets a callout.
			if fresh then
				UnitView.callout(view, if look then look.label else event.form, RenderConfig.formChangeTextColor)
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

	-- Starts the wind-up of an attack that lands at fight time `landsAt`.
	local function anticipate(event, landsAt: number, now: number)
		local attacker = views[event.unit]
		local target = views[event.target]
		if not attacker or not target then
			return
		end
		UnitView.face(attacker, target)
		local landsIn = landsAt - now
		if isRanged(event.unit) then
			local own = info[event.unit].side == localSide
			local color = if own then RenderConfig.ownProjectileColor else RenderConfig.enemyProjectileColor
			CombatEffects.projectile(attacker, target, now + landsIn, color)
			UnitView.shoot(attacker, target)
		else
			UnitView.lunge(attacker, target, now + landsIn - RenderConfig.lungeDuration / 2)
		end
	end

	local events = result.events
	local nextEvent = 1
	local nextAnticipated = 1
	local maxLead = math.max(RenderConfig.projectileFlightTime, RenderConfig.lungeDuration / 2)
	local upcoming = {} -- indexes of attacks inside the lead window, not yet wound up
	local lastFrame = fightNow()

	-- Every time below is fight time: lead windows, durations and the frame step all scale with
	-- the playback speed.
	connection = RunService.RenderStepped:Connect(function()
		local now = fightNow()
		local dt = math.max(0, now - lastFrame)
		lastFrame = now
		FastForwardBadge.setSpeed(if now < fightEnd then Playback.speedAt(now) else 1)

		while nextAnticipated <= #events and fightTimeOf(events[nextAnticipated].tick) - maxLead <= now do
			if events[nextAnticipated].kind == "Attack" then
				table.insert(upcoming, nextAnticipated)
			end
			nextAnticipated += 1
		end
		for i = #upcoming, 1, -1 do
			local event = events[upcoming[i]]
			local landsAt = fightTimeOf(event.tick)
			if now >= landsAt - leadTime(event.unit) then
				table.remove(upcoming, i)
				if landsAt > now then
					anticipate(event, landsAt, now)
				end
			end
		end

		local currentTick = now * result.ticksPerSecond
		while nextEvent <= #events and events[nextEvent].tick <= currentTick do
			local event = events[nextEvent]
			apply(nextEvent, event, now - fightTimeOf(event.tick) < STALE_SECONDS)
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
