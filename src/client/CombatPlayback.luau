-- Plays back the fight the server simulated. CombatStarted carries the starting units and every
-- event with its tick; events are applied as server time passes `startsAt`. Presentation only:
-- nothing here changes what happens in the fight or when.
--
-- Long fights play faster (fast-forward, CombatConfig.playbackSpeeds): the playback runs on a
-- fight-time clock, Playback.fightSeconds(server time since `startsAt`), which every unit view and
-- effect uses, so movement, animations, projectiles and numbers all follow the speed. The server
-- times the Combat phase with the same schedule. A badge shows the speed while it is above 1x.
--
-- The event list is known in full when the fight starts, so attacks and casts are anticipated:
-- each attack's motion (AnimationConfig.styles, timed to the unit's actual attack interval) starts
-- early so a melee strike lands as the hit lands and a ranged shot leaves so its projectile arrives
-- then, and a cast's wind-up starts before its Cast event so the release comes on it. CombatFx
-- shows each moment (motion, impacts, numbers, shake, hit-stop). Damage types and area centers
-- come from CastReader, since events do not carry them.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AnimationConfig = require(Shared:WaitForChild("AnimationConfig"))
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
local UltimateConfig = require(Shared:WaitForChild("UltimateConfig"))
local UnitConfig = require(Shared:WaitForChild("UnitConfig"))

-- Display name of an ability. Abilities are named by their character's internal id.
local function abilityName(abilityId: string): string
	local skin = SkinConfig[abilityId]
	return if skin then skin.ability else abilityId
end

local AbilityFx = require(script.Parent.AbilityFx)
local Arena = require(script.Parent.Arena)
local CameraCues = require(script.Parent.CameraCues)
local CastReader = require(script.Parent.CastReader)
local Cinematic = require(script.Parent.Cinematic)
local CharacterLook = require(script.Parent.CharacterLook)
local CombatEffects = require(script.Parent.CombatEffects)
local CombatFx = require(script.Parent.CombatFx)
local FastForwardBadge = require(script.Parent.FastForwardBadge)
local ImpactEffects = require(script.Parent.ImpactEffects)
local UltimateMoment = require(script.Parent.UltimateMoment)
local UnitMotion = require(script.Parent.UnitMotion)
local UnitView = require(script.Parent.UnitView)

local CombatPlayback = {}

-- One-shot effects (numbers, flashes, text) are skipped for events older than this (fight
-- seconds), so a client that joins mid-fight does not get a burst of everything that already
-- happened.
local STALE_SECONDS = 0.5

local views: { [number]: UnitView.UnitView } = {} -- living units, by unit index
local dying: { [UnitView.UnitView]: boolean } = {} -- fading out; destroyed when the fade ends
-- Cast clones (RenderConfig.castClones): client-only figures, not units, removed at `endsAt`.
local clones: { { view: UnitView.UnitView, endsAt: number } } = {}
local connection: RBXScriptConnection? = nil

local function clear()
	if connection then
		connection:Disconnect()
		connection = nil
	end
	FastForwardBadge.setSpeed(1)
	UltimateMoment.clear()
	CombatEffects.setClock(nil)
	ImpactEffects.setClock(nil)
	ImpactEffects.clear()
	CameraCues.setClock(nil)
	CameraCues.clear()
	Cinematic.clear()
	for _, view in views do
		UnitView.destroy(view)
	end
	table.clear(views)
	for view in dying do
		UnitView.destroy(view)
	end
	table.clear(dying)
	for _, clone in clones do
		UnitView.destroy(clone.view)
	end
	table.clear(clones)
	CombatEffects.clear()
end

-- Where a playback is drawn: by default the arena (CombatStarted); the dev preview passes its own
-- place (CombatPlayback.preview).
type Placement = {
	parent: Instance, -- the views' parent
	offset: Vector3, -- added to every arena cell position
	clock: (() -> number)?, -- fight time (default: from server time since `startsAt`)
}

