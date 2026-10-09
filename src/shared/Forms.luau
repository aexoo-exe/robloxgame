-- Forms (transformations): data rules for units that change form mid-fight. A unit type may list
-- its forms in order under `forms` in UnitConfig; it starts every fight in the first one. Units
-- without `forms` are untouched by everything here. docs/forms.md explains how to add forms.
--
-- A form:
--   name     string, unique within the unit (shown to players as-is for now)
--   stats    optional { [stat] = { flat = n?, percent = n? } }: changes while in this form, added
--            to the unit's buffs in Battle.stat. Stats: AD, AP, AttackSpeed, Armor, MR, MoveSpeed.
--   ability  optional ability (Abilities data) used instead of the unit's own while in this form
--   health   optional health pool of the form's own, before scaling (StarLevel.scaleHealth). While
--            the pool has health, damage goes to it instead of the unit's health (Battle.damage).
--   range    optional attack range (hexes) used instead of the unit's own while in this form
--   splash   optional { percent }: basic attacks also hit every enemy next to the target for this
--            percentage of the attack's damage (physical, after crits; CombatSim)
--   rules    optional overrides of FormConfig.rules for this form
--   trigger  optional { type, to?, healthPercent?, maxUses?, belowPercent?, unlockedBy? }: what
--            moves the unit on. `to` names the destination form (default: the next form in the
--            list), `healthPercent` sets the destination's pool on entry (default 100), `maxUses`
--            limits how often this trigger can fire per fight (default unlimited; 1 is a
--            once-per-fight change). HEALTH_BELOW needs `belowPercent`. With `unlockedBy` (a flag
--            name) the trigger fires only for units whose `flags` has that flag set for the fight
--            (bonds set them; see Bonds).
-- The look of a form (size, tint, callout text) is presentation only: RenderConfig.formLooks.
--
-- Form changes are decided by the combat simulation on the server (Battle.checkForm) and reach
-- clients as Form events in the fight's event list.
-- Pure Luau: no Roblox APIs, so it runs in Lune tests.

local FormConfig = if script then require(script.Parent.FormConfig) else require("./FormConfig")

local Forms = {}

-- Moments at which Battle asks the current form's trigger whether it fires.
Forms.Hook = table.freeze({
	Damaged = "Damaged", -- the unit just took a hit and survived it (after the hit's event)
	Takedown = "Takedown", -- the unit just landed the killing blow on an enemy board unit
	Cast = "Cast", -- the unit just finished applying its ability (Abilities.cast)
})

Forms.Trigger = table.freeze({
	FormHealthDepleted = "FORM_HEALTH_DEPLETED",
	Takedown = "TAKEDOWN",
	OnCast = "ON_CAST",
	HealthBelow = "HEALTH_BELOW",
})

-- Trigger types: the hook each one listens to, whether its form needs a health pool, and the
-- condition checked at that hook. A new trigger (a timer, say) is one entry here, plus a hook call
-- in Battle or CombatSim if it needs a new moment.
local TRIGGERS = {
	[Forms.Trigger.FormHealthDepleted] = {
		hook = Forms.Hook.Damaged,
		needsHealth = true,
		fires = function(unit): boolean
			return unit.formHealth ~= nil and unit.formHealth <= 0
		end,
	},
	[Forms.Trigger.Takedown] = {
		hook = Forms.Hook.Takedown,
		fires = function(_unit): boolean
			return true
		end,
	},
	-- Every cast in the form moves the unit on, so the next cast uses the next form's ability.
	[Forms.Trigger.OnCast] = {
		hook = Forms.Hook.Cast,
		fires = function(_unit): boolean
			return true
		end,
	},
	-- The unit's own health (not a form pool) fell below `belowPercent` of its max health.
	[Forms.Trigger.HealthBelow] = {
		hook = Forms.Hook.Damaged,
		fires = function(unit, trigger): boolean
			return unit.health * 100 < unit.maxHealth * trigger.belowPercent
		end,
	},
}

-- Stats a form may change. MaxHealth is left out on purpose: it would need refreshMaxHealth.
Forms.Stats = table.freeze({ AD = true, AP = true, AttackSpeed = true, Armor = true, MR = true, MoveSpeed = true })

-- A FormConfig rule for `form`: its own override if it has one, else the global default.
function Forms.rule(form, name: string): any
	if form and form.rules and form.rules[name] ~= nil then
		return form.rules[name]
	end
	return FormConfig.rules[name]
end

-- The flat and percent change `form` makes to `stat` (0, 0 without one).
function Forms.modifier(form, stat: string): (number, number)
	local change = form and form.stats and form.stats[stat]
	if not change then
		return 0, 0
	end
	return change.flat or 0, change.percent or 0
end

-- A stat field of `stats` (UnitConfig entry) with only `form`'s change applied, no buffs. The
-- client uses it for move speed, to animate movement at the right pace.
function Forms.baseStat(stats, form, stat: string, field: string): number
	local flat, percent = Forms.modifier(form, stat)
	return ((stats[field] or 0) + flat) * (1 + percent / 100)
end

-- True if `form`'s trigger fires for `unit` at `hook`. A trigger with `unlockedBy` fires only
-- while the unit has that flag.
function Forms.fires(form, unit, hook: string): boolean
	local trigger = form and form.trigger
	local kind = trigger and TRIGGERS[trigger.type]
	if kind == nil or kind.hook ~= hook then
		return false
	end
	if trigger.unlockedBy and not (unit.flags and unit.flags[trigger.unlockedBy]) then
		return false
	end
	return kind.fires(unit, trigger)
end

-- A unit's attack range in `form` (nil: no form): the form's own range, else the unit type's.
function Forms.range(stats, form): number
	return if form and form.range then form.range else stats.range
end

-- Index of the form a trigger moves to from form `index`, or nil if there is none.
function Forms.destination(forms, index: number, trigger): number?
	if trigger.to == nil then
		return if forms[index + 1] then index + 1 else nil
	end
	for i, form in forms do
		if form.name == trigger.to then
			return i
		end
	end
	return nil
end

-- The ability named `name` among a unit type's own ability and its forms' abilities, or nil.
function Forms.abilityNamed(stats, name: string?): any?
	if stats.ability and (name == nil or stats.ability.name == name) then
		return stats.ability
	end
	for _, form in stats.forms or {} do
		if form.ability and form.ability.name == name then
			return form.ability
		end
	end
	return nil
end

local function positive(value): boolean
	return type(value) == "number" and value > 0
end

-- Checks a unit type's `forms` list (nil is fine: no forms). Ability overrides are checked with
-- Abilities.validate separately. Returns true, or false and a reason.
function Forms.validate(forms): (boolean, string?)
	if forms == nil then
		return true
	end
	if type(forms) ~= "table" or #forms == 0 then
		return false, "forms must be a non-empty list"
	end
	local names = {}
	for index, form in forms do
		local where = "form " .. index
		if type(form.name) ~= "string" or form.name == "" then
			return false, where .. " needs a name"
		end
		if names[form.name] then
			return false, where .. ": duplicate name " .. form.name
		end
		names[form.name] = true
		where ..= " (" .. form.name .. ")"
		for stat, change in form.stats or {} do
			if not Forms.Stats[stat] then
				return false, where .. ": unknown stat " .. tostring(stat)
			end
			if type(change) ~= "table" or (change.flat == nil and change.percent == nil) then
				return false, where .. ": " .. stat .. " needs flat or percent"
			end
			local flatOk = change.flat == nil or type(change.flat) == "number"
			local percentOk = change.percent == nil or type(change.percent) == "number"
			if not flatOk or not percentOk then
				return false, where .. ": " .. stat .. " flat and percent must be numbers"
			end
		end
		if form.health ~= nil and not positive(form.health) then
			return false, where .. ": health must be a positive number"
		end
		if form.range ~= nil and (not positive(form.range) or form.range ~= math.floor(form.range)) then
			return false, where .. ": range must be a whole number of at least 1"
		end
		if form.splash ~= nil and (type(form.splash) ~= "table" or not positive(form.splash.percent)) then
			return false, where .. ": splash needs a positive percent"
		end
		if form.ability ~= nil and (type(form.ability) ~= "table" or type(form.ability.name) ~= "string") then
			return false, where .. ": ability must be ability data with a name"
		end
		for name in form.rules or {} do
			if FormConfig.rules[name] == nil then
				return false, where .. ": unknown rule " .. tostring(name)
			end
		end
	end
	for index, form in forms do
		local trigger = form.trigger
		if trigger ~= nil then
			local where = string.format("form %d (%s) trigger", index, form.name)
			local kind = TRIGGERS[trigger.type]
			if not kind then
				return false, where .. ": unknown type " .. tostring(trigger.type)
			end
			if kind.needsHealth and form.health == nil then
				return false, where .. ": " .. trigger.type .. " needs a form with health"
			end
			if trigger.to ~= nil and not names[trigger.to] then
				return false, where .. ": no form named " .. tostring(trigger.to)
			end
			local destination = Forms.destination(forms, index, trigger)
			if destination == nil then
				return false, where .. ": no form to move to"
			end
			if destination == index then
				return false, where .. ": moves to its own form"
			end
			if trigger.healthPercent ~= nil then
				if not positive(trigger.healthPercent) or trigger.healthPercent > 100 then
					return false, where .. ": healthPercent must be above 0 and at most 100"
				end
				if forms[destination].health == nil then
					return false, where .. ": healthPercent needs a destination form with health"
				end
			end
			if
				trigger.maxUses ~= nil
				and (not positive(trigger.maxUses) or trigger.maxUses ~= math.floor(trigger.maxUses))
			then
				return false, where .. ": maxUses must be a whole number of at least 1"
			end
			if trigger.type == Forms.Trigger.HealthBelow then
				if not positive(trigger.belowPercent) or trigger.belowPercent >= 100 then
					return false, where .. ": HEALTH_BELOW needs belowPercent above 0 and below 100"
				end
			elseif trigger.belowPercent ~= nil then
				return false, where .. ": belowPercent is only for HEALTH_BELOW"
			end
			if trigger.unlockedBy ~= nil and (type(trigger.unlockedBy) ~= "string" or trigger.unlockedBy == "") then
				return false, where .. ": unlockedBy must be a flag name"
			end
		end
	end
	return true
end

return Forms