local function play(playback, placement: Placement?)
	clear()
	local result = playback.result
	local parent: Instance = if placement then placement.parent else Arena.folder
	local shift = if placement then placement.offset else Vector3.zero

	-- Show the local player's side nearest the camera. Spectators see side 1's view.
	local localSide = if playback.sideUserIds[2] == Players.LocalPlayer.UserId then 2 else 1
	local function toWorld(column: number, row: number): Vector3
		if localSide == 2 then
			column, row = HexGrid.rotateHalfTurn(column, row, BoardConfig.columns, BoardConfig.rows * 2)
		end
		return Arena.cellPosition(column, row) + shift
	end
	-- Fight time: the moment of the fight on screen now, with fast-forward applied. Every view and
	-- effect of this fight runs on it. It is the server's fight time warped by ultimate moments
	-- (UltimateMoment: slowed around the local player's ultimate, then caught up); the warp is
	-- stepped once a frame, before anything reads it.
	local clock = if placement then placement.clock else nil
	local function serverFightNow(): number
		if clock then
			return clock()
		end
		return Playback.fightSeconds(workspace:GetServerTimeNow() - playback.startsAt)
	end
	local warp = UltimateMoment.newClock(serverFightNow)
	local function fightNow(): number
		return warp.now()
	end
	local function fightTimeOf(tick: number): number
		return tick / result.ticksPerSecond
	end
	local fightEnd = fightTimeOf(result.endTick)
	warp.setEnd(fightEnd)
	-- Moments only in real matches (and in dev previews when asked for: UltimateMoment.inPreview).
	local momentsHere = placement == nil or UltimateMoment.inPreview()
	CombatEffects.setClock(fightNow)
	ImpactEffects.setClock(fightNow)
	-- The fight on screen is the one the local player watches (one playback at a time): its
	-- ultimates may use camera cues.
	CameraCues.setClock(fightNow)
	CameraCues.setWatched(true)

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
			UnitView.new(look.name, unit.starLevel, look.color, toWorld(unit.column, unit.row), parent, {
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
				formName = if form then form.name else nil,
				starPips = character, -- creeps and bosses have no star level to show
				clock = fightNow,
				items = unit.items,
			})
		-- For the hover tooltip and the unit info panel.
		views[unit.index].part:SetAttribute("UnitType", unit.unitType)
		views[unit.index].part:SetAttribute("StarLevel", unit.starLevel)
		views[unit.index].part:SetAttribute("Items", table.concat(unit.items or {}, ","))
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
			range = Forms.range(stats, form),
			moveSpeed = Forms.baseStat(stats, form, "MoveSpeed", "moveSpeed"),
			unitType = unit.unitType,
			formName = if form then form.name else nil,
			look = CharacterLook.of(unit.unitType).figure,
			attacksPerSecond = stats.attacksPerSecond,
			-- The ability style: element and colors (AbilityFxConfig); `color` is its primary.
			style = AbilityFx.styleOf(unit.unitType, CombatFx.factionColor(unit.unitType)),
		}
		info[unit.index].color = info[unit.index].style.primary
	end
	for _, event in result.events do
		if event.kind == "Summon" and info[event.unit] then
			info[event.summon] = {
				side = info[event.unit].side,
				range = event.range,
				moveSpeed = event.moveSpeed,
				summoner = event.unit,
				look = CharacterLook.summon,
				color = info[event.unit].color,
				style = info[event.unit].style,
			}
		end
	end

	-- Timing for the motion (presentation only), read from the event list: each attack's interval to
	-- the unit's next attack (else its last one, else its attack rate), so its motion fits.
	local events = result.events
	local attackInterval: { [number]: number } = {}
	do
		local lastAttack: { [number]: number } = {}
		for i, event in events do
			if event.kind == "Attack" then
				local previous = lastAttack[event.unit]
				if previous then
					attackInterval[previous] = fightTimeOf(event.tick - events[previous].tick)
				end
				lastAttack[event.unit] = i
			end
		end
		local lastGap: { [number]: number } = {}
		for i, event in events do
			if event.kind == "Attack" then
				local gap = attackInterval[i]
				if gap then
					lastGap[event.unit] = gap
				else
					local rate = info[event.unit] and info[event.unit].attacksPerSecond
					attackInterval[i] = lastGap[event.unit] or (if rate and rate > 0 then 1 / rate else nil)
				end
			end
		end
	end

	-- The attack style of a unit now (its range can change with its form).
	local function styleOf(unitIndex: number): string
		local unit = info[unitIndex]
		if not unit then
			return AnimationConfig.defaultMelee
		end
		return UnitMotion.styleFor(unit.unitType, unit.range, unit.look, unit.formName)
	end
	local function colorOf(unitIndex: number): Color3
		return if info[unitIndex] then info[unitIndex].color else AnimationConfig.factionColors.summon
	end
	-- Fight time of each unit's last cast, and the last unit to hit each unit (its killer).
	local lastCastAt: { [number]: number } = {}
	local lastHitBy: { [number]: number } = {}
	local function castRecently(unitIndex: number, now: number): boolean
		local at = lastCastAt[unitIndex]
		return at ~= nil and now - at <= AnimationConfig.cast.targetWindow
	end

	-- Ability effects generated from each ability's events, in each unit's element (AbilityFx).
	local abilityFx = AbilityFx.newFight({
		views = views,
		toWorld = toWorld,
		styleOf = function(unitIndex: number)
			local unit = info[unitIndex]
			return if unit and unit.style
				then unit.style
				else AbilityFx.styleOf(nil, AnimationConfig.factionColors.summon)
		end,
		unitTypeOf = function(unitIndex: number)
			return if info[unitIndex] then info[unitIndex].unitType else nil
		end,
		summonerOf = function(unitIndex: number)
			return if info[unitIndex] then info[unitIndex].summoner else nil
		end,
		now = fightNow,
		ticksPerSecond = result.ticksPerSecond,
		events = events,
	})

	local reading = CastReader.read(result.units, result.events, function(index, name)
		local unit = unitsByIndex[index]
		return if unit then Forms.abilityNamed(Pve.unitType(unit.unitType), name) else nil
	end)

	-- Pulses every field cell of the area, spreading outward from its center: a circle's cells within
	-- its radius, or a line's or cone's listed cells (spreading from the caster's cell).
	local function pulseArea(area: CastReader.Area, color: Color3?, fromColumn: number?, fromRow: number?)
		local cells = {}
		if area.cells then
			local originColumn, originRow = fromColumn or area.column, fromRow or area.row
			for _, cell in area.cells do
				table.insert(cells, {
					position = toWorld(cell[1], cell[2]),
					delay = HexGrid.distance(originColumn, originRow, cell[1], cell[2]) * RenderConfig.areaWaveDelay,
				})
			end
			CombatEffects.areaPulse(cells, color or RenderConfig.lineAreaColor)
			return
		end
		for row = 1, BoardConfig.rows * 2 do
			for column = 1, BoardConfig.columns do
				local distance = HexGrid.distance(area.column, area.row, column, row)
				if distance <= (area.radius or 0) then
					table.insert(cells, {
						position = toWorld(column, row),
						delay = distance * RenderConfig.areaWaveDelay,
					})
				end
			end
		end
		CombatEffects.areaPulse(cells, color)
	end

	-- Client-only clones around a caster for the cast (RenderConfig.castClones).
	local function spawnClones(view, ability: string)
		local spec = RenderConfig.castClones[ability]
		if not spec then
			return
		end
		local ground = view.base - Vector3.new(0, view.part.Size.Y / 2, 0)
		for i = 1, spec.count do
			local angle = (i - 0.5) / spec.count * 2 * math.pi
			local offset = Vector3.new(math.cos(angle), 0, math.sin(angle)) * RenderConfig.hexRadius * 0.9
			local clone = UnitView.new("clone", 1, view.color, ground + offset, parent, {
				maxHealth = 1,
				yaw = view.yaw,
				summon = true,
				look = CharacterLook.summon,
				starPips = false,
				clock = fightNow,
			})
			clone.infoBoard.Enabled = false
			UnitView.cast(clone)
			table.insert(clones, { view = clone, endsAt = fightNow() + spec.duration })
		end
	end

	local function showStatus(view, status: string?)
		local label = if status then RenderConfig.statusLabels[status] else nil
		if view and label then
			UnitView.statusText(view, label, RenderConfig.statusTextColor)
		end
	end

	-- Applies one CombatSim event (see the Event list in CombatSim) to the views. `fresh` is false
	-- for events that happened a while ago, which skip their one-shot effects.
	local function apply(index: number, event, fresh: boolean)
		-- Ability effects first: they read where units are before the event moves them.
		abilityFx:event(index, event, fresh)
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
			-- A summon that feeds its summoner mana.
			local summoner = info[event.unit] and info[event.unit].summoner
			if event.summonerMana and summoner and views[summoner] then
				UnitView.setMana(views[summoner], event.summonerMana)
			end
			if view and targetView and kind == "Attack" then
				UnitView.face(view, targetView)
			end
			if targetView then
				local shieldBroken = targetView.shield > 0 and (event.shield or 0) <= 0
				UnitView.setHealth(targetView, event.health)
				UnitView.setShield(targetView, event.shield)
				UnitView.setMana(targetView, event.targetMana)
				if event.formHealth then
					UnitView.setFormHealth(targetView, event.formHealth)
				end
				if not event.dot and not event.aura then
					lastHitBy[event.target] = event.unit
				end
				if fresh and event.dot then
					CombatFx.dot(targetView, event.damage, event.damageType)
				elseif fresh then
					-- Every non-attack hit (not an item's or a form's splash) comes from an ability.
					local ability = kind == "Damage" and not event.item and not event.splash
					CombatFx.hit(targetView, view, {
						damage = event.damage,
						damageType = reading.damageTypes[index],
						crit = event.crit,
						ability = ability,
						abilityColor = if ability then colorOf(event.unit) else nil,
						execute = event.execute,
						shieldBroken = shieldBroken,
						slam = kind == "Attack" and UnitMotion.style(styleOf(event.unit)).slam == true,
					})
				end
			end
		elseif kind == "Cast" and view then
			UnitView.setMana(view, 0)
			lastCastAt[event.unit] = fightTimeOf(event.tick)
			if fresh then
				abilityFx:release(event.unit, view)
				if isBoss(event.unit) then
					UnitView.callout(view, abilityName(event.ability), RenderConfig.bossCastTextColor)
				end
				-- Areas the server described pulse with their Area events; only inferred ones here.
				for _, area in reading.areas[index] or {} do
					if area.inferred and not Cinematic.running(event.unit) then
						pulseArea(area, colorOf(event.unit))
					end
				end
				-- An ultimate that draws its own clones replaces the generic ones.
				local ultimate = Cinematic.running(event.unit)
				if not (ultimate and ultimate.def.ownClones) then
					spawnClones(view, event.ability)
				end
			end
		elseif kind == "FollowUp" and view and fresh then
			lastCastAt[event.unit] = fightTimeOf(event.tick)
			abilityFx:release(event.unit, view)
		elseif kind == "Area" and fresh and not Cinematic.running(event.unit) then
			-- In the caster's element color (AbilityFx draws the shape's own effect on top); an
			-- ultimate's recipe shows its own area, so no hex pulse under it.
			pulseArea(
				reading.areaEvents[index] or CastReader.areaOf(event),
				colorOf(event.unit),
				event.fromColumn,
				event.fromRow
			)
		elseif kind == "Bounce" and fresh and targetView and views[event.from] then
			local now = fightNow()
			CombatEffects.projectile(
				views[event.from],
				targetView,
				now + RenderConfig.bounceFlightTime,
				RenderConfig.bounceColor,
				{ look = "bounce" }
			)
		elseif kind == "Vanish" and view then
			UnitView.vanish(view, event.duration)
		elseif kind == "Immune" and view and fresh then
			UnitView.statusText(view, RenderConfig.immuneLabel, RenderConfig.statusTextColor)
		elseif kind == "Mana" and view then
			UnitView.setMana(view, event.mana)
		elseif kind == "Mark" and view and fresh then
			UnitView.callout(view, RenderConfig.markLabel, RenderConfig.traitTextColor)
		elseif kind == "Meter" and view and fresh then
			local label = RenderConfig.meterLabels[event.phase]
			if label then
				UnitView.callout(view, label, RenderConfig.traitTextColor)
			end
		elseif
			fresh
			and targetView
			and ((kind == "Buff" and event.status) or (kind == "Dot" and not event.refreshed))
		then
			-- Debuffs and new damage over time float their status label.
			showStatus(targetView, event.status)
			if kind == "Buff" and castRecently(event.unit, fightTimeOf(event.tick)) then
				CombatFx.abilityTouch(targetView, colorOf(event.unit))
			end
		elseif kind == "Buff" and fresh and targetView and not event.source then
			-- A buff from a cast touches its target in the caster's color.
			if castRecently(event.unit, fightTimeOf(event.tick)) then
				CombatFx.abilityTouch(targetView, colorOf(event.unit))
			end
		elseif kind == "Heal" and targetView then
			UnitView.setHealth(targetView, event.health)
			if event.formHealth then
				UnitView.setFormHealth(targetView, event.formHealth)
			end
			if fresh then
				CombatFx.heal(targetView, event.amount)
			end
		elseif kind == "Shield" and targetView then
			local grew = event.shield > targetView.shield
			UnitView.setShield(targetView, event.shield)
			if fresh and grew then
				CombatFx.shield(targetView)
			end
		elseif kind == "ShieldEnd" and view then
			UnitView.setShield(view, 0)
		elseif kind == "Stun" and targetView then
			CombatFx.stun(targetView, event.duration, fresh)
			if fresh and castRecently(event.unit, fightTimeOf(event.tick)) and event.unit ~= event.target then
				CombatFx.abilityTouch(targetView, colorOf(event.unit))
			end
		elseif kind == "MaxHealth" and view then
			UnitView.setMaxHealth(view, event.maxHealth, event.health)
		elseif kind == "AreaStun" and fresh and not Cinematic.running(event.unit) then
			-- The field in the caster's element color; each stunned unit shows the stun halo.
			pulseArea({ column = event.column, row = event.row, radius = event.radius }, colorOf(event.unit))
		elseif kind == "Summon" and view then
			local own = info[event.summon].side == localSide
			views[event.summon] = UnitView.new("summon", 1, view.color, toWorld(event.column, event.row), parent, {
				maxHealth = event.maxHealth,
				yaw = if own then 0 else math.pi,
				healthColor = if own then RenderConfig.healthBarColor else RenderConfig.enemyHealthBarColor,
				summon = true,
				look = CharacterLook.summon,
				starPips = false,
				clock = fightNow,
			})
		elseif (kind == "Pull" or kind == "Knockback") and targetView then
			-- The pulled or knocked-back unit slides to its new cell, like a dash.
			UnitView.dashTo(targetView, toWorld(event.column, event.row))
		elseif kind == "Form" and view then
			-- The server decided the form change; this only shows it.
			local unit = unitsByIndex[event.unit]
			local form = formOf(unit.unitType, event.formIndex)
			local look = formLook(form)
			UnitView.setForm(view, look, event.formHealth, event.maxFormHealth, if form then form.name else nil)
			UnitView.setHealth(view, event.health)
			local stats = Pve.unitType(unit.unitType)
			info[event.unit].moveSpeed = Forms.baseStat(stats, form, "MoveSpeed", "moveSpeed")
			info[event.unit].range = Forms.range(stats, form)
			info[event.unit].formName = if form then form.name else nil
			if event.cleansed then
				UnitView.stun(view, 0)
			end
			-- A form change mid-fight (a dismount, a remount) is a big moment: it gets a callout.
			if fresh then
				UnitView.callout(view, if look then look.label else event.form, RenderConfig.formChangeTextColor)
			end
		elseif (kind == "Death" or kind == "SummonEnd") and view then
			-- Deaths stagger, crumple and fade; expiring summons just fade.
			if kind == "Death" then
				local killer = lastHitBy[event.unit]
				CombatFx.death(view, if killer then views[killer] else nil)
			else
				UnitView.kill(view)
			end
			views[event.unit] = nil
			dying[view] = true
		end
	end

	-- The motion of the attack at event `index` (AnimationConfig.styles), timed to the attacker's
	-- interval to its next attack.
	local function planOf(index: number): CombatFx.Plan
		local event = events[index]
		local unit = info[event.unit]
		local ranged = unit ~= nil and unit.range > 1
		return CombatFx.plan(styleOf(event.unit), attackInterval[index], ranged)
	end

	-- Starts the motion of an attack that lands at fight time `landsAt`.
	local function anticipate(event, plan: CombatFx.Plan, landsAt: number, quiet: boolean?)
		local attacker = views[event.unit]
		local target = views[event.target]
		if not attacker or not target then
			return
		end
		local projectiles = AnimationConfig.projectiles
		local own = info[event.unit].side == localSide
		local tongue = RenderConfig.tongueAttacks[info[event.unit].unitType or ""] == true
		local color = if tongue
			then RenderConfig.tongueColor
			elseif own then projectiles.ownColor
			else projectiles.enemyColor
		CombatFx.attack(attacker, target, landsAt, plan, { color = color, tongue = tongue, noMotion = quiet })
	end

	-- When the wind-up of the cast at event `index` starts: its wind-up length before it
	-- (AbilityFx.windupLength: a signature's, else `cast.windup`).
	-- An ultimate's anticipation (AbilityFx.windupLength) is squeezed (to AbilityFx.minWindup at the
	-- least) so it starts after the unit's previous cast and a breath of room
	-- (UltimateConfig.afterPreviousCast); the cast itself is never moved.
	local previousCastAt: { [number]: number } = {}
	do
		local last: { [number]: number } = {}
		for i, event in events do
			if event.kind == "Cast" then
				previousCastAt[i] = last[event.unit]
				last[event.unit] = fightTimeOf(event.tick)
			end
		end
	end
	local function windupStartOf(index: number): number
		local unit = info[events[index].unit]
		local unitType = if unit then unit.unitType else nil
		local at = fightTimeOf(events[index].tick)
		local length = AbilityFx.windupLength(unitType)
		local previous = previousCastAt[index]
		if previous then
			local room = at - previous - UltimateConfig.afterPreviousCast
			length = math.clamp(room, AbilityFx.minWindup(unitType), length)
		end
		return at - length
	end

	-- An ultimate moment for the cast at event `index`, if it gets one (UltimateMoment: the local
	-- player's own unit, an ultimate that opts in, the limits): its anticipation then starts `rate x
	-- preroll` fight seconds before the cast (the warp plays that span at `rate`, so the caster's
	-- anticipation runs its full designed length in real time), never before the unit's previous
	-- cast and its room. Returns that start, or nil (no moment: the usual wind-up).
	local function momentStartOf(index: number): number?
		local event = events[index]
		local unit = info[event.unit]
		if not momentsHere or not unit or unit.side ~= localSide or unit.summoner then
			return nil
		end
		local unitType = unit.unitType
		if not Cinematic.has(unitType) or not UltimateMoment.optedIn(unitType) then
			return nil
		end
		local at = fightTimeOf(event.tick)
		local from = at - (Cinematic.preroll(unitType) or 0) * UltimateMoment.SETTINGS.rate
		local previous = previousCastAt[index]
		if previous then
			from = math.max(from, previous + UltimateConfig.afterPreviousCast)
		end
		local planned = warp.plan(from, at, function()
			local view = views[event.unit]
			return if view and view.part.Parent then view.part.Position else nil
		end)
		return if planned then from else nil
	end

	local nextEvent = 1
	local nextAnticipated = 1
	local maxLead = math.max(CombatFx.maxLead(), AbilityFx.maxWindup())
	-- Attacks and casts inside the lead window, not yet started: { index, startsAt, plan }.
	local upcoming: { { index: number, startsAt: number, plan: CombatFx.Plan?, quiet: boolean? } } = {}
	local cheered = false
	local lastFrame = fightNow()

	-- Every time below is fight time: lead windows, durations and the frame step all scale with
	-- the playback speed.
	connection = RunService.RenderStepped:Connect(function()
		warp.step() -- the warped fight time for this frame (ultimate moments)
		local now = fightNow()
		local dt = math.max(0, now - lastFrame)
		lastFrame = now
		FastForwardBadge.setSpeed(if now < fightEnd then Playback.speedAt(now) else 1)

		while nextAnticipated <= #events and fightTimeOf(events[nextAnticipated].tick) - maxLead <= now do
			local index = nextAnticipated
			local kind = events[index].kind
			if kind == "Attack" then
				local plan = planOf(index)
				local startsAt = fightTimeOf(events[index].tick) - CombatFx.leadTime(plan)
				table.insert(upcoming, { index = index, startsAt = startsAt, plan = plan })
			elseif kind == "Cast" then
				-- Mana fills from attacks, so a cast usually comes right after the unit's last attack:
				-- the wind-up takes over the motion of that unit's attacks that would overlap it (they
				-- still land, with their numbers and projectiles).
				local startsAt = momentStartOf(index) or windupStartOf(index)
				local caster = events[index].unit
				for _, entry in upcoming do
					local other = events[entry.index]
					if entry.plan and other.unit == caster and fightTimeOf(other.tick) > startsAt then
						entry.quiet = true
					end
				end
				table.insert(upcoming, { index = index, startsAt = startsAt })
			end
			nextAnticipated += 1
		end
		for i = #upcoming, 1, -1 do
			local entry = upcoming[i]
			if now >= entry.startsAt then
				table.remove(upcoming, i)
				local event = events[entry.index]
				local at = fightTimeOf(event.tick)
				if at > now and entry.plan then
					anticipate(event, entry.plan, at, entry.quiet)
				elseif at > now and views[event.unit] then
					abilityFx:windup(event.unit, views[event.unit], entry.startsAt, at, entry.index)
				end
			end
		end

		local currentTick = now * result.ticksPerSecond
		while nextEvent <= #events and events[nextEvent].tick <= currentTick do
			local event = events[nextEvent]
			apply(nextEvent, event, now - fightTimeOf(event.tick) < STALE_SECONDS)
			nextEvent += 1
		end

		-- The fight is over: the winning side's survivors cheer (not on a draw).
		if not cheered and now >= fightEnd then
			cheered = true
			if result.winner and now - fightEnd < STALE_SECONDS then
				local winners = {}
				for unitIndex, view in views do
					if info[unitIndex] and info[unitIndex].side == result.winner then
						table.insert(winners, view)
					end
				end
				CombatFx.victory(winners, fightEnd + AnimationConfig.victory.delay)
			end
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
		for i = #clones, 1, -1 do
			local clone = clones[i]
			if now >= clone.endsAt then
				UnitView.destroy(clone.view)
				table.remove(clones, i)
			else
				UnitView.update(clone.view, now, dt)
			end
		end
		CombatEffects.update(now)
	end)
end

-- Dev preview (DevLineup): plays a fight `result` (CombatSim) the way a real fight plays, drawn at
-- arena cell positions shifted by `offset` under `parent`, from fight time `from` on (earlier
-- events apply without their one-shot effects, as for a client joining mid-fight). Side 1 is
-- nearest the camera. `clock` (optional) gives the fight time instead of server time (the
-- preview's slow motion and freeze). It replaces any playback in progress; CombatPlayback.stop
-- ends it.
function CombatPlayback.preview(result, parent: Instance, offset: Vector3, from: number, clock: (() -> number)?)
	play({
		result = result,
		startsAt = workspace:GetServerTimeNow() - Playback.realSeconds(from),
		sideUserIds = { Players.LocalPlayer.UserId },
	}, { parent = parent, offset = offset, clock = clock })
end

-- Ends any playback and removes its views and effects.
function CombatPlayback.stop()
	clear()
end

function CombatPlayback.start()
	local matchState = ReplicatedStorage:WaitForChild("MatchState")
	local remotes = ReplicatedStorage:WaitForChild("Remotes")

	remotes:WaitForChild(RemoteNames.CombatStarted).OnClientEvent:Connect(play)

	-- Survivors stay on the field through Results; clear them when the next round's board appears.
	matchState:GetAttributeChangedSignal("Phase"):Connect(function()
		local phase = matchState:GetAttribute("Phase")
		if phase == Phase.Preparation or phase == Phase.Waiting or phase == Phase.Intro then
			clear()
		end
	end)
end

return CombatPlayback
